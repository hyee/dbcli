/*
 * Paint.cpp -- rc_plan_paint: the operation list one flush needs, with no console in sight.
 *
 * Read Paint.h first; it states why this is a separate module. The rules, in the order they apply:
 *
 *  1. Model row r is buffer row row0 + r, where row0 is the *model's own* anchor plus whatever this flush
 *     slid the window (rule 3) -- not the window top the user may have moved. pendingScrolls is the only
 *     thing that can break that mapping otherwise, and it is repaired by moving the window (free: the cells
 *     stay where they are) or the buffer (one call), never by repainting: sliding the window down by k
 *     shifts every content row k rows *up* in the model and k rows *down* in row0, so each row keeps its
 *     physical buffer row. That is why a scroll costs no cell writes, and why the gutter exists -- the rows
 *     the viewport pushes out of its top are still waiting to be painted into the scrollback above the
 *     window.
 *     1b. A buffer scroll moves the rows the *anchor* claims, which is the band as it stood before this plan
 *     slid anything: `[base + slide + by, base + rows - 1]` up by `by`, landing on `[row0, ...]` (`by` = the
 *     part of the debt the slide could not pay). It is not the new band `[row0, row0 + rows - 1]` shifted up,
 *     and the difference is damage: that one drags the top `by` rows of the claim above the claim, into the
 *     scrollback the user is reading, and leaves the bottom `by` rows of the claim holding cells the model
 *     believes are `by` rows higher. Once the claim this flush *leaves behind* sits on the buffer's last row
 *     (`row0 + rows >= bufH`) there is no band left to move inside, and the scroll becomes an eviction -- the
 *     whole buffer rides up and the oldest lines fall off its top, which is the terminal's contract rather than
 *     this renderer's option (rc_scroll_band). A slide never escapes that: sliding is how the claim gets to the
 *     last row, and it moves no cells.
 *  2. The anchor is the model's, the view is the user's. A slide is only offered while the window sits on
 *     the rows the model claims; a view the user moved over scrollback is left where they put it, the
 *     scroll is paid with the buffer, and the cursor is not parked outside it.
 *  3. A window slide is requested by parking the cursor on the row that must become the window's
 *     bottom. conhost slides down to include a cursor it is told about and never slides up, which is
 *     exactly what the ANSI leg does with the same newline, so the two legs agree on the view.
 *  4. A model row *is* a buffer row (Render.h, `cols`), so the columns right of the window are not a tail
 *     the painter appends but cells the model holds -- the same cells ConEmu's EL erases to dwSize.X
 *     fills, and the reason a 200-column line printed in an 80-column terminal is one line rather than
 *     three. That is what the model stores, and it is not a per-frame cost: what conhost is *told about*
 *     is the run's own column range (Render.h, `dirtyLo`/`dirtyHi`), so redrawing one character of a
 *     status line moves one cell and not a 2000-column row. Storing wide is I7; painting narrow is
 *     damage tracking. Nothing here may read "we only paint what changed" as "we only keep what changed".
 *
 * One fidelity shortcut, stated so it does not read as an oversight: rows the console scrolled get
 * filled with the model's *current* attribute, the same value ScrollConsoleScreenBuffer is handed.
 * ConEmu makes the same choice per line (ExtWriteText scrolls with whatever gDisplayParm says then),
 * so a chunk that changes colour *between* two scrolls can differ in the attribute of one scrolled-in
 * row -- and nothing else, because those rows are painted again below as dirty rows.
 */

#include "Paint.h"

#include <string.h>

/* The console value behind a DECSCUSR parameter. ConEmu answers the same way (Ansi.cpp:3677:
 * `ci.dwSize = (nStyle == 1 || nStyle == 2) ? 100 : 15`), because a console reachable from Win7 has two
 * cursor shapes at all — block and a short underline — and SetConsoleCursorShape, which would give the
 * bar, is Windows 10 18297. Parameter 0 is ConEmu's "default" and lands on the thin side there too, which
 * is why this maps 0 like 3..6; the "nobody asked" case is -1 and has no height at all, so a session that
 * never sent `CSI q` leaves the user's own cursor height alone. */
static int cursor_height(int style)
{
  if (style < 0) return 0;
  return (style == 1 || style == 2) ? 100 : 15;
}

void rc_plan_paint(const RcGrid *g, const RcView *v, RcPlan *p)
{
  memset(p, 0, sizeof(*p));
  p->reason = RC_PLAN_OK;
  p->slideTo = -1;
  p->attr = g->attr;
  p->cursorVisible = g->cursorVisible;
  p->shapeHeight = cursor_height(g->cursorShape);
  p->setShape = (g->cursorShape >= 0 && p->shapeHeight > 0 && v && v->curHeight > 0 &&
                 v->curHeight != p->shapeHeight) ? 1 : 0;
  p->curX = g->cx;
  p->curY = g->cy;

  /* 1. Does the model still describe this console? The model row is a whole buffer row measured from
     the window's left edge, because that is where conhost wraps, so the width to compare is
     `bufW - winL` and NOT the window's own width -- a window dragged narrower keeps the same rows and
     needs nothing. A resize in height, or a view the user moved sideways, is not something a plan can
     fix: the caller has to re-read the grid. The gutter above the viewport is the model's own business
     and is not part of the comparison. */
  if (!g || !v || v->bufW <= 0 || v->bufH <= 0 || g->cols <= 0 || g->winRows <= 0)
  {
    p->reason = RC_PLAN_NOGEOM;
    return;
  }
  p->paintCols = v->bufW - v->winL;
  if (p->paintCols != g->cols || v->winB - v->winT + 1 != g->winRows)
  {
    p->paintCols = 0;
    p->reason = RC_PLAN_NOGEOM;
    return;
  }

  /* 2. Where the model's rows are, and whether the view is still on them.
     `baseRow` is the model's own claim on the buffer -- conhost's `_virtualBottom` in row-0 form, ghostty's
     `.active` pin -- and the rule this restates is that *the window is evidence about the view, not about
     the content*. A user who scrolls up has moved srWindow and no cell at all; deriving rows from it then
     writes the current frame over the history they were reading (the measured case: view at row 0, content
     at row 30, one prompt line rewrote row 29 and blanked row 30). A model that has never painted has no
     claim to keep, so the window is the only answer it can be given. And a claim that has fallen *behind*
     the view is advanced to it, never pulled back: screenInfo.cpp:714-717. */
  const int hist = g->rows - g->winRows;
  const int viewBase = v->winT - hist;              /* where the window says model row 0 is */
  int base = viewBase;
  if (g->baseSet && g->baseRow > base) base = g->baseRow;
  const int ours = (v->winT == base + hist);

  /* 3. Spend the scroll: rows the window can still travel down are free, the rest are the buffer's.
     While the view is not ours, none are: sliding would drag it across the buffer to follow output, and
     neither terminal does that -- ghostty's `scroll-to-bottom` is `{ keystroke = true, output = false }`
     (Config.zig:10446) and conhost only snaps for output the user has not walked away from
     (screenInfo.cpp:1715-1726). The scroll is then paid with the buffer, which moves cells under a window
     that stays where the user put it, exactly as conhost's own scroll does. */
  const int k = g->pendingScrolls;
  int free_slide = ours ? (v->bufH - g->winRows - v->winT) : 0;
  if (free_slide < 0) free_slide = 0;
  int slide = (k < free_slide) ? k : free_slide;
  if (slide > 0) p->slideTo = v->winT + slide + g->winRows - 1;
  p->slideRows = slide;
  p->bufScroll = k - slide;
  p->scrollAttr = g->attr;

  /* A slide moves the base with the window; a buffer scroll leaves it alone and moves the cells under it,
     which is the same thing seen from the other side: content rode up `k` rows in the model, so the model's
     rows keep their buffer rows either way. The window ends up on the base plus the gutter -- unless the
     view was somebody else's, in which case it stays on the row the user scrolled to. */
  p->row0 = base + slide;
  p->winTop = ours ? (v->winT + slide) : v->winT;

  /* Rows past the buffer's last one are not a thing a plan can paint: the anchor and the view disagree by
     more than the buffer holds, which only a shrink from under the model can do. Declining is honest and
     self-healing -- the caller re-adopts, and an adopt recomputes the anchor from the window it just read. */
  if (p->row0 + g->rows > v->bufH)
  {
    p->paintCols = 0;
    p->slideTo = -1;
    p->bufScroll = p->slideRows = 0;
    p->row0 = p->winTop = 0;
    p->reason = RC_PLAN_NOGEOM;
    return;
  }

  /* Negative row0 is not an error: the viewport rows it still addresses are the ones the plan paints.
     A gutter row with no buffer row under it is scrollback this console cannot keep -- a window at the
     top of the buffer, or a buffer shorter than the model -- and it is counted, never hidden. */
  const int skip = (p->row0 < 0) ? -p->row0 : 0;

  /* 4. Damage: contiguous dirty rows become one rectangle each, as wide as their union of columns. */
  int first = -1, last = -1, capped = 0;
  int bandLo = 0, bandHi = -1;              /* union over every damaged row, for the capped band */
  for (int r = skip; r < g->rows; r++)
  {
    if (!rc_row_dirty(g, r)) continue;
    const int lo = RC_LO(g, r), hi = RC_HI(g, r);
    if (first < 0) { first = r; bandLo = lo; }
    if (hi > bandHi) bandHi = hi;
    if (lo < bandLo) bandLo = lo;
    last = r;
    if (capped) continue;
    if (p->nRuns && p->run[p->nRuns - 1].top + p->run[p->nRuns - 1].nrows == r)
    {
      /* merging into the run above widens it rather than adding a call: one rectangle covering both
         rows' columns is cheaper than two calls and cannot miss damage. */
      RcRun *prev = &p->run[p->nRuns - 1];
      if (lo < prev->lo) prev->lo = lo;
      if (hi > prev->hi) prev->hi = hi;
      prev->nrows++;
    }
    else if (p->nRuns < RC_PLAN_MAX_RUNS)
    {
      p->run[p->nRuns].top = r;
      p->run[p->nRuns].nrows = 1;
      p->run[p->nRuns].lo = lo;
      p->run[p->nRuns].hi = hi;
      p->nRuns++;
    }
    else
    {
      /* more separate runs than the plan can name: the whole band from the first damaged row to the
         last goes as one rectangle. Over-painting clean rows is waste; dropping them is a bug. */
      capped = 1;
      p->nRuns = 0;
    }
  }
  if (capped)
  {
    p->run[0].top = first;
    p->run[0].nrows = last - first + 1;
    p->run[0].lo = bandLo;
    p->run[0].hi = bandHi;
    p->nRuns = 1;
  }

  for (int r = 0; r < skip && r < g->rows; r++) if (rc_row_dirty(g, r)) p->drop++;
  if (first < 0) p->reason = RC_PLAN_EMPTY;

  for (int i = 0; i < p->nRuns; i++)
    p->cells += (unsigned long)p->run[i].nrows * (unsigned long)(p->run[i].hi - p->run[i].lo + 1);
  p->attrChanged = (v->attr != g->attr) ? 1 : 0;
  p->setVisible = (v->cursorOn >= 0 && v->cursorOn != g->cursorVisible) ? 1 : 0;

  /* A slide or a buffer scroll shifts what the cursor's old row *means*, so the cursor goes back on
     the model's word even when the coordinates did not change. The column, though, is held back: conhost
     slides the viewport right to include a cursor it is told about, exactly as it slides down (measured
     2026-09-23: parking at column 105 of a 100-column window moved srWindow to 6..105, at column 300 of a
     120-column window to 181..300), and a printer must not drag the user's view sideways just because its
     line was wider than the window -- which is the normal case for a wide buffer. So the parked column is
     clamped into the window while the model keeps the true one, and align() adopts whatever column the
     console really has. Vertically there is no clamp: the slide *is* rule 3. */
  p->curTX = v->winL + g->cx;
  if (p->curTX > v->winR) p->curTX = v->winR;
  p->curTY = p->row0 + g->cy;
  p->cursorMoved = (p->curTX != v->curX || p->curTY != v->curY || p->bufScroll > 0) ? 1 : 0;

  /* ...and a cursor whose row the plan cannot put inside the window is not parked at all. The test is
     against the window as the plan leaves it, which for a slide is one the model chose: parking below it is
     how rule 3 moves the view, and rows above it the buffer has never held. conhost's SnapOnOutput refuses
     the same transaction for the same reason ("We only want to snap if the user didn't intentionally scroll
     away", screenInfo.cpp:1715-1726) and MakeCursorVisible slides by the least displacement it can
     (1684-1705); ghostty's output leg does not touch the view at all in its default configuration
     (Config.zig:10446). `cursorOffView` says so instead of hiding it -- and it also covers the row a
     too-short buffer dropped above itself, where there is nowhere to park. */
  if (p->curTY < p->winTop || p->curTY > p->winTop + g->winRows - 1)
  {
    p->cursorOffView = 1;
    p->cursorMoved = 0;
  }
}

void rc_paint_done(RcGrid *g)
{
  g->pendingScrolls = 0;
  rc_clear_dirty(g);
}

/* The view a keystroke is entitled to ask for. No console call and no mutation of the model: like every
 * other row decision in this file, it is arithmetic on the claim and the window, so RenderCheck can pin the
 * cases the live console would only demonstrate by damaging something. */
int rc_snap_view(const RcGrid *g, const RcView *v, int *row, int *col)
{
  if (row) *row = -1;
  if (col) *col = -1;
  if (!g || !v || g->cols <= 0 || g->winRows <= 0) return RC_SNAP_NOGEOM;
  if (v->bufW <= 0 || v->bufH < v->winT) return RC_SNAP_NOGEOM;
  /* Rule 1's test, same as the plan's: the model addresses whole buffer rows, and a console whose row width
     or window height disagrees has nothing for these numbers to mean. */
  if (v->bufW - v->winL != g->cols || v->winB - v->winT + 1 != g->winRows) return RC_SNAP_NOGEOM;
  if (!g->baseSet) return RC_SNAP_NOCHANGE;   /* a model that never painted has no rows to be shown */
  if (!g->cursorVisible) return RC_SNAP_NOCHANGE;   /* conhost's guard, and the same reason */
  const int want = g->baseRow + g->cy;
  if (want < 0 || want > v->bufH - 1) return RC_SNAP_NOCHANGE;
  if (want >= v->winT && want <= v->winB) return RC_SNAP_NOCHANGE;
  *row = want;
  const int maxc = v->winR - v->winL;
  *col = v->winL + (g->cx > maxc ? maxc : (g->cx < 0 ? 0 : g->cx));
  return RC_SNAP_PARK;
}

/* Rule 2 seen from the other end: an adopt has to know which rows to read, and after a resize the honest
 * answer is not always "the window's". A rebuild throws the grid away and with it the anchor, so the carry
 * is arithmetic on the claim the *old* grid had -- and conhost's rule for exactly that moment is worth
 * taking whole (screenInfo.cpp:1103-1115): "in general we want to avoid moving the virtual bottom unless
 * it's aligned with the visible viewport", updated only when the viewport's bottom sweeps across it on the
 * way to its new size, or when keeping it would push the virtual viewport above the buffer's top.
 *
 * The reason is the same reason the paint has it: a resize moves the window, not the cells. Drag the
 * window shorter while the user is scrolled up and their history is still under their eyes, while the
 * application's own rows are further down the buffer -- where an anchor that survived the resize keeps
 * addressing them. An anchor pulled to the window instead would put the next prompt line on top of the
 * text the user was reading, which is the damage rule 2 exists to prevent, arriving through a different
 * door. The bottom is what is carried rather than the top because a rebuilt grid has a different height,
 * and the row the content ends on is the one that means the same thing in both.
 *
 * The sweep test is a resize's, not every adopt's, which is why it is behind a flag. conhost keeps the two
 * moments in different functions: the straddle rule above lives in `_InternalSetViewportSize`
 * (screenInfo.cpp:953, the check at 1110-1112, reached from `SetViewportSize` at 605), while
 * `SetViewportOrigin` -- what the scroll wheel drives (642) -- has no such rule, only the one-directional
 * advance when `updateBottom` says the view became the content (714), because the virtual bottom is by
 * definition "not affected by the user scrolling the viewport, only when API calls cause the viewport
 * to move" (screenInfo.hpp:218). An adopt that is only re-reading the console after a decline has no new
 * window height at all; applying the sweep to it would drop the anchor precisely when the user had scrolled
 * furthest away, which is the one situation the anchor is there for. `reshaped` says "the grid changed
 * height", and only that.
 *
 * Returns the buffer row of the new grid's model row 0. `prevWinB` is the window's bottom as the old model
 * last saw it -- the plan's, not the console's, so a view the user moved since is not mistaken for a slide.
 */
int rc_anchor_adopt(int prevSet, int prevBase, int prevRows, int prevWinB, int reshaped,
                    int winT, int winB, int bufH, int rows, int winRows)
{
  const int hist = rows - winRows;
  const int base = winT - hist;                  /* a model with no claim has only the window to go on */
  if (!prevSet || hist < 0 || winRows <= 0 || bufH <= 0 || rows <= 0) return base;
  const int vb = prevBase + prevRows - 1;        /* the anchor in the form that survives a rebuild */
  if (reshaped)
  {
    const int swept = (vb >= prevWinB && vb < winB) || (vb <= prevWinB && vb > winB);
    if (swept) return base;
  }
  /* Kept only where the grid it now anchors is legal: the viewport rows an adopt reads have to be inside
     the buffer, and `vb >= winRows - 1` is conhost's own guard, which in row-0 form is exactly the
     "virtual viewport may not poke above row 0" that the read would otherwise hit. */
  if (vb < winRows - 1 || vb > bufH - 1) return base;
  return vb - rows + 1;
}

/* Rule 1b: the source rect of a buffer scroll, in buffer rows.
 *
 * `p->row0` is where the plan is about to *address* model row 0 -- after its slide. The cells that have to
 * move, though, are the ones at the rows the anchor claimed *before* the slide, because sliding a window
 * moves no cell: they are at base + r, and the model's shift of k = slide + by put model row r's content at
 * old row r + k. Hence a source that starts k rows below the old top -- which is `row0 + by`, since
 * row0 = base + slide -- and ends at the old band's last row. Landing on [row0, row0+...] is then automatic:
 * a shift up by `by` from row0+by is row0.
 *
 * That is one of the two answers, and it is the plan's *destination* that decides which applies: whether the
 * claim this flush leaves behind ends on the buffer's last row (`row0 + modelRows >= bufH`).
 *
 *  - While there are buffer rows left below the claim, the scroll stays inside it as above. Nothing above it
 *    may move: those rows are the user's, and the room below is where the next line belongs.
 *  - Once the claim ends on the buffer's last row there is nowhere left to write, and a new line can be bought
 *    only by giving one up. Then the source starts `by` rows under the buffer's first row and lands on row 0:
 *    every row from the buffer's first down to the row the *anchor* last claimed rides up by `by`, and the
 *    oldest `by` lines leave the top. That is conhost's overflow path and not a choice this renderer gets to
 *    make its own way -- `host/_stream.cpp:123-126` answers "output wants a row past the buffer's last one"
 *    with `TextBuffer::IncrementCircularBuffer()`, which is "increments the circular buffer by one": reset
 *    row 0 and advance `_firstRow` (buffer/out/textBuffer.cpp:722-745). The buffer is a ring holding the
 *    newest `bufH` lines of one mixed stream, and no line in it is exempt from eviction because it predates
 *    this program's output. "The row the anchor last claimed" is not the same row as "the buffer's last one"
 *    whenever the flush slid, and the band ends on the former: on a mixed flush `bottom` sits `slide` rows
 *    short of `bufH - 1` -- the mixed case below pins 380 against a 400-row buffer -- because the rows a slide
 *    bought moved no cell and have nothing to ride.
 *
 * Note that a *slide* does not escape this, and cannot: sliding is how the claim gets to the buffer's last row
 * in the first place, and it moves no cells, so the rows it leaves above the claim are still holding the lines
 * the model has just dropped. A flush of k lines that slides f of them and scrolls the rest therefore owes the
 * scroll's `by` evictions as much as one that never slid -- the slide paid for the rows, not for the eviction.
 * That half was measured first and read second: with 420 numbered lines through a renderer over a 400-row
 * buffer, the claim arrived at the buffer's bottom on a mixed flush and stayed band-only, and the census found
 * the buffer holding 399 lines with one of them missing in the middle and the last row blank -- a whole
 * session's worth of lines in the wrong place, all of it below the window's sight.
 *
 * Which rows the band itself lands on is the same in both branches (old model row r + by -> buffer row0 + r),
 * so an eviction changes what happens *above* the claim and nothing about the paint at or below it; where
 * there is no scrollback to move (`row0 == 0`, the buffer's first row already claimed) the two coincide.
 *
 * Two ends get clamped, both of them the gutter's doing rather than this plan's: a band that reaches above
 * row 0 has cells the buffer does not hold, and a band that reaches past the last row was already refused by
 * rc_plan_paint -- unless the console's shape moved under the plan, in which case trimming is the least
 * damaging answer. The first of those clamps moves the band without moving `by`, so the destination this band
 * implies (`srcTop - by`, absolute -- see scroll_region) can end up above row 0, and it is deliberately left
 * that way: conhost reduces the request itself, pinning the target to the clip and shrinking the source to
 * match (host/output.cpp:365-397), which is the same answer as "shift by `by` and lose what hangs off the
 * top". Pre-clamping `by` here would be the renderer deciding to under-shift, and an under-shift moves the
 * model's own rows to rows the model no longer claims -- damage below the window rather than above it. The
 * "gutter:" case in RenderCheck pins the arithmetic this leaves. A scroll that leaves nothing to move (`by`
 * at or beyond the source's height) is a no-op with a reason: every one of the band's rows is dirty, because
 * scroll_up() blanks and marks them all when the shift is the whole grid, so the paint that follows covers the
 * band completely.
 *
 * Returns the number of rows to move, 0 for that no-op, and writes the band into srcTop and srcBottom. */
int rc_scroll_band(const RcPlan *p, int modelRows, int bufH, int *srcTop, int *srcBottom)
{
  const int base = p->row0 - p->slideRows;
  const int full = (p->row0 + modelRows >= bufH);  /* nothing below the claim left to write into */
  int top = full ? p->bufScroll : p->row0 + p->bufScroll;
  int bottom = base + modelRows - 1;
  if (top < 0) top = 0;
  if (bottom > bufH - 1) bottom = bufH - 1;
  if (top > bottom) { *srcTop = *srcBottom = top; return 0; }
  *srcTop = top;
  *srcBottom = bottom;
  return bottom - top + 1;
}

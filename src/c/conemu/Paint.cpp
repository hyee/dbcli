/*
 * Paint.cpp -- rc_plan_paint: the operation list one flush needs, with no console in sight.
 *
 * Read Paint.h first; it states why this is a separate module. The rules, in the order they apply:
 *
 *  1. Model row r is buffer row row0 + r, where row0 = window top - gutter. pendingScrolls is the only
 *     thing that can break that, and it is repaired by moving the window (free) or the buffer (one
 *     call), never by repainting: sliding the window down by k shifts every content row k rows *up* in
 *     the model and k rows *down* in row0, so each row keeps its physical buffer row. That is why a
 *     scroll costs no cell writes, and why the gutter exists -- the rows the viewport pushes out of its
 *     top are still waiting to be painted into the scrollback above the window.
 *  2. A window slide is requested by parking the cursor on the row that must become the window's
 *     bottom. conhost slides down to include a cursor it is told about and never slides up, which is
 *     exactly what the ANSI leg does with the same newline, so the two legs agree on the view.
 *  3. A model row *is* a buffer row (Render.h, `cols`), so the columns right of the window are not a tail
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

  /* 2. Spend the scroll: rows the window can still travel down are free, the rest are the buffer's. */
  const int hist = g->rows - g->winRows;
  const int k = g->pendingScrolls;
  int free_slide = v->bufH - g->winRows - v->winT;
  if (free_slide < 0) free_slide = 0;
  int slide = (k < free_slide) ? k : free_slide;
  if (slide > 0) p->slideTo = v->winT + slide + g->winRows - 1;
  p->bufScroll = k - slide;
  p->scrollAttr = g->attr;

  /* After both operations the window's top is winT + slide -- unless the buffer was scrolled, in
     which case the window was already on the last row and stays there. The gutter hangs above it. */
  p->winTop = (p->bufScroll > 0) ? (v->bufH - g->winRows) : (v->winT + slide);
  p->row0 = p->winTop - hist;
  /* Negative row0 is not an error: the viewport rows it still addresses are the ones the plan paints.
     A gutter row with no buffer row under it is scrollback this console cannot keep -- a window at the
     top of the buffer, or a buffer shorter than the model -- and it is counted, never hidden. */
  const int skip = (p->row0 < 0) ? -p->row0 : 0;

  /* 3. Damage: contiguous dirty rows become one rectangle each, as wide as their union of columns. */
  int first = -1, last = -1, capped = 0;
  int bandLo = 0, bandHi = -1;              /* union over every damaged row, for the capped band */
  for (int r = skip; r < g->rows; r++)
  {
    if (!rc_row_dirty(g, r)) continue;
    const int lo = g->dirtyLo[r], hi = g->dirtyHi[r];
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
     console really has. Vertically there is no clamp: the slide *is* rule 2. */
  p->curTX = v->winL + g->cx;
  if (p->curTX > v->winR) p->curTX = v->winR;
  p->curTY = p->row0 + g->cy;
  p->cursorMoved = (p->curTX != v->curX || p->curTY != v->curY || p->bufScroll > 0) ? 1 : 0;
}

void rc_paint_done(RcGrid *g)
{
  g->pendingScrolls = 0;
  rc_clear_dirty(g);
}

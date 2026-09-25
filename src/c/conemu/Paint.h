/*
 * Paint.h -- the console-free half of the painter: what one flush must send to conhost.
 *
 * Splitting this out is what makes the expensive geometry testable. Every bug the shipped Java writer
 * had in this area (§13 the window that will not follow, §14.1 the repaint that lands on row 0 of a
 * 9001-row buffer, §21 the block that scrolls twice) is a decision about *where the window is*, not
 * about the console API, so it can be enumerated here with no console at all and pinned by
 * RenderCheck. RenderJni.cpp is then deliberately dumb: it executes the operations in order and
 * reports the error codes.
 *
 * The one idea worth stating: a viewport scroll costs zero cell writes. While the window can still
 * slide down inside the buffer, moving it is what conhost itself does for a newline at the bottom,
 * and the cells stay exactly where they are -- so the plan says "park the cursor lower" instead of
 * "repaint everything". Only when the window already sits on the buffer's last row does the plan pay
 * for a ScrollConsoleScreenBuffer, which again moves the cells for us. Either way the only rows that
 * have to be painted are the ones that scroll *into* the viewport, plus the rows this chunk wrote.
 *
 * The second: the model is a viewport *plus* a gutter of unpainted scrollback above it (Render.h), and
 * this module is where the two coordinate. Slide and scroll are what turn a gutter row into a buffer
 * row, so a chunk of several screenfuls is painted in full instead of losing its earliest lines.
 */

#ifndef ANSIRENDER_PAINT_H
#define ANSIRENDER_PAINT_H

#include "Render.h"

#define RC_PLAN_MAX_RUNS 8

/* Reasons a flush declines to paint. Anything but RC_PLAN_OK means the caller hands the chunk to the
 * fallback leg; RC_PLAN_NOGEOM additionally means the model no longer describes the console, so it
 * has to be re-read before the next chunk. */
enum
{
  RC_PLAN_OK = 0,
  RC_PLAN_NOGEOM,    /* the console's shape is not the geometry the model was built for */
  RC_PLAN_EMPTY,     /* nothing to repaint: no read, no rectangle, maybe one cursor call */
  RC_PLAN_MAX
};

/* GetConsoleScreenBufferInfo + GetConsoleCursorInfo, narrowed to the integers the plan uses. */
typedef struct RcView
{
  int bufW, bufH;             /* dwSize */
  int winL, winT, winR, winB; /* srWindow, inclusive */
  uint16_t attr;              /* wAttributes: what SetConsoleTextAttribute would have to restore */
  int cursorOn;               /* current visibility, so ?25h/l only costs a call when it changes */
  int curHeight;              /* CONSOLE_CURSOR_INFO.dwSize as the console has it now, -1 if unreadable:
                                 DECSCUSR compares against it so a cursor nobody changed costs no call. */
  int curX, curY;             /* where the console's cursor actually is, in buffer coordinates */
} RcView;

typedef struct RcRun
{
  int top;    /* model row the run starts on */
  int nrows;  /* rows in the run */
  int lo, hi; /* columns of the buffer row it repaints, inclusive: the union of the rows' damage. A run
                 is one rectangle, so a row damaged at column 3 merged with one damaged at column 90
                 paints 3..90 on both. Over-paint is waste; the alternative is a call per row. */
} RcRun;

typedef struct RcPlan
{
  int reason;

  /* Console operations, in this order. slideTo is the buffer row to park the cursor on so conhost
     slides the window down to it (-1 = no slide); slideRows is how many rows that slide moves, which the
     executor has to add to the model's anchor only if the park actually landed. bufScroll then moves the
     model's own rows up -- the region this plan addresses, never the whole buffer, because the rows above it
     are the history the user is reading (RenderJni.cpp::scroll_region) -- which is what conhost does itself
     once the window is on the last buffer row, and the only scroll available while the view is somewhere the
     model does not own. */
  int slideTo;
  int slideRows;
  int bufScroll;
  uint16_t scrollAttr;        /* attribute ScrollConsoleScreenBuffer fills its new rows with */

  int  row0;                  /* buffer row of model row 0: the model's anchor (Render.h, baseRow) plus
                                 slideRows. May be negative -- the gutter can reach above the buffer. */
  int  winTop;                /* buffer row the window ends up on: row0 + the model's gutter while the view
                                 was ours to move, and the row the user scrolled to when it was not. */
  int  drop;                  /* damaged gutter rows with no buffer row: only a too-short buffer loses these */
  int  paintCols;             /* the buffer row: v->bufW - v->winL, which is g->cols whenever the plan
                                 is OK. It is the geometry test and the ceiling a run's columns are
                                 measured against -- NOT the width any run writes: that is run[i].lo
                                 ..hi, because damage knows its columns. 0 once the plan has declined. */
  int  nRuns;
  RcRun run[RC_PLAN_MAX_RUNS];

  int curX, curY;             /* where the cursor belongs when we are done, in model coords */
  int curTX, curTY;           /* the same point in buffer coords. curTX is clamped to the window's right
                                 column: conhost slides the viewport sideways to include a cursor parked
                                 outside it, so a line wider than the window would drag the user's view.
                                 curTY is not clamped -- sliding down for it is the point of slideTo -- but
                                 see cursorOffView: when the view is not the model's to move, it is parked
                                 nowhere. */
  int cursorMoved;            /* 0 => the console is already there and no scroll happened: skip the call */
  int cursorOffView;          /* 1 => the model's cursor row is outside the window the user is looking at,
                                 so cursorMoved is forced to 0: following output with the view is what a
                                 terminal that respects scrollback declines to do (Paint.cpp rule 2). The
                                 counts stay truthful either way -- this says why no call was made. */
  uint16_t attr;
  int  attrChanged;           /* 0 => the console already holds this attribute */
  int  cursorVisible, setVisible;
  int  shapeHeight, setShape; /* DECSCUSR: the cursor height to hand SetConsoleCursorInfo, and whether the
                                 console's differs. One call serves both this and setVisible. */
  unsigned long cells;        /* cells the runs will move: the cost the rollout gate compares, and since
                                 B2 it is the rectangles' real area rather than rows x the buffer row */
} RcPlan;

/* Fills `p` from the model and the console's current shape. Does not mutate the grid: clearing the
 * dirty flags and consuming pendingScrolls is the caller's, once the operations actually landed. */
void rc_plan_paint(const RcGrid *g, const RcView *v, RcPlan *p);

/* The caller finished with this plan: consume g->pendingScrolls and clear the damage. */
void rc_paint_done(RcGrid *g);

/* Where an adopt should read. The other half of rule 2: the window moving is not the content moving, so a
 * rebuild has to carry the anchor the old grid claimed rather than re-derive it from a view the user may
 * have scrolled away. prevSet/prevBase/prevRows are the claim the model is about to lose, prevWinB the
 * window's bottom as that model last planned it, and winT/winB/bufH the console's shape as it is now -- all
 * in buffer rows, for a grid of `rows` rows whose viewport is `winRows` tall.
 *
 * `reshaped` says the grid changed height, and it is the only case in which conhost's straddle rule applies
 * (screenInfo.cpp:1110-1112, `SetViewportSize`); a same-shape re-read must keep the anchor however far the
 * user scrolled, which is what it is there for. See the long comment at its definition. */
int rc_anchor_adopt(int prevSet, int prevBase, int prevRows, int prevWinB, int reshaped,
                    int winT, int winB, int bufH, int rows, int winRows);

/* Rule 1b: the band a buffer scroll of `p->bufScroll` rows moves, in buffer rows, and how many rows that is
 * (0 when nothing of the band survives, which is a no-op the caller may not report as a failure -- every
 * row it would have moved is dirty and the paint that follows covers them). The destination is this source
 * shifted up by `p->bufScroll`, which is `p->row0` while the claim this flush leaves behind still has buffer
 * rows below it and the buffer's first row once it does not (`p->row0 + modelRows >= bufH`): at the bottom of
 * the buffer a new line is bought by evicting the oldest one, which moves the user's scrollback as well and in
 * what order (conhost's `IncrementCircularBuffer`). It is the destination and not the anchor that decides,
 * because a slide that runs out of buffer ends on that row. Spelled here rather than at the call so that the
 * row arithmetic -- the part that decides whether the user's scrollback survives -- is checkable without a
 * console. */
int rc_scroll_band(const RcPlan *p, int modelRows, int bufH, int *srcTop, int *srcBottom);

/* What a keystroke may do to the view. The three outcomes are named because the caller may only touch the
 * console for one of them: NOCHANGE covers both "the user is already looking at the prompt" and "the model
 * has nothing to show", and only PARK carries a row and a column to park the cursor on. */
enum
{
  RC_SNAP_NOGEOM = 0,  /* the console's shape is not the model's: the caller re-adopts, as for a plan */
  RC_SNAP_NOCHANGE,    /* nothing to do, and nothing owed: the view already has it, or there is no claim */
  RC_SNAP_PARK         /* the model's cursor row is outside the window; bring it in, at least displacement */
};

/* conhost's `SnapOnInput`, which is what makes a classic console follow the user's typing after they scrolled
 * up to read history (input.cpp:177 -> SCREEN_INFORMATION::SnapOnInput, screenInfo.cpp:1707). Three facts of
 * that reference are load-bearing here and none of them is this renderer's taste:
 *
 *  - It asks for the *cursor* to be made visible, never for the bottom of the buffer (`_makeCursorVisible`,
 *    1728-1733), and `MakeCursorVisible` (1631-1666) slides the window by the least displacement that brings
 *    the row inside -- up if the row is above the view, down if below. Snapping to the buffer's last row
 *    instead would jump a user who was reading one line of history past everything above their prompt.
 *  - It is guarded on the cursor being *visible*. An application that hid the cursor owns the screen and
 *    does not want a keystroke dragging the view under it mid-frame.
 *  - conhost fires it only for a console in VTP mode (input.cpp:171-178) -- and the mode this renderer
 *    exists for is exactly the one where VTP is off. So nothing else will snap this user's view: the call
 *    has to come from the reader of the keystrokes, and the row it aims at has to come from the model.
 *
 * `want` is `baseRow + g->cy` rather than the plan's `row0 + g->cy`, because a plan has not run: the claim is
 * the model's own, and a slide would only move the window to where that claim already is. The row is refused
 * when it is not on the buffer at all -- a claim past the buffer's end has no view that could show it, and a
 * park there would be a cursor move conhost may or may not answer.
 *
 * The column is clamped into the window for the reason Paint.cpp rule 4 measures: conhost slides the viewport
 * sideways to include a cursor parked outside it, and dragging a user's view horizontally is not part of
 * following their typing. Returns the enum above; `row`/`col` are filled only for RC_SNAP_PARK. */
int rc_snap_view(const RcGrid *g, const RcView *v, int *row, int *col);

#endif /* ANSIRENDER_PAINT_H */

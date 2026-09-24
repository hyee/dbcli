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
     slides the window down to it (-1 = no slide); bufScroll then moves the whole buffer up, which is
     what conhost does itself once the window is on the last buffer row. */
  int slideTo;
  int bufScroll;
  uint16_t scrollAttr;        /* attribute ScrollConsoleScreenBuffer fills its new rows with */

  int  row0;                  /* buffer row of model row 0, after slide + scroll; may be negative */
  int  winTop;                /* buffer row the window ends up on: row0 + the model's gutter */
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
                                 curTY is not: sliding down for it is the point of slideTo. */
  int cursorMoved;            /* 0 => the console is already there and no scroll happened: skip the call */
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

#endif /* ANSIRENDER_PAINT_H */

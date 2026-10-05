#ifndef ANSIRENDER_PAINT_H
#define ANSIRENDER_PAINT_H
#include "Render.h"
#define RC_PLAN_MAX_RUNS 8

enum
{
  RC_PLAN_OK = 0,
  RC_PLAN_NOGEOM,
  RC_PLAN_EMPTY,
  RC_PLAN_MAX
};

typedef struct RcView
{
  int bufW, bufH;
  int winL, winT, winR, winB;
  uint16_t attr;
  int cursorOn;
  int curHeight;
  int curX, curY;
} RcView;

typedef struct RcRun
{
  int top;
  int nrows;
  int lo, hi;
} RcRun;

typedef struct RcPlan
{
  int reason;

  int slideTo;
  int slideRows;
  int bufScroll;
  uint16_t scrollAttr;

  int  row0;
  int  winTop;
  int  drop;
  int  paintCols;
  int  nRuns;
  RcRun run[RC_PLAN_MAX_RUNS];

  int curX, curY;
  int curTX, curTY;
  int cursorMoved;
  int cursorOffView;
  uint16_t attr;
  int  attrChanged;
  int  cursorVisible, setVisible;
  int  shapeHeight, setShape;
  int  shapeStyle, setStyle;
  unsigned long cells;
} RcPlan;

void rc_plan_paint(const RcGrid *g, const RcView *v, RcPlan *p);

#define RC_CURSOR_STYLE_BLOCK 1
#define RC_CURSOR_STYLE_VERTICAL_BAR 2

int rc_cursor_style_for(int style, int haveShapeApi);
int rc_cursor_shape_api(int available);

void rc_paint_done(RcGrid *g);

int rc_anchor_adopt(int prevSet, int prevBase, int prevRows, int prevWinB, int reshaped,
                    int winT, int winB, int bufH, int rows, int winRows);

int rc_scroll_band(const RcPlan *p, int modelRows, int bufH, int *srcTop, int *srcBottom);

enum
{
  RC_SNAP_NOGEOM = 0,
  RC_SNAP_NOCHANGE,
  RC_SNAP_PARK
};

int rc_snap_view(const RcGrid *g, const RcView *v, int *row, int *col);

#endif

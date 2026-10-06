#include "Paint.h"
#include <string.h>

static int cursor_height(int style)
{
  if (style < 0) return 0;
  return (style == 1 || style == 2) ? 100 : 15;
}

int rc_cursor_style_for(int style, int haveShapeApi)
{
  if (!haveShapeApi) return -1;
  if (style == 5 || style == 6) return RC_CURSOR_STYLE_VERTICAL_BAR;
  return -1;
}

static int rcHaveShapeApi;

int rc_cursor_shape_api(int available)
{
  const int was = rcHaveShapeApi;
  rcHaveShapeApi = available ? 1 : 0;
  return was;
}

void rc_plan_paint(const RcGrid *g, const RcView *v, RcPlan *p)
{
  memset(p, 0, sizeof(*p));
  p->reason = RC_PLAN_OK;
  p->slideTo = -1;
  p->attr = g->attr;
  p->cursorVisible = g->carried.cursorVisible;
  p->shapeHeight = cursor_height(g->cursorShape);
  p->shapeStyle = rc_cursor_style_for(g->cursorShape, rcHaveShapeApi);
  p->setStyle = (g->cursorShape >= 0 && p->shapeStyle >= 0) ? 1 : 0;
  p->setShape = (g->cursorShape >= 0 && p->shapeHeight > 0 && !p->setStyle && v && v->curHeight > 0 &&
                 v->curHeight != p->shapeHeight) ? 1 : 0;
  p->curX = g->cx;
  p->curY = g->cy;

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

  const int hist = g->rows - g->winRows;
  const int viewBase = v->winT - hist;
  int base = viewBase;
  if (g->baseSet && g->baseRow > base) base = g->baseRow;
  const int ours = (v->winT == base + hist);

  const int k = g->pendingScrolls;
  int free_slide = ours ? (v->bufH - g->winRows - v->winT) : 0;
  if (free_slide < 0) free_slide = 0;
  int slide = (k < free_slide) ? k : free_slide;
  if (slide > 0) p->slideTo = v->winT + slide + g->winRows - 1;
  p->slideRows = slide;
  p->bufScroll = k - slide;
  p->scrollAttr = g->attr;

  p->row0 = base + slide;
  p->winTop = ours ? (v->winT + slide) : v->winT;

  if (p->row0 + g->rows > v->bufH)
  {
    p->paintCols = 0;
    p->slideTo = -1;
    p->bufScroll = p->slideRows = 0;
    p->row0 = p->winTop = 0;
    p->reason = RC_PLAN_NOGEOM;
    return;
  }

  const int skip = (p->row0 < 0) ? -p->row0 : 0;

  int first = -1, last = -1, capped = 0;
  int bandLo = 0, bandHi = -1;
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
  p->setVisible = (v->cursorOn >= 0 && v->cursorOn != g->carried.cursorVisible) ? 1 : 0;

  p->curTX = v->winL + g->cx;
  if (p->curTX > v->winR) p->curTX = v->winR;
  p->curTY = p->row0 + g->cy;
  p->cursorMoved = (p->curTX != v->curX || p->curTY != v->curY || p->bufScroll > 0) ? 1 : 0;

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

int rc_snap_view(const RcGrid *g, const RcView *v, int *row, int *col)
{
  if (row) *row = -1;
  if (col) *col = -1;
  if (!g || !v || g->cols <= 0 || g->winRows <= 0) return RC_SNAP_NOGEOM;
  if (v->bufW <= 0 || v->bufH < v->winT) return RC_SNAP_NOGEOM;
  if (v->bufW - v->winL != g->cols || v->winB - v->winT + 1 != g->winRows) return RC_SNAP_NOGEOM;
  if (!g->baseSet) return RC_SNAP_NOCHANGE;
  if (!g->carried.cursorVisible) return RC_SNAP_NOCHANGE;
  const int want = g->baseRow + g->cy;
  if (want < 0 || want > v->bufH - 1) return RC_SNAP_NOCHANGE;
  if (want >= v->winT && want <= v->winB) return RC_SNAP_NOCHANGE;
  *row = want;
  const int maxc = v->winR - v->winL;
  *col = v->winL + (g->cx > maxc ? maxc : (g->cx < 0 ? 0 : g->cx));
  return RC_SNAP_PARK;
}

int rc_anchor_adopt(int prevSet, int prevBase, int prevRows, int prevWinB, int reshaped,
                    int winT, int winB, int bufH, int rows, int winRows)
{
  const int hist = rows - winRows;
  const int base = winT - hist;
  if (!prevSet || hist < 0 || winRows <= 0 || bufH <= 0 || rows <= 0) return base;
  const int vb = prevBase + prevRows - 1;
  if (reshaped)
  {
    const int swept = (vb >= prevWinB && vb < winB) || (vb <= prevWinB && vb > winB);
    if (swept) return base;
  }
  if (vb < winRows - 1 || vb > bufH - 1) return base;
  return vb - rows + 1;
}

int rc_scroll_band(const RcPlan *p, int modelRows, int bufH, int *srcTop, int *srcBottom)
{
  const int base = p->row0 - p->slideRows;
  const int full = (p->row0 + modelRows >= bufH);
  int top = full ? p->bufScroll : p->row0 + p->bufScroll;
  int bottom = base + modelRows - 1;
  if (top < 0) top = 0;
  if (bottom > bufH - 1) bottom = bufH - 1;
  if (top > bottom) { *srcTop = *srcBottom = top; return 0; }
  *srcTop = top;
  *srcBottom = bottom;
  return bottom - top + 1;
}

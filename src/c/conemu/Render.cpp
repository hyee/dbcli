#include "Render.h"
#include <algorithm>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "HostTypes.h"
#include "../luauf8/ansi_width_tables.h"
#include "vendor/ConEmuColors3.h"
#include "vendor/ConEmuRgbMap.h"
#include "vendor/X11ColorNames.h"

static_assert(sizeof(RgbMap) / sizeof(RgbMap[0]) == 256, "RgbMap excerpt is not 256 entries");
static_assert(sizeof(ClrMap) / sizeof(ClrMap[0]) == 8, "ClrMap excerpt is not 8 entries");

int rc_width(uint32_t cp)
{
  uint32_t hi = cp >> 8;
  int8_t bw = (hi < ANSI_NBLK) ? ansi_blk_w[hi] : -1;
  if (bw >= 0) return (unsigned)bw;
  unsigned cw = 1;
  uint32_t k = (hi < ANSI_NBLK) ? ansi_blk_iv[hi] : 0;
  for (; k < ANSI_NWIV; k++)
  {
    if (ansi_wiv[k].first > cp) break;
    if (cp <= ansi_wiv[k].last) { cw = ansi_wiv[k].w; break; }
  }
  return (int)cw;
}

static const uint16_t G0_DRAWING[31] = {
  0x2666, 0x2592, 0x2192, 0x21A8, 0x2190, 0x2193, 0x00B0, 0x00B1,
  0x00B6, 0x2195, 0x2518, 0x2510, 0x250C, 0x2514, 0x253C, 0x203E,
  0x207B, 0x2500, 0x208B, 0x005F, 0x251C, 0x2524, 0x2534, 0x252C,
  0x2502, 0x2264, 0x2265, 0x03C0, 0x2260, 0x00A3, 0x00B7
};

static int attr_to_index(int attr)
{
  return (int)(ClrMap[attr & 7] | (attr & 8));
}

uint16_t rc_attr(const RcGrid *g, const RcSgr *s)
{
  const uint32_t *pal = g->carried.palette;
  DWORD fg, bg;
  int fg24 = 0, bg24 = 0;

  if (s->fgKind)
  {
    if (s->fgKind == RC_CLR24B) { fg24 = 1; fg = (DWORD)s->fg & 0xFFFFFF; }
    else
    {
      if (s->fg > 15) fg24 = 1;
      fg = pal[((DWORD)s->fg) & 0xFF];
    }
  }
  else if (s->fg & 0x8)
  {
    fg = (DWORD)(ClrMap[s->fg & 7] | 0x08);
  }
  else
  {
    fg = (DWORD)(ClrMap[s->fg & 7]
                 | ((s->brightFore || (s->bold && !s->brightBack)) ? 0x08 : 0));
  }

  if (s->bgKind)
  {
    if (s->bgKind == RC_CLR24B) { bg24 = 1; bg = (DWORD)s->bg & 0xFFFFFF; }
    else
    {
      if (s->bg > 15) bg24 = 1;
      bg = pal[((DWORD)s->bg) & 0xFF];
    }
  }
  else if (s->bg & 0x8)
  {
    bg = (DWORD)(ClrMap[s->bg & 7] | 0x08);
  }
  else
  {
    bg = (DWORD)(ClrMap[s->bg & 7] | (s->brightBack ? 0x08 : 0));
  }

  WORD n = 0;
  DWORD nForeColor = 0;
  if (fg24)
  {
    nForeColor = fg & 0xFFFFFF;
    Far3Color::Color2FgIndex(nForeColor, n, (const COLORREF*)g->carried.pal16);
  }
  else
  {
    n |= (WORD)(fg & 0xF);
  }

  if (bg24)
  {
    DWORD nBackColor = bg & 0xFFFFFF;
    Far3Color::Color2BgIndex(nBackColor, nBackColor == nForeColor ? TRUE : FALSE, n, (const COLORREF*)g->carried.pal16);
  }
  else
  {
    n |= (WORD)((bg & 0xF) << 4);
  }

  if (s->underline) n |= RC_LVB_UNDERSCORE;
  if (s->inverse)   n |= RC_LVB_REVERSE;
  return n;
}

static void mark_dirty(RcGrid *g, int row, int from, int to)
{
  if (row < 0 || row >= g->rows) return;
  if (from < 0) from = 0;
  if (to > g->cols - 1) to = g->cols - 1;
  if (from > to) return;
  if (!RC_DTY(g, row))
  {
    RC_DTY(g, row) = 1;
    RC_LO(g, row) = (uint16_t)from;
    RC_HI(g, row) = (uint16_t)to;
    return;
  }
  if (from < (int)RC_LO(g, row)) RC_LO(g, row) = (uint16_t)from;
  if (to > (int)RC_HI(g, row)) RC_HI(g, row) = (uint16_t)to;
}

static void mark_row_dirty(RcGrid *g, int row)
{
  mark_dirty(g, row, 0, g->cols - 1);
}

static int gutter(const RcGrid *g)
{
  return g->rows - g->winRows;
}

void rc_mark_all_dirty(RcGrid *g)
{
  for (int r = gutter(g); r < g->rows; r++) mark_row_dirty(g, r);
}

void rc_adopt_clean(RcGrid *g)
{
  for (int r = gutter(g); r < g->rows; r++) RC_DTY(g, r) = 0;
}

void rc_set_base(RcGrid *g, int row)
{
  g->baseRow = row;
  g->baseSet = 1;
}

void rc_drop_base(RcGrid *g)
{
  g->baseSet = 0;
  rc_mark_all_dirty(g);
}

int rc_row_dirty(const RcGrid *g, int row)
{
  return (row >= 0 && row < g->rows) ? RC_DTY(g, row) : 0;
}

int rc_row_wrap(const RcGrid *g, int row)
{
  return (row >= 0 && row < g->rows) ? RC_ST(g, row).wrap : (int)RC_WRAP_NONE;
}

void rc_forget_row_state(RcGrid *g)
{
  const RcRowState clean = RC_ROW_CLEAN;
  for (int r = gutter(g); r < g->rows; r++) RC_ST(g, r) = clean;
}

int rc_row_mark(const RcGrid *g, int row)
{
  return (row >= 0 && row < g->rows) ? (int)RC_ST(g, row).mark : (int)RC_PM_NONE;
}

int rc_mark_col(const RcGrid *g, int row)
{
  return (row >= 0 && row < g->rows) ? (int)RC_ST(g, row).col : 0;
}

int rc_last_exit(const RcGrid *g)
{
  return g->lastExit;
}

unsigned long rc_prompt_marks(const RcGrid *g)
{
  return g->nPromptMark;
}

int rc_model_suspect(const RcGrid *g)
{
  return g->modelSuspect;
}

void rc_clear_model_suspect(RcGrid *g)
{
  g->modelSuspect = 0;
}

void rc_clear_dirty(RcGrid *g)
{
  memset(g->rowDirty, 0, sizeof(g->rowDirty));
}

int rc_validate_grid(const RcGrid *g, char *msg, int len)
{
  int r, c;
  msg[0] = '\0';

#define RC_BAD(...) do { snprintf(msg, (size_t) len, __VA_ARGS__); return 1; } while (0)

  if (g->cols < 1 || g->cols > RC_MAX_COLS) RC_BAD("cols=%d outside 1..%d", g->cols, RC_MAX_COLS);
  if (g->rows < 1 || g->rows > RC_MAX_ROWS) RC_BAD("rows=%d outside 1..%d", g->rows, RC_MAX_ROWS);
  if (g->winRows < 1 || g->winRows > g->rows) RC_BAD("winRows=%d outside 1..rows(%d)", g->winRows, g->rows);
  if (g->cx < 0 || g->cx >= g->cols) RC_BAD("cursor column %d outside 0..%d", g->cx, g->cols - 1);
  if (g->carried.marginSet)
  {
    if (g->carried.leftMargin < 0 || g->carried.rightMargin >= g->cols || g->carried.leftMargin >= g->carried.rightMargin)
      RC_BAD("margins %d..%d are not an ordered span inside 0..%d", g->carried.leftMargin, g->carried.rightMargin, g->cols - 1);
    if (g->cx < g->carried.leftMargin || g->cx > g->carried.rightMargin)
      RC_BAD("cursor column %d is outside the margins %d..%d", g->cx, g->carried.leftMargin, g->carried.rightMargin);
  }
  if (g->cy < g->rows - g->winRows || g->cy >= g->rows)
    RC_BAD("cursor row %d outside the viewport %d..%d", g->cy, g->rows - g->winRows, g->rows - 1);
  if (g->saveX < 0 || g->saveX >= g->cols) RC_BAD("saved column %d outside 0..%d", g->saveX, g->cols - 1);
  if (g->saveY < 0 || g->saveY >= g->rows) RC_BAD("saved row %d outside 0..%d", g->saveY, g->rows - 1);
  if (g->regSet && !(g->regTop >= 0 && g->regTop <= g->regBot && g->regBot < g->rows))
    RC_BAD("region %d..%d is not an ordered span inside 0..%d", g->regTop, g->regBot, g->rows - 1);
  if (g->nInterims < 0 || g->nInterims > RC_INTERIM_MAX)
    RC_BAD("nInterims=%d outside 0..%d", g->nInterims, RC_INTERIM_MAX);
  for (int gs = 0; gs < 4; gs++)
    if (g->carried.charset[gs] != 0 && g->carried.charset[gs] != 1)
      RC_BAD("charset[%d]=%d is neither VTCS_DEFAULT nor VTCS_DRAWING", gs, (int)g->carried.charset[gs]);
  if (g->carried.gshift > 3) RC_BAD("gshift=%d names no G-set", (int)g->carried.gshift);
  if (g->cursorVisible != 0 && g->cursorVisible != 1) RC_BAD("cursorVisible=%d", g->cursorVisible);
  if (g->semanticContent < RC_SC_OUTPUT || g->semanticContent > RC_SC_PROMPT)
    RC_BAD("semanticContent=%d outside RC_SC_OUTPUT..RC_SC_PROMPT", g->semanticContent);

  if (g->carried.tabsDefaults != 0 && g->carried.tabsDefaults != 1)
    RC_BAD("tabsDefaults=%d is neither claimed nor not", g->carried.tabsDefaults);
  for (c = 0; c < g->cols; c++)
    if (g->carried.tabStop[c] > 1) RC_BAD("tab stop %d holds %u, not a bit", c, (unsigned) g->carried.tabStop[c]);

  {
    uint8_t seen[RC_MAX_ROWS];
    memset(seen, 0, sizeof seen);
    for (r = 0; r < g->rows; r++)
    {
      const int p = g->of[r];
      if (p < 0 || p >= g->rows)
        RC_BAD("row %d addresses pool row %d, outside 0..%d", r, p, g->rows - 1);
      if (seen[p])
        RC_BAD("rows %d and %d are both pool row %d: the row order is not a permutation",
               r, (int) seen[p] - 1, p);
      seen[p] = (uint8_t) (r + 1);
    }
  }

  for (r = 0; r < g->rows; r++)
  {
    const uint8_t wrap = RC_ST(g, r).wrap;
    if (wrap != RC_WRAP_NONE && wrap != RC_WRAP_FORCED && wrap != RC_WRAP_PAD)
      RC_BAD("row %d: rowState.wrap=%d is not one of NONE/FORCED/PAD", r, (int) wrap);
    if (RC_ST(g, r).mark > RC_PM_ERROR) RC_BAD("row %d: rowState.mark=%d is not a known mark", r, (int) RC_ST(g, r).mark);
    if (RC_ST(g, r).mark != RC_PM_NONE && RC_ST(g, r).col >= g->cols)
      RC_BAD("row %d: a mark claims column %u of a %d-column row", r, RC_ST(g, r).col, g->cols);
    if (RC_DTY(g, r))
    {
      if (RC_LO(g, r) > RC_HI(g, r))
        RC_BAD("row %d: dirty range %u..%u is inverted", r, RC_LO(g, r), RC_HI(g, r));
      if (RC_HI(g, r) >= g->cols)
        RC_BAD("row %d: dirty range %u..%u reaches past the %d-column row", r, RC_LO(g, r), RC_HI(g, r), g->cols);
    }
    for (c = 0; c < g->cols; c++)
    {
      const uint16_t a = RC_CELLS(g, r)[c].attr;
      if (a & RC_LVB_LEADING)
      {
        if (c + 1 >= g->cols || !(RC_CELLS(g, r)[c + 1].attr & RC_LVB_TRAILING))
          RC_BAD("row %d column %d: a LEADING U+%x with no trailing half beside it",
                 r, c, RC_CELLS(g, r)[c].ch);
        c++;
      }
      else if (a & RC_LVB_TRAILING)
        RC_BAD("row %d column %d: a TRAILING half whose LEADING is gone", r, c);
    }
  }
#undef RC_BAD
  return 0;
}

static void heal_pairs(RcGrid *g, int row, int from, int to)
{
  if (row < 0 || row >= g->rows) return;
  if (from < 0) from = 0;
  if (to > g->cols - 1) to = g->cols - 1;
  for (int c = from; c <= to; c++)
  {
    const uint16_t a = RC_CELLS(g, row)[c].attr;
    int bad;
    if (a & RC_LVB_LEADING)
      bad = (c + 1 >= g->cols) || !(RC_CELLS(g, row)[c + 1].attr & RC_LVB_TRAILING);
    else if (a & RC_LVB_TRAILING)
      bad = (c == 0) || !(RC_CELLS(g, row)[c - 1].attr & RC_LVB_LEADING);
    else continue;
    if (!bad) continue;
    RC_CELLS(g, row)[c].ch = ' ';
    RC_CELLS(g, row)[c].attr = g->attr;
    mark_dirty(g, row, c, c);
  }
}

static void fill_span(RcGrid *g, int row, int from, int to, uint16_t attr)
{
  if (row < 0 || row >= g->rows) return;
  if (from < 0) from = 0;
  if (to >= g->cols) to = g->cols - 1;
  for (int c = from; c <= to; c++)
  {
    RC_CELLS(g, row)[c].ch = ' ';
    RC_CELLS(g, row)[c].attr = attr;
    RC_PROT(g, row)[c] = 0;
  }
  if (to >= g->cols - 1) RC_ST(g, row).wrap = RC_WRAP_NONE;
  mark_dirty(g, row, from, to);
  heal_pairs(g, row, from - 1, to + 1);
}

static void fill_row(RcGrid *g, int row, int from, uint16_t attr)
{
  fill_span(g, row, from, g->cols - 1, attr);
}

static void region(const RcGrid *g, int *top, int *bot);
static int  rect_of(const RcGrid *g, int t, int l, int b, int r, int *rt, int *rl, int *rb, int *rr);
static void rect_fill(RcGrid *g, int rt, int rl, int rb, int rr, uint16_t ch, int prot);
static void rect_selective_erase(RcGrid *g, int rt, int rl, int rb, int rr);
static void rect_copy(RcGrid *g, int st, int sl, int sb, int sr, int dt, int dl);
static void columns_shift(RcGrid *g, int n, int insert);

static int rect_of(const RcGrid *g, int t, int l, int b, int r,
                   int *rt, int *rl, int *rb, int *rr)
{
  int top = gutter(g), bot = g->rows - 1, x0 = 0, x1 = g->cols - 1;
  if (g->carried.originMode)
  {
    region(g, &top, &bot);
    if (g->carried.marginSet) { x0 = g->carried.leftMargin; x1 = g->carried.rightMargin; }
  }
  const int pageh = bot - top + 1, pagew = x1 - x0 + 1;
  int t2 = top + (t > 0 ? t : 1) - 1;
  int b2 = top + (b > 0 ? b : pageh) - 1;
  int l2 = x0 + (l > 0 ? l : 1) - 1;
  int r2 = x0 + (r > 0 ? r : pagew) - 1;
  if (t2 < top) t2 = top;
  if (b2 > bot) b2 = bot;
  if (l2 < x0) l2 = x0;
  if (r2 > x1) r2 = x1;
  *rt = t2; *rb = b2; *rl = l2; *rr = r2;
  return t2 <= b2 && l2 <= r2;
}

static void rect_fill(RcGrid *g, int rt, int rl, int rb, int rr, uint16_t ch, int prot)
{
  for (int r = rt; r <= rb; r++)
  {
    for (int c = rl; c <= rr; c++)
    {
      RC_CELLS(g, r)[c].ch = ch;
      RC_CELLS(g, r)[c].attr = g->attr;
      RC_PROT(g, r)[c] = (uint8_t)prot;
    }
    if (rr >= g->cols - 1) RC_ST(g, r).wrap = RC_WRAP_NONE;
    mark_dirty(g, r, rl, rr);
    heal_pairs(g, r, rl - 1, rr + 1);
  }
}

static void rect_selective_erase(RcGrid *g, int rt, int rl, int rb, int rr)
{
  for (int r = rt; r <= rb; r++)
    for (int c = rl; c <= rr; c++)
      if (!RC_PROT(g, r)[c])
      {
        RC_CELLS(g, r)[c].ch = ' ';
        mark_dirty(g, r, c, c);
        heal_pairs(g, r, c - 1, c + 1);
      }
}

static void rect_copy(RcGrid *g, int st, int sl, int sb, int sr, int dt, int dl)
{
  int rtop, rleft, rbot, rright;
  if (!rect_of(g, st, sl, sb, sr, &rtop, &rleft, &rbot, &rright)) return;
  const int h = rbot - rtop + 1, w = rright - rleft + 1;
  int top = gutter(g), x0 = 0;
  if (g->carried.originMode)
  {
    int db;
    region(g, &top, &db);
    if (g->carried.marginSet) x0 = g->carried.leftMargin;
  }
  const int e = top + (dt > 0 ? dt : 1) - 1;
  const int f = x0 + (dl > 0 ? dl : 1) - 1;
  const int back = (e > rtop) || (e == rtop && f > rleft);
  for (int i = 0; i < h; i++)
  {
    const int sr2 = rtop + i, dr2 = e + i;
    if (dr2 < gutter(g) || dr2 > g->rows - 1) continue;
    for (int k = 0; k < w; k++)
    {
      const int j = back ? (w - 1 - k) : k;
      const int sc = rleft + j, col = f + j;
      if (col < 0 || col > g->cols - 1) continue;
      RC_CELLS(g, dr2)[col] = RC_CELLS(g, sr2)[sc];
      RC_PROT(g, dr2)[col] = RC_PROT(g, sr2)[sc];
    }
    mark_row_dirty(g, dr2);
    heal_pairs(g, dr2, f - 1, f + w);
  }
}

static void columns_shift(RcGrid *g, int n, int insert)
{
  int top, bot;
  region(g, &top, &bot);
  const int x0 = g->carried.marginSet ? g->carried.leftMargin : 0;
  const int x1 = g->carried.marginSet ? g->carried.rightMargin : g->cols - 1;
  if (g->cy < top || g->cy > bot || g->cx < x0 || g->cx > x1) return;
  if (n < 0) n = -n;
  const int span = x1 - g->cx + 1;
  if (n > span) n = span;
  if (n <= 0) return;
  for (int r = top; r <= bot; r++)
  {
    if (insert)
    {
      memmove(&RC_CELLS(g, r)[g->cx + n], &RC_CELLS(g, r)[g->cx],
              (size_t)(span - n) * sizeof(RcCell));
      memmove(&RC_PROT(g, r)[g->cx + n], &RC_PROT(g, r)[g->cx], (size_t)(span - n));
    }
    else
    {
      memmove(&RC_CELLS(g, r)[g->cx], &RC_CELLS(g, r)[g->cx + n],
              (size_t)(span - n) * sizeof(RcCell));
      memmove(&RC_PROT(g, r)[g->cx], &RC_PROT(g, r)[g->cx + n], (size_t)(span - n));
    }
    const int lo = insert ? g->cx : (x1 - n + 1);
    for (int c = lo; c < lo + n; c++)
    {
      RC_CELLS(g, r)[c].ch = ' ';
      RC_CELLS(g, r)[c].attr = g->attr;
      RC_PROT(g, r)[c] = 0;
    }
    mark_dirty(g, r, g->cx, x1);
    heal_pairs(g, r, g->cx - 1, x1 + 1);
  }
}

static void insert_cells(RcGrid *g, int row, int col, int n)
{
  if (row < 0 || row >= g->rows || col < 0 || col >= g->cols || n <= 0) return;
  if (n > g->cols - col) n = g->cols - col;
  for (int c = g->cols - 1; c >= col + n; c--) RC_CELLS(g, row)[c] = RC_CELLS(g, row)[c - n];
  fill_span(g, row, col, col + n - 1, g->attr);
  heal_pairs(g, row, 0, g->cols - 1);
  mark_dirty(g, row, col, g->cols - 1);
}

static void row_reset_state(RcGrid *g, int row)
{
  const RcRowState clean = RC_ROW_CLEAN;
  RC_ST(g, row) = clean;
}

static void ftcs_line_ended(RcGrid *g)
{
  if (g->semanticContent == RC_SC_OUTPUT) return;
  if (g->semanticClearEol)
  {
    g->semanticContent = RC_SC_OUTPUT;
    g->semanticClearEol = 0;
    return;
  }
  if (g->cy >= 0 && g->cy < g->rows && RC_ST(g, g->cy).mark == RC_PM_NONE)
  {
    RC_ST(g, g->cy).mark = RC_PM_CONTINUATION;
    RC_ST(g, g->cy).col = 0;
    g->nPromptMark++;
  }
}

static void region(const RcGrid *g, int *top, int *bot)
{
  *top = g->regSet ? g->regTop : gutter(g);
  *bot = g->regSet ? g->regBot : g->rows - 1;
}

static void col_span(const RcGrid *g, int *left, int *right)
{
  *left = g->carried.marginSet ? g->carried.leftMargin : 0;
  *right = g->carried.marginSet ? g->carried.rightMargin : g->cols - 1;
}

static int col_left(const RcGrid *g) { return g->carried.marginSet ? g->carried.leftMargin : 0; }
static int col_right(const RcGrid *g) { return g->carried.marginSet ? g->carried.rightMargin : g->cols - 1; }

static void origin_base(const RcGrid *g, int *row0, int *col0)
{
  if (!g->carried.originMode) { *row0 = gutter(g); *col0 = 0; return; }
  int top, bot, left, right;
  region(g, &top, &bot);
  col_span(g, &left, &right);
  *row0 = top;
  *col0 = left;
}

static void rotate_span(RcGrid *g, int from, int span, int n, int down)
{
  int tmp[RC_MAX_ROWS];
  if (n <= 0 || span <= 0) return;
  if (n > span) n = span;
  memcpy(tmp, &g->of[from], (size_t)span * sizeof tmp[0]);
  for (int k = 0; k < span; k++)
    g->of[from + k] = down ? tmp[(k - n + span) % span] : tmp[(k + n) % span];
}

static void shift_region(RcGrid *g, int n, int top, int bot, int down)
{
  if (n <= 0) return;
  const int span = bot - top + 1;
  if (n > span) n = span;
  rotate_span(g, top, span, n, down);
  if (down) for (int r = top; r < top + n; r++) fill_row(g, r, 0, g->attr);
  else      for (int r = bot - n + 1; r <= bot; r++) fill_row(g, r, 0, g->attr);
  if (down) for (int r = top; r < top + n; r++) row_reset_state(g, r);
  else      for (int r = bot - n + 1; r <= bot; r++) row_reset_state(g, r);
  for (int r = top; r <= bot; r++) mark_row_dirty(g, r);
  g->nScrolls += (unsigned long)n;
}

static void scroll_up(RcGrid *g, int n)
{
  if (n <= 0) return;
  if (g->alt)
  {
    const int top = gutter(g);
    if (n > g->winRows) n = g->winRows;
    rotate_span(g, top, g->rows - top, n, 0);
    for (int r = g->rows - n; r < g->rows; r++)
    {
      fill_row(g, r, 0, g->attr);
      row_reset_state(g, r);
    }
    g->nScrolls += (unsigned long)n;
    rc_mark_all_dirty(g);
    return;
  }
  if (n > g->rows) n = g->rows;
  rotate_span(g, 0, g->rows, n, 0);
  g->nScrolls += (unsigned long)n;
  g->pendingScrolls += n;
  g->carried.unpushed = 1;
  for (int r = g->rows - n; r < g->rows; r++)
  {
    mark_row_dirty(g, r);
    row_reset_state(g, r);
    for (int c = 0; c < g->cols; c++)
    {
      RC_CELLS(g, r)[c].ch = ' ';
      RC_CELLS(g, r)[c].attr = g->attr;
      RC_PROT(g, r)[c] = 0;
    }
  }
  const int room = g->streamScrolls ? 1 : rc_scroll_room(g);
  if (g->onFlush && room > 0 && g->pendingScrolls >= room) g->onFlush(g->flushCtx);
}

static void line_down_page_scroll(RcGrid *g, int bot)
{
  rotate_span(g, 0, bot + 1, 1, 0);
  fill_row(g, bot, 0, g->attr);
  row_reset_state(g, bot);
  mark_row_dirty(g, bot);
  for (int r = bot + 1; r < g->rows; r++) mark_row_dirty(g, r);
  g->nScrolls += 1;
  g->pendingScrolls += 1;
  g->carried.unpushed = 1;
  const int room = g->streamScrolls ? 1 : rc_scroll_room(g);
  if (g->onFlush && room > 0 && g->pendingScrolls >= room) g->onFlush(g->flushCtx);
}

static void line_down(RcGrid *g)
{
  int top, bot;
  region(g, &top, &bot);
  if (g->cy > bot) { if (g->cy < g->rows - 1) g->cy++; }
  else if (g->cy < bot) g->cy++;
  else
  if (g->alt || top > gutter(g) || g->carried.marginSet) shift_region(g, 1, top, bot, 0);
  else if (bot == g->rows - 1) scroll_up(g, 1);
  else line_down_page_scroll(g, bot);
  ftcs_line_ended(g);
}

static void newline(RcGrid *g)
{
  g->cx = 0;
  line_down(g);
}

static void blank_cell(RcGrid *g, int row, int col)
{
  if (row < 0 || row >= g->rows || col < 0 || col >= g->cols) return;
  RC_CELLS(g, row)[col].ch = ' ';
  RC_CELLS(g, row)[col].attr = g->attr;
  RC_PROT(g, row)[col] = g->carried.penProt;
  mark_dirty(g, row, col, col);
  heal_pairs(g, row, col - 1, col + 1);
}

static int last_free_col(const RcGrid *g, int row, int col)
{
  if (col > 0 && (RC_CELLS(g, row)[col].attr & RC_LVB_TRAILING)) col--;
  return col < 0 ? 0 : col;
}

static void put_cell(RcGrid *g, uint16_t ch, int w)
{
  if (w <= 0) return;
  if (w > 2) w = 2;

  if (g->cx + w > col_right(g) + 1)
  {
    if (!g->carried.wrapMode)
    {
      if (w == 2) blank_cell(g, g->cy, g->cx);
      return;
    }
    RC_ST(g, g->cy).wrap = RC_WRAP_PAD;
    g->cx = col_left(g);
    line_down(g);
  }

  if (g->carried.insertMode && g->cx + w < col_right(g) + 1) insert_cells(g, g->cy, g->cx, w);

  RC_CELLS(g, g->cy)[g->cx].ch = ch;
  RC_CELLS(g, g->cy)[g->cx].attr = (uint16_t)(g->attr | (w == 2 ? RC_LVB_LEADING : 0));
  RC_PROT(g, g->cy)[g->cx] = g->carried.penProt;
  if (w == 2)
  {
    RC_CELLS(g, g->cy)[g->cx + 1].ch = ch;
    RC_CELLS(g, g->cy)[g->cx + 1].attr = (uint16_t)(g->attr | RC_LVB_TRAILING);
    RC_PROT(g, g->cy)[g->cx + 1] = g->carried.penProt;
  }
  mark_dirty(g, g->cy, g->cx, g->cx + w - 1);
  heal_pairs(g, g->cy, g->cx - 1, g->cx + w);
  g->nCells += (unsigned long)w;
  g->cx += w;

  if (g->cx > col_right(g))
  {
    if (!g->carried.wrapMode)
    {
      g->cx = last_free_col(g, g->cy, col_right(g));
      return;
    }
    RC_ST(g, g->cy).wrap = RC_WRAP_FORCED;
    g->cx = col_left(g);
    line_down(g);
  }
}

static void put_pair(RcGrid *g, uint16_t hi, uint16_t lo, int w)
{
  g->nAstral++;
  if (w >= 2)
  {
    if (g->cx + 2 > g->cols)
    {
      if (!g->carried.wrapMode) { blank_cell(g, g->cy, g->cx); return; }
      RC_ST(g, g->cy).wrap = RC_WRAP_PAD; g->cx = 0; line_down(g);
    }
    RC_CELLS(g, g->cy)[g->cx].ch = hi;
    RC_CELLS(g, g->cy)[g->cx].attr = (uint16_t)(g->attr | RC_LVB_LEADING);
    RC_CELLS(g, g->cy)[g->cx + 1].ch = lo;
    RC_CELLS(g, g->cy)[g->cx + 1].attr = (uint16_t)(g->attr | RC_LVB_TRAILING);
    mark_dirty(g, g->cy, g->cx, g->cx + 1);
    heal_pairs(g, g->cy, g->cx - 1, g->cx + 2);
    g->nCells += 2;
    g->cx += 2;
    if (g->cx >= g->cols)
    {
      if (!g->carried.wrapMode) { g->cx = last_free_col(g, g->cy, col_right(g)); return; }
      RC_ST(g, g->cy).wrap = RC_WRAP_FORCED; g->cx = 0; line_down(g);
    }
    return;
  }
  if (!g->carried.wrapMode && g->cx + 2 > g->cols) { blank_cell(g, g->cy, g->cx); return; }
  put_cell(g, hi, 1);
  put_cell(g, lo, 1);
}

static void put_cp(RcGrid *g, uint32_t cp)
{
  if (rc_width(cp) > 0) g->lastUnit = cp;
  if (cp > 0xFFFFu)
  {
    const uint32_t v = cp - 0x10000u;
    put_pair(g, (uint16_t)(0xD800u + (v >> 10)), (uint16_t)(0xDC00u + (v & 0x3FFu)), rc_width(cp));
    return;
  }
  uint16_t glyph = (uint16_t)cp;
  if (g->carried.charset[g->carried.gshift] == 1 && cp >= 0x60 && cp < 0x7F) glyph = G0_DRAWING[cp - 0x60];
  put_cell(g, glyph, rc_width(cp));
}

static void sgr_reset(RcGrid *g, int keep_underline)
{
  RcSgr *s = &g->sgr;
  memset(s, 0, sizeof(*s));
  s->fg = attr_to_index(g->carried.defAttr & 0x0F);
  s->bg = attr_to_index((g->carried.defAttr >> 4) & 0x0F);
  s->seeded = 1;
  if (keep_underline) s->underline = (g->carried.defAttr & RC_LVB_UNDERSCORE) ? 1 : 0;
  g->attr = rc_attr(g, s);
}

static void sgr_default_fg(RcGrid *g)
{
  g->sgr.fg = attr_to_index(g->carried.defAttr & 0x0F);
  g->sgr.fgKind = RC_CLR4B;
  g->sgr.brightFore = 0;
}

static void sgr_default_bg(RcGrid *g)
{
  g->sgr.bg = attr_to_index((g->carried.defAttr >> 4) & 0x0F);
  g->sgr.bgKind = RC_CLR4B;
  g->sgr.brightBack = 0;
}

static void unsupported(RcGrid *g, enum RcUnsupported which);

static void sgr_apply(RcGrid *g, const int *a, int n)
{
  RcSgr *s = &g->sgr;
  const int subbed = (a == g->args);
#define IS_SUB(i) (subbed ? g->argSub[i] : 0)
  for (int i = 0; i < n; i++)
  {
    int v = a[i];
    if (IS_SUB(i)) { unsupported(g, RC_UN_COLON); continue; }
    if (v < 0) v = 0;
    switch (v)
    {
      case 0: sgr_reset(g, 0); break;
      case 1: s->bold = 1; break;
      case 2: case 22: s->bold = 0; break;
      case 3: s->italic = 1; break;
      case 23: s->italic = 0; break;
      case 4:
      {
        s->underline = 1;
        if (i + 1 < n && IS_SUB(i + 1))
        {
          const int style = (a[i + 1] < 0) ? 0 : a[i + 1];
          s->underline = (style != 0) ? 1 : 0;
          i++;
          if (style >= 2) unsupported(g, RC_UN_COLON);
          while (i + 1 < n && IS_SUB(i + 1)) i++;
        }
        break;
      }
      case 24: s->underline = 0; break;
      case 5: case 6: case 25: break;
      case 7: s->inverse = 1; break;
      case 27: s->inverse = 0; break;
      case 9: s->crossed = 1; break;
      case 29: s->crossed = 0; break;
      case 39: sgr_default_fg(g); break;
      case 49: sgr_default_bg(g); break;
      case 58:
      {
        const int colon = (i + 1 < n && IS_SUB(i + 1));
        int k = i + 1;
        if (colon) { while (k < n && IS_SUB(k)) k++; }
        else if (k < n && a[k] == 5) k += 2;
        else if (k < n && a[k] == 2) k += 4;
        else if (k < n && a[k] == 0) k += 1;
        i = (k > i + 1 ? k : i + 1) - 1;
        unsupported(g, RC_UN_COLON);
        break;
      }
      case 38: case 48:
      {
        int *slot = (v == 38) ? &s->fg : &s->bg;
        uint8_t *kind = (v == 38) ? &s->fgKind : &s->bgKind;
        uint8_t *bright = (v == 38) ? &s->brightFore : &s->brightBack;
        const int colon = (i + 1 < n && IS_SUB(i + 1));
        if (!colon)
        {
          if (i + 2 < n && a[i + 1] == 5)
          {
            *slot = a[i + 2] & 0xFF;
            *kind = RC_CLR8B;
            *bright = 0;
            i += 2;
          }
          else if (i + 4 < n && a[i + 1] == 2)
          {
            int r = a[i + 2] & 0xFF, gg = a[i + 3] & 0xFF, b = a[i + 4] & 0xFF;
            *slot = (b << 16) | (gg << 8) | r;
            *kind = RC_CLR24B;
            *bright = 0;
            i += 4;
          }
          break;
        }

        const int kindv = (a[i + 1] < 0) ? -1 : a[i + 1];
        int k = i + 2;
        if (kindv == 2 && k < n && a[k] < 0) k++;
        int got = 0;
        while (k + got < n && IS_SUB(k + got) && a[k + got] >= 0) got++;
        if (kindv == 5 && got >= 1)
        {
          *slot = a[k] & 0xFF; *kind = RC_CLR8B; *bright = 0;
          k += 1;
        }
        else if (kindv == 2 && got >= 3)
        {
          *slot = ((a[k + 2] & 0xFF) << 16) | ((a[k + 1] & 0xFF) << 8) | (a[k] & 0xFF);
          *kind = RC_CLR24B; *bright = 0;
          k += 3;
        }
        else unsupported(g, RC_UN_COLON);
        while (k < n && IS_SUB(k)) k++;
        i = k - 1;
        break;
      }
      default:
        if (v >= 30 && v <= 37) { s->fg = v - 30; s->fgKind = RC_CLR4B; s->brightFore = 0; }
        else if (v >= 40 && v <= 47) { s->bg = v - 40; s->bgKind = RC_CLR4B; s->brightBack = 0; }
        else if (v >= 90 && v <= 97) { s->fg = (v - 90) | 8; s->fgKind = RC_CLR4B; s->brightFore = 1; }
        else if (v >= 100 && v <= 107) { s->bg = (v - 100) | 8; s->bgKind = RC_CLR4B; s->brightBack = 1; }
        break;
    }
  }
#undef IS_SUB
  g->attr = rc_attr(g, s);
}

struct RcCensus { const char *name; const char *sentence; int suspect; };

#define RC_CENSUS_ROW(tok, label, word, sentence, suspect) { label, sentence, suspect },
static const struct RcCensus rc_census[RC_UN_MAX] =
{
  RC_CENSUS_X(RC_CENSUS_ROW)
};
#undef RC_CENSUS_ROW

static void unsupported(RcGrid *g, enum RcUnsupported which)
{
  if (which >= RC_UN_MAX) return;
  g->nUnsupported[which]++;
  if (rc_census[which].suspect)
    g->modelSuspect = 1;
}

static void ignored(RcGrid *g, enum RcUnsupported which)
{
  if (which < RC_UN_MAX) g->nUnsupported[which]++;
}

static int g_clipPolicy = RC_CLIP_DENY;
void rc_set_clipboard_policy(int allow) { g_clipPolicy = allow ? RC_CLIP_ALLOW : RC_CLIP_DENY; }
int  rc_clipboard_policy(void) { return g_clipPolicy; }

int rc_census_count(void) { return RC_UN_MAX; }
const char *rc_census_name(int slot)
{ return (slot >= 0 && slot < RC_UN_MAX) ? rc_census[slot].name : NULL; }
const char *rc_census_sentence(int slot)
{ return (slot >= 0 && slot < RC_UN_MAX) ? rc_census[slot].sentence : NULL; }
int rc_census_suspect(int slot)
{ return (slot >= 0 && slot < RC_UN_MAX) ? rc_census[slot].suspect : 0; }

static int arg(const RcGrid *g, int i, int dflt)
{
  return (i < g->nArgs && g->args[i] > 0) ? g->args[i] : dflt;
}

static int count_arg(const RcGrid *g, int i, int limit)
{
  int n = arg(g, i, 1);
  if (n > limit) n = limit;
  return n > 0 ? n : 0;
}

static int count_arg_raw(const RcGrid *g, int i, int limit)
{
  int n = (i < g->nArgs) ? g->args[i] : 1;
  if (n > limit) n = limit;
  return n > 0 ? n : 0;
}

static int region_arg(const RcGrid *g, int i, int dflt, int page)
{
  int n = arg(g, i, dflt);
  if (n < 1) n = 1;
  if (n > page) n = page;
  return n;
}

static void tabs_default(RcGrid *g, int from)
{
  int c;
  if (!g->carried.tabsDefaults) return;
  if (from < RC_TAB_INTERVAL) from = RC_TAB_INTERVAL;
  for (c = from; c < g->cols; c++)
    if ((c % RC_TAB_INTERVAL) == 0) g->carried.tabStop[c] = 1;
}

static void tabs_reset(RcGrid *g)
{
  memset(g->carried.tabStop, 0, sizeof g->carried.tabStop);
  g->carried.tabsDefaults = 1;
  tabs_default(g, 0);
}

static int tab_next(const RcGrid *g, int from)
{
  int c;
  for (c = from + 1; c <= col_right(g); c++)
    if (g->carried.tabStop[c]) return c;
  return col_right(g);
}

static int tab_prev(const RcGrid *g, int from)
{
  int c;
  for (c = from - 1; c > 0; c--)
    if (g->carried.tabStop[c]) return c;
  return 0;
}

static void arm_report(RcGrid *g, enum RcReport kind, int mode, int status, int idx)
{
  if (g->reportLen >= RC_REPORT_MAX) { g->nReportFull++; return; }
  struct RcReportItem *it = &g->report[(g->reportHead + g->reportLen) % RC_REPORT_MAX];
  it->kind = (uint8_t)kind;
  it->y = (uint16_t)(kind == RC_REP_OSC ? idx : g->cy);
  it->x = (uint16_t)g->cx;
  it->mode = (uint32_t)mode;
  it->status = (uint32_t)status;
  g->reportLen++;
}

static void set_margins(RcGrid *g, int left, int right);

static void clxy(RcGrid *g, int row, int col)
{
  int top, bot, left, right;
  if (g->carried.originMode) region(g, &top, &bot);
  else { top = gutter(g); bot = g->rows - 1; }
  col_span(g, &left, &right);
  if (row < top) row = top;
  if (row > bot) row = bot;
  if (col < left) col = left;
  if (col > right) col = right;
  g->cy = row;
  g->cx = col;
}

static void set_margins(RcGrid *g, int left, int right)
{
  if (left <= 0) left = 1;
  if (right <= 0 || right > g->cols) right = g->cols;
  if (left >= right) return;
  if (left == 1 && right == g->cols) { g->carried.marginSet = 0; g->carried.leftMargin = 0; g->carried.rightMargin = g->cols - 1; }
  else { g->carried.marginSet = 1; g->carried.leftMargin = left - 1; g->carried.rightMargin = right - 1; }
  int r0, c0;
  origin_base(g, &r0, &c0);
  clxy(g, r0, c0);
}

static void move_row(RcGrid *g, int delta)
{
  int top, bot;
  region(g, &top, &bot);
  int row = g->cy + delta;
  if (delta < 0) { if (g->cy >= top && row < top) row = top; }
  else           { if (g->cy <= bot && row > bot) row = bot; }
  clxy(g, row, g->cx);
}

static void blank_viewport(RcGrid *g)
{
  for (int r = gutter(g); r < g->rows; r++)
  {
    for (int c = 0; c < g->cols; c++)
    {
      RC_CELLS(g, r)[c].ch = ' ';
      RC_CELLS(g, r)[c].attr = g->attr;
      RC_PROT(g, r)[c] = 0;
    }
  }
  rc_forget_row_state(g);
  rc_mark_all_dirty(g);
}

static int alt_screen(RcGrid *g, int on)
{
  const int hist = gutter(g), nrows = g->winRows;
  if (on)
  {
    if (!g->alt)
    {
      if (!g->snap)
      {
        g->snap = (RcCell *)malloc((size_t)nrows * g->cols * sizeof(RcCell));
        if (!g->snap)
        {
          g->nAltFail++;
          g->nUnsupported[RC_UN_ALTBUF]++;
          return 0;
        }
      }
      for (int r = 0; r < nrows; r++)
      {
        memcpy(&g->snap[(size_t)r * g->cols], &RC_CELLS(g, hist + r)[0], (size_t)g->cols * sizeof(RcCell));
        g->snapState[r] = RC_ST(g, hist + r);
      }
      g->alt = 1;
    }
    g->nAltSwitch++;
    g->saveX = g->cx;
    g->saveY = g->cy;
    g->pendingScrolls = 0;
    blank_viewport(g);
    return 1;
  }
  if (!g->alt) return 1;
  g->nAltSwitch++;
  for (int r = 0; r < nrows; r++)
  {
    memcpy(&RC_CELLS(g, hist + r)[0], &g->snap[(size_t)r * g->cols], (size_t)g->cols * sizeof(RcCell));
    RC_ST(g, hist + r) = g->snapState[r];
  }
  g->alt = 0;
  g->pendingScrolls = 0;
  clxy(g, g->saveY, g->saveX);
  rc_mark_all_dirty(g);
  return 1;
}

static void mode_reset_walk(RcGrid *g, int ris);

static void full_reset(RcGrid *g)
{
  sgr_reset(g, 0);
  g->carried.charset[0] = g->carried.charset[1] = g->carried.charset[2] = g->carried.charset[3] = 0;
  g->carried.gshift = 0;
  mode_reset_walk(g, 1);
  g->carried.mouseModes = 0;
  g->carried.mouseFormat = RC_MF_X10;
  g->carried.lastBtn = 0; g->moveSeen = 0;
  g->lastMoveX = g->lastMoveY = 0; g->lastMoveBtn = 0;
  g->regSet = 0;
  g->carried.marginSet = 0; g->carried.leftMargin = 0; g->carried.rightMargin = g->cols - 1;
  g->carried.saveOrigin = 0;
  g->cursorShape = -1;
  tabs_reset(g);
  scroll_up(g, g->winRows);
  g->carried.unpushed = 0;
  g->carried.xtOn = 0;
  g->carried.xtHave = 0;
  g->carried.penProt = 0;
  clxy(g, gutter(g), 0);
}

static void soft_reset(RcGrid *g)
{
  sgr_reset(g, 0);
  g->carried.penProt = 0;
  g->carried.charset[0] = 0; g->carried.charset[1] = 0; g->carried.charset[2] = 0; g->carried.charset[3] = 0;
  g->carried.gshift = 0;
  mode_reset_walk(g, 0);
  g->regSet = 0;
  g->carried.marginSet = 0; g->carried.leftMargin = 0; g->carried.rightMargin = g->cols - 1;
  g->saveX = g->cx;
  g->saveY = g->cy;
}

static int step_back_col(const RcGrid *g, int n)
{
  int col = g->cx - n;
  if (col < 0) col = 0;
  if (col > 0 && (RC_CELLS(g, g->cy)[col].attr & RC_LVB_TRAILING)) col--;
  return col;
}

static int interim_is(const RcGrid *g, uint8_t ch);

static void sgr_push(RcGrid *g);
static void sgr_pop(RcGrid *g);

static void xt_save(RcGrid *g, int v);
static void xt_restore(RcGrid *g, int v);

static int interim_is(const RcGrid *g, uint8_t ch)
{
  return g->nInterims == 1 && g->interims[0] == ch;
}

static void interim_push(RcGrid *g, uint8_t ch)
{
  if (g->nInterims < RC_INTERIM_MAX) g->interims[g->nInterims++] = ch;
}

static uint16_t mouseBit(int v)
{
  switch (v)
  {
    case 9:    return (uint16_t)(1u << 0);
    case 1000: return (uint16_t)(1u << 1);
    case 1002: return (uint16_t)(1u << 2);
    case 1003: return (uint16_t)(1u << 3);
    case 1004: return (uint16_t)(1u << 4);
    case 1005: return (uint16_t)(1u << 5);
    case 1006: return (uint16_t)(1u << 6);
    case 1015: return (uint16_t)(1u << 7);
    case 1016: return (uint16_t)(1u << 8);
    default:   return 0;
  }
}

/* ---- the mode table: one row per DECSET number this model knows ---------------------- */

enum
{
  RC_MOD_NONE = 0,      /* answers a constant, stores nothing (DECANM, DECCOLM) */
  RC_MOD_CURSORKEYS, RC_MOD_INSERT, RC_MOD_WRAP, RC_MOD_VISIBLE, RC_MOD_ORIGIN,
  RC_MOD_DECLRMM, RC_MOD_BP, RC_MOD_INBAND, RC_MOD_SYNC,
  RC_MOD_MOUSE,         /* a bit in mouseModes */
  RC_MOD_MFORMAT,       /* a bit in mouseModes that also picks mouseFormat */
  RC_MOD_ALT,           /* the alt-screen switch (?47/?1047/?1049) */
  RC_MOD_SAVECUR,       /* ?1048: save/restore cursor, no state of its own */
  RC_MOD_REFUSED        /* ?1001: recognised by neither reference, counted only */
};

#define RC_MSP_PRIV 0    /* private spelling only */
#define RC_MSP_BOTH 1    /* both spellings (mode 4, IRM) */

typedef struct RcModeSpec
{
  int num;
  uint8_t fld;
  uint8_t spell;
  uint8_t xt;            /* XTSAVE/XTRESTORE may name it */
  uint8_t ris;           /* RIS restores it... */
  uint8_t risVal;        /* ...to this value */
  uint8_t decstr;        /* DECSTR restores it (to risVal) */
  uint8_t carried;       /* build_model carries it across a rebuild */
} RcModeSpec;

static const RcModeSpec rc_modes[] =
{
  /*    num fld              spell       xt ris risV dec carr */
  {     1, RC_MOD_CURSORKEYS, RC_MSP_PRIV, 1, 1, 0, 1, 1 },
  {     2, RC_MOD_NONE,       RC_MSP_PRIV, 0, 0, 0, 0, 0 },
  {     3, RC_MOD_NONE,       RC_MSP_PRIV, 0, 0, 0, 0, 0 },
  {     4, RC_MOD_INSERT,     RC_MSP_BOTH, 1, 1, 0, 1, 1 },
  {     6, RC_MOD_ORIGIN,     RC_MSP_PRIV, 0, 1, 0, 1, 1 },
  {     7, RC_MOD_WRAP,       RC_MSP_PRIV, 1, 1, 1, 1, 1 },
  {     9, RC_MOD_MOUSE,      RC_MSP_PRIV, 1, 1, 0, 0, 1 },
  {    25, RC_MOD_VISIBLE,    RC_MSP_PRIV, 1, 1, 1, 1, 0 },
  {    47, RC_MOD_ALT,        RC_MSP_PRIV, 0, 1, 0, 0, 0 },
  {    69, RC_MOD_DECLRMM,    RC_MSP_PRIV, 0, 1, 0, 1, 1 },
  {  1000, RC_MOD_MOUSE,      RC_MSP_PRIV, 1, 1, 0, 0, 1 },
  {  1001, RC_MOD_REFUSED,    RC_MSP_PRIV, 0, 0, 0, 0, 0 },
  {  1002, RC_MOD_MOUSE,      RC_MSP_PRIV, 1, 1, 0, 0, 1 },
  {  1003, RC_MOD_MOUSE,      RC_MSP_PRIV, 1, 1, 0, 0, 1 },
  {  1004, RC_MOD_MOUSE,      RC_MSP_PRIV, 1, 1, 0, 0, 1 },
  {  1005, RC_MOD_MFORMAT,    RC_MSP_PRIV, 0, 1, 0, 0, 1 },
  {  1006, RC_MOD_MFORMAT,    RC_MSP_PRIV, 0, 1, 0, 0, 1 },
  {  1015, RC_MOD_MFORMAT,    RC_MSP_PRIV, 0, 1, 0, 0, 1 },
  {  1016, RC_MOD_MFORMAT,    RC_MSP_PRIV, 0, 1, 0, 0, 1 },
  {  1047, RC_MOD_ALT,        RC_MSP_PRIV, 0, 1, 0, 0, 0 },
  {  1048, RC_MOD_SAVECUR,    RC_MSP_PRIV, 0, 0, 0, 0, 0 },
  {  1049, RC_MOD_ALT,        RC_MSP_PRIV, 0, 1, 0, 0, 0 },
  {  2004, RC_MOD_BP,         RC_MSP_PRIV, 1, 1, 0, 1, 1 },
  {  2026, RC_MOD_SYNC,       RC_MSP_PRIV, 1, 1, 0, 1, 0 },
  {  2048, RC_MOD_INBAND,     RC_MSP_PRIV, 1, 1, 0, 1, 1 },
};

#define RC_MODE_N ((int)(sizeof rc_modes / sizeof rc_modes[0]))

static const RcModeSpec *rc_mode_find(int num)
{
  for (int i = 0; i < RC_MODE_N; i++)
    if (rc_modes[i].num == num) return &rc_modes[i];
  return NULL;
}

static int mode_get(const RcGrid *g, const RcModeSpec *m)
{
  switch (m->fld)
  {
    case RC_MOD_CURSORKEYS: return g->carried.cursorKeys;
    case RC_MOD_INSERT:     return g->carried.insertMode;
    case RC_MOD_WRAP:       return g->carried.wrapMode;
    case RC_MOD_VISIBLE:    return g->cursorVisible;
    case RC_MOD_ORIGIN:     return g->carried.originMode;
    case RC_MOD_DECLRMM:    return g->carried.declrmm;
    case RC_MOD_BP:         return g->carried.bracketedPaste;
    case RC_MOD_INBAND:     return g->carried.inbandResize;
    case RC_MOD_SYNC:       return g->sync;
    case RC_MOD_MOUSE: case RC_MOD_MFORMAT:
                            return (g->carried.mouseModes & mouseBit(m->num)) != 0;
    case RC_MOD_ALT:        return g->alt;
    default:                return 0;
  }
}

static void mode_set(RcGrid *g, const RcModeSpec *m, int on)
{
  switch (m->fld)
  {
    case RC_MOD_CURSORKEYS: g->carried.cursorKeys = (uint8_t)(on ? 1 : 0); return;
    case RC_MOD_INSERT:     g->carried.insertMode = (uint8_t)(on ? 1 : 0); return;
    case RC_MOD_WRAP:       g->carried.wrapMode = (uint8_t)(on ? 1 : 0); return;
    case RC_MOD_VISIBLE:    g->cursorVisible = (on ? 1 : 0); return;
    case RC_MOD_DECLRMM:    g->carried.declrmm = (uint8_t)(on ? 1 : 0); return;
    case RC_MOD_BP:         g->carried.bracketedPaste = (uint8_t)(on ? 1 : 0); return;
    case RC_MOD_INBAND:     g->carried.inbandResize = (uint8_t)(on ? 1 : 0); return;
    case RC_MOD_ORIGIN:
    {
      g->carried.originMode = (uint8_t)(on ? 1 : 0);
      int r0, c0;
      origin_base(g, &r0, &c0);
      clxy(g, r0, c0);
      return;
    }
    case RC_MOD_SYNC:
      if (on) { if (g->sync) g->nSyncNested++; else { g->sync = 1; g->nSyncEngages++; } }
      else g->sync = 0;
      return;
    case RC_MOD_MOUSE:
    {
      const uint16_t b = mouseBit(m->num);
      g->carried.mouseModes = on ? (uint16_t)(g->carried.mouseModes | b)
                         : (uint16_t)(g->carried.mouseModes & (uint16_t)~b);
      return;
    }
    case RC_MOD_MFORMAT:
    {
      const uint16_t b = mouseBit(m->num);
      g->carried.mouseModes = on ? (uint16_t)(g->carried.mouseModes | b)
                         : (uint16_t)(g->carried.mouseModes & (uint16_t)~b);
      const uint8_t f = (m->num == 1005) ? RC_MF_UTF8 : (m->num == 1006) ? RC_MF_SGR
                      : (m->num == 1015) ? RC_MF_URXVT : RC_MF_SGR_PX;
      if (on) g->carried.mouseFormat = f;
      else if (g->carried.mouseFormat == f) g->carried.mouseFormat = RC_MF_X10;
      return;
    }
    case RC_MOD_ALT:        alt_screen(g, on); return;
    case RC_MOD_SAVECUR:
      if (on) { g->saveX = g->cx; g->saveY = g->cy; }
      else clxy(g, g->saveY, g->saveX);
      return;
    case RC_MOD_REFUSED:    ignored(g, RC_UN_MOUSE); return;
    default:                ignored(g, RC_UN_MODE); return;
  }
}

/* RIS/DECSTR restore a mode's value without its set-arm side effects: setting DECOM homes the
   cursor, resetting it does not, and the alt family restores once, not once per spelling. */
static void mode_restore(RcGrid *g, const RcModeSpec *m)
{
  switch (m->fld)
  {
    case RC_MOD_CURSORKEYS: g->carried.cursorKeys = (uint8_t)m->risVal; return;
    case RC_MOD_INSERT:     g->carried.insertMode = (uint8_t)m->risVal; return;
    case RC_MOD_WRAP:       g->carried.wrapMode = (uint8_t)m->risVal; return;
    case RC_MOD_VISIBLE:    g->cursorVisible = m->risVal; return;
    case RC_MOD_ORIGIN:     g->carried.originMode = (uint8_t)m->risVal; return;
    case RC_MOD_DECLRMM:    g->carried.declrmm = (uint8_t)m->risVal; return;
    case RC_MOD_BP:         g->carried.bracketedPaste = (uint8_t)m->risVal; return;
    case RC_MOD_INBAND:     g->carried.inbandResize = (uint8_t)m->risVal; return;
    case RC_MOD_SYNC:       g->sync = (uint8_t)m->risVal; return;
    default: return;
  }
}

static void mode_reset_walk(RcGrid *g, int ris)
{
  int altDone = 0;
  for (int i = 0; i < RC_MODE_N; i++)
  {
    const RcModeSpec *m = &rc_modes[i];
    if (!(ris ? m->ris : m->decstr)) continue;
    if (m->fld == RC_MOD_ALT) { if (!altDone) { alt_screen(g, 0); altDone = 1; } }
    else mode_restore(g, m);
  }
}

static int mode_status(const RcGrid *g, int id, int *out)
{
  const RcModeSpec *m = rc_mode_find(id);
  if (!m) return 0;
  if (m->fld == RC_MOD_NONE) { *out = (m->num == 2) ? 3 : 4; return 1; }
  if (m->fld == RC_MOD_SAVECUR || m->fld == RC_MOD_REFUSED) return 0;
  *out = mode_get(g, m) ? 1 : 2;
  return 1;
}

static void csi_cursor(RcGrid *g, uint8_t final)
{
  switch (final)
  {
case 'A': move_row(g, -arg(g, 0, 1)); break;

case 'B': move_row(g, arg(g, 0, 1)); break;

case 'C': clxy(g, g->cy, g->cx + arg(g, 0, 1)); break;

case 'a': clxy(g, g->cy, g->cx + arg(g, 0, 1)); break;

case 'e': clxy(g, g->cy + arg(g, 0, 1), g->cx); break;

case 'D': clxy(g, g->cy, step_back_col(g, arg(g, 0, 1))); break;

case 'E': move_row(g, arg(g, 0, 1)); g->cx = col_left(g); break;

case 'F': move_row(g, -arg(g, 0, 1)); g->cx = col_left(g); break;

case 'G': clxy(g, g->cy, arg(g, 0, 1) - 1); break;

case 'H': case 'f':
    {
      int r0, c0;
      origin_base(g, &r0, &c0);
      const int tr = r0 + arg(g, 0, 1) - 1;
      if (!g->alt && !g->regSet && g->nArgs == 0 && g->carried.unpushed && tr == gutter(g) && g->cy > tr)
      {
        scroll_up(g, g->cy - tr + 1);
        g->carried.unpushed = 0;
      }
      clxy(g, tr, c0 + arg(g, 1, 1) - 1);
      break;
    }

case 'd': clxy(g, gutter(g) + arg(g, 0, 1) - 1, g->cx); break;


  }
}

static void csi_edit(RcGrid *g, uint8_t final)
{
  switch (final)
  {
case 'J':
    {
      const int top = gutter(g);
      int mode = arg(g, 0, 0);
      if (g->priv == '?')
      {
        if (mode == 0)
        {
          rect_selective_erase(g, g->cy, g->cx, g->cy, g->cols - 1);
          rect_selective_erase(g, g->cy + 1, 0, g->rows - 1, g->cols - 1);
        }
        else if (mode == 1)
        {
          rect_selective_erase(g, top, 0, g->cy - 1, g->cols - 1);
          rect_selective_erase(g, g->cy, 0, g->cy, g->cx);
        }
        else rect_selective_erase(g, top, 0, g->rows - 1, g->cols - 1);
        break;
      }
      if (mode == 0) { fill_row(g, g->cy, g->cx, g->attr); for (int r = g->cy + 1; r < g->rows; r++) fill_row(g, r, 0, g->attr); }
      else if (mode == 1) { for (int r = top; r < g->cy; r++) fill_row(g, r, 0, g->attr); fill_row(g, g->cy, 0, g->attr); }
      else
      {
        for (int r = top; r < g->rows; r++) fill_row(g, r, 0, g->attr);
        g->cx = col_left(g); g->cy = top;
      }
      break;
    }

case 'K':
    {
      int mode = arg(g, 0, 0);
      if (g->priv == '?')
      {
        if (mode == 0) rect_selective_erase(g, g->cy, g->cx, g->cy, col_right(g));
        else if (mode == 1) rect_selective_erase(g, g->cy, col_left(g), g->cy, g->cx);
        else rect_selective_erase(g, g->cy, 0, g->cy, g->cols - 1);
        break;
      }
      if (mode == 0) fill_span(g, g->cy, g->cx, col_right(g), g->attr);
      else if (mode == 1) fill_span(g, g->cy, col_left(g), g->cx, g->attr);
      else fill_row(g, g->cy, 0, g->attr);
      break;
    }

case 'L': case 'M':
    {
      int n, top, bot;
      region(g, &top, &bot);
      if (g->regSet && (g->cy > bot || g->cy < top)) break;
      n = count_arg(g, 0, g->regSet ? bot - g->cy + 1 : g->rows - g->cy);
      if (g->regSet)
      {
        shift_region(g, n, g->cy, bot, final == 'L');
        g->cx = col_left(g);
        break;
      }
      if (final == 'L')
      {
        rotate_span(g, g->cy, g->rows - g->cy, n, 1);
        for (int r = g->cy; r < g->cy + n && r < g->rows; r++) { fill_row(g, r, 0, g->attr); row_reset_state(g, r); }
      }
      else
      {
        rotate_span(g, g->cy, g->rows - g->cy, n, 0);
        for (int r = g->rows - n; r < g->rows; r++) { fill_row(g, r, 0, g->attr); row_reset_state(g, r); }
      }
      g->cx = col_left(g);
      rc_mark_all_dirty(g);
      break;
    }

case '@': case 'P':
    {
      if (g->cx < g->cols)
      {
        const int n = count_arg(g, 0, g->cols - g->cx);
        if (final == '@') insert_cells(g, g->cy, g->cx, n);
        else
        {
          for (int c = g->cx; c + n < g->cols; c++) RC_CELLS(g, g->cy)[c] = RC_CELLS(g, g->cy)[c + n];
          fill_span(g, g->cy, g->cols - n, g->cols - 1, g->attr);
          heal_pairs(g, g->cy, 0, g->cols - 1);
          mark_dirty(g, g->cy, g->cx, g->cols - 1);
        }
      }
      break;
    }

case 'X':
    {
      const int n = count_arg_raw(g, 0, g->cols - g->cx);
      if (n > 0)
        fill_span(g, g->cy, g->cx, g->cx + n - 1, g->attr);
      break;
    }


case 'b':
    {
      if (g->priv) { ignored(g, RC_UN_MODE); break; }
      const int want = count_arg_raw(g, 0, RC_ARG_MAX);
      for (int n = 0; n < want; n++) put_cp(g, g->lastUnit);
      break;
    }


case 'S':
    {
      int top, bot;
      region(g, &top, &bot);
      const int n = count_arg(g, 0, g->regSet ? bot - top + 1 : g->rows);
      if (!g->regSet && top == gutter(g) && bot == g->rows - 1) scroll_up(g, n);
      else shift_region(g, n, top, bot, 0);
      break;
    }

case 'T':
    {
      int top, bot;
      region(g, &top, &bot);
      shift_region(g, count_arg(g, 0, bot - top + 1), top, bot, 1);
      break;
    }


  }
}

static void csi_region(RcGrid *g, uint8_t final)
{
  switch (final)
  {
case 's':
      if (g->priv) { if (g->nArgs) xt_save(g, g->args[0]); else ignored(g, RC_UN_MODE); }
      else if (g->carried.declrmm) set_margins(g, arg(g, 0, 1), arg(g, 1, g->cols));
      else { g->saveX = g->cx; g->saveY = g->cy; g->carried.saveOrigin = g->carried.originMode; }

      break;

case 'u':
      if (g->priv) { ignored(g, RC_UN_MODE); break; }
      g->carried.originMode = g->carried.saveOrigin;
      clxy(g, g->saveY, g->saveX);

      break;


case 'r':
    {
      if (g->priv && g->nArgs) { xt_restore(g, g->args[0]); break; }
      const int top = gutter(g);
      const int page = g->rows - top;
      if (!g->nArgs) { g->regSet = 0; g->regionSerial++; break; }
      int t = region_arg(g, 0, 1, page), b = region_arg(g, 1, page, page);
      if (t > b) break;
      const int rt = top + t - 1, rb = top + b - 1;
      g->regSet = 0;
      if (!(rt == top && rb == g->rows - 1)) { g->regSet = 1; g->regTop = rt; g->regBot = rb; }
      g->regionSerial++;
      break;
    }

  }
}

static void csi_mode(RcGrid *g, uint8_t final)
{
  switch (final)
  {
case 'h': case 'l':
    {
      const int on = (final == 'h');
      const int v = g->nArgs ? g->args[0] : 0;
      const RcModeSpec *m = rc_mode_find(v);
      if (!m || (g->priv != '?' && !(g->priv == 0 && m->spell == RC_MSP_BOTH)))
        ignored(g, RC_UN_MODE);
      else
        mode_set(g, m, on);
      break;
    }

  }
}

static void csi_report(RcGrid *g, uint8_t final)
{
  switch (final)
  {
case 'p':
    {
      int st = 0;
      if (interim_is(g, '$') && g->nArgs == 1 &&
          (g->priv == '?' || (g->priv == 0 && g->args[0] == 4)))
      {
        if (!mode_status(g, g->args[0], &st)) st = 0;
        arm_report(g, RC_REP_DECRPM, g->args[0], st, 0);
      }
      else if (interim_is(g, '!') && !g->priv && !g->nArgs) soft_reset(g);
      else if (interim_is(g, '$')) ignored(g, RC_UN_MODE);
      else ignored(g, RC_UN_SUP);
      break;
    }

case 'c':
      if (g->priv == '>' && (!g->nArgs || g->args[0] == 0)) arm_report(g, RC_REP_DA2, 0, 0, 0);
      else if (!g->priv && (!g->nArgs || g->args[0] == 0)) arm_report(g, RC_REP_DA, 0, 0, 0);
      else unsupported(g, RC_UN_REPORT);
      break;

case 'n':
      if (!g->priv && g->nArgs == 1 && g->args[0] == 5) arm_report(g, RC_REP_DSR, 0, 0, 0);
      else if (!g->priv && g->nArgs == 1 && g->args[0] == 6) arm_report(g, RC_REP_CPR, 0, 0, 0);
      else unsupported(g, RC_UN_REPORT);
      break;

case 't':
    {
      const int fn = arg(g, 0, 0);
      if (fn == 18 && g->nArgs <= 1)
        arm_report(g, RC_REP_WINOP, g->winRows, g->cols, 0);
      else if (fn == 21 && g->nArgs <= 1)
        arm_report(g, RC_REP_TITLE, 0, 0, 0);
      else if ((fn == 22 || fn == 23) && g->nArgs >= 2 && g->nArgs <= 3)
      {
        const int which = arg(g, 1, 0);
        if (which > 2) { unsupported(g, RC_UN_REPORT); break; }
        if (fn == 22)
        {
          int at;
          if (g->carried.nTStack < RC_TITLE_STACK) at = g->carried.nTStack++;
          else
          {
            at = RC_TITLE_STACK - 1;
            for (int k = 0; k + 1 < RC_TITLE_STACK; k++)
            {
              g->carried.tstackLen[k] = g->carried.tstackLen[k + 1];
              for (int c = 0; c < g->carried.tstackLen[k]; c++) g->carried.tstack[k][c] = g->carried.tstack[k + 1][c];
            }
          }
          g->carried.tstackLen[at] = g->carried.nTitle;
          for (int c = 0; c < g->carried.nTitle; c++) g->carried.tstack[at][c] = g->carried.title[c];
        }
        else if (g->carried.nTStack > 0)
        {
          const int at = --g->carried.nTStack;
          const int len = g->carried.tstackLen[at];
          g->carried.tstackLen[at] = -1;
          if (len < 0)
          { unsupported(g, RC_UN_REPORT); break; }
          for (int c = 0; c < len; c++) g->osc[c] = g->carried.tstack[at][c];
          g->nOsc = len;
          g->titlePending = 1;
          for (int c = 0; c < len; c++) g->carried.title[c] = g->carried.tstack[at][c];
          g->carried.nTitle = len;
        }
        else unsupported(g, RC_UN_REPORT);
      }
      else unsupported(g, RC_UN_REPORT);
      break;
    }

  }
}

static void csi_pen_tabs_rect(RcGrid *g, uint8_t final)
{
  switch (final)
  {
case 'q':
      if (interim_is(g, ' ') && !g->priv)
      {
        int v = (g->nArgs && g->args[0] >= 1 && g->args[0] <= 6) ? g->args[0] : 0;
        g->cursorShape = v;
      }
      else if (g->priv == '>' && (!g->nArgs || g->args[0] == 0))
        arm_report(g, RC_REP_XTVER, 0, 0, 0);
      else if (interim_is(g, '"') && !g->priv)
      {
        const int v = g->nArgs ? g->args[0] : 0;
        if (v == 1) g->carried.penProt = 1;
        else if (v == 0 || v == 2) g->carried.penProt = 0;
        else ignored(g, RC_UN_MODE);
      }
      else ignored(g, RC_UN_SUP);
      break;

case 'Z':
    {
      const int n = count_arg(g, 0, RC_ARG_MAX);
      for (int i = 0; i < n; i++) g->cx = tab_prev(g, g->cx);
      break;
    }


case 'I':
    {
      const int n = count_arg(g, 0, RC_ARG_MAX);
      for (int i = 0; i < n; i++) g->cx = tab_next(g, g->cx);
      break;
    }


case 'W':
      if (g->priv == '?' && !g->nInterims && (!g->nArgs || arg(g, 0, 0) == 5)) tabs_reset(g);
      else ignored(g, RC_UN_MODE);
      break;


case 'g':
    {
      const int what = (g->nArgs > 0) ? g->args[0] : 0;
      if (what == 0) g->carried.tabStop[g->cx] = 0;
      else if (what == 3)
      {
        memset(g->carried.tabStop, 0, sizeof g->carried.tabStop);
        g->carried.tabsDefaults = 0;
      }
      else if (what == 5) tabs_reset(g);
      else ignored(g, RC_UN_MODE);
      break;
    }

case '{':
      if (interim_is(g, '#')) sgr_push(g);
      else if (interim_is(g, '$') && !g->priv)
      {
        int a, b, c, d;
        if (rect_of(g, g->nArgs > 0 ? g->args[0] : 0, g->nArgs > 1 ? g->args[1] : 0,
                    g->nArgs > 2 ? g->args[2] : 0, g->nArgs > 3 ? g->args[3] : 0, &a, &b, &c, &d))
          rect_selective_erase(g, a, b, c, d);
      }
      else unsupported(g, RC_UN_SUP);
      break;

case '}':
      if (interim_is(g, '#')) sgr_pop(g);
      else if (!g->nInterims && !g->priv) columns_shift(g, arg(g, 0, 1), 1);
      else unsupported(g, RC_UN_SUP);
      break;

case '~':
      if (!g->nInterims && !g->priv) columns_shift(g, arg(g, 0, 1), 0);
      else unsupported(g, RC_UN_SUP);
      break;

case 'x':
      if (interim_is(g, '$') && !g->priv)
      {
        const int ch = arg(g, 4, 32);
        if (ch >= 32 && ch <= 65535)
        {
          int a, b, c, d;
          if (rect_of(g, g->nArgs > 0 ? g->args[0] : 0, g->nArgs > 1 ? g->args[1] : 0,
                      g->nArgs > 2 ? g->args[2] : 0, g->nArgs > 3 ? g->args[3] : 0, &a, &b, &c, &d))
            rect_fill(g, a, b, c, d, (uint16_t)ch, g->carried.penProt);
        }
        else ignored(g, RC_UN_SUP);
      }
      else unsupported(g, RC_UN_SUP);
      break;

case 'z':
      if (interim_is(g, '$') && !g->priv)
      {
        int a, b, c, d;
        if (rect_of(g, g->nArgs > 0 ? g->args[0] : 0, g->nArgs > 1 ? g->args[1] : 0,
                    g->nArgs > 2 ? g->args[2] : 0, g->nArgs > 3 ? g->args[3] : 0, &a, &b, &c, &d))
          rect_fill(g, a, b, c, d, ' ', 0);
      }
      else unsupported(g, RC_UN_SUP);
      break;

case 'v':
      if (interim_is(g, '$') && !g->priv)
        rect_copy(g, g->nArgs > 0 ? g->args[0] : 0, g->nArgs > 1 ? g->args[1] : 0,
                  g->nArgs > 2 ? g->args[2] : 0, g->nArgs > 3 ? g->args[3] : 0,
                  g->nArgs > 5 ? g->args[5] : 0, g->nArgs > 6 ? g->args[6] : 0);
      else unsupported(g, RC_UN_SUP);
      break;

  }
}

static void csi_dispatch(RcGrid *g, uint8_t final)
{
  switch (final)
  {
    case 'm':
      if (!g->priv)
      {
        static const int one_zero[1] = {0};
        sgr_apply(g, g->nArgs ? g->args : one_zero, g->nArgs ? g->nArgs : 1);
      }
      else if (!g->csiColon) ignored(g, RC_UN_MODE);
      break;


    case 'A': case 'B': case 'C': case 'D': case 'E': case 'F': case 'G': case 'H': case 'f': case 'd': case 'a': case 'e': csi_cursor(g, final); break;
    case 'J': case 'K': case 'L': case 'M': case 'S': case 'T': case 'X': case '@': case 'P': case 'b': csi_edit(g, final); break;
    case 'r': case 's': case 'u': csi_region(g, final); break;
    case 'h': case 'l': csi_mode(g, final); break;
    case 'c': case 'n': case 't': case 'p': csi_report(g, final); break;
    case 'q': case 'Z': case 'I': case 'W': case 'g': case '{': case '}': case '~': case 'x': case 'z': case 'v': csi_pen_tabs_rect(g, final); break;
    default: unsupported(g, RC_UN_SUP); break;

  }
}

static void sgr_push(RcGrid *g)
{
  uint8_t mask = 0;
  if (g->nArgs)
  {
    for (int i = 0; i < g->nArgs; i++)
    {
      switch (g->args[i])
      {
        case 1:  mask |= RC_SP_BOLD; break;
        case 3:  mask |= RC_SP_ITAL; break;
        case 4:  mask |= RC_SP_UNDER; break;
        case 7:  mask |= RC_SP_INVERSE; break;
        case 9:  mask |= RC_SP_CROSSED; break;
        case 30: mask |= RC_SP_FORE; break;
        case 31: mask |= RC_SP_BACK; break;
        default: break;
      }
    }
    mask |= RC_SP_PARAMSED;
  }
  g->carried.sgrStack[g->carried.sgrTop] = g->sgr;
  g->carried.sgrParts[g->carried.sgrTop] = mask;
  g->carried.sgrTop = (uint8_t)((g->carried.sgrTop + 1) % RC_SGR_STACK);
  if (g->carried.sgrDepth < RC_SGR_STACK) g->carried.sgrDepth++;
}

static void sgr_pop(RcGrid *g)
{
  if (!g->carried.sgrDepth) return;
  g->carried.sgrDepth--;
  g->carried.sgrTop = (uint8_t)((g->carried.sgrTop + RC_SGR_STACK - 1) % RC_SGR_STACK);
  const RcSgr s = g->carried.sgrStack[g->carried.sgrTop];
  const uint8_t mask = g->carried.sgrParts[g->carried.sgrTop];
  if (mask & RC_SP_PARAMSED)
  {
    if (mask & RC_SP_BOLD)    g->sgr.bold = s.bold;
    if (mask & RC_SP_ITAL)    g->sgr.italic = s.italic;
    if (mask & RC_SP_UNDER)   g->sgr.underline = s.underline;
    if (mask & RC_SP_INVERSE) g->sgr.inverse = s.inverse;
    if (mask & RC_SP_CROSSED) g->sgr.crossed = s.crossed;
    if (mask & RC_SP_FORE)
    { g->sgr.fg = s.fg; g->sgr.fgKind = s.fgKind; g->sgr.brightFore = s.brightFore; }
    if (mask & RC_SP_BACK)
    { g->sgr.bg = s.bg; g->sgr.bgKind = s.bgKind; g->sgr.brightBack = s.brightBack; }
  }
  else
  {
    const int seeded = g->sgr.seeded;
    g->sgr = s;
    g->sgr.seeded = seeded;
  }
  g->attr = rc_attr(g, &g->sgr);
}

static const RcModeSpec *xt_row(int v, uint16_t *bit)
{
  uint16_t b = 1;
  for (int i = 0; i < RC_MODE_N; i++)
  {
    if (!rc_modes[i].xt) continue;
    if (rc_modes[i].num == v)
    {
      *bit = b;
      return &rc_modes[i];
    }
    b = (uint16_t)(b << 1);
  }
  *bit = 0;
  return NULL;
}

static void xt_save(RcGrid *g, int v)
{
  uint16_t b;
  const RcModeSpec *m = xt_row(v, &b);
  if (!m) { ignored(g, RC_UN_MODE); return; }
  if (mode_get(g, m)) g->carried.xtOn |= b; else g->carried.xtOn = (uint16_t)(g->carried.xtOn & (uint16_t)~b);
  g->carried.xtHave |= b;
}

static void xt_restore(RcGrid *g, int v)
{
  uint16_t b;
  const RcModeSpec *m = xt_row(v, &b);
  if (!m) { ignored(g, RC_UN_MODE); return; }
  mode_set(g, m, (g->carried.xtOn & b) != 0);
}

static void screen_alignment(RcGrid *g)
{
  const uint16_t attr = g->carried.defAttr;
  const int first = g->rows - g->winRows;
  for (int r = first; r < g->rows; r++)
  {
    for (int c = 0; c < g->cols; c++)
    {
      RC_CELLS(g, r)[c].ch = 'E';
      RC_CELLS(g, r)[c].attr = attr;
      RC_PROT(g, r)[c] = 0;
    }
    RC_ST(g, r).wrap = RC_WRAP_NONE;
    mark_dirty(g, r, 0, g->cols - 1);
    heal_pairs(g, r, 0, g->cols - 1);
  }
  g->regSet = 0;
  g->regTop = 0; g->regBot = g->rows - 1;
  g->carried.marginSet = 0;
  g->carried.leftMargin = 0;
  g->carried.rightMargin = g->cols - 1;
  g->carried.originMode = 0; g->carried.saveOrigin = 0; g->carried.declrmm = 0;
  g->sgr.bold = g->sgr.brightFore = g->sgr.brightBack = 0;
  g->sgr.italic = g->sgr.underline = g->sgr.inverse = g->sgr.crossed = 0;
  g->attr = rc_attr(g, &g->sgr);
  clxy(g, first, 0);
}

static void esc_dispatch(RcGrid *g, uint8_t interim, uint8_t final)
{
  if (interim == '#')
  {
    if (final == '8') screen_alignment(g);
    else if (final == '3' || final == '4' || final == '5' || final == '6') ignored(g, RC_UN_SUP);
    else ignored(g, RC_UN_SUP);
    return;
  }
  switch (final)
  {
    case '7': g->saveX = g->cx; g->saveY = g->cy; g->carried.saveOrigin = g->carried.originMode;
      break;
    case '8': g->carried.originMode = g->carried.saveOrigin; clxy(g, g->saveY, g->saveX);
      break;
    case 'c': full_reset(g); break;
    case 'D': line_down(g); break;
    case 'E': g->cx = col_left(g); line_down(g); break;
    case 'M':
    {
      int top, bot;
      region(g, &top, &bot);
      if (g->cy == gutter(g) || (g->regSet && g->cy == top))
      {
        if (g->cy >= top && g->cy <= bot) shift_region(g, 1, g->cy, bot, 1);
      }
      else clxy(g, g->cy - 1, g->cx);
      break;
    }
    case 'g': ignored(g, RC_UN_MODE); break;
    case 'H': g->carried.tabStop[g->cx] = 1; break;
    case '=': case '>': ignored(g, RC_UN_MODE); break;
    default: unsupported(g, RC_UN_SUP); break;
  }
}

static void esc_charset(RcGrid *g, uint8_t designator, uint8_t c)
{
  int slot = -1;
  switch (designator)
  {
    case '(': slot = 0; break;
    case ')': slot = 1; break;
    case '*': slot = 2; break;
    case '+': slot = 2; break;
    case '~': slot = 3; break;
    default: break;
  }
  if (slot >= 0)
  {
    g->carried.charset[slot] = (c == '0') ? 1 : 0;
    if (c != '0' && c != 'B')
      ignored(g, RC_UN_CHARSET);
    return;
  }
  ignored(g, RC_UN_SUP);
}

static void control(RcGrid *g, uint16_t u)
{
  switch (u)
  {
    case 0x07: break;
    case 0x08: if (g->cx > 0) g->cx = step_back_col(g, 1); break;
    case 0x09: g->cx = tab_next(g, g->cx); break;
    case 0x0A: newline(g); break;
    case 0x0D: g->cx = 0; break;
    case 0x0E: g->carried.gshift = 1; break;
    case 0x0F: g->carried.gshift = 0; break;
    default: break;
  }
}

static void push_arg(RcGrid *g, int v, int sub)
{
  if (g->nArgs < RC_CSI_ARGS) { g->args[g->nArgs] = v; g->argSub[g->nArgs] = (uint8_t)(sub ? 1 : 0); g->nArgs++; return; }
  g->nArgTrunc++;
}

static void csi_start(RcGrid *g)
{
  g->mode = RC_CSI;
  g->priv = 0;
  g->csiColon = 0;
  g->csiSub = 0;
  g->nInterims = 0;
  g->nArgs = 0;
  g->digit = 0;
  g->cur = 0;
}

static void osc_start(RcGrid *g, int kind)
{
  g->mode = RC_OSC;
  g->nOsc = 0;
  g->oscKind = kind;
  g->oscClip = 0;
}

#define RC_OSC_CODE_MAX 1000000
static int osc_code_of(const RcGrid *g, int *sepAt)
{
  int i = 0;
  while (i < g->nOsc && g->osc[i] >= '0' && g->osc[i] <= '9') i++;
  *sepAt = (i < g->nOsc && g->osc[i] == ';') ? i : -1;
  if (i == 0) return -1;
  if (i > 1 && g->osc[0] == '0') return RC_OSC_CODE_MAX;
  int v = 0;
  for (int j = 0; j < i; j++)
  {
    v = v * 10 + (g->osc[j] - '0');
    if (v > RC_OSC_CODE_MAX) return RC_OSC_CODE_MAX;
  }
  return v;
}

static int ftcs_field(const uint16_t *p, int n, int idx, int *off, int *len)
{
  int start = 0, i = 0;
  for (;;)
  {
    int j = start;
    while (j < n && p[j] != ';') j++;
    if (i == idx) { *off = start; *len = j - start; return 1; }
    if (j >= n) return 0;
    start = j + 1; i++;
  }
}

static int ftcs_is(const uint16_t *p, int off, int len, const char *key)
{
  int i = 0;
  for (; key[i]; i++) if (len <= i || p[off + i] != (uint16_t)key[i]) return 0;
  return len == i;
}

static int ftcs_continuation(const uint16_t *p, int n)
{
  int off, len;
  for (int i = 1; ftcs_field(p, n, i, &off, &len); i++)
  {
    int e = 0;
    while (e < len && p[off + e] != '=') e++;
    if (e >= len) continue;
    if (!ftcs_is(p, off, e, "k")) continue;
    if (len - e - 1 != 1) return 0;
    const uint16_t v = p[off + e + 1];
    return (v == 'c' || v == 's');
  }
  return 0;
}

static int ftcs_exit(const uint16_t *p, int n, int *code)
{
  int off, len;
  *code = RC_EXIT_UNKNOWN;
  if (!ftcs_field(p, n, 1, &off, &len)) return 0;
  if (len < 1 || len > 9) return -1;
  long v = 0;
  for (int i = 0; i < len; i++)
  {
    const uint16_t u = p[off + i];
    if (u < '0' || u > '9') return -1;
    v = v * 10L + (long)(u - '0');
  }
  *code = (int)v;
  return 1;
}

static void ftcs_prompt(RcGrid *g, int continuation)
{
  g->semanticContent = RC_SC_PROMPT;
  g->semanticClearEol = 0;
  if (g->cy < 0 || g->cy >= g->rows) return;
  if (RC_ST(g, g->cy).mark != RC_PM_NONE && RC_ST(g, g->cy).mark != RC_PM_CONTINUATION) return;
  RC_ST(g, g->cy).mark = (uint8_t)(continuation ? RC_PM_CONTINUATION : RC_PM_PROMPT);
  RC_ST(g, g->cy).col = (uint16_t)g->cx;
  g->nPromptMark++;
}

static void ftcs_fresh_line(RcGrid *g)
{
  if (g->cx == 0) return;
  g->cx = 0;
  line_down(g);
}

static int ftcs_apply(RcGrid *g, const uint16_t *p, int n)
{
  int off, len;
  if (!ftcs_field(p, n, 0, &off, &len) || len != 1) return 0;
  const uint16_t a = p[off];
  if (a == 'L')
  {
    if (n != 1) return 0;
    ftcs_fresh_line(g);
    return 1;
  }
  switch (a)
  {
    case 'A': case 'N':
      ftcs_fresh_line(g);
      ftcs_prompt(g, ftcs_continuation(p, n));
      return 1;
    case 'P':
      ftcs_prompt(g, ftcs_continuation(p, n));
      return 1;
    case 'B': case 'I':
      g->semanticContent = RC_SC_INPUT;
      g->semanticClearEol = (uint8_t)(a == 'I');
      return 1;
    case 'C':
      g->semanticContent = RC_SC_OUTPUT;
      g->semanticClearEol = 0;
      if (g->cy >= 0 && g->cy < g->rows && g->cx == 0 && RC_ST(g, g->cy).mark != RC_PM_NONE)
        RC_ST(g, g->cy).mark = RC_PM_NONE;
      return 1;
    case 'D':
    {
      int code;
      const int have = ftcs_exit(p, n, &code);
      g->semanticContent = RC_SC_OUTPUT;
      g->semanticClearEol = 0;
      g->lastExit = (have == 1) ? code : (have == -1) ? RC_EXIT_UNPARSABLE : RC_EXIT_UNKNOWN;
      for (int r = g->cy; r >= 0 && r < g->rows; r--)
      {
        if (RC_ST(g, r).mark == RC_PM_NONE) continue;
        if (have != 0)
          RC_ST(g, r).mark = (uint8_t)((have == 1 && code == 0) ? RC_PM_SUCCESS : RC_PM_ERROR);
        return 1;
      }
      return 1;
    }
    default: return 0;
  }
}

static int hex_digit_of(uint16_t u)
{
  if (u >= '0' && u <= '9') return u - '0';
  if (u >= 'a' && u <= 'f') return u - 'a' + 10;
  if (u >= 'A' && u <= 'F') return u - 'A' + 10;
  return -1;
}

static int comp_of(const uint16_t *p, int n, uint32_t *out)
{
  if (n < 1 || n > 4) return 0;
  uint32_t v = 0;
  for (int i = 0; i < n; i++)
  {
    const int d = hex_digit_of(p[i]);
    if (d < 0) return 0;
    v = (v << 4) | (uint32_t)d;
  }
  *out = n == 1 ? v * 0x11u : n == 2 ? v : n == 3 ? v >> 4 : v >> 8;
  return 1;
}

static int color_spec_of(const uint16_t *f, int n, uint32_t *out)
{
  uint32_t c[3] = { 0, 0, 0 };
  if (n <= 1) return 0;

  if (f[0] == '#')
  {
    const int body = n - 1;
    if (body != 3 && body != 6 && body != 9 && body != 12) return 0;
    const int w = body / 3;
    for (int i = 0; i < 3; i++) if (!comp_of(f + 1 + i * w, w, &c[i])) return 0;
  }
  else if (n >= 9 && n <= 18 && (f[0] == 'r' || f[0] == 'R') &&
           (f[1] == 'g' || f[1] == 'G') && (f[2] == 'b' || f[2] == 'B') && f[3] == ':')
  {
    int a = -1, b = -1;
    for (int i = 4; i < n; i++)
    {
      if (f[i] != '/') continue;
      if (a < 0) a = i; else if (b < 0) b = i; else return 0;
    }
    if (a < 0 || b < 0) return 0;
    if (!comp_of(f + 4, a - 4, &c[0])) return 0;
    if (!comp_of(f + a + 1, b - a - 1, &c[1])) return 0;
    if (!comp_of(f + b + 1, n - b - 1, &c[2])) return 0;
  }
  else
  {
    char key[32];
    if (x11_color_fold(f, n, key, (int)sizeof key) < 0) return 0;
    const int rgb = x11_color_lookup(key);
    if (rgb < 0) return 0;
    *out = (uint32_t)rgb;
    return 1;
  }

  *out = (c[2] << 16) | (c[1] << 8) | c[0];
  return 1;
}

static int osc_field(const RcGrid *g, int sep, int k, int *first, int *len)
{
  if (sep < 0) return 0;
  int i = sep + 1, n = 0;
  for (;;)
  {
    int j = i;
    while (j < g->nOsc && g->osc[j] != ';') j++;
    if (n == k) { *first = i; *len = j - i; return 1; }
    if (j >= g->nOsc) return 0;
    i = j + 1; n++;
  }
}

static int dec_of(const uint16_t *p, int n, int *out)
{
  if (n < 1) return 0;
  int v = 0;
  for (int i = 0; i < n; i++)
  {
    if (p[i] < '0' || p[i] > '9') return 0;
    v = v * 10 + (p[i] - '0');
    if (v > 0xFFFF) return 0;
  }
  *out = v;
  return 1;
}

static void palette_set(RcGrid *g, int idx, uint32_t rgb)
{
  if (idx < 16)
  {
    g->carried.pal16[idx] = rgb;
    g->carried.palTouched |= (uint16_t)(1u << idx);
  }
  else g->carried.palette[idx] = rgb;
  g->attr = rc_attr(g, &g->sgr);
}

static int nearest_index(const RcGrid *g, uint32_t rgb)
{
  WORD n = 0;
  Far3Color::Color2FgIndex((COLORREF)rgb, n, (const COLORREF*)g->carried.pal16);
  return (int)(n & 0xF);
}

static void palette_osc(RcGrid *g, int code, int sep, int terminated)
{
  if (!terminated) { unsupported(g, RC_UN_OSC_OTHER); return; }

  int first = 0, len = 0;
  if (code == 4)
  {
    for (int k = 0; osc_field(g, sep, k, &first, &len); k += 2)
    {
      int idx = 0;
      if (!dec_of(g->osc + first, len, &idx) || idx > 255) { unsupported(g, RC_UN_OSC_OTHER); continue; }
      int sf = 0, sl = 0;
      if (!osc_field(g, sep, k + 1, &sf, &sl)) { unsupported(g, RC_UN_OSC_OTHER); break; }
      if (sl == 1 && g->osc[sf] == '?')
      {
        arm_report(g, RC_REP_OSC, 4, idx < 16 ? g->carried.pal16[idx] : g->carried.palette[idx], idx);
        continue;
      }
      uint32_t rgb = 0;
      if (!color_spec_of(g->osc + sf, sl, &rgb)) { unsupported(g, RC_UN_OSC_OTHER); continue; }
      palette_set(g, idx, rgb);
    }
    return;
  }

  if (code == 10 || code == 11)
  {
    int resource = code;
    for (int k = 0; osc_field(g, sep, k, &first, &len); k++, resource++)
    {
      if (resource > 12) { unsupported(g, RC_UN_OSC_OTHER); break; }
      if (len == 1 && g->osc[first] == '?')
      {
        const uint32_t q = g->carried.pal16[(resource == 10) ? (g->carried.defAttr & 0xF) : ((g->carried.defAttr >> 4) & 0xF)];
        arm_report(g, RC_REP_OSC, resource, q, 0);
        continue;
      }
      uint32_t rgb = 0;
      if (!color_spec_of(g->osc + first, len, &rgb)) { unsupported(g, RC_UN_OSC_OTHER); continue; }
      const int idx = nearest_index(g, rgb);
      if (resource == 10) g->carried.defAttr = (uint16_t)((g->carried.defAttr & 0xFFF0) | idx);
      else if (resource == 11) g->carried.defAttr = (uint16_t)((g->carried.defAttr & 0xFF0F) | (idx << 4));
      else { unsupported(g, RC_UN_OSC_OTHER); continue; }
      g->attr = rc_attr(g, &g->sgr);
    }
    return;
  }

  if (code == 104)
  {
    if (!osc_field(g, sep, 0, &first, &len))
    {
      for (int i = 0; i < 256; i++) g->carried.palette[i] = RgbMap[i];
      for (int i = 0; i < 16; i++) g->carried.pal16[i] = (uint32_t)Far3Color::GetStdPalette()[i];
      g->carried.palTouched = 0xFFFF;
      g->attr = rc_attr(g, &g->sgr);
      return;
    }
    for (int k = 0; osc_field(g, sep, k, &first, &len); k++)
    {
      int idx = 0;
      if (!dec_of(g->osc + first, len, &idx)) { unsupported(g, RC_UN_OSC_OTHER); break; }
      if (idx > 255) { unsupported(g, RC_UN_OSC_OTHER); continue; }
      if (idx < 16) { g->carried.pal16[idx] = (uint32_t)Far3Color::GetStdPalette()[idx];
                      g->carried.palTouched |= (uint16_t)(1u << idx); }
      else g->carried.palette[idx] = RgbMap[idx];
    }
    g->attr = rc_attr(g, &g->sgr);
    return;
  }

  if (code == 110 || code == 111)
  {
    if (osc_field(g, sep, 0, &first, &len)) { unsupported(g, RC_UN_OSC_OTHER); return; }
    g->carried.defAttr = (uint16_t)((code == 110) ? ((g->carried.defAttr & 0xFFF0) | (g->defAttrSeed & 0xF))
                                          : ((g->carried.defAttr & 0xFF0F) | (g->defAttrSeed & 0xF0)));
    g->attr = rc_attr(g, &g->sgr);
    return;
  }
}

static int path_is_legal(const uint16_t *p, int n)
{
  if (n <= 0) return 0;
  for (int i = 0; i < n; i++)
    if (p[i] < 0x20 || p[i] == 0x7F || p[i] == L'"') return 0;
  return 1;
}

static void osc9_action(RcGrid *g, int sep, int terminated)
{
  if (!terminated || sep < 0) { unsupported(g, RC_UN_OSC_PRIV); return; }
  int first = 0, len = 0, sub = 0;
  if (!osc_field(g, sep, 0, &first, &len) || !dec_of(g->osc + first, len, &sub))
  { unsupported(g, RC_UN_OSC_PRIV); return; }

  if (sub == 4)
  {
    int state = 0, progress = 0, sf = 0, sl = 0;
    if (osc_field(g, sep, 1, &sf, &sl))
    {
      if (sl && !dec_of(g->osc + sf, sl, &state)) { unsupported(g, RC_UN_OSC_PRIV); return; }
      if (osc_field(g, sep, 2, &sf, &sl) && sl && !dec_of(g->osc + sf, sl, &progress))
      { unsupported(g, RC_UN_OSC_PRIV); return; }
    }
    if (state > 4) { unsupported(g, RC_UN_OSC_PRIV); return; }
    if (progress > 100) progress = 100;
    g->carried.taskbarState = state;
    g->carried.taskbarProgress = progress;
    g->carried.taskbarSeen = 1;
    return;
  }

  if (sub == 9)
  {
    if (!osc_field(g, sep, 1, &first, &len)) { unsupported(g, RC_UN_OSC_PRIV); return; }
    int a = first, n = len;
    if (n >= 3 && g->osc[a] == L'"' && g->osc[a + n - 1] == L'"') { a++; n -= 2; }
    if (!path_is_legal(g->osc + a, n) || n > RC_TITLE_MAX) { unsupported(g, RC_UN_OSC_PRIV); return; }
    for (int i = 0; i < n; i++) g->carried.cwd[i] = g->osc[a + i];
    g->carried.nCwd = n;
    return;
  }

  if (sub == 12)
  {
    const uint16_t B = L'B';
    if (ftcs_apply(g, &B, 1)) return;
    unsupported(g, RC_UN_OSC_PRIV);
    return;
  }

  unsupported(g, RC_UN_OSC_PRIV);
}

static void osc_title(RcGrid *g, int code, int sep, int terminated)
{
  (void)code;
  if (sep != 1 || g->nOsc <= 2 || !terminated) { unsupported(g, RC_UN_OSC_OTHER); return; }
  int from = 2, len = g->nOsc - 2;
  const int clipped = (g->nOsc > RC_TITLE_MAX) || g->oscClip;
  if (len > RC_TITLE_MAX - 2) len = RC_TITLE_MAX - 2;
  if (len > 1 && g->osc[from] == '"' && g->osc[from + len - 1] == '"') { from++; len -= 2; }
  for (int i = 0; i < len; i++) g->osc[i] = g->osc[from + i];
  g->nOsc = len;
  g->titlePending = 1;
  for (int i = 0; i < len; i++) g->carried.title[i] = g->osc[i];
  g->carried.nTitle = len;
  g->nTitleSet++;
  if (clipped) g->nTitleTrunc++;
}

static void osc_ftcs(RcGrid *g, int code, int sep, int terminated)
{
  (void)code;
  if (sep != 3 || !terminated) { unsupported(g, RC_UN_OSC_OTHER); return; }
  if (!ftcs_apply(g, g->osc + sep + 1, g->nOsc - sep - 1)) unsupported(g, RC_UN_OSC_OTHER);
}

static void osc_bracket(RcGrid *g, int code, int sep, int terminated)
{
  (void)code; (void)sep; (void)terminated;
  unsupported(g, RC_UN_DECBP);
}

static void osc_private9(RcGrid *g, int code, int sep, int terminated)
{
  (void)code;
  osc9_action(g, sep, terminated);
}

static int b64_value(uint16_t u)
{
  if (u >= 'A' && u <= 'Z') return u - 'A';
  if (u >= 'a' && u <= 'z') return 26 + (u - 'a');
  if (u >= '0' && u <= '9') return 52 + (u - '0');
  if (u == '+') return 62;
  if (u == '/') return 63;
  return -1;
}

int rc_b64_decode(const uint16_t *src, int n, uint8_t *dst, int cap)
{
  if (n < 0) return -1;
  if (n == 0) return 0;

  int pad = 0;
  while (pad < n && src[n - 1 - pad] == '=') pad++;
  if (pad > 2) return -1;
  const int body = n - pad;
  for (int i = 0; i < body; i++) if (b64_value(src[i]) < 0) return -1;
  for (int i = body; i < n; i++) if (src[i] != '=') return -1;

  const int tail = body % 4;
  if (tail == 1) return -1;
  if (pad && tail == 0) return -1;
  if (pad == 1 && tail != 3) return -1;
  if (pad == 2 && tail != 2) return -1;

  long out = (long)(body / 4) * 3;
  if (tail == 2) out += 1;
  else if (tail == 3) out += 2;
  if (out > cap) return -1;

  int o = 0;
  for (int i = 0; i + 4 <= body; i += 4)
  {
    const unsigned acc = ((unsigned)b64_value(src[i]) << 18) | ((unsigned)b64_value(src[i + 1]) << 12)
                       | ((unsigned)b64_value(src[i + 2]) << 6) | (unsigned)b64_value(src[i + 3]);
    dst[o++] = (uint8_t)(acc >> 16);
    dst[o++] = (uint8_t)((acc >> 8) & 0xFFu);
    dst[o++] = (uint8_t)(acc & 0xFFu);
  }
  if (tail)
  {
    unsigned acc = ((unsigned)b64_value(src[body - tail]) << 18) | ((unsigned)b64_value(src[body - tail + 1]) << 12);
    if (tail == 3) acc |= (unsigned)b64_value(src[body - 1]) << 6;
    const unsigned unusedBits = (tail == 2) ? ((acc >> 12) & 0x0Fu) : ((acc >> 6) & 0x03u);
    if (unusedBits != 0) return -1;
    dst[o++] = (uint8_t)(acc >> 16);
    if (tail == 3) dst[o++] = (uint8_t)((acc >> 8) & 0xFFu);
  }
  return o;
}

static void osc_clip(RcGrid *g, int code, int sep, int terminated)
{
  (void)code;
  if (!terminated) { unsupported(g, RC_UN_OSC_OTHER); return; }

  int s2 = -1;
  for (int i = sep + 1; i < g->nOsc; i++) { if (g->osc[i] == ';') { s2 = i; break; } }
  if (s2 < 0) { g->nClipBad++; unsupported(g, RC_UN_OSC_CLIP); return; }

  const int selLen = s2 - (sep + 1);
  if (!(selLen == 0 || (selLen == 1 && g->osc[sep + 1] == 'c')))
  { g->nClipSel++; unsupported(g, RC_UN_OSC_CLIP); return; }

  const int from = s2 + 1, len = g->nOsc - from;
  if (len == 1 && g->osc[from] == '?') { g->nClipRead++; unsupported(g, RC_UN_OSC_CLIP); return; }

  if (g->oscClip || len > RC_CLIP_ENC_MAX) { g->nClipBad++; unsupported(g, RC_UN_OSC_CLIP); return; }

  uint8_t text[RC_CLIP_MAX];
  const int n = rc_b64_decode(g->osc + from, len, text, RC_CLIP_MAX);
  if (n < 0) { g->nClipBad++; unsupported(g, RC_UN_OSC_CLIP); return; }
  for (int i = 0; i < n; i++)
  {
    if (text[i] == 0) { g->nClipBad++; unsupported(g, RC_UN_OSC_CLIP); return; }
  }
  if (rc_clipboard_policy() != RC_CLIP_ALLOW) { unsupported(g, RC_UN_OSC_CLIP); return; }

  for (int i = 0; i < n; i++) g->clip[i] = text[i];
  g->nClip = n;
  g->clipPending = 1;
  g->nClipSet++;
}

struct RcOscFamily
{
  const char *name;
  int  (*owns)(int code);
  void (*apply)(RcGrid *g, int code, int sep, int terminated);
};

static void osc_cwd7(RcGrid *g, int code, int sep, int terminated)
{
  (void)code; (void)terminated;
  int first = 0, len = 0;
  if (!osc_field(g, sep, 0, &first, &len)) { unsupported(g, RC_UN_OSC_OTHER); return; }
  if (len >= 8 && g->osc[first] == 'f' && g->osc[first + 1] == 'i' && g->osc[first + 2] == 'l' &&
      g->osc[first + 3] == 'e' && g->osc[first + 4] == ':' && g->osc[first + 5] == '/' &&
      g->osc[first + 6] == '/')
  {
    int i = first + 7;
    while (i < first + len && g->osc[i] != '/') i++;
    if (i >= first + len) { unsupported(g, RC_UN_OSC_OTHER); return; }
    len = first + len - i;
    first = i;
  }
  if (!path_is_legal(g->osc + first, len) || len > RC_TITLE_MAX) { unsupported(g, RC_UN_OSC_OTHER); return; }
  for (int i = 0; i < len; i++) g->carried.cwd[i] = g->osc[first + i];
  g->carried.nCwd = len;
}

static int osc_is_cwd7(int c)     { return c == 7; }

static int osc_is_title(int c)    { return c == 0 || c == 1 || c == 2; }
static int osc_is_palette(int c)  { return c == 4 || c == 10 || c == 11 || c == 104 || c == 110 || c == 111; }
static int osc_is_private9(int c) { return c == 9; }
static int osc_is_ftcs(int c)     { return c == 133; }
static int osc_is_bracket(int c)  { return c == 2004; }
static int osc_is_clip(int c)     { return c == 52; }

static const struct RcOscFamily rc_osc_families[] =
{
  { "ConEmu private 9",  osc_is_private9, osc_private9      },
  { "bracketed paste",   osc_is_bracket,  osc_bracket       },
  { "palette",           osc_is_palette,  palette_osc       },
  { "semantic prompt",   osc_is_ftcs,     osc_ftcs          },
  { "window title",      osc_is_title,    osc_title         },
  { "clipboard",         osc_is_clip,     osc_clip          },
  { "working directory", osc_is_cwd7,     osc_cwd7          },
};

int rc_osc_family_count(void) { return (int)(sizeof(rc_osc_families) / sizeof rc_osc_families[0]); }
const char *rc_osc_family_name(int i)
{ return (i >= 0 && i < rc_osc_family_count()) ? rc_osc_families[i].name : NULL; }
int rc_osc_family_owns(int i, int code)
{ return (i >= 0 && i < rc_osc_family_count()) ? rc_osc_families[i].owns(code) : 0; }

static void osc_finish(RcGrid *g, int terminated)
{
  const int kind = g->oscKind;
  g->oscKind = RC_OSC_NONE;
  if (kind == RC_OSC_DCS) { unsupported(g, RC_UN_DCS); return; }

  int sep = -1;
  const int code = osc_code_of(g, &sep);
  for (int i = 0; i < rc_osc_family_count(); i++)
  {
    if (!rc_osc_families[i].owns(code)) continue;
    rc_osc_families[i].apply(g, code, sep, terminated);
    return;
  }
  unsupported(g, RC_UN_OSC_OTHER);
}

static void cap_push(RcGrid *g, uint16_t u)
{
  if (g->nCap < RC_SGR_CAP_MAX) g->cap[g->nCap++] = u;
  else g->capLost = 1;
}

static void cap_begin(RcGrid *g, uint16_t esc)
{
  g->capLost = 0;
  g->cap[0] = esc;
  g->nCap = 1;
}

static void sgr_captured(RcGrid *g)
{
  if (g->capLost || g->nCap <= 0) { if (g->capLost) g->nSgrDrop++; return; }
  if (g->nSgrEcho + g->nCap > RC_SGR_ECHO_MAX) { g->nSgrDrop++; return; }
  for (int i = 0; i < g->nCap; i++) g->sgrEcho[g->nSgrEcho + i] = g->cap[i];
  g->nSgrEcho += g->nCap;
}

static int echoes(const RcGrid *g, uint8_t final)
{
  if (final == 'm') return !g->priv;
  if (final == 'p') return interim_is(g, '!') && !g->priv;
  return 0;
}

int rc_sgr_pending(const RcGrid *g) { return g->nSgrEcho; }

void rc_sgr_clear(RcGrid *g)
{
  if (g) g->nSgrEcho = 0;
}

int rc_sgr_take(RcGrid *g, uint16_t *dst, int cap)
{
  if (g->nSgrEcho == 0) return 0;
  if (!dst || cap < g->nSgrEcho) return -1;
  for (int i = 0; i < g->nSgrEcho; i++) dst[i] = g->sgrEcho[i];
  const int n = g->nSgrEcho;
  g->nSgrEcho = 0;
  return n;
}

int rc_clip_pending(const RcGrid *g) { return g->clipPending; }

int rc_clip_take(RcGrid *g, uint8_t *dst, int cap)
{
  if (!g->clipPending) return 0;
  if (!dst || cap < g->nClip) return -1;
  for (int i = 0; i < g->nClip; i++) dst[i] = g->clip[i];
  const int n = g->nClip;
  g->clipPending = 0;
  g->nClip = 0;
  return n;
}

int rc_title_pending(const RcGrid *g) { return g->titlePending; }

int rc_title_take(RcGrid *g, uint16_t *dst, int cap)
{
  if (!g->titlePending) return 0;
  if (!dst || cap < g->nOsc) return -1;
  for (int i = 0; i < g->nOsc; i++) dst[i] = g->osc[i];
  const int n = g->nOsc;
  g->titlePending = 0;
  return n;
}

int rc_report_pending(const RcGrid *g) { return g ? g->reportLen : 0; }

int rc_report_take(RcGrid *g, struct RcReportItem *out)
{
  if (!g || g->reportLen <= 0) return RC_REP_NONE;
  const struct RcReportItem head = g->report[g->reportHead];
  if (out) *out = head;
  const int kind = head.kind;
  g->reportHead = (g->reportHead + 1) % RC_REPORT_MAX;
  if (--g->reportLen == 0) g->reportHead = 0;
  return kind;
}

void rc_report_result(RcGrid *g, int written)
{
  if (!g) return;
  if (written) g->nReportOk++;
  else g->nReportFail++;
}

enum { RC_MACT_NONE = 0, RC_MACT_PRESS, RC_MACT_RELEASE, RC_MACT_MOTION,
       RC_MACT_WHEEL_UP, RC_MACT_WHEEL_DOWN, RC_MACT_WHEEL_LEFT, RC_MACT_WHEEL_RIGHT };

static int mouseLevel(const RcGrid *g)
{
  if (g->carried.mouseModes & mouseBit(1003)) return RC_ME_ANY;
  if (g->carried.mouseModes & mouseBit(1002)) return RC_ME_BUTTON;
  if (g->carried.mouseModes & mouseBit(1000)) return RC_ME_NORMAL;
  if (g->carried.mouseModes & mouseBit(9))    return RC_ME_X10;
  return RC_ME_NONE;
}

static int pressedButton(uint32_t state)
{
  if (state & RC_MS_LEFT) return 0;
  if (state & RC_MS_MIDDLE) return 1;
  if (state & RC_MS_RIGHT) return 2;
  return -1;
}

static int buttonBitToId(uint32_t bit)
{
  if (bit & RC_MS_LEFT) return 0;
  if (bit & RC_MS_MIDDLE) return 1;
  if (bit & RC_MS_RIGHT) return 2;
  return -1;
}

static int put_dec16(uint16_t *out, int cap, int v)
{
  char tmp[12];
  int n = 0;
  if (v < 0) v = 0;
  do {
    if (n >= (int)sizeof tmp) return -1;
    tmp[n++] = (char)('0' + (v % 10));
    v /= 10;
  } while (v);
  if (n > cap) return -1;
  for (int i = 0; i < n; i++) out[i] = (uint16_t)tmp[n - 1 - i];
  return n;
}

static int put_lit16(uint16_t *out, int cap, const char *s)
{
  int n = 0;
  while (s[n]) { if (n >= cap) return -1; out[n] = (uint16_t)(unsigned char)s[n]; n++; }
  return n;
}

int rc_mouse_report(RcGrid *g, const struct RcMouseRec *m, uint16_t *out, int cap)
{
  if (!g || !m) return 0;
  const int level = mouseLevel(g);
  const uint32_t st = m->buttonState;

  int action = RC_MACT_NONE, button = pressedButton(st);
  if (m->eventFlags & RC_MS_WHEELED)
    action = ((int16_t)((st >> 16) & 0xFFFFu) > 0) ? RC_MACT_WHEEL_UP : RC_MACT_WHEEL_DOWN;
  else if (m->eventFlags & RC_MS_HWHEELED)
    action = ((int16_t)((st >> 16) & 0xFFFFu) > 0) ? RC_MACT_WHEEL_RIGHT : RC_MACT_WHEEL_LEFT;
  else if (m->eventFlags & RC_MS_MOVED)
    action = RC_MACT_MOTION;
  else
  {
    const uint32_t down = st & ~g->carried.lastBtn, up = g->carried.lastBtn & ~st;
    if (down) { action = RC_MACT_PRESS; button = buttonBitToId(down); }
    else if (up) { action = RC_MACT_RELEASE; button = buttonBitToId(up); }
  }

  int n = 0;
  uint16_t tmp[40];
  const int room = (int)(sizeof tmp / sizeof tmp[0]);

  do {
    if (level == RC_ME_NONE) { g->nMouseQuiet++; break; }
    if (action == RC_MACT_NONE) break;

    if (level == RC_ME_X10 && (action != RC_MACT_PRESS || button < 0)) break;
    if (level == RC_ME_NORMAL && action == RC_MACT_MOTION) break;
    if (level == RC_ME_BUTTON && action == RC_MACT_MOTION && button < 0) break;

    if (action == RC_MACT_MOTION && g->moveSeen && g->carried.mouseFormat != RC_MF_SGR_PX &&
        m->x == g->lastMoveX && m->y == g->lastMoveY && button == (int)g->lastMoveBtn) break;

    if (m->x < 0 || m->y < 0) break;
    if (g->carried.mouseFormat != RC_MF_SGR && g->carried.mouseFormat != RC_MF_SGR_PX && g->carried.mouseFormat != RC_MF_UTF8 &&
        (m->x > 222 || m->y > 222)) break;

    if (g->carried.mouseFormat == RC_MF_SGR_PX && (m->px < 0 || m->py < 0)) break;

    int code;
    switch (action)
    {
      case RC_MACT_WHEEL_UP:    code = 64; break;
      case RC_MACT_WHEEL_DOWN:  code = 65; break;
      case RC_MACT_WHEEL_LEFT:  code = 66; break;
      case RC_MACT_WHEEL_RIGHT: code = 67; break;
      case RC_MACT_RELEASE:     code = (g->carried.mouseFormat == RC_MF_SGR ||
                                        g->carried.mouseFormat == RC_MF_SGR_PX) ? button : 3; break;
      default:                  code = button < 0 ? 3 : button; break;
    }
    if (action == RC_MACT_MOTION) code += 32;
    if (level != RC_ME_X10)
    {
      if (m->ctrlKeyState & RC_MS_SHIFT) code += 4;
      if (m->ctrlKeyState & RC_MS_ALT)   code += 8;
      if (m->ctrlKeyState & RC_MS_CTRL)  code += 16;
    }

    int t;
    if (g->carried.mouseFormat == RC_MF_SGR || g->carried.mouseFormat == RC_MF_SGR_PX)
    {
      n += put_lit16(tmp + n, room - n, "\x1b[<");
      const int cx = g->carried.mouseFormat == RC_MF_SGR_PX ? m->px : m->x + 1;
      const int cy = g->carried.mouseFormat == RC_MF_SGR_PX ? m->py : m->y + 1;
      if ((t = put_dec16(tmp + n, room - n, code)) < 0) { n = -1; break; } n += t;
      if ((t = put_lit16(tmp + n, room - n, ";")) < 0) { n = -1; break; } n += t;
      if ((t = put_dec16(tmp + n, room - n, cx)) < 0) { n = -1; break; } n += t;
      if ((t = put_lit16(tmp + n, room - n, ";")) < 0) { n = -1; break; } n += t;
      if ((t = put_dec16(tmp + n, room - n, cy)) < 0) { n = -1; break; } n += t;
      tmp[n++] = (action == RC_MACT_RELEASE) ? 'm' : 'M';
    }
    else if (g->carried.mouseFormat == RC_MF_URXVT)
    {
      n += put_lit16(tmp + n, room - n, "\x1b[");
      if ((t = put_dec16(tmp + n, room - n, 32 + code)) < 0) { n = -1; break; } n += t;
      if ((t = put_lit16(tmp + n, room - n, ";")) < 0) { n = -1; break; } n += t;
      if ((t = put_dec16(tmp + n, room - n, m->x + 1)) < 0) { n = -1; break; } n += t;
      if ((t = put_lit16(tmp + n, room - n, ";")) < 0) { n = -1; break; } n += t;
      if ((t = put_dec16(tmp + n, room - n, m->y + 1)) < 0) { n = -1; break; } n += t;
      tmp[n++] = 'M';
    }
    else
    {
      n += put_lit16(tmp + n, room - n, "\x1b[M");
      tmp[n++] = (uint16_t)(32 + code);
      if (g->carried.mouseFormat == RC_MF_UTF8)
      { tmp[n++] = (uint16_t)(33 + m->x); tmp[n++] = (uint16_t)(33 + m->y); }
      else { tmp[n++] = (uint16_t)(32 + m->x + 1); tmp[n++] = (uint16_t)(32 + m->y + 1); }
    }

    if (!out || n > cap) { n = -1; break; }
  } while (0);

  if (n >= 0) g->carried.lastBtn = st;
  if (n > 0)
  {
    for (int i = 0; i < n; i++) out[i] = tmp[i];
    if (action == RC_MACT_MOTION)
    {
      g->lastMoveX = m->x; g->lastMoveY = m->y; g->lastMoveBtn = (uint8_t)(button < 0 ? 3 : button);
      g->moveSeen = 1;
    }
    g->nMouseRep++;
  }
  return n;
}

int rc_focus_report(RcGrid *g, int focused, uint16_t *out, int cap)
{
  if (!g || !(g->carried.mouseModes & mouseBit(1004))) return 0;
  if (!out || cap < 3) return -1;
  out[0] = 0x1b; out[1] = '['; out[2] = focused ? 'I' : 'O';
  g->nFocusRep++;
  return 3;
}

void rc_report_counts(const RcGrid *g, unsigned long *out)
{
  if (!out) return;
  if (!g) { for (int i = 0; i < 5; i++) out[i] = 0; return; }
  out[0] = g->nMouseRep;
  out[1] = g->nFocusRep;
  out[2] = g->nMouseQuiet;
  out[3] = g->nInjectOk;
  out[4] = g->nInjectFail;
}

int rc_notify_geometry(RcGrid *g)
{
  if (!g) return 0;
  const int before = g->reportLen;
  arm_report(g, RC_REP_WINOP, g->winRows, g->cols, 0);
  return g->reportLen > before;
}

void rc_feed(RcGrid *g, const uint16_t *units, int n)
{
  int i = 0;
  while (i < n)
  {
    uint16_t u = units[i];

    switch (g->mode)
    {
      case RC_CSI:
      {
        if (u >= 0x30 && u <= 0x3F)
        {
          cap_push(g, u);
          if (u == ';')
          {
            push_arg(g, g->digit ? g->cur : 0, g->csiSub);
            g->digit = 0; g->cur = 0; g->csiSub = 0;
          }
          else if (u == ':')
          {
            push_arg(g, g->digit ? g->cur : -1, g->csiSub);
            g->digit = 0; g->cur = 0; g->csiSub = 1;
            g->csiColon = 1;
          }
          else if (u >= '0' && u <= '9')
          {
            g->digit = 1;
            g->cur = (g->cur > RC_ARG_MAX / 10) ? RC_ARG_MAX : g->cur * 10 + (u - '0');
          }
          else
            g->priv = u;
          i++;
          continue;
        }
        if (u >= 0x20 && u <= 0x2F)
        {
          cap_push(g, u);
          interim_push(g, (uint8_t)u);
          i++;
          continue;
        }
        if (u >= 0x40 && u <= 0x7E)
        {
          if (g->digit) push_arg(g, g->cur, g->csiSub);
          g->mode = RC_GROUND;
          cap_push(g, u);
          const int colon = g->csiColon, isSgr = ((uint8_t)u == 'm');
          if (colon && !isSgr) unsupported(g, RC_UN_COLON);
          else if (echoes(g, (uint8_t)u)) sgr_captured(g);
          if (!colon || isSgr) csi_dispatch(g, (uint8_t)u);
          i++;
          continue;
        }
        if (u == 0x18 || u == 0x1A) { g->mode = RC_GROUND; i++; continue; }
        g->mode = RC_GROUND;
        continue;
      }

      case RC_OSC:
      {
        if (u == 0x07) { osc_finish(g, 1); g->mode = RC_GROUND; i++; continue; }
        if (u == 0x1B) { g->mode = RC_OSC_ESC; i++; continue; }
        if (u == 0x18 || u == 0x1A) { osc_finish(g, 0); g->mode = RC_GROUND; i++; continue; }
        if (g->nOsc < RC_OSC_MAX) g->osc[g->nOsc++] = u;
        else g->oscClip = 1;
        i++;
        continue;
      }

      case RC_OSC_ESC:
        if (u == '\\') { osc_finish(g, 1); g->mode = RC_GROUND; i++; continue; }
        osc_finish(g, 0);
        g->mode = RC_ESC;
        cap_begin(g, 0x1B);
        continue;

      case RC_ESC:
      {
        if (u == '[') { cap_push(g, u); csi_start(g); i++; continue; }
        if (u == ']') { osc_start(g, RC_OSC_NONE); i++; continue; }
        if (u == 'P' || u == 'X' || u == '^' || u == '_') { osc_start(g, RC_OSC_DCS); i++; continue; }
        if (u == '(' || u == ')' || u == '*' || u == '+' || u == '~' || u == '%')
        { g->mode = RC_ESC_INTERIM; g->escInterim = u; i++; continue; }
        if (u == 'N' || u == 'O') { g->mode = RC_GROUND; i++; continue; }
        if (u >= 0x20 && u <= 0x2F) { g->mode = RC_ESC_INTERIM; g->escInterim = u; i++; continue; }
        if (u >= 0x30 && u <= 0x7E)
        {
          cap_push(g, u);
          if (u == 'c') sgr_captured(g);
          esc_dispatch(g, 0, (uint8_t)u);
          g->mode = RC_GROUND;
          i++;
          continue;
        }
        g->mode = RC_GROUND;
        continue;
      }

      case RC_ESC_INTERIM:
      {
        uint8_t intro = (uint8_t)g->escInterim;
        if (intro == '(' || intro == ')' || intro == '*' || intro == '+' || intro == '~' || intro == '%')
        {
          esc_charset(g, intro, (uint8_t)u);
          g->mode = RC_GROUND;
          i++;
          continue;
        }
        if (u >= 0x20 && u <= 0x2F) { g->escInterim = u; i++; continue; }
        g->mode = RC_GROUND;
        if (u >= 0x30 && u <= 0x7E) esc_dispatch(g, intro, (uint8_t)u);
        i++;
        continue;
      }

      default: break;
    }

    if (u == 0x1B) { cap_begin(g, u); g->mode = RC_ESC; i++; continue; }
    if (u < 0x20 || u == 0x7F) { control(g, u); i++; continue; }

    uint32_t cp;
    if (g->wantLow)
    {
      if (u >= 0xDC00 && u <= 0xDFFF)
      {
        uint16_t hi = (uint16_t)g->wantLow;
        g->wantLow = 0;
        put_cp(g, 0x10000u + (((uint32_t)hi - 0xD800u) << 10) + ((uint32_t)u - 0xDC00u));
        i++;
        continue;
      }
      g->wantLow = 0;
      put_cp(g, 0xFFFDu);
    }
    if (u >= 0xD800 && u <= 0xDBFF)
    {
      if (i + 1 < n && units[i + 1] >= 0xDC00 && units[i + 1] <= 0xDFFF)
      {
        put_cp(g, 0x10000u + (((uint32_t)u - 0xD800u) << 10)
                  + ((uint32_t)units[i + 1] - 0xDC00u));
        i += 2;
        continue;
      }
      g->wantLow = u;
      i++;
      continue;
    }
    cp = (u >= 0xDC00 && u <= 0xDFFF) ? 0xFFFDu : u;
    put_cp(g, cp);
    i++;
  }

}

void rc_tabs_widen(RcGrid *g, int from)
{
  tabs_default(g, from);
}

int rc_reset_hist(RcGrid *g, int cols, int winRows, int histRows, uint16_t defAttr)
{
  if (!g || cols <= 0 || winRows <= 0 || histRows < 0) return 0;
  free(g->snap);
  g->snap = NULL;
  if (cols > RC_MAX_COLS || winRows + histRows > RC_MAX_ROWS) return 0;
  memset(g, 0, sizeof(*g));
  g->cols = cols;
  g->rows = winRows + histRows;
  for (int r = 0; r < g->rows; r++) g->of[r] = r;
  g->winRows = winRows;
  g->cy = histRows;
  g->carried.defAttr = defAttr;
  g->defAttrSeed = defAttr;
  g->cursorVisible = 1;
  g->carried.wrapMode = 1;
  g->carried.insertMode = 0;
  g->carried.originMode = 0;
  g->carried.declrmm = 0;
  g->carried.bracketedPaste = 0;
  g->carried.cursorKeys = 0;
  g->carried.mouseModes = 0;
  g->carried.mouseFormat = RC_MF_X10;
  g->carried.lastBtn = 0; g->moveSeen = 0;
  g->lastMoveX = g->lastMoveY = 0; g->lastMoveBtn = 0;
  g->carried.inbandResize = 0;
  g->carried.marginSet = 0;
  g->carried.leftMargin = 0;
  g->carried.rightMargin = cols - 1;
  g->carried.saveOrigin = 0;
  tabs_reset(g);
  g->cursorShape = -1;
  g->lastUnit = ' ';
  g->carried.nTitle = -1;
  for (int k = 0; k < RC_TITLE_STACK; k++) g->carried.tstackLen[k] = -1;
  g->lastExit = -1;
  for (int i = 0; i < 256; i++) g->carried.palette[i] = RgbMap[i];
  for (int i = 0; i < 16; i++) g->carried.pal16[i] = (uint32_t)Far3Color::GetStdPalette()[i];
  sgr_reset(g, 1);
  for (int r = 0; r < g->rows; r++)
    for (int c = 0; c < cols; c++)
    {
      RC_CELLS(g, r)[c].ch = ' ';
      RC_CELLS(g, r)[c].attr = defAttr;
    }
  memset(g->cellProt, 0, sizeof g->cellProt);
  rc_clear_dirty(g);
  return 1;
}

int rc_reset(RcGrid *g, int cols, int rows, uint16_t defAttr)
{
  return rc_reset_hist(g, cols, rows, 0, defAttr);
}

int rc_scroll_room(const RcGrid *g)
{
  const int room = g->rows - g->winRows;
  return room > 0 ? room : 0;
}

int rc_in_alt(const RcGrid *g)
{
  return g ? g->alt : 0;
}

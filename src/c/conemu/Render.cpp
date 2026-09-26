/*
 * Render.cpp -- the console-free ANSI parser + grid model of the native ANSI renderer.
 *
 * Read Render.h first: it states which upstream each rule comes from and which two places we
 * deliberately part company with ConEmu. Everything below is either a transcription of measured
 * behaviour or a documented deviation; nothing here is a guess dressed up as code.
 *
 * Layout: widths, then the attribute fold, then grid operations, then SGR, then the sequence
 * dispatcher, then the resumable parser in rc_feed(). The painter in RenderJni.cpp only has to turn
 * dirty rows into WriteConsoleOutputW rectangles -- it holds no state of its own.
 */

#include "Render.h"

#include <algorithm>   /* std::max/min inside Far3Color */
#include <stdio.h>     /* snprintf, for the message rc_validate_grid writes on a violation */
#include <stdlib.h>    /* the alt screen's snapshot: malloc at the first entry (alt_screen) */
#include <string.h>

#include "HostTypes.h"
#include "../luauf8/ansi_width_tables.h"
#include "vendor/ConEmuColors3.h"    /* Far3Color folding, verbatim from ConEmu, BSD-3 notice intact */
#include "vendor/ConEmuRgbMap.h"     /* ClrMap[8] and RgbMap[256], generated verbatim from Ansi.cpp */

static_assert(sizeof(RgbMap) / sizeof(RgbMap[0]) == 256, "RgbMap excerpt is not 256 entries");
static_assert(sizeof(ClrMap) / sizeof(ClrMap[0]) == 8, "ClrMap excerpt is not 8 entries");

/* ---------------------------------------------------------------- widths --------------------- */

/*
 * One code point -> display columns. Copied from src/c/luauf8/ansi_width.c cp_width() rather than
 * shared through a header, because that file is the tested LuaJIT module and pulling its internals
 * out would churn a component nobody asked us to touch. RenderCheck.cpp pins the two against each
 * other over the whole range, so a fork in either copy is a build failure, not a subtle misalignment.
 *
 * The tables are generated from Unicode 15 with measured overrides (see the header of
 * ansi_width_tables.h); the jansi / JLine WCWidth family is explicitly not used here.
 */
int rc_width(uint32_t cp)
{
  uint32_t hi = cp >> 8;
  int8_t bw = (hi < ANSI_NBLK) ? ansi_blk_w[hi] : -1;
  if (bw >= 0) return (unsigned)bw;
  unsigned cw = 1;                              /* not listed -> width 1 */
  uint32_t k = (hi < ANSI_NBLK) ? ansi_blk_iv[hi] : 0;
  for (; k < ANSI_NWIV; k++)
  {
    if (ansi_wiv[k].first > cp) break;          /* passed cp -> not present */
    if (cp <= ansi_wiv[k].last) { cw = ansi_wiv[k].w; break; }
  }
  return (int)cw;
}

/* ESC ( 0 line drawing, Ansi.cpp:1113-1118: only 0x60..0x7E is remapped, everything else passes. */
static const uint16_t G0_DRAWING[31] = {
  0x2666, 0x2592, 0x2192, 0x21A8, 0x2190, 0x2193, 0x00B0, 0x00B1,
  0x00B6, 0x2195, 0x2518, 0x2510, 0x250C, 0x2514, 0x253C, 0x203E,
  0x207B, 0x2500, 0x208B, 0x005F, 0x251C, 0x2524, 0x2534, 0x252C,
  0x2502, 0x2264, 0x2265, 0x03C0, 0x2260, 0x00A3, 0x00B7
};

/* ------------------------------------------------------------- attributes ---------------------- */

/*
 * ReSetDisplayParm (Ansi.cpp:761-824) followed by ExtPrepareColor (ExtConsole.cpp:292-341), in that
 * order, because the order is the behaviour: the foreground nibble goes in first, and the background
 * is either ORed in directly or pushed through Far3Color::Color2BgIndex -- and only that second path
 * carries ConEmu's "never paint fg==bg" correction. Measured over 633 samples: skipping the gate
 * paints white-on-white for \e[48;5;145m on a default prompt, applying it unconditionally disagrees
 * with the fallback leg for \e[38;5;7m\e[48;5;7m.
 *
 * attr{} is zero-initialised upstream, so every "|=" there is an "=" here.
 */
/* Console attribute -> the index rc_attr's 4-bit paths expect. ClrMap is an involution, so this is the same
   table read the other way and the pair is an identity for all sixteen values. */
static int attr_to_index(int attr)
{
  return (int)(ClrMap[attr & 7] | (attr & 8));
}

uint16_t rc_attr(const RcGrid *g, const RcSgr *s)
{
  const uint32_t *pal = g->palette;   /* 256-colour indices the application may have rewritten (I34) */
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
    /* comes straight out of CONSOLE_SCREEN_BUFFER_INFO::wAttributes, so the bright bit is already there */
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
    /* The live palette is handed to the fold, and the vendored helper's memo has to be told about it:
       `static LastColor/LastIndex` caches the previous answer by colour alone, so without the guard a colour
       folded before an OSC 4 keeps folding to the index it had before the change. */
    Far3Color::Color2FgIndex(nForeColor, n, (const COLORREF*)g->pal16);
  }
  else
  {
    n |= (WORD)(fg & 0xF);      /* CONCOLORINDEX */
  }

  if (bg24)
  {
    DWORD nBackColor = bg & 0xFFFFFF;
    /* Equal is passed upstream but never read inside Color2BgIndex; kept for fidelity. */
    Far3Color::Color2BgIndex(nBackColor, nBackColor == nForeColor ? TRUE : FALSE, n, (const COLORREF*)g->pal16);
  }
  else
  {
    n |= (WORD)((bg & 0xF) << 4);
  }

  if (s->underline) n |= RC_LVB_UNDERSCORE;
  if (s->inverse)   n |= RC_LVB_REVERSE;
  return n;
}

/* ----------------------------------------------------------- grid primitives ------------------- */

/* Damage is a column range, not just a row flag: the rectangle that reaches conhost costs one cell write
 * per column, and a status line that redraws one character of a 2000-column buffer row must not pay for
 * 1999 others. The range is a union, so widening it is always safe. The risk is the mirror image -- a
 * writer that moves cells without saying so now goes unseen instead of being covered by the whole-row
 * flag -- which is why every caller that cannot name its columns (an adopt, IL/DL, a row that scrolled
 * in blank) says the whole row, and why `mark_row_dirty` exists next to this. */
static void mark_dirty(RcGrid *g, int row, int from, int to)
{
  if (row < 0 || row >= g->rows) return;
  if (from < 0) from = 0;
  if (to > g->cols - 1) to = g->cols - 1;
  if (from > to) return;                       /* nothing inside the row: nothing to repaint */
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

/* The whole row, for a change that moved cells wherever it liked. */
static void mark_row_dirty(RcGrid *g, int row)
{
  mark_dirty(g, row, 0, g->cols - 1);
}

/* First model row of the viewport: everything above it is the gutter, i.e. scrollback this chunk has
 * written but not painted. Zero when the model has no gutter, which is what every host test uses. */
static int gutter(const RcGrid *g)
{
  return g->rows - g->winRows;
}

void rc_mark_all_dirty(RcGrid *g)
{
  /* Only the viewport: the gutter above it holds content this model has not been told about (align()
     adopts the window, never the scrollback), and painting it would blank the user's history. */
  for (int r = gutter(g); r < g->rows; r++) mark_row_dirty(g, r);
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

/* align() reads cells, and neither of a row's private claims is a cell: ReadConsoleOutputW carries no wrap
   information and no semantic mark either (MSFT_TERMINAL_REFERENCE \u00a75). A claim left behind an adopt is
   worse than no claim -- it would describe content that is no longer there -- so an adopt drops both for
   the rows it replaced. Renamed from rc_forget_wrap for that reason: it was never only about the wrap. */
void rc_forget_row_state(RcGrid *g)
{
  const RcRowState clean = RC_ROW_CLEAN;
  for (int r = gutter(g); r < g->rows; r++) RC_ST(g, r) = clean;
}

int rc_row_mark(const RcGrid *g, int row)
{
  return (row >= 0 && row < g->rows) ? (int)RC_ST(g, row).mark : (int)RC_PM_NONE;
}

/* The column the row's mark was made at -- the prompt's own start, which is what a consumer that wants to
   select "this command" needs: after a scroll the row may carry output text to the left of the mark, and
   taking the whole row would take that too. */
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

/* The model's own invariants, read back over the live part of the grid. See Render.h: this is a witness and
 * not a guard -- no production path calls it, and it repairs nothing. Every check below is a property the
 * rest of this file *claims* to maintain, so a violation is either a real defect or a claim that was never
 * true; both are worth a line of text instead of a screen that quietly looks wrong.
 * The list is deliberately conservative -- only what the code guarantees today. A cursor resting on a
 * trailing half is NOT on the list: `step_back_col` keeps a leftward move off a glyph, but a CUP may name any
 * column and MSFT's `SetXPosition` does not refuse one either, so "the cursor never rests inside a glyph" is
 * a rule about moves, not about positions. */
int rc_validate_grid(const RcGrid *g, char *msg, int len)
{
  int r, c;
  msg[0] = '\0';

#define RC_BAD(...) do { snprintf(msg, (size_t) len, __VA_ARGS__); return 1; } while (0)

  if (g->cols < 1 || g->cols > RC_MAX_COLS) RC_BAD("cols=%d outside 1..%d", g->cols, RC_MAX_COLS);
  if (g->rows < 1 || g->rows > RC_MAX_ROWS) RC_BAD("rows=%d outside 1..%d", g->rows, RC_MAX_ROWS);
  if (g->winRows < 1 || g->winRows > g->rows) RC_BAD("winRows=%d outside 1..rows(%d)", g->winRows, g->rows);
  if (g->cx < 0 || g->cx >= g->cols) RC_BAD("cursor column %d outside 0..%d", g->cx, g->cols - 1);
  /* The cursor addresses the viewport, never the gutter: a row above it is unpainted history, and a painter
     that addressed one would write to rows it has no plan for. */
  if (g->cy < g->rows - g->winRows || g->cy >= g->rows)
    RC_BAD("cursor row %d outside the viewport %d..%d", g->cy, g->rows - g->winRows, g->rows - 1);
  if (g->saveX < 0 || g->saveX >= g->cols) RC_BAD("saved column %d outside 0..%d", g->saveX, g->cols - 1);
  if (g->saveY < 0 || g->saveY >= g->rows) RC_BAD("saved row %d outside 0..%d", g->saveY, g->rows - 1);
  if (g->regSet && !(g->regTop >= 0 && g->regTop <= g->regBot && g->regBot < g->rows))
    RC_BAD("region %d..%d is not an ordered span inside 0..%d", g->regTop, g->regBot, g->rows - 1);
  if (g->nInterims < 0 || g->nInterims > RC_INTERIM_MAX)
    RC_BAD("nInterims=%d outside 0..%d", g->nInterims, RC_INTERIM_MAX);
  if (g->charset != 0 && g->charset != 1) RC_BAD("charset=%d is neither VTCS_DEFAULT nor VTCS_DRAWING", g->charset);
  if (g->cursorVisible != 0 && g->cursorVisible != 1) RC_BAD("cursorVisible=%d", g->cursorVisible);
  if (g->semanticContent < RC_SC_OUTPUT || g->semanticContent > RC_SC_PROMPT)
    RC_BAD("semanticContent=%d outside RC_SC_OUTPUT..RC_SC_PROMPT", g->semanticContent);

  /* The table is a claim per column, so it is only meaningful below the width -- and a stale 1 past the
     * edge is not a violation, which is why this checks the values and not the reach. */
  if (g->tabsDefaults != 0 && g->tabsDefaults != 1)
    RC_BAD("tabsDefaults=%d is neither claimed nor not", g->tabsDefaults);
  for (c = 0; c < g->cols; c++)
    if (g->tabStop[c] > 1) RC_BAD("tab stop %d holds %u, not a bit", c, (unsigned) g->tabStop[c]);

  /* #75's own invariant, and the one thing a rotation can break: the model's row order has to be a
   * permutation of the pool. A shift that drops a row, double-books one, or names a pool row past the
   * model's height is invisible here and obvious on the screen -- two model rows reading the same storage
   * paints one line twice and loses another, which is the same class of wrong as an orphaned glyph half
   * and just as unremarkable to anything downstream. The oracle exists for exactly this (its own comment
   * says a broken model reads as a wrong answer rather than a broken model), and this is why #72 was
   * scheduled before #75 rather than after it. */
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
      /* A dirty row has to name a range that exists. The rectangle the painter sends is cut from these two
         numbers, so an empty or out-of-range pair is a row that is either never repainted or painted past
         the model's own width. */
      if (RC_LO(g, r) > RC_HI(g, r))
        RC_BAD("row %d: dirty range %u..%u is inverted", r, RC_LO(g, r), RC_HI(g, r));
      if (RC_HI(g, r) >= g->cols)
        RC_BAD("row %d: dirty range %u..%u reaches past the %d-column row", r, RC_LO(g, r), RC_HI(g, r), g->cols);
    }
    /* I16, over every row of the grid rather than only the ones an edit just touched. */
    for (c = 0; c < g->cols; c++)
    {
      const uint16_t a = RC_CELLS(g, r)[c].attr;
      if (a & RC_LVB_LEADING)
      {
        if (c + 1 >= g->cols || !(RC_CELLS(g, r)[c + 1].attr & RC_LVB_TRAILING))
          RC_BAD("row %d column %d: a LEADING U+%x with no trailing half beside it",
                 r, c, RC_CELLS(g, r)[c].ch);
        c++;                                    /* the pair is one unit; do not re-read its tail */
      }
      else if (a & RC_LVB_TRAILING)
        RC_BAD("row %d column %d: a TRAILING half whose LEADING is gone", r, c);
    }
  }
#undef RC_BAD
  return 0;
}

/* I16 as a property of the grid rather than a hope: no cell may claim to be half of a 2-column glyph whose
 * other half is somewhere else. The two flags are enough to decide it from the cells alone -- a LEADING
 * wants a TRAILING to its right, a TRAILING wants a LEADING to its left -- and a glyph is at most two
 * columns, so one pass with no back-tracking is stable: blanking an orphan can only ever act on a cell
 * whose partner was already wrong, never on a valid pair.
 * This is the rule ghostty enforces by refusing to start or end an edit inside a glyph (clearCells over
 * the whole pair at each boundary, Terminal.zig:3322-3342 and :3448-3452, with `assertIntegrity()` rejecting
 * a spacer tail that does not follow its wide head, page.zig:518-540). It is enforced here after the edit
 * instead of before it because the erases and the shifts here move cells, not glyphs: repairing the two
 * boundary cells costs the same as predicting them, and it also covers a shift that dragged a half away
 * from its own pair. A blanked cell is a blank in the live attribute, exactly like the erase that reached
 * it. Returns nothing; the damage it marks is its own, so a healed cell can never stay painted. */
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

/* The attribute is written verbatim, not merged with what was there: that is also what destroys a wide
 * glyph's LEADING/TRAILING half under an erase. What an erase may not do is leave the *other* half
 * standing, so the heal runs over the two cells flanking the span (I16). */
static void fill_span(RcGrid *g, int row, int from, int to, uint16_t attr)
{
  if (row < 0 || row >= g->rows) return;
  if (from < 0) from = 0;
  if (to >= g->cols) to = g->cols - 1;
  for (int c = from; c <= to; c++)
  {
    RC_CELLS(g, row)[c].ch = ' ';
    RC_CELLS(g, row)[c].attr = attr;
  }
  /* An erase that reaches the margin ends the row's claim to have overflowed: nothing ran off its right
     edge any more, whatever was there before. Erases short of the margin leave the claim alone. */
  if (to >= g->cols - 1) RC_ST(g, row).wrap = RC_WRAP_NONE;
  mark_dirty(g, row, from, to);
  heal_pairs(g, row, from - 1, to + 1);
}

/* Erases `from` to the end of the model row. A model row is the whole console row -- cols is dwSize.X
 * less the window's left edge -- so an erase that stops at "the end of the line" is already ConEmu's
 * EL/ED behaviour of erasing to dwSize.X, and no second width needs to be tracked. */
static void fill_row(RcGrid *g, int row, int from, uint16_t attr)
{
  fill_span(g, row, from, g->cols - 1, attr);
}

/* A row that arrived blank knows nothing: it overflowed nowhere and no command started on it.
   `rotate_span` is why this is the only per-row bookkeeping a vertical move needs any more: the row's own
   claims (I20's wrap, I23's mark and its column) and its damage range are indexed through the row order, so
   a move carries them by identity instead of by a call somebody has to remember. Build -25's #5 was a carry
   here moving two of three fields and -27 made the carry one statement; #75 removed it. The reason the three
   are one struct stays where the shape is: Render.h's RcRowState comment. */
static void row_reset_state(RcGrid *g, int row)
{
  const RcRowState clean = RC_ROW_CLEAN;
  RC_ST(g, row) = clean;
}

/* What a line ending does to the FTCS claims the cursor is carrying (I23). Both references put this on the
 * row rather than on the sequence: ghostty's `index()` runs a defer that either returns the cursor to output
 * -- when the input was the `I` kind, whose whole difference from `B` is that it ends at line feed -- or
 * stamps the row the cursor arrived on as a prompt continuation (Terminal.zig:2330-2357). It exists because
 * shells that do emit 133 do not always emit `k=c` for their continuation lines, and a jump-to-prompt that
 * cannot see them is wrong on fish. MSFT gets the same screen by a different road, `_createPromptMarkIfNeeded`
 * (textBuffer.cpp:3441), which needs a scan of earlier marks this model does not keep.
 *
 * This runs from line_down(), so it covers LF, IND, NEL *and* the two wrap paths. ghostty separates the last
 * one (its printWrap promotes a row only for content that was `.prompt`, never for `.input`,
 * Terminal.zig:1773-1792) and this model does not, because without per-cell content there is nothing to tell
 * a wrapped prompt row from a wrapped input row -- and a wrapped line *is* a continuation line either way. */
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

/* The rows a scroll can reach, and the rows a relative cursor move is clipped to: the DECSTBM region when
 * one is set, the viewport otherwise. Both bounds
 * are inclusive model rows, and `regTop`/`regBot` are clamped to the viewport when they are set, so this
 * never hands a caller a gutter row. */
static void region(const RcGrid *g, int *top, int *bot)
{
  *top = g->regSet ? g->regTop : gutter(g);
  *bot = g->regSet ? g->regBot : g->rows - 1;
}

/* The one primitive every vertical move is made of: relabel which pool row sits at which model row, inside
 * [from, from+span), by `n`. Content moving *up* pulls the rows below it up and hands the rows that left the
 * span's bottom to its top; moving *down* is the mirror. Either way the span stays a permutation of the pool
 * -- which is what `rc_validate_grid` now insists on -- and no cell is copied.
 *
 * This is #75, and the price that bought it: at a 2000-column buffer and a 128-row window, the row-by-row
 * `memcpy` this replaces was 99.7 us of a 104.7 us line feed (`RowBench.cpp`, whose table is in
 * DESIGN.md section 5). The rotation is
 * 24 ns for the same 255 rows.
 *
 * What comes free with it is the part that matters for correctness: the row's own claims and its damage
 * range are indexed through the same order, so they travel with the content by identity rather than by a
 * carry call somebody has to remember. Build -25's #5 was `shift_region` carrying `wrap` and `mark` and
 * leaving a live `col` behind, and -27's fix was to make the carry one statement; this removes the statement.
 * ghostty is one step ahead of us here for the same reason it packs a row into one `u64` (`Row` at
 * page.zig:2014): its page *is* a list of row slots, and `scrollUp` rotates them (PageList.zig:5252's
 * recycling is what our `row_reset_state` on the incoming rows mirrors). */
static void rotate_span(RcGrid *g, int from, int span, int n, int down)
{
  int tmp[RC_MAX_ROWS];
  if (n <= 0 || span <= 0) return;
  if (n > span) n = span;
  memcpy(tmp, &g->of[from], (size_t)span * sizeof tmp[0]);
  for (int k = 0; k < span; k++)
    g->of[from + k] = down ? tmp[(k - n + span) % span] : tmp[(k + n) % span];
}

/* Shifts rows [top..bot] by n, up or down, filling the rows the content left behind at the live
 * attribute. Unlike scroll_up() this never touches the gutter or the console window: a region smaller
 * than the viewport has no console scroll to ask for, and the only way to show it is to repaint the
 * rows it moved. So the damage is the whole region, including the rows that merely changed number --
 * a row that was clean and moved is still a change on the screen. */
static void shift_region(RcGrid *g, int n, int top, int bot, int down)
{
  if (n <= 0) return;
  const int span = bot - top + 1;
  if (n > span) n = span;
  rotate_span(g, top, span, n, down);
  if (down) for (int r = top; r < top + n; r++) fill_row(g, r, 0, g->attr);
  else      for (int r = bot - n + 1; r <= bot; r++) fill_row(g, r, 0, g->attr);
  /* fill_row clears a row's wrap claim only when the erase reaches the margin, which a narrowed region
     does not have to: rows below the region still wrap at the buffer's right edge. So every row this shift
     blanked has its own state dropped -- the claim, the semantic mark, *and* the column that mark was made
     at, which is the third field of the triple and the one `rc_mark_col()` hands to a consumer that wants
     to select "this command". ghostty found the same shape in its own recycler and fixed it wholesale:
     "fully reset row metadata when recycling row storage", with `resetRow` clearing cells *and*
     `row.reset()` (PageList.zig:5252 -> Page.zig:1307). */
  if (down) for (int r = top; r < top + n; r++) row_reset_state(g, r);
  else      for (int r = bot - n + 1; r <= bot; r++) row_reset_state(g, r);
  for (int r = top; r <= bot; r++) mark_row_dirty(g, r);
  g->nScrolls += (unsigned long)n;
}

/* The viewport scrolls up by n; the vacated rows are blank in the current attribute, which is what
 * ScrollConsoleScreenInfo does when the caller passes the live console attribute (as the shipped
 * Java writer has always done).
 *
 * The damage overlay and the row's own claims travel with the content by identity now, which is the whole
 * point of rotating rather than copying: a chunk that writes a row and then scrolls (three lines flushed at
 * once, a dashboard frame that runs off the bottom) leaves those writes n rows higher, and a flag left
 * behind at the old row would paint the wrong one -- the new rows would look right in the model and be blank
 * on screen. The columns ride with the row too: a status line that damaged columns 40..59 moves up and still
 * needs only those twenty columns repainted, wherever it now is. A row that arrives at a new number claiming
 * no damage paints nothing and keeps the stale screen. Two hand-written carries used to be responsible for
 * that, `scroll_carry` for the overlay and `row_carry` for the claims, and -25's #5 is what happens when one
 * of them is half a statement. */
static void scroll_up(RcGrid *g, int n)
{
  if (n <= 0) return;
  if (g->alt)
  {
    /* The alt screen has no scrollback, and its rows are the viewport's: the line that leaves its top is
       gone for good, and *nothing above the viewport moves*, because the gutter belongs to the main screen
       and is still wanted when this one is left. So this shift stops at gutter(), where every other scroll
       starts at row 0 -- a full-model shift here carries alt content into the rows the painter maps above
       the window, and a program's first screenful prints itself over the user's history. (Live witness:
       Render.java "the alt's blanking stopped at the window", with a 30-row gutter over a window two rows
       from the top of the buffer.)
       Nothing may be spent on a window slide or a buffer scroll either (Paint.cpp rule 1) -- both would
       drag the user's view through the real buffer to make room for a screen that is about to be blanked.
       The rows still have to be blanked and their wrap claims dropped, exactly as on the main screen, or the
       bottom row keeps a duplicate of the line that scrolled out of it; and the damage overlay is not
       enough, because a row that was *clean* and merely moved is still a change on a screen nobody scrolled.
       So the whole viewport goes dirty and the caller repaints it. */
    const int top = gutter(g);
    if (n > g->winRows) n = g->winRows;
    rotate_span(g, top, g->rows - top, n, 0);
    for (int r = g->rows - n; r < g->rows; r++)
    {
      fill_row(g, r, 0, g->attr);                 /* also clears the row's wrap claim, at the margin */
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
  /* The n rows that arrive at the bottom are pool rows that left the top, so they need everything: cells
     blank in the live attribute, the wrap claim and the semantic mark dropped (a row that scrolls in from
     the gutter arrived blank, whatever it held before), and a damage claim, because a row coming into the
     viewport is a row nobody has painted there. */
  for (int r = g->rows - n; r < g->rows; r++)
  {
    mark_row_dirty(g, r);                         /* rows that came into the viewport are unknown */
    row_reset_state(g, r);
    for (int c = 0; c < g->cols; c++)
    {
      RC_CELLS(g, r)[c].ch = ' ';
      RC_CELLS(g, r)[c].attr = g->attr;
    }
  }
  /* The grid is consistent at this point and the input is not: ask for a paint now rather than let the
     next line's text fall off the top of the gutter, where nothing can recover it. */
  const int room = rc_scroll_room(g);
  if (g->onFlush && room > 0 && g->pendingScrolls >= room) g->onFlush(g->flushCtx);
}

static void line_down(RcGrid *g)
{
  int top, bot;
  region(g, &top, &bot);
  /* A cursor below the region's bottom margin walks down and scrolls nothing -- the row it lands on is
     the caller's own business, not the region's. MSFT's `_DoLineFeed` takes this branch for any row
     `!= bottomMargin` and clamps to the page bottom (adaptDispatch.cpp:2443-2453). ConEmu agrees by
     construction rather than by intent: `workRgn` there is the *buffer* (Ansi.cpp:2897) and only `clipRgn`
     is the region (:2880-2886), and set_y's relative-down arm clamps to the region solely while the cursor
     is inside it -- from above the region (:2913-2914) or from below it (:2917-2918) the bound is workRgn,
     i.e. the buffer. So `set_y` cannot say what a cursor below the bottom margin should do; our viewport
     clamp is the nearest statement of the same non-scroll, and it is what move_row() at :742 already does
     for a relative move. It is not a corner case here: a status bar is exactly this cursor, because the bar
     occupies the rows the region gave up. Scrolling instead -- the previous reading of `cy < bot` --
     collapsed a two-row bar onto one row and rotated the session's text away once per newline.
     RenderCheck.cpp's status_bar() pins the pair. The clamp is the viewport's last row -- `clxy` would say
     the same but is defined below, and this file keeps its order one-way. */
  if (g->cy > bot) { if (g->cy < g->rows - 1) g->cy++; }
  else if (g->cy < bot) g->cy++;
  else
  /* A region that is the viewport is not a region at all: the whole-model shift below is what carries
     unpainted history out of the gutter and asks for the console scroll (pendingScrolls, rc_scroll_room),
     and a chunk longer than the window still has to run through it. Only a region narrower than the
     viewport is scrolled on its own, and then the rows outside it hold what they hold. */
  if (top == gutter(g) && bot == g->rows - 1) scroll_up(g, 1);
  else shift_region(g, 1, top, bot, 0);
  ftcs_line_ended(g);
}

/* LF, and only LF: conhost folds the column too. Measured, not read -- ConEmu hands the newline to
 * WriteConsoleW, so whatever ExtWriteText believes, the console is what the shipped writer and a live
 * session both agree on ("ab\ncd" through WriteConsoleW puts 'c' at column 0 of the next row). IND and
 * RI keep the column, which is why they call line_down() and not this. */
static void newline(RcGrid *g)
{
  g->cx = 0;
  line_down(g);
}

/* One cell back to the pen, with no erase of its own and no claim taken off the row. The wrap rules below
   need it twice: "this glyph was not drawn, so nothing may stand here". */
static void blank_cell(RcGrid *g, int row, int col)
{
  if (row < 0 || row >= g->rows || col < 0 || col >= g->cols) return;
  RC_CELLS(g, row)[col].ch = ' ';
  RC_CELLS(g, row)[col].attr = g->attr;
  mark_dirty(g, row, col, col);
  heal_pairs(g, row, col - 1, col + 1);   /* and take the half it just orphaned with it (I16) */
}

/* The column a cursor pinned at the right margin rests on, off a wide glyph's back half. `step_back_col`
   is the same rule and cannot be reused: it works from the current cursor. */
static int last_free_col(const RcGrid *g, int row, int col)
{
  if (col > 0 && (RC_CELLS(g, row)[col].attr & RC_LVB_TRAILING)) col--;
  return col < 0 ? 0 : col;
}

static void put_cell(RcGrid *g, uint16_t ch, int w)
{
  if (w <= 0) return;            /* Mn/Me/Cf and the C0 range contribute no cell */
  if (w > 2) w = 2;

  if (g->cx + w > g->cols)
  {
    if (!g->wrapMode)
    {
      /* DECAWM off: the margin ends the line, so a 2-column glyph with one column left is not drawn at
         all. Both references drop it whole rather than split it -- MSFT clears the cell it could not fit
         (`Row.cpp:474-481`, "Ignore the character. There's no correct alternative way to handle this
         situation") and its anti-deadlock guard names the same case for wrap off
         (MSFT_TERMINAL_REFERENCE.md section 2.1). Clearing that cell, rather than leaving whatever was there
         before, is what keeps the row honest: the glyph is gone, and a stale character would read as
         content the application never sent. */
      if (w == 2) blank_cell(g, g->cy, g->cx);
      return;
    }
    /* conhost with ENABLE_WRAP_AT_EOL moves to the next row the moment the last column is filled,
       so a 2-column glyph that does not fit starts the next row whole (JLine's columnSplitLength
       agrees). The shipped Java writer declines this case and hands it to ConEmuHk instead; here it
       is a wrap, because nothing can be declined once one parser owns the stream.

       The row left behind keeps its own reason: it did not overflow, its last glyph was moved whole to
       spare it a split (conhost's _doubleBytePadded). Copy and export join the two differently. */
    RC_ST(g, g->cy).wrap = RC_WRAP_PAD;
    g->cx = 0;
    line_down(g);
  }

  RC_CELLS(g, g->cy)[g->cx].ch = ch;
  RC_CELLS(g, g->cy)[g->cx].attr = (uint16_t)(g->attr | (w == 2 ? RC_LVB_LEADING : 0));
  if (w == 2)
  {
    RC_CELLS(g, g->cy)[g->cx + 1].ch = ch;
    RC_CELLS(g, g->cy)[g->cx + 1].attr = (uint16_t)(g->attr | RC_LVB_TRAILING);
  }
  mark_dirty(g, g->cy, g->cx, g->cx + w - 1);
  /* The pair is a unit (I16): overwrite its front and the back is no longer anybody's glyph, and overwrite
     its back and the front has nothing to be the front of. One rule in both directions, checked on the two
     cells flanking the write -- which is also the only way to catch the case where the cursor got onto a
     half by CUP or DECRC rather than by a backward move, since those name a column and do not adjust it. */
  heal_pairs(g, g->cy, g->cx - 1, g->cx + w);
  g->nCells += (unsigned long)w;
  g->cx += w;

  if (g->cx >= g->cols)
  {
    if (!g->wrapMode)
    {
      /* Held at the margin, and no wrap claim: nothing ran off the edge, so copy and export must not join
         this row to the next. The cursor keeps its column, which is the whole point -- the application
         asked for a line that ends here, and a fixed-width status line overwrites this cell from now on. */
      g->cx = last_free_col(g, g->cy, g->cols - 1);
      return;
    }
    RC_ST(g, g->cy).wrap = RC_WRAP_FORCED;   /* text reached the margin and continued on the next row */
    g->cx = 0;
    line_down(g);
  }
}

/*
 * An astral code point reaches the console as the UTF-16 pair that represents it, because a
 * CHAR_INFO cell holds one WCHAR. A wide glyph therefore occupies its two columns as
 * LEADING(half) TRAILING(half), which is the same two-cell convention CJK already uses; a narrow one
 * takes two ordinary cells. What conhost actually does with a surrogate pair on a legacy console is
 * not something I will assert from reading -- RenderCheck counts these (nAstral) and the grid witness
 * on the Win7 console decides whether the rule stands.
 */
static void put_pair(RcGrid *g, uint16_t hi, uint16_t lo, int w)
{
  g->nAstral++;
  if (w >= 2)
  {
    if (g->cx + 2 > g->cols)
    {
      if (!g->wrapMode) { blank_cell(g, g->cy, g->cx); return; }   /* drop whole, as put_cell does (I35) */
      RC_ST(g, g->cy).wrap = RC_WRAP_PAD; g->cx = 0; line_down(g);
    }
    RC_CELLS(g, g->cy)[g->cx].ch = hi;
    RC_CELLS(g, g->cy)[g->cx].attr = (uint16_t)(g->attr | RC_LVB_LEADING);
    RC_CELLS(g, g->cy)[g->cx + 1].ch = lo;
    RC_CELLS(g, g->cy)[g->cx + 1].attr = (uint16_t)(g->attr | RC_LVB_TRAILING);
    mark_dirty(g, g->cy, g->cx, g->cx + 1);
    heal_pairs(g, g->cy, g->cx - 1, g->cx + 2);   /* the same unit rule as put_cell, for the same reason */
    g->nCells += 2;
    g->cx += 2;
    if (g->cx >= g->cols)
    {
      if (!g->wrapMode) { g->cx = last_free_col(g, g->cy, g->cols - 1); return; }
      RC_ST(g, g->cy).wrap = RC_WRAP_FORCED; g->cx = 0; line_down(g);
    }
    return;
  }
  /* Two columns of a different kind: half a surrogate pair is not a character either, so with the margin
     one column away the pair is dropped as a unit rather than written as one lone high surrogate. */
  if (!g->wrapMode && g->cx + 2 > g->cols) { blank_cell(g, g->cy, g->cx); return; }
  put_cell(g, hi, 1);
  put_cell(g, lo, 1);
}

/* One code point written to the grid -- the ground path's whole text job, factored out so REP can replay
   it. Two rules make this a function rather than a call to put_cell:
   - the charset remap applies to the *glyph*, while the code point that was asked for is what `lastUnit`
     remembers. ConEmu does the same thing by accident of ordering: WriteText stores `lpBuffer[n-1]`
     (Ansi.cpp:1098-1099) and only then maps through mCharSet (:1111), so `ESC ( 0` + a letter + `CSI b`
     repeats the letter and draws the line glyph. Storing the mapped glyph instead would make a repeat
     after drawing mode print a box character.
   - `lastUnit` is a code point, not a UTF-16 unit. Upstream's m_LastWrittenChar is a wchar_t and so can
     only ever hold half of an astral character; repeating it writes that half twice. We keep the whole
     character, which is the difference between two broken halves and one correct wide cell.
   Neither rule changes what the *console* sees for the sequences a real application actually sends, so both are
   recorded rather than argued about (CONEMU_ANSI_DEFECTS.md, REP). */
static void put_cp(RcGrid *g, uint32_t cp)
{
  /* A third rule makes this a function rather than a call to put_cell: what REP replays is the last
     character that *occupied a cell*. A combining mark, a ZWSP or a C1 control claims none -- put_cell drops
     it with `w <= 0` -- so remembering it would turn `A` + U+0301 + `CSI 3b` into three columns of nothing,
     which is what ghostty avoids by assigning `previous_char` only in its printable arm, after the
     width==0 branch has already returned (Terminal.zig:1469 -> :1515). */
  if (rc_width(cp) > 0) g->lastUnit = cp;
  if (cp > 0xFFFFu)
  {
    const uint32_t v = cp - 0x10000u;
    put_pair(g, (uint16_t)(0xD800u + (v >> 10)), (uint16_t)(0xDC00u + (v & 0x3FFu)), rc_width(cp));
    return;
  }
  uint16_t glyph = (uint16_t)cp;
  if (g->charset && cp >= 0x60 && cp < 0x7F) glyph = G0_DRAWING[cp - 0x60];
  put_cell(g, glyph, rc_width(cp));
}

/* ------------------------------------------------------------------- SGR ---------------------- */

static void sgr_reset(RcGrid *g, int keep_underline)
{
  RcSgr *s = &g->sgr;
  memset(s, 0, sizeof(*s));
  /* DisplayParm::Reset (Ansi.cpp:562-571) zeroes the struct and then seeds the two colours from the
     *frozen* default -- not from the live console attribute, which is what the fallback leg would
     have shown. The underscore bit therefore comes back false, unconditionally. */
  /* `defAttr` is a console *attribute* -- it is what `csbi.wAttributes` said, and rc_reset_hist fills the
     cells with it -- while these two slots are *indices*: rc_attr turns an index back into an attribute
     through ClrMap. Seeding one with the other therefore converts twice, and because ClrMap is its own
     inverse ({0,4,2,6,1,5,3,7}) the double conversion is only invisible for the palindromic entries. With a
     profile whose default foreground is FORE_BLUE (attribute 1) the pen came back red (4) while the cells the
     same reset had just filled were blue, so the model disagreed with itself before anything was written.
     Converting on the way in makes the round trip an identity for all sixteen values. */
  s->fg = attr_to_index(g->defAttr & 0x0F);
  s->bg = attr_to_index((g->defAttr >> 4) & 0x0F);
  s->seeded = 1;
  if (keep_underline) s->underline = (g->defAttr & RC_LVB_UNDERSCORE) ? 1 : 0;
  g->attr = rc_attr(g, s);
}

/* ConEmu stores SGR 39/49 as "the default colour", in the 4-bit space, from the frozen default. */
static void sgr_default_fg(RcGrid *g)
{
  g->sgr.fg = attr_to_index(g->defAttr & 0x0F);   /* the same index/attribute round trip as sgr_reset */
  g->sgr.fgKind = RC_CLR4B;
  g->sgr.brightFore = 0;
}

static void sgr_default_bg(RcGrid *g)
{
  g->sgr.bg = attr_to_index((g->defAttr >> 4) & 0x0F);
  g->sgr.bgKind = RC_CLR4B;
  g->sgr.brightBack = 0;
}

/*
 * CEAnsi::WriteAnsiCode_CSI's 'm' arm (Ansi.cpp:3493-3640), parameter by parameter, left to right.
 * Two upstream details worth keeping because they are observable:
 *   - an unrecognised parameter is skipped and the loop carries on with the next one, so
 *     \e[53;31m still paints red;
 *   - a truncated 38/48 applies nothing and leaves its 5/2/r/g/b to be read as colour codes.
 * The one thing we do NOT copy is the int overflow in the parameter accumulator (Ansi.cpp:1760):
 * digits saturate at 65535 here instead of wrapping. Deviation #3; it only differs on absurd input.
 */
static void sgr_apply(RcGrid *g, const int *a, int n)
{
  RcSgr *s = &g->sgr;
  for (int i = 0; i < n; i++)
  {
    int v = a[i];
    if (v < 0) v = 0;
    switch (v)
    {
      case 0: sgr_reset(g, 0); break;
      case 1: s->bold = 1; break;
      case 2: case 22: s->bold = 0; break;
      case 3: s->italic = 1; break;
      case 23: s->italic = 0; break;
      case 4: s->underline = 1; break;
      case 24: s->underline = 0; break;
      case 5: case 6: case 25: break;              /* blink: no state at all upstream (Ansi.cpp:3530) */
      case 7: s->inverse = 1; break;
      case 27: s->inverse = 0; break;
      case 9: s->crossed = 1; break;
      case 29: s->crossed = 0; break;
      case 39: sgr_default_fg(g); break;
      case 49: sgr_default_bg(g); break;
      case 38: case 48:
      {
        int *slot = (v == 38) ? &s->fg : &s->bg;
        uint8_t *kind = (v == 38) ? &s->fgKind : &s->bgKind;
        uint8_t *bright = (v == 38) ? &s->brightFore : &s->brightBack;
        if (i + 2 < n && a[i + 1] == 5)
        {
          *slot = a[i + 2] & 0xFF;                 /* masked, not range-checked (Ansi.cpp:3568) */
          *kind = RC_CLR8B;
          *bright = 0;
          i += 2;
        }
        else if (i + 4 < n && a[i + 1] == 2)
        {
          int r = a[i + 2] & 0xFF, gg = a[i + 3] & 0xFF, b = a[i + 4] & 0xFF;
          *slot = (b << 16) | (gg << 8) | r;       /* 0x00BBGGRR, the COLORREF order */
          *kind = RC_CLR24B;
          *bright = 0;
          i += 4;
        }
        /* anything else: nothing happens and the leftover args fall through to the switch */
        break;
      }
      default:
        if (v >= 30 && v <= 37) { s->fg = v - 30; s->fgKind = RC_CLR4B; s->brightFore = 0; }
        else if (v >= 40 && v <= 47) { s->bg = v - 40; s->bgKind = RC_CLR4B; s->brightBack = 0; }
        else if (v >= 90 && v <= 97) { s->fg = (v - 90) | 8; s->fgKind = RC_CLR4B; s->brightFore = 1; }
        else if (v >= 100 && v <= 107) { s->bg = (v - 100) | 8; s->bgKind = RC_CLR4B; s->brightBack = 1; }
        /* 10, 312, 315, 414, 3130 and everything else: ignored, loop continues (Ansi.cpp:3626-3638) */
        break;
    }
  }
  g->attr = rc_attr(g, s);
}

/* ------------------------------------------------------------- sequence dispatch --------------- */

/* The census, as data. One row per `RcUnsupported` slot, in the enum's order, holding the label the report
 * prints, the sentence for what was skipped, and whether counting that slot makes the frame suspect.
 *
 * Before this table the same eleven facts lived in three places -- the comments inside the enum, the
 * `which == RC_UN_SUP` test in unsupported() below, and the label lists `Render.java` and
 * `NativeRenderer.java` each carry -- and only four of the Java indices were checked against anything.
 * I19 makes the census a positional contract across three files, so a slot renamed on one side and not the
 * other prints a confident wrong number forever, and the only thing that notices is a human reading a log.
 * The live gate now compares all eleven labels against this table, and the host gate pins the table itself
 * (including the one-entry-per-suspect fact), which is what lets `modelSuspect` be a column rather than a
 * special case.
 *
 * The order is the ABI: `RenderJni.cpp stats()` walks these slots by index and the Java side hardcodes the
 * positions, so a row may be re-worded and a new one appended, but nothing in the middle may move. */
struct RcCensus { const char *name; const char *sentence; int suspect; };

static const struct RcCensus rc_census[RC_UN_MAX] =
{
  { "unrecognised", "a CSI whose final byte neither this dispatch nor ConEmu's parser has a case for, so its reach is assumed rather than known", 1 },
  { "decstbm", "dead since DECSTBM became a modelled region (I25); the slot stays where it is because the census is positional", 0 },
  { "altbuf", "the alt-screen snapshot could not be taken -- a switch that was asked for and refused", 0 },
  { "mouse", "mouse tracking asked for; this library generates no mouse reports", 0 },
  { "mode", "a mode this model holds no state for (the private set it does hold answers DECRQM instead)",0 },
  { "bracketed paste", "DECSET 2004 asked for; the paste is executed by the host's input leg, which this library does not own", 0 },
  { "osc9", "a ConEmu-private OSC 9 outside the safe subset -- sleep, MessageBox, GuiMacro, DoProcess", 0 },
  { "other osc", "an OSC neither acted on nor answered, including one that never terminated", 0 },
  { "dcs", "a DCS payload, read to its terminator and discarded", 0 },
  { "report", "a query this build will not answer -- `CSI ? 6 n`, a DA with a parameter, `CSI t`", 0 },
  { "colon", "a CSI carrying a ':' subparameter, dropped whole for ConEmu parity (I10, I19)", 0 },
  { "osc clip", "OSC 52 asked for the clipboard and this build did not give it: policy off, a selection this platform has no place for, a payload that failed the strict decode, a request over the cap, or a read", 0 },
};

static void unsupported(RcGrid *g, enum RcUnsupported which)
{
  if (which >= RC_UN_MAX) return;
  g->nUnsupported[which]++;
  /* Counting was the whole answer until the grid witness showed what a count cannot do: a sequence that
   * moves the console's cursor, or chooses which rows scroll, leaves the model confidently describing a
   * screen that is not there -- and no geometry check catches that, because the console's shape still
   * matches and only its content and cursor do not.
   * That reach belongs to exactly one counter: RC_UN_SUP, the finals this switch has no case for and whose
   * effect therefore is not known, only assumed. Suspicion is what the painter acts on (S3,
   * MSFT_TERMINAL_REFERENCE §7.1), so every sequence with a *known* inert effect -- mouse tracking,
   * bracketed paste, reports, the OSC/DCS framing, a mode ConEmu has a case for but no body in -- is
   * counted by ignored() below instead, and the frame stays trusted. The alt buffer left this list when
   * ?47/?1047/?1049 became a modelled switch (alt_screen); the only thing still counted there is a
   * snapshot that failed to allocate, which by itself moves nothing. */
  if (rc_census[which].suspect)
    g->modelSuspect = 1;      /* the table's one 1, and the host gate keeps it the only one (I19) */
}

/* A sequence whose effect on the screen is *known* -- none -- so the frame stays trusted and only the
 * census records it. Either ConEmu has no case for it at all, or it has a case whose body is not there.
 * Every unrecognised CSI/ESC reaches DumpUnknownEscape and every recognised-but-unimplemented one reaches
 * DumpKnownEscape(de_Ignored), and in a release build both macros are `(0)` (Ansi.cpp:968-972) -- so
 * consuming the sequence here without modelling it is parity, not a gap. It counts all the same, because
 * the census is what says how often the stream asked for something neither leg does.
 * The family this replaced is DEC modes: `unsupported(g, RC_UN_MODE)` marked the model suspect for
 * every mode name we do not carry, which turned `?7h` from vim, `?12l` from a cnorm, or `?1h` from
 * smkx into a full-window re-adopt for nothing. ConEmu ignores 5 and 33 (no case at all), 12 (a case
 * whose body is commented out, :3295-3312) and 4 (":3328 ignored for now"), and the ones it does
 * implement -- 1, 2004 and the mouse family -- change input, not a cell. */
static void ignored(RcGrid *g, enum RcUnsupported which)
{
  if (which < RC_UN_MAX) g->nUnsupported[which]++;
}

/* Process-wide, because the decision belongs to the host that loaded the library and a second handle must
   not be able to disagree with the first. The Java side sets it once, from its own switch or from an explicit
   call; nothing in the byte stream can reach it. */
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

/* An argument read as a **count of things**, which is the shape every `CSI Ps` that moves, inserts, deletes
 * or erases has. Two rules belong here rather than at the eight arms that need them: DEC says an omitted
 * parameter and a zero parameter are the same request and both mean one, and a count cannot exceed what there
 * is to count. `limit` is that -- the rows a region can reach, the cells in front of the cursor -- and it may
 * be 0, which means "nothing here to do" and comes back 0.
 *   `shift_region` and `scroll_up` bound the move again for their own internal callers. That is not this
 * helper failing twice: the parser clamps what an application *asked for*, the model clamps what a call from
 * inside this file can mean, and only the first is a decision about the wire. */
static int count_arg(const RcGrid *g, int i, int limit)
{
  int n = arg(g, i, 1);
  if (n > limit) n = limit;
  return n > 0 ? n : 0;
}

/* The same, for the two sequences that read the parameter **raw** because zero is an answer rather than an
 * absent value: `CSI 0X` erases nothing and `CSI 0b` repeats nothing. ghostty clamps both to one
 * (Terminal.zig:3443-3446) and is the odd one out; ConEmu lets the zero stand and MSFT's arithmetic agrees
 * (`std::min(startCol + numChars, GetLineWidth(row))` over a `numChars` that came from `Ps` untranslated).
 * REP passes `RC_ARG_MAX` for `limit`: it emits *text*, so it wraps and every count is honoured -- the
 * only ceiling it has is the accumulator's own, which saturates rather than wrapping (deviation #3). */
static int count_arg_raw(const RcGrid *g, int i, int limit)
{
  int n = (i < g->nArgs) ? g->args[i] : 1;
  if (n > limit) n = limit;
  return n > 0 ? n : 0;
}

/* DECSTBM's two parameters are 1-based rows *within the page*, and each defaults to the edge it sits at:
 * `CSI 3r` is rows 3..bottom, `CSI ;4r` is 1..4. Out of range pulls back to the page rather than refusing,
 * which is the recorded split from MSFT (`adaptDispatch.cpp:2260` rejects an out-of-range bottom outright);
 * clamping is the deviation, so it is stated once, here, and `t > b` remains an ignore rather than a swap. */
static int region_arg(const RcGrid *g, int i, int dflt, int page)
{
  int n = arg(g, i, dflt);
  if (n < 1) n = 1;
  if (n > page) n = page;
  return n;
}

/* ------------------------------------------------------------------------------------------ tab stops -- */
/* Fill the columns from `from` up with the default interval, leaving anything the application claimed alone.
   MSFT does exactly this to the newly allocated tail of its vector and only while its default flag stands
   (`_InitTabStopsForWidth`, adaptDispatch.cpp:2799-2817), which is the half of the rule that says a resize is
   not a reset: stops you set survive one, and columns that appear past the old width get the defaults. */
static void tabs_default(RcGrid *g, int from)
{
  int c;
  if (!g->tabsDefaults) return;
  if (from < RC_TAB_INTERVAL) from = RC_TAB_INTERVAL;
  for (c = from; c < g->cols; c++)
    if ((c % RC_TAB_INTERVAL) == 0) g->tabStop[c] = 1;
}

/* The whole table back to the interval, with whatever was claimed thrown away: the answer at init, at RIS,
   and at DECST8C. ghostty's `reset(TABSTOP_INTERVAL)` (Terminal.zig:4943, Tabstops.zig:165) is this function;
   MSFT's HardReset has no such call, which is the one place this model follows DEC over MSFT -- a session that
   cannot get its defaults back has no way to ask, and `ESC c` means "as at power-up". */
static void tabs_reset(RcGrid *g)
{
  memset(g->tabStop, 0, sizeof g->tabStop);
  g->tabsDefaults = 1;
  tabs_default(g, 0);
}

/* The next stop strictly ahead of the cursor, or the last column when there is none left. Stopping rather
   than wrapping is the ruling in both references (MSFT's loop runs `while (column < maxColumn)` at
   :2670-2683; ghostty's `nextColumn` agrees), and it is why a tab cannot move the cursor to the next row:
   the row's end is a wall, and the write that follows is what wraps. Column 0 is never a stop on the way
   out, so a tab from the margin goes to 8 -- and `RC_TAB_INTERVAL` is where the defaults start, not 0. */
static int tab_next(const RcGrid *g, int from)
{
  int c;
  for (c = from + 1; c < g->cols; c++)
    if (g->tabStop[c]) return c;
  return g->cols - 1;
}

/* The previous stop strictly behind the cursor, or column 0 (MSFT's `while (column > minColumn)`,
   :2712-2730). Both walks stay on the row: a back-tab does not climb. */
static int tab_prev(const RcGrid *g, int from)
{
  int c;
  for (c = from - 1; c > 0; c--)
    if (g->tabStop[c]) return c;
  return 0;
}

/* Arm a reply the painter owes. Nothing here writes: the console input handle belongs to the process, and
 * a parser that could reach it would make every host test of this file a test of a handle. So the query
 * becomes one queue entry carrying the cursor as it stands, and RenderJni.cpp::flush_reports turns the entry
 * into KEY_EVENT records at the end of the flush that lands the screen they describe.
 * The queue is FIFO because that is the order the asker will read the replies in, and it refuses rather
 * than evict: a dropped *older* reply hangs a program already blocked on its first read, while a refused
 * newer one hangs only a program that asked more times than the console can remember -- and both leave a
 * number (nReportFull), which is the difference between a limit and a leak.
 * `idx` is for the kinds that answer about a numbered thing rather than about the cursor: an OSC colour
 * reply names the table index it belongs to (I34), and for that kind it replaces the cursor snapshot, which
 * nobody reads. Every other kind passes 0 and gets the cursor as it stands. */
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

/* `row` is a model row. The cursor is confined to the viewport: a gutter row is scrollback, and on a
 * real console nothing an escape sequence says can move the cursor into the history above the window. */
static void clxy(RcGrid *g, int row, int col)
{
  const int top = gutter(g);
  if (row < top) row = top;
  if (row >= g->rows) row = g->rows - 1;
  if (col < 0) col = 0;
  if (col >= g->cols) col = g->cols - 1;
  g->cy = row;
  g->cx = col;
}

/* A vertical cursor move by `delta` rows, clipped the way ConEmu's set_y clips it (Ansi.cpp:2913-2918):
 * down stops at the region's bottom row, up stops at its top, and a cursor already outside the region on
 * the side it is moving away from is left to the viewport. So a program that asked for lines 2..5 to
 * scroll cannot walk the cursor out of them with `CSI nE`, which is what the status line and every
 * full-screen redraw assume. With no region the bounds are the viewport's own and this is exactly clxy().
 * Upstream compares absolute buffer rows (ScrollStart/End, stored plus-srw.Top by SetScrollRegion :4160)
 * against a window-relative cursor (:2888), so its clip is off by the window's position in the buffer --
 * with scrollback below the region's top the down-clip simply never bites. Using region() keeps both
 * bounds in g->cy's space instead; CONEMU_ANSI_DEFECTS.md records the original. */
static void move_row(RcGrid *g, int delta)
{
  int top, bot;
  region(g, &top, &bot);
  int row = g->cy + delta;
  if (delta < 0) { if (g->cy >= top && row < top) row = top; }
  else           { if (g->cy <= bot && row > bot) row = bot; }
  clxy(g, row, g->cx);
}

/* The viewport's rows, blank: what MSFT's alt buffer arrives as (`UseAlternateScreenBuffer` is handed
 * `_GetEraseAttributes` at adaptDispatch.cpp:1747, i.e. the page's current erase attribute) and what our
 * own ED uses, so a screen that scrolls into the alt from below is blank in the same colour as one
 * cleared by CSI J. */
static void blank_viewport(RcGrid *g)
{
  for (int r = gutter(g); r < g->rows; r++)
    for (int c = 0; c < g->cols; c++)
    {
      RC_CELLS(g, r)[c].ch = ' ';
      RC_CELLS(g, r)[c].attr = g->attr;
    }
  rc_forget_row_state(g);
  rc_mark_all_dirty(g);
}

/* ?47 / ?1047 / ?1049 -- one behaviour for all three, which is what MSFT ships: their mode parameters all
 * reach ASB_AlternateScreenBuffer, whose arm saves the cursor, switches to a cleared buffer the size of
 * the viewport, and on the way back switches to the main buffer and restores the cursor
 * (adaptDispatch.cpp:1741-1756, screenInfo.cpp:1900-1965). There is one main and one alt, so a second
 * entry while already on the alt re-clears it and keeps the snapshot the main screen came with.
 *
 * The console is never asked to switch anything: it always shows the model's viewport, so a switch costs a
 * snapshot of those `winRows` rows and one full repaint. That is also why a refusal -- the snapshot's
 * malloc failing -- can leave the screen untouched without distrusting the model: nothing in the console
 * moved, and the sequence is counted rather than guessed at. */
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
      /* Row by row: `cells` is RC_MAX_COLS wide and `snap` is `cols` wide, so no single copy spans both. */
      for (int r = 0; r < nrows; r++)
      {
        memcpy(&g->snap[(size_t)r * g->cols], &RC_CELLS(g, hist + r)[0], (size_t)g->cols * sizeof(RcCell));
        g->snapState[r] = RC_ST(g, hist + r);
      }
      g->alt = 1;
    }
    g->nAltSwitch++;
    g->saveX = g->cx;
    g->saveY = g->cy;           /* DECSC's own slot, as MSFT uses it: a later ESC 8 finds this position */
    g->pendingScrolls = 0;
    blank_viewport(g);
    return 1;
  }
  if (!g->alt) return 1;        /* leaving a screen we are already on changes nothing */
  g->nAltSwitch++;
  for (int r = 0; r < nrows; r++)
  {
    memcpy(&RC_CELLS(g, hist + r)[0], &g->snap[(size_t)r * g->cols], (size_t)g->cols * sizeof(RcCell));
    RC_ST(g, hist + r) = g->snapState[r];
  }
  g->alt = 0;
  g->pendingScrolls = 0;
  clxy(g, g->saveY, g->saveX);  /* CursorRestoreState() after the screen is back, like MSFT's order */
  rc_mark_all_dirty(g);
  return 1;
}

/* RIS (`ESC c`) -- the reset that owns the screen. Both references separate it from DECSTR by what it may
 * touch: MSFT's `HardReset` switches buffers and erases (:3042-3062, with `UseMainScreenBuffer` in the
 * list), while its `SoftReset` (:2984-3020) is a list of state assignments with no cursor move, no erase and
 * no buffer switch at all. See soft_reset() below for the second half of that line.
 * The hard part here is "leave the alt screen, run the viewport's worth of rows up into history, home": the
 * alt is left first, because a reset must not overwrite the main screen with it
 * (adaptDispatch.cpp:3038-3049), and attributes are not saved by 1049, so the reset still lands.
 * Two places this answers VT rather than either reference: upstream routes the drop through the
 * region-honouring scroll, so a program that set `CSI 1;5r` and died would have five rows wiped and the rest
 * of the screen kept, and nothing clears the scroll region, the cursor shape or the charset designation.
 * A reset that leaves a region behind it is a reset whose next line feed scrolls five rows, so the region is
 * dropped here, and so is the drawing set -- `_termOutput.HardReset()` / `SoftReset()` reset the designations
 * (adaptDispatch.cpp:3000), which is the `smacs` state a shell inherits after a child died in graphics mode. */
static void full_reset(RcGrid *g)
{
  sgr_reset(g, 0);
  g->charset = 0;
  alt_screen(g, 0);
  g->regSet = 0;
  g->cursorShape = -1;
  g->cursorVisible = 1;
  g->wrapMode = 1;   /* RIS/DECSTR put every mode back, including the one with no caps entry (I35) */
  tabs_reset(g);     /* and the tab stops are part of "as at power-up", whatever MSFT's HardReset omits */
  /* RIS ends a synchronized region with everything else it ends. The alternative -- leaving the bit set and
     letting the painter hold the reset's own scroll -- is the one case where a hold could swallow the very
     sequence that would have cleared it. */
  g->sync = 0;
  scroll_up(g, g->winRows);
  clxy(g, gutter(g), 0);
}

/* DECSTR (`CSI ! p`) -- the reset that does not touch the screen. MSFT's SoftReset is
 * adaptDispatch.cpp:2984-3020 and reads as a list of assignments: cursor visible, the modes it knows back to
 * their default, AutoWrap on, the scroll margins put back to the page, the character set designations reset,
 * the rendition normal, and the *active* buffer's saved cursor state cleared -- and it contains no cursor
 * positioning, no erase and no buffer switch, because those belong to HardReset (:3042-3062, where
 * `UseMainScreenBuffer` finally appears at :3047). Clearing only the active saved state is called out as deliberate
 * xterm parity (GH#19918, :3005-3008).
 * This model has no "is there a saved cursor" bit, only the two coordinates, so clearing it means writing the
 * cursor back over them: a later DECRC then restores the position the terminal is already at, which is all
 * "no saved cursor" is worth to a program.
 * The cursor shape is deliberately not reset. It is the user's preference as much as the application's -- the
 * reason -1 exists here is to leave it alone -- and DECSTR's own list has no shape in it.
 * The synchronized bit is cleared here even though MSFT has no such mode to clear: this model can hold a
 * frame open with it, and a reset that left it set would strand the paint with nothing left to close it. */
static void soft_reset(RcGrid *g)
{
  sgr_reset(g, 0);
  g->charset = 0;
  g->regSet = 0;
  g->cursorVisible = 1;
  g->wrapMode = 1;
  g->sync = 0;
  g->saveX = g->cx;
  g->saveY = g->cy;
}

/* The column a leftward move of `n` cells lands on, adjusted to a glyph boundary. This is conhost's
 * `ROW::_adjustBackward` (Row.cpp:1215: `for (; _uncheckedIsTrailer(column); --column) {}`), whose whole
 * point is that a cursor never stops inside a wide glyph. Ours is a test on the cell rather than a stored
 * per-column flag, because we must be able to write the pair out as CHAR_INFO, and the same
 * `put_cell` that writes LEADING at c writes TRAILING at c+1.
 *
 * Without it, BS after a wide glyph stops the model one column inside the glyph and the next character
 * is written over its trailing half, leaving the leading half orphaned on screen -- which the grid
 * witness measured as a real difference from the fallback leg (`Render.java` "wide glyph then BS").
 * A glyph is at most two columns, so one adjustment is enough: `n` steps collapsed into one move cannot
 * skip a second trailer. */
static int step_back_col(const RcGrid *g, int n)
{
  int col = g->cx - n;
  if (col < 0) col = 0;
  if (col > 0 && (RC_CELLS(g, g->cy)[col].attr & RC_LVB_TRAILING)) col--;
  return col;
}

/* The CSI intermediates are matched the way ConEmu matches its Pvt buffer: the whole thing, length
   included. `PvtLen == 1 && Pvt[0] == L' '` (:3657) is one byte that happens to be a space, so a
   two-byte interim is not DECSCUSR there and is not DECSCUSR here either. */
static int interim_is(const RcGrid *g, uint8_t ch)
{
  return g->nInterims == 1 && g->interims[0] == ch;
}

static void interim_push(RcGrid *g, uint8_t ch)
{
  if (g->nInterims < RC_INTERIM_MAX) g->interims[g->nInterims++] = ch;
}

/* DECRQM's answer, for the modes whose state this struct actually holds. The numbers are VT500's
   (1 = reset, 2 = set), and the two that describe a *permanent* fact -- 3 permanently reset, 4
   permanently set -- are never sent here, for two reasons that point the same way.
     The vocabulary is not stable. xterm and DEC read 4 as "permanently set"; jline4 documents 3 that
   way and 4 as "permanently reset" (AbstractTerminal.java:663-667), and treats 1/2/3 as SUPPORTED
   (:685). So for any mode this renderer has no state for, whichever permanent number it answers, one
   of the two readers is told the opposite of the truth -- and #52 already learned what it costs when a
   number this library emits is read by an outside program as a capability claim.
     And the number buys nothing. `parseDecrpm` returns NOT_SUPPORTED for a reply it cannot find
   exactly as it does for a 4 (:677-689), so to the one consumer in the house silence and 4 are the
   same verdict. Silence is also the ruling this file already made for the extended `CSI ? 6 n`: answer
   what the model can prove, count what it cannot.
   Two ids in the family jline4 probes are absent for that reason:
     2027 (grapheme reflow) and 2048 (in-band window resize) -- this build wraps at cells and reports
       geometry out of band, so "set" is false and either permanent number is unreadable. Both already
       vote `RC_UN_MODE` on the `h`/`l` side, and `$p` leaves the same count.
     1048 -- xterm lists it as "alternating cursor position", which is what we implement (`?1048h` saves,
       `?1048l` restores, Render.cpp's `h`/`l` block), and that is an *event*, not a state a reply could
       report. `cursorVisible` is the state a caller means when it asks about a cursor, and that is 25. */
static int mode_status(const RcGrid *g, int id, int *out)
{
  switch (id)
  {
    case 25:   *out = g->cursorVisible ? 2 : 1; return 1;
    case 7:    *out = g->wrapMode ? 2 : 1; return 1;   /* modelled, so answerable (I35) */
    case 47: case 1047: case 1049:
               *out = g->alt ? 2 : 1; return 1;      /* the three spellings share one slot (I14's alt screen) */
    case 2026: *out = g->sync ? 2 : 1; return 1;     /* 1 and 2 both reach jline4 as SUPPORTED (:685) */
    default:   return 0;
  }
}

/* CSI with a final byte in hand. The 0x20..0x2F bytes it names are in g->interims (' ' selects cursor
   shape), because which interim a final had is a property of the sequence, not of the last byte read. */
static void csi_dispatch(RcGrid *g, uint8_t final)
{
  switch (final)
  {
    case 'm':
      /* A private byte makes ConEmu drop the whole SGR (Ansi.cpp:3494): '?31m' paints nothing. That
         also covers colon subparameters, since ':' is 0x3A and lands in Pvt.
         CSI m with no parameters at all is the universal "reset" spelling; ConEmu's handling of the
         empty case is not something I measured, so RenderCheck records it as an assumption rather
         than as parity, and the fallback leg is the witness if it ever matters. */
      if (!g->priv)
      {
        static const int one_zero[1] = {0};
        sgr_apply(g, g->nArgs ? g->args : one_zero, g->nArgs ? g->nArgs : 1);
      }
      else if (!g->csiColon) ignored(g, RC_UN_MODE);
      /* The colon form is counted as RC_UN_COLON when the sequence dispatches, and deliberately not here.
         Neither is suspicion-worthy: a dropped colour moves no cursor (Ansi.cpp:3494 drops the whole SGR
         for any private byte, which is what the line above mirrors). */
      break;

    case 'A': move_row(g, -arg(g, 0, 1)); break;
    case 'B': move_row(g, arg(g, 0, 1)); break;
    case 'C': clxy(g, g->cy, g->cx + arg(g, 0, 1)); break;
    /* HPR (`CSI a`) and VPR (`CSI e`). They used to be counted and dropped, because ConEmu has no case for
       either one: the finals its CSI switch handles are `@ A B C D E F H J K L M P S T X b c d f h l m n p q
       r s t u`, so `a`/`e` reach `default:` -> DumpUnknownEscape (Ansi.cpp:3816 -> :971), a no-op in a release
       build. Both references implement them, and agree on the one detail that makes them more than aliases for
       CUF/CUD: **they are not constrained by the scroll region.** ghostty routes them to
       `cursor_col_relative`/`cursor_pos_relative` (stream.zig:1863/:1942) and MSFT says so in the comment on
       each one -- "Unlike CUF/CUD, this is not constrained by margin settings" (adaptDispatch.cpp:427/:437) --
       with both landing on `_CursorMovePosition(..., wrapAround=false)`, whose clamps are the screen's edges.
       So VPR is `clxy` (viewport) and *not* `move_row` (region), and that difference is the whole reason this
       case cannot simply alias onto 'B'. A program that pinned a region with `CSI r` and then walked out of it
       with `CSI e` gets the region on the fallback leg (ConEmu drops the sequence: cursor stays) and gets the
       viewport here -- which is what every other terminal it was ever tested on gives it. */
    case 'a': clxy(g, g->cy, g->cx + arg(g, 0, 1)); break;
    case 'e': clxy(g, g->cy + arg(g, 0, 1), g->cx); break;
    case 'D': clxy(g, g->cy, step_back_col(g, arg(g, 0, 1))); break;
    case 'E': move_row(g, arg(g, 0, 1)); g->cx = 0; break;
    case 'F': move_row(g, -arg(g, 0, 1)); g->cx = 0; break;
    case 'G': clxy(g, g->cy, arg(g, 0, 1) - 1); break;
    case 'H': case 'f': clxy(g, gutter(g) + arg(g, 0, 1) - 1, arg(g, 1, 1) - 1); break;
    case 'd': clxy(g, gutter(g) + arg(g, 0, 1) - 1, g->cx); break;

    case 'J':
    {
      /* ED erases the *screen*, so it stops at the viewport: the rows above it are history the
         fallback leg cannot erase either, and blanking them here would paint over the user's
         scrollback. */
      const int top = gutter(g);
      int mode = arg(g, 0, 0);
      if (mode == 0) { fill_row(g, g->cy, g->cx, g->attr); for (int r = g->cy + 1; r < g->rows; r++) fill_row(g, r, 0, g->attr); }
      else if (mode == 1) { for (int r = top; r < g->cy; r++) fill_row(g, r, 0, g->attr); fill_row(g, g->cy, 0, g->attr); }
      else
      {
        for (int r = top; r < g->rows; r++) fill_row(g, r, 0, g->attr);
        g->cx = 0; g->cy = top;                     /* ConEmu resets the cursor with a 2J (Ansi.cpp:3027) */
      }
      break;
    }
    case 'K':
    {
      int mode = arg(g, 0, 0);
      if (mode == 0) fill_row(g, g->cy, g->cx, g->attr);
      else if (mode == 1) fill_span(g, g->cy, 0, g->cx, g->attr);
      else fill_row(g, g->cy, 0, g->attr);
      break;
    }
    /* IL pushes the lines at and below the cursor down, n of them, and the gap it opens at the cursor
       is the blank; DL pulls everything below the cursor up. Getting the direction wrong is invisible on
       a single-line test and catastrophic on a table, hence RenderCheck case "IL/DL".
       Both are region-bounded: the shift spans [cursor row .. region bottom] and a cursor outside the
       region is refused outright -- not clamped to it, which is what the Status bar needs to stay safe
       while `csr` has the upper rows. MSFT's guard is the same test on both halves of the same helper
       (`row >= topMargin && row <= bottomMargin && col >= leftMargin && col <= rightMargin`,
       adaptDispatch.cpp:2145) and ghostty's is the four-way check at Terminal.zig:2964-2967 and
       :3138-3141. Without horizontal margins the column term is always true here, so only the row one
       bites. The no-region path below is the one every witness before DECSTBM was modelled depends on, and
       it is kept verbatim.
       When n exceeds the region both references clamp it to what is left rather than writing past the
       bottom: `adjusted_count = @min(count, rem)` (Terminal.zig:2992) and
       `std::min(std::abs(delta), scrollRect.height())` (adaptDispatch.cpp:552), which is what shift_region
       does. And after the shift, both take the cursor to the left margin -- "The IL and DL controls are
       also expected to move the cursor to the left margin" (:2150-2151, `cursor.SetXPosition(leftMargin)`)
       and `cursorAbsolute(scrolling_region.left, start_y)` in the `defer` of insertLines and deleteLines
       (:2977, :3151). The application this costs anything is the one redrawing a table: it walks the cursor
       in to a column, deletes the row, and writes the replacement from wherever the cursor ended up, so a
       column kept is a row printed n columns off, once per row. */
    case 'L': case 'M':
    {
      int n, top, bot;
      region(g, &top, &bot);
      if (g->regSet && (g->cy > bot || g->cy < top)) break;
      /* The limit is the rows this move can actually reach: inside a region that is [cursor .. region bottom],
         without one it is [cursor .. the model's last row]. For IL the two candidate bounds -- the viewport's
         height and the rows below the cursor -- ask for the same screen, because a push taller than the space
         below simply empties it. **For DL they are not the same, and the viewport's height was a real
         defect**: the blanking loop runs from `rows - n`, so with a gutter and the cursor two rows into the
         window `CSI 9M` blanked `rows - winRows` .. `rows` -- the rows *above* the cursor -- and left the
         cursor's own row standing. The application offered the rows below it and only those go; erasing the
         rest is a side effect of an arithmetic bound nobody had named. Witness: RenderCheck's "reaches no
         higher", which was red before this line existed. */
      n = count_arg(g, 0, g->regSet ? bot - g->cy + 1 : g->rows - g->cy);
      if (g->regSet)
      {
        shift_region(g, n, g->cy, bot, final == 'L');
        g->cx = 0;                                      /* IL/DL home the column and keep the row */
        break;
      }
      /* Both directions are one rotation of [cursor .. the model's last row], with the rows the move made
         room for blanked at the end it opened -- and `n` is already bounded by that span above. */
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
      g->cx = 0;                                         /* the same contract, with or without a region */
      rc_mark_all_dirty(g);
      break;
    }
    /* ICH opens n blank columns at the cursor and pushes the row's tail right; DCH pulls the tail back
       and blanks the tail end. Both act on the row alone, from the cursor to the end of the *model* row,
       which is the buffer width: nothing wraps, nothing below moves, and text pushed past the last column
       cannot be pulled back -- MSFT scrolls the rect `{col, row, rightMargin + 1, row + 1}` (its
       `_InsertDeleteCharacterHelper`, adaptDispatch.cpp:654-690, which is the cursor row and only that row)
       and ghostty's insertBlanks/deleteChars work from `rem = right - x + 1` on one row
       (Terminal.zig:3330, :3406). A glyph whose two cells end up on opposite sides of the shift is healed
     after the move (I16), which is where this differs in mechanism, not in outcome, from ghostty's
     boundary clears at :3322-3342 and :3411-3413. */
    case '@': case 'P':
    {
      if (g->cx < g->cols)
      {
        /* Both are row-local and both stop at the row's end: the cells in front of the cursor are all there
           is to insert before or delete. The bound is what makes `g->cols - n` below safe. */
        const int n = count_arg(g, 0, g->cols - g->cx);
        if (final == '@')
        {
          for (int c = g->cols - 1; c >= g->cx + n; c--) RC_CELLS(g, g->cy)[c] = RC_CELLS(g, g->cy)[c - n];
          fill_span(g, g->cy, g->cx, g->cx + n - 1, g->attr);
        }
        else
        {
          for (int c = g->cx; c + n < g->cols; c++) RC_CELLS(g, g->cy)[c] = RC_CELLS(g, g->cy)[c + n];
          fill_span(g, g->cy, g->cols - n, g->cols - 1, g->attr);
        }
        /* A shift by n keeps every pair whose two cells are both inside the moved span and destroys the
           ones the fill covers; what it cannot be trusted to notice is a half that crossed the boundary, so
           the row is checked. The fill above healed its own two edges; this catches the far side of a pair
           that moved out from under its own head. */
        heal_pairs(g, g->cy, 0, g->cols - 1);
      }
      break;
    }
    /* ECH (`CSI Ps X`) erases Ps cells at the cursor and stops at the end of that row. Both references say
       so and mean it: "This will only erase characters in the current line, and won't wrap to the next"
       (adaptDispatch.cpp:706-724, which clamps with `std::min(startCol + numChars, GetLineWidth(row))`), and
       `remaining = cols - cursor.x; end = @min(remaining, @max(count_req, 1))` (Terminal.zig:3443-3446).
       The row below the cursor holds text the application did not ask to lose, which is the same reason ED
       refuses to touch the rows above the viewport. The parameter is read raw, so `CSI 0X` erases nothing
       (MSFT's arithmetic agrees; ghostty clamps to 1 and is the odd one out). Filled with the live
       attribute, which is what makes `bce` true for this sequence. */
    case 'X':
    {
      /* Read raw, so `CSI 0X` erases nothing, and bounded by the cells in front of the cursor -- which is what
         makes `fill_span`'s `to` land inside the row without a second clamp of its own. */
      const int n = count_arg_raw(g, 0, g->cols - g->cx);
      if (n > 0)
        fill_span(g, g->cy, g->cx, g->cx + n - 1, g->attr);   /* also heals a glyph the erase cut in half */
      break;
    }

    /* REP (`CSI Ps b`) replays the last character written, Ps times. Upstream builds a buffer of that one
       character and hands it to WriteText (Ansi.cpp:3070-3087), so it is *text*: it wraps at the margin,
       obeys the drawing charset, takes the current attribute, and for a wide glyph costs two columns. That
       makes it a call to put_cp rather than a cell poke, and it is why the two ConEmu quirks fall out for
       free -- the count is read raw, so `CSI 0b` repeats nothing (ghostty's Terminal.zig clamps to 1), and
       the character repeated is the one before the charset remap, so a repeat after `ESC ( 0` draws the
       line glyph from the stored letter. The private form is refused upstream and counted without
       suspicion here; nothing about a refused REP moves a cell, so the frame stays trustworthy. */
    case 'b':
    {
      if (g->priv) { ignored(g, RC_UN_MODE); break; }
      /* No geometric bound on purpose: REP is text, so a count larger than the screen scrolls it and keeps
         going. The only ceiling is the accumulator's, and naming it here says so out loud. */
      const int want = count_arg_raw(g, 0, RC_ARG_MAX);
      for (int n = 0; n < want; n++) put_cp(g, g->lastUnit);
      break;
    }

    /* SU and SD scroll the region. With no region, or a region that is the whole viewport, SU keeps the
       whole-model shift it always used -- that path carries unpainted history out of the gutter and asks
       the console for its own scroll, and every witness before DECSTBM was modelled depends on it. SD
       has no such history to move: content pushed below the viewport is gone, which is what ConEmu's
       LinesInsert at the window's bottom rows does too (Ansi.cpp:3183-3192, region-aware, cursor left
       where it was -- neither sequence moves the cursor and neither do we). */
    case 'S':
    {
      int top, bot;
      region(g, &top, &bot);
      /* A whole-model scroll can be asked for more rows than the model holds and the surplus is simply the
         same screen again, so the limit is the model; a region shift is bounded by the region. Either way the
         count is read through the same door as every other `Ps`, and the guards inside `scroll_up` and
         `shift_region` stay for the callers that come from inside this file. */
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

    case 's': g->saveX = g->cx; g->saveY = g->cy; break;
    /* DECRC, and the one place this model deliberately diverges from ConEmu, where "restore is
       unconditional" (Ansi.cpp:4194 -- PvtLen is never consulted for 'u'). The private spelling
       `CSI ?u` is kitty's keyboard-flags *query*, and it is on the wire: jline4's probe batch opens
       with it (AbstractTerminal.probeModes), so obeying upstream teleports the cursor to the last
       DECSC on every round of capability probing. Windows Terminal and ghostty both route a
       private-marker final to their query/ignore arms and never move the cursor, so the divergence
       is toward the two references that answer this sequence at all, not away from parity.
       The store `CSI ?s` is left alone: a save nobody restores costs nothing, while the restore is
       the half that actually moves the cursor. */
    case 'u':
      if (g->priv) { ignored(g, RC_UN_MODE); break; }
      clxy(g, g->saveY, g->saveX);
      break;

    /* DECSTBM. Two defaults, one refusal, and one clamp.
       A missing or zero parameter names the edge of the viewport, so `CSI 3r` is "rows 3..bottom" and
       `CSI ;4r` is "rows 1..4". Both references do that (MSFT adaptDispatch.cpp:2243-2257, whose comment at
       :2239 spells out `[3;r -> 3,h`), and upstream does not: Ansi.cpp:3142 demands `ArgC >= 2`, so a
       one-parameter call fell through to `SetScrollRegion(false)` here and *cleared* a region somebody had
       just asked for. A contradictory pair (`3;2r`) is likewise ignored by both references, and ignoring is
       not the same act as clearing -- clearing hands the next line feed the whole viewport, which is the
       #47/#48 failure with a different trigger. Those two are the reason this is no longer a mirror of
       upstream; what the mirror keeps is the clamp below and the no-home rule.
       Zero clamps to the viewport's first row (`CSI 0;35r` = `CSI 1;35r`), setting a region does NOT home the
       cursor -- which is what the comment in Status.java:234 ("usually moves the cursor") assumes it does --
       and the private form `CSI ?r` is accepted, because upstream never checks PvtLen for this final byte.
       The parameters are viewport-relative (`GetWorkingRegion(.., true)` at :4108-4127, which is
       srWindow), which is the same frame this model addresses rows in, so the gutter can never be pulled
       into a region. The clamp happens once, here, and is never revisited: the viewport's row span cannot
       move under a live grid, because rc_reset_hist() is the only writer of cols/rows/winRows and the
       painter refuses to realign a geometry change rather than re-cutting one it was asked for
       (RenderJni.cpp:574) -- the caller reopens, and a reopened grid has no region.
       A bottom past the viewport is pulled back to its last row rather than rejected, which is a deliberate
       split from MSFT (:2260 rejects): "scroll below row 3" is the application's intent, and throwing the
       whole request away to honour a literal parameter is the worse of the two wrongs. For the same reason a
       degenerate `Pt == Pb` is accepted as a one-row region where both references refuse it -- `Status.reset()`
       reaches this parser as `CSI 1;1r` (JLine's `csr` at a 0x0 size through `%i`, and Display.java:112 is the
       layer that makes that size), and refusing it would leave the bar's region stuck on. That tolerance is
       load-bearing, and it is the reason the rule here is `t > b` rather than `t >= b`. */
    case 'r':
    {
      const int top = gutter(g);
      const int page = g->rows - top;              /* the 1-based rows the parameters may name */
      if (!g->nArgs) { g->regSet = 0; break; }     /* `CSI r` is the reset form */
      int t = region_arg(g, 0, 1, page), b = region_arg(g, 1, page, page);
      if (t > b) break;                            /* inverted: leave whatever region is live */
      const int rt = top + t - 1, rb = top + b - 1;
      g->regSet = 0;
      /* Normalise "the region is the viewport" back to no region at all: the paths that keep the gutter and
         the console scroll in mind branch on exactly that, and a region that happens to cover everything
         must not cost them. MSFT normalises the same way for `apt` (:2262-2270). */
      if (!(rt == top && rb == g->rows - 1)) { g->regSet = 1; g->regTop = rt; g->regBot = rb; }
      break;
    }
    case 'h': case 'l':
    {
      /* Two gates shared with upstream: the whole switch is skipped when the sequence has no parameter
         (`CSI h` is inert, Ansi.cpp:3197), and only ArgV[0] is ever read (:3240), so `?1;2004h` acts on
         the 1 and drops the 2004. Both are mirrored by looking at args[0] alone. */
      int on = (final == 'h');
      int v = g->nArgs ? g->args[0] : 0;
      if (g->priv == '?')
      {
        if (v == 25) g->cursorVisible = on;
        else if (v == 7) g->wrapMode = on ? 1 : 0;   /* DECAWM (I35) -- `CSI 7h` is GATM, not this */
        else if (v == 2026)
        {
          /* DECSET/RESET 2026, the synchronized-output mode. Off is unconditional -- a `?2026l` nobody armed
             is exactly as inert as it looks, and gating it on `sync` would only hide a leaked BSU from the
             census. On is the half with a convention to follow: xterm has no depth (the first ESU ends the
             region whatever the BSU count), so a nested BSU is counted and dropped rather than stacked, and
             the application that sends one gets the frame the single-level model describes. */
          if (on) { if (g->sync) g->nSyncNested++; else { g->sync = 1; g->nSyncEngages++; } }
          else g->sync = 0;
        }
        else if (v == 47 || v == 1047 || v == 1049) alt_screen(g, on);
        else if (v == 1048) { if (on) { g->saveX = g->cx; g->saveY = g->cy; } else clxy(g, g->saveY, g->saveX); }
        else if (v == 9 || v == 1000 || v == 1002 || v == 1003 || v == 1004 ||
                 v == 1005 || v == 1006 || v == 1015) ignored(g, RC_UN_MOUSE);
        else if (v == 2004) ignored(g, RC_UN_DECBP);
        else ignored(g, RC_UN_MODE);
      }
      else ignored(g, RC_UN_MODE);
      /* The modes in that last arm that have a body upstream, and why ignoring them is still parity:
         4 (IRM) is "ignored for now" in ConEmu itself (:3323-3329), which makes `smir`/`rmir` a claim
         neither leg can keep; 7 (DECAWM) only records WrapAt=80 for ConEmu's own writer, because the
         SetConsoleMode that would really toggle ENABLE_WRAP_AT_EOL_OUTPUT is commented out (:3268-3281,
         and the dead block at :3428-3457); 20 (LF/NL) sets a flag whose only reader adds a CR to the
         writer's LF (:1181), and this model already folds the column on every newline. Of the rest, 1
         (DECCKM), 9/1000-1015 and 2004 change input, 3 sets a ConEmu GUI display option, 12 is an arm
         whose only statement is a commented-out dump, and 1034/7786/7787/7711 are marked ignored or are
         ConEmu's own prompt marker; every other mode number falls to `default: DumpUnknownEscape`
         (:3427) and is inert there exactly as it is here. */
      break;
    }
    case 'q':
      if (interim_is(g, ' ') && !g->priv)
      {
        /* DECSCUSR. Upstream really does implement it (:3656-3686), and does so with the one call this
           model is allowed to make on Win7: GetConsoleCursorInfo/SetConsoleCursorInfo with dwSize 100 for
           a block and 15 for an underline. Bar shapes (5/6) need a per-console-API ConEmu only reaches
           through its own GUI, so they fold to the underline here exactly as they fold upstream, where
           `nStyle == 1 || nStyle == 2 ? 100 : 15` leaves 3..6 at 15. Out of range or absent -> 0, which
           is ConEmu's "default", i.e. the shape the console had before anything asked. */
        int v = (g->nArgs && g->args[0] >= 1 && g->args[0] <= 6) ? g->args[0] : 0;
        g->cursorShape = v;
      }
      else ignored(g, RC_UN_SUP);   /* `CSI q` with no interim byte: XTSSZ, no case upstream */
      break;
    case 'p':
    {
      /* DECRQM -- `CSI ? Ps $ p`. ConEmu has no case for it at all (:3650-3653 sends every `p` it does not
         recognise to DumpUnknownEscape), so this is an addition rather than a parity item, and the reason it
         is worth one is jline4's probe batch: it asks 2026/2027/2048 in one write and then looks each reply
         up by its mode number (`parseDecrpm`, AbstractTerminal.java:675-690), so an id this switch leaves
         unanswered simply resolves to NOT_SUPPORTED there, while an id it answers is believed.
         Only the private spelling with exactly one parameter and exactly one interim byte is a request
         (interim_is is the whole-buffer comparison upstream does with Pvt); every other `$p` -- no `?`, two
         parameters, no parameter -- is a spelling this switch has no answer for, and it is counted rather
         than guessed at. Modes outside mode_status() get no reply at all: a reply is a claim about state,
         and for `?999$p` the state is not ours to describe. Silence is also what this file already decided
         for `CSI ? 6 n`, whose extended form is declined rather than answered with the plain-form answer
         (:1276-1280), and the rule generalises: answer what you can prove, count what you cannot.
       DECSTR -- `CSI ! p` with no parameter -- keeps the rest of this case, and it gets soft_reset() rather
         than full_reset() because the two sequences are not the same act in either reference: a soft reset
         puts state back and leaves the screen alone, and MSFT's comment on the one line of it that looks like
         a cursor action says exactly that (adaptDispatch.cpp:3005-3008). Erasing the screen on a soft reset
         costs a full-screen application its whole display. Upstream gates it on
         `ArgC == 0 && PvtLen == 1 && Pvt[0] == L'!'` (Ansi.cpp:3645), and '!' (0x21) is an interim byte, not
         a private one -- but both ranges are appended into the *same* Pvt buffer there (:1788), so `? ! p` is
         a two-byte Pvt and upstream refuses it. That is the whole reason the test below reads `!g->priv` as
         well: with the intermediates in a slot of their own, the two ranges were tested separately and the
         hybrid spelling reset a console nothing else resets. It also drops the restore-memory spelling
         `CSI Ps;Ps!p`, which upstream sends to the same place; gating on "no parameters" is upstream's
         behaviour, not an oversight here.
       Everything left hits the last two lines, and they are numbers rather than a bare `break` for the reason
         this file states everywhere: a sequence that reached a final and did nothing must leave a count, so
         the census can tell "the application asked" from "the application never wrote it". `$` says the
         sequence was about a mode, which is why it votes MODE and not SUP. */
      int st = 0;
      if (interim_is(g, '$') && g->priv == '?' && g->nArgs == 1 && mode_status(g, g->args[0], &st))
        arm_report(g, RC_REP_DECRPM, g->args[0], st, 0);
      else if (interim_is(g, '!') && !g->priv && !g->nArgs) soft_reset(g);
      else if (interim_is(g, '$')) ignored(g, RC_UN_MODE);
      else ignored(g, RC_UN_SUP);
      break;
    }
    /* CBT (`CSI Ps Z`) walks the same table backwards. It used to be refused with the reason "there is no
       tab stop for a backtab to find" -- which described the implementation, not the terminal: once HTS is
       real, so is this, and the application that reads `cbt` out of the terminfo entry is asking for exactly
       it. The count is read as a count: `CSI 0Z` is one back-tab, and the walk stops at column 0. */
    case 'Z':
    {
      const int n = count_arg(g, 0, RC_ARG_MAX);
      for (int i = 0; i < n; i++) g->cx = tab_prev(g, g->cx);
      break;
    }

    /* CHT (`CSI Ps I`) is the same walk forward, with a count. */
    case 'I':
    {
      const int n = count_arg(g, 0, RC_ARG_MAX);
      for (int i = 0; i < n; i++) g->cx = tab_next(g, g->cx);
      break;
    }

    /* TBC (`CSI Ps g`). 0 clears the stop under the cursor; 3 clears every stop *and* the default interval,
       so a later tab has nowhere to run to but the margin (MSFT: `_ClearAllTabStops` sets
       `_initDefaultTabStops = false` at :2775; ghostty: `reset(0)`, which its own header reads as "an
       interval of 0 sets no tabstops", Tabstops.zig:164). 5 is DECST8C -- the name says five columns and
       both references implement "put the defaults back", which is why MSFT's enum calls the value 5
       `SetEvery8Columns` (DispatchTypes.hpp:579-582) and ghostty resets to `TABSTOP_INTERVAL`
       (Terminal.zig:2309). Any other parameter asks for nothing either reference has: counted, not guessed. */
    case 'g':
    {
      const int what = (g->nArgs > 0) ? g->args[0] : 0;   /* `CSI g` is `CSI 0g`, DEC says so */
      if (what == 0) g->tabStop[g->cx] = 0;
      else if (what == 3)
      {
        memset(g->tabStop, 0, sizeof g->tabStop);
        g->tabsDefaults = 0;
      }
      else if (what == 5) tabs_reset(g);
      else ignored(g, RC_UN_MODE);
      break;
    }
    case 'c':
      /* Device Attributes -- and the one reply in this file that says something about the terminal it is
         *not*. Two facts have to be held at once, so read them in order.
         (1) The strings are conhost's own, not ConEmu's (deviation 8): `CSI c` answers `?61;4;6;7;14;21;22;23;
             24;28;32;42c` (minus the `;52` clipboard bit this renderer does not model) and `CSI > c` answers
             `>0;10;1c`. Upstream's pair is `?1;2c` and `>0;136;0c` (Ansi.cpp:3765-3784, ConEmu claiming xterm
             136 because MinTTY answers 77, rxvt 82 and GNU screen 83 and scripts gate on the number), and it is
             *not* copied because a chunk this library declines goes to the console unparsed -- conhost answers
             that one itself -- so a session would meet two terminal identities out of one question. Deviation
             8 exists for that reason, and the live leg (`caseReports`) asserts the exact bytes.
         (2) Within that string, `4` is **Sixel Graphics** -- Microsoft's own list, `adaptDispatch.cpp:1441`
             ("4 = Sixel Graphics"), and the same clone's `DeviceAttributes` really does have a SixelParser
             behind it. It is *not* the VT100 "132-column mode" bit, which is what an earlier draft of these
             notes asserted; corrected against the source, and the correction matters because it is the whole
             difference between "we claim a wider screen" (harmless) and "we claim to draw graphics" (not).
             We do not: the DCS arm above drops every payload and counts `RC_UN_DCS`, so a sixel stream sent
             here disappears silently.
         The claim is therefore inherited from the machine underneath and cannot be retracted in the reply:
         removing the bit would make this answer disagree with the one conhost gives for the declined half of
         the same session, which is the thing deviation 8 was written to prevent. The place a claim *can* be
         vetoed without falsifying a byte is the consumer that reads it, and that is where it was vetoed --
         jline4's family layer returns false for `Mode.SIXEL` regardless of DA1 (ANSI_TODO section 5), so
         `SixelGraphics` never emits the payload. The remaining half of this item is telling jline4 upstream,
         which is a public action and is left for a human to send; the text is prepared at
         `cache/p52/jline4-sixel-report.md`.
         Gated on "no parameters, or a single 0" exactly as upstream gates it; anything else is a query with a
         spelling neither this switch nor ConEmu has an answer for, and stays in the census. */
      if (g->priv == '>' && (!g->nArgs || g->args[0] == 0)) arm_report(g, RC_REP_DA2, 0, 0, 0);
      else if (!g->priv && (!g->nArgs || g->args[0] == 0)) arm_report(g, RC_REP_DA, 0, 0, 0);
      else unsupported(g, RC_UN_REPORT);
      break;
    case 'n':
      /* Device Status Report, and the cursor-position form of it. Upstream answers 5 with `ESC [ 0 n` and 6
         with `ESC [ row ; col R` computed from the live console (Ansi.cpp:3466-3483 → :2595-2605), where row
         and col are 1-based and measured from the *window*, not the buffer -- which is why the painter, not
         this parser, does the arithmetic: only it knows the row0 and the column clamp of the frame the query
         ends up in.
         The private spelling `CSI ? 6 n` is deliberately not answered. xterm's extended CPR replies
         `CSI ? row ; col R`, ConEmu replies the plain form to it, and a program that asked the extended
         question and got the plain answer reads a cursor position it did not ask for. Declining is the one
         option that cannot be wrong, so it is the option taken, and it is counted rather than silent. */
      if (!g->priv && g->nArgs == 1 && g->args[0] == 5) arm_report(g, RC_REP_DSR, 0, 0, 0);
      else if (!g->priv && g->nArgs == 1 && g->args[0] == 6) arm_report(g, RC_REP_CPR, 0, 0, 0);
      else unsupported(g, RC_UN_REPORT);
      break;
    /* Window manipulation. Upstream has a case (:3688-3762) and splits into three kinds: 8/22/23 reach
       Dump*Escape and do nothing, everything outside the list hits a TODO and does nothing, and 14/18/19/21
       call ReportTerminalPixelSize / ReportTerminalCharSize / ReportConsoleTitle.
       Not answered, and now for a narrower reason than "a renderer owns no input handle" -- it does, since
       the arms above armed a reply for the painter to write. Three of these four are answerable here and one
       is not: pixel size needs the client rectangle of a window this library does not have (ConEmu reaches
       its own GUI through ghConEmuWndDC), and a renderer that guessed it would be the first thing a
       resizable program anchored its next layout to. The two size-in-characters reports would be exact, and
       `18t`/`19t` are what a program asks when it wants the screen it already has; nothing in JLine or Nano
       asks, so the leg stays out until something that runs here does. This is the same rule that decided
       `rep`: modelled because a real writer emits it, not because the registry lists it. */
    case 't': unsupported(g, RC_UN_REPORT); break;
    default: unsupported(g, RC_UN_SUP); break;
  }
}

static void esc_dispatch(RcGrid *g, uint8_t interim, uint8_t final)
{
  (void)interim;
  switch (final)
  {
    case '7': g->saveX = g->cx; g->saveY = g->cy; break;   /* attributes are NOT saved (Ansi.cpp:2719) */
    case '8': clxy(g, g->saveY, g->saveX); break;
    case 'c': full_reset(g); break;                      /* RIS: see full_reset above */
    case 'D': line_down(g); break;                          /* IND */
    case 'E': g->cx = 0; line_down(g); break;               /* NEL */
    case 'M':                                                /* RI */
    {
      /* Reverse line feed moves the cursor up one, and at the top of the region -- or of the window, when
         no region is set -- it inserts a blank line there instead of stopping (Ansi.cpp:2094-2098: the
         second arm of that test is exactly `ScrollRegion && cy == ScrollStart`, and it hands off to
         LinesInsert(1), which scrolls [cy .. region bottom] down). Two consequences worth stating, because
         neither is the VT answer: a cursor above a narrowed region is *not* at its start, so it simply
         moves up -- LinesInsert would refuse it (:2136) and the third arm of the test is a plain
         SetConsoleCursorPosition; and IND, for contrast, never looks at gDisplayOpt at all
         (ForwardLF :2044-2080), so upstream the pair is asymmetric. Keeping RI region-aware and IND
         not-quite is the closest this model comes to the oracle without a scroll the painter cannot show;
         CONEMU_ANSI_DEFECTS.md records both halves. */
      int top, bot;
      region(g, &top, &bot);
      if (g->cy == gutter(g) || (g->regSet && g->cy == top))
      {
        if (g->cy >= top && g->cy <= bot) shift_region(g, 1, g->cy, bot, 1);
      }
      else clxy(g, g->cy - 1, g->cx);
      break;
    }
    /* Three ESC finals that used to be a bare `break`, which is the one thing the census cannot forgive:
       it makes a consumed-but-unmodelled sequence indistinguishable from one that never arrived. Each now
       has a *known* upstream body, and none of it touches the grid --
       `ESC g`  visual bell: upstream calls GuiFlashWindow (:2728-2731), which flashes the ConEmu *window*.
                That is a GUI call this renderer has no business making, and it is also why the caps should
                not advertise `flash` -- without it JLine falls back to `bel` (see the caps audit).
       `ESC H`  set tab stop: DumpKnownEscape(de_Ignored) at :2732-2735, with the issue number in the
                comment. There is no tab-stop state anywhere, which is what makes `CSI Z` inert too.
       `ESC =`/`ESC >` keypad modes: the same ignored call (:2745-2750). JLine's smkx/rmkx send them
                alongside `CSI ?h`, and the input-side keys they would select are not ours to change.
       Counted as modes, not as unknown finals: the effect is known to be nothing, so the frame stays
       trusted and no adopt is bought. */
    case 'g': ignored(g, RC_UN_MODE); break;
    /* HTS (`ESC H`) claims the column the cursor stands on and leaves the rest alone -- including the
     * defaults, which is what makes it a table rather than a flag. MSFT materializes the defaults on the
     * way (`:2648`) and sets the bit; the caps entry can now advertise `cbt`, which is the sequence this
     * row used to make unspellable. */
    case 'H': g->tabStop[g->cx] = 1; break;
    case '=': case '>': ignored(g, RC_UN_MODE); break;
    default: unsupported(g, RC_UN_SUP); break;
  }
}

/* ESC ( <c>: 0 selects the drawing set, B or anything else selects the default (Ansi.cpp:2751-2767). */
static void esc_charset(RcGrid *g, uint8_t designator, uint8_t c)
{
  if (designator == '(')
  {
    /* Both arms are real: upstream's `default` for the third byte sets VTCS_DEFAULT too (:2763-2765), so
       `ESC ( A` unloads the drawing set here exactly as it does there. This is the `smacs`/`rmacs` path. */
    g->charset = (c == '0') ? 1 : 0;
    return;
  }
  /* G1 (`ESC ) c`) and the Latin-1/UTF-8 selector (`ESC % G`) have no case upstream at all: they fall to
     `default: DumpUnknownEscape` (Ansi.cpp:2769-2770), which changes nothing -- so G1 is unreachable and the
     UTF-8 flag is never set, on either leg. Counted rather than silently eaten, for the same reason as
     `CSI p`: `ESC % G` is what a program that believes it is turning UTF-8 on writes, and the census is the
     only place that can still say so afterwards. No suspicion: the arm has been read, and it is inert. */
  ignored(g, RC_UN_SUP);
}

/* C0 controls that are not part of a sequence. Width-0 by the tables, so none of them paints a cell. */
static void control(RcGrid *g, uint16_t u)
{
  switch (u)
  {
    case 0x07: break;                                       /* BEL: beeps, never occupies a cell */
    case 0x08: if (g->cx > 0) g->cx = step_back_col(g, 1); break;  /* BS: moves, does not erase */
    case 0x09: g->cx = tab_next(g, g->cx); break;   /* the table, not the arithmetic it used to be */
    case 0x0A: newline(g); break;
    case 0x0D: g->cx = 0; break;
    default: break;                                         /* other C0, DEL: nothing */
  }
}

/* --------------------------------------------------------------- the parser -------------------- */

static void push_arg(RcGrid *g, int v)
{
  if (g->nArgs < RC_CSI_ARGS) { g->args[g->nArgs++] = v; return; }
  /* The list is full. The sequence still acts on the sixteen it kept, which is what ConEmu's ArgV does
   * (Ansi.h:174) and what RenderCheck's "16th argument kept" pins; what it did *not* do until #74 was leave
   * any trace of the seventeenth. A clamp that bites silently is indistinguishable from a parameter list that
   * fitted, and the caller reading a report cannot tell "it asked for three" from "it asked for forty".
   * Counted per argument, not per sequence, because that is the number that says how much was lost. */
  g->nArgTrunc++;
}

static void csi_start(RcGrid *g)
{
  g->mode = RC_CSI;
  g->priv = 0;
  g->csiColon = 0;
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

/* What an OSC payload claimed before its first ';'. The digits are accumulated rather than collapsed, because
 * the codes acted on below are 0/1/2 (title), 9 (ConEmu's private family) and 133 (FTCS) -- 133 is three
 * digits, so "the first digit, or 'other'" stopped being enough. Two guards keep the answer honest:
 * saturation at RC_OSC_CODE_MAX, so that 1000000 and 10000000000 cannot wrap into something recognised, and
 * the leading-zero test, because both references dispatch on the code as the *string* it was -- "133" matches
 * in ghostty's table (osc.zig:955) and in MSFT's (OutputStateMachineEngine.hpp:228), "0133" matches nothing. */
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

/* ------------------------------------------------------------- OSC 133 (FTCS) ------------------ */

/* The semantic-prompt family. ConEmu has no case for it at all -- its OSC switch reads the digits, fails the
 * `ArgSZ[1] == ';'` guard a title needs (Ansi.cpp:3845, where "133;A" has a '3' at index 1), and consumes the
 * payload in silence -- so nothing below is a parity question with the fallback leg: the bytes reach only this
 * model, and what they mean is what the two implementations that do read them agree on (ghostty's
 * osc/parsers/semantic_prompt.zig plus Terminal.zig:2091-2229, MSFT's adaptDispatch.cpp:3692-3764 plus
 * Row.cpp:1248-1288). That silence is also what makes it safe for the calling application's own prompt to emit them: nothing
 * else in the chain would react.
 *
 * One consequence of the same fact, worth stating plainly because it is the only place a 133 could disagree
 * with the fallback leg: `A`, `L` and `N` move the cursor down. A chunk this model painted moves the console
 * cursor too, so the screen is right; a chunk it *declined* goes through ConEmuHk, which ignores the 133 and
 * so prints one row higher. The legs cannot be made equal here without inventing 133 support in ConEmu, and
 * the difference is bounded by that one row. */

/* Field `idx` of a `;`-split payload, exactly as ghostty's split loop defines it
 * (semantic_prompt.zig:151-176): a field runs to the next ';' or to the end. */
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

/* `k=<i|r|c|s>`: the first field carrying that key decides, and a value that is not exactly one character of
 * the four is no value at all (`value.len == 1` + PromptKind::init, semantic_prompt.zig:207/:292), which puts
 * the caller back on the default `i`. MSFT has no `k` at all -- every prompt row is primary there -- so this
 * is ghostty's rule taken whole. */
static int ftcs_continuation(const uint16_t *p, int n)
{
  int off, len;
  for (int i = 1; ftcs_field(p, n, i, &off, &len); i++)
  {
    int e = 0;
    while (e < len && p[off + e] != '=') e++;
    if (e >= len) continue;                         /* a bare field names no key: skipped, still valid */
    if (!ftcs_is(p, off, e, "k")) continue;
    if (len - e - 1 != 1) return 0;
    const uint16_t v = p[off + e + 1];
    return (v == 'c' || v == 's');
  }
  return 0;
}

/* D's exit code is the payload's second field, unkeyed -- ghostty special-cases it before any key lookup
 * (:168-176) and MSFT reads parts[1] (:3735). The two disagree on a code that is not a number: ghostty calls
 * it success (0), MSFT calls it an error (UINT_MAX). MSFT's answer is followed, because it is the one that
 * cannot hide a failure. Returns 0 for "there was no second field" (MSFT leaves the row's category alone),
 * 1 for a code, -1 for one that did not read as a number. */
static int ftcs_exit(const uint16_t *p, int n, int *code)
{
  int off, len;
  *code = RC_EXIT_UNKNOWN;
  if (!ftcs_field(p, n, 1, &off, &len)) return 0;
  /* Nine digits, not the CSI parser's saturating run: this value is a *claim* -- an index into a table, an
   * exit code -- and a claim arrived at by truncation would be a different claim. -1 means "there is no
   * answer to give", which every caller already treats as refusal rather than zero. */
  if (len < 1 || len > 9) return -1;
  long v = 0;
  for (int i = 0; i < len; i++)
  {
    const uint16_t u = p[off + i];
    if (u < '0' || u > '9') return -1;               /* a leading '-' is MSFT's failure case too */
    v = v * 10L + (long)(u - '0');
  }
  *code = (int)v;
  return 1;
}

/* Start a prompt on the cursor's row. A row already carrying one -- or a command's verdict -- keeps what it
 * has: that is MSFT's guard, `if (!_promptData.has_value())` (Row.cpp:1263), and overwriting would throw away
 * the exit code of the command whose text is still on screen. A continuation is different in kind, because it
 * is this model's own guess (ftcs_line_ended) rather than something a shell said, so an explicit prompt
 * replaces it -- which is exactly what ghostty's ordering produces, its `index()` defer flags the new row and
 * the `A` that follows stamps `.prompt` over it. */
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

/* `A`, `L` and `N` begin a fresh line first: nothing if the cursor already sits at the left margin, otherwise
 * CR and a line feed (Terminal.zig:2211-2229 -- the *margin*, and this model has no left/right margin mode, so
 * that is column 0). Doing it before the mark is what makes the mark land on the row the prompt starts on. */
static void ftcs_fresh_line(RcGrid *g)
{
  if (g->cx == 0) return;
  g->cx = 0;
  line_down(g);
}

/* The whole 133 command, payload in hand: everything after the `133;`. Returns 0 when the grammar rejects it,
 * which is the pair of rules both references share -- field 0 must be exactly the action letter (ghostty wants
 * `data[1] == ';'`, MSFT wants `parts[0].size() == 1`; one claim, expressed twice), `L` allows no options at
 * all (:379, so even `133;L;` is nothing), and an unknown letter is nothing. Anything wrong *inside* the
 * options is not a rejection: unkeyed fields, unknown keys, empty and duplicate values are all skipped and the
 * command still lands (ghostty keeps the options verbatim and only splits them on demand). */
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
      /* Both say "the prompt ended and the user's input begins"; `I` is the variant whose input stops at the
       * end of the line rather than at the next 133 (ghostty's clear_eol, Terminal.zig:2174-2179). Neither
       * touches the row -- the row keeps the prompt it began with, because the mark's whole purpose is to say
       * where the command started. */
      g->semanticContent = RC_SC_INPUT;
      g->semanticClearEol = (uint8_t)(a == 'I');
      return 1;
    case 'C':
      g->semanticContent = RC_SC_OUTPUT;
      g->semanticClearEol = 0;
      /* The fish heuristic, and the only place a mark is ever taken away (Terminal.zig:2185-2198): a row that
       * is still at column 0 when its output starts was never a prompt line, it was the continuation of one.
       * fish has no PS2 and does not send `k=c`, so without this its wrapped prompts stay marked. */
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
      /* Upstream's search, row for row: the first row at or above the cursor that carries a mark takes the
       * verdict, and the search stops there (textBuffer.cpp:3486-3499, `for (y = cursor.y; y >= 0; y--)`).
       * It is a search rather than a stored "current command" because a command's output may have scrolled the
       * prompt several rows up -- and because a second `D` with no prompt between it lands on the same row and
       * replaces its code, which is what MSFT does too. */
      for (int r = g->cy; r >= 0 && r < g->rows; r--)
      {
        if (RC_ST(g, r).mark == RC_PM_NONE) continue;
        if (have != 0)
          RC_ST(g, r).mark = (uint8_t)((have == 1 && code == 0) ? RC_PM_SUCCESS : RC_PM_ERROR);
        return 1;
      }
      return 1;                              /* a verdict with nothing to mark: the code is still the log's */
    }
    default: return 0;
  }
}


/* ------------------------------------------------- OSC 4 / 10 / 11 -- the palette (I34) -------- */

/* ConEmu parses this family and does nothing with it -- Ansi.cpp:3845's guard accepts "4;..." because the
   semicolon is at index 1, and then its switch has no case for 4, 10, 11 or 104 -- so nothing below is a
   parity question with the fallback leg. The grammar is MSFT's, because MSFT implements it:
   OutputStateMachineEngine.cpp:955-1000 (the `index;spec` pairs), :1062-1092 (the resource walk) and
   types/utils.cpp:180-344 (the spec forms and their scaling). */

static int hex_digit_of(uint16_t u)
{
  if (u >= '0' && u <= '9') return u - '0';
  if (u >= 'a' && u <= 'f') return u - 'a' + 10;
  if (u >= 'A' && u <= 'F') return u - 'A' + 10;
  return -1;
}

/* One component: 1..4 hex digits scaled to 8 bits. MSFT scales the `rgb:` form by bit replication
   (`f`->0xFF, `ff`->0xFF, `fff`->0xFF, `ffff`->0xFF) but the `#` form by a 0x10 multiplier, which makes
   `#f` 0xF0 -- two spellings of one colour, two answers. This uses the replication rule for both, which is
   also what `rgb:f/f/f` gives in MSFT, so the only divergence from the reference is the internal
   inconsistency it drops. */
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

/* `#RGB` / `#RRGGBB` / `#RRRRGGGGBBBB` (equal widths only -- MSFT's size gate at utils.cpp:236 accepts
   exactly 4, 7, 10 or 13 units) or `rgb:r/g/b` with 1..4 digits per component and widths that need not
   match (its size gate is 9..18 units, which is the same rule stated over the whole string).
   Anything else -- including an X11 colour name, which this build does not resolve (I34) -- returns 0.
   The result is a COLORREF, 0x00BBGGRR, because that is what the fold consumes. */
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
      if (a < 0) a = i; else if (b < 0) b = i; else return 0;      /* a third slash is not a colour */
    }
    if (a < 0 || b < 0) return 0;
    if (!comp_of(f + 4, a - 4, &c[0])) return 0;
    if (!comp_of(f + a + 1, b - a - 1, &c[1])) return 0;
    if (!comp_of(f + b + 1, n - b - 1, &c[2])) return 0;
  }
  else return 0;

  *out = (c[2] << 16) | (c[1] << 8) | c[0];
  return 1;
}

/* The k-th `;`-separated field of an OSC payload, counted from after the code's own separator. */
static int osc_field(const RcGrid *g, int sep, int k, int *first, int *len)
{
  /* `sep < 0` means the payload has no `;` after the code at all -- `]104` and `]110` are exactly that, and
     reading them as if the code itself were field zero would reset table entry 104. */
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

/* A decimal field with no sign and no trailing junk; 0 on anything else, which is how MSFT's
   StringToUint failure is read here. */
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
  /* Two ranges, two tables (see Render.h): below 16 the entry is a console attribute's colour, which is
     both what the fold searches and what the console is told; at or above 16 it is only the RGB a
     256-colour index means, because a 4-bit attribute has nowhere else to put it. */
  if (idx < 16)
  {
    g->pal16[idx] = rgb;
    g->palTouched |= (uint16_t)(1u << idx);   /* the painter writes back only the bits set here (I34) */
  }
  else g->palette[idx] = rgb;
  g->attr = rc_attr(g, &g->sgr);   /* the colour under the current pen may now fold differently */
}

/* The nearest index for a colour, using the same fold the cells go through. `shift` picks the nibble. */
static int nearest_index(const RcGrid *g, uint32_t rgb)
{
  WORD n = 0;
  Far3Color::Color2FgIndex((COLORREF)rgb, n, (const COLORREF*)g->pal16);
  return (int)(n & 0xF);
}

static void palette_osc(RcGrid *g, int code, int sep, int terminated)
{
  if (!terminated) { unsupported(g, RC_UN_OSC_OTHER); return; }   /* same rule as titles and 133 */

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
        arm_report(g, RC_REP_OSC, 4, idx < 16 ? g->pal16[idx] : g->palette[idx], idx);
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
    /* MSFT walks the resources forward one per field (:803-819), so `10;a;b` is 10 then 11, and a field it
       cannot parse still consumes a step. The answer to a query is the colour the console will really show,
       which for a default means the index it was folded to -- not the RGB that was asked for (I34). */
    int resource = code;
    for (int k = 0; osc_field(g, sep, k, &first, &len); k++, resource++)
    {
      if (resource > 12) { unsupported(g, RC_UN_OSC_OTHER); break; }
      if (len == 1 && g->osc[first] == '?')
      {
        const uint32_t q = g->pal16[(resource == 10) ? (g->defAttr & 0xF) : ((g->defAttr >> 4) & 0xF)];
        arm_report(g, RC_REP_OSC, resource, q, 0);
        continue;
      }
      uint32_t rgb = 0;
      if (!color_spec_of(g->osc + first, len, &rgb)) { unsupported(g, RC_UN_OSC_OTHER); continue; }
      const int idx = nearest_index(g, rgb);
      if (resource == 10) g->defAttr = (uint16_t)((g->defAttr & 0xFFF0) | idx);
      else if (resource == 11) g->defAttr = (uint16_t)((g->defAttr & 0xFF0F) | (idx << 4));
      else { unsupported(g, RC_UN_OSC_OTHER); continue; }         /* 12, the cursor colour, has no slot */
      g->attr = rc_attr(g, &g->sgr);
    }
    return;
  }

  if (code == 104)
  {
    /* No fields resets the table; with fields, MSFT stops at the first index it cannot parse, and its own
       comment says that is xterm's choice over VTE's (:846). */
    if (!osc_field(g, sep, 0, &first, &len))
    {
      for (int i = 0; i < 256; i++) g->palette[i] = RgbMap[i];
      for (int i = 0; i < 16; i++) g->pal16[i] = (uint32_t)Far3Color::GetStdPalette()[i];
      g->palTouched = 0xFFFF;
      g->attr = rc_attr(g, &g->sgr);
      return;
    }
    for (int k = 0; osc_field(g, sep, k, &first, &len); k++)
    {
      int idx = 0;
      if (!dec_of(g->osc + first, len, &idx)) { unsupported(g, RC_UN_OSC_OTHER); break; }
      if (idx > 255) { unsupported(g, RC_UN_OSC_OTHER); continue; }
      if (idx < 16) { g->pal16[idx] = (uint32_t)Far3Color::GetStdPalette()[idx];
                      g->palTouched |= (uint16_t)(1u << idx); }
      else g->palette[idx] = RgbMap[idx];
    }
    g->attr = rc_attr(g, &g->sgr);
    return;
  }

  if (code == 110 || code == 111)
  {
    /* MSFT resets these only on an empty payload and notes that xterm and VTE disagree otherwise (:855-866).
       The default attribute returns to what the console had when this handle opened, which is `defAttrSeed`. */
    if (osc_field(g, sep, 0, &first, &len)) { unsupported(g, RC_UN_OSC_OTHER); return; }
    g->defAttr = (uint16_t)((code == 110) ? ((g->defAttr & 0xFFF0) | (g->defAttrSeed & 0xF))
                                          : ((g->defAttr & 0xFF0F) | (g->defAttrSeed & 0xF0)));
    g->attr = rc_attr(g, &g->sgr);
    return;
  }
}

/* ------------------------------------------------- OSC 9 -- the safe subset (T7) --------------- */

/* ConEmu's private family is the one place where "count it and do nothing" was itself the safety property:
 * the #687 report is an OSC 9;7 that runs a process. MSFT implements the same dialect and draws the same
 * line -- DoConEmuAction (adaptDispatch.cpp:3558-3647) acts on 9;4, 9;9 and 9;12 and sends EVERYTHING ELSE
 * to UnknownSequence() -- so the boundary is no longer ours to guess, and the dangerous subcommands stay
 * unanswered here exactly as they are unanswered there.
 * Nothing below can move the process. The taskbar pair is *reported*, because a renderer owns no window and
 * therefore has no taskbar to paint; the directory is *stored as text*, because a working directory taken
 * from an output stream is a prompt injection with a path on it. Both are read through the seam by whoever
 * asked for them. */

/* MSFT's til::is_legal_path screens the ASCII range through a path filter and lets everything above it
   through; its own test states the pair that survives and the one that does not
   (`C:\Users\...\Users\;Why not` yes, `"Quote-un-quote users` no -- ut_til/string.cpp:247-249). Control
   characters and the double quote are what that filter rejects in the range that matters here. */
static int path_is_legal(const uint16_t *p, int n)
{
  if (n <= 0) return 0;
  for (int i = 0; i < n; i++)
    if (p[i] < 0x20 || p[i] == 0x7F || p[i] == L'"') return 0;
  return 1;
}

static void osc9_action(RcGrid *g, int sep, int terminated)
{
  /* A DCS never reaches here: osc_finish() classifies RC_OSC_DCS before this arm, so `\eP9;7;calc.exe\e\\`
     cannot be read as a subcommand by any path the parser has. */
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
    /* Out of range is refused outright (MSFT :3596-3600 returns without applying); out of *bounds upward*
       on progress is clamped instead (:3601-3605), because "750%" is a program that means 100%. */
    if (state > 4) { unsupported(g, RC_UN_OSC_PRIV); return; }
    if (progress > 100) progress = 100;
    g->taskbarState = state;
    g->taskbarProgress = progress;
    g->taskbarSeen = 1;
    return;
  }

  if (sub == 9)
  {
    if (!osc_field(g, sep, 1, &first, &len)) { unsupported(g, RC_UN_OSC_PRIV); return; }
    int a = first, n = len;
    /* ConEmu's documented spelling wraps the path in quotes. MSFT strips one pair when it finds one and
       takes the value anyway when it does not (:3614-3621) -- both are the same generosity, and the second
       is the one that keeps `9;9;/tmp` working. */
    if (n >= 3 && g->osc[a] == L'"' && g->osc[a + n - 1] == L'"') { a++; n -= 2; }
    if (!path_is_legal(g->osc + a, n) || n > RC_TITLE_MAX) { unsupported(g, RC_UN_OSC_PRIV); return; }
    for (int i = 0; i < n; i++) g->cwd[i] = g->osc[a + i];
    g->nCwd = n;
    return;
  }

  if (sub == 12)
  {
    /* "treat this position as the prompt start". MSFT's own comment says it is basically 133;B
       (:3631-3637), so it goes into the same function with the same argument rather than into a copy of
       what that argument does -- the row marking, the continuation claim and the exit-code search all come
       along for free, and cannot drift apart from it later. */
    const uint16_t B = L'B';
    if (ftcs_apply(g, &B, 1)) return;
    unsupported(g, RC_UN_OSC_PRIV);
    return;
  }

  unsupported(g, RC_UN_OSC_PRIV);   /* 1, 2, 3, 6, 7, 42 and every other subcommand: counted, never run */
}


/* The OSC/DCS payload is over -- BEL, ST, or abandoned by an ESC or a CAN/SUB. One classification, made
 * here rather than at the introducer, because the parser cannot tell a title from "\e]9;7;calc.exe"
 * until it has read the payload.
 *
 * Nothing here touches the grid, which is why the whole family used to be invisible: a title or a
 * GuiMacro changes state *outside* the cells, so no grid witness can ever show it and the counter is
 * the only record that the stream contained one.
 *
 * `terminated` says the sequence reached its end. An unterminated title is counted and dropped --
 * neither console applies a title it never saw the close of (upstream keeps eating past the ESC,
 * deviation #1; we abandon and restart, so we get the colour the bytes asked for instead). The 9 family
 * is counted either way: the thing worth recording is "this stream asked ConEmu to run something", and
 * this renderer never runs anything -- that is the whole of the #687 answer. */
/* The title family (0/1/2). ConEmu's guard is reproduced byte for byte (Ansi.cpp:3845): the digit, then
   ';' at index 1 -- so "]10;foo" is NOT a title -- then at least one character of payload, so "]0;" alone
   sets nothing. */
static void osc_title(RcGrid *g, int code, int sep, int terminated)
{
  (void)code;
  if (sep != 1 || g->nOsc <= 2 || !terminated) { unsupported(g, RC_UN_OSC_OTHER); return; }
  /* What EscCopyCtrlString hands on (Ansi.cpp:2276-2283): one pair of surrounding double quotes removed.
     An empty result is still a title -- "]0;""ST" sets the title to "", it does not leave it alone; the
     gsInitConTitle argument at :3851 is CEStr::c_str's *null* substitute (it returns the default only when
     the buffer was never allocated), not an empty one. */
  int from = 2, len = g->nOsc - 2;
  /* The sink keeps far more than a title now, so the title's own cap became this family's business: clip
     first, then strip, which is the order the shared buffer used to force by stopping collection at
     RC_TITLE_MAX units -- "0;" counted, which is why the longest applied title is two units short of the
     cap. A payload the sink itself could not hold (oscClip) says so through the same counter. */
  const int clipped = (g->nOsc > RC_TITLE_MAX) || g->oscClip;
  if (len > RC_TITLE_MAX - 2) len = RC_TITLE_MAX - 2;
  if (len > 1 && g->osc[from] == '"' && g->osc[from + len - 1] == '"') { from++; len -= 2; }
  for (int i = 0; i < len; i++) g->osc[i] = g->osc[from + i];
  g->nOsc = len;
  g->titlePending = 1;                 /* the painter applies it; a later title in the chunk replaces it */
  g->nTitleSet++;
  if (clipped) g->nTitleTrunc++;
}

/* FTCS (133). `sep == 3` is the guard's form of "the payload really opens with 133;" -- the length of the
   digit run this code was read from -- so "]0133;A" (leading zero, RC_OSC_CODE_MAX) and "]1334;A" both fail
   it. An unterminated one is dropped rather than applied: a half-read command says where the shell meant to
   mark a row but not what it meant there, and a mark in the wrong place is worse than no mark. A rejection
   is counted as OSC_OTHER and not as suspicious -- 133 moves the cursor only on its own say-so
   (ftcs_fresh_line), which this model then applied faithfully or not at all, so the grid is never left
   describing a screen that is not there. */
static void osc_ftcs(RcGrid *g, int code, int sep, int terminated)
{
  (void)code;
  if (sep != 3 || !terminated) { unsupported(g, RC_UN_OSC_OTHER); return; }
  if (!ftcs_apply(g, g->osc + sep + 1, g->nOsc - sep - 1)) unsupported(g, RC_UN_OSC_OTHER);
}

/* `]2004;...` is DECSET 2004 spelled as an OSC, which is the shape MSFT's ConEmu-compatibility arm takes
   (`DoConEmuAction`, adaptDispatch.cpp:3558). The mode is inert here for the reason ANSI_SUPPORTS section 3
   gives -- this library is the output leg and never reads a paste -- so the counter that wants the vote is
   `bracketed paste`, the row whose whole sentence is about that mode. Counting it as `other osc` instead
   records it as a code this build has no case for, which is a different fact. */
static void osc_bracket(RcGrid *g, int code, int sep, int terminated)
{
  (void)code; (void)sep; (void)terminated;
  unsupported(g, RC_UN_DECBP);
}

/* OSC 9's dangerous half -- sleep, MessageBox, set-env, GuiMacro, DoProcess -- is counted and *never run*,
   which is the whole #687 answer; `osc9_action` owns that boundary. DCS is separated before this table is
   reached, so a `\eP9;7;...` can only arrive as RC_UN_DCS. */
static void osc_private9(RcGrid *g, int code, int sep, int terminated)
{
  (void)code;
  osc9_action(g, sep, terminated);
}

/* The clipboard family (52): `ESC ] 52 ; Pc ; Pd` with Pd base64 of the text, per xterm's ctlseqs, and the
   same grammar ghostty parses (`osc/parsers/clipboard_operation.zig:20-40`). Three of its rules are copied
   deliberately and one is ours.

   COPIED -- an empty selection field means the clipboard (`52;;data`, ghostty :24-31); `Pd` of exactly `?` is
   a *read* and not a write (ghostty decides that downstream too, :685 / Surface.zig:1046); and a bad payload
   is refused whole rather than partially decoded -- ghostty's own words for the same choice are that
   corrupted data "must not be silently discarded, since that turns corrupted data into apparently valid
   data" (`kitty/clipboard_write.zig:169-170`), and its decoder rejects whitespace inside the base64 rather
   than skipping it the way the SIMD library underneath would (`simd/base64.zig:98-110`).

   OURS -- the selection whitelist. ghostty folds any letter it does not know onto the standard clipboard
   (`stream_terminal.zig:678-682`) because on X11 and on macOS `p`/`s` name something real: primary is a
   live buffer there, and macOS answers it with nil and reports unsupported (`NSPasteboard+Extension.swift:
   137-152`). A Windows console has exactly one clipboard and no other target to fold *onto*, so accepting
   `p` and quietly writing the clipboard would be a letter answered by a different thing than the one asked
   for. `c` and the empty field are honoured; every other spelling is refused and counted. MSFT is the third
   data point and the one that shows what folding costs: it parses the family
   (`OutputStateMachineEngine.hpp:222` `SetClipboard = 52`) and then throws the field away -- ":1097",
   "Currently the first parameter `Pc` is ignored" -- so `52;p;data` writes the clipboard there, which is its
   own unfinished business rather than a design to copy. It also defaults the feature to *allowed*
   (`compatibility.allowOSC52`, `ControlProperties.h:59`), as does ghostty (`clipboard-write = .allow`); this
   build defaults to refused, for the reason I36 gives: those two are terminals somebody configured, and a
   renderer inside someone else's process has no such configuration to lean on.

   The read is refused whatever the policy says, and that is the one place this library is stricter than
   ghostty: its reply goes straight back into the pty (`stream_terminal.zig:820-826`), which for a terminal
   we own means putting the user's clipboard content into the console's *input* stream -- an application
   could read it and a second one could be fed it as keystrokes. ghostty's answer to that is a dialog
   (`clipboard-read` defaults to `ask`); with no window to show one in, the only honest value is no. */
static int b64_value(uint16_t u)
{
  if (u >= 'A' && u <= 'Z') return u - 'A';
  if (u >= 'a' && u <= 'z') return 26 + (u - 'a');
  if (u >= '0' && u <= '9') return 52 + (u - '0');
  if (u == '+') return 62;
  if (u == '/') return 63;
  return -1;
}

/* Strict base64 into `dst`. Returns the number of bytes, 0 for an empty payload, or -1 for anything that is
   not a whole, well-formed encoding -- never a partial decode, and never a decode that drops information.
   Whitespace is rejected rather than skipped (see the note above), which also means a payload an application
   wrapped over several lines is refused as one unit and shows up in the census instead of arriving mangled.
   Canonicality is checked the way RFC 4648 section 3.5 asks: the unused bits of a final group must be zero,
   so a tail that decodes to "the same byte plus a hidden character" is refused too. */
int rc_b64_decode(const uint16_t *src, int n, uint8_t *dst, int cap)
{
  if (n < 0) return -1;
  if (n == 0) return 0;

  /* Alphabet first: every unit is a data character or padding, nothing else. */
  int pad = 0;
  while (pad < n && src[n - 1 - pad] == '=') pad++;
  if (pad > 2) return -1;
  const int body = n - pad;
  for (int i = 0; i < body; i++) if (b64_value(src[i]) < 0) return -1;
  for (int i = body; i < n; i++) if (src[i] != '=') return -1;   /* padding is a suffix or nothing */

  const int tail = body % 4;
  if (tail == 1) return -1;                        /* one character encodes no byte */
  if (pad && tail == 0) return -1;                 /* `ABCD==`: padding after a complete group */
  if (pad == 1 && tail != 3) return -1;
  if (pad == 2 && tail != 2) return -1;
  /* No `(body + pad) % 4` test here on purpose: an unpadded tail (`SGVsbG8` for `Hello`) is legal, which is
     the `.optional` padding ghostty decodes with, and the two lines above already pin the padded forms down. */

  long out = (long)(body / 4) * 3;
  if (tail == 2) out += 1;
  else if (tail == 3) out += 2;
  if (out > cap) return -1;                        /* over the cap: refuse the whole request */

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
    /* The bits that carried no character are at the bottom of the *group*, not of the accumulator: the
       12 or 18 bits of this tail sit at bits 23..12 or 23..6 because of the shifts above. Masking the
       accumulator's low nibble instead was this function's first bug, caught by the non-canonical-tail
       case in gm_clipboard -- `QR==` is a legal-looking encoding of 'A' with a hidden bit set. */
    const unsigned unusedBits = (tail == 2) ? ((acc >> 12) & 0x0Fu) : ((acc >> 6) & 0x03u);
    if (unusedBits != 0) return -1;                 /* RFC 4648 3.5: they must be zero */
    dst[o++] = (uint8_t)(acc >> 16);
    if (tail == 3) dst[o++] = (uint8_t)((acc >> 8) & 0xFFu);
  }
  return o;
}

static void osc_clip(RcGrid *g, int code, int sep, int terminated)
{
  (void)code;
  /* An abandoned OSC is the framing case every family shares: counted as `other osc`, never applied. */
  if (!terminated) { unsupported(g, RC_UN_OSC_OTHER); return; }

  /* `sep` is where the code's digits ended, so the payload opens at sep+1 and must hold a second ';' --
     `52;data` has no selection field at all and is not a request anyone can honour. */
  int s2 = -1;
  for (int i = sep + 1; i < g->nOsc; i++) { if (g->osc[i] == ';') { s2 = i; break; } }
  if (s2 < 0) { g->nClipBad++; unsupported(g, RC_UN_OSC_CLIP); return; }

  /* The selection field: empty means the clipboard, `c` means the clipboard, anything else is a target this
     platform has no place for. */
  const int selLen = s2 - (sep + 1);
  if (!(selLen == 0 || (selLen == 1 && g->osc[sep + 1] == 'c')))
  { g->nClipSel++; unsupported(g, RC_UN_OSC_CLIP); return; }

  const int from = s2 + 1, len = g->nOsc - from;
  if (len == 1 && g->osc[from] == '?') { g->nClipRead++; unsupported(g, RC_UN_OSC_CLIP); return; }

  /* The sink clipped this payload, so what we hold is a prefix and a prefix of base64 is not a message. */
  if (g->oscClip || len > RC_CLIP_ENC_MAX) { g->nClipBad++; unsupported(g, RC_UN_OSC_CLIP); return; }

  uint8_t text[RC_CLIP_MAX];
  const int n = rc_b64_decode(g->osc + from, len, text, RC_CLIP_MAX);
  if (n < 0) { g->nClipBad++; unsupported(g, RC_UN_OSC_CLIP); return; }
  for (int i = 0; i < n; i++)
  {
    /* CF_UNICODETEXT is a NUL-terminated string, so a payload that decodes to text containing a NUL cannot
       be stored at all. Refusing the request says so; storing the prefix would hand the user half a paste. */
    if (text[i] == 0) { g->nClipBad++; unsupported(g, RC_UN_OSC_CLIP); return; }
  }
  if (rc_clipboard_policy() != RC_CLIP_ALLOW) { unsupported(g, RC_UN_OSC_CLIP); return; }

  for (int i = 0; i < n; i++) g->clip[i] = text[i];
  g->nClip = n;
  g->clipPending = 1;                            /* the painter writes it; a later OSC 52 replaces it */
  g->nClipSet++;
}

/* A family of OSC codes: the numbers it owns, the name the report and the gate give it, and what it does
 * with a payload.
 *
 * This table replaces a chain of six `if (code == ...)` tests in one function. The chain worked; what it
 * could not say is what the table can be checked against -- which codes are spoken for (so adding a family
 * cannot quietly collide with one already handled), that every family either acts or counts (I21's rule,
 * which the old chain satisfied only because its last line happened to be a count), and what each family is
 * called when a report names it. ghostty is the model for the shape: one parser per sequence under
 * `src/terminal/osc/parsers/` behind one dispatch; MSFT does the same thing with a VTID-keyed switch
 * (`OutputStateMachineEngine.hpp:228`). Handlers stay in this file and the parser still touches no console
 * API, so this is structure, not a new layer.
 *
 * Table order is precedence. The ownership sets below are disjoint, and `geo_osc_families` proves it rather
 * than trusting it -- which is also what makes the order free to read as priority rather than as a
 * load-bearing accident. */
struct RcOscFamily
{
  const char *name;
  int  (*owns)(int code);
  void (*apply)(RcGrid *g, int code, int sep, int terminated);
};

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
  /* The tail is the invariant: a code no family owns is counted, never ignored. `geo_osc_families` is the
     leg that shows each owned code reaches an action or a count of its own, so this line cannot quietly
     become the only thing standing between an OSC and silence. */
  unsupported(g, RC_UN_OSC_OTHER);
}


/* ------------------------------------------------------- the SGR echo to ConEmuHk -------------- */

/* One unit of the sequence being parsed. `capLost` says the sequence outgrew the capture, so its
 * dispatch must not echo a prefix of it -- half an SGR is worse than none. */
static void cap_push(RcGrid *g, uint16_t u)
{
  if (g->nCap < RC_SGR_CAP_MAX) g->cap[g->nCap++] = u;
  else g->capLost = 1;
}

/* A sequence starts at an ESC -- including the one that abandoned an OSC payload, which our parser
 * re-examines as an introducer (deviation #1), so the capture restarts with it. */
static void cap_begin(RcGrid *g, uint16_t esc)
{
  g->capLost = 0;
  g->cap[0] = esc;
  g->nCap = 1;
}

/* The sequence just dispatched changed the attributes, so the fallback leg has to be told about it in
 * the same words it would have read from the stream. */
static void sgr_captured(RcGrid *g)
{
  if (g->capLost || g->nCap <= 0) { if (g->capLost) g->nSgrDrop++; return; }
  if (g->nSgrEcho + g->nCap > RC_SGR_ECHO_MAX) { g->nSgrDrop++; return; }
  for (int i = 0; i < g->nCap; i++) g->sgrEcho[g->nSgrEcho + i] = g->cap[i];
  g->nSgrEcho += g->nCap;
}

/* Does this CSI final byte change the attribute state? Mirrors the dispatch: a private byte makes
 * ConEmu drop the whole SGR, so '?31m' must not be echoed either. DECSTR's '!' is an interim byte, and
 * 'm' has no interim of its own, so only the 'p' case has to look at the set -- but both cases gate on
 * `priv`, because upstream puts the two ranges in one buffer and tests its length (see csi_dispatch). */
static int echoes(const RcGrid *g, uint8_t final)
{
  if (final == 'm') return !g->priv;
  if (final == 'p') return interim_is(g, '!') && !g->priv;   /* DECSTR resets the attributes */
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
  if (!dst || cap < g->nClip) return -1;          /* the same rule as rc_title_take: losing one is a bug */
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
  if (!dst || cap < g->nOsc) return -1;            /* nothing cleared: the title stays pending */
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
  if (--g->reportLen == 0) g->reportHead = 0;        /* empty is (0,0), so a reset model reads as a fresh queue */
  return kind;
}

void rc_report_result(RcGrid *g, int written)
{
  if (!g) return;
  if (written) g->nReportOk++;
  else g->nReportFail++;
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
        if (u >= 0x30 && u <= 0x3F)                  /* parameter bytes, ';' and the private range */
        {
          cap_push(g, u);
          if (u == ';')
          {
            /* ';' always pushes, even with no digits: \e[;31m is [0,31] (Ansi.cpp:1764) */
            push_arg(g, g->digit ? g->cur : 0);
            g->digit = 0; g->cur = 0;
          }
          else if (u >= '0' && u <= '9')
          {
            g->digit = 1;
            g->cur = (g->cur > RC_ARG_MAX / 10) ? RC_ARG_MAX : g->cur * 10 + (u - '0');
          }
          else
          {
            /* ':' is 0x3A, so ConEmu reads it as a Pvt byte and drops the whole sequence: the colon form
               of SGR 38 loses its colour here too (I10 parity, \u00a713.2). Remembered separately so the
               count says "a colon sequence went past" rather than hiding it among the mode sets. */
            if (u == ':') g->csiColon = 1;
            g->priv = u;                             /* '?' '>' '<' '=' '/' ':' -- Pvt in ConEmu */
          }
          i++;
          continue;
        }
        if (u >= 0x20 && u <= 0x2F)                  /* intermediates: ' ' before 'q', nothing else we model */
        {
          cap_push(g, u);
          interim_push(g, (uint8_t)u);
          i++;
          continue;
        }
        if (u >= 0x40 && u <= 0x7E)                  /* final */
        {
          if (g->digit) push_arg(g, g->cur);         /* a trailing empty parameter is NOT a zero */
          g->mode = RC_GROUND;
          cap_push(g, u);
          if (echoes(g, (uint8_t)u)) sgr_captured(g);
          csi_dispatch(g, (uint8_t)u);
          /* One票 per sequence for the colon form, whichever final it carried: this is the number that
             says whether the ConEmu-parity decision in \u00a713.2 ever costs a real application anything. */
          if (g->csiColon) unsupported(g, RC_UN_COLON);
          i++;
          continue;
        }
        if (u == 0x18 || u == 0x1A) { g->mode = RC_GROUND; i++; continue; }   /* CAN / SUB abort */
        /* Any other byte, ESC included, abandons the CSI and is re-examined from ground. ConEmu
           instead parks it in Pvt and keeps eating (deviation #1, see Render.h).
           The three abandonment sites in this parser -- here, the ESC-without-a-final below, and the
           interim arm in RC_ESC_INTERIM -- are deliberately *not* counted, and the reason is worth keeping
           next to the two arms that are (`CSI p`, `ESC ) c`): a cancelled sequence never completed, so it
           asked for nothing. The rule is "a sequence that reached a final and did nothing must leave a
           count"; a half-sequence that the sender aborted with CAN, SUB or a fresh ESC is framing, and the
           byte that aborted it is re-examined in ground, so no effect is invisible to anyone. */
        g->mode = RC_GROUND;
        continue;
      }

      case RC_OSC:
      {
        if (u == 0x07) { osc_finish(g, 1); g->mode = RC_GROUND; i++; continue; }               /* BEL */
        if (u == 0x1B) { g->mode = RC_OSC_ESC; i++; continue; }              /* ST, or abandon */
        if (u == 0x18 || u == 0x1A) { osc_finish(g, 0); g->mode = RC_GROUND; i++; continue; }
        if (g->nOsc < RC_OSC_MAX) g->osc[g->nOsc++] = u;
        else g->oscClip = 1;        /* still consumed; whoever acts on it says it was clipped (I21) */
        i++;
        continue;
      }

      case RC_OSC_ESC:
        /* esc_end() abandons an OSC *at* the ESC, not after it (Ansi.cpp:1889-1907), so a byte that is
           not the '\' of an ST leaves the ESC to re-open a sequence. Reprocessing u in RC_ESC -- rather
           than consuming it -- is what makes "\e]0;x\e[31m" apply red instead of painting "[31m". The
           abandoned sequence is counted there, never applied: see osc_finish(). */
        if (u == '\\') { osc_finish(g, 1); g->mode = RC_GROUND; i++; continue; }
        osc_finish(g, 0);
        g->mode = RC_ESC;
        cap_begin(g, 0x1B);   /* the ESC that got us here is an introducer again, as our parser says */
        continue;

      case RC_ESC:
      {
        if (u == '[') { cap_push(g, u); csi_start(g); i++; continue; }
        if (u == ']') { osc_start(g, RC_OSC_NONE); i++; continue; }
        /* DCS/SOS/PM/APC: the payload framing is identical to an OSC's and the whole thing is discarded,
           but it is counted on its own -- a DCS never carries a window title, so telling it apart is what
           makes the title counter mean what it says. */
        if (u == 'P' || u == 'X' || u == '^' || u == '_') { osc_start(g, RC_OSC_DCS); i++; continue; }
        if (u == '(' || u == ')' || u == '%') { g->mode = RC_ESC_INTERIM; g->escInterim = u; i++; continue; }
        /* SS2/SS3: esc_end() counts the introducer as the whole sequence, so the byte that follows is
           ordinary text. Swallowing it would drop a column from the line. */
        if (u == 'N' || u == 'O') { g->mode = RC_GROUND; i++; continue; }
        if (u >= 0x20 && u <= 0x2F) { g->mode = RC_ESC_INTERIM; g->escInterim = u; i++; continue; }
        if (u >= 0x30 && u <= 0x7E)
        {
          cap_push(g, u);
          if (u == 'c') sgr_captured(g);            /* RIS resets the attributes as well as the cursor */
          esc_dispatch(g, 0, (uint8_t)u);
          g->mode = RC_GROUND;
          i++;
          continue;
        }
        g->mode = RC_GROUND;                                                    /* ESC + anything else: only the ESC was a sequence */
        continue;
      }

      case RC_ESC_INTERIM:
      {
        uint8_t intro = (uint8_t)g->escInterim;
        if (intro == '(' || intro == ')' || intro == '%')
        {
          /* One byte of payload and the sequence is over, whoever it designated. */
          esc_charset(g, intro, (uint8_t)u);
          g->mode = RC_GROUND;
          i++;
          continue;
        }
        if (u >= 0x20 && u <= 0x2F) { g->escInterim = u; i++; continue; }   /* more intermediates */
        g->mode = RC_GROUND;
        if (u >= 0x30 && u <= 0x7E) esc_dispatch(g, intro, (uint8_t)u);
        i++;
        continue;
      }

      default: break;                                 /* RC_GROUND falls through to the text path */
    }

    /* ---- ground ---- */
    if (u == 0x1B) { cap_begin(g, u); g->mode = RC_ESC; i++; continue; }
    if (u < 0x20 || u == 0x7F) { control(g, u); i++; continue; }

    uint32_t cp;
    if (g->wantLow)
    {
      if (u >= 0xDC00 && u <= 0xDFFF)                /* the half-character this chunk completed */
      {
        uint16_t hi = (uint16_t)g->wantLow;
        g->wantLow = 0;
        put_cp(g, 0x10000u + (((uint32_t)hi - 0xD800u) << 10) + ((uint32_t)u - 0xDC00u));
        i++;
        continue;
      }
      g->wantLow = 0;                                /* the promised low half never came */
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
      /* A high surrogate that ends the chunk may still be completed by the next one, so hold it
         rather than painting U+FFFD -- and never let half a character reach the grid. */
      g->wantLow = u;
      i++;
      continue;
    }
    cp = (u >= 0xDC00 && u <= 0xDFFF) ? 0xFFFDu : u;  /* a lone low surrogate is one replacement cell */
    put_cp(g, cp);
    i++;
  }

  /* A high surrogate that ended this chunk stays in g->wantLow; rc_feed() resumes it next call. */
}

/* ------------------------------------------------------------------ setup --------------------- */

/* Carry the table across a rebuild: the caller has already copied the old bytes in, and `from` is the old
 * width, so this only decides what the columns that did not exist before are. Public because the state is the
 * model's and the decision to keep it is the seam's (RenderJni.cpp::build_model). */
void rc_tabs_widen(RcGrid *g, int from)
{
  tabs_default(g, from);
}

int rc_reset_hist(RcGrid *g, int cols, int winRows, int histRows, uint16_t defAttr)
{
  if (!g || cols <= 0 || winRows <= 0 || histRows < 0) return 0;
  /* The snapshot is cut to the geometry it was taken with: its rows are `cols` wide, so the memset below
     is not enough -- a reused handle would copy last session's screen into rows of a different width.
     Before the range checks, so a rejected reset cannot strand the old one either. */
  free(g->snap);
  g->snap = NULL;
  if (cols > RC_MAX_COLS || winRows + histRows > RC_MAX_ROWS) return 0;
  memset(g, 0, sizeof(*g));
  g->cols = cols;
  g->rows = winRows + histRows;
  /* The pool starts in order. `of` is the only thing that says which pool row *is* which model row, so a
   * fresh grid -- and every rebuild, which is a fresh grid wearing the old one's carried state -- is the
   * identity, and the first scroll is what permutes it. Forgetting this line is not a slow day: it maps
   * every row onto row 0, and `rc_validate_grid` calls that what it is (a repeated `of`, not a permutation). */
  for (int r = 0; r < g->rows; r++) g->of[r] = r;
  g->winRows = winRows;
  g->cy = histRows;                                 /* the viewport's first row, whatever the gutter is */
  g->defAttr = defAttr;
  g->defAttrSeed = defAttr;   /* what OSC 110/111 go back to (I34) */
  g->cursorVisible = 1;
  g->wrapMode = 1;            /* out of reset DECAWM is on, in VT and in both references */
  tabs_reset(g);              /* the interval is a claim about the terminal, and a fresh one has it */
  g->cursorShape = -1;     /* memset above says 0, which here would mean "a DECSCUSR asked for the thin
                              cursor" -- the two are only told apart by this, and the difference is that a
                              session nobody shaped may not touch the user's console cursor height. */
  /* Two more slots where 0 is a answer and not a question. `lastUnit` is what REP replays, and ConEmu's
     m_LastWrittenChar starts at L' ' (Ansi.h:197), so a session that never printed anything and asked for a
     repeat gets spaces here too -- a 0 would make `CSI b` print nothing and read as "no glyph to repeat".
     `lastExit` is 0 for "the command succeeded", which is a claim, not an absence: -1 until a 133;D says so. */
  g->lastUnit = ' ';
  g->lastExit = -1;
  /* The fold table starts at upstream's own colours (I34): an OSC 4 that never arrives must not change a
     single pixel, and the console's live ColorTable is deliberately not consulted here -- on Win10/11 it is
     Campbell while this fold has always used ConEmu's table, so seeding from the screen would recolour
     every 256-colour and true-colour SGR in the product. A rebuilt grid carries the previous table instead
     (RenderJni.cpp's build_model), so an application's OSC 4 survives a resize. */
  for (int i = 0; i < 256; i++) g->palette[i] = RgbMap[i];
  for (int i = 0; i < 16; i++) g->pal16[i] = (uint32_t)Far3Color::GetStdPalette()[i];
  sgr_reset(g, 1);                                   /* the underscore bit comes from the default */
  for (int r = 0; r < g->rows; r++)
    for (int c = 0; c < cols; c++)
    {
      RC_CELLS(g, r)[c].ch = ' ';
      RC_CELLS(g, r)[c].attr = defAttr;
    }
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

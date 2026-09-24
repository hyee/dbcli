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
uint16_t rc_attr(const RcSgr *s, uint16_t defAttr)
{
  DWORD fg, bg;
  int fg24 = 0, bg24 = 0;

  (void)defAttr;   /* the default is folded in at Reset()/SGR 39/49 time, exactly like ConEmu's
                      CONFORECOLOR(GetDefaultTextAttr()), not here. */

  if (s->fgKind)
  {
    if (s->fgKind == RC_CLR24B) { fg24 = 1; fg = (DWORD)s->fg & 0xFFFFFF; }
    else
    {
      if (s->fg > 15) fg24 = 1;
      fg = RgbMap[((DWORD)s->fg) & 0xFF];
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
      bg = RgbMap[((DWORD)s->bg) & 0xFF];
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
    Far3Color::Color2FgIndex(nForeColor, n);
  }
  else
  {
    n |= (WORD)(fg & 0xF);      /* CONCOLORINDEX */
  }

  if (bg24)
  {
    DWORD nBackColor = bg & 0xFFFFFF;
    /* Equal is passed upstream but never read inside Color2BgIndex; kept for fidelity. */
    Far3Color::Color2BgIndex(nBackColor, nBackColor == nForeColor ? TRUE : FALSE, n);
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
  if (!g->rowDirty[row])
  {
    g->rowDirty[row] = 1;
    g->dirtyLo[row] = (uint16_t)from;
    g->dirtyHi[row] = (uint16_t)to;
    return;
  }
  if (from < (int)g->dirtyLo[row]) g->dirtyLo[row] = (uint16_t)from;
  if (to > (int)g->dirtyHi[row]) g->dirtyHi[row] = (uint16_t)to;
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

int rc_row_dirty(const RcGrid *g, int row)
{
  return (row >= 0 && row < g->rows) ? g->rowDirty[row] : 0;
}

int rc_row_wrap(const RcGrid *g, int row)
{
  return (row >= 0 && row < g->rows) ? g->rowWrap[row] : (int)RC_WRAP_NONE;
}

/* align() reads cells, and neither of a row's private claims is a cell: ReadConsoleOutputW carries no wrap
   information and no semantic mark either (MSFT_TERMINAL_REFERENCE \u00a75). A claim left behind an adopt is
   worse than no claim -- it would describe content that is no longer there -- so an adopt drops both for
   the rows it replaced. Renamed from rc_forget_wrap for that reason: it was never only about the wrap. */
void rc_forget_row_state(RcGrid *g)
{
  for (int r = gutter(g); r < g->rows; r++)
  {
    g->rowWrap[r] = RC_WRAP_NONE;
    g->rowMark[r] = RC_PM_NONE;
    g->markCol[r] = 0;
  }
}

int rc_row_mark(const RcGrid *g, int row)
{
  return (row >= 0 && row < g->rows) ? (int)g->rowMark[row] : (int)RC_PM_NONE;
}

/* The column the row's mark was made at -- the prompt's own start, which is what a consumer that wants to
   select "this command" needs: after a scroll the row may carry output text to the left of the mark, and
   taking the whole row would take that too. */
int rc_mark_col(const RcGrid *g, int row)
{
  return (row >= 0 && row < g->rows) ? (int)g->markCol[row] : 0;
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

/* The attribute is written verbatim, not merged with what was there: that is also what destroys a wide
 * glyph's LEADING/TRAILING half under an erase, which is what conhost does to the pair. */
static void fill_span(RcGrid *g, int row, int from, int to, uint16_t attr)
{
  if (row < 0 || row >= g->rows) return;
  if (from < 0) from = 0;
  if (to >= g->cols) to = g->cols - 1;
  for (int c = from; c <= to; c++)
  {
    g->cells[row][c].ch = ' ';
    g->cells[row][c].attr = attr;
  }
  /* An erase that reaches the margin ends the row's claim to have overflowed: nothing ran off its right
     edge any more, whatever was there before. Erases short of the margin leave the claim alone. */
  if (to >= g->cols - 1) g->rowWrap[row] = RC_WRAP_NONE;
  mark_dirty(g, row, from, to);
}

/* Erases `from` to the end of the model row. A model row is the whole console row -- cols is dwSize.X
 * less the window's left edge -- so an erase that stops at "the end of the line" is already ConEmu's
 * EL/ED behaviour of erasing to dwSize.X, and no second width needs to be tracked. */
static void fill_row(RcGrid *g, int row, int from, uint16_t attr)
{
  fill_span(g, row, from, g->cols - 1, attr);
}

/* What a row knows about *itself*: why its line ended (I20) and which FTCS region it begins (I23). Both
   belong to the content, not to the row number, so both must travel together on every vertical shift --
   a soft-wrapped table row that scrolls up one row is still the first half of a line, and a prompt that
   scrolls up is still where that command started. They move in one call because the failure mode of the
   pair is forgetting half of it, which no grid witness can see: neither bit reaches the console, so
   neither can be read back after the fact.
   The damage overlay has its own carry (scroll_carry) because it is a paint-cost fact, not a content one. */
static void row_carry(RcGrid *g, int dst, int src)
{
  g->rowWrap[dst] = g->rowWrap[src];
  g->rowMark[dst] = g->rowMark[src];
  g->markCol[dst] = g->markCol[src];
}

/* A row that arrived blank knows nothing: it overflowed nowhere and no command started on it. */
static void row_reset_state(RcGrid *g, int row)
{
  g->rowWrap[row] = RC_WRAP_NONE;
  g->rowMark[row] = RC_PM_NONE;
  g->markCol[row] = 0;
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
  if (g->cy >= 0 && g->cy < g->rows && g->rowMark[g->cy] == RC_PM_NONE)
  {
    g->rowMark[g->cy] = RC_PM_CONTINUATION;
    g->markCol[g->cy] = 0;
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
  if (down)
  {
    for (int r = bot; r - n >= top; r--)
    {
      memcpy(&g->cells[r], &g->cells[r - n], (size_t)g->cols * sizeof(RcCell));
      row_carry(g, r, r - n);
    }
    for (int r = top; r < top + n; r++) fill_row(g, r, 0, g->attr);
  }
  else
  {
    for (int r = top; r + n <= bot; r++)
    {
      memcpy(&g->cells[r], &g->cells[r + n], (size_t)g->cols * sizeof(RcCell));
      row_carry(g, r, r + n);
    }
    for (int r = bot - n + 1; r <= bot; r++) fill_row(g, r, 0, g->attr);
  }
  /* fill_row clears a row's wrap claim only when the erase reaches the margin, which a narrowed region
     does not have to: rows below the region still wrap at the buffer's right edge. Drop the claim -- and
     the semantic mark, which no erase ever clears -- for every row this shift blanked. */
  if (down) for (int r = top; r < top + n; r++) { g->rowWrap[r] = RC_WRAP_NONE; g->rowMark[r] = RC_PM_NONE; }
  else      for (int r = bot - n + 1; r <= bot; r++) { g->rowWrap[r] = RC_WRAP_NONE; g->rowMark[r] = RC_PM_NONE; }
  for (int r = top; r <= bot; r++) mark_row_dirty(g, r);
  g->nScrolls += (unsigned long)n;
}

/* The viewport scrolls up by n; the vacated rows are blank in the current attribute, which is what
 * ScrollConsoleScreenInfo does when the caller passes the live console attribute (as the shipped
 * Java writer has always done). */
/* The damage overlay travelling with the content it describes. A chunk that writes a row and then scrolls
 * (three lines flushed at once, a dashboard frame that runs off the bottom) leaves those writes n rows
 * higher, and a flag left behind at the old row would paint the wrong one -- the new rows would look right
 * in the model and be blank on screen. The columns ride with the row: a status line that damaged columns
 * 40..59 moves up and still needs only those twenty columns repainted, wherever it now is. A row that
 * arrives at a new number claiming no damage paints nothing and keeps the stale screen. */
static void scroll_carry(RcGrid *g, int n)
{
  for (int r = 0; r + n < g->rows; r++)
  {
    g->rowDirty[r] = g->rowDirty[r + n];
    g->dirtyLo[r] = g->dirtyLo[r + n];
    g->dirtyHi[r] = g->dirtyHi[r + n];
  }
}

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
       Nothing may be spent on a window slide or a buffer scroll either (Paint.cpp rule 2) -- both would
       drag the user's view through the real buffer to make room for a screen that is about to be blanked.
       The rows still have to be blanked and their wrap claims carried, exactly as on the main screen, or the
       bottom row keeps a duplicate of the line that scrolled out of it; and the damage overlay cannot travel
       row-for-row, because a row that was *clean* and merely moved is still a change on the screen. So the
       whole viewport goes dirty and the caller repaints it. */
    const int top = gutter(g);
    if (n > g->winRows) n = g->winRows;
    for (int r = top; r + n < g->rows; r++)
    {
      memcpy(&g->cells[r], &g->cells[r + n], (size_t)g->cols * sizeof(RcCell));
      row_carry(g, r, r + n);
    }
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
  /* Row by row, never as one span: cells[] is a fixed RC_MAX_COLS stride, so a contiguous copy of
     (rows-n)*cols cells would run row 1's tail into row 0 and leave row 1 where it was. */
  for (int r = 0; r + n < g->rows; r++)
    memcpy(&g->cells[r], &g->cells[r + n], (size_t)g->cols * sizeof(RcCell));
  g->nScrolls += (unsigned long)n;
  g->pendingScrolls += n;
  /* The damage overlay has to travel with the content it describes. A chunk that writes a row and then
     scrolls (three lines flushed at once, a dashboard frame that runs off the bottom) leaves those
     writes n rows higher, and a flag left behind at the old row would paint the wrong one -- the new
     rows would look right in the model and be blank on screen. */
  scroll_carry(g, n);
  /* The wrap claim and the semantic mark belong to the content, not to the row number: a soft-wrapped table
     row that scrolls up one is still the first half of a line, a prompt that scrolls up is still the row a
     command started on, and one that scrolls in from the gutter arrived blank. */
  for (int r = 0; r + n < g->rows; r++) row_carry(g, r, r + n);
  for (int r = g->rows - n; r < g->rows; r++)
  {
    mark_row_dirty(g, r);                         /* rows that came into the viewport are unknown */
    row_reset_state(g, r);
    for (int c = 0; c < g->cols; c++)
    {
      g->cells[r][c].ch = ' ';
      g->cells[r][c].attr = g->attr;
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

static void put_cell(RcGrid *g, uint16_t ch, int w)
{
  if (w <= 0) return;            /* Mn/Me/Cf and the C0 range contribute no cell */
  if (w > 2) w = 2;

  if (g->cx + w > g->cols)
  {
    /* conhost with ENABLE_WRAP_AT_EOL moves to the next row the moment the last column is filled,
       so a 2-column glyph that does not fit starts the next row whole (JLine's columnSplitLength
       agrees). The shipped Java writer declines this case and hands it to ConEmuHk instead; here it
       is a wrap, because nothing can be declined once one parser owns the stream.

       The row left behind keeps its own reason: it did not overflow, its last glyph was moved whole to
       spare it a split (conhost's _doubleBytePadded). Copy and export join the two differently. */
    g->rowWrap[g->cy] = RC_WRAP_PAD;
    g->cx = 0;
    line_down(g);
  }

  g->cells[g->cy][g->cx].ch = ch;
  g->cells[g->cy][g->cx].attr = (uint16_t)(g->attr | (w == 2 ? RC_LVB_LEADING : 0));
  if (w == 2)
  {
    g->cells[g->cy][g->cx + 1].ch = ch;
    g->cells[g->cy][g->cx + 1].attr = (uint16_t)(g->attr | RC_LVB_TRAILING);
  }
  mark_dirty(g, g->cy, g->cx, g->cx + w - 1);
  g->nCells += (unsigned long)w;
  g->cx += w;

  if (g->cx >= g->cols)
  {
    g->rowWrap[g->cy] = RC_WRAP_FORCED;   /* text reached the margin and continued on the next row */
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
    if (g->cx + 2 > g->cols) { g->rowWrap[g->cy] = RC_WRAP_PAD; g->cx = 0; line_down(g); }
    g->cells[g->cy][g->cx].ch = hi;
    g->cells[g->cy][g->cx].attr = (uint16_t)(g->attr | RC_LVB_LEADING);
    g->cells[g->cy][g->cx + 1].ch = lo;
    g->cells[g->cy][g->cx + 1].attr = (uint16_t)(g->attr | RC_LVB_TRAILING);
    mark_dirty(g, g->cy, g->cx, g->cx + 1);
    g->nCells += 2;
    g->cx += 2;
    if (g->cx >= g->cols) { g->rowWrap[g->cy] = RC_WRAP_FORCED; g->cx = 0; line_down(g); }
    return;
  }
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
  g->lastUnit = cp;
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
  s->fg = g->defAttr & 0x0F;
  s->bg = (g->defAttr >> 4) & 0x0F;
  s->seeded = 1;
  if (keep_underline) s->underline = (g->defAttr & RC_LVB_UNDERSCORE) ? 1 : 0;
  g->attr = rc_attr(s, g->defAttr);
}

/* ConEmu stores SGR 39/49 as "the default colour", in the 4-bit space, from the frozen default. */
static void sgr_default_fg(RcGrid *g)
{
  g->sgr.fg = g->defAttr & 0x0F;
  g->sgr.fgKind = RC_CLR4B;
  g->sgr.brightFore = 0;
}

static void sgr_default_bg(RcGrid *g)
{
  g->sgr.bg = (g->defAttr >> 4) & 0x0F;
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
  g->attr = rc_attr(s, g->defAttr);
}

/* ------------------------------------------------------------- sequence dispatch --------------- */

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
  if (which == RC_UN_SUP)
    g->modelSuspect = 1;
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

static int arg(const RcGrid *g, int i, int dflt)
{
  return (i < g->nArgs && g->args[i] > 0) ? g->args[i] : dflt;
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
      g->cells[r][c].ch = ' ';
      g->cells[r][c].attr = g->attr;
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
        memcpy(&g->snap[(size_t)r * g->cols], &g->cells[hist + r][0], (size_t)g->cols * sizeof(RcCell));
        g->snapWrap[r] = g->rowWrap[hist + r];
        g->snapMark[r] = g->rowMark[hist + r];
        g->snapCol[r] = g->markCol[hist + r];
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
    memcpy(&g->cells[hist + r][0], &g->snap[(size_t)r * g->cols], (size_t)g->cols * sizeof(RcCell));
    g->rowWrap[hist + r] = g->snapWrap[r];
    g->rowMark[hist + r] = g->snapMark[r];
    g->markCol[hist + r] = g->snapCol[r];
  }
  g->alt = 0;
  g->pendingScrolls = 0;
  clxy(g, g->saveY, g->saveX);  /* CursorRestoreState() after the screen is back, like MSFT's order */
  rc_mark_all_dirty(g);
  return 1;
}

/* RIS (`ESC c`) and DECSTR (`CSI !p`) are one and the same call upstream -- FullReset (Ansi.cpp:2723-2726
 * and :3644-3649) -- and it is a hard reset rather than an attribute reset: ReSetDisplayParm drops the SGR
 * state, `ScrollScreen(-csbi.dwSize.Y)` is the line commented "easy way to drop all lines", and the cursor
 * goes to the origin. Here that is "leave the alt screen, run the viewport's worth of rows up into
 * history, home". The alt is left first, because a reset must not overwrite the main screen with it
 * (adaptDispatch.cpp:3038-3049), and attributes are not saved by 1049, so the reset still lands.
 * Two places this answers VT instead of ConEmu, both because leftover state would do damage on a reset:
 * upstream routes the drop through the region-honouring ScrollScreen overload (:2002-2007), so a program
 * that set `CSI 1;5r` and died would have five rows wiped and the rest of the screen kept; and nothing in
 * FullReset clears gDisplayOpt.ScrollRegion, or the cursor shape, at all. */
static void full_reset(RcGrid *g)
{
  sgr_reset(g, 0);
  alt_screen(g, 0);
  g->regSet = 0;
  g->cursorShape = -1;
  g->cursorVisible = 1;
  scroll_up(g, g->winRows);
  clxy(g, gutter(g), 0);
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
  if (col > 0 && (g->cells[g->cy][col].attr & RC_LVB_TRAILING)) col--;
  return col;
}

/* CSI with a final byte in hand. interim carries the 0x20..0x2F bytes (' ' selects cursor shape). */
static void csi_dispatch(RcGrid *g, uint8_t interim, uint8_t final)
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
    /* HPR (`CSI a`) and VPR (`CSI e`) are the two final bytes this dispatch used to alias onto CUF and
       CUDL -- and ConEmu has no case for either one. Verified against the switch in Ansi.cpp: the finals it
       handles are `@ A B C D E F H J K L M P S T X b c d f h l m n p q r s t u`, so `a` and `e` fall through
       to its own default (Ansi.cpp:3816), which is DumpUnknownEscape -- a no-op in a release build
       (:971), so the cursor does not move and nothing prints. ghostty implements both (stream.zig:1863
       HPR -> cursor_col_relative, :1942 VPR) and so does MSFT (adaptDispatch.cpp:427/:437, whose comment
       notes VPR is "unlike CUD not constrained by margin"): the two references agree with each other and
       neither agrees with ConEmu, and the fallback leg *is* ConEmu. Counted, and suspicion-free for the
       same reason `Z` is -- nothing moved. */
    case 'a': case 'e': ignored(g, RC_UN_SUP); break;
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
       Both are region-bounded upstream (LinesInsert :2133-2140, LinesDelete :2190-2201): the shift spans
       [cursor row .. region bottom], and a cursor outside the region is refused outright -- not clamped to
       it, which is what the Status bar needs to stay safe while `csr` has the upper rows. (DL's own guard
       is looser than IL's: `cy + n <= ScrollStart` at :2195 lets a cursor sitting just above the region
       pull region rows up past its top edge. That one overlap case is declined here, not copied.) The
       no-region path below is the one every witness before DECSTBM was modelled depends on, and it is kept
       verbatim.
       Where upstream and this diverge deliberately: when n exceeds the region, ConEmu fills
       `dwSize.X * linesCount` cells from the cursor row (:2152-2155), i.e. it writes past the region's
       bottom and over whatever is under it; shift_region clamps to the span and blanks the region. That
       is a ConEmu overflow, not a behaviour to copy (CONEMU_ANSI_DEFECTS.md). */
    case 'L': case 'M':
    {
      int n = arg(g, 0, 1), top, bot;
      region(g, &top, &bot);
      if (g->regSet)
      {
        if (g->cy > bot || g->cy < top) break;
        shift_region(g, n, g->cy, bot, final == 'L');
        break;
      }
      if (n > g->winRows) n = g->winRows;               /* insert or delete within the viewport only */
      if (final == 'L')
      {
        for (int r = g->rows - 1; r >= g->cy + n; r--)
        {
          memcpy(&g->cells[r], &g->cells[r - n], (size_t)g->cols * sizeof(RcCell));
          row_carry(g, r, r - n);
        }
        for (int r = g->cy; r < g->cy + n && r < g->rows; r++) { fill_row(g, r, 0, g->attr); row_reset_state(g, r); }
      }
      else
      {
        for (int r = g->cy; r + n < g->rows; r++)
        {
          memcpy(&g->cells[r], &g->cells[r + n], (size_t)g->cols * sizeof(RcCell));
          row_carry(g, r, r + n);
        }
        for (int r = g->rows - n; r < g->rows; r++) { fill_row(g, r, 0, g->attr); row_reset_state(g, r); }
      }
      rc_mark_all_dirty(g);
      break;
    }
    /* ICH opens n blank columns at the cursor and pushes the row's tail right; DCH pulls the tail back
       and blanks the tail end. Both act on the row alone, from the cursor to the end of the *model* row,
       which is the buffer width: as in ConEmu (ScrollLine at ExtConsole.cpp:1661-1675) nothing wraps,
       nothing below moves and text pushed past the last column cannot be pulled back. The cells are moved
       whole, LEADING/TRAILING halves included, so a wide glyph split by the shift shows its two halves
       apart -- upstream does exactly the same to the same pair, and this is the one sequence family where
       copying a ConEmu oddity is cheaper than inventing a third answer. */
    case '@': case 'P':
    {
      int n = arg(g, 0, 1);
      if (g->cx < g->cols)
      {
        if (n > g->cols - g->cx) n = g->cols - g->cx;
        if (final == '@')
        {
          for (int c = g->cols - 1; c >= g->cx + n; c--) g->cells[g->cy][c] = g->cells[g->cy][c - n];
          fill_span(g, g->cy, g->cx, g->cx + n - 1, g->attr);
        }
        else
        {
          for (int c = g->cx; c + n < g->cols; c++) g->cells[g->cy][c] = g->cells[g->cy][c + n];
          fill_span(g, g->cy, g->cols - n, g->cols - 1, g->attr);
        }
      }
      break;
    }
    /* ECH (`CSI Ps X`) erases Ps cells at the cursor and -- unlike EL -- it does not stop at the end of the
       row. ConEmu measures what is left as `X-cx-1 + X*(Y-cy-1)` and clamps to that (Ansi.cpp:3802-3811), so
       an over-long ECH walks down through the buffer; ghostty (Terminal.zig:3443) and MSFT
       (adaptDispatch.cpp:713) both clamp it to the row. Followed upstream here, with the two differences
       that are ours: the clamp is the true count of remaining cells (ConEmu's formula is one short of a row,
       so its last column survives an over-long ECH -- CONEMU_ANSI_DEFECTS.md), and the walk stops at the
       viewport bottom, because the rows above it are the user's scrollback and ED already refuses to touch
       them for that reason. The parameter is read raw, so `CSI 0X` erases nothing exactly as it does
       upstream; filled with the live attribute, which is what makes `bce` true for this sequence. */
    case 'X':
    {
      int n = (g->nArgs > 0) ? g->args[0] : 1;
      if (n > 0)
      {
        int left = (g->cols - g->cx) + g->cols * (g->rows - g->cy - 1);
        if (n > left) n = left;
        for (int r = g->cy; n > 0; r++)
        {
          int from = (r == g->cy) ? g->cx : 0;
          int w = g->cols - from;
          if (w > n) w = n;
          fill_span(g, r, from, from + w - 1, g->attr);
          n -= w;
        }
      }
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
      int n = (g->nArgs > 0) ? g->args[0] : 1;
      while (n-- > 0) put_cp(g, g->lastUnit);
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
      int n = arg(g, 0, 1), top, bot;
      region(g, &top, &bot);
      if (!g->regSet && top == gutter(g) && bot == g->rows - 1) scroll_up(g, n);
      else shift_region(g, n, top, bot, 0);
      break;
    }
    case 'T':
    {
      int top, bot;
      region(g, &top, &bot);
      shift_region(g, arg(g, 0, 1), top, bot, 1);
      break;
    }

    case 's': g->saveX = g->cx; g->saveY = g->cy; break;
    case 'u': clxy(g, g->saveY, g->saveX); break;   /* restore is unconditional upstream (Ansi.cpp:4194) */

    /* DECSTBM. ConEmu's acceptance test is mirrored exactly, including the three ways it differs from
       VT (Ansi.cpp:3142-3150 + SetScrollRegion :4146-4174): a region it rejects *clears* the region
       rather than being ignored, so `CSI r`, one argument alone, or top above bot all return the whole
       viewport to scrolling; a zero parameter is accepted and clamps to the viewport's first row, so
       `CSI 0;35r` means `CSI 1;35r`; and setting a region does NOT home the cursor, which the comment
       in Status.java:234 ("usually moves the cursor") assumes it does. The private form `CSI ?r` is
       also accepted, because upstream never checks PvtLen for this final byte.
       The parameters are viewport-relative (`GetWorkingRegion(.., true)` at :4108-4127, which is
       srWindow), which is the same frame this model addresses rows in, so the gutter can never be pulled
       into a region. The clamp happens once, here, and is never revisited: the viewport's row span cannot
       move under a live grid, because rc_reset_hist() is the only writer of cols/rows/winRows and the
       painter refuses to realign a geometry change rather than re-cutting one it was asked for
       (RenderJni.cpp:574) -- the caller reopens, and a reopened grid has no region. */
    case 'r':
    {
      int t = arg(g, 0, 1), b = arg(g, 1, 1);
      const int top = gutter(g);
      g->regSet = 0;
      if (g->nArgs >= 2 && t >= 0 && b >= t)
      {
        int rt = top + (t > 0 ? t - 1 : 0);
        int rb = top + (b > 0 ? b - 1 : 0);
        if (rt < top) rt = top;
        if (rb > g->rows - 1) rb = g->rows - 1;
        if (rt > g->rows - 1) rt = g->rows - 1;
        if (rb < rt) rb = rt;
        /* Normalise "the region is the viewport" back to no region at all: the paths that keep the
           gutter and the console scroll in mind branch on exactly that, and a region that happens to
           cover everything must not cost them. */
        if (!(rt == top && rb == g->rows - 1)) { g->regSet = 1; g->regTop = rt; g->regBot = rb; }
      }
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
      if (interim == ' ' && !g->priv)
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
      /* DECSTR. Upstream gates it on `ArgC == 0 && Pvt == "!"` (Ansi.cpp:3645), and '!' (0x21) reaches us
         as an interim byte, not in `priv` -- the same slot the ' ' of DECSCUSR uses. */
      if (interim == '!' && !g->nArgs) full_reset(g);
      break;
    case 'Z': ignored(g, RC_UN_SUP); break;  /* CBT: no case upstream (:3051-3052), and HTS is ignored
        * too (:2731-2734), so there is no tab stop for a backtab to find. */
    case 'c': unsupported(g, RC_UN_REPORT); break;      /* DA: would need a write back to stdin */
    case 'n': unsupported(g, RC_UN_REPORT); break;      /* DSR */
    /* Window manipulation. Upstream has a case (:3688-3762) and splits into three kinds: 8/22/23 reach
       Dump*Escape and do nothing, everything outside the list hits a TODO and does nothing, and 14/18/19/21
       call ReportTerminalPixelSize / ReportTerminalCharSize / ReportConsoleTitle -- which is a write into
       the application's *input*, exactly what a renderer that owns no pipe cannot answer. Counted as a
       report, not as an unknown final, because the reach is known and moves no cell: this arm buys no
       repaint, which is the difference between a gap and a hazard. The caps carry the matching half of the
       deal (windows-conemu.caps advertises no `u6`/`u7`/`cs`-query string either) -- JLine's cursor-position
       probe is an unbounded `reader.read()` loop, so a caps entry that let it ask would hang the reader. */
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
    case 'H': ignored(g, RC_UN_MODE); break;
    case '=': case '>': ignored(g, RC_UN_MODE); break;
    default: unsupported(g, RC_UN_SUP); break;
  }
}

/* ESC ( <c>: 0 selects the drawing set, B or anything else selects the default (Ansi.cpp:2751-2767). */
static void esc_charset(RcGrid *g, uint8_t designator, uint8_t c)
{
  if (designator == '(') g->charset = (c == '0') ? 1 : 0;
  /* ')' and '%' are consumed and discarded upstream, so G1 and the UTF-8 flag are unreachable. */
}

/* C0 controls that are not part of a sequence. Width-0 by the tables, so none of them paints a cell. */
static void control(RcGrid *g, uint16_t u)
{
  switch (u)
  {
    case 0x07: break;                                       /* BEL: beeps, never occupies a cell */
    case 0x08: if (g->cx > 0) g->cx = step_back_col(g, 1); break;  /* BS: moves, does not erase */
    case 0x09: { int to = ((g->cx + 8) >> 3) << 3; g->cx = to < g->cols ? to : g->cols - 1; break; }
    case 0x0A: newline(g); break;
    case 0x0D: g->cx = 0; break;
    default: break;                                         /* other C0, DEL: nothing */
  }
}

/* --------------------------------------------------------------- the parser -------------------- */

static void push_arg(RcGrid *g, int v)
{
  if (g->nArgs < RC_CSI_ARGS) g->args[g->nArgs++] = v;
}

static void csi_start(RcGrid *g)
{
  g->mode = RC_CSI;
  g->priv = 0;
  g->csiColon = 0;
  g->interim = 0;
  g->nArgs = 0;
  g->digit = 0;
  g->cur = 0;
}

static void osc_start(RcGrid *g, int kind)
{
  g->mode = RC_OSC;
  g->nTitle = 0;
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
  while (i < g->nTitle && g->title[i] >= '0' && g->title[i] <= '9') i++;
  *sepAt = (i < g->nTitle && g->title[i] == ';') ? i : -1;
  if (i == 0) return -1;
  if (i > 1 && g->title[0] == '0') return RC_OSC_CODE_MAX;
  int v = 0;
  for (int j = 0; j < i; j++)
  {
    v = v * 10 + (g->title[j] - '0');
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
  if (len < 1 || len > 9) return -1;                 /* 10 digits can overflow an int: treat as gibberish */
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
  if (g->rowMark[g->cy] != RC_PM_NONE && g->rowMark[g->cy] != RC_PM_CONTINUATION) return;
  g->rowMark[g->cy] = (uint8_t)(continuation ? RC_PM_CONTINUATION : RC_PM_PROMPT);
  g->markCol[g->cy] = (uint16_t)g->cx;
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
      if (g->cy >= 0 && g->cy < g->rows && g->cx == 0 && g->rowMark[g->cy] != RC_PM_NONE)
        g->rowMark[g->cy] = RC_PM_NONE;
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
        if (g->rowMark[r] == RC_PM_NONE) continue;
        if (have != 0)
          g->rowMark[r] = (uint8_t)((have == 1 && code == 0) ? RC_PM_SUCCESS : RC_PM_ERROR);
        return 1;
      }
      return 1;                              /* a verdict with nothing to mark: the code is still the log's */
    }
    default: return 0;
  }
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
static void osc_finish(RcGrid *g, int terminated)
{
  const int kind = g->oscKind;
  g->oscKind = RC_OSC_NONE;
  if (kind == RC_OSC_DCS) { unsupported(g, RC_UN_DCS); return; }

  int sep = -1;
  const int code = osc_code_of(g, &sep);
  if (code == 9) { unsupported(g, RC_UN_OSC_PRIV); return; }

  /* FTCS. `sep == 3` is the guard's form of "the payload really opens with 133;" -- the digit run this code was
     read from, so "]0133;A" (leading zero, RC_OSC_CODE_MAX) and "]1334;A" both fail it. An unterminated one is
     dropped rather than applied: a half-read command says where the shell meant to mark a row but not what it
     meant there, and a mark in the wrong place is worse than no mark. A rejection is counted as OSC_OTHER and
     not as suspicious -- 133 moves the cursor only on its own say-so (ftcs_fresh_line), which this model then
     applied faithfully or not at all, so the grid is never left describing a screen that is not there. */
  if (code == 133)
  {
    if (sep != 3 || !terminated) { unsupported(g, RC_UN_OSC_OTHER); return; }
    if (!ftcs_apply(g, g->title + sep + 1, g->nTitle - sep - 1)) unsupported(g, RC_UN_OSC_OTHER);
    return;
  }

  /* ConEmu's guard, byte for byte (Ansi.cpp:3845): the digit, then ';' at index 1 -- so "]10;foo" is
     NOT a title -- then at least one character of payload, so "]0;" alone sets nothing. */
  if ((code == 0 || code == 1 || code == 2) && sep == 1 && g->nTitle > 2)
  {
    if (!terminated) { unsupported(g, RC_UN_OSC_OTHER); return; }
    /* What EscCopyCtrlString hands on (Ansi.cpp:2276-2283): one pair of surrounding double quotes
       removed. An empty result is still a title -- "]0;""ST" sets the title to "", it does not leave it
       alone; the gsInitConTitle argument at :3851 is CEStr::c_str's *null* substitute (it returns the
       default only when the buffer was never allocated), not an empty one. */
    int from = 2, len = g->nTitle - 2;
    if (len > 1 && g->title[from] == '"' && g->title[from + len - 1] == '"') { from++; len -= 2; }
    for (int i = 0; i < len; i++) g->title[i] = g->title[from + i];
    g->nTitle = len;
    g->titlePending = 1;               /* the painter applies it; a later title in the chunk replaces it */
    g->nTitleSet++;
    if (g->oscClip) g->nTitleTrunc++;
    return;
  }
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

/* Does this CSI/ESC final byte change the attribute state? Mirrors the dispatch: a private byte makes
 * ConEmu drop the whole SGR, so '?31m' must not be echoed either. DECSTR's '!' is an interim byte -- the
 * same slot DECSCUSR's ' ' occupies -- and never arrives in `priv`, which only collects 0x30..0x3F. */
static int echoes(uint8_t interim, uint8_t final, int priv)
{
  if (final == 'm') return !priv;
  if (final == 'p') return interim == '!';            /* DECSTR resets the attributes */
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

int rc_title_pending(const RcGrid *g) { return g->titlePending; }

int rc_title_take(RcGrid *g, uint16_t *dst, int cap)
{
  if (!g->titlePending) return 0;
  if (!dst || cap < g->nTitle) return -1;            /* nothing cleared: the title stays pending */
  for (int i = 0; i < g->nTitle; i++) dst[i] = g->title[i];
  const int n = g->nTitle;
  g->titlePending = 0;
  return n;
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
            g->cur = (g->cur > 6553) ? 65535 : g->cur * 10 + (u - '0');
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
          g->interim = u;
          i++;
          continue;
        }
        if (u >= 0x40 && u <= 0x7E)                  /* final */
        {
          if (g->digit) push_arg(g, g->cur);         /* a trailing empty parameter is NOT a zero */
          g->mode = RC_GROUND;
          cap_push(g, u);
          if (echoes((uint8_t)g->interim, (uint8_t)u, g->priv)) sgr_captured(g);
          csi_dispatch(g, (uint8_t)g->interim, (uint8_t)u);
          /* One票 per sequence for the colon form, whichever final it carried: this is the number that
             says whether the ConEmu-parity decision in \u00a713.2 ever costs a real application anything. */
          if (g->csiColon) unsupported(g, RC_UN_COLON);
          i++;
          continue;
        }
        if (u == 0x18 || u == 0x1A) { g->mode = RC_GROUND; i++; continue; }   /* CAN / SUB abort */
        /* Any other byte, ESC included, abandons the CSI and is re-examined from ground. ConEmu
           instead parks it in Pvt and keeps eating (deviation #1, see Render.h). */
        g->mode = RC_GROUND;
        continue;
      }

      case RC_OSC:
      {
        if (u == 0x07) { osc_finish(g, 1); g->mode = RC_GROUND; i++; continue; }               /* BEL */
        if (u == 0x1B) { g->mode = RC_OSC_ESC; i++; continue; }              /* ST, or abandon */
        if (u == 0x18 || u == 0x1A) { osc_finish(g, 0); g->mode = RC_GROUND; i++; continue; }
        if (g->nTitle < RC_TITLE_MAX) g->title[g->nTitle++] = u;
        else g->oscClip = 1;                     /* still consumed, and a title from it is counted truncated */
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
        if (u == '(' || u == ')' || u == '%') { g->mode = RC_ESC_INTERIM; g->interim = u; i++; continue; }
        /* SS2/SS3: esc_end() counts the introducer as the whole sequence, so the byte that follows is
           ordinary text. Swallowing it would drop a column from the line. */
        if (u == 'N' || u == 'O') { g->mode = RC_GROUND; i++; continue; }
        if (u >= 0x20 && u <= 0x2F) { g->mode = RC_ESC_INTERIM; g->interim = u; i++; continue; }
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
        uint8_t intro = (uint8_t)g->interim;
        if (intro == '(' || intro == ')' || intro == '%')
        {
          /* One byte of payload and the sequence is over, whoever it designated. */
          esc_charset(g, intro, (uint8_t)u);
          g->mode = RC_GROUND;
          i++;
          continue;
        }
        if (u >= 0x20 && u <= 0x2F) { g->interim = u; i++; continue; }   /* more intermediates */
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
  g->winRows = winRows;
  g->cy = histRows;                                 /* the viewport's first row, whatever the gutter is */
  g->defAttr = defAttr;
  g->cursorVisible = 1;
  g->cursorShape = -1;     /* memset above says 0, which here would mean "a DECSCUSR asked for the thin
                              cursor" -- the two are only told apart by this, and the difference is that a
                              session nobody shaped may not touch the user's console cursor height. */
  /* Two more slots where 0 is a answer and not a question. `lastUnit` is what REP replays, and ConEmu's
     m_LastWrittenChar starts at L' ' (Ansi.h:197), so a session that never printed anything and asked for a
     repeat gets spaces here too -- a 0 would make `CSI b` print nothing and read as "no glyph to repeat".
     `lastExit` is 0 for "the command succeeded", which is a claim, not an absence: -1 until a 133;D says so. */
  g->lastUnit = ' ';
  g->lastExit = -1;
  sgr_reset(g, 1);                                   /* the underscore bit comes from the default */
  for (int r = 0; r < g->rows; r++)
    for (int c = 0; c < cols; c++)
    {
      g->cells[r][c].ch = ' ';
      g->cells[r][c].attr = defAttr;
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

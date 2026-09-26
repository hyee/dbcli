/*
 * RenderCheck.cpp -- the host-side gate for Render.cpp: no console, no JNI, no Windows.
 *
 * Why this exists as a separate binary: the whole parity claim of the native renderer is "the same
 * bytes produce the same grid on Win7 and Win11" (user ruling). That claim is mostly about the
 * parser, the width tables and the colour fold -- all three of which are console-free computations
 * that can be executed here. So every rule that can be settled without a terminal is settled here,
 * and only what genuinely needs conhost (paint, whether EL reaches the viewport or the buffer width,
 * what a legacy console does with a surrogate pair) is left for the grid witness.
 *
 * Six sections:
 *   1. colour   -- replays cache/native-probe/out/colors-native.txt, the ConEmu folding dumped by
 *                  ColorCheck over all 256 palette indices and 10 truecolour probes. .dsh/memory
 *                  names that artefact as the colour spec; if the renderer disagrees with it index by
 *                  index, the fast path and WriteProcessed3 disagree on screen.
 *   2. widths   -- rc_width() against an independent binary search over the very same generated
 *                  interval table, plus the individually measured characters pinned in
 *                  src/c/luauf8/ansi_width.c's header. This catches a fork in the copied cp_width(),
 *                  which is the price of not sharing that file's internals.
 *   3. grammar  -- escape-parsing verdicts, including deviation #1 (an ESC abandons the open sequence
 *                  and is re-examined), the OSC 133 family, and the shapes the shipped application's output contains.
 *   4. geometry -- cells, wrapping, erasing, scrolling, damage, and the row claims a 133 lays down.
 *   5. resume   -- every input from 3 and 4 replayed one UTF-16 unit at a time and diffed against the
 *                  whole-string result. A sequence whose meaning depends on where the chunk boundary
 *                  fell is exactly the bug class that painted a literal "[33m".
 *   6. plan     -- rc_plan_paint (Paint.cpp): the console operations a flush owes, which is where the
 *                  shipped Java writer's §13/§14.1/§21 bugs lived. Needs no console: a view is seven
 *                  integers. Includes the gutter -- the unpainted scrollback rows above the viewport
 *                  that let a chunk of several screenfuls be painted in full -- and rc_feed()'s mid-chunk
 *                  flush hook that fills it.
 *
 * Exit code is the gate; build.sh treats non-zero as a build failure.
 */

#include "Render.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "HostTypes.h"
#include "../luauf8/ansi_width_tables.h"
#include "Paint.h"
#include "vendor/ConEmuRgbMap.h"

static int g_checks, g_fails;

/* Rotating context buffers, so an assertion can name its inputs without a malloc per failure. */
static char g_slot[4][192];
static int g_slot_i;
static const char *S(const char *fmt, ...)
{
  char *buf = g_slot[g_slot_i = (g_slot_i + 1) & 3];
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(buf, sizeof g_slot[0], fmt, ap);
  va_end(ap);
  return buf;
}

static void eq_u(const char *what, unsigned got, unsigned want, const char *ctx)
{
  g_checks++;
  if (got == want) return;
  g_fails++;
  printf("FAIL  %s: got 0x%X want 0x%X  {%s}\n", what, got, want, ctx);
}

static void eq_text(const RcGrid *g, int row, int upto, const char *want, const char *ctx)
{
  g_checks++;
  /* A zero width is not a weak assertion, it is no assertion: the loop below does not run and the call still
     votes "pass". Two of those existed in this file -- one written this month -- and both were invisible until
     someone asked why a red arm came back green, which is the same question #73's arm asked. Refuse the shape
     rather than remember to avoid it. */
  if (upto <= 0)
  {
    g_fails++;
    printf("FAIL  eq_text(row %d, upto %d) would compare no cells  {%s}\n", row, upto, ctx);
    return;
  }
  /* The other half of the same mistake: `cells[]` is a fixed RC_MAX_COLS stride, so asking past the model's
     width reads the bytes a *wider* geometry left behind rather than anything this row ever held. */
  if (upto > g->cols)
  {
    g_fails++;
    printf("FAIL  eq_text(row %d, upto %d) reaches past a %d-column grid  {%s}\n", row, upto, g->cols, ctx);
    return;
  }
  for (int i = 0; i < upto; i++)
  {
    unsigned ch = RC_CELLS(g, row)[i].ch;
    /* Past the terminator everything is a space. The old form tested `want[i] ? want[i] : ' '`, which reads
       the bytes *after* the literal for every i beyond it -- so a leg asking for ten columns of "r0" was
       comparing that row against whatever the linker happened to place next, and could pass or fail on where
       its strings sat. `upto > strlen(want)` is the common case here, not a corner. */
    const unsigned w = ((int)i < (int)strlen(want)) ? (unsigned)(unsigned char)want[i] : ' ';
    if (ch == w) continue;
    g_fails++;
    printf("FAIL  cell(%d,%d)=0x%04X want 0x%04X  {%s}\n", row, i, ch, w, ctx);
    return;
  }
}

/* The columns a dirty row will repaint (B2). Naming a row without naming its columns proves only half of
   what the painter does now, so every damage gate below says both. */
static void eq_span(const RcGrid *g, int row, int lo, int hi, const char *ctx)
{
  g_checks++;
  if (!rc_row_dirty(g, row))
  {
    g_fails++;
    printf("FAIL  row %d clean, want %d..%d  {%s}\n", row, lo, hi, ctx);
    return;
  }
  if ((int)RC_LO(g, row) == lo && (int)RC_HI(g, row) == hi) return;
  g_fails++;
  printf("FAIL  span row %d: got %d..%d want %d..%d  {%s}\n",
         row, RC_LO(g, row), RC_HI(g, row), lo, hi, ctx);
}

/* A row that knows no narrower answer: the whole buffer row. */
static void eq_full(const RcGrid *g, int row, const char *ctx)
{
  eq_span(g, row, 0, g->cols - 1, ctx);
}

/* I16 read back as a shape rather than a wish: no cell may claim to be half of a glyph whose other half is
   somewhere else. Asserted after every edit that moves or erases cells, because the failures worth catching
   are the ones where the row still spells something plausible -- an orphaned leading half renders as a wide
   glyph that swallows its neighbour, an orphaned trailing half as a column that is silently not the one the
   next write lands on, and neither is visible in the text. */
static void no_orphan(const RcGrid *g, int row, const char *ctx)
{
  g_checks++;
  for (int c = 0; c < g->cols; c++)
  {
    const unsigned a = RC_CELLS(g, row)[c].attr;
    int bad;
    if (a & RC_LVB_LEADING)
      bad = (c + 1 >= g->cols) || !(RC_CELLS(g, row)[c + 1].attr & RC_LVB_TRAILING);
    else if (a & RC_LVB_TRAILING)
      bad = (c == 0) || !(RC_CELLS(g, row)[c - 1].attr & RC_LVB_LEADING);
    else continue;
    if (!bad) continue;
    g_fails++;
    printf("FAIL  row %d column %d is 0x%X, half a glyph with no partner (its cells are 0x%04X | 0x%04X)"
           "  {%s}\n", row, c, (a & RC_LVB_LEADING) ? RC_LVB_LEADING : RC_LVB_TRAILING,
           (unsigned)RC_CELLS(g, row)[c > 0 ? c - 1 : 0].attr,
           (unsigned)RC_CELLS(g, row)[c + 1 < g->cols ? c + 1 : c].attr, ctx);
    return;
  }
}

/* ------------------------------------------------------------- feeding helpers ----------------- */

/* The corpus section 5 replays. put() registers, putraw() does not: the colour loop builds 512
 * near-identical SGR strings and chunk-hammering those would add nothing but runtime.
 *
 * The cap is not allowed to bite quietly. A full table turns put() into putraw() without saying so, which is
 * the same shape as a zero-evidence `else`: sections 5 and 6 would go on printing their verdicts over a
 * smaller corpus than the file feeds them. So an overflow is a failure, and the size is what the whole file
 * currently registers plus room for the next witness. */
static char g_corpus[512][128];
static int g_ncorpus;

static void corpus_add(const char *s)
{
  for (int i = 0; i < g_ncorpus; i++)
    if (!strcmp(g_corpus[i], s)) return;
  if (g_ncorpus >= (int)(sizeof g_corpus / sizeof g_corpus[0]))
  {
    g_fails++;
    printf("FAIL  corpus full at %d entries; %s was not added to the replay set\n", g_ncorpus, s);
    return;
  }
  const int n = snprintf(g_corpus[g_ncorpus], sizeof g_corpus[0], "%s", s);
  if (n < 0 || n >= (int)sizeof g_corpus[0])
  {
    g_fails++;
    printf("FAIL  corpus entry does not fit in %d units, so the replay set holds half of it\n",
           (int)sizeof g_corpus[0]);
    return;
  }
  g_ncorpus++;
}

static void putraw(RcGrid *g, const char *s)
{
  uint16_t buf[128];
  int n = 0;
  for (; *s && n < 128; s++) buf[n++] = (uint16_t)(unsigned char)*s;
  rc_feed(g, buf, n);
}

/* Every string the gates feed has to leave the grid internally consistent, and this is the one place all three
   feed paths (whole string, unit-at-a-time, uint16 array) can be watched. It is a witness over the model, not
   a paint assertion: a violation here means some edit left the grid in a state the rest of this file's
   comments claim is impossible, which is exactly the class -25 fixed (a fill that reaches one half of a wide
   glyph and not the other). The live gate has its own copy of this eye, through the gate-only export, because
   the host gate links Render.cpp directly and cannot speak for the dll that ships. */
static void grid_ok(const RcGrid *g, const char *ctx)
{
  char msg[256];
  g_checks++;
  if (!rc_validate_grid(g, msg, (int) sizeof msg)) return;
  g_fails++;
  printf("  FAIL grid invariants after %s: %s\n", ctx, msg);
}

/* The take below hands out the whole queue entry; most gates want one field of it and nothing else. */
static int take_xy(RcGrid *g, int *row, int *col)
{
  struct RcReportItem it;
  const int kind = rc_report_take(g, &it);
  if (row) *row = it.y;
  if (col) *col = it.x;
  return kind;
}

static void put(RcGrid *g, const char *s)
{
  corpus_add(s);
  putraw(g, s);
  grid_ok(g, s);
}

static void putu(RcGrid *g, const uint16_t *u, int n) { rc_feed(g, u, n); grid_ok(g, "a uint16 feed"); }

static void put1(RcGrid *g, const char *s)         /* one unit per call: the chunk-boundary hammer */
{
  while (*s)
  {
    uint16_t u = (uint16_t)(unsigned char)*s++;
    rc_feed(g, &u, 1);
  }
  grid_ok(g, s ? "unit-at-a-time feed" : "unit-at-a-time feed");
}

/* =========================================================== 1. colour parity ================== */

/*
 * colors-native.txt columns, as emitted by ColorCheck.cpp:
 *   FOLD <n> <entry> <fg> <attrOnDefault7> <attrOnSameFg> <D|F>
 *     entry           ConEmu's RgbMap[n]: a console attribute when D (n<16), a 0x00BBGGRR when F
 *     fg              the foreground nibble that colour folds to
 *     attrOnDefault7  the painted attribute for \e[48;5;Nm over the default prompt colour 0x07
 *     attrOnSameFg    the same colour used as the foreground too: \e[38;5;Nm\e[48;5;Nm
 *   TC <rgb> <attr-both> <attr-on-default-7>      truecolour, the same two shapes
 * The D|F split is the whole reason there are two attr columns: a low index never reaches Far3Color,
 * so it never gets the fg==bg bump, and \e[48;5;7m over a 7 foreground really does paint invisible
 * text. Everything here runs against defAttr 0x07, the attribute the oracle was dumped with.
 */
static void check_colors(const char *path)
{
  FILE *f = fopen(path, "r");
  if (!f)
  {
    g_fails++;
    printf("FAIL  cannot open %s -- build.sh writes it (host ColorCheck run) before this test\n", path);
    return;
  }

  static RcGrid g;
  rc_reset(&g, 80, 6, 0x07);
  char line[256];
  int nfold = 0, ntc = 0;
  while (fgets(line, sizeof line, f))
  {
    char kind[8] = {0};
    unsigned n, entry, fg, a7, as;
    char flag;
    if (sscanf(line, "%7s %u %u %u %u %u %c", kind, &n, &entry, &fg, &a7, &as, &flag) == 7 &&
        !strcmp(kind, "FOLD") && n < 256)
    {
      nfold++;
      const char *ctx = S("n=%u", n);
      eq_u("RgbMap identity", RgbMap[n], entry, ctx);      /* our generated header vs upstream's */

      char seq[64];
      snprintf(seq, sizeof seq, "\033[0m\033[38;5;%um", n);
      putraw(&g, seq);
      eq_u("fg nibble of 38;5;n", g.attr & 0xF, fg, ctx);

      snprintf(seq, sizeof seq, "\033[0m\033[48;5;%um", n);
      putraw(&g, seq);
      eq_u("attrOnDefault7", g.attr, a7, ctx);

      snprintf(seq, sizeof seq, "\033[0m\033[38;5;%um\033[48;5;%um", n, n);
      putraw(&g, seq);
      eq_u("attrOnSameFg", g.attr, as, ctx);
      continue;
    }

    unsigned rgb, both, on7;
    if (sscanf(line, "%7s %u %u %u", kind, &rgb, &both, &on7) == 4 && !strcmp(kind, "TC"))
    {
      ntc++;
      const char *ctx = S("rgb=0x%06X", rgb);
      unsigned r = rgb & 0xFF, gg = (rgb >> 8) & 0xFF, bb = (rgb >> 16) & 0xFF;
      char seq[96];
      snprintf(seq, sizeof seq, "\033[0m\033[38;2;%u;%u;%um\033[48;2;%u;%u;%um", r, gg, bb, r, gg, bb);
      putraw(&g, seq);
      eq_u("truecolour fg==bg", g.attr, both, ctx);

      snprintf(seq, sizeof seq, "\033[0m\033[48;2;%u;%u;%um", r, gg, bb);
      putraw(&g, seq);
      eq_u("truecolour on default 7", g.attr, on7, ctx);
    }
  }
  fclose(f);
  g_checks++;
  if (nfold != 256 || ntc != 10)
  {
    g_fails++;
    printf("FAIL  colour table incomplete: %d FOLD lines (want 256), %d TC lines (want 10)\n", nfold, ntc);
  }
  else
    printf("colour  %d FOLD + %d TC replayed against upstream's table\n", nfold, ntc);
}

/* ============================================================ 2. width parity ================== */

/* A different algorithm over the same generated data: binary search, where rc_width() uses the block
 * table and a forward scan that starts at the first interval that can overlap. Any transcription
 * slip in the accelerated path shows up here. */
static int width_ref(uint32_t cp)
{
  uint32_t lo = 0, hi = ANSI_NWIV;
  while (lo < hi)
  {
    uint32_t mid = (lo + hi) / 2;
    if (ansi_wiv[mid].last < cp) lo = mid + 1;
    else hi = mid;
  }
  if (lo < ANSI_NWIV && ansi_wiv[lo].first <= cp) return ansi_wiv[lo].w;
  return 1;
}

static void check_widths()
{
  int diffs = 0, first = -1;
  for (uint32_t cp = 0; cp <= 0x10FFFFu; cp++)
  {
    if (cp >= 0xD800 && cp <= 0xDFFF) continue;   /* never reaches rc_width(): rc_feed pairs or replaces */
    if (rc_width(cp) == width_ref(cp)) continue;
    if (!diffs) first = (int)cp;
    diffs++;
  }
  g_checks++;
  if (diffs)
  {
    g_fails++;
    printf("FAIL  rc_width disagrees with the table over %d code points, first U+%04X (%d vs %d)\n",
           diffs, first, rc_width((uint32_t)first), width_ref((uint32_t)first));
  }

  /* The individually measured verdicts, restated so a table regeneration cannot quietly flip one.
     The eight ambiguous rows pin both halves of the ruling: EAW=A is wide, except the code points
     measured one cell in *every* console font, which stay narrow. See I14 and DESIGN.md §9. */
  static const struct { uint32_t cp; int want; const char *why; } pin[] = {
    {0x0041, 1, "ASCII"},
    {0x0301, 0, "combining acute (Mn)"},
    {0x200B, 0, "ZWSP (Cf)"},
    {0x00AD, 1, "soft hyphen: terminals still draw it"},
    {0x0600, 1, "Prepended_Concatenation_Mark: drawn"},
    {0x1100, 2, "Hangul initial (EAW W)"},
    {0x1160, 0, "conjoining Hangul jamo"},
    {0x4E00, 2, "CJK ideograph"},
    {0xFF61, 1, "halfwidth ideographic point (EAW H, not ambiguous)"},
    {0x09BE, 1, "Mc spacing mark"},
    {0x4DC0, 2, "Yijing hexagram"},
    {0x1F600, 2, "astral emoji"},
    {0x00E9, 1, "ambiguous, measured narrow in all six faces"},
    {0x2500, 1, "ambiguous box drawing: a border must stay one cell"},
    {0x2592, 1, "ambiguous shade block: the narrow runs stop at U+2595"},
    {0x00B0, 2, "ambiguous degree sign: the font-split set follows the ruling"},
    {0x2192, 2, "ambiguous arrow"},
    {0x3248, 2, "ambiguous circled number, where glibc and Windows Terminal disagree"},
    {0xE000, 2, "basic private use: wide in every face measured"},
    {0xF0000, 2, "astral private use"},
  };
  for (unsigned i = 0; i < sizeof pin / sizeof pin[0]; i++)
    eq_u(pin[i].why, (unsigned)rc_width(pin[i].cp), (unsigned)pin[i].want, S("U+%04X", pin[i].cp));
  printf("width   0x110000 code points cross-checked, %d pinned classes\n",
         (int)(sizeof pin / sizeof pin[0]));
}

/* ============================================================ 3. grammar ======================= */

static void gm_split_sgr()
{
  static RcGrid g;
  rc_reset(&g, 20, 4, 0x07);
  put1(&g, "\033[3");                                 /* the exact shape the shipped writer lost */
  eq_u("mode after a partial CSI", (unsigned)g.mode, RC_CSI, "pending, not abandoned");
  eq_u("nothing painted while pending", g.nCells, 0, "");
  put1(&g, "3m");
  eq_u("attr after a reassembled CSI", g.attr, 0x06, "33m yellow foreground over the default background 0");
  put(&g, "X");
  eq_text(&g, 0, 1, "X", "split SGR paints one cell");
  eq_u("cursor after split SGR", (unsigned)g.cx, 1, "X");
}

static void gm_double_esc()
{
  /* "\e\e[33m": the first ESC is a sequence of one (esc_end), the second opens the CSI. Painting the
     ESC, or treating "[33m" as text, is the bug this case pins -- the same rule had to be fixed once in
     the Java rectangle writer (BulkCellWriter, retired 2026-09-23). */
  static RcGrid g;
  rc_reset(&g, 20, 4, 0x07);
  put1(&g, "\033");
  put(&g, "\033[33mX");
  eq_u("ESC ESC cells painted", g.nCells, 1, "only the X");
  eq_u("ESC ESC attr", g.attr, 0x06, "yellow foreground");
}

static void gm_abandon_and_restart()
{
  /* Deviation #1. ConEmu parks the ESC in Code.Pvt and keeps eating until a final byte, so it applies
     no colour and repaints the tail; esc_end() abandons the open sequence and re-examines the ESC, so
     the following sequence wins and the buffered "3" is dropped rather than painted. */
  static RcGrid g;
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[3\033[31mX");
  eq_u("abandon+restart attr", g.attr, 0x04, "31m red foreground, ClrMap[1]=4");
  eq_text(&g, 0, 1, "X", "no stray 31m text");
  eq_u("abandon+restart cells", g.nCells, 1, "X only");
}

static void gm_osc()
{
  static RcGrid g;
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]0;render\007X");
  eq_u("OSC cells", g.nCells, 1, "a BEL-terminated OSC paints nothing");
  eq_text(&g, 0, 1, "X", "after BEL");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]0;db\033[31mX");
  eq_u("OSC abandoned by ESC", g.attr, 0x04, "the new ESC opens a CSI");
  eq_text(&g, 0, 1, "X", "an abandoned OSC leaves no text behind");
  eq_u("OSC abandoned by ST-looking ESC", g.mode, RC_GROUND, "consumed");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]0;db\033\\X");
  eq_text(&g, 0, 1, "X", "ST terminates an OSC");
  eq_u("OSC via ST attr", g.attr, 0x07, "unchanged");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]0;unterminated\033[31mY");
  eq_u("unterminated OSC swallowed no text", g.nCells, 1, "only the Y");
}

/* The pending title, asserted and consumed. rc_title_pending() and the length are two facts and the
 * interface keeps them two: ESC ] 0 ; "" ST is a title of zero units, not the absence of one.
 * `want` NULL means "no title was accepted". */
static void eq_title(RcGrid *g, const char *want, const char *ctx)
{
  g_checks++;
  if (!rc_title_pending(g))
  {
    if (!want) return;
    g_fails++;
    printf("FAIL  title: none pending, want \"%s\"  {%s}\n", want, ctx);
    return;
  }
  uint16_t t[RC_TITLE_MAX + 1];
  const int n = rc_title_take(g, t, RC_TITLE_MAX);
  char s[RC_TITLE_MAX + 1];
  for (int i = 0; i < n; i++) s[i] = (char)t[i];      /* every case below feeds ASCII */
  s[n] = 0;
  if (want && !strcmp(s, want)) return;
  g_fails++;
  if (!want) printf("FAIL  title: \"%s\" pending, wanted none  {%s}\n", s, ctx);
  else printf("FAIL  title: got \"%s\" want \"%s\"  {%s}\n", s, want, ctx);
}

/*
 * The OSC/DCS family: what is counted, what is applied, and what is never run. These counters are the
 * family's only witness. A window title and a GuiMacro both change state *outside* the screen buffer, so
 * no grid diff -- here or at the console -- can ever show one, which is the reason the whole family used
 * to be swallowed with no record at all (and why DESIGN's I19 needed the JNI slots to be added before it
 * could be true).
 */
static void gm_osc_family()
{
  static RcGrid g;

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]0;render\007X");
  eq_text(&g, 0, 1, "X", "an OSC still paints nothing");
  eq_title(&g, "render", "OSC 0 is a title");
  eq_u("one title parsed", g.nTitleSet, 1, "");
  eq_u("a title is not a dropped sequence",
       (unsigned)(g.nUnsupported[RC_UN_OSC_OTHER] + g.nUnsupported[RC_UN_OSC_PRIV]
                  + g.nUnsupported[RC_UN_DCS]), 0, "");
  eq_u("the take cleared the flag", (unsigned)rc_title_pending(&g), 0, "");

  /* 1 and 2 are the same three lines upstream (Ansi.cpp:3842-3854); both name the window here. The model
     holds one title, so the last of a chunk is the one that reaches the console -- which is all the
     console can ever show, and nTitleSet still says two were parsed. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]1;icon\007\033]2;win\007");
  eq_title(&g, "win", "the last title wins");
  eq_u("both parsed", g.nTitleSet, 2, "one of them reaches the console");

  /* The private family: counted, never run. ESC ] 9 ; 7 runs a process and 9 ; 6 runs a GuiMacro, which
     is what CONEMU_ANSI_DEFECTS #687 calls remote code execution. The counter is how a session can prove
     it saw one and did nothing about it. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]9;7;calc.exe\007\033]9;6;GuiMacro(\"x\")\007");
  eq_u("OSC 9 counted", g.nUnsupported[RC_UN_OSC_PRIV], 2, "sleep, macro, process: counted, not run");
  eq_title(&g, NULL, "9 is not a title");
  eq_text(&g, 0, 1, " ", "and it leaves no text behind");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]10;fg\007\033]4;1;rgb:00/00/00\007\033]52;c;AAAA\007\033]\007");
  eq_u("other OSC counted", g.nUnsupported[RC_UN_OSC_OTHER], 2,
       "the name in `10;fg` and a bare introducer -- `4;1;rgb:00/00/00` is applied now (I34), so it votes nothing,"
       " and 52 left this list for its own family (I36)");
  eq_u("52 votes in the clipboard's bucket instead", g.nUnsupported[RC_UN_OSC_CLIP], 1,
       "the sequence is still in the stream above, which is the proof the count moved rather than vanished");
  eq_title(&g, NULL, "none of them is a title");

  /* The guard ConEmu really has (Ansi.cpp:3845): the ';' must sit at index 1, so "]10;t" is not a title
     even though it starts with a digit a title would use; and the payload must not be empty, so "]0;" is
     not one either. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]10;t\007\033]0;\007\033]0t\007\033]t;\007");
  eq_u("near-misses are not titles", g.nUnsupported[RC_UN_OSC_OTHER], 4, "");
  eq_title(&g, NULL, "");

  /* Quotes: EscCopyCtrlString strips one surrounding pair when more than one character is left
     (Ansi.cpp:2276-2283). A pair on its own is a title of zero units -- an explicit clear, not a no-op,
     because CEStr::c_str's substitute covers an unallocated buffer, not an empty one. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]0;\"abc\"\007");
  eq_title(&g, "abc", "a surrounding pair is stripped");
  put(&g, "\033]0;\"abc\007");
  eq_title(&g, "\"abc", "an unpaired quote stays");
  put(&g, "\033]0;ab\"cd\007");
  eq_title(&g, "ab\"cd", "only a surrounding pair counts");
  put(&g, "\033]0;\"\"\007");
  eq_title(&g, "", "an explicit empty title is still a title");
  eq_u("four titles", g.nTitleSet, 4, "");

  /* DCS, SOS, PM and APC: identical framing, the whole payload discarded, and a counter of their own --
     separating them is what lets the title counter mean what it says. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033P1;2$q+\033\\\033Xq\033\\\033^q\033\\\033_q\033\\");
  eq_u("DCS family counted", g.nUnsupported[RC_UN_DCS], 4, "ESC P, X, ^ and _");
  eq_title(&g, NULL, "and none of them set a title");

  /* An OSC abandoned mid-payload is counted and its title dropped. Upstream would have kept eating past
     the ESC and applied neither (deviation #1); we apply the colour -- the better half -- and the counter
     says the title was abandoned rather than absent. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]0;gone\033[31mX");
  eq_u("abandoned OSC counted", g.nUnsupported[RC_UN_OSC_OTHER], 1, "");
  eq_title(&g, NULL, "a title that never terminated is not applied");
  eq_u("the CSI after it still applied", g.attr, 0x04, "deviation #1");
  put(&g, "\033]9;7;calc.exe\033[31m");
  eq_u("an abandoned OSC 9 is still counted", g.nUnsupported[RC_UN_OSC_PRIV], 1,
       "the stream asked for a process to be run, terminated or not");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]0;mid\030X");
  eq_u("CAN aborts an OSC", g.nUnsupported[RC_UN_OSC_OTHER], 1, "and is not a title");
  eq_text(&g, 0, 1, "X", "the X after CAN is text");

  /* An OSC still open when the chunk ends is neither abandoned nor counted: it resumes. This is the
     case the resumable state machine exists for (deviation #2). */
  rc_reset(&g, 20, 4, 0x07);
  put1(&g, "\033]0;split\007");
  eq_title(&g, "split", "unit by unit, the way a chunk boundary delivers it");
  putraw(&g, "\033]0;held");
  eq_u("an open OSC is pending, not abandoned", (unsigned)g.mode, RC_OSC, "");
  eq_u("and it has counted nothing", g.nUnsupported[RC_UN_OSC_OTHER], 0, "");
  eq_title(&g, NULL, "nothing to apply yet");
  putraw(&g, "\007");
  eq_title(&g, "held", "the next chunk closes it");

  /* A payload past RC_TITLE_MAX is applied truncated and counted; the sequence is still consumed whole.
     The cap holds the *payload*, "0;" included, so the title that survives is two units shorter than the
     cap -- the same shape as upstream, where the 512-unit escape buffer counts the introducer too. */
  rc_reset(&g, 20, 4, 0x07);
  {
    static uint16_t big[4 + RC_TITLE_MAX + 5];
    big[0] = 0x1B; big[1] = ']'; big[2] = '0'; big[3] = ';';
    for (int i = 0; i < RC_TITLE_MAX + 4; i++) big[4 + i] = 'x';
    big[4 + RC_TITLE_MAX + 4] = 0x07;
    rc_feed(&g, big, 4 + RC_TITLE_MAX + 5);
  }
  char many[RC_TITLE_MAX + 1];
  memset(many, 'x', RC_TITLE_MAX - 2);
  many[RC_TITLE_MAX - 2] = 0;
  eq_title(&g, many, "the payload after \"0;\", clipped at what the cap leaves");
  eq_u("truncation counted", g.nTitleTrunc, 1, "");
  eq_u("the rest of the sequence was consumed", (unsigned)g.mode, RC_GROUND, "");

  /* rc_title_take refuses a buffer that cannot hold the title and leaves the title pending: losing one
     is a bug rather than a policy, which is the same rule rc_sgr_take follows. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]0;abcdef\007");
  {
    uint16_t small[3];
    eq_u("a too-small take refuses", (unsigned)rc_title_take(&g, small, 3), (unsigned)-1, "");
    eq_u("and the title is still there", (unsigned)rc_title_pending(&g), 1, "");
  }
  eq_title(&g, "abcdef", "a bigger buffer gets it later");
}

/* ------------------------------------------------------- 3i. OSC 133 (FTCS) grammar ------------- */

/* Which payloads are commands and which are nothing. The geometry of a mark is geo_ftcs()'s; this is the
 * classifier, taken from the two implementations that read the family -- ghostty's parser table
 * (osc/parsers/semantic_prompt.zig:327-399) and MSFT's (adaptDispatch.cpp:3692-3764). ConEmu contributes
 * nothing to either verdict: it has no case for 133 and consumes the payload in silence (Ansi.cpp:3845 fails
 * the `ArgSZ[1] == ';'` guard a title needs), so the census counter is the whole record that a stream used
 * the family. */
static void gm_ftcs()
{
  static RcGrid g;

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;A\007");
  eq_u("133;A is a command", (unsigned)rc_row_mark(&g, 0), RC_PM_PROMPT, "");
  eq_u("and it is not a dropped sequence",
       (unsigned)(g.nUnsupported[RC_UN_OSC_OTHER] + g.nUnsupported[RC_UN_OSC_PRIV]), 0, "");
  eq_u("one mark laid", (unsigned)rc_prompt_marks(&g), 1, "");
  eq_text(&g, 0, 1, " ", "a 133 paints no cells");

  /* The rejections, one per rule. ghostty's parser falls out of its switch for each of them; MSFT's
   * `parts[0].length() != 1` and its default arm agree on the same list -- except that ConEmu would have
   * accepted "]0133;A" as nothing at all, and so do we, on the *string* rather than the number. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133\007");            /* no ';' at all: no payload */
  put(&g, "\033]133;\007");            /* an empty payload */
  put(&g, "\033]133;Q\007");            /* unknown action letter */
  put(&g, "\033]133;AX\007");           /* junk glued to the letter instead of a ';' */
  put(&g, "\033]133;L;k=c\007");        /* L is the one action that allows no options (:379) */
  put(&g, "\033]133;L;\007");           /* not even an empty option list */
  put(&g, "\033]0133;A\007");           /* a leading zero is not the code 133 */
  put(&g, "\033]1334;A\007");           /* a different code */
  put(&g, "\033]1000000;A\007");        /* past the cap: saturates, and cannot wrap back to 133 */
  eq_u("every one counted as an OSC we did not act on", g.nUnsupported[RC_UN_OSC_OTHER], 9, "");
  eq_u("and none of them marked a row", (unsigned)rc_prompt_marks(&g), 0, "");
  eq_u("nothing reached the cursor either", (unsigned)g.cy, 0, "");

  /* What is *wrong inside* the options is not a rejection: unkeyed fields, unknown keys and empty values are
   * all stepped over and the command still lands (ghostty keeps the option string verbatim and splits it on
   * demand, :151-202). */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;A;aid=14;cl=line\007");
  eq_u("unknown options are skipped", (unsigned)rc_row_mark(&g, 0), RC_PM_PROMPT, "a future shell may send them");
  put(&g, "\033[1;4H\033]133;P;zz\007");
  eq_u("a field with no '=' names no key and is skipped too", (unsigned)rc_row_mark(&g, 0), RC_PM_PROMPT, "");
  eq_u("and the second prompt did not move the one already there", (unsigned)rc_mark_col(&g, 0), 0,
       "MSFT emplaces a prompt only when the row has none (Row.cpp:1263)");
  eq_u("one mark laid, not two", (unsigned)rc_prompt_marks(&g), 1, "");

  /* k= is ghostty's only, and it is exact: one character out of i r c s, and the first field that carries the
   * key decides even when its value is garbage (the read returns at the key match, :180-207). */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;P;k=c\007");
  eq_u("k=c is a continuation prompt", (unsigned)rc_row_mark(&g, 0), RC_PM_CONTINUATION, "");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;P;k=s\007");
  eq_u("k=s likewise", (unsigned)rc_row_mark(&g, 0), RC_PM_CONTINUATION, "fish's secondary prompt");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;P;k=i\007");
  eq_u("k=i is the default anyway", (unsigned)rc_row_mark(&g, 0), RC_PM_PROMPT, "");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;P;k=x;k=c\007");
  eq_u("a bad value stops the scan rather than passing the choice on", (unsigned)rc_row_mark(&g, 0),
       RC_PM_PROMPT, "so the later k=c is never read");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;P;k=cc\007");
  eq_u("a two-character value is not a value", (unsigned)rc_row_mark(&g, 0), RC_PM_PROMPT, "`value.len == 1`");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;P;;k=c\007");
  eq_u("an empty field before it does not spoil the option", (unsigned)rc_row_mark(&g, 0),
       RC_PM_CONTINUATION, "MSFT has no k at all: this is ghostty's rule alone");

  /* Abandoned, the two ways. A 133 that never terminated is dropped rather than applied: unlike a title,
   * where the cost of applying nothing is one wrong window caption, the cost here is a mark on the wrong row
   * and a jump-to-prompt that later offers the wrong destination. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;A\033[31m");
  eq_u("an ESC abandons it", g.nUnsupported[RC_UN_OSC_OTHER], 1, "deviation #1");
  eq_u("no row was marked", (unsigned)rc_prompt_marks(&g), 0, "");
  eq_u("and the CSI after it still applied", g.attr, 0x04, "");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;A\030");
  eq_u("so does a CAN", g.nUnsupported[RC_UN_OSC_OTHER], 1, "");
  eq_u("and it marked nothing", (unsigned)rc_prompt_marks(&g), 0, "");

  /* Open at the end of a chunk is neither: it resumes, which is the case the resumable state machine exists
   * for (deviation #2). The mark lands when the terminator does. */
  rc_reset(&g, 20, 4, 0x07);
  putraw(&g, "\033]133;A");
  eq_u("still parsing", (unsigned)g.mode, RC_OSC, "");
  eq_u("counted nothing", g.nUnsupported[RC_UN_OSC_OTHER], 0, "");
  eq_u("marked nothing yet", (unsigned)rc_prompt_marks(&g), 0, "");
  putraw(&g, "\007");
  eq_u("the next chunk closes it and the mark lands", (unsigned)rc_row_mark(&g, 0), RC_PM_PROMPT, "");
  put1(&g, "\033]133;B\007");
  eq_u("unit by unit is the same command", (unsigned)g.semanticContent, RC_SC_INPUT, "");
}

static void gm_charset()
{
  const uint16_t q = 'q';
  static RcGrid g;
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033(0");
  putu(&g, &q, 1);
  eq_u("ESC ( 0 remap", RC_CELLS(&g, 0)[0].ch, 0x2500, "q -> horizontal line");
  put(&g, "\033(B");
  putu(&g, &q, 1);
  eq_u("ESC ( B restores", RC_CELLS(&g, 0)[1].ch, 'q', "default set");
  eq_u("and neither designator is counted", g.nUnsupported[RC_UN_SUP], 0,
       "the smacs/rmacs path is modelled; a count here would make the census unreadable as a ratio");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033)0q");                                 /* G1 is unreachable upstream, and so here */
  eq_text(&g, 0, 1, "q", "an ESC ) designator has no effect on G0");
  eq_u("but ESC ) 0 leaves a count", g.nUnsupported[RC_UN_SUP], 1,
       "it has no case upstream either (Ansi.cpp:2769-2770 falls to DumpUnknownEscape)");
  eq_u("counted inert, not suspected", (unsigned)g.modelSuspect, 0, "the arm is read, not assumed");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033%Gq");
  eq_text(&g, 0, 1, "q", "ESC % G never selects UTF-8: the flag has no writer here or upstream");
  eq_u("ESC % G counted", g.nUnsupported[RC_UN_SUP], 1,
       "this is what an application writes when it believes it is turning UTF-8 on, and the census is the "
       "only place that can still say so afterwards");

  rc_reset(&g, 20, 4, 0x07);
  put1(&g, "\033(");
  eq_u("mid-designator", (unsigned)g.mode, RC_ESC_INTERIM, "waiting for the set byte");
  put1(&g, "0");
  eq_u("charset state after a split designator", (unsigned)g.charset, 1, "resumed");
  putu(&g, &q, 1);
  eq_u("split designator took effect", RC_CELLS(&g, 0)[0].ch, 0x2500, "");
}

/* OSC 4 / 10 / 11 -- the palette (I34). The grammar is MSFT's because MSFT implements it and ConEmu does
 * nothing, and the two tables are the whole point of the family: an index below 16 is the colour of a
 * *console attribute* (it goes to the console and to the fold), one at or above 16 is only the RGB a
 * 256-colour index means, because a 4-bit attribute has nowhere else to put it. What a host grid can witness
 * is the model side; that the console really changed, and that it came back on close(), is the live leg.
 * Every expectation below is in COLORREF order (0x00BBGGRR), which is what this tree's colour domain is --
 * `RgbMap[17] == 0x5f0000` is xterm's 00005f read that way, and SGR 38;2 packs `(b<<16)|(g<<8)|r`. */
static void gm_palette()
{
  static RcGrid g;

  /* The default attribute is an attribute; the pen has to come back as the same colour the reset filled
     the cells with. Attribute 1 is FORE_BLUE and ClrMap[1] is 4, so before the conversion at the seed sites
     a blue-default profile got a red pen and a blue screen out of one rc_reset. */
  rc_reset(&g, 20, 4, 0x01);
  eq_u("a blue-default profile keeps a blue pen", g.attr & 0x0F, 1,
       "the cells the same reset filled are attribute 1; the pen must not be 4");
  eq_u("and the fill agrees", RC_CELLS(&g, 0)[0].attr & 0x0F, 1, "");
  put(&g, "Z");
  eq_u("a character written into it lands blue", RC_CELLS(&g, 0)[0].attr & 0x0F, 1, "");
  rc_reset(&g, 20, 4, 0x01);
  put(&g, "\033[37mX\033[m");
  eq_u("SGR 0 after an explicit colour returns to the default, not to its double conversion",
       (unsigned)(g.attr & 0x0F), 1, "37 makes the pen white; the reset must land on 1, not on ClrMap[1]");
  put(&g, "\033[37m\033[39m");
  eq_u("and SGR 39 says the same", (unsigned)(g.attr & 0x0F), 1, "");

  /* The spec forms. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]4;1;rgb:11/22/33\007");
  eq_u("rgb:r/g/b lands in the attribute table", g.pal16[1], 0x00332211, "COLORREF: red 0x11, green 0x22, blue 0x33");
  eq_u("and asks for exactly that entry to be written", g.palTouched, 1u << 1, "");
  put(&g, "\033]4;2;#4080c0\007");
  eq_u("#RRGGBB parses", g.pal16[2], 0x00C08040, "");
  put(&g, "\033]4;3;#0f0\007");
  eq_u("#RGB replicates the nibble", g.pal16[3], 0x0000FF00,
       "MSFT's sharp-form multiplier would say 0xF0 here while its rgb: form says 0xFF; this uses one rule");
  put(&g, "\033]4;4;#0000ffff0000\007");
  eq_u("#RRRRGGGGBBBB scales down", g.pal16[4], 0x0000FF00, "");
  put(&g, "\033]4;5;rgb:f/ff/0f0\007");
  eq_u("the rgb: form allows unequal widths", g.pal16[5], 0x000FFFFF, "f->0xFF, ff->0xFF, 0f0->0x0F");

  /* What is not a colour, and what a refusal costs. */
  put(&g, "\033]4;6;orange\007");
  eq_u("a name is counted", g.nUnsupported[RC_UN_OSC_OTHER], 1, "I34 says why this build does not resolve names");
  eq_u("and stores nothing", g.palTouched, (1u << 1) | (1u << 2) | (1u << 3) | (1u << 4) | (1u << 5),
       "bits 1..5, and not 6");
  put(&g, "\033]4;300;#ffffff\007");
  eq_u("an index past the table is counted too", g.nUnsupported[RC_UN_OSC_OTHER], 2, "");
  put(&g, "\033]4;7;#12\007");
  eq_u("a sharp form with a bad width is counted", g.nUnsupported[RC_UN_OSC_OTHER], 3, "");
  put(&g, "\033]4;7;rgb:1/2\007");
  eq_u("a truncated rgb: form is counted", g.nUnsupported[RC_UN_OSC_OTHER], 4, "");

  /* Two ranges, two tables. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]4;196;rgb:ff/00/00\007");
  eq_u("index 196 goes into the 256 table", g.palette[196], 0x000000FFu, "pure red as a COLORREF");
  eq_u("and asks the console for nothing", g.palTouched, 0, "there is no console slot 196");
  eq_u("the attribute table is untouched", g.pal16[4], 0x00000080u, "attribute 4 is still the standard dark red");

  /* The fold follows the table it was given -- the reason the model owns a palette at all. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[38;2;18;52;86mX");
  const unsigned before = g.attr & 0xF;
  put(&g, "\033]4;9;rgb:12/34/56\007");
  put(&g, "\033[38;2;18;52;86mY");
  eq_u("the same colour now folds to the entry that was made for it", g.attr & 0xF, 9,
       "an exact match in the table the application just wrote");
  eq_u("and that fold was elsewhere before the change", before, 1,
       "the bucket logic answers 1 for 0x12/0x34/0x56; the exact match answers 9 only after the write");

  /* Queries arm through the same queue as DSR and DECRQM. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]4;0;rgb:01/02/03;1;?\007");
  eq_u("a set and an ask in one payload arm one reply", (unsigned)rc_report_pending(&g), 1, "");
  eq_u("the pair before the ask was applied", g.pal16[0], 0x00030201u, "");
  {
    struct RcReportItem it;
    eq_u("its kind is OSC", (unsigned)rc_report_take(&g, &it), (unsigned)RC_REP_OSC, "");
    eq_u("it names the resource", (unsigned)it.mode, 4, "");
    eq_u("and the index that asked", (unsigned)it.y, 1, "not 0: that one was set, not asked about");
    eq_u("with the colour the console will show", it.status, g.pal16[1], "");
  }

  /* OSC 10/11: a default is an index on this console, so an RGB is folded and the *effective* colour is
     what a query answers with. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]10;rgb:80/00/00\007");
  eq_u("the default foreground moved to the nearest index", g.defAttr & 0xF, 4,
       "the table is indexed by console attribute, and 4 is FORE_RED");
  eq_u("and the console's own attribute is not", g.attr & 0xF, 7,
       "on this console that field *is* the pen, so an OSC 10 cannot be pushed at it (I34)");
  eq_u("the background nibble did not move", (g.defAttr >> 4) & 0xF, 0, "");
  put(&g, "\033]11;rgb:00/ff/00\007");
  eq_u("the default background follows the same rule", (g.defAttr >> 4) & 0xF, 10, "");
  put(&g, "\033]11;?\007");
  {
    struct RcReportItem it;
    rc_report_take(&g, &it);
    eq_u("a default query carries no index", (unsigned)it.y, 0, "only `4` names one");
    eq_u("and answers with the colour of the index chosen", it.status, g.pal16[10],
         "the effective colour, not the RGB that was asked for (I34)");
  }
  put(&g, "\033]10;red;green\007");
  eq_u("MSFT walks resources forward one per field, and names fail on the way",
       g.nUnsupported[RC_UN_OSC_OTHER], 2, "");

  /* Resets. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]4;3;rgb:ff/ff/ff\007\033]104\007");
  eq_u("104 with no payload restores the standard table", g.pal16[3], 0x00808000u, "");
  eq_u("and marks all sixteen for the console", g.palTouched, 0xFFFFu,
       "restoring is a write like any other, and the console keeps the user's other entries");
  put(&g, "\033]4;4;rgb:ff/ff/ff\007\033]4;5;rgb:ff/ff/ff\007\033]104;4\007");
  eq_u("104 with an index restores that one", g.pal16[4], 0x00000080u, "");
  eq_u("and leaves its neighbour set", g.pal16[5], 0x00FFFFFFu, "");
  put(&g, "\033]104;7;x;8\007");
  eq_u("104 stops at the first index it cannot parse", g.nUnsupported[RC_UN_OSC_OTHER], 1,
       "MSFT:846 records that this is xterm's choice over VTE's");
  eq_u("so the index after the junk was never reached", g.pal16[8], 0x00808080u, "still the standard grey");

  /* 110/111, and the payload that never closed. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]10;rgb:80/00/00\007\033]110\007");
  eq_u("110 with an empty payload restores the default foreground", g.defAttr & 0xF, 7,
       "the seed the handle found, not a guess at a colour");
  put(&g, "\033]10;rgb:80/00/00\007\033]110;1\007");
  eq_u("110 with a payload counts and does nothing", g.nUnsupported[RC_UN_OSC_OTHER], 1,
       "MSFT:855-866 notes xterm and VTE disagree here");
  eq_u("and the default stays where it was", g.defAttr & 0xF, 4, "the same FORE_RED the write chose");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]4;1;rgb:00/00/00");
  put(&g, "\033[5n");
  eq_u("an unterminated palette write counts and applies nothing", g.nUnsupported[RC_UN_OSC_OTHER], 1,
       "the same rule titles and 133 use");
  eq_u("nothing was touched", g.palTouched, 0, "");
  eq_u("and the abandoned sequence still left the queue alone", (unsigned)rc_report_pending(&g), 1,
       "the `CSI 5n` that restarted the parser is its own question");
}

/* The OSC 9 safe subset (T7). ConEmu's private dialect is where the #687 remote-code report lives, so the
 * gate has two jobs: prove the three subcommands MSFT acts on really do what MSFT does, and prove that
 * everything else -- including the shapes that look one byte away from acting -- leaves nothing stored. */
static void gm_osc9()
{
  static RcGrid g;

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]9;4;1;50\007");
  eq_u("9;4 stores the state", (unsigned)g.taskbarState, 1, "");
  eq_u("and the progress", (unsigned)g.taskbarProgress, 50, "");
  eq_u("and says it saw one", (unsigned)g.taskbarSeen, 1, "state 0 is an instruction, not an absence");
  eq_u("with nothing counted", g.nUnsupported[RC_UN_OSC_PRIV], 0, "");

  put(&g, "\033]9;4;2;150\007");
  eq_u("progress past 100 clamps", (unsigned)g.taskbarProgress, 100,
       "MSFT :3601-3605: a program that means 750% means the bar is full");
  eq_u("and the state came along", (unsigned)g.taskbarState, 2, "");

  put(&g, "\033]9;4;9;50\007");
  eq_u("a state past 4 is refused outright", (unsigned)g.taskbarState, 2,
       "MSFT returns without applying (:3596-3600) -- the old value stays");
  eq_u("and counted as the private family it is", g.nUnsupported[RC_UN_OSC_PRIV], 1, "");

  put(&g, "\033]9;4\007");
  eq_u("bare 9;4 is the remove form", (unsigned)g.taskbarState, 0, "");
  eq_u("with the progress cleared too", (unsigned)g.taskbarProgress, 0, "");
  put(&g, "\033]9;4;3;25\007\033]9;4;\007");
  eq_u("an empty state field is not an error", (unsigned)g.taskbarState, 0,
       "MSFT only bails on a field that is both unparseable and non-empty (:3581-3584)");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]9;9;\"D:/\"\007");
  eq_u("9;9 strips one pair of quotes", (unsigned)g.nCwd, 3, "ConEmu's documented spelling");
  eq_u("first unit", g.cwd[0], L'D', "");
  eq_u("second unit", g.cwd[1], L':', "");
  eq_u("third unit", g.cwd[2], L'/', "");
  put(&g, "\033]9;9;/tmp\007");
  eq_u("and an unquoted path is taken anyway", (unsigned)g.nCwd, 4, "MSFT :3616-3621 does the same");
  put(&g, "\033]9;9;C:\001x\007");   /* SOH, not BEL: \a would have ended the OSC */
  eq_u("a control character in the path refuses it", (unsigned)g.nCwd, 4, "still /tmp");
  eq_u("counted", g.nUnsupported[RC_UN_OSC_PRIV], 1, "");
  put(&g, "\033]9;9;\"a\"b\"\007");
  eq_u("and an inner quote survives the strip only to fail legality", (unsigned)g.nCwd, 4,
       "the pair comes off, then `a\"b` is rejected -- til::is_legal_path's own test case");
  put(&g, "\033]9;9;\007");
  eq_u("an empty path stores nothing", (unsigned)g.nCwd, 4, "");
  eq_u("and counts -- the third refusal in a row", g.nUnsupported[RC_UN_OSC_PRIV], 3,
       "the control character, the inner quote and the empty field each vote once");

  /* 9;12 must be the *same* path as 133;B, not a copy of it: compare every field one of them can move. */
  static RcGrid a, b;
  rc_reset(&a, 20, 4, 0x07);
  rc_reset(&b, 20, 4, 0x07);
  put(&a, "abc\033]133;B\007");
  put(&b, "abc\033]9;12\007");
  eq_u("9;12 marks the row the way 133;B does", (unsigned)RC_ST(&b, a.cy).mark, (unsigned)RC_ST(&a, a.cy).mark, "");
  eq_u("with the same content claim", (unsigned)b.semanticContent, (unsigned)a.semanticContent,
       "RC_SC_INPUT, which is what makes the next line a command line");
  eq_u("and the same end-of-line rule", (unsigned)b.semanticClearEol, (unsigned)a.semanticClearEol, "");
  eq_u("cursor where it was", (unsigned)b.cy, (unsigned)a.cy, "neither form moves the cursor");
  eq_u("and nothing counted for 9;12", b.nUnsupported[RC_UN_OSC_PRIV], 0, "");

  /* The dangerous half of the family, and the shapes that must not reach it. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]9;7;calc.exe\007");
  eq_u("9;7 counts and stores nothing", g.nUnsupported[RC_UN_OSC_PRIV], 1,
       "the #687 shape: the answer is that no path through this file runs it");
  eq_u("no directory", (unsigned)g.nCwd, 0, "");
  eq_u("no taskbar", (unsigned)g.taskbarSeen, 0, "");
  put(&g, "\033]9;2;boom\007\033]9;3;E=1\007\033]9;1;5\007\033]9;6;GuiMacro(\"x\")\007");
  eq_u("MessageBox, set-env, sleep and GuiMacro all just count", g.nUnsupported[RC_UN_OSC_PRIV], 5, "");
  put(&g, "\033]9\007");
  eq_u("a bare 9 with no subcommand counts", g.nUnsupported[RC_UN_OSC_PRIV], 6, "");
  put(&g, "\033]9;x\007");
  eq_u("and so does an unparseable subcommand", g.nUnsupported[RC_UN_OSC_PRIV], 7, "");
  put(&g, "\033]9;4;1;60");
  eq_u("an unterminated 9;4 has applied nothing yet", (unsigned)g.taskbarProgress, 0,
       "the payload is still open, so there is nothing to count either");
  eq_u("and has not counted yet", g.nUnsupported[RC_UN_OSC_PRIV], 7, "");
  put(&g, "\033[\007");                          /* abandon and restart: the OSC closes as unterminated */
  eq_u("the abandoned 9;4 counts once", g.nUnsupported[RC_UN_OSC_PRIV], 8,
       "same rule as titles and 133: a half-read command is not a claim, but it is a record");
  eq_u("and still applies nothing", (unsigned)g.taskbarProgress, 0, "");
  put(&g, "\033P9;7;calc.exe\033\\\033]9;12\007");
  eq_u("a DCS wearing the same digits is the DCS counter", g.nUnsupported[RC_UN_DCS], 1,
       "osc_finish separates the framings before any subcommand is read");
  eq_u("while the real 9;12 acted", (unsigned)g.semanticContent, RC_SC_INPUT, "");
  eq_u("and the frame is still trusted", (unsigned)g.modelSuspect, 0,
       "a private OSC that was refused must not poison the picture, only be counted");
}

/* The clipboard family's own helper: the decoder reads the UTF-16 sink, and a gate that wants to hand it
   "QQ==" builds the units one at a time rather than pretending a char* is one. */
static int b64s(const char *s, uint8_t *out, int cap)
{
  uint16_t u[64];
  int n = 0;
  while (s[n] && n < 64) { u[n] = (uint16_t)(unsigned char)s[n]; n++; }
  return rc_b64_decode(u, n, out, cap);
}

/* I36: OSC 52. The decoder is tested as a unit because a refusal that says only "the sequence was rejected"
 * cannot tell a rollout whether the grammar, the policy or the base64 rejected it -- three different things
 * to fix in three different places. The family is tested through the parser, which is the only way the
 * policy and the counters can be seen at all. */
static void gm_clipboard()
{
  static RcGrid g;
  uint8_t out[64];

  /* ---- the decoder ---- */
  eq_u("one byte, padded", (unsigned)b64s("QQ==", out, sizeof out), 1, "");
  eq_u("and it is the byte", (unsigned)out[0], (unsigned)'A', "");
  eq_u("two bytes", (unsigned)b64s("QUI=", out, sizeof out), 2, "");
  eq_u("three bytes", (unsigned)b64s("YWJj", out, sizeof out), 3, "");
  eq_u("which is abc", (unsigned)out[0] * 65536u + (unsigned)out[1] * 256u + (unsigned)out[2],
       (unsigned)'a' * 65536u + (unsigned)'b' * 256u + (unsigned)'c', "");
  eq_u("an unpadded tail decodes", (unsigned)b64s("SGVsbG8", out, sizeof out), 5,
       "ghostty decodes with .optional padding; senders that strip it are the same bytes");
  eq_u("and to the right text", (unsigned)out[0], (unsigned)'H', "");
  eq_u("empty is zero, not an error", (unsigned)b64s("", out, sizeof out), 0,
       "which is a request to clear the clipboard, not the absence of a request");
  eq_u("one character encodes nothing", (unsigned)(b64s("Q", out, sizeof out) == -1), 1, "");
  eq_u("a lone pad after a full group", (unsigned)(b64s("QQ=", out, sizeof out) == -1), 1, "");
  eq_u("three pads", (unsigned)(b64s("A===", out, sizeof out) == -1), 1, "");
  eq_u("padding must be a suffix", (unsigned)(b64s("QQ=A", out, sizeof out) == -1), 1, "");
  eq_u("a non-canonical tail is refused", (unsigned)(b64s("QR==", out, sizeof out) == -1), 1,
       "'Q' and 'R' carry 12 bits for one byte, and the 4 left over are not zero (RFC 4648 3.5)");
  eq_u("a space inside is refused", (unsigned)(b64s("Y WJ", out, sizeof out) == -1), 1,
       "so a payload wrapped over lines is refused whole and the census says so, instead of arriving joined");
  eq_u("a newline inside is refused", (unsigned)(b64s("YW\nj", out, sizeof out) == -1), 1, "");
  eq_u("any byte outside the alphabet is refused", (unsigned)(b64s("YW*j", out, sizeof out) == -1), 1, "");
  eq_u("+ and / are the 62nd and 63rd", (unsigned)b64s("++//", out, sizeof out), 3, "");
  eq_u("over the caller's cap refuses the whole payload",
       (unsigned)(b64s("YWJjYWJj", out, 3) == -1), 1, "no half-written buffer exists to be mistaken for a paste");

  /* ---- the family, through the parser ---- */
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]52;c;YWJj\007");
  eq_u("with the policy off, one request is refused", g.nUnsupported[RC_UN_OSC_CLIP], 1,
       "the default is the state a session gets without having asked, and asking is not something a byte stream can do");
  eq_u("and it is not also an unknown OSC", g.nUnsupported[RC_UN_OSC_OTHER], 0,
       "the family owns code 52 now, so `other osc` would double-count one sequence");
  eq_u("nothing is armed", (unsigned)rc_clip_pending(&g), 0, "");
  eq_u("a refusal by policy is not a decode failure", (unsigned)g.nClipBad, 0,
       "the report has to be able to say which of the two happened");

  rc_set_clipboard_policy(RC_CLIP_ALLOW);
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]52;c;YWJj\007");
  eq_u("armed one write", (unsigned)rc_clip_pending(&g), 1, "");
  eq_u("and refused nothing", g.nUnsupported[RC_UN_OSC_CLIP], 0, "");
  {
    uint8_t raw[8];
    const int n = rc_clip_take(&g, raw, (int)sizeof raw);
    eq_u("the bytes are what the base64 said", (unsigned)n, 3, "");
    eq_u("abc", (unsigned)raw[0] * 65536u + (unsigned)raw[1] * 256u + (unsigned)raw[2],
         (unsigned)'a' * 65536u + (unsigned)'b' * 256u + (unsigned)'c', "");
  }
  eq_u("taking it clears the request", (unsigned)rc_clip_pending(&g), 0,
       "one request, one write: the painter cannot apply the same paste twice");

  /* The empty selection field is the clipboard (ghostty's own grammar); any other letter names a target
     Windows has no place for, and folding it onto the clipboard would answer a different question. */
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]52;;YWJj\007");
  eq_u("an empty selection means the clipboard", (unsigned)rc_clip_pending(&g), 1, "");
  /* `52;;` with nothing after the second ';' is not a missing payload -- it is the request to clear the
     register. That makes it the one case where "armed" and "zero bytes" are both true, and the case a
     painter gets wrong by reading 0 as failure (which is exactly what MultiByteToWideChar returns for an
     empty input, so the two look alike downstream). */
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]52;;\007");
  eq_u("an empty payload arms a clear", (unsigned)rc_clip_pending(&g), 1,
       "the request is the whole point of the payload, and an absent one says something");
  eq_u("with nothing to write", (unsigned)g.nClip, 0, "");
  eq_u("and no refusal of any kind", (unsigned)(g.nClipBad + g.nClipSel + g.nClipRead
                                                + g.nUnsupported[RC_UN_OSC_CLIP]), 0, "");
  eq_u("counted as one request", (unsigned)g.nClipSet, 1, "");
  {
    uint8_t raw[8];
    raw[0] = 0x7f;
    eq_u("which the painter can take", (unsigned)rc_clip_take(&g, raw, (int)sizeof raw), 0, "");
    eq_u("and the request is consumed", (unsigned)rc_clip_pending(&g), 0, "");
  }
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]52;p;YWJj\007");
  eq_u("`p` is refused, not folded", (unsigned)rc_clip_pending(&g), 0, "");
  eq_u("under its own counter", (unsigned)g.nClipSel, 1, "");
  eq_u("one census vote", g.nUnsupported[RC_UN_OSC_CLIP], 1, "");
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]52;cp;YWJj\007");
  eq_u("a two-letter selection is not a thing", (unsigned)g.nClipSel, 1, "");

  /* A read is refused whatever the policy says: the reply would put the user's clipboard into the input
     stream, and this library has no window to ask permission in. */
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]52;c;?\007\033]52;;?\007");
  eq_u("two reads, two counts", (unsigned)g.nClipRead, 2, "");
  eq_u("nothing armed", (unsigned)rc_clip_pending(&g), 0, "even with the write policy on");
  eq_u("and no reply was queued", (unsigned)rc_report_pending(&g), 0,
       "answering is the whole thing being refused");

  /* Grammar refusals, each under the decode counter. */
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]52;c\007\033]52;YWJj\007");
  eq_u("no selection field, twice", (unsigned)g.nClipBad, 2,
       "`52;c` has no payload field and `52;base64` has no selection field");
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]52;c;YW*j\007");
  eq_u("a bad encoding is a decode failure", (unsigned)g.nClipBad, 1, "");
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]52;c;YWJj\033[0mq");   /* the ESC abandons it; [0m is a sequence of its own */
  eq_u("an abandoned OSC is framing, not a clipboard refusal", g.nUnsupported[RC_UN_OSC_OTHER], 1,
       "the rule I21 states for every family: never applied, and counted where it belongs");
  eq_u("and the clipboard counter stays clean", g.nUnsupported[RC_UN_OSC_CLIP], 0,
       "it never reached a terminator, so it never asked for anything");
  eq_u("the byte after the ESC is re-examined", (unsigned)RC_CELLS(&g, 0)[0].ch, (unsigned)'q',
       "deviation #1: an ESC that abandons an OSC is an introducer again, not a swallowed byte");

  /* A NUL cannot be stored in a NUL-terminated string, so the request is refused rather than truncated. */
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]52;c;QQAg\007");       /* 'A', NUL, ' ' */
  eq_u("a decoded NUL refuses the whole payload", (unsigned)g.nClipBad, 1,
       "storing the prefix would hand the user half a paste with no way to know");
  eq_u("nothing armed", (unsigned)rc_clip_pending(&g), 0, "");

  /* Over the cap: refused as a unit, under the decode counter, whatever the sink thought. */
  {
    static uint16_t big[RC_OSC_MAX];
    int i, k = 0;
    big[k++] = 0x1B; big[k++] = ']'; big[k++] = '5'; big[k++] = '2'; big[k++] = ';';
    big[k++] = 'c'; big[k++] = ';';
    for (i = 0; i < RC_CLIP_ENC_MAX + 8; i++) big[k++] = 'a';   /* well-formed, and long enough that the
                                                                   cap is the thing that says no */
    big[k++] = 0x07;
    rc_reset(&g, 20, 3, 0x07);
    rc_feed(&g, big, k);
    eq_u("over the cap is refused", (unsigned)g.nClipBad, 1, "");
    eq_u("and nothing armed", (unsigned)rc_clip_pending(&g), 0, "");
    eq_u("the sequence was still consumed", (unsigned)g.mode, (unsigned)RC_GROUND, "");
  }
  rc_set_clipboard_policy(RC_CLIP_DENY);   /* the default, restored for every case after this one */
}

/* The queue a query goes into, which is the whole of what the model can say about a reply: RenderJni's
 * drain turns an entry into key events, and everything it needs to say the right thing is here. Two rules
 * are worth pinning against a grid rather than trusting a live `tput rows`: the entry carries the cursor as
 * it stood *when the question was read* (a later move must not change the answer), and the queue is FIFO
 * with a refusal at the far end (an evicted older reply hangs a program already blocked on its first read). */

static void gm_reports()
{
  static RcGrid g;
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[5n");
  eq_u("a status request arms one reply", (unsigned)rc_report_pending(&g), 1, "");
  eq_u("and is not counted as one we refuse", g.nUnsupported[RC_UN_REPORT], 0, "");
  int ry = -1, rx = -1;
  eq_u("its kind", (unsigned)take_xy(&g, &ry, &rx), (unsigned)RC_REP_DSR, "");
  eq_u("and it armed nothing else", (unsigned)rc_report_pending(&g), 0, "");

  /* The snapshot, which is the subtle half. `CSI 6n` then a move asks about where the cursor was; a drain
     that reads g->cy at flush time would answer the move instead, which is a fact about a screen the asker
     never saw. */
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[3;5H\033[6n\033[6;2H");
  eq_u("the move did not add a second reply", (unsigned)rc_report_pending(&g), 1, "");
  take_xy(&g, &ry, &rx);
  eq_u("CPR row is the cursor as it stood", (unsigned)ry, 2, "model row, 0-based; the painter adds row0");
  eq_u("CPR column likewise", (unsigned)rx, 4, "");
  eq_u("and the cursor has since moved", (unsigned)g.cy, 5, "the answer must not follow it");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[c\033[>c");
  eq_u("two identity queries, two replies", (unsigned)rc_report_pending(&g), 2, "");
  eq_u("the oldest is the primary", (unsigned)rc_report_take(&g, NULL), (unsigned)RC_REP_DA, "FIFO");
  eq_u("then the secondary", (unsigned)rc_report_take(&g, NULL), (unsigned)RC_REP_DA2, "");
  eq_u("and nothing was refused on the way", g.nUnsupported[RC_UN_REPORT], 0, "both were answered");
  put(&g, "\033[1c");
  eq_u("counted", g.nUnsupported[RC_UN_REPORT], 1, "VT52 and friends are not answered");
  eq_u("and armed nothing", (unsigned)rc_report_pending(&g), 0, "");
  put(&g, "\033[t");
  eq_u("window manipulation is counted too", g.nUnsupported[RC_UN_REPORT], 2, "");

  /* DECRQM. ConEmu has no such reply -- every `p` it does not recognise goes to DumpUnknownEscape
     (Ansi.cpp:3650-3653) -- so the numbers below are the VT500 ones (1 reset, 2 set, 3 permanently reset,
     4 permanently set) and only the first two ever appear: 3 and 4 claim a permanence this model cannot
     keep, and the block after this one is the evidence that the two readers do not even agree on what they
     mean. A mode the table does not name is counted and left unanswered rather than guessed at.
     The snapshot is the half that needed the queue entry to grow: the answer belongs to the moment the
     request was read, so a chunk that turns the mode off afterwards still gets "it was on". */
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?2026h\033[?2026$p\033[?2026l");
  eq_u("one request, one reply", (unsigned)rc_report_pending(&g), 1, "neither the DECSET nor the RESET speaks");
  {
    struct RcReportItem it;
    eq_u("its kind is DECRPM", (unsigned)rc_report_take(&g, &it), (unsigned)RC_REP_DECRPM, "");
    eq_u("the reply names the mode that was asked", (unsigned)it.mode, 2026,
         "jline4 reads the number back out of the reply, so a reply about the wrong id is worse than none");
    eq_u("and the state it had when the request was read", (unsigned)it.status, 2,
         "the `?2026l` that followed is a later fact, exactly as a cursor move after a CPR is");
  }
  eq_u("answering a query votes in no census", g.nUnsupported[RC_UN_MODE], 0, "");

  /* The two ids of jline4's probe batch that this build holds no state for. They are the ones a permanent
     number was written for, and they are the reason no number is sent at all: DEC and xterm read DECRPM 4 as
     "permanently set" while jline4 documents 4 as "permanently reset" (AbstractTerminal.java:663-667), so
     either spelling lies to one of the two -- and `parseDecrpm` already reaches NOT_SUPPORTED for a mode it
     finds no reply for (:677-689), which is the verdict both of them should be given. */
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?2027$p\033[?2048$p");
  eq_u("reflow and in-band resize answer nothing", (unsigned)rc_report_pending(&g), 0,
       "2048 is the resize notification, not the paste mode: this build wraps at cells and reports size out of band");
  eq_u("and each votes for the mode it asked about", g.nUnsupported[RC_UN_MODE], 2,
       "the count its DECSET already costs, so `h` and `$p` cannot disagree about who owns a mode");

  /* The order the answered ids leave in. jline4 writes its batch as one string and looks each reply up by
     number, so the one failure this queue must not have is a reply about the wrong id. */
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?25$p\033[?2026$p\033[?1049$p");
  {
    struct RcReportItem first, second, third;
    eq_u("three requests queued", (unsigned)rc_report_pending(&g), 3, "");
    rc_report_take(&g, &first);
    rc_report_take(&g, &second);
    rc_report_take(&g, &third);
    eq_u("first out is first in", (unsigned)first.mode, 25, "");
    eq_u("the middle keeps its own answer", (unsigned)second.mode, 2026, "");
    eq_u("and so does the tail", (unsigned)third.mode, 1049, "");
    eq_u("a region nobody opened is reported as reset", (unsigned)second.status, 1,
         "1, not a permanent number: the mode is understood and currently off, and jline4 reads both 1 and 2 as SUPPORTED (:685)");
  }

  /* Modes with a real state behind them, read through the same table. */
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?25$p");
  {
    struct RcReportItem it;
    rc_report_take(&g, &it);
    eq_u("a fresh grid reports the cursor visible", (unsigned)it.status, 2, "");
  }
  put(&g, "\033[?25l\033[?25$p");
  {
    struct RcReportItem it;
    rc_report_take(&g, &it);
    eq_u("and `?25l` is a fact the reply carries", (unsigned)it.status, 1, "");
  }
  put(&g, "\033[?1049h\033[?1049$p\033[?47$p");
  {
    struct RcReportItem alt, legacy;
    rc_report_take(&g, &alt);
    rc_report_take(&g, &legacy);
    eq_u("1049 on the alternate screen answers set", (unsigned)alt.status, 2, "");
    eq_u("and 47 is the same slot, so it cannot disagree", (unsigned)legacy.status, 2,
         "three spellings, one bit (I14): a reply that contradicted the DECSET that moved it would be the lie");
  }

  /* What is *not* a request. Each of these is a spelling a program can send, and each has to leave a number
     rather than a reply it cannot be held to. */
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?999$p");
  eq_u("a mode neither leg models answers nothing", (unsigned)rc_report_pending(&g), 0,
       "and that is a decision, not a gap: see the `?6n` ruling this one follows");
  eq_u("counted as the mode it asked about", g.nUnsupported[RC_UN_MODE], 1, "not SUP: the `$` says what it was");
  put(&g, "\033[2026$p");
  eq_u("the non-private request is counted too", g.nUnsupported[RC_UN_MODE], 2,
       "ANSI 2026 does not exist; the probe always carries the `?`");
  eq_u("and armed nothing", (unsigned)rc_report_pending(&g), 0, "");
  put(&g, "\033[?1;2$p");
  eq_u("a request with two parameters is not one", g.nUnsupported[RC_UN_MODE], 3, "");
  put(&g, "\033[?$p");
  eq_u("and one with no parameter is not either", g.nUnsupported[RC_UN_MODE], 4, "");
  put(&g, "\033[?2026!p");
  eq_u("a different interim with the same final still votes SUP", g.nUnsupported[RC_UN_SUP], 1,
       "`!` is DECSTR's byte, and with a parameter it is nothing at all");
  eq_u("while the census of modes did not move", g.nUnsupported[RC_UN_MODE], 4, "");

  /* The limit, and the direction it refuses in. */
  rc_reset(&g, 20, 6, 0x07);
  for (int i = 0; i < RC_REPORT_MAX + 3; i++) put(&g, "\033[6n");
  eq_u("the queue holds its stated depth", (unsigned)rc_report_pending(&g), (unsigned)RC_REPORT_MAX, "");
  eq_u("and says so, three times", g.nReportFull, 3, "a refusal, not an eviction");
  eq_u("the first entry is still the first asked", (unsigned)take_xy(&g, &ry, &rx), (unsigned)RC_REP_CPR, "");
  eq_u("at the position it was asked from", (unsigned)ry, 0, "nine identical queries, no cursor moves");
  rc_report_result(&g, 1);
  eq_u("a reply the console took is counted once", g.nReportOk, 1, "");
  rc_report_result(&g, 0);                         /* no take above this one: what is pinned is the separation */
  eq_u("and a failed write is counted separately", g.nReportFail, 1, "so the two are never confused");

  /* A reset drops the queue with everything else it owns: the bytes that asked are gone from this model,
     and a re-adopt cannot answer a question the rebuilt grid never saw. */
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[5n");
  eq_u("armed before the reset", (unsigned)rc_report_pending(&g), 1, "");
  rc_reset(&g, 20, 6, 0x07);
  eq_u("gone after it", (unsigned)rc_report_pending(&g), 0, "");
}

static void gm_dropped()
{
  static RcGrid g;
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[?31mX");
  eq_u("CSI ? drops the SGR", g.attr, 0x07, "Pvt set (Ansi.cpp:3494)");
  eq_text(&g, 0, 1, "X", "still one cell");

  /* Re-baselined by #78. This leg used to pin the drop: ConEmu appends ':' to the same Pvt buffer it puts
     '?' in (Ansi.cpp:1788) and the SGR arm tests Pvt (:3494), so the whole sequence went away -- and that was
     recorded here as parity. Parity with a parser this library no longer shares the stream with is not a floor
     (the #60 and #61 rulings, and I38's tab refusal said the same thing about a different byte), and both
     reference terminals parse the form. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[38:2:1:2:3mX");
  eq_u("the colon form carries its colour", (unsigned)(g.attr != 0x07), 1,
       "24-bit, folded by the same path the semicolon form takes");
  eq_u("and the text it arrived with is still written", RC_CELLS(&g, 0)[0].ch, 'X', "");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[53;31mX");
  eq_u("an unknown parameter is skipped, the loop carries on", g.attr, 0x04, "53 then 31 still red");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[38;5mX");
  eq_u("a truncated 38;5 applies nothing", g.attr, 0x07, "the leftover args fall through the switch");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[4mX");
  eq_u("underline painted", g.attr, 0x8007, "");
  put(&g, "\033[mY");
  eq_u("bare CSI m resets", g.attr, 0x07, "an assumption, not measured parity: nothing in this build emits it");

  /* CAN aborts the open sequence and the tail is ordinary text -- what ConEmu does too, and what
     keeps a stray control byte from eating the rest of a line. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[3\030""31m");
  eq_text(&g, 0, 3, "31m", "CAN abandons the CSI, the tail is painted as text");
  eq_u("CAN leaves attr", g.attr, 0x07, "no colour applied");

  /* SS2/SS3 consume the introducer only (esc_end counts 1 for the byte after it), so the graphic
     byte must still be painted. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033NX");
  eq_text(&g, 0, 1, "X", "ESC N leaves the next byte to the text path");
  eq_u("ESC N cells", g.nCells, 1, "");
  rc_reset(&g, 20, 4, 0x07);
  put1(&g, "\033O");
  eq_u("SS3 ends in ground", (unsigned)g.mode, RC_GROUND, "introducer only");
  put(&g, "Y");
  eq_text(&g, 0, 1, "Y", "SS3 painted the shifted byte");
}

/* One member of the unsupported-sequence tally. gm_wrap_suspect names four of them in six lines, where
   spelling the array out each time would hide the point of the comparison. */
static unsigned un(const RcGrid *g, enum RcUnsupported which)
{
  return which < RC_UN_MAX ? (unsigned)g->nUnsupported[which] : 0u;
}

static void gm_wrap_suspect()
{
  /* S5: why a row's line continued. The two reasons are conhost's own two bits, and a consumer that joins
     rows for copy or export reads them differently -- a padded row's content is complete, a forced row's
     runs into the next one. */
  static RcGrid g;
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "aaaaaaaaaa");
  eq_u("half a row wraps nothing", (unsigned)rc_row_wrap(&g, 0), RC_WRAP_NONE, "");
  put(&g, "bbbbbbbbbb");
  eq_u("a row filled to the margin is forced", (unsigned)rc_row_wrap(&g, 0), RC_WRAP_FORCED, "");
  eq_u("and the cursor is on the next row", (unsigned)g.cy, 1, "");
  put(&g, "cc");
  eq_text(&g, 1, 2, "cc", "the continuation starts at column 0");
  eq_u("which is not itself wrapped", (unsigned)rc_row_wrap(&g, 1), RC_WRAP_NONE, "");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "1234567890123456789");                    /* 19 columns used, one left */
  {
    static const uint16_t hira = 0x3042;
    putu(&g, &hira, 1);                               /* does not fit: the whole glyph moves down */
  }
  eq_u("a glyph moved whole pads the row it left", (unsigned)rc_row_wrap(&g, 0), RC_WRAP_PAD, "");
  eq_u("and the glyph is on the next row, not split", RC_CELLS(&g, 1)[0].ch, 0x3042, "leading half");
  eq_u("with its trailing cell", RC_CELLS(&g, 1)[1].attr & RC_LVB_TRAILING, RC_LVB_TRAILING, "");
  eq_u("padded, not forced, so a copy does not join the rows", (unsigned)rc_row_wrap(&g, 1), RC_WRAP_NONE, "");

  /* An erase that reaches the margin ends the claim: nothing runs off that row any more. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "aaaaaaaaaaaaaaaaaaaa");                     /* 20: forced */
  eq_u("forced by a full row", (unsigned)rc_row_wrap(&g, 0), RC_WRAP_FORCED, "");
  put(&g, "\033[1;11H");
  eq_u("moving the cursor does not undo it", (unsigned)rc_row_wrap(&g, 0), RC_WRAP_FORCED, "");
  put(&g, "\033[K");
  eq_u("erasing to the margin does", (unsigned)rc_row_wrap(&g, 0), RC_WRAP_NONE, "");
  put(&g, "aaaaaaaaaaaaaaaaaaaa");                     /* forced again, cursor on row 1 */
  put(&g, "\033[1;11H\033[5X");                        /* ECH five columns, short of the margin */
  eq_u("erasing short of the margin leaves it standing", (unsigned)rc_row_wrap(&g, 0), RC_WRAP_FORCED, "");

  /* The bit belongs to the content, so every vertical shift carries it. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "aaaaaaaaaaaaaaaaaaaa");                     /* row 0 forced, cursor row 1 */
  put(&g, "bbbbbbbbbbbbbbbbbbbb");                     /* row 1 forced, cursor row 2 */
  put(&g, "ccccccccccccccccccccdddddddddddddddddddd"); /* rows 2 and 3, and one scroll off the bottom */
  eq_text(&g, 0, 4, "bbbb", "the scroll moved the content up");
  eq_u("with its reason", (unsigned)rc_row_wrap(&g, 0), RC_WRAP_FORCED, "");
  eq_u("and the row that came in is not wrapped", (unsigned)rc_row_wrap(&g, 3), RC_WRAP_NONE, "");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "aaaaaaaaaaaaaaaaaaaa");
  put(&g, "\033[1;1H\033[L");                          /* IL at row 0 opens a row and pushes the rest down */
  eq_u("IL shifts the claim down with the rows", (unsigned)rc_row_wrap(&g, 1), RC_WRAP_FORCED, "");
  eq_u("and the row it inserted has none", (unsigned)rc_row_wrap(&g, 0), RC_WRAP_NONE, "");
  put(&g, "\033[1;1H\033[M");                          /* DL at row 0 deletes the blank and pulls it up */
  eq_u("DL carries it up too", (unsigned)rc_row_wrap(&g, 0), RC_WRAP_FORCED, "");

  /* S3: the counters say what we skipped; suspicion says this frame is no longer known. Only a sequence
     with the reach to move a cursor or choose the scrolling rows earns it -- a dropped colour costs a
     whole-window repaint for nothing, and the colon form of SGR is exactly that.
     DECSTBM left this list when `CSI r` became a modelled region (I25, geo_region): the rows it scrolls are
     known, so it neither spends a counter nor doubts the frame. The RC_UN_DECSTBM slot stays, because the
     census the JNI hands back is positional. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[2;4r");
  eq_u("a scroll region is counted nowhere", un(&g, RC_UN_DECSTBM), 0, "the slot is dead but kept in place");
  eq_u("and makes the model suspect nowhere", (unsigned)rc_model_suspect(&g), 0, "its rows are known");
  eq_u("with the region itself live", (unsigned)g.regSet, 1, "");

  /* The alt buffer left this list with it: ?1049 is a switch the model takes rather than a sequence it
     skips, so it moves the screen it is describing *and knows* it moved. geo_alt() checks what that buys. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[?1049h");
  eq_u("the alt switch is not counted as unmodelled", un(&g, RC_UN_ALTBUF), 0, "");
  eq_u("and does not make the model suspect", (unsigned)rc_model_suspect(&g), 0,
       "a repaint of the whole window is enough for a screen the model chose");
  eq_u("it is counted where it belongs", g.nAltSwitch, 1, "one switch taken");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[?1000h");
  eq_u("mouse tracking is counted", un(&g, RC_UN_MOUSE), 1, "");
  eq_u("and moves nothing", (unsigned)rc_model_suspect(&g), 0, "no repaint for a mode the screen never sees");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[38:2:1:2:3mX");
  eq_u("a colon colour this build can name is no vote at all", un(&g, RC_UN_COLON), 0,
       "#78 moved the counter's meaning from \"a sequence with a ':' went past\" to \"an arm of it is not "
       "carried here\"; a count that cannot make that difference says nothing about either");
  eq_u("as colon, not as a mode set", un(&g, RC_UN_MODE), 0, "the two are different decisions");
  eq_u("and paints the text it carried", RC_CELLS(&g, 0)[0].ch, 'X', "only the colour is dropped");
  eq_u("which is not a reason to distrust the frame", (unsigned)rc_model_suspect(&g), 0, "");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]0;t\007");
  eq_u("a title is counted where it belongs", un(&g, RC_UN_OSC_OTHER), 0, "it is acted on, not swallowed");
  eq_u("and sets nothing suspect", (unsigned)rc_model_suspect(&g), 0, "it changes no cell and moves no cursor");
}

static void gm_state_reset()
{
  static RcGrid g;

  /* DECSTR (`CSI ! p`) and RIS (`ESC c`) are two different acts and the difference is everything a
     full-screen application relies on: the soft one puts state back, the hard one owns the screen. MSFT's
     SoftReset (:2984-3020) has no cursor move, no erase and no buffer switch in it -- `UseMainScreenBuffer`
     first appears in HardReset (:3045) -- and ghostty's softReset is the same list. A "reset" that tears the
     alt screen down pushes the program's own display into the user's history and leaves it printing on the
     main screen, which is the worst possible answer to a request to start over. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[?1049h");
  eq_u("the alt screen is live", (unsigned)g.alt, 1, "");
  put(&g, "\033[31mRED");
  put(&g, "\033[1;3r\033[2;7H");
  put(&g, "\033[5 q");                                 /* a shape the reset is not allowed to touch */
  const unsigned scrolled = g.nScrolls;
  put(&g, "\033[!p");
  eq_u("DECSTR leaves the screen it was asked on", (unsigned)g.alt, 1, "");
  eq_text(&g, 0, 3, "RED", "and erases nothing, so the program's display is still there");
  eq_u("its cursor does not move", (unsigned)g.cy, 1, "");
  eq_u("nor its column", (unsigned)g.cx, 6, "");
  eq_u("nothing was pushed into history", (unsigned)(g.nScrolls == scrolled), 1, "");
  eq_u("the rendition is back to normal", (unsigned)(g.attr & 0x0F), 7, "");
  eq_u("the region is put back to the page", (unsigned)g.regSet, 0, "");
  eq_u("the drawing set is unloaded", (unsigned)g.charset, 0,
       "MSFT resets the designations on both resets (:3000), which is the smacs state a shell inherits");
  eq_u("the cursor shape is left alone", (unsigned)g.cursorShape, 5,
       "DECSTR's list has no shape in it, and the application that asked for one is still on this screen");
  put(&g, "\033[8");                                   /* DECRC */
  eq_u("a restore after a soft reset lands where the terminal already was", (unsigned)g.cy, 1,
       "the active buffer's saved state is cleared, not left pointing at a stale row (:3005-3008)");
  eq_u("and no cells moved on the way", RC_CELLS(&g, 0)[0].ch, 'R', "");

  /* RIS is the other act, and the same assertions run backwards. */
  put(&g, "\033c");
  eq_u("RIS leaves the alt screen", (unsigned)g.alt, 0, "");
  eq_u("and homes the cursor", (unsigned)g.cy, 0, "");
  eq_u("having run a viewport of rows up into history", (unsigned)(g.nScrolls > scrolled), 1, "");
  put(&g, "\033(B\033(0");
  eq_u("the charset is loaded by ESC ( 0", (unsigned)g.charset, 1, "");
  put(&g, "\033c");
  eq_u("and RIS drops it", (unsigned)g.charset, 0, "a program that died in graphics mode leaves nothing behind");

  /* A row that a region shift blanked arrives with no memory of the row it replaced. All three of the row's
     own facts have to go: the wrap claim, the semantic mark, and the *column* the mark was made at, which is
     the third field and the one a consumer reads only through rc_mark_col(). ghostty fixed its own version of
     this hole by resetting the row whole -- "fully reset row metadata when recycling row storage",
     PageList.zig:5252 -> Page.zig:1307 -- after which no recycler in that codebase clears some fields and
     forgets others. */
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[2;4r");
  /* `133;P` rather than `133;A`, because `A` starts a fresh line before marking (Terminal.zig:2211-2229, and
     ftcs_fresh_line() here): at column 4 that moves the prompt down a row and, inside this region, scrolls
     it. `P` marks where the cursor stands, which is the state the recycler has to clear. */
  put(&g, "\033[3;5H\033]133;P\007");
  eq_u("the mark is on its row", (unsigned)rc_row_mark(&g, 2), RC_PM_PROMPT, "");
  eq_u("at the column it was made", (unsigned)rc_mark_col(&g, 2), 4, "");
  put(&g, "\033[3;1H\033[1L");
  eq_u("IL inside the region blanks the row", RC_CELLS(&g, 2)[0].ch, ' ', "");
  eq_u("and the blanked row keeps no mark", (unsigned)rc_row_mark(&g, 2), RC_PM_NONE, "");
  eq_u("nor a column for the mark it no longer has", (unsigned)rc_mark_col(&g, 2), 0,
       "a stale column beside RC_PM_NONE is read as 'select from here' by a jump-to-prompt consumer");
  put(&g, "\033[5;5H\033]133;P\007");                   /* below the region, where IL cannot reach */
  eq_u("a row the region refused keeps its own mark", (unsigned)rc_row_mark(&g, 4), RC_PM_PROMPT, "");
  eq_u("and its own column", (unsigned)rc_mark_col(&g, 4), 4, "");

  /* REP replays the last character that *occupied a cell*. A combining mark, a ZWSP or a C1 control claims
     none -- put_cell drops them at `w <= 0` -- so remembering one turns `CSI 3b` into three repetitions of
     nothing. ghostty assigns `previous_char` in its printable arm, after the width==0 branch has already
     returned (Terminal.zig:1469 -> :1515), and that ordering is the whole rule. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "A");
  {
    static const uint16_t acute = 0x0301;
    putu(&g, &acute, 1);
  }
  eq_u("the mark took no cell", (unsigned)g.cx, 1, "");
  eq_u("and is not what a repeat would replay", g.lastUnit, 'A', "the last character written is A");
  put(&g, "\033[3b");
  eq_text(&g, 0, 4, "AAAA", "three repeats of A, not three copies of a mark that draws nothing");
  put(&g, "\033[1;9H");
  put(&g, "\033(0");                                   /* the drawing set: `n` is a box glyph */
  put(&g, "n");
  put(&g, "\033[2b");
  eq_u("the repeat replays the code point, so it is remapped the same way", RC_CELLS(&g, 0)[9].ch,
       RC_CELLS(&g, 0)[8].ch, "a stored glyph instead of a stored letter would print 'n' here");
  eq_u("twice over", RC_CELLS(&g, 0)[10].ch, RC_CELLS(&g, 0)[8].ch, "");
}

static void gm_argcap()
{
  /* ConEmu's ArgV holds 16 and silently drops the surplus; matching that keeps a long parameter list
     from applying a colour the fallback leg would not. */
  static RcGrid g;
  rc_reset(&g, 20, 4, 0x07);
  char seq[128] = "\033[";
  for (int i = 0; i < 16; i++) strcat(seq, "0;");
  strcat(seq, "31m");
  corpus_add(seq);
  putraw(&g, seq);
  eq_u("16th argument kept", (unsigned)g.nArgs, 16, "args 0..15");
  eq_u("surplus argument dropped", g.attr, 0x07, "the 31 never reached the SGR");
  eq_u("and the drop left a number", (unsigned)g.nArgTrunc, 1,
       "#74: the limit is parity with upstream, the silence was not -- without this a caller cannot tell "
       "\"three parameters\" from \"forty and sixteen kept\"");

  char seq2[160] = "\033[";
  for (int i = 0; i < 19; i++) strcat(seq2, "1;");
  strcat(seq2, "H");
  corpus_add(seq2);
  putraw(&g, seq2);
  eq_u("a twentieth parameter is the fourth loss", (unsigned)g.nArgTrunc, 4, "counted per argument");
  eq_u("and the sequence still acted on the first", (unsigned)g.cy, 0, "args[0] is 1, so row 1");
  rc_reset(&g, 20, 4, 0x07);
  eq_u("a reset drops it, like the report counters beside it", (unsigned)g.nArgTrunc, 0,
       "Render.h's rule: nothing that wants to outlive a resize belongs in the grid");
  putraw(&g, "\033[1;2;3H");
  eq_u("a list that fits costs nothing", (unsigned)g.nArgTrunc, 0, "the counter is not a sequence census");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[999999999999mX");
  eq_u("digits saturate", (unsigned)g.args[0], 65535, "deviation #3: no wrap to a small number");
  eq_u("an enormous SGR applies nothing", g.attr, 0x07, "not a code we know");
  eq_u("saturating is not truncating, so nothing was dropped", (unsigned)g.nArgTrunc, 0,
       "the two limits are different acts: one keeps a value, the other loses an argument");

  /* The other two #74 named. Both sequences ask for a count of *cells*, and both had their bound written at
     the arm as an `if (n > ...)` rather than as a limit -- which is how a bound can be right once and wrong in
     the one geometry nobody tried. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "abcdefghij\033[1;6H");                       /* ten cells on row 0, cursor back to column 5 */
  eq_u("setup: the cursor is at column 5", (unsigned)g.cx, 5, "fifteen columns are left");
  put(&g, "\033[999@");
  eq_u("ICH does not move the cursor", (unsigned)g.cx, 5, "its whole act is on the row's tail");
  eq_text(&g, 0, 20, "abcde", "the tail went out past the margin and the rest of the row is the insert");
  put(&g, "\033[999P");
  eq_text(&g, 0, 20, "abcde", "DCH of the same impossible number pulls back what is there and stops");
  put(&g, "\033[1;1Habcdefghijklmnopqr\033[1;20H");
  eq_u("setup: the cursor on the row's last column", (unsigned)g.cx, 19, "one cell left to erase");
  put(&g, "\033[999X");
  eq_text(&g, 0, 19, "abcdefghijklmnopqr", "ECH erases the cell in front of the cursor and reaches no further");
  eq_u("and does not walk off the end", (unsigned)g.cx, 19, "an erase moves nothing");
}

static void echo_eq(const char *what, RcGrid *g, const char *want, const char *ctx)
{
  uint16_t u[RC_SGR_ECHO_MAX];
  const int n = rc_sgr_take(g, u, (int)(sizeof u / sizeof u[0]));
  const int w = (int)strlen(want);
  g_checks++;
  if (n == w)
  {
    int i;
    for (i = 0; i < w; i++) if ((char)(unsigned char)u[i] != want[i]) break;
    if (i == w) return;
    printf("FAIL  %s: bytes differ at %d: got 0x%02X want 0x%02X  {%s}\n", what, i, u[i], want[i], ctx);
  }
  else printf("FAIL  %s: got %d units want %d  {%s}\n", what, n, w, ctx);
  g_fails++;
}

/* The echo is compared byte for byte, and that is the whole point: a canonical re-encode would have to
 * reproduce which colour went through Far3Color's fold -- the rule that was wrong in §27 -- whereas the
 * bytes we captured are by construction what the fallback leg would have read from the stream. */
static void gm_echo(void)
{
  static RcGrid g;
  uint16_t big[RC_SGR_ECHO_MAX];

  rc_reset(&g, 20, 4, 0x07);
  putraw(&g, "\033[31mred\033[0m plain");
  echo_eq("the SGR pairs, verbatim and in order", &g, "\033[31m\033[0m", "text is not echoed");
  eq_u("a take empties the accumulator", (unsigned)rc_sgr_pending(&g), 0, "");
  putraw(&g, "\033[32mg");
  echo_eq("the next chunk accumulates afresh", &g, "\033[32m", "no leftovers");

  rc_reset(&g, 20, 4, 0x07);
  putraw(&g, "\033[1;1H\033[K\033[1;38;5;145m");
  echo_eq("cursor addressing and erase stay out", &g, "\033[1;38;5;145m",
          "replaying a CUP or an EL would move the real cursor");
  putraw(&g, "\033[?31m\033[4:3m");
  echo_eq("a private SGR echoes nothing; a colon SGR that carries something does", &g, "\033[4:3m",
          "Ansi.cpp:3494 drops the '?', and `4:3` really did turn the underscore on -- a fallback leg that "
          "never saw the sequence would show the two paths disagreeing");
  putraw(&g, "\033c");
  echo_eq("RIS resets the attributes too", &g, "\033c", "");
  putraw(&g, "\0337");
  echo_eq("DECSC changes no attribute", &g, "", "");

  /* Split across chunk boundaries is the case the resumable parser exists for; the echo must still come
     out as one whole sequence, or the fallback leg reads half of it as text. */
  rc_reset(&g, 20, 4, 0x07);
  put1(&g, "\033[33m");
  echo_eq("a unit-at-a-time SGR echoes complete", &g, "\033[33m", "");

  /* Sequences we abandon mid-way: the capture restarts with the ESC that reopened the parse, which is
     exactly what our parser applied. */
  rc_reset(&g, 20, 4, 0x07);
  putraw(&g, "\033]0;title\033[31mX");
  echo_eq("an OSC abandoned at an ESC still echoes its introducer", &g, "\033[31m",
          "[31m without the ESC would apply nothing");
  rc_reset(&g, 20, 4, 0x07);
  putraw(&g, "\033[3\033[31mX");
  echo_eq("abandon-and-restart echoes the restarted sequence", &g, "\033[31m", "deviation #1");
  rc_reset(&g, 20, 4, 0x07);
  putraw(&g, "\033[3\030mX");
  echo_eq("CAN abandons the sequence, so nothing is echoed", &g, "", "the tail was painted as text");
  rc_reset(&g, 20, 4, 0x07);
  putraw(&g, "\033[31");
  echo_eq("an SGR that never dispatched is not echoed", &g, "", "still pending in the parser");

  /* Caps: dropping is counted, never silent. */
  rc_reset(&g, 20, 4, 0x07);
  putraw(&g, "\033[31m");
  eq_u("pending units", (unsigned)rc_sgr_pending(&g), 5, "ESC [ 3 1 m");
  eq_u("a too-small take is refused", (unsigned)rc_sgr_take(&g, big, 4), (unsigned) -1,
       "losing the echo loses parity, so the caller is told instead of the bytes being dropped");
  eq_u("and the pending count survives it", (unsigned)rc_sgr_pending(&g), 5, "");
  eq_u("a take that fits succeeds", (unsigned)rc_sgr_take(&g, big, 5), 5, "");

  rc_reset(&g, 20, 4, 0x07);
  char seq[256] = "\033[";
  for (int i = 0; i < 40; i++) strcat(seq, "1;");
  strcat(seq, "m");
  putraw(&g, seq);
  eq_u("a sequence longer than the capture is not echoed", (unsigned)rc_sgr_pending(&g), 0,
       "half an SGR is worse than none");
  eq_u("and the drop is counted", (unsigned)g.nSgrDrop, 1, "visible in stats[16]");

  const int L = (int)strlen("\033[1;38;5;145;48;5;145m");
  rc_reset(&g, 20, 4, 0x07);
  for (int i = 0; i < 200; i++) putraw(&g, "\033[1;38;5;145;48;5;145m");
  eq_u("the accumulator holds whole sequences up to its cap", (unsigned)rc_sgr_pending(&g),
       (unsigned)((RC_SGR_ECHO_MAX / L) * L), "a prefix of the chunk, never half a sequence");
  eq_u("the rest is counted", (unsigned)g.nSgrDrop, (unsigned)(200 - RC_SGR_ECHO_MAX / L),
       "unreachable while a chunk is one writer buffer: JLine hands over 1024 units");
}

static void gm_pending()
{
  static RcGrid g;
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[");
  eq_u("a lone CSI introducer", (unsigned)g.mode, RC_CSI, "waiting");
  eq_u("nothing painted yet", g.nCells, 0, "pending");
  put(&g, "H");
  eq_u("CSI H after resume", (unsigned)g.cx, 0, "cursor to home");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033");
  eq_u("a lone ESC", (unsigned)g.mode, RC_ESC, "waiting");
  put(&g, "[1;1HX");
  eq_text(&g, 0, 1, "X", "completed at the next chunk");

  rc_reset(&g, 20, 4, 0x07);
  put1(&g, "\033[31");
  eq_u("attr before the final byte", g.attr, 0x07, "SGR is applied at the final byte, not earlier");
  put1(&g, ";42mX");
  eq_u("SGR split between parameters", g.attr, 0x24, "red foreground, green background");

  rc_reset(&g, 20, 4, 0x07);
  put1(&g, "\033]0;ti");
  eq_u("OSC pending", (unsigned)g.mode, RC_OSC, "waiting for BEL or ST");
  put1(&g, "tle\007X");
  eq_text(&g, 0, 1, "X", "the OSC never reached the grid");
}

/* =========================================================== 4. geometry ======================= */

static void geo_wrap()
{
  static RcGrid g;
  rc_reset(&g, 10, 3, 0x07);
  put(&g, "0123456789");
  eq_text(&g, 0, 10, "0123456789", "line 0 full");
  eq_u("immediate wrap x", (unsigned)g.cx, 0, "conhost wrapped as soon as the last cell was filled");
  eq_u("immediate wrap y", (unsigned)g.cy, 1, "");
  put(&g, "A");
  eq_text(&g, 1, 1, "A", "wrapped text lands on row 1");

  /* A wide glyph that does not fit moves whole: never split across two rows, never squashed into one
     column. JLine's columnSplitLength agrees; the shipped Java writer declined the case instead. */
  const uint16_t wide = 0x4E00;                        /* U+4E00, EAW W */
  rc_reset(&g, 10, 3, 0x07);
  put(&g, "012345678");
  putu(&g, &wide, 1);
  eq_text(&g, 0, 9, "012345678", "row 0 untouched");
  eq_u("row 0 last column still blank", RC_CELLS(&g, 0)[9].ch, ' ', "the wide glyph did not split");
  eq_u("wide front", RC_CELLS(&g, 1)[0].ch, 0x4E00, "");
  eq_u("wide front attr", RC_CELLS(&g, 1)[0].attr & RC_LVB_LEADING, RC_LVB_LEADING, "LEADING");
  eq_u("wide back", RC_CELLS(&g, 1)[1].ch, 0x4E00, "conhost repeats the code point");
  eq_u("wide back attr", RC_CELLS(&g, 1)[1].attr & RC_LVB_TRAILING, RC_LVB_TRAILING, "TRAILING");
  eq_u("wide back keeps the colour", RC_CELLS(&g, 1)[1].attr & 0xF0, RC_CELLS(&g, 1)[0].attr & 0xF0, "");
  eq_u("cursor after wide", (unsigned)g.cx, 2, "");
  eq_u("two columns charged", g.nCells, 11, "9 narrow + 1 wide");

  /* exactly two columns left: it fits, and the fill triggers the wrap */
  rc_reset(&g, 10, 3, 0x07);
  put(&g, "01234567");
  putu(&g, &wide, 1);
  eq_u("wide at cols-2 front", RC_CELLS(&g, 0)[8].attr & RC_LVB_LEADING, RC_LVB_LEADING, "");
  eq_u("wide at cols-2 back", RC_CELLS(&g, 0)[9].attr & RC_LVB_TRAILING, RC_LVB_TRAILING, "");
  eq_u("cursor wrapped after a full row", (unsigned)g.cx, 0, "");
  eq_u("row wrapped after a full row", (unsigned)g.cy, 1, "");
}

/* I35: DECAWM -- `CSI ?7 l` ends the line at the margin instead of continuing it on the next row.
   Both reference terminals act on the mode (MSFT keeps it as private mode 7 and answers DECRQM for it),
   and the product's own ANSI dictionary names both spellings (`lua/ansi.lua`'s WRAP/UNWRAP), so refusing
   the sequence was silence in answer to a request that has a meaning. ConEmu's own arm leaves the
   SetConsoleMode commented out (Ansi.cpp:3268-3281), which is what makes this a documented deviation
   rather than a parity item -- and the terminfo entry keeps `smam`/`rmam` out, because it also describes
   sessions where that parser reads the stream (I26). */
static void geo_decawm()
{
  static RcGrid g;
  const uint16_t wide = 0x4E00;
  const uint16_t narrowAstral[2] = { 0xD834, 0xDD1E };   /* U+1D11E: astral, EAW N, so two units one column each */
  struct RcReportItem it;

  /* The margin is where the line ends. */
  rc_reset(&g, 10, 3, 0x07);
  put(&g, "\033[?7l0123456789abc");
  eq_text(&g, 0, 10, "012345678c", "three characters past the margin overwrote the last cell");
  eq_u("cursor holds at the margin", (unsigned)g.cx, 9, "the cell a fixed-width status line keeps redrawing");
  eq_u("cursor never left the row", (unsigned)g.cy, 0, "nothing scrolled for a line that ended here");
  eq_u("the row claims no wrap", (unsigned)rc_row_wrap(&g, 0), (unsigned)RC_WRAP_NONE,
       "copy and export must not join a row the application ended");
  eq_u("the row below is blank", (unsigned)RC_CELLS(&g, 1)[0].ch, (unsigned)' ', "");

  /* DECSET 7 takes effect on the very next character. The wrap is immediate, not pending (I22's four
     discriminators), so the character that fills the last column is drawn there and only the one after it
     starts the next row -- which is the difference this case had wrong on its first run. */
  put(&g, "\033[?7hZ");
  eq_u("the character that filled the row landed in it", (unsigned)RC_CELLS(&g, 0)[9].ch, (unsigned)'Z', "");
  eq_u("the row that had ended is forced", (unsigned)rc_row_wrap(&g, 0), (unsigned)RC_WRAP_FORCED, "");
  eq_u("cursor wrapped to the next row", (unsigned)g.cy, 1, "");
  put(&g, "Y");
  eq_text(&g, 1, 1, "Y", "and the next character starts it");

  /* A wide glyph with one column left is dropped whole, and the column it could not use is cleared.
     MSFT's words for the same choice: "Ignore the character. There's no correct alternative way to
     handle this situation." (Row.cpp:474-494) */
  rc_reset(&g, 10, 3, 0x07);
  put(&g, "\033[?7l012345678");
  eq_u("nine columns written", (unsigned)g.nCells, 9, "");
  putu(&g, &wide, 1);
  eq_u("the glyph is not on the grid", (unsigned)RC_CELLS(&g, 0)[9].ch, (unsigned)' ',
       "cleared, rather than left holding whatever passed this way before");
  eq_u("no trailing bit on it", (unsigned)(RC_CELLS(&g, 0)[9].attr & RC_LVB_TRAILING), 0, "");
  eq_u("a dropped glyph charges no cell", (unsigned)g.nCells, 9, "");
  eq_u("cursor still at the margin", (unsigned)g.cx, 9, "");
  eq_u("no pad claim", (unsigned)rc_row_wrap(&g, 0), (unsigned)RC_WRAP_NONE,
       "the row was not left short so a glyph could start the next one");
  eq_u("no row was started", (unsigned)g.cy, 0, "");

  /* Two columns left is enough: the pair lands, and the cursor comes off its back half. */
  rc_reset(&g, 10, 3, 0x07);
  put(&g, "\033[?7l01234567");
  putu(&g, &wide, 1);
  eq_u("front half at cols-2", (unsigned)(RC_CELLS(&g, 0)[8].attr & RC_LVB_LEADING),
       (unsigned)RC_LVB_LEADING, "");
  eq_u("back half at cols-1", (unsigned)(RC_CELLS(&g, 0)[9].attr & RC_LVB_TRAILING),
       (unsigned)RC_LVB_TRAILING, "");
  eq_u("the margin clamp stepped off the back half", (unsigned)g.cx, 8,
       "the rule step_back_col exists for: a cursor never rests inside a glyph");
  put(&g, "x");
  eq_u("the front half is overwritten", (unsigned)RC_CELLS(&g, 0)[8].ch, (unsigned)'x', "");
  eq_u("its partner went with it", (unsigned)RC_CELLS(&g, 0)[9].ch, (unsigned)' ', "");
  eq_u("no orphaned trailing bit", (unsigned)(RC_CELLS(&g, 0)[9].attr & RC_LVB_TRAILING), 0, "");
  eq_u("cursor on the last column", (unsigned)g.cx, 9, "");

  /* The trim belongs to the cell pair, not to the mode: a narrow glyph over a wide one's front half ends
     the glyph wherever the cursor happened to be put. With DECAWM on and a CUP, that is the same shape. */
  rc_reset(&g, 10, 3, 0x07);
  putu(&g, &wide, 1);
  put(&g, "\033[1;1HA");
  eq_u("overwrite of the front half", (unsigned)RC_CELLS(&g, 0)[0].ch, (unsigned)'A', "");
  eq_u("ends the back half too", (unsigned)RC_CELLS(&g, 0)[1].ch, (unsigned)' ',
       "conhost trims the cluster the same way (Row.cpp's ReplaceCharacters)");
  eq_u("no stray trailing bit", (unsigned)(RC_CELLS(&g, 0)[1].attr & RC_LVB_TRAILING), 0,
       "left alone, it would be copied as part of a glyph that is no longer there");

  /* Half a surrogate pair is not a character either, so a narrow astral glyph is dropped as a unit
     rather than written as one lone high surrogate in the last cell. */
  eq_u("the oracle widths U+1D11E as one column", (unsigned)rc_width(0x1D11E), 1,
       "this case is about the two-unit arm, and it only reaches that arm if the glyph is narrow");
  rc_reset(&g, 10, 3, 0x07);
  put(&g, "\033[?7l012345678");
  putu(&g, narrowAstral, 2);
  eq_u("neither half landed", (unsigned)RC_CELLS(&g, 0)[9].ch, (unsigned)' ', "");
  eq_u("and nothing wrapped to the next row", (unsigned)RC_CELLS(&g, 1)[0].ch, (unsigned)' ', "");

  /* DECRQM answers what the model now holds, snapshot and all. */
  rc_reset(&g, 10, 3, 0x07);
  put(&g, "\033[?7$p");
  eq_u("one request, one reply", (unsigned)rc_report_pending(&g), 1, "");
  eq_u("its kind", (unsigned)rc_report_take(&g, &it), (unsigned)RC_REP_DECRPM, "");
  eq_u("the mode that was asked about", (unsigned)it.mode, 7, "");
  eq_u("set, out of reset", (unsigned)it.status, 2, "DECAWM is on after a reset in VT and in both references");
  put(&g, "\033[?7l\033[?7$p");
  eq_u("the set spelled here is the one that answers", (unsigned)rc_report_pending(&g), 1,
       "`?7l` itself is silent");
  rc_report_take(&g, &it);
  eq_u("and says reset", (unsigned)it.status, 1, "");
  eq_u("none of this voted in the census", (unsigned)g.nUnsupported[RC_UN_MODE], 0,
       "an answered query is not an unmodelled request");

  /* RIS and DECSTR both put the mode back with everything else they reset. */
  put(&g, "\033[?7l\033[!p\033[?7$p");
  rc_report_take(&g, &it);
  eq_u("DECSTR restores it", (unsigned)it.status, 2,
       "a mode with no terminfo entry is still a mode a reset owns");
  put(&g, "\033[?7l\033c\033[?7$p");
  rc_report_take(&g, &it);
  eq_u("RIS restores it", (unsigned)it.status, 2, "");

  /* `CSI 7 h/l` without the `?` is GATM, not DECAWM, and stays unmodelled. */
  rc_reset(&g, 10, 3, 0x07);
  put(&g, "\033[7l\033[7h");
  eq_u("the two GATM spellings are counted as modes", (unsigned)g.nUnsupported[RC_UN_MODE], 2,
       "only the private spelling is DECAWM");
  eq_u("and left the wrap alone", (unsigned)g.wrapMode, 1, "");
  put(&g, "0123456789");
  eq_u("so the row still wraps", (unsigned)rc_row_wrap(&g, 0), (unsigned)RC_WRAP_FORCED, "");
}


/**
 * The wrap column is the BUFFER row, not the window. Measured 2026-09-23 on a fresh conhost with this
 * machine's console profile (a 2000x9001 buffer, a 120x60 window): a raw WriteConsoleW of 150 units put
 * all 150 on one row, left srWindow at 0..99, and parked the cursor at column 150. A model as wide as
 * the window would wrap a report that conhost is going to print 2000 columns wide, onto rows the
 * console never used -- which is why `cols` comes from the buffer and not from the window.
 */
static void geo_wrap_wide_buffer(void)
{
  static RcGrid g;
  static uint16_t u[2001];                            /* putraw()'s 128-unit window is too narrow here */
  const uint16_t one = 'z';
  int i;

  rc_reset(&g, 2000, 3, 0x07);
  for (i = 0; i < 200; i++) u[i] = 'z';
  putu(&g, u, 200);
  eq_u("200 columns: no wrap in a 2000-column row", (unsigned)g.cy, 0,
       "a 120-column window would have wrapped this at 120");
  eq_u("cursor past the window's right edge", (unsigned)g.cx, 200, "adopted, not clamped, by align()");
  eq_u("column 119 is on the line", RC_CELLS(&g, 0)[119].ch, 'z', "the window's last column");
  eq_u("column 120 is on the line too", RC_CELLS(&g, 0)[120].ch, 'z', "off screen, and still a cell");
  eq_u("column 199 is the last", RC_CELLS(&g, 0)[199].ch, 'z', "");
  eq_u("row 1 untouched", RC_CELLS(&g, 1)[0].ch, ' ', "no phantom wrapped row");

  for (i = 0; i < 1800; i++) u[i] = 'y';
  putu(&g, u, 1800);
  eq_u("filling the last column wraps at once", (unsigned)g.cx, 0, "the same rule geo_wrap pins on a 10-column row");
  eq_u("so the cursor is already on the next row", (unsigned)g.cy, 1,
       "nothing is left sitting past the buffer's edge; the real console is the witness (Render.java)");
  eq_u("the last column of the buffer row", RC_CELLS(&g, 0)[1999].ch, 'y', "");
  putu(&g, &one, 1);
  eq_u("the next cell starts that row", RC_CELLS(&g, 1)[0].ch, 'z', "wrapped at the buffer's edge");
  eq_u("and it did not scroll twice", (unsigned)g.cy, 1, "");
}

static void geo_surrogates()
{
  const uint16_t pair[] = {0xD83D, 0xDE00};           /* U+1F600 */
  const uint16_t a = 'A';
  static RcGrid g;
  rc_reset(&g, 20, 3, 0x07);
  putu(&g, pair, 2);
  eq_u("astral counted", g.nAstral, 1, "");
  eq_u("astral front", RC_CELLS(&g, 0)[0].ch, 0xD83D, "the pair reaches the grid as two WCHARs");
  eq_u("astral back", RC_CELLS(&g, 0)[1].ch, 0xDE00, "");
  eq_u("astral is wide", RC_CELLS(&g, 0)[0].attr & RC_LVB_LEADING, RC_LVB_LEADING,
       "U+1F600 is EAW W, so two columns as for CJK. The grid witness on a legacy console has the "
       "last word on this convention; RenderCheck only pins the rule we shipped with.");

  /* A high surrogate at the very end of a chunk is held, not painted: half a character must never
     reach the screen, which is the hole the JLine Windows path has (jansi-research ANALYSIS.md 3.3). */
  rc_reset(&g, 20, 3, 0x07);
  putu(&g, pair, 1);
  eq_u("a held high surrogate paints nothing", g.nCells, 0, "");
  eq_u("held high surrogate", g.wantLow, 0xD83D, "");
  putu(&g, pair + 1, 1);
  eq_u("completed on the next chunk", g.nCells, 2, "");
  eq_u("completed front", RC_CELLS(&g, 0)[0].ch, 0xD83D, "");
  eq_u("wantLow cleared on completion", g.wantLow, 0, "");

  rc_reset(&g, 20, 3, 0x07);
  putu(&g, pair, 1);
  putu(&g, &a, 1);
  eq_u("an uncompleted high surrogate", RC_CELLS(&g, 0)[0].ch, 0xFFFD, "replaced, never half-painted");
  /* U+FFFD is EAW=A, measured 2 on the CJK faces and 1 on the Western ones, so by the ruling (I14) it
     costs two columns and whatever follows lands one column further along than it did before. */
  eq_u("the replacement takes the whole cell pair", RC_CELLS(&g, 0)[1].attr & RC_LVB_TRAILING,
       RC_LVB_TRAILING, "U+FFFD's own trailing cell, not a stray glyph");
  eq_u("the unit after a replacement still lands", RC_CELLS(&g, 0)[2].ch, 'A', "");
  eq_u("wantLow cleared", g.wantLow, 0, "");

  rc_reset(&g, 20, 3, 0x07);
  const uint16_t low = 0xDE00;
  putu(&g, &low, 1);
  eq_u("a lone low surrogate", RC_CELLS(&g, 0)[0].ch, 0xFFFD, "");
}

/* T6, and the reason a table replaced a test: `stats()` is positional across three files (I19), the labels
 * that turn those numbers into a sentence are written in two of them, and until now four indices had a check
 * and eleven names had none. This pins the table itself -- one row per slot, no two slots sharing a label,
 * exactly one of them doubting the frame, and the label list spelled out so a rename has to be a decision
 * made in three places with the gate naming the one that was forgotten. */
static void geo_census()
{
  static RcGrid g;
  static char dump[1024];
  const int n = rc_census_count();
  int i, j, suspects = 0, slot = -1;

  eq_u("one row per slot", (unsigned)n, (unsigned)RC_UN_MAX, "the enum's own count, so a new slot must be appended with a row");
  dump[0] = 0;
  for (i = 0; i < n; i++)
  {
    const char *nm = rc_census_name(i), *se = rc_census_sentence(i);
    eq_u(S("slot %d has a name", i), (unsigned)(nm != NULL && nm[0] != 0), 1, "");
    eq_u(S("slot %d says what was skipped", i), (unsigned)(se != NULL && se[0] != 0), 1, "");
    for (j = 0; j < i; j++)
      eq_u(S("slot %d does not share slot %d's label", i, j),
           (unsigned)(strcmp(nm, rc_census_name(j)) != 0), 1, "two labels a report cannot tell apart");
    if (rc_census_suspect(i)) { suspects++; slot = i; }
    if (i) strncat(dump, ", ", sizeof dump - strlen(dump) - 1);
    strncat(dump, nm, sizeof dump - strlen(dump) - 1);
  }
  eq_u("exactly one slot doubts the frame", (unsigned)suspects, 1,
       "the reach belongs to the unknown final alone; every other family is a known no-op");
  eq_u("and it is the first slot", (unsigned)slot, (unsigned)RC_UN_SUP,
       "which is the day `ignored()` was split out of `unsupported()` and why the two still exist");
  eq_u("the labels, in this order, unchanged",
       (unsigned)(strcmp(dump, "unrecognised, decstbm, altbuf, mouse, mode, bracketed paste, osc9, "
                               "other osc, dcs, report, colon, osc clip") == 0), 1,
       "this is the text a rollout reads; renaming one here has to rename it in Render.java's report and in "
       "NativeRenderer's UNMODELLED, and the live gate now checks the first of those at run time");
  eq_u("an out-of-range slot names nothing", (rc_census_name(RC_UN_MAX) == NULL) ? 1u : 0u, 1u, "");

  /* The flag is now data, so the behaviour it used to encode needs re-pinning from both sides. */
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033[1;2:3m");
  eq_u("a sub-parameter no arm consumed is one vote", (unsigned)un(&g, RC_UN_COLON), 1,
       "`2:3`: the `2` took its own parameter, and the 3 belongs to it rather than to the loop");
  eq_u("and it is not read as a rendition", (unsigned)g.sgr.italic, 0,
       "SGR 3 would be italic, invented from a number whose owner already said no");
  eq_u("and still does not cost a repaint", (unsigned)rc_model_suspect(&g), 0, "");
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033[1\\");
  eq_u("the unknown final still does", (unsigned)rc_model_suspect(&g), 1, "");

  /* A row of the registry is not only a label: it claims that whatever reaches that counter is *described*
     by it. Two rows failed that claim, and writing the table down is what made them visible. */
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "]2004;1x");
  eq_u("a `]2004;` OSC is counted as the bracketed-paste request it is",
       (unsigned)un(&g, RC_UN_DECBP), 1,
       "`other osc`'s own sentence says the code had no case here, which is a different fact from the one asked");
  eq_u("and not also as an unrecognised OSC", (unsigned)un(&g, RC_UN_OSC_OTHER), 0,
       "one sequence, one counter: two votes would let the census add up past the sequences it saw");
  eq_u("nothing about it doubts the frame", (unsigned)rc_model_suspect(&g), 0,
       "a mode this library does not own is inert, not unknown");
  eq_text(&g, 0, 1, "x", "the payload is consumed with the sequence, as every un-acted-on OSC's is");
}

/* Every way one OSC family is known to be able to leave a mark, in one value.
 *
 * The question this answers is "did the handler do anything, or is it a `return;` wearing a name?" -- and
 * answering it needs a witness list, because the honest alternative (compare the whole grid) is vacuous:
 * the payload sink is part of the struct, so every probe would "change the model" merely by being parsed.
 * The sink, the parser's own resumable state and the console geometry are therefore left out, and what is
 * kept is the set of fields the families can write: the tallies, the colour tables, the attribute the
 * defaults fold to, the FTCS marks and row semantic, the pending title and clipboard request, and the
 * reported OSC 9 pair. A family that later acts through a field nobody thought of is a gate that stops
 * proving something about that family -- which is why the fields are named here rather than hashed. */
struct OscFx
{
  unsigned long un[RC_UN_MAX];
  unsigned long nTitleSet, nTitleTrunc, nClipSet, nClipBad, nClipSel, nClipRead;
  unsigned long nPromptMark, nReportOk, nReportFail, nReportFull;
  uint32_t pal16[16];
  RcRowState rowState[RC_MAX_ROWS];   /* whole structs: a mirror that copies one field is how #73 started */
  int cx, cy, attr, defAttr, titlePending, clipPending, nClip, nCwd;
  int semanticContent, semanticClearEol, taskbarState, taskbarProgress, taskbarSeen, lastExit, palTouched;
};

static void osc_fx_get(RcGrid *g, struct OscFx *f)
{
  int i;
  for (i = 0; i < RC_UN_MAX; i++) f->un[i] = g->nUnsupported[i];
  f->nTitleSet = g->nTitleSet; f->nTitleTrunc = g->nTitleTrunc;
  f->nClipSet = g->nClipSet; f->nClipBad = g->nClipBad;
  f->nClipSel = g->nClipSel; f->nClipRead = g->nClipRead;
  f->nPromptMark = g->nPromptMark;
  f->nReportOk = g->nReportOk; f->nReportFail = g->nReportFail; f->nReportFull = g->nReportFull;
  for (i = 0; i < 16; i++) f->pal16[i] = g->pal16[i];
  /* The mirror is flat and the grid is not: capture by *model* row, which is the row a comparison after a
     probe asks about. Reading `g->rowState[i]` here would compare storage that a scroll is free to move. */
  for (i = 0; i < RC_MAX_ROWS; i++) f->rowState[i] = RC_ST(g, i);
  f->cx = g->cx; f->cy = g->cy; f->attr = g->attr; f->defAttr = g->defAttr;
  f->titlePending = g->titlePending; f->clipPending = g->clipPending;
  f->nClip = g->nClip; f->nCwd = g->nCwd;
  f->semanticContent = g->semanticContent; f->semanticClearEol = g->semanticClearEol;
  f->taskbarState = g->taskbarState; f->taskbarProgress = g->taskbarProgress;
  f->taskbarSeen = g->taskbarSeen; f->lastExit = g->lastExit; f->palTouched = g->palTouched;
}

static void geo_osc_families()
{
  static RcGrid g;
  /* One well-formed payload per code the table is allowed to own, and the setup each one needs to be
     observable at all: `110` with the default foreground already at the seed changes nothing, so the probe
     that wants to prove 110 *can* act has to move the attribute first. */
  static const struct { int code; const char *setup, *probe; } probe[] = {
    {    0, NULL,            "\033]0;gate title\007"  },
    {    1, NULL,            "\033]1;gate icon\007"   },
    {    2, NULL,            "\033]2;gate title\007"  },
    {    4, NULL,            "\033]4;1;rgb:ff/00/00\007" },
    {    9, NULL,            "\033]9;12\007"           },
    {   10, NULL,            "\033]10;rgb:ff/ff/ff\007" },
    {   11, NULL,            "\033]11;rgb:ff/00/00\007" },
    {   52, NULL,            "\033]52;c;YWJj\007"      },
    {  104, "\033]4;1;rgb:ff/00/00\007", "\033]104\007" },
    {  110, "\033]10;rgb:ff/ff/ff\007",  "\033]110\007" },
    {  111, "\033]11;rgb:ff/ff/ff\007",  "\033]111\007" },
    {  133, NULL,            "\033]133;A\007"          },
    { 2004, NULL,            "\033]2004;1\007"         },
  };
  const int nf = rc_osc_family_count();
  const int np = (int)(sizeof probe / sizeof probe[0]);
  int i, j, k, owned = 0;

  /* Names, because the census row is not the only label a report reads from here. */
  for (i = 0; i < nf; i++)
  {
    const char *nm = rc_osc_family_name(i);
    int probed = 0;
    eq_u(S("family %d has a name", i), (unsigned)(nm != NULL && nm[0] != 0), 1, "");
    for (j = 0; j < i; j++)
      eq_u(S("family %d does not share %s's name", i, rc_osc_family_name(j)),
           (unsigned)(strcmp(nm, rc_osc_family_name(j)) != 0), 1,
           "two families a report could not tell apart");
    for (k = 0; k < np; k++) if (rc_osc_family_owns(i, probe[k].code)) probed = 1;
    eq_u(S("%s has a probe", nm), (unsigned)probed, 1,
         "a family nothing feeds cannot be shown to answer, which is the whole point of listing them");
  }
  eq_u("an out-of-range family names nothing", (rc_osc_family_name(nf) == NULL) ? 1u : 0u, 1u, "");
  eq_u("and owns nothing", (unsigned)rc_osc_family_owns(nf, 2), 0, "");

  /* Disjointness, and the exact extent of what the table claims. Order in the table is precedence, and
     that is only a free thing to read if no code is claimed twice -- the if-chain this replaced had the
     same hazard and no way to say it was absent. The second half is the one that catches a new code added
     to an `owns` predicate: it fails here, and the fix is to add a probe, not to loosen this line. */
  for (i = 0; i <= 4096; i++)
  {
    int claimants = 0;
    for (j = 0; j < nf; j++) if (rc_osc_family_owns(j, i)) claimants++;
    if (claimants > 1)
      eq_u(S("code %d is owned by %d families", i, claimants), 1u, 0u,
           "the later handler is unreachable, and no test of the earlier one would notice");
    if (claimants == 1) owned++;
    if (claimants == 1)
    {
      int probed = 0;
      for (k = 0; k < np; k++) if (probe[k].code == i) probed = 1;
      if (!probed) eq_u(S("code %d is claimed but never probed", i), 0u, 1u,
                        "a code with a handler and no test is a code nobody can show arriving");
    }
  }
  eq_u("the table owns exactly the codes this gate feeds", (unsigned)owned, (unsigned)np,
       "the probe list is the extent of what the parser claims -- grow both together");

  /* Every probe reaches its family, is not swallowed by the tail, and leaves a mark. */
  for (k = 0; k < np; k++)
  {
    struct OscFx before, after;
    int claimants = 0;
    for (j = 0; j < nf; j++) if (rc_osc_family_owns(j, probe[k].code)) claimants++;
    eq_u(S("code %d is spoken for by exactly one family", probe[k].code), (unsigned)claimants, 1,
         claimants ? "claimed twice above" : "no family owns it, so the tail counts it and the probe is silent");

    rc_reset(&g, 20, 3, 0x07);
    if (probe[k].setup) put(&g, probe[k].setup);
    osc_fx_get(&g, &before);
    put(&g, probe[k].probe);
    eq_u(S("code %d does not fall through to `other osc`", probe[k].code),
         (unsigned)un(&g, RC_UN_OSC_OTHER), 0,
         "the tail's sentence is `a code no family owns`, and dispatching here would make it a lie");
    eq_u(S("and code %d does not doubt the frame", probe[k].code),
         (unsigned)rc_model_suspect(&g), 0, "an OSC named by a family is a known no-op at worst");
    osc_fx_get(&g, &after);
    eq_u(S("code %d leaves a mark", probe[k].code),
         (unsigned)(memcmp(&before, &after, sizeof before) != 0), 1,
         "nothing in the witness list moved: this handler acts on nothing and counts nothing");
  }
}

static void geo_scroll()
{
  /* The row a scroll vacates is blank in the *current* attribute, which is what the shipped writer
     has always passed to ScrollConsoleScreenBuffer (BulkCellWriter.java:364,448). */
  static RcGrid g;
  rc_reset(&g, 8, 2, 0x07);
  put(&g, "\033[42m");
  eq_u("bg green attr", g.attr, 0x27, "ClrMap[2]=2 in the background nibble");
  put(&g, "A\r\nB\r\nC");
  eq_text(&g, 0, 1, "B", "A scrolled up and out");
  eq_text(&g, 1, 1, "C", "C on the fresh line");
  eq_u("scrolled fill char", RC_CELLS(&g, 1)[1].ch, ' ', "");
  eq_u("scrolled fill attr", RC_CELLS(&g, 1)[1].attr, 0x27, "the live attribute, not the default");
  eq_u("scrolls counted", g.nScrolls, 1, "");

  rc_reset(&g, 8, 3, 0x07);
  put(&g, "a\r\nb\r\nc");
  eq_text(&g, 2, 1, "c", "the third row is the bottom of a 3-row viewport");
  put(&g, "\033[S");
  eq_text(&g, 0, 1, "b", "CSI S scrolls up one");
  eq_text(&g, 1, 1, "c", "");
  eq_u("CSI S left the bottom blank", RC_CELLS(&g, 2)[0].ch, ' ', "");
  put(&g, "\033[A\033[2A");
  eq_u("CUU clamps at the top", (unsigned)g.cy, 0, "");
}

static void geo_erase()
{
  static RcGrid g;
  rc_reset(&g, 10, 3, 0x07);
  put(&g, "ABCDEFGH\033[42m\033[3;1H");         /* green from here, cursor to row 2 col 0 */
  put(&g, "XY");
  eq_u("cursor col", (unsigned)g.cx, 2, "");
  put(&g, "\033[0K");
  eq_text(&g, 2, 2, "XY", "EL 0 leaves the text before the cursor");
  eq_u("EL 0 blank", RC_CELLS(&g, 2)[3].ch, ' ', "");
  eq_u("EL 0 attr is the live one", RC_CELLS(&g, 2)[3].attr, 0x27, "not the default");
  put(&g, "\033[1D\033[1K");
  eq_text(&g, 2, 2, "  ", "EL 1 clears from the line start through the cursor");
  eq_text(&g, 2, 4, "    ", "EL 1 leaves the rest of the row");

  rc_reset(&g, 10, 3, 0x07);
  put(&g, "AB\033[42m\033[2K");
  eq_text(&g, 0, 2, "  ", "EL 2 clears the whole row");
  eq_u("EL 2 attr", RC_CELLS(&g, 0)[9].attr, 0x27, "");

  rc_reset(&g, 10, 3, 0x07);
  put(&g, "AB\r\nCD\033[2J");
  eq_text(&g, 0, 1, " ", "ED 2 clears the viewport");
  eq_text(&g, 1, 1, " ", "ED 2 clears row 1");
  eq_u("ED 2 homes the cursor x", (unsigned)g.cx, 0, "Ansi.cpp:3027");
  eq_u("ED 2 homes the cursor y", (unsigned)g.cy, 0, "");
  rc_clear_dirty(&g);
  put(&g, "\033[2J");
  eq_u("ED 2 dirties every row", (unsigned)rc_row_dirty(&g, 2), 1, "the painter must repaint them all");

  rc_reset(&g, 10, 3, 0x07);
  put(&g, "ABCDEFGH");
  put(&g, "\033[1;3H");
  eq_u("before ECH", (unsigned)g.cx, 2, "");
  put(&g, "\033[X");
  eq_text(&g, 0, 4, "AB D", "ECH erases one cell at the cursor and keeps the rest");
  eq_u("ECH attr", RC_CELLS(&g, 0)[2].attr, 0x07, "the live attribute, which is still the default");

  rc_reset(&g, 10, 3, 0x07);
  put(&g, "ABCDEFGH");
  put(&g, "\033[2;1H1234567890");
  put(&g, "\033[3;1HXYZ");
  put(&g, "\033[1;3H\033[0J");
  eq_text(&g, 0, 3, "AB ", "ED 0 clears from the cursor to the end of the row");
  eq_text(&g, 0, 8, "AB      ", "and the tail too");
  eq_text(&g, 1, 10, "", "ED 0 clears the rows below, every column of them");
  eq_text(&g, 2, 10, "", "including the last");
  eq_u("ED 0 left row 1 blank", RC_CELLS(&g, 1)[0].ch, ' ', "");

  /* a trailing half must not survive an erase over it, or the grid diff shows a ghost cell */
  const uint16_t wide = 0x4E00;
  rc_reset(&g, 10, 3, 0x07);
  putu(&g, &wide, 1);
  put(&g, "\033[1;1H\033[2K");
  eq_u("erase kills TRAILING", RC_CELLS(&g, 0)[1].attr & RC_LVB_TRAILING, 0, "");
}

static void geo_cursor()
{
  static RcGrid g;
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "AB\b");
  eq_u("BS moves x", (unsigned)g.cx, 1, "BS does not erase");
  eq_text(&g, 0, 2, "AB", "the character is still there");
  put(&g, "\033[20D");
  eq_u("CUB clamps at 0", (unsigned)g.cx, 0, "");

  /* Backspace and CUB stop at a glyph boundary and never inside a wide glyph -- conhost's
     ROW::_adjustBackward (Row.cpp:1215), which upstream makes a named primitive of the row
     (NavigateToPrevious) precisely because the alternative is a cursor parked in a character's belly.
     The grid witness demanded this: with a one-column step, "wide glyph then BS" left a leading half
     on screen that the fallback leg does not leave (Render.java caseLegsAgree, measured 2026-09-23). */
  const uint16_t hira = 0x3042;                        /* U+3042, EAW W */
  rc_reset(&g, 20, 6, 0x07);
  putu(&g, &hira, 1);
  eq_u("a wide glyph takes two columns", (unsigned)g.cx, 2, "setup");
  put(&g, "\b");
  eq_u("BS steps over the whole glyph", (unsigned)g.cx, 0, "not 1: cell 1 is a trailing half");
  eq_u("BS still erases nothing", RC_CELLS(&g, 0)[0].ch, 0x3042, "the move is not a delete");

  rc_reset(&g, 20, 6, 0x07);
  putu(&g, &hira, 1);
  put(&g, "\033[1D");
  eq_u("CUB 1 steps over the glyph too", (unsigned)g.cx, 0, "same rule, different door");

  rc_reset(&g, 20, 6, 0x07);
  putu(&g, &hira, 1);
  putu(&g, &hira, 1);
  put(&g, "a");
  eq_u("wide wide narrow cursor", (unsigned)g.cx, 5, "setup");
  put(&g, "\b");
  eq_u("first BS steps over the narrow", (unsigned)g.cx, 4, "");
  put(&g, "\b");
  eq_u("second BS steps over a glyph", (unsigned)g.cx, 2, "");
  put(&g, "\b");
  eq_u("third BS steps over the other", (unsigned)g.cx, 0, "");

  rc_reset(&g, 20, 6, 0x07);
  putu(&g, &hira, 1);
  putu(&g, &hira, 1);
  put(&g, "a\033[3D");
  eq_u("CUB 3 lands on a leading half, which needs no adjust", (unsigned)g.cx, 2, "");
  put(&g, "\033[1D");
  eq_u("and CUB 1 from there crosses the glyph", (unsigned)g.cx, 0, "one adjustment is enough: a glyph is 2 columns");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "a\tb");
  eq_u("TAB snaps to a multiple of 8", RC_CELLS(&g, 0)[8].ch, 'b', "((x+8)>>3)<<3 from x=1");
  put(&g, "\t");
  eq_u("TAB from 9 advances to 16", (unsigned)g.cx, 16, "");
  put(&g, "\t");
  eq_u("TAB clamps inside the line", (unsigned)g.cx, 19, "20 columns");
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\t");
  eq_u("TAB from 0", (unsigned)g.cx, 8, "ConEmu never stays put");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "abc\rdef");
  eq_text(&g, 0, 3, "def", "CR folds the cursor back inside the line");
  put(&g, "\ngh");
  eq_text(&g, 1, 2, "gh", "LF folds the column: the newline goes to the console, and the console folds");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "abc\rdef\033Dij");
  eq_text(&g, 1, 5, "   ij", "but IND is not LF -- it moves down where it stands");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[3;5H");
  eq_u("CUP y", (unsigned)g.cy, 2, "1-based");
  eq_u("CUP x", (unsigned)g.cx, 4, "");
  put(&g, "\033[999;999H");
  eq_u("CUP clamps y", (unsigned)g.cy, 5, "");
  eq_u("CUP clamps x", (unsigned)g.cx, 19, "");
  put(&g, "\033[7;2;5H");
  eq_u("CUP takes 2 args, clamps y", (unsigned)g.cy, 5, "7-1 clamped into 6 rows");
  eq_u("CUP takes 2 args, x", (unsigned)g.cx, 1, "2-1");
  put(&g, "\033[d\033[1;1H");
  eq_u("VPA alone keeps the column", (unsigned)g.cx, 0, "after home");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[s\033[6;9H\033[u");
  eq_u("CSI s/u x", (unsigned)g.cx, 0, "save then restore");
  eq_u("CSI s/u y", (unsigned)g.cy, 0, "");
  put(&g, "\033[8;8H\033[7m\0338");
  eq_u("ESC 8 x", (unsigned)g.cx, 0, "ESC 7 saved (0,0); attributes are NOT saved");
  eq_u("ESC 8 keeps the SGR", g.attr, 0x4007, "ESC 7 saved the position, not the inverse bit");

  /* The private spelling of DECRC is not DECRC. Upstream restores unconditionally (Ansi.cpp:4194 never
     looks at PvtLen for 'u'), and that is a defect a real consumer can prove: jline4 opens its capability
     probe batch with kitty's `CSI ?u` query (AbstractTerminal.probeModes), so every probe round jerked the
     cursor to whatever was saved last. WT and ghostty both route a private-marker final to their
     query/ignore arms. The gate is a deliberate divergence, so it needs both halves pinned: the query
     stays put, and the plain DECRC that caps `rc`/`sc` keeps working. */
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[s\033[6;9H");
  eq_u("saved at home, moved away", (unsigned)g.cy, 5, "row");
  eq_u("moved away", (unsigned)g.cx, 8, "column");
  put(&g, "\033[?u");
  eq_u("`CSI ?u` restores nothing -- row stays", (unsigned)g.cy, 5, "the probe-batch cursor jerk");
  eq_u("column stays", (unsigned)g.cx, 8, "");
  eq_u("and the query is counted as a refused mode", g.nUnsupported[RC_UN_MODE], 1,
       "same bucket as `?12h`, because its reach is known to be nothing");
  eq_u("without making the frame suspect", (unsigned)g.modelSuspect, 0, "a full repaint for a probe is the old bug");
  put(&g, "\033[u");
  eq_u("the plain `CSI u` still restores", (unsigned)g.cy, 0, "xterm's DECRC carries no private marker");
  eq_u("both columns", (unsigned)g.cx, 0, "");
  eq_u("and a real restore is not counted", g.nUnsupported[RC_UN_MODE], 1, "still the one from the query");

  /* HPR and VPR, and the one thing that makes them more than CUF/CUD aliases: they are clamped to the
     viewport, not to the scroll region (MSFT says it in the comment on each, adaptDispatch.cpp:427/:437).
     ConEmu drops both finals outright, so every assertion here is a deliberate divergence and the pair that
     pins it is `CSI e` and `CSI B` from the same row of the same region. */
  rc_reset(&g, 20, 6, 0x07);
  const unsigned supBefore = g.nUnsupported[RC_UN_SUP];
  put(&g, "\033[H\033[3a");
  eq_u("HPR moves the column", (unsigned)g.cx, 3, "`CSI 3a` from column 0");
  eq_u("and leaves the row alone", (unsigned)g.cy, 0, "");
  put(&g, "\033[2e");
  eq_u("VPR moves the row", (unsigned)g.cy, 2, "`CSI 2e` from row 0");
  eq_u("and leaves the column alone", (unsigned)g.cx, 3, "");
  put(&g, "\033[a\033[e");
  eq_u("HPR with no parameter is 1", (unsigned)g.cx, 4, "xterm: absent or zero is the default");
  eq_u("VPR with no parameter is 1", (unsigned)g.cy, 3, "");
  put(&g, "\033[0a\033[0e");
  eq_u("zero means the default too, not a step back", (unsigned)g.cx, 5, "");
  eq_u("in both", (unsigned)g.cy, 4, "");
  put(&g, "\033[2;4r\033[4;1H");           /* region rows 2..4, cursor on its bottom row */
  eq_u("the region put the cursor at its bottom", (unsigned)g.cy, 3, "setup for the pair below");
  put(&g, "\033[B");
  eq_u("CUD cannot walk out of the region", (unsigned)g.cy, 3, "the behaviour this model already had");
  put(&g, "\033[4;1H\033[e");
  eq_u("VPR walks past the region's bottom", (unsigned)g.cy, 4, "the divergence, both halves pinned");
  put(&g, "\033[99e\033[99a");
  eq_u("VPR is clamped to the viewport bottom", (unsigned)g.cy, 5, "rows-1 of a 6-row grid");
  eq_u("HPR is clamped to the last column", (unsigned)g.cx, 19, "cols-1 of a 20-column grid");
  eq_u("neither final is counted as unsupported any more", g.nUnsupported[RC_UN_SUP], supBefore,
       "the census is how a reader tells `a`/`e` from a byte this dispatch has never heard of");
  put(&g, "\033[3;5r\033[5;1H\033[2e");
  eq_u("a VPR aimed past a region near the bottom stops at the screen, not past it", (unsigned)g.cy, 5,
       "region rows 3..5, cursor on its bottom, asked for two more");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?25l");
  eq_u("DECSCNM ?25 hides", (unsigned)g.cursorVisible, 0, "");
  put(&g, "\033[?25h");
  eq_u("?25 shows", (unsigned)g.cursorVisible, 1, "");
  put(&g, "\033[?47h\033[?1049l\033[?1000h\033[?2004h\033[1;2r\033[c");
  eq_u("alt switches taken", g.nAltSwitch, 2, "47 in and 1049 out -- one behaviour for the family");
  eq_u("nothing counted as an unmodelled alt buffer", g.nUnsupported[RC_UN_ALTBUF], 0, "");
  eq_u("mouse counted", g.nUnsupported[RC_UN_MOUSE], 1, "");
  eq_u("bracketed paste counted", g.nUnsupported[RC_UN_DECBP], 1, "");
  eq_u("DECSTBM counted", g.nUnsupported[RC_UN_DECSTBM], 0, "CSI r sets a region now; the slot is census padding");
  eq_u("DA answered instead of counted", g.nUnsupported[RC_UN_REPORT], 0, "a bare `CSI c` arms a reply now");
  eq_u("and armed exactly one reply", (unsigned)rc_report_pending(&g), 1, "two would leave bytes for the next reader");
  {
    int ry = -1, rx = -1;
    eq_u("the armed reply is DA", (unsigned)take_xy(&g, &ry, &rx), (unsigned)RC_REP_DA, "");
    eq_u("DA snapshot row", (unsigned)ry, 0, "the cursor as it stood when the query was read");
    eq_u("DA snapshot col", (unsigned)rx, 0, "");
    eq_u("the queue is empty again", (unsigned)rc_report_pending(&g), 0, "");
    eq_u("popping an empty queue", (unsigned)rc_report_take(&g, NULL), (unsigned)RC_REP_NONE, "so a drain loop can stop");
  }
  eq_u("DECSTBM painted nothing", g.nCells, 0, "modelled, and a region paints no cells");
  eq_u("and the region it asked for is live", (unsigned)g.regSet, 1, "`CSI c` above is DA, not RIS");
}

/* The alternate screen. What is pinned is the one promise the feature exists for: a program may fill the
 * screen, scroll inside it, and leave, and the screen it started on is found exactly as it was -- its rows,
 * the rows above them, and its cursor. MSFT keeps two buffers and swaps which one the window shows
 * (screenInfo.cpp:1900-1965); we keep one and copy the viewport out and back, so each assertion below is
 * about what a witness reading the console would see, not about which of the two mechanisms produced it.
 * The places the two differ are said so, with the reason. */
static void geo_alt()
{
  static RcGrid g;
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "main\r\nsecond\r\nthird\r\n");
  rc_clear_dirty(&g);
  put(&g, "\033[2;6H");                          /* the row and column the program switched from */
  rc_clear_dirty(&g);

  put(&g, "\033[?1049h");
  eq_u("entered the alt", (unsigned)rc_in_alt(&g), 1, "");
  eq_text(&g, 0, 5, "     ", "it arrives blank, as MSFT's cleared buffer does");
  eq_text(&g, 3, 5, "     ", "");
  eq_u("every viewport row is dirty", (unsigned)(rc_row_dirty(&g, 0) & rc_row_dirty(&g, 3)), 1,
       "the console has to be told to hide what it was showing");
  eq_u("the cursor keeps its viewport position", (unsigned)g.cy, 1,
       "MSFT copies it across: _CreateAltBuffer, screenInfo.cpp:1817-1820");
  eq_u("and its column", (unsigned)g.cx, 5, "");
  eq_u("one switch counted", g.nAltSwitch, 1, "");
  eq_u("the model is not distrusted by its own switch", (unsigned)rc_model_suspect(&g), 0,
       "it knows which screen it is on; suspicion is for what it cannot model");

  put(&g, "\033[1;1Halt");
  eq_text(&g, 0, 3, "alt", "the alt is what is written to now");
  put(&g, "\033[?1049l");
  eq_u("left the alt", (unsigned)rc_in_alt(&g), 0, "");
  eq_text(&g, 0, 5, "main ", "the main screen is back, row for row");
  eq_text(&g, 1, 6, "second", "");
  eq_text(&g, 2, 5, "third", "");
  eq_u("the cursor is where the program stood", (unsigned)g.cx, 5, "CursorRestoreState after the switch, MSFT's order");
  eq_u("and its row", (unsigned)g.cy, 1, "");
  eq_u("leaving dirties the viewport", (unsigned)rc_row_dirty(&g, 2), 1,
       "the alt overwrote those console rows; the main ones have to go back");
  eq_u("two switches, one each way", g.nAltSwitch, 2, "");

  /* The family is one behaviour: all three parameters reach MSFT's ASB_AlternateScreenBuffer, so mixing
     the enter and the leave must be as harmless as using the same number twice. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "zzz\r\n");
  put(&g, "\033[?47h\033[1;1Hq\033[?1047l");     /* in on 47, out on 1047 */
  eq_text(&g, 0, 3, "zzz", "a 47 entry is undone by a 1047 exit");
  put(&g, "\033[?1047h\033[2;1Hw\033[?47l");
  eq_u("and the other way round", (unsigned)rc_in_alt(&g), 0, "");
  eq_text(&g, 0, 3, "zzz", "the row written to inside the alt is gone with it");
  eq_u("four switches", g.nAltSwitch, 4, "");

  /* Re-entering while already on the alt: MSFT discards the alt it has and makes a new one
     (screenInfo.cpp:1911-1922), which keeps the *main* snapshot and loses the alt's content. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "keep\r\n");
  put(&g, "\033[?1049h\033[1;1Htemp\033[?1049h");
  eq_text(&g, 0, 4, "    ", "the second entry re-clears");
  eq_u("and stays on the alt", (unsigned)rc_in_alt(&g), 1, "");
  put(&g, "\033[?1049l");
  eq_text(&g, 0, 4, "keep", "the main screen survived the alt's own replacement");

  /* Leaving a screen we are already on changes nothing -- and MSFT's version of this is a bug we decline
     to copy: `_SetAlternateScreenBufferMode(false)` calls CursorRestoreState() unconditionally
     (adaptDispatch.cpp:1750-1755), so a stray rmcup on the main screen teleports the cursor to whatever
     DECSC last saved. A pager that emits its exit sequences twice would move a cursor it never placed. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "abcd\r\n\r\n\r\n");
  put(&g, "\033[7\033[3;5H\033[?1049l");
  eq_u("no-op leave stays on main", (unsigned)rc_in_alt(&g), 0, "");
  eq_u("cursor unmoved by it: row", (unsigned)g.cy, 2, "ESC 7 saved (0,3); a restore would have moved it");
  eq_u("cursor unmoved by it: column", (unsigned)g.cx, 4, "");
  eq_u("and no switch was taken", g.nAltSwitch, 0, "a no-op is not an event");

  /* Cursor *visibility* is the one piece of state that does cross the boundary in MSFT's design: the alt
     inherits it on entry and hands it back on exit (screenInfo.cpp:1952-1957). There is one cursor in
     this model, so that behaviour is free -- and it is asserted here because it is surprising: a program
     that hides the cursor and quits leaves it hidden. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[?1049h\033[?25l\033[?1049l");
  eq_u("hidden inside the alt, hidden outside", (unsigned)g.cursorVisible, 0, "as upstream ships it");

  /* A hard reset leaves the alt before it resets anything, so the alt's text cannot survive into the main
     screen (adaptDispatch.cpp:3042-3049). And the reset is not a no-op any more: ConEmu's FullReset drops
     every line with ScrollScreen(-dwSize.Y) (Ansi.cpp:2025-2042, "Easy way to drop all lines"), which is
     the erase this model used to skip while it treated RIS as attributes-only. Both halves are pinned --
     the alt is left, and the screen it lands on is dropped along with its own rows. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "main\r\n\033[?1049h\033[1;1Hgone\r\nmore\033c");
  eq_u("RIS left the alt", (unsigned)rc_in_alt(&g), 0, "");
  eq_text(&g, 0, 4, "    ", "the reset took the main screen's rows with it, as upstream's does");
  eq_text(&g, 1, 4, "    ", "and the alt's text went with the alt instead of leaking here");

  /* The scroll is the case the whole design turns on. A viewport scroll on the main screen is queued and
     spent on a window slide or a buffer scroll (Paint.cpp rule 1) because those rows are still wanted
     above the window; the alt has no rows above it, so nothing is queued and the moved rows have to be
     repainted instead. plan_alt() is the half of that which says what reaches the console. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "1\r\n2\r\n3\r\n4");
  put(&g, "\r\n");
  eq_u("on the main screen a scroll is queued", (unsigned)g.pendingScrolls, 1, "the slide is free");
  put(&g, "\033[?1049h");
  eq_u("entering the alt drops the queue", (unsigned)g.pendingScrolls, 0,
       "the window does not move for a screen that is about to be blanked");
  put(&g, "\033[1;1Ha\r\nb\r\nc\r\nd\r\n");
  eq_u("an alt scroll is not queued", (unsigned)g.pendingScrolls, 0, "there is no scrollback to slide into");
  eq_text(&g, 0, 1, "b", "the row that left the alt's top is gone (xterm and MSFT alike)");
  eq_text(&g, 2, 1, "d", "and the rest moved up");
  eq_text(&g, 3, 1, " ", "the row scrolled in at the bottom is blank in the current attribute");
  put(&g, "\033[?1049l");
  eq_u("leaving drops the queue the same way", (unsigned)g.pendingScrolls, 0, "");
  eq_text(&g, 0, 1, "2", "the alt's rows went with it; the main screen's are back where they were");
  eq_text(&g, 2, 1, "4", "");
  eq_text(&g, 3, 1, " ", "its own scrolled-in row, from before the switch");

  /* The scrollback above the viewport is not part of the switch: the snapshot is the viewport's rows and
     nothing else, so a program that fills the screen cannot eat the lines the prompt scrolled through. */
  rc_reset_hist(&g, 20, 4, 4, 0x07);
  put(&g, "gutter\r\n\r\n\r\n\r\n");               /* one line pushed into the gutter, none into row 7 */
  eq_u("a gutter row exists", (unsigned)g.pendingScrolls, 1, "setup");
  rc_clear_dirty(&g);
  put(&g, "\033[?1049h");
  eq_text(&g, 3, 6, "gutter", "the alt blanked the viewport and left the scrollback alone");
  eq_u("the gutter row is not dirty", (unsigned)rc_row_dirty(&g, 3), 0, "nothing about it changed");
  eq_u("the viewport is", (unsigned)rc_row_dirty(&g, 4), 1, "");
  put(&g, "altalt");
  /* The scroll is the case this comment has been asserting without a witness. `rc_reset` -- the shape every
     other alt leg in this file uses -- has no gutter, so there `top == 0` and rotating the viewport is
     indistinguishable from rotating the model: an arm that scrolls the whole model while in the alt came
     back green until this leg existed. With four rows of scrollback above the viewport, the difference is
     on the screen: the alt's own rows move, its top row loses what left it, a blank comes in at its bottom,
     and "gutter" above row 4 does not move. Rotating the model instead pulls the scrollback into the alt and
     prints a program's first screenful over the user's history. Render.java's "the alt's blanking stopped at
     the window" is the same claim on a real console; this is the version the host gate can reach. */
  put(&g, "\033[2J");                            /* a known-empty alt, and 2J stops at the viewport by I25 */
  put(&g, "\033[1;1HA\033[4;1HD");                /* the alt's first row and its last */
  put(&g, "\r\n");                                /* at the alt's bottom: this one scrolls */
  eq_text(&g, 6, 1, "D", "the alt's own rows moved up");
  eq_text(&g, 7, 1, " ", "and a blank came in at its bottom");
  eq_text(&g, 4, 1, " ", "the row that left the alt's top is gone for good");
  eq_text(&g, 3, 6, "gutter", "and the scrollback above the alt is not part of its scroll");
  put(&g, "\033[?1049l");
  eq_text(&g, 3, 6, "gutter", "and it is still there afterwards");

  /* A handle is reused across resizes, and a reset must not come back on the alt -- the geometry the
     snapshot was taken with is gone with the rows it held. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[?1049h");
  rc_reset(&g, 40, 8, 0x07);
  eq_u("a reset starts on the main screen", (unsigned)rc_in_alt(&g), 0, "");
  eq_u("with no switch taken to get there", g.nAltSwitch, 0, "the counters describe this model, not the last");
  put(&g, "\033[?1049l");
  eq_u("and leaving an alt we never entered is still a no-op", g.nAltSwitch, 0, "");
}

static void geo_lines()
{
  static RcGrid g;
  rc_reset(&g, 8, 4, 0x07);
  put(&g, "aaa\r\nbbb\r\nccc");
  eq_text(&g, 0, 3, "aaa", "setup");
  eq_text(&g, 2, 3, "ccc", "setup");
  put(&g, "\033[2;1H\033[L");
  eq_text(&g, 0, 3, "aaa", "IL leaves the lines above the cursor alone");
  eq_text(&g, 1, 3, "   ", "IL opens a blank line at the cursor");
  eq_text(&g, 2, 3, "bbb", "and pushes the line under it down");
  eq_text(&g, 3, 3, "ccc", "one row further");
  put(&g, "\033[2;1H\033[M");
  eq_text(&g, 1, 3, "bbb", "DL pulls it back up");
  eq_text(&g, 2, 3, "ccc", "");
  put(&g, "\033[1;1H\033[2M");
  eq_text(&g, 0, 3, "ccc", "DL 2 from the top");
  eq_text(&g, 1, 3, "   ", "the two blanks land at the bottom");
  eq_u("DL left row 3 blank", RC_CELLS(&g, 3)[0].ch, ' ', "");

  /* IL and DL take the cursor to the start of the row they acted on, and keep the row. This is not a
     courtesy to a program that happens to sit at column 0: MSFT states it as the control's own contract
     ("The IL and DL controls are also expected to move the cursor to the left margin",
     adaptDispatch.cpp:2150) and ghostty does it in the `defer` of both functions
     (`cursorAbsolute(scrolling_region.left, start_y)`, Terminal.zig:2977 and :3151). The application that
     cares is the one redrawing a table: it walks the cursor in to a column, deletes the row, and writes the
     replacement from wherever the cursor ended up -- with the column kept, every cell of that row lands n
     columns off, and the drift repeats per row. */
  rc_reset(&g, 8, 4, 0x07);
  put(&g, "aaa\r\nbbb\r\nccc");
  put(&g, "\033[2;4H");                                /* row 1, three columns in */
  put(&g, "\033[1M");
  eq_u("DL homes the cursor", (unsigned)g.cx, 0, "the left margin, which is column 0 without DECVSSM");
  eq_u("and leaves it on the row it deleted from", (unsigned)g.cy, 1, "");
  eq_text(&g, 1, 3, "ccc", "the delete itself happened");
  put(&g, "\033[3;6H");
  put(&g, "\033[1L");
  eq_u("IL homes it the same way", (unsigned)g.cx, 0, "");
  eq_u("on its own row", (unsigned)g.cy, 2, "");
  eq_text(&g, 1, 3, "ccc", "and pushed nothing that the cursor left behind");

  /* Inside a region the same rule holds, because the region is vertical only: the left margin is still 0.
     The content is placed with CUP rather than newlines, so no line feed here can scroll the region that
     is already set. */
  rc_reset(&g, 8, 5, 0x07);
  put(&g, "\033[2;4r");
  put(&g, "\033[1;1H1\033[2;1H2\033[3;1H3\033[4;1H4\033[5;1H5");
  put(&g, "\033[3;5H\033[1M");
  eq_u("DL in a region homes the cursor too", (unsigned)g.cx, 0, "");
  eq_u("and stays on its row", (unsigned)g.cy, 2, "");
  eq_text(&g, 2, 1, "4", "the region's rows moved");
  eq_text(&g, 0, 1, "1", "the row above the region did not");
  put(&g, "\033[1;7H");                                 /* above the region, on the row it gave up */
  put(&g, "\033[1M");
  eq_u("a cursor the region refused keeps its column", (unsigned)g.cx, 6,
       "IL/DL outside the margins do nothing at all, cursor included");
  eq_u("and its row", (unsigned)g.cy, 0, "");
  eq_text(&g, 0, 1, "1", "and nothing moved underneath it");
}

/* ------------------------------------ 4''. tab stops: a table, not arithmetic ---------------------- */
/* Until #70 `\t` was `((cx + 8) >> 3) << 3` -- correct only while every stop sits where the default
   interval put it, which is what made `ESC H` (set a stop), `CSI Ps g` (clear them), `CSI Ps Z` (back up)
   and `CSI Ps I` (skip forward) all unspeakable: there was no state for them to talk about. The rulings here
   are the references', and the one place they disagree is named in the line that depends on it:
   MSFT keeps one `_tabStopColumns` table on the terminal (`adaptDispatch.cpp:2649`, walked forward at
   `:2677` and back at `:2720`, extended on resize at `:2805-2815`), ghostty keeps one on the Terminal
   (`Tabstops.zig`'s bit set, `Terminal.zig:56`, `:2295-2309`), so **both share it between the main and the
   alternate screen**; both materialize the defaults at columns 8, 16, ... below the width; both stop a
   forward tab at the last column when no stop is left rather than wrapping (MSFT's `maxColumn`, ghostty's
   `nextColumn`); and `CSI 5 g` (DECST8C) means "restore every-8" for both (`DispatchTypes.hpp:579-582`
   names the value 5 `SetEvery8Columns`, ghostty resets to `TABSTOP_INTERVAL` at `Terminal.zig:2309`).
   Where they split: ghostty rebuilds the table when the column count changes (`:4019`, `:4082` -- custom
   stops are lost) while MSFT only extends it (`:2805`, so a stop you set survives a widening and a
   narrowing); we follow MSFT, because our own resize already treats application-set state as carrying over
   (`RenderJni.cpp`'s build_model keeps the palette and the OSC 9 face for the same reason). */
static void geo_tabs()
{
  static RcGrid g;

  /* The defaults, and the fallback when there is nothing left to run to. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\t");
  eq_u("a tab from the margin reaches the first default stop", (unsigned)g.cx, 8, "columns 8, 16 (both references)");
  put(&g, "\t");
  eq_u("and the next one reaches the next", (unsigned)g.cx, 16, "");
  put(&g, "\t");
  eq_u("with no stop left, a tab ends on the last column", (unsigned)g.cx, 19,
       "MSFT's loop stops at maxColumn; it does not wrap to the next row");
  put(&g, "\t");
  eq_u("and a tab from the last column stays there", (unsigned)g.cx, 19,
       "the cursor is not pushed onto the next row by a tab");
  put(&g, "\033[1;9H\t");
  eq_u("a stop the cursor is standing on does not count", (unsigned)g.cx, 16,
       "the scan starts at cx+1 in both references");

  /* CHT and CBT are the same walk with a count and a direction. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[2I");
  eq_u("CHT of two lands two stops on", (unsigned)g.cx, 16, "`CSI Ps I`, Ps absent means one");
  put(&g, "\033[1I");
  eq_u("and CHT of one runs out and stops at the margin", (unsigned)g.cx, 19, "");
  put(&g, "\033[1;20H");
  eq_u("setup: the cursor on the last column", (unsigned)g.cx, 19, "");
  put(&g, "\033[Z");
  eq_u("CBT backs up to the stop before", (unsigned)g.cx, 16, "no `?1` needed: it is an ordinary CSI final");
  put(&g, "\033[Z");
  eq_u("one more backs up to the next", (unsigned)g.cx, 8, "");
  put(&g, "\033[2Z");
  eq_u("two at once walks past it to column 0", (unsigned)g.cx, 0,
       "the walk has no stop to find below 8, and 0 is where MSFT's minColumn leaves it");

  /* HTS adds a stop without erasing the defaults, and the added stop is the one a tab finds. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[1;6H\033H");
  eq_u("set tab stop leaves the cursor where it was", (unsigned)g.cx, 5, "`ESC H` does not move");
  put(&g, "\033[1;1H\t");
  eq_u("and the next tab finds it", (unsigned)g.cx, 5, "the table, not the arithmetic");
  put(&g, "\t");
  eq_u("while the default stop after it is still there", (unsigned)g.cx, 8,
       "MSFT materializes the defaults rather than replacing them (`_InitTabStopsForWidth`, :2799)");

  /* TBC: 0 clears the column the cursor is on, 3 clears everything and stops re-adding the defaults. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[1;9H\033[0g\t");
  eq_u("clearing the stop under the cursor makes the next tab skip it", (unsigned)g.cx, 16, "`CSI 0g`");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[3g\t");
  eq_u("after `CSI 3g` there is nowhere to go but the margin", (unsigned)g.cx, 19,
       "ghostty's `reset(0)` and MSFT's clear-with-flag-false are the same answer");
  put(&g, "\033[1;17H\033[Z");
  eq_u("and a back-tab with no stops goes to column 0", (unsigned)g.cx, 0, "");
  put(&g, "\033[5g\t");
  eq_u("DECST8C brings the every-8 defaults back", (unsigned)g.cx, 8,
       "the parameter value 5 means `SetEvery8Columns` (DispatchTypes.hpp:581)");

  /* A reset restores them; a soft reset does not. `ESC c` is RIS and takes no bracket -- the first version of
     these two legs fed `ESC [ c`, which is Device Attributes, and the model was right about it. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[3g\033c\t");
  eq_u("RIS puts the defaults back", (unsigned)g.cx, 8,
       "ghostty resets the table in its full reset (Terminal.zig:4943); MSFT's HardReset leaves it alone, and "
       "a session that cannot ask for its defaults back has no way to ask");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[3g\033[!p\t");
  eq_u("DECSTR does not", (unsigned)g.cx, 19, "neither reference touches tabs on a soft reset (I37's family)");

  /* The widen half: what `build_model` does with the table it carried across a rebuild, tested here because
     the model owns the rule and the seam only calls it. A rebuild is a fresh grid; the seam's job is to put
     the old table back and then ask this question, which is `rc_tabs_widen`'s whole contract. */
  {
    static uint8_t keep[RC_MAX_COLS];
    int keepDefaults;
    rc_reset(&g, 20, 4, 0x07);
    put(&g, "\033[1;6H\033H");                             /* claim column 5 */
    memcpy(keep, g.tabStop, sizeof keep);
    keepDefaults = g.tabsDefaults;
    rc_reset_hist(&g, 40, 4, 0, 0x07);                     /* the rebuild */
    memcpy(g.tabStop, keep, sizeof g.tabStop);
    g.tabsDefaults = keepDefaults;
    rc_tabs_widen(&g, 20);
    eq_u("a claimed stop is still claimed past a resize", (unsigned)g.tabStop[5], 1, "the part build_model carries");
    eq_u("a column that did not exist gets the interval", (unsigned)g.tabStop[24], 1,
         "MSFT fills only the newly allocated tail (:2805-2815), and so do we");
    eq_u("while a column that did is not re-decided", (unsigned)g.tabStop[16], 1, "it was a stop and stays one");
    put(&g, "\033[1;17H\033[0g");                          /* clear 16, then widen again */
    rc_reset_hist(&g, 60, 4, 0, 0x07);
    memcpy(g.tabStop, keep, sizeof g.tabStop);
    g.tabsDefaults = 1;
    g.tabStop[16] = 0;
    rc_tabs_widen(&g, 40);
    eq_u("a cleared stop below the old width is not resurrected", (unsigned)g.tabStop[16], 0,
         "the widen starts where the old grid ended, which is the whole point of passing `from`");
    eq_u("and the new tail does get the interval", (unsigned)g.tabStop[48], 1, "");
    rc_reset_hist(&g, 60, 4, 0, 0x07);
    memset(g.tabStop, 0, sizeof g.tabStop);
    g.tabsDefaults = 0;
    rc_tabs_widen(&g, 20);
    eq_u("with the flag down, a resize adds nothing", (unsigned)g.tabStop[24], 0,
         "rc_tabs_widen obeys the flag -- and it is asked about column 24, because a widen starts where the "
         "old grid ended: the first version of this leg read column 8, which no widen ever fills, so it could "
         "not have failed for any reason at all");
    /* And the flag got to 0 by being told to, not by this file writing it. An arm that leaves `CSI 3g`
       clearing the array but keeping the flag is invisible to every leg above, because an empty table and a
       live interval look identical until something rebuilds -- which is exactly the shape of #73's green arm,
       found the same way: by running an arm and watching it not bite. */
    rc_reset(&g, 20, 4, 0x07);
    put(&g, "\033[3g");
    keepDefaults = g.tabsDefaults;
    memcpy(keep, g.tabStop, sizeof keep);
    rc_reset_hist(&g, 60, 4, 0, 0x07);
    memcpy(g.tabStop, keep, sizeof g.tabStop);
    g.tabsDefaults = keepDefaults;
    rc_tabs_widen(&g, 20);
    eq_u("`CSI 3g` is what a resize then respects", (unsigned)g.tabStop[24], 0,
         "the clear is a claim about the interval, not just about the array -- and the interval's only "
         "exposure to a resize is the tail, so that is where the question has to be asked");
    rc_reset(&g, 20, 4, 0x07);
    put(&g, "\033[3g\033[5g");                           /* clear, then DECST8C */
    keepDefaults = g.tabsDefaults;
    memcpy(keep, g.tabStop, sizeof keep);
    rc_reset_hist(&g, 60, 4, 0, 0x07);
    memcpy(g.tabStop, keep, sizeof g.tabStop);
    g.tabsDefaults = keepDefaults;
    rc_tabs_widen(&g, 20);
    eq_u("and DECST8C puts it back, resize included", (unsigned)g.tabStop[24], 1,
         "the same column, the opposite answer, one `CSI 5g` apart");
  }

  /* One table for both screens: the ruling both references agree on, and the reason it is safe here is that
     the alternate screen is a different view of the same session rather than a different session. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[1;6H\033H\033[?1049h\033[1;1H");
  put(&g, "\t");
  eq_u("the custom stop is still there on the alternate screen", (unsigned)g.cx, 5,
       "MSFT's table is on the terminal (:2649), ghostty's on the Terminal (Terminal.zig:56)");
  put(&g, "\033[?1049l");
  eq_u("and leaving it does not lose the stop either", (unsigned)g.cx, 5, "the same table, both ways");

  /* A stop may sit on the leading half of a wide glyph. What must never happen is the tab *creating* an
     orphan: the write that follows is the narrow-over-leading case I35 already handles, and the grid oracle
     votes after every feed, so this leg is here to pin where the cursor lands, not what the pair does. */
  rc_reset(&g, 20, 4, 0x07);
  {
    static const uint16_t cjk = 0x4E00u;
    put(&g, "\033[1;9H");
    putu(&g, &cjk, 1);                               /* LEADING at 8, TRAILING at 9 */
  }
  eq_u("a wide glyph took two columns", (unsigned)g.cx, 10, "setup");
  put(&g, "\033[1;17H\033[Z");
  eq_u("back-tabs stop at 8, the leading half", (unsigned)g.cx, 8, "a stop the cursor can stand on");
  put(&g, "X");
  eq_u("writing there evicts its trailing half", (unsigned)RC_CELLS(&g, 0)[9].ch, ' ',
       "I35's narrow-over-leading rule: a narrow write on a LEADING clears the TRAILING it orphaned");
  eq_u("and the cursor moves on by one", (unsigned)g.cx, 9, "the glyph it replaced was two columns wide");
}

/* DECSTBM and everything that scrolls inside it (I25). The assertions are the oracle's own acceptance
   test, not the VT500 manual's: where ConEmu deviates -- a rejected region clears rather than ignores, a
   zero parameter clamps instead of defaulting, and setting a region homes nothing -- the deviation is what
   is pinned, because that is what the same bytes do on a ConEmu console today. */
static void geo_region()
{
  static RcGrid g;

  rc_reset(&g, 8, 5, 0x07);
  put(&g, "\033[2;4r");
  eq_u("region live", (unsigned)g.regSet, 1, "");
  eq_u("region top", (unsigned)g.regTop, 1, "1-based parameters, counted from the viewport");
  eq_u("region bottom", (unsigned)g.regBot, 3, "");
  eq_u("a region homes nothing", (unsigned)g.cy, 0, "SetScrollRegion has no SetConsoleCursorPosition");
  eq_u("and a modelled sequence leaves the frame trusted", (unsigned)g.modelSuspect, 0, "");

  put(&g, "\033[H1\033[2;1H2\033[3;1H3\033[4;1H4\033[5;1H5");
  put(&g, "\033[4;1HX\n");                       /* the line feed lands on the region's bottom row */
  eq_text(&g, 0, 1, "1", "the row above the region never moved");
  eq_text(&g, 1, 1, "3", "the region rotated up into the cursor row");
  eq_text(&g, 2, 1, "X", "");
  eq_text(&g, 3, 1, " ", "the blank opens at the region's bottom, not at the window's");
  eq_text(&g, 4, 1, "5", "and the row under it is untouched -- this is the Status-bar case");
  eq_u("a LF at the region bottom keeps its row", (unsigned)g.cy, 3, "");
  eq_u("a region scroll asks the console for nothing", (unsigned)g.pendingScrolls, 0,
       "only a whole-viewport scroll can be a window slide");
  eq_u("and is still counted as a scroll", g.nScrolls, 1, "");

  /* A rejected request must not *clear*. Both references ignore it -- MSFT states it outright at
     adaptDispatch.cpp:2242 ("an illegal combo (eg, 3;2r) is ignored") -- and ignoring is a different act from
     clearing: clearing hands the next line feed the whole viewport, which is the #47/#48 failure with a new
     trigger. Upstream clears (Ansi.cpp:3147-3150) and this arm mirrored it until every "upstream does the
     same" reason in these files was re-read for an independent one. */
  put(&g, "\033[3;2r");
  eq_u("top above bottom leaves the live region alone", (unsigned)g.regSet, 1, "");
  eq_u("at its own top", (unsigned)g.regTop, 1, "");
  eq_u("and its own bottom", (unsigned)g.regBot, 3, "");
  /* One parameter is legal and defaults the other edge to the viewport -- the case upstream's `ArgC >= 2`
     quietly turned into a reset. */
  put(&g, "\033[2r");
  eq_u("one argument names the top", (unsigned)g.regTop, 1, "row 2 of the viewport");
  eq_u("and the bottom defaults to the viewport's last row", (unsigned)g.regBot, 4, "");
  put(&g, "\033[r");
  eq_u("no argument is the reset form", (unsigned)g.regSet, 0, "");
  put(&g, "\033[1;99r");
  eq_u("a whole-viewport request is normalised away", (unsigned)g.regSet, 0,
       "whatever the parameter that got it there: the paths that carry history out of the gutter branch on this");
  /* The clamp is the split from MSFT, which rejects an out-of-range bottom outright (:2260). Clamping keeps
     the intent -- "scroll from row 3 down" -- and on a 3-row viewport that intent is a one-row region. */
  rc_reset(&g, 8, 5, 0x07);
  put(&g, "\033[4;99r");
  eq_u("a bottom past the viewport clamps instead of refusing", (unsigned)g.regSet, 1,
       "MSFT would ignore this whole request; the app asked for rows 4..end and that is what it gets");
  eq_u("top", (unsigned)g.regTop, 3, "");
  eq_u("bottom is the viewport's last row", (unsigned)g.regBot, 4, "");

  /* A zero parameter is accepted and clamps to the viewport's first row -- :4150's own comment. */
  rc_reset(&g, 8, 5, 0x07);
  put(&g, "\033[0;3r");
  eq_u("CSI 0;3r means CSI 1;3r: top", (unsigned)g.regTop, 0, "");
  eq_u("and bottom", (unsigned)g.regBot, 2, "");

  /* SU and SD go through the region-aware ScrollScreen (:1998-2010) and move no cursor. */
  rc_reset(&g, 8, 5, 0x07);
  put(&g, "\033[H1\033[2;1H2\033[3;1H3\033[4;1H4\033[5;1H5\033[2;4r\033[1;1H");
  put(&g, "\033[S");
  eq_text(&g, 0, 1, "1", "SU left the row above the region");
  eq_text(&g, 1, 1, "3", "and rotated the region");
  eq_text(&g, 2, 1, "4", "");
  eq_text(&g, 3, 1, " ", "");
  eq_text(&g, 4, 1, "5", "SU left the row below it");
  eq_u("SU moves no cursor", (unsigned)g.cy, 0, "");
  put(&g, "\033[T");
  eq_text(&g, 1, 1, " ", "SD pulls it back down");
  eq_text(&g, 2, 1, "3", "");
  eq_text(&g, 3, 1, "4", "");
  eq_u("SD moves no cursor either", (unsigned)g.cy, 0, "");

  /* RI: at the region's first row it inserts, everywhere else it is a plain move up. */
  put(&g, "\033[2;1H\033M");
  eq_text(&g, 1, 1, " ", "RI at the region top opened a blank there");
  eq_text(&g, 2, 1, " ", "and pushed the region down");
  eq_text(&g, 3, 1, "3", "the row that fell out of the region's bottom is gone");
  eq_u("RI spent no window scroll", (unsigned)g.pendingScrolls, 0, "");
  put(&g, "\033[4;1H\033M");
  eq_u("RI below the region top is only a move", (unsigned)g.cy, 2, "");

  /* IL and DL are confined to [cursor .. region bottom]; a cursor outside is refused, not clamped in. */
  rc_reset(&g, 8, 5, 0x07);
  put(&g, "\033[H1\033[2;1H2\033[3;1H3\033[4;1H4\033[5;1H5\033[2;4r");
  put(&g, "\033[1;1H\033[L");
  eq_text(&g, 0, 1, "1", "IL with the cursor above the region inserted nothing");
  eq_text(&g, 1, 1, "2", "");
  put(&g, "\033[5;1H\033[L");
  eq_text(&g, 4, 1, "5", "and IL below the region is refused too");
  put(&g, "\033[3;1H\033[L");
  eq_text(&g, 1, 1, "2", "the region's first row is untouched");
  eq_text(&g, 2, 1, " ", "IL blanks the cursor's row");
  eq_text(&g, 3, 1, "3", "and pushes the rest of the region down");
  eq_text(&g, 4, 1, "5", "not the window's last row");
  put(&g, "\033[3;1H\033[2M");
  eq_text(&g, 2, 1, " ", "DL 2 with one row left in the region");
  eq_text(&g, 3, 1, " ", "blanks the region's tail");
  eq_text(&g, 4, 1, "5", "and stops there: upstream fills dwSize.X * n cells from the cursor (Ansi.cpp:2152"
                         ") and would have written over this row");

  /* Relative vertical moves are clipped to the region (set_y's relative arms, Ansi.cpp:2913-2918), so a
     program that narrowed the screen cannot walk the cursor out of the rows it asked for. The oddity is
     upstream's, not ours: a cursor *below* the region moving up is stopped at the region's top, and one
     *above* it moving down reaches the region's bottom, because both arms clip rather than refuse. */
  rc_reset(&g, 8, 5, 0x07);
  put(&g, "\033[2;4r\033[1;3H");                    /* cursor on row 0, region rows 1..3 */
  put(&g, "\033[10B");
  eq_u("cursor down stops at the region bottom", (unsigned)g.cy, 3, "");
  put(&g, "\033[10A");
  eq_u("cursor up stops at the region top", (unsigned)g.cy, 1, "not at the window's first row");
  put(&g, "\033[10E");
  eq_u("CNL is clipped the same way", (unsigned)g.cy, 3, "");
  eq_u("and still homes the column", (unsigned)g.cx, 0, "");
  put(&g, "\033[10F");
  eq_u("and CPN", (unsigned)g.cy, 1, "");
  put(&g, "\033[1;1H\033[10A");
  eq_u("a cursor above the region still reaches the window top", (unsigned)g.cy, 0,
       "set_y's last arm: outside the region, clip to the buffer, not to the region");
  put(&g, "\033[5;1H\033[10B");
  eq_u("and one below it still reaches the window bottom", (unsigned)g.cy, 4, "");
  put(&g, "\033[r\033[1;3H\033[9999E");
  eq_u("with no region, a huge CNL reaches the window bottom", (unsigned)g.cy, 4,
       "this is jline's own startup write to a ConEmu (AbstractWindowsTerminal.java:181)");
  eq_u("and homes the column", (unsigned)g.cx, 0, "");
  eq_u("none of it scrolled", (unsigned)g.nScrolls, 0, "a clipped cursor move is not a line feed");

  /* A whole-viewport region still takes the gutter path, which is what every pre-DECSTBM witness uses. */
  rc_reset_hist(&g, 8, 3, 2, 0x07);
  put(&g, "\033[1;3r");
  eq_u("no region for a full-height request", (unsigned)g.regSet, 0, "");
  put(&g, "\033[3;1HZ\n");
  eq_u("so its LF asks the console to scroll", (unsigned)g.pendingScrolls, 1, "");
  rc_reset_hist(&g, 8, 3, 2, 0x07);
  put(&g, "\033[3;99r");
  eq_u("a region inside a guttered grid: top", (unsigned)g.regTop, 4, "the viewport's last model row");
  eq_u("bottom clamped", (unsigned)g.regBot, 4, "");
  put(&g, "\033[3;1HZ\n");
  eq_text(&g, 4, 1, " ", "one-row region: the LF blanked it in place");
  eq_u("and asked the console for nothing", (unsigned)g.pendingScrolls, 0, "");

  /* DL deletes rows **from the cursor down**, so the largest count with anything to delete is the number of
     rows below the cursor -- and the viewport's height is a different (bigger) number whenever the cursor is
     not on the viewport's top row. #74 found this by making every count name its limit: with eight gutter
     rows and the cursor two rows into the viewport, `CSI 9M` blanked the two rows **above** it and left its
     own row standing, which is text the application never offered to lose. IL never suffered it because its
     fill loop starts at the cursor; the defect was in the bound, not in the shape. */
  rc_reset_hist(&g, 4, 4, 8, 0x07);                    /* twelve model rows, the viewport the last four */
  put(&g, "\033[1;1Hr0\033[2;1Hr1\033[3;1Hr2\033[4;1Hr3");   /* CUP is viewport-relative: rows 8..11 */
  put(&g, "\033[3;1H\033[9M");
  eq_text(&g, 8, 4, "r0", "a delete of more rows than there are below the cursor reaches no higher");
  eq_text(&g, 9, 4, "r1", "");
  eq_text(&g, 10, 4, "", "the cursor's own row is the first thing erased");
  eq_text(&g, 11, 4, "", "and the row under it is the last");
  rc_reset_hist(&g, 4, 4, 8, 0x07);
  put(&g, "\033[1;1Hr0\033[2;1Hr1\033[3;1Hr2\033[4;1Hr3");
  put(&g, "\033[3;1H\033[9L");
  eq_text(&g, 8, 4, "r0", "IL confined the same way, from the same row");
  eq_text(&g, 9, 4, "r1", "");
  eq_text(&g, 10, 4, "", "an insert taller than the space below blanks that space and nothing more");
  eq_text(&g, 11, 4, "", "");

  /* ?1048 shares the one saved position that ESC 7 and ?1049 use (XTermSaveRestoreCursor, :4176+). */
  rc_reset(&g, 8, 4, 0x07);
  put(&g, "\033[3;5H\033[?1048h\033[1;1H");
  eq_u("moved away", (unsigned)g.cy, 0, "");
  put(&g, "\033[?1048l");
  eq_u("?1048l restored the row", (unsigned)g.cy, 2, "");
  eq_u("and the column", (unsigned)g.cx, 4, "");
  put(&g, "\033[1;1H\033[7\033[2;2H\033[?1048h\033[8");
  eq_u("and DECSC finds the ?1048 save, not its own", (unsigned)g.cy, 1, "one slot, so the later save won");
  eq_u("in both columns", (unsigned)g.cx, 1, "XTermSaveRestoreCursor keeps one position, not two");

  /* A hard reset drops the region, the modes, the shape and the text: the viewport's worth of rows goes up
     into history and the cursor comes home. It is the half of the pair that DECSTR may not do, which is why
     the two are asserted side by side -- they used to be one call. */
  rc_reset(&g, 8, 3, 0x07);
  put(&g, "\033[2;3r\033[?25l\033[1 qX\033c");
  eq_u("RIS cleared the region", (unsigned)g.regSet, 0, "");
  eq_u("RIS showed the cursor", (unsigned)g.cursorVisible, 1, "");
  eq_u("RIS stopped claiming a shape", (unsigned)g.cursorShape, -1, "");
  eq_u("RIS homed the cursor", (unsigned)g.cy, 0, "");
  eq_text(&g, 0, 1, " ", "RIS blanked the viewport, not just the attributes");
  eq_u("RIS spent the scroll that a blank viewport owes", (unsigned)g.pendingScrolls, 3, "");
  rc_reset(&g, 8, 3, 0x07);
  put(&g, "A\033[!p");
  eq_text(&g, 0, 1, "A", "DECSTR erases nothing -- MSFT's SoftReset has no FillRect, no scroll and no buffer "
                         "switch in its whole body (:2984-3020, against HardReset's :3028-3050)");
  eq_u("and moves no cursor", (unsigned)g.cy, 0, "");
  eq_u("and asks the console for no scroll at all", (unsigned)g.pendingScrolls, 0, "");
  eq_u("the DECSTR that took effect leaves no count", g.nUnsupported[RC_UN_SUP], 0,
       "`CSI !p` with no arguments is the only spelling either leg acts on");
  rc_reset(&g, 8, 3, 0x07);
  put(&g, "A\033[1!p");
  eq_text(&g, 0, 1, "A", "and upstream gates that on ArgC == 0 (:3645)");
  eq_u("while the spelling it drops leaves one", g.nUnsupported[RC_UN_SUP], 1,
       "a parameter is enough to reach the same DumpUnknownEscape (:3650-3653) as a final nobody knows");

  /* A private byte and an intermediate are two ranges of the *same* accumulating buffer upstream:
     Ansi.cpp:1788 appends every byte that is neither a digit, a ';' nor a final into Pvt -- 0x20..0x2F and
     0x30..0x3F alike -- and each consumer then compares the buffer's length (`ArgC == 0 && PvtLen == 1 &&
     Pvt[0] == L'!'`, :3645). So `? ! p` has a two-byte Pvt there and is not a soft reset. This model kept
     the two ranges in two independent slots and tested only the interim, which let the hybrid spelling
     reset a console. DECSCUSR's arm has carried the private-byte gate all along (:1213); this arm never
     got the same test, because with one interim slot there was nothing to distinguish "?" from "!". */
  rc_reset(&g, 8, 3, 0x07);
  put(&g, "A\033[?!p");
  eq_text(&g, 0, 1, "A", "`CSI ? ! p` resets nothing -- upstream's Pvt would read \"?!\"");
  eq_u("and the refusal is counted", g.nUnsupported[RC_UN_SUP], 1,
       "an unknown final with a body we did not run, exactly as the parameterised spelling above");

  /* The hole this closes was a bare `break`: `CSI p` was consumed, did nothing, and said nothing, so the
     census could not tell "the application asked for a soft reset neither leg carries" from "the
     application never wrote one". Both spellings below are the same inert else upstream, and both must
     now be numbers. */
  rc_reset(&g, 8, 3, 0x07);
  put(&g, "\033[p\033[61p");
  eq_text(&g, 0, 1, " ", "and neither of them paints, moves or clears anything beyond that");
  eq_u("a bare `p` and `61p` are each counted", g.nUnsupported[RC_UN_SUP], 2, "neither is DECSTR");
  eq_u("counted without suspicion", (unsigned)g.modelSuspect, 0,
       "the reach is known-inert, so no full repaint is bought");

  /* The census and the suspicion: a known-inert sequence is counted and trusted; a final byte neither
     this switch nor ConEmu has a case for is neither. */
  rc_reset(&g, 8, 3, 0x07);
  put(&g, "\033[?12h\033[?7l\033[?1h\033[?2004h\033[?1000h\033[?1005l\033[?7h");
  eq_u("?12 and ?1 are counted as modes", g.nUnsupported[RC_UN_MODE], 2,
       "?7 left this list when DECAWM became a modelled mode (I35); it is still in the stream above, which"
       " is the proof -- the count fell by exactly its two spellings");
  eq_u("and the mode is back on", (unsigned)g.wrapMode, 1, "the trailing `?7h` is part of the stream, not a fix-up");
  eq_u("bracketed paste has its own bucket", g.nUnsupported[RC_UN_DECBP], 1, "");
  eq_u("the mouse family has its own, and ?1005 is in it", g.nUnsupported[RC_UN_MOUSE], 2, "");
  eq_u("none of them doubts the frame", (unsigned)g.modelSuspect, 0,
       "this is the full repaint that used to be paid for a cnorm");
  put(&g, "\033[1\\");
  eq_u("an unknown final is counted", g.nUnsupported[RC_UN_SUP], 1, "no case here, none upstream");
  eq_u("and makes the frame suspect", (unsigned)g.modelSuspect, 1, "S3: the reach is not known");
  rc_clear_model_suspect(&g);
  put(&g, "\033[Z");
  eq_u("CBT is modelled now and spends no count", g.nUnsupported[RC_UN_SUP], 1,
       "#70 gave the back-tab a table to walk; while `ESC H` was ignored there was no stop for it to find, and "
       "refusing was the truth -- this assertion is the census noticing that the sentence changed");
  eq_u("and it still cannot make the frame suspect", (unsigned)g.modelSuspect, 0,
       "a walk over state this model owns is the opposite of an unknown reach");
}

/* The status bar (I25's consumer). This replays the byte stream the host's status line actually produces
   -- `ESC 7`, `csr(0, n)`, `ESC 8`, then the lines at the bottom -- so the contract the feature depends on
   is pinned as a sequence of bytes rather than as a description: the caller's cursor never lands in the
   status rows, ordinary output cannot scroll those rows away, and the two spellings of "undo the region"
   are told apart. The last pair is why this case exists: `csr` carries `%i`, so the call the reference
   implementation uses to clear the region compiles to `CSI 1;1r`, which is a one-row region, not a reset. */
static void status_bar()
{
  static RcGrid g;

  rc_reset(&g, 8, 5, 0x07);
  put(&g, "\033[4;1HZ");                           /* the caller's cursor, deliberately mid-screen */
  put(&g, "\033" "7");                             /* DECSC: caps sc=\E7, no bracket */
  put(&g, "\033[1;4r");                            /* csr(0, 3): the viewport minus the status row */
  put(&g, "\033" "8");                             /* DECRC */
  eq_u("the region is the viewport minus the status row", (unsigned)g.regTop, 0, "model rows 0..3 scroll");
  eq_u("bottom", (unsigned)g.regBot, 3, "");
  eq_u("and the caller came back from the save", (unsigned)g.cy, 3, "row 3, not the row the region ends on");
  eq_u("in the column it was in", (unsigned)g.cx, 1, "'Z' had already moved it one column right");

  put(&g, "\033[5;1HSTATUS");                      /* cup(rows-1, 0) then the line itself */
  put(&g, "\033" "8");
  eq_text(&g, 4, 8, "STATUS  ", "the bar is the viewport's last row, written to its full width");
  eq_u("the cursor did not stay in the status row", (unsigned)g.cy, 3,
       "this is the reference implementation's fault: a region change whose save it never replays");
  eq_u("at the column it was saved at", (unsigned)g.cx, 1, "");
  eq_u("painting a status line scrolled nothing", (unsigned)g.nScrolls, 0, "");
  eq_u("and asked the console for no scroll", (unsigned)g.pendingScrolls, 0,
       "row 4 is outside the region, so writing it cannot move the window");

  /* Ordinary output while the bar is up: the rows above rotate, the bar does not. */
  put(&g, "\033[1;1HA\033[2;1HB\033[3;1HC\033[4;1HD\n");
  eq_text(&g, 0, 1, "B", "the region scrolled under the cursor at its bottom edge");
  eq_text(&g, 2, 1, "D", "");
  eq_text(&g, 3, 1, " ", "the LF blanked the row the cursor left");
  eq_text(&g, 4, 6, "STATUS", "the bar survived the scroll -- this is the whole point of the region");
  eq_u("one region scroll", (unsigned)g.nScrolls, 1, "");
  eq_u("no window scroll", (unsigned)g.pendingScrolls, 0, "");

  /* Taking the bar away. Both spellings appear in the wild, and they are not the same write. */
  put(&g, "\033" "7\033[1;1r\033" "8");
  eq_u("csr(0, 0) through %i is a region, not a reset", (unsigned)g.regSet, 1,
       "Status.java's reset; Display.java:112 turns a 0x0 size into rows=1 -- the same trap, one layer down");
  eq_u("a one-row region: top", (unsigned)g.regTop, 0, "");
  eq_u("bottom", (unsigned)g.regBot, 0, "so only the viewport's first row can scroll any more");
  put(&g, "\033" "7\033[r\033" "8");
  eq_u("the bare form is the reset", (unsigned)g.regSet, 0, "");
  eq_u("and it moved nothing", (unsigned)g.cy, 3, "`CSI r` homes no cursor (Ansi.cpp:4146-4174)");

  /* The shape the field actually draws: two lines, not one. `Console.setStatus` hands Status a rule of
     dashes and the text, so Status.update reserves the viewport's last two rows, narrows the region to
     everything above them (`csr(0, rows-3)`), addresses row rows-2, and separates the lines with a real
     newline. That newline reaches the model with the cursor BELOW the region's bottom margin, where a
     line feed must simply move down and scroll nothing: MSFT's `_DoLineFeed` scrolls only at
     `y == bottomMargin` and otherwise clamps to the page bottom (adaptDispatch.cpp:2443-2453); ConEmu's
     `set_y` clip leaves a caller outside the region to the viewport too (Ansi.cpp:2913-2918), which is
     the answer `move_row` at Render.cpp:742 already gives. This case exists because the two answers
     differ, and on a live 49-row window the wrong one collapsed the bar onto a single row and rotated
     the session's text away one row per newline. */
  static RcGrid g2;
  rc_reset(&g2, 20, 6, 0x07);
  put(&g2, "\033[1;1HAAAA\nBBBB\nCCCC\nDDDD");
  put(&g2, "\033" "7\033[1;4r\033" "8");                  /* csr(0, 3): rows 0..3 scroll, 4 and 5 are the bar */
  put(&g2, "\033[5;1H----------\n==========");            /* cup(4, 0), the rule, a newline, the text */
  /* `upto` is 11, not 20: eq_text walks `want` byte by byte and a shorter want would read the next
     literal in the pool, so the count is the want's own length. The 11th cell is the space after the
     write -- enough to pin that neither line ran past its row. */
  eq_text(&g2, 4, 11, "---------- ", "the bar's first row keeps its row, and ends there");
  eq_text(&g2, 5, 11, "========== ", "the newline between the bar's lines moved down, it did not scroll");
  eq_text(&g2, 0, 5, "AAAA ", "row 0 of the region is where the caller left it");
  eq_text(&g2, 3, 5, "DDDD ", "and so is its bottom row -- nothing rotated");
  eq_u("a line feed below the region scrolled nothing", (unsigned)g2.nScrolls, 0, "");
  eq_u("the cursor is on the bar's second row", (unsigned)g2.cy, 5, "");
  put(&g2, "\n");                                         /* the newline that ends the last bar row */
  eq_u("at the page bottom, still below the region, still no scroll", (unsigned)g2.nScrolls, 0,
       "MSFT clamps to page.Bottom() - 1 rather than cycling the buffer (:2448-2452)");
  eq_u("the cursor stays on the last row", (unsigned)g2.cy, 5, "");
  eq_text(&g2, 5, 11, "========== ", "the bar's last row survived its own trailing newline");
}

/* The character-editing family, which the shipped output never sends but an application on this terminal
   may: ICH, DCH, and the DECSCUSR parameter the painter turns into a cursor height. */
/* IRM (#77, I40): insert mode is a write-side claim on the same primitive an ICH performs, so its legs are
   the write path -- which is the path that had never been asked to shift anything before. */
/* `CSI Ps t` (#79, I42): the window operations whose answer or effect this model really owns, and the ones
   it refuses out of a principle rather than a gap. The reply *bytes* are the seam's work and are witnessed
   live (Render.java's caseWindowOps); what the host gate can pin is which questions arm an answer at all, and
   what the title stack does to the string the painter is about to apply. */
static void geo_windowops()
{
  static RcGrid g;
  uint16_t out[RC_TITLE_MAX];

  /* 18t: the two numbers are the model's own viewport, so this is a measurement and not an estimate. The
     grid has to be built with a gutter for the rows half of that to be a witness at all -- with `rc_reset`
     the model's `rows` IS `winRows`, and an arm that answers with the wrong one of the two comes back green
     (it did, first time). Same lesson as #70's resize arm and #77's alt-gutter arm: build the case where the
     two designs differ, or the leg proves nothing. */
  rc_reset_hist(&g, 132, 37, 13, 0x07);
  put(&g, "\033[18t");
  eq_u("18t arms exactly one answer", (unsigned)rc_report_pending(&g), 1, "");
  {
    struct RcReportItem it;
    rc_report_take(&g, &it);
    eq_u("and it is the window-op kind", (unsigned)it.kind, (unsigned)RC_REP_WINOP, "");
    eq_u("rows first, the viewport's own", (unsigned)it.mode, 37,
         "the model is 50 rows here and the gutter is not text area: 37 is the answer that can be checked");
    eq_u("columns second, the model row's width", (unsigned)it.status, 132,
         "I7: a model row IS the buffer row, so the answer is the width an application draws into");
  }
  eq_u("with nothing voted", (unsigned)un(&g, RC_UN_REPORT), 0, "it was answered, not skipped");
  put(&g, "\033[18;5t");
  eq_u("a parameter behind the function is not a query", (unsigned)rc_report_pending(&g), 0,
       "ghostty requires `params.len == 1` here for the same reason (stream.zig:2398-2402)");
  eq_u("and that goes on the record", (unsigned)un(&g, RC_UN_REPORT), 1, "");
  put(&g, "\033[1;18t");
  eq_u("a parameter in front of the function is not the function either", (unsigned)rc_report_pending(&g), 0,
       "`CSI 1;18t` is a resize request's shape; the function is args[0]");
  eq_u("and that counts too", (unsigned)un(&g, RC_UN_REPORT), 2, "");

  /* The pixel and screen families: silence, chosen and counted. */
  rc_reset(&g, 80, 24, 0x07);
  put(&g, "\033[19t\033[14t\033[16t");
  eq_u("none of the three answers", (unsigned)rc_report_pending(&g), 0,
       "19t would report the same two numbers as 18t under a prefix that promises a second geometry, and "
       "14t/16t have no pixel source here that is not a nominal constant");
  eq_u("and all three are counted", (unsigned)un(&g, RC_UN_REPORT), 3,
       "the count is how a rollout learns whether an application asked");

  /* The title stack. A push saves what this parser last applied, so the pair has to be run against the
     string the painter is holding, not against a field. */
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]0;first\007");
  eq_u("the title is pending", (unsigned)rc_title_pending(&g), 1, "setup");
  eq_u("and it is five units", (unsigned)rc_title_take(&g, out, RC_TITLE_MAX), 5, "");
  put(&g, "\033[22;0t");
  eq_u("a push of a title this parser applied spends no refusal", (unsigned)un(&g, RC_UN_REPORT), 0, "");
  put(&g, "\033]0;second\007");
  eq_u("the second title is pending too", (unsigned)rc_title_pending(&g), 1, "setup");
  rc_title_take(&g, out, RC_TITLE_MAX);
  put(&g, "\033[23;0t");
  eq_u("and the pop hands the first one back to the painter", (unsigned)rc_title_pending(&g), 1,
       "restoring a title is the same act as setting one -- one sink, no second path to drift");
  eq_u("five units, as pushed", (unsigned)rc_title_take(&g, out, RC_TITLE_MAX), 5, "");
  eq_u("and they spell the pushed title", out[0], 'f', "");

  /* The two cases where a pop has nothing honest to give back. Both must leave the console's own title
     alone, which for the model means: no pending title at all. */
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033[23;2t");
  eq_u("a pop with an empty stack arms nothing", (unsigned)rc_title_pending(&g), 0,
       "the only value it could restore is one this library never observed");
  eq_u("and says so", (unsigned)un(&g, RC_UN_REPORT), 1, "");
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033[22;2t\033[23;2t");
  eq_u("a push before any title was ever applied restores nothing either",
       (unsigned)rc_title_pending(&g), 0, "length -1 is not the same fact as an empty title (RC_TITLE_MAX)");
  eq_u("and that pair is the one honest answer", (unsigned)un(&g, RC_UN_REPORT), 1,
       "the pop found no saved string");

  /* And what "nothing known" is *not*: an OSC 0 whose payload is empty never becomes a title in this build at
     all (`pending=0, nTitleSet=0` -- the OSC family requires a field), so the state the pop above refused is
     the same one an empty OSC 0 leaves behind. The -1 in `nTitle` is still the right encoding, because the
     day an empty title does apply it lands at length 0 and this pair of legs splits. */
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]0;\007\033[22;1t\033[23;1t");
  eq_u("an empty OSC 0 is no title, so there is nothing to restore",
       (unsigned)rc_title_pending(&g), 0, "");
  eq_u("and the pop of what it saved refuses once", (unsigned)un(&g, RC_UN_REPORT), 1, "");

  /* Depth two, and the eviction order. Pushing a third saves CCC and drops AAA, so the first pop returns the
     newest (CCC), the second returns BBB -- and AAA is gone, which is what a bounded ring *means*. The live
     leg cannot see this distinction, because the console keeps no history either. */
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]0;AAA\007\033[22;0t");
  put(&g, "\033]0;BBB\007\033[22;0t");
  put(&g, "\033]0;CCC\007\033[22;0t");        /* third push: the oldest goes */
  rc_title_take(&g, out, RC_TITLE_MAX);
  put(&g, "\033[23;0t");
  eq_u("a pop is pending", (unsigned)rc_title_pending(&g), 1, "setup");
  eq_u("three deep restores the newest", (unsigned)rc_title_take(&g, out, RC_TITLE_MAX), 3, "");
  eq_u("which is CCC", out[0], 'C', "LIFO, as xterm's stack is");
  put(&g, "\033[23;0t");
  eq_u("and the next is BBB", (unsigned)rc_title_pending(&g), 1, "");
  rc_title_take(&g, out, RC_TITLE_MAX);
  eq_u("restored as BBB", out[0], 'B', "the depth held");
  put(&g, "\033[23;0t");
  eq_u("the third pop finds the stack empty and says so", (unsigned)un(&g, RC_UN_REPORT), 1,
       "AAA was evicted, not forgotten-then-restored: a bounded ring is a decision, and this leg is where"
       " it is written down");
  eq_u("with nothing pending", (unsigned)rc_title_pending(&g), 0, "");

  /* The sub-codes that name an icon xterm-format this console does not have. */
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033[22;3t");
  eq_u("`22;3t` is xterm-format, and is not swallowed silently", (unsigned)un(&g, RC_UN_REPORT), 1, "");
  put(&g, "\033[22;1t");
  eq_u("while 1 (title) is accepted, because the console's one string IS the title",
       (unsigned)un(&g, RC_UN_REPORT), 1, "no new vote from the accepted form");
}

static void geo_irm()
{
  static RcGrid g;

  /* The mode, in both spellings. DEC's private `?4` and the ANSI 4 both references register are the same
     bit, so the second must act like the first rather than be counted as a mode nobody knows. */
  rc_reset(&g, 10, 3, 0x07);
  put(&g, "ABCD");
  put(&g, "\033[1;2H\033[?4hX");
  eq_text(&g, 0, 8, "AXBCD   ", "a written glyph opens room for itself and the tail rides right");
  eq_u("and the cursor stands after the glyph it wrote", (unsigned)g.cx, 2, "");
  put(&g, "Y");
  eq_text(&g, 0, 8, "AXYBCD  ", "the next one pushes again from where the cursor is now");
  put(&g, "\033[?4lZ");
  eq_text(&g, 0, 8, "AXYZCD  ", "`?4l` is back to overwriting: the cell under the cursor is replaced, not moved");
  eq_u("and the row's tail did not ride along", (unsigned)g.cx, 4, "one column for one glyph, no push");

  rc_reset(&g, 10, 3, 0x07);
  put(&g, "ABCD");
  put(&g, "\033[1;2H\033[4hX");
  eq_text(&g, 0, 8, "AXBCD   ", "the ANSI spelling of the same mode (MSFT registers 4, ghostty tags it ansi)");
  eq_u("and it was not counted as an unknown mode", (unsigned)un(&g, RC_UN_MODE), 0, "");

  /* The margin, where there is nothing to push. ghostty's print takes the insert arm only while
     `cursor.x + width < cols` (Terminal.zig:1522-1528); a glyph that would run off the end overwrites and
     then wraps under the ordinary rule, because inserting zero columns is not a thing. */
  rc_reset(&g, 6, 3, 0x07);
  put(&g, "\033[?4hABCDEF");
  eq_text(&g, 0, 6, "ABCDEF", "each glyph opened room for itself until the row was full, and the last one "
                              "reached the margin where there is nothing left to push");
  put(&g, "\033[1;5HZ");                /* one column short of the end: the insert runs, and the tail falls off */
  eq_text(&g, 0, 6, "ABCDZE", "E rode right over F, and F is gone: an insert that kept the row's length kept it");
  put(&g, "\033[1;6HY");                /* at the margin there is nothing to push */
  eq_text(&g, 0, 6, "ABCDZY", "so the write overwrites the last cell instead of inserting zero columns");

  /* A wide glyph costs two columns, so it opens two -- and the pair it moves must not be cut by the shift. */
  rc_reset(&g, 10, 3, 0x07);
  {
    const uint16_t wide = 0x3042;
    put(&g, "AB");
    putu(&g, &wide, 1);                                /* columns 2 and 3 */
    put(&g, "\033[?4h");
    put(&g, "\033[1;3H");
    put(&g, "X");
    eq_u("the glyph stands where the cursor was", RC_CELLS(&g, 0)[2].ch, 'X',
         "one column opened, one column written");
    eq_u("the pair rode one column right, together", (unsigned)(RC_CELLS(&g, 0)[3].attr & RC_LVB_LEADING),
         (unsigned)RC_LVB_LEADING, "its head moved and its tail moved with it");
    eq_u("and the tail is still a tail", (unsigned)(RC_CELLS(&g, 0)[4].attr & RC_LVB_TRAILING),
         (unsigned)RC_LVB_TRAILING, "");
    no_orphan(&g, 0, "an IRM write beside a wide glyph");
  }

  /* The damage claim a write under IRM files. This is the whole point of #77's other half: the glyph changed
     one cell and the row changed from there to the end, and a run is the union of the claimed columns. */
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "ABCDEFGHIJKLMNOP");
  rc_clear_dirty(&g);
  put(&g, "\033[?4h\033[1;5HZ");
  eq_u("an IRM write claims from the cursor", (unsigned)RC_LO(&g, 0), 4, "where its first changed cell is");
  eq_u("to the end of the row", (unsigned)RC_HI(&g, 0), 19, "P moved one column right, so the screen must hear about it");

  /* What the mode answers, and what it costs in the census. A state the model holds is a state DECRQM can
     report, under either spelling of the number DEC assigned it. */
  rc_reset(&g, 20, 6, 0x07);
  {
    struct RcReportItem it;
    put(&g, "\033[?4$p");
    rc_report_take(&g, &it);
    eq_u("a fresh grid is in replace mode", (unsigned)it.status, 1, "off is a state, not an absence");
    put(&g, "\033[?4h\033[?4$p");
    rc_report_take(&g, &it);
    eq_u("`?4h` is the difference the reply carries", (unsigned)it.status, 2, "");
    put(&g, "\033[4$p");
    rc_report_take(&g, &it);
    eq_u("and the ANSI spelling answers the same question", (unsigned)it.status, 2,
         "the mode was set by that spelling, so a probe using it must not be told the number is unknown");
    eq_u("with nothing left counted", (unsigned)un(&g, RC_UN_MODE), 0,
         "IRM is modelled, so neither `4h` nor `4$p` is a mode this build cannot name");
    put(&g, "\033[2026$p");
    eq_u("while a number with no ANSI registration is still counted", (unsigned)un(&g, RC_UN_MODE), 1,
         "ANSI 2026 does not exist; answering it would be inventing the spelling (the rest of the "
         "non-private field is #87's)");
  }

  /* Both resets clear it -- MSFT's SoftReset names InsertReplace (:2989) and its HardReset calls SoftReset --
     and the reset is the only thing that does: a resize carries the mode, because a resize is not a reset. */
  rc_reset(&g, 10, 3, 0x07);
  put(&g, "\033[?4hAB");
  put(&g, "\033[1;2H\033c");
  eq_u("RIS is back in replace mode", (unsigned)g.insertMode, 0, "");
  put(&g, "\033[?4h");
  put(&g, "\033[!p");
  eq_u("and so is DECSTR", (unsigned)g.insertMode, 0, "the same list MSFT's SoftReset works through");
  put(&g, "\033[?4h");
  eq_u("the mode is on again for the alt's sake", (unsigned)g.insertMode, 1, "setup");
  put(&g, "\033[?1049h");
  eq_u("entering the alternate screen does not change it", (unsigned)g.insertMode, 1,
       "it is terminal state, like DECAWM and the tab table (I38's ruling on the other axis)");
  put(&g, "\033[?1049l");
  eq_u("and leaving finds it where it was", (unsigned)g.insertMode, 1, "");
}

/* #78, I41: the colon sub-parameter family. The legs are paired on purpose -- each spelling that has an
 * equivalent semicolon form is required to land on the *same* attribute, which is the only way this file can
 * say it parses the form rather than merely surviving it. */
static void geo_colon()
{
  static RcGrid g;

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[38;2;10:20:30m");
  const unsigned int flat = (unsigned)g.attr;
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[38:2:10:20:30m");
  eq_u("`38:2:r:g:b` folds to the same attribute as the semicolon form", (unsigned)g.attr, flat,
       "one colour model, two spellings");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[38:2::10:20:30m");
  eq_u("and so does the form with the deprecated colour-space slot left empty", (unsigned)g.attr, flat,
       "MSFT keeps an empty sub-parameter as distinct from 0 for exactly this (`CSI 0:::m` is three sub "
       "params, stateMachine.cpp:574-576)");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[38;2;10;20;30m");
  eq_u("which is the attribute the semicolon spelling gives", (unsigned)g.attr, flat, "");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[38:5:146m");
  eq_u("`38:5:n` is the indexed form", (unsigned)g.sgr.fgKind, (unsigned)RC_CLR8B, "");
  eq_u("with the index it named", (unsigned)g.sgr.fg, 146, "");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[48:5:33;38:5:1m");
  eq_u("two colour arms in one sequence, both colon", (unsigned)g.sgr.bgKind, (unsigned)RC_CLR8B, "");
  eq_u("background first", (unsigned)g.sgr.bg, 33, "");
  eq_u("foreground second", (unsigned)g.sgr.fg, 1, "");
  eq_u("and nothing about a parsed colour is a vote", (unsigned)un(&g, RC_UN_COLON), 0, "");

  /* A colon whose kind is missing or unknown. The count is the point, and the *absence* of a colour is what
     makes it honest: applying nothing and saying so beats guessing a colour from the wrong field. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[31m");
  const unsigned int red = (unsigned)g.attr;     /* what `31m` means on its own, to compare against */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[38:9:1m\033[31m");
  eq_u("an unknown kind colours nothing", (unsigned)un(&g, RC_UN_COLON), 1,
       "9 is neither 2 nor 5, so the arm is not carried");
  put(&g, "\033[31m");
  eq_u("and the colour that follows still arrives", (unsigned)g.attr, red,
       "the refused arm consumes its own sub-parameters instead of leaking them into the loop");

  /* 58, the underline colour: a family with no surface on a console, and a *previous* bug -- before #78 the
     semicolon form fell through the switch and read its colour index as a rendition, so `58;5;1` set bold. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[58;5;1m");
  eq_u("`58;5;1` does not set bold", (unsigned)g.sgr.bold, 0,
       "its parameters belong to 58; the old code read `1` as a rendition");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[58:5::14m");
  eq_u("and the colon form of the same thing is parsed, counted and inert", (unsigned)un(&g, RC_UN_COLON), 1,
       "no field exists for an underscore's colour, and inventing one nobody can read is the I26 shape");
  eq_u("with no attribute moved", (unsigned)g.sgr.bold, 0, "");

  /* 4:n, the underline styles. The console has one underscore, so 2..5 are state with no drawing. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[4:3m");
  eq_u("`4:3` puts the underscore on", (unsigned)g.sgr.underline, 1, "the half of the request that is drawable");
  eq_u("and says the rest was not", (unsigned)un(&g, RC_UN_COLON), 1, "curly is not an attribute conhost has");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[4:1m");
  eq_u("`4:1` is single: on, and no vote", (unsigned)un(&g, RC_UN_COLON), 0, "");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[4:1m\033[4:0m");
  eq_u("`4:0` turns it off, which is a request fully carried", (unsigned)g.sgr.underline, 0, "");
  eq_u("and costs nothing", (unsigned)un(&g, RC_UN_COLON), 0,
       "the sender asked for no underline and got no underline");

  /* Mixed separators and the non-SGR finals. ghostty's own parser refuses every family but 'm' -- "We only
     allow colon or mixed separators for the 'm' command" (stream.zig:1350-1358) -- so the boundary is not
     this file's preference, and the count says the sequence arrived. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "abc\033[1;3H");
  eq_u("CUP still moves", (unsigned)g.cx, 2, "setup");
  put(&g, "\033[1:2;3H");
  eq_u("a colon on CUP is counted", (unsigned)un(&g, RC_UN_COLON), 1, "");
  eq_u("and moves nothing", (unsigned)g.cx, 2,
       "no reference agrees on what the family means, so guessing would be a claim, not a parse");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[38:5:1m");
  eq_u("a colon SGR is not suspected of anything", (unsigned)rc_model_suspect(&g), 0,
       "it is parsed and applied");
}

static void geo_edit()
{
  static RcGrid g;
  rc_reset(&g, 8, 3, 0x07);
  put(&g, "ABCD");
  rc_clear_dirty(&g);                        /* the claim under test is the edit's, not the setup's */
  put(&g, "\033[1;2H\033[2@");
  eq_text(&g, 0, 8, "A  BCD  ", "ICH blanks *at* the cursor and pushes the tail from there right");
  eq_u("ICH leaves the cursor where it was", (unsigned)g.cx, 1, "");
  /* The tail that moved is damage. What the painter sends is the union of a row's claimed columns, so a
     claim that stops at the gap it opened leaves the pushed text standing on the screen at its old columns:
     measured on a 20-column row before these lines existed, `CSI 3@` at column 5 claimed [4,6] and planned
     one run [4,6] while every column from 4 to 19 had changed. The vertical case has said this out loud for
     a long time ("a row that arrives at a new number claiming no damage paints nothing and keeps the stale
     screen"); the horizontal one was only ever witnessed through a wide glyph, where the pair healing
     incidentally claimed the row -- which is why a leg that passes can still be a leg that proves nothing. */
  eq_u("ICH claims from the cursor", (unsigned)RC_LO(&g, 0), 1, "where its first changed cell is");
  eq_u("to the end of the row", (unsigned)RC_HI(&g, 0), (unsigned)(g.cols - 1),
       "everything right of the gap moved, not just the gap");
  rc_clear_dirty(&g);
  put(&g, "\033[1;2H\033[P");
  eq_text(&g, 0, 8, "A BCD   ", "DCH pulls the tail back left over the gap and blanks the row's end");
  eq_u("DCH claims from the cursor", (unsigned)RC_LO(&g, 0), 1, "not from the blanks it landed on");
  eq_u("and to the row's end", (unsigned)RC_HI(&g, 0), (unsigned)(g.cols - 1),
       "the old leg read the cells in the model, which is not the screen");
  put(&g, "\033[1;2H\033[99P");
  eq_text(&g, 0, 2, "A ", "an over-long DCH clears the row from the cursor and stops at the margin");
  eq_text(&g, 0, 8, "A       ", "nothing wrapped, nothing moved on the row below");
  eq_text(&g, 1, 1, " ", "row 1 never had anything on it, and still has nothing");

  rc_reset(&g, 8, 3, 0x07);
  put(&g, "ABCDEFGH");
  put(&g, "\033[1;8H\033[2@");
  eq_text(&g, 0, 7, "ABCDEFG", "ICH at the last column can only open the one cell left");
  eq_u("and paints nothing outside the row", RC_CELLS(&g, 0)[7].ch, ' ', "n clamps to cols-cx");

  /* A pair of cells holding one glyph travels as a pair, and an edit that leaves one half behind does not
     get to keep the other. ghostty makes that a hard property of the grid: `assertIntegrity()` rejects a
     spacer tail at column 0 or one that does not follow its wide head (page.zig:518-540), and every edit
     that could straddle a boundary clears the glyph whole instead -- "If our X is a wide spacer tail then we
     need to erase the previous cell too so we don't split a multi-cell character" (Terminal.zig:3322-3327),
     `splitCellBoundary()` at each edge of an ECH or a DCH (:3411-3413, :3463-3464), and ECH growing its
     erase by one cell when the last cell it would take is wide (:3448-3452). The two legs below are the
     shapes where a cell-shifting implementation cuts a glyph in half: the cursor on the trailing side for
     ICH, on the leading side for DCH. */
  const uint16_t wide = 0x3042;                        /* U+3042, EAW W */
  rc_reset(&g, 8, 3, 0x07);
  putu(&g, &wide, 1);
  put(&g, "A");
  eq_u("setup: the leading half", RC_CELLS(&g, 0)[0].attr & RC_LVB_LEADING, RC_LVB_LEADING, "");
  eq_u("setup: the trailing half", RC_CELLS(&g, 0)[1].attr & RC_LVB_TRAILING, RC_LVB_TRAILING, "");
  put(&g, "\033[1;1H\033[1@");
  eq_u("ICH moved the leading half right", RC_CELLS(&g, 0)[1].attr & RC_LVB_LEADING, RC_LVB_LEADING, "");
  eq_u("and the trailing half kept its own bit", RC_CELLS(&g, 0)[2].attr & RC_LVB_TRAILING, RC_LVB_TRAILING, "");
  eq_u("the blank is at the cursor column", RC_CELLS(&g, 0)[0].ch, ' ', "");
  eq_u("A rode one column further right", RC_CELLS(&g, 0)[3].ch, 'A', "");
  no_orphan(&g, 0, "ICH with both halves inside the shifted span");
  put(&g, "\033[1;1H\033[P");
  eq_u("DCH shifted the pair back: front half at column 0", RC_CELLS(&g, 0)[0].attr & RC_LVB_LEADING,
       RC_LVB_LEADING, "the pair survives because both halves moved by the same amount");
  eq_u("trailing half at column 1", RC_CELLS(&g, 0)[1].attr & RC_LVB_TRAILING, RC_LVB_TRAILING, "");
  eq_u("and no third cell claims the code point", RC_CELLS(&g, 0)[2].ch, 'A', "");
  no_orphan(&g, 0, "DCH with both halves inside the shifted span");

  rc_reset(&g, 8, 3, 0x07);
  put(&g, "x");
  putu(&g, &wide, 1);                                  /* the glyph occupies columns 1 and 2 */
  put(&g, "AB");
  put(&g, "\033[1;3H\033[1@");                         /* ICH with the cursor on the trailing half */
  eq_text(&g, 0, 6, "x   AB", "the glyph is destroyed whole and the tail still shifts one column");
  no_orphan(&g, 0, "ICH with the cursor on a trailing half");

  rc_reset(&g, 8, 3, 0x07);
  put(&g, "x");
  putu(&g, &wide, 1);
  put(&g, "AB");
  put(&g, "\033[1;2H\033[1P");                         /* DCH with the cursor on the leading half */
  eq_text(&g, 0, 5, "x AB", "the head goes with the erase and the tail that slid into it goes too");
  no_orphan(&g, 0, "DCH with the cursor on a leading half");

  /* The same rule seen from the write side: CUP and DECRC can park the cursor on either half of a glyph,
     because the column they name is the column that was asked for. What the model may not do is write one
     cell and keep the other -- put_cell already destroys the glyph when the cursor sits on its head, and the
     mirror case has to answer the same way. */
  rc_reset(&g, 8, 3, 0x07);
  putu(&g, &wide, 1);
  put(&g, "AB");
  put(&g, "\033[1;2Hz");
  eq_u("writing over a trailing half blanks the head", RC_CELLS(&g, 0)[0].ch, ' ', "");
  eq_u("and the new glyph stands where the cursor was", RC_CELLS(&g, 0)[1].ch, 'z', "");
  no_orphan(&g, 0, "a narrow cell written on a trailing half");

  rc_reset(&g, 8, 3, 0x07);
  putu(&g, &wide, 1);
  put(&g, "AB");
  put(&g, "\033[1;2H");
  putu(&g, &wide, 1);                                  /* a wide cell written *on* the old one's tail */
  eq_u("the new glyph owns its own two cells", RC_CELLS(&g, 0)[1].attr & RC_LVB_LEADING, RC_LVB_LEADING, "");
  no_orphan(&g, 0, "a wide cell written over a pair");

  /* ECH erases to the end of its own row. "Erase Characters from the current cursor position ... will only
     erase characters in the current line, and won't wrap to the next" (adaptDispatch.cpp:706-724, which
     clamps with `std::min(startCol + numChars, GetLineWidth(row))`), and ghostty clamps the same way with
     `remaining = cols - cursor.x` (Terminal.zig:3443-3446). An over-long ECH is not a screen clear: the
     rows below hold text the application did not ask to lose. */
  rc_reset(&g, 8, 3, 0x07);
  put(&g, "AAAAAAAA");
  put(&g, "\033[2;1HBBBBBBBB");
  put(&g, "\033[1;1H\033[99X");
  eq_text(&g, 0, 8, "        ", "ECH 99 on a row of 8 erases the row");
  eq_text(&g, 1, 8, "BBBBBBBB", "and stops at its end, because the row below is a different line");
  eq_u("with the cursor where the sequence left it", (unsigned)g.cx, 0, "");
  eq_u("and the row's wrap claim dropped with the margin", (unsigned)rc_row_wrap(&g, 0), RC_WRAP_NONE, "");
  put(&g, "\033[2;1H\033[3X");
  eq_text(&g, 1, 8, "   BBBBB", "ECH counts cells from the cursor, on the row the cursor is on");

  rc_reset(&g, 8, 3, 0x07);
  putu(&g, &wide, 1);
  put(&g, "AB");
  put(&g, "\033[1;1H\033[1X");
  eq_text(&g, 0, 4, "  AB", "ECH takes the whole glyph when it would take half of one");
  no_orphan(&g, 0, "ECH over a leading half");

  /* DECSCUSR: the parameter is what the model keeps, and 0/out-of-range is ConEmu's "default", which for
     a console means the thin side of the only two shapes it has (Ansi.cpp:3677). */
  rc_reset(&g, 8, 3, 0x07);
  eq_u("a fresh grid claims no shape", (unsigned)g.cursorShape, -1, "so the user's cursor height survives");
  put(&g, "\033[2 q");
  eq_u("steady block", (unsigned)g.cursorShape, 2, "");
  put(&g, "\033[4 q");
  eq_u("steady underline", (unsigned)g.cursorShape, 4, "");
  put(&g, "\033[0 q");
  eq_u("the default is 0, which is a shape as far as the console is concerned", (unsigned)g.cursorShape, 0, "");
  put(&g, "\033[9 q");
  eq_u("out of range folds to the default", (unsigned)g.cursorShape, 0, "");
  put(&g, "\033[ q");
  eq_u("and so does no parameter at all", (unsigned)g.cursorShape, 0, "");
  put(&g, "\033[?1 q");
  eq_u("a private byte alongside the interim is not DECSCUSR", (unsigned)g.cursorShape, 0,
       "upstream gates on PvtLen == 1, and '?' would make it 2 (:3657)");
  put(&g, "\033[1q");
  eq_u("and neither is a q with no interim byte", (unsigned)g.cursorShape, 0, "unchanged, as upstream's else arm");
  eq_u("that one is counted: it has no case here or there", g.nUnsupported[RC_UN_SUP], 2, "XTSSZ");
  put(&g, "\033[3 q");
  eq_u("blinking underline is kept as the parameter", (unsigned)g.cursorShape, 3,
       "3..6 all fold to the thin side in cursor_height(), because the console has two shapes, not six");

  /* The two intermediates below are the reason the interim is a set and not a slot. Upstream appends both
     into one Pvt buffer (:1788) and DECSCUSR then asks for `PvtLen == 1` (:3657), so "! " is refused there;
     a slot that the later byte overwrites reported the junk spelling `! SP q` as if it were the real
     request, because ' ' happened to arrive last. The same trap is wider than one sequence: any final whose
     interim is chosen by arrival order can be spoofed by a junk byte in front of it, and the long run after
     it is that trap at its most obvious -- ten intermediates, none of which is "exactly one space". */
  put(&g, "\033[! q");
  eq_u("an interim of two bytes selects no cursor shape", (unsigned)g.cursorShape, 3,
       "unchanged from the leg above: Pvt would be \"!\", two bytes, and the arm wants length 1");
  eq_u("and the sequence is counted as the unknown final it was", g.nUnsupported[RC_UN_SUP], 3, "");
  put(&g, "\033[          q");
  eq_u("a run of intermediates past the buffer still selects nothing", (unsigned)g.cursorShape, 3,
       "the extras are dropped as they are upstream, where a full Pvt stops appending (:1788)");
  eq_u("and counted once more", g.nUnsupported[RC_UN_SUP], 4, "");

  /* REP (`CSI Ps b`) is text, not a cell poke. Upstream builds a buffer of the one character it remembers and
     hands it to WriteText (Ansi.cpp:3070-3087), so it wraps at the margin, obeys the drawing set, takes the
     live attribute, and repeats the character *before* the remap -- m_LastWrittenChar is stored at :1098 and
     mCharSet is applied at :1111, in that order. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "X\033[3b");
  eq_text(&g, 0, 4, "XXXX", "one write, three repeats");
  eq_u("and the cursor ends where the text does", (unsigned)g.cx, 4, "");
  put(&g, "\033[1;11H\033[15b");
  eq_text(&g, 0, 20, "XXXX      XXXXXXXXXX", "REP fills the row to the margin");
  eq_text(&g, 1, 5, "XXXXX", "and wraps on to the next one, because it is text");
  eq_u("with the wrap claimed by the row that ran out", (unsigned)rc_row_wrap(&g, 0), RC_WRAP_FORCED, "");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "X");
  rc_clear_dirty(&g);
  put(&g, "\033[1;3H\033[0b");
  eq_u("a zero count repeats nothing", (unsigned)g.cx, 2, "ArgV[0] is read raw, so `CSI 0b` is not `CSI b`");
  eq_u("and damages nothing", (unsigned)rc_row_dirty(&g, 0), 0, "");
  put(&g, "\033[1;3H\033[b");
  eq_u("no parameter is the default of one", (unsigned)g.cx, 3, "");
  eq_u("the cell it painted is the glyph remembered", RC_CELLS(&g, 0)[2].ch, 'X', "");
  eq_span(&g, 0, 2, 2, "one column of damage");
  put(&g, "\033[?3b");
  eq_u("a private byte is not REP", (unsigned)g.cx, 3, "upstream gates the whole case on !PvtLen (:3072)");
  eq_u("and it is counted as inert rather than unknown", g.nUnsupported[RC_UN_MODE], 1, "");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[1;3H\033[2b");
  eq_u("before anything is written, REP repeats a space", RC_CELLS(&g, 0)[2].ch, ' ',
       "lastUnit is seeded by rc_reset_hist; upstream's m_LastWrittenChar is whatever survived the last reset");
  eq_span(&g, 0, 2, 3, "a space still damages the cells it is written to");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033(0q");
  eq_u("the drawing set remaps the glyph", RC_CELLS(&g, 0)[0].ch, 0x2500, "`ESC ( 0` then q");
  put(&g, "\033[2b");
  eq_u("and REP repeats the same line glyph", RC_CELLS(&g, 0)[1].ch, 0x2500, "the remap is still live");
  put(&g, "\033(B\033[2b");
  eq_u("leaving the set shows what was remembered: the letter", RC_CELLS(&g, 0)[3].ch, 'q',
       "the code point is stored before the charset is applied, so a repeat after `ESC ( B` is plain text");
  eq_u("one letter per repeat", RC_CELLS(&g, 0)[4].ch, 'q', "");

  rc_reset(&g, 20, 4, 0x07);
  {
    uint16_t w = 0x4E00;                            /* U+4E00, EAW W */
    putu(&g, &w, 1);
  }
  put(&g, "\033[2b");
  eq_u("a wide glyph costs two columns per repeat", (unsigned)g.cx, 6, "one write plus two repeats");
  eq_u("and keeps the pair convention", (unsigned)(RC_CELLS(&g, 0)[4].attr & RC_LVB_LEADING),
       (unsigned)RC_LVB_LEADING, "otherwise half a glyph paints");
  eq_u("its partner trailing", (unsigned)(RC_CELLS(&g, 0)[5].attr & RC_LVB_TRAILING),
       (unsigned)RC_LVB_TRAILING, "");

  rc_reset(&g, 20, 4, 0x07);
  {
    const uint16_t astral[2] = { 0xD83D, 0xDE00 };  /* U+1F600 */
    putu(&g, astral, 2);
  }
  const uint16_t hi = RC_CELLS(&g, 0)[0].ch, lo = RC_CELLS(&g, 0)[1].ch;
  put(&g, "\033[1b");
  eq_u("REP of an astral writes the pair again, high half first", RC_CELLS(&g, 0)[2].ch, hi,
       "upstream's m_LastWrittenChar is one wchar_t, so a repeat there is the same half twice");
  eq_u("low half second", RC_CELLS(&g, 0)[3].ch, lo, "");
}


/* ------------------------ 4i. the byte stream jline 3.29 itself writes, replayed ------------------ */

/* Neither leg of the caps audit can be trusted on the other's word. These bytes were captured from jline
   3.29 running against the deployed lib/Jline3.jar -- cache/caps-audit/JlineWire.java, not invented here --
   so the grid below is the model's answer to the exact stream a real client puts on the wire. If either
   side changes its mind, this is the case that notices. */
static void geo_jline_stream()
{
  static RcGrid g;

  /* jline draws boxes from a table hard-coded in AttributedCharSequence.java:266-280, not from the acsc
     string it advertises, so these eleven letters are what actually crosses the wire under `ESC ( 0`.
     Each is the glyph G0_DRAWING owes back (Render.cpp:54): j box UL UR LR cross horizontal VR LL RR TU. */
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033(0jklmnqtuvwx\033(Bz");
  const unsigned box[11] = { 0x2518, 0x2510, 0x250C, 0x2514, 0x253C, 0x2500,
                             0x251C, 0x2524, 0x2534, 0x252C, 0x2502 };
  for (int i = 0; i < 11; i++)
    eq_u(S("jline box letter %d draws its glyph", i + 1), RC_CELLS(&g, 0)[i].ch, box[i], "");
  eq_u("and `ESC ( B` closes the set, so the letter after it is text", RC_CELLS(&g, 0)[11].ch, 'z',
       "otherwise a plain 'z' would silently become a greater-or-equal");

  /* A mid-line edit, replayed on a 32-column grid so no line end interferes: jline writes the whole line,
     steps back to the difference, inserts the completion and deletes the characters it displaced (dch is
     newly on the wire -- the old caps had no dch, so the row was rewritten instead). */
  rc_reset(&g, 32, 3, 0x07);
  put(&g, "select * from dual;");
  put(&g, "\033[5Dv$session\033[4P;\033[3D");
  eq_text(&g, 0, 26, "select * from v$session;  ", "jline's own redraw lands the line it meant");
  eq_u("with the cursor on the column jline asked for", (unsigned)g.cx, 21, "");
  eq_text(&g, 1, 3, "   ", "and nothing above or below it moved");
}


/* ------------------------------------------- 4h. FTCS marks: what they say and where they go ------ */

/* The row claims OSC 133 lays down. They never reach the console -- no attribute, no cell, no cursor shape --
 * so this grid is the only place they can be seen at all, which is exactly why the census cannot stand in for
 * it: a counter says a command arrived, and only a row says whether it landed where the shell meant. */
static void geo_ftcs()
{
  static RcGrid g;

  /* `A` and `N` start a fresh line *before* marking, so the mark is on the row the prompt begins on and the
     row the cursor leaves keeps what it was. At the left margin there is no line to fresh -- ghostty returns
     at once (Terminal.zig:2225) -- and no row is consumed. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "abcde");
  put(&g, "\033]133;A\007$ ");
  eq_u("A returned the column", (unsigned)g.cx, 2, "the prompt's own two characters, counted from column 0");
  eq_u("and moved down one row", (unsigned)g.cy, 1, "");
  eq_u("the prompt is marked on the row it starts on", (unsigned)rc_row_mark(&g, 1), RC_PM_PROMPT, "");
  eq_u("at the column it starts on", (unsigned)rc_mark_col(&g, 1), 0, "");
  eq_u("the row it left is not marked", (unsigned)rc_row_mark(&g, 0), RC_PM_NONE, "");
  eq_text(&g, 0, 5, "abcde", "and the CR touched no cell on it");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;A\007");
  eq_u("at the margin nothing is consumed", (unsigned)g.cy, 0, "");
  put(&g, "\033]133;A\007");
  eq_u("and a second prompt on a row that has one is refused", (unsigned)rc_prompt_marks(&g), 1,
       "MSFT emplaces a prompt only when the row has none (Row.cpp:1263)");
  put(&g, "\033]133;D;3\007");
  eq_u("D turns the prompt row into a verdict", (unsigned)rc_row_mark(&g, 0), RC_PM_ERROR, "");
  eq_u("and keeps the code for the log", (unsigned)rc_last_exit(&g), 3, "");
  put(&g, "\033]133;A\007");
  eq_u("a later prompt does not steal the verdict", (unsigned)rc_row_mark(&g, 0), RC_PM_ERROR,
       "that command's text is still on the row");

  /* A continuation this model guessed for itself is the one mark an explicit prompt may replace: the guess was
     ours, and the shell has now said otherwise. This is the ordering ghostty produces, its index() defer
     flagging the new row and the `A` that follows stamping .prompt over it. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;A\007$ \033]133;B\007ls\r\n");
  eq_u("Enter inside B's input marks the next row a continuation", (unsigned)rc_row_mark(&g, 1),
       RC_PM_CONTINUATION, "a wrapped prompt and an entered one are the same kind of row");
  put(&g, "\033]133;P\007");
  eq_u("a primary prompt overwrites that guess", (unsigned)rc_row_mark(&g, 1), RC_PM_PROMPT, "");

  /* B and I are one state with two ends, and the end is the only difference either reference can observe. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;A\007$ \033]133;B\007");
  eq_u("B marks no row", (unsigned)rc_prompt_marks(&g), 1, "the row keeps the prompt it began with");
  eq_u("input, and not the kind that ends at a line feed", (unsigned)g.semanticClearEol, 0, "");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;A\007$ \033]133;I\007");
  eq_u("I is the same state with the other end", (unsigned)g.semanticClearEol, 1,
       "Terminal.zig:2174-2179: .clear_eol rather than .clear_explicit");
  put(&g, "\r\n");
  eq_u("its input is over at the line feed", (unsigned)g.semanticContent, RC_SC_OUTPUT, "");
  eq_u("so the next row is nobody's continuation", (unsigned)rc_row_mark(&g, 1), RC_PM_NONE, "");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;A\007$ \033]133;B\007\r\n");
  eq_u("whereas B's carries on down", (unsigned)rc_row_mark(&g, 1), RC_PM_CONTINUATION, "");

  /* C at column 0 is the one place a mark is taken away, and it is a fish workaround
     (Terminal.zig:2185-2198): fish has no PS2, its own marking never says k=s, and it switches to output on
     the continuation line -- so a prompt claim at column 0 when output starts was never a prompt line. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;A\007>>> \033]133;C\007");
  eq_u("C mid-row leaves the prompt alone", (unsigned)rc_row_mark(&g, 0), RC_PM_PROMPT, "column 4, not column 0");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;A\007>>> ");
  put(&g, "\r\n");
  eq_u("a line feed inside a prompt continues it", (unsigned)rc_row_mark(&g, 1), RC_PM_CONTINUATION,
       "A leaves the cursor in the prompt state, not in output");
  put(&g, "\033]133;C\007out");
  eq_u("and C at column 0 retires that claim", (unsigned)rc_row_mark(&g, 1), RC_PM_NONE, "");
  eq_u("the tally counts requests, not rows standing", (unsigned)rc_prompt_marks(&g), 2, "");
  eq_u("the row above keeps its prompt", (unsigned)rc_row_mark(&g, 0), RC_PM_PROMPT, "the heuristic is about column 0");
  put(&g, "\r\n");
  eq_u("and output running past a row claims nothing", (unsigned)rc_row_mark(&g, 2), RC_PM_NONE,
       "C's state is output, so this is a command's answer, not a prompt's second line");

  /* A verdict finds its prompt by searching upward and stopping at the first row that carries a mark: the
     command's own output may have scrolled the prompt up, and there may be another prompt in between
     (textBuffer.cpp:3486-3499, `for (y = cursor.y; y >= 0; y--)`). */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;A\007$ ");
  put(&g, "\033]133;B\007ls\r\n");
  put(&g, "\033]133;C\007file1\r\nfile2\r\n");
  eq_u("three rows down by the time the command finishes", (unsigned)g.cy, 3, "");
  eq_u("the output rows kept no claim", (unsigned)rc_row_mark(&g, 1), RC_PM_NONE, "");
  put(&g, "\033]133;D;0\007");
  eq_u("and the verdict reaches the prompt under them all", (unsigned)rc_row_mark(&g, 0), RC_PM_SUCCESS, "");
  eq_u("with its code", (unsigned)rc_last_exit(&g), 0, "");
  eq_u("the search stopped there", (unsigned)rc_prompt_marks(&g), 2,
       "the prompt and the continuation Enter left behind -- and only the first was answered");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;D;7\007");
  eq_u("a verdict with nothing above it to mark records the code", (unsigned)rc_last_exit(&g), 7, "");
  eq_u("and lays no mark", (unsigned)rc_prompt_marks(&g), 0, "");

  /* The three shapes of a missing or unusable code. ghostty calls a non-number success; MSFT calls it an
     error (UINT_MAX). MSFT's answer is the one followed, because the other can hide a failed command. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;A\007");
  put(&g, "\033]133;D\007");
  eq_u("no second field is not a verdict", (unsigned)rc_row_mark(&g, 0), RC_PM_PROMPT, "MSFT leaves the category alone");
  eq_u("and there is no code to report", (unsigned)rc_last_exit(&g), (unsigned)RC_EXIT_UNKNOWN, "");
  put(&g, "\033]133;D;abc\007");
  eq_u("a code that is not a number reads as an error", (unsigned)rc_row_mark(&g, 0), RC_PM_ERROR, "");
  eq_u("and as not-a-number rather than as a value", (unsigned)rc_last_exit(&g), (unsigned)RC_EXIT_UNPARSABLE, "");
  put(&g, "\033]133;D;0\007");
  eq_u("a second verdict replaces the first", (unsigned)rc_row_mark(&g, 0), RC_PM_SUCCESS,
       "there is no stored current command to disagree with it");
  put(&g, "\033]133;D;-1\007");
  eq_u("a negative code is not a number either", (unsigned)rc_last_exit(&g), (unsigned)RC_EXIT_UNPARSABLE,
       "upstream's UINT_MAX; MSFT parses unsigned");
  eq_u("so it is an error", (unsigned)rc_row_mark(&g, 0), RC_PM_ERROR, "");
  put(&g, "\033]133;D;1234567890\007");
  eq_u("ten digits would overflow the int, so it is not a number either", (unsigned)rc_last_exit(&g),
       (unsigned)RC_EXIT_UNPARSABLE, "");
  put(&g, "\033]133;D;0;aid=x\007");
  eq_u("options after the code do not hide it", (unsigned)rc_last_exit(&g), 0, "the code is the second field, unkeyed");

  /* A mark belongs to its content, not to its row number, so every vertical shift carries it. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[4;1Hxx");
  put(&g, "\033]133;A\007$ ");
  eq_u("a fresh line at the bottom scrolls the viewport", (unsigned)rc_row_mark(&g, 3), RC_PM_PROMPT, "");
  eq_text(&g, 3, 2, "$ ", "and the prompt text follows the cursor there");
  eq_u("the row that came in from the buffer knows nothing", (unsigned)rc_row_mark(&g, 0), RC_PM_NONE, "");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[3;1H\033]133;P\007cmd");
  put(&g, "\033[2;1H\033[1L");
  eq_text(&g, 3, 3, "cmd", "IL pushed the row down");
  eq_u("and its prompt with it", (unsigned)rc_row_mark(&g, 3), RC_PM_PROMPT, "");
  eq_u("the blank that arrived knows nothing", (unsigned)rc_row_mark(&g, 1), RC_PM_NONE, "");
  eq_u("the row it vacated neither", (unsigned)rc_row_mark(&g, 2), RC_PM_NONE, "");
  put(&g, "\033[2;1H\033[1M");
  eq_u("deleting a row above brings the prompt back", (unsigned)rc_row_mark(&g, 2), RC_PM_PROMPT, "");
  eq_text(&g, 2, 3, "cmd", "with its text");

  /* The column in transit, which is the field #73's whole-struct carry exists to protect. Every rc_mark_col()
     assertion above is on a row that either stayed put or was blanked, so a carry written field by field --
     mark and wrap across, the number left behind -- passes all of them: the two rows it would corrupt read 0
     in and 0 out, because a mark made at the margin has no column to lose. This one is made at column 4 and
     *moved*, so the lost half shows. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[3;5H\033]133;P\007");
  eq_u("a prompt made mid-row", (unsigned)rc_row_mark(&g, 2), RC_PM_PROMPT, "");
  eq_u("remembers its column", (unsigned)rc_mark_col(&g, 2), 4, "");
  put(&g, "\033[1;1H\033[1M");
  eq_u("deleting above moves the mark up", (unsigned)rc_row_mark(&g, 1), RC_PM_PROMPT, "");
  eq_u("and its column the whole way", (unsigned)rc_mark_col(&g, 1), 4,
       "a half-carry reads 0 here, which a consumer takes for 'the prompt starts at the margin'");
  put(&g, "\033[1;1H\033[1L");
  eq_u("inserting it back down carries it down", (unsigned)rc_mark_col(&g, 2), 4,
       "the guard is the shape, not the direction");
  eq_u("while the row that came in has neither", (unsigned)rc_row_mark(&g, 1), RC_PM_NONE, "");

  /* The alt screen is a different screen, so it has different claims -- and the user's prompt row is exactly
     what a full-screen program must not be able to overwrite with its own. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[3;1H\033]133;A\007");
  eq_u("the main screen has a prompt on row 2", (unsigned)rc_row_mark(&g, 2), RC_PM_PROMPT, "");
  put(&g, "\033[?1049h");
  eq_u("entering the alt leaves no claim behind", (unsigned)rc_row_mark(&g, 2), RC_PM_NONE,
       "blank_viewport forgets the row state with the wrap bits");
  eq_u("and does not home the cursor", (unsigned)g.cy, 2, "1049 saves a position to restore, it does not move one");
  put(&g, "\033[1;1H\033]133;A\007vim");
  eq_u("an alt prompt is marked where the alt can see it", (unsigned)rc_row_mark(&g, 0), RC_PM_PROMPT, "");
  eq_u("while the main screen's row stays in the snapshot", (unsigned)rc_row_mark(&g, 2), RC_PM_NONE, "");
  put(&g, "\033[?1049l");
  eq_u("leaving restores the prompt the user had", (unsigned)rc_row_mark(&g, 2), RC_PM_PROMPT,
       "the verdict a shell waits for may arrive after the program exits");
  eq_u("and the alt's own mark goes with the alt", (unsigned)rc_row_mark(&g, 0), RC_PM_NONE, "");

  /* Adopting the console's screen drops the claims, because they cannot be read back -- the same contract
     rc_row_wrap keeps, and for the same reason: the console knows nothing about either. */
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;A\007");
  eq_u("marked before the adopt", (unsigned)rc_row_mark(&g, 0), RC_PM_PROMPT, "");
  rc_forget_row_state(&g);
  eq_u("an adopt forgets the marks", (unsigned)rc_row_mark(&g, 0), RC_PM_NONE, "");
  eq_u("and the column with them", (unsigned)rc_mark_col(&g, 0), 0, "");
}


static void geo_sgr_bits()
{
  static RcGrid g;
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033[4;7m");
  eq_u("underline bit", g.attr & RC_LVB_UNDERSCORE, RC_LVB_UNDERSCORE, "");
  eq_u("inverse bit", g.attr & RC_LVB_REVERSE, RC_LVB_REVERSE, "");
  put(&g, "\033[24;27m");
  eq_u("bits cleared", g.attr & (RC_LVB_UNDERSCORE | RC_LVB_REVERSE), 0, "");
  put(&g, "\033[4mX\033[39;49mY");
  eq_u("39/49 keeps the underline on the pending state", g.attr & RC_LVB_UNDERSCORE,
       RC_LVB_UNDERSCORE, "only SGR 0 clears it");
  eq_u("the cell painted before 39/49 keeps it too", RC_CELLS(&g, 0)[0].attr, 0x8007, "0x07 + underline");
  eq_u("the cell painted after 39/49", RC_CELLS(&g, 0)[1].attr, 0x8007, "underline is still set");

  /* bold brightens the foreground unless a bright background already claimed the bit (Ansi.cpp:783) */
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033[1;31m");
  eq_u("bold red", g.attr & 0x0F, 0x0C, "dark red | FOREGROUND_INTENSITY");
  put(&g, "\033[0;31m");
  eq_u("plain red", g.attr & 0x0F, 0x04, "");
  put(&g, "\033[1;101m");
  eq_u("bold with a bright background", g.attr & 0x0F, 0x04, "brightBack steals the intensity bit");

  /* 90..97 and 100..107 are the bright set in xterm numbering */
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033[91m");
  eq_u("bright fg 91", g.attr & 0x0F, 0x0C, "red + intensity");
  put(&g, "\033[0;101m");
  eq_u("bright bg 101", g.attr & 0xF0, 0xC0, "");

  /* a default attribute carrying the underscore bit survives until the first SGR 0 */
  rc_reset(&g, 20, 3, 0x8007);
  eq_u("underscore seeded from the default", g.attr, 0x8007, "DisplayParm::Reset seeds colours only");
  put(&g, "\033[0mX");
  eq_u("SGR 0 drops it", g.attr, 0x07, "measured upstream behaviour");
  eq_u("the painted cell uses the cleared attribute", RC_CELLS(&g, 0)[0].attr, 0x07, "");

  /* 38/48 with an index above 255 masks rather than rejects (Ansi.cpp:3568) */
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033[48;5;300mX");
  unsigned masked = g.attr;
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033[48;5;44mX");
  eq_u("index masked to 8 bits", masked, g.attr, "300 & 0xFF = 44, so the two must paint alike");
}

static void geo_damage()
{
  static RcGrid g;
  rc_reset(&g, 20, 6, 0x07);
  int any = 0;
  for (int r = 0; r < 6; r++) any |= rc_row_dirty(&g, r);
  eq_u("rc_reset leaves nothing dirty", (unsigned)any, 0, "a fresh grid needs no repaint");
  put(&g, "ab\r\n\rcd");
  eq_u("row 0 dirty", (unsigned)rc_row_dirty(&g, 0), 1, "ab painted");
  eq_u("row 1 dirty", (unsigned)rc_row_dirty(&g, 1), 1, "cd painted");
  eq_u("row 2 clean", (unsigned)rc_row_dirty(&g, 2), 0, "untouched");
  rc_clear_dirty(&g);
  eq_u("clear_dirty", (unsigned)rc_row_dirty(&g, 0), 0, "");
  put(&g, "\033[1;1r");
  eq_u("an ignored sequence dirties nothing", (unsigned)rc_row_dirty(&g, 0), 0, "DECSTBM");
  put(&g, "\033[1;1H");
  eq_u("a cursor move alone dirties nothing", (unsigned)rc_row_dirty(&g, 0), 0, "CHT then paint");
  put(&g, "\033[6;1H\033[2K");
  eq_u("ED/EL dirties its own row", (unsigned)rc_row_dirty(&g, 5), 1, "");
  eq_u("and not its neighbour", (unsigned)rc_row_dirty(&g, 4), 0, "");

  /* B2: a dirty row knows which columns. Getting this wrong is silent in two opposite ways -- too wide
     costs nothing but time, too narrow loses pixels forever -- so each answer is named exactly. */
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[1;11HX");                        /* column 10 of a 20-column buffer row */
  eq_span(&g, 0, 10, 10, "one glyph damages one column");
  rc_clear_dirty(&g);
  put(&g, "\033[1;11H\033[K");
  eq_span(&g, 0, 10, 19, "EL 0 starts at the cursor and stops at the margin");
  rc_clear_dirty(&g);
  put(&g, "\033[1;11H\033[1K");
  eq_span(&g, 0, 0, 10, "EL 1 reaches the cursor, no further");
  rc_clear_dirty(&g);
  put(&g, "\033[1;11H\033[2K");
  eq_span(&g, 0, 0, 19, "EL 2 is the whole row because it says so");
  rc_clear_dirty(&g);
  put(&g, "\033[1;11H\033[30X");
  eq_span(&g, 0, 10, 19, "ECH spends its count on the row's tail and stops at the margin");
  eq_u("the row below is not the next row of the same erase", (unsigned)rc_row_dirty(&g, 1), 0,
       "MSFT clamps with `min(startCol + numChars, GetLineWidth(row))` (adaptDispatch.cpp:718) and ghostty "
       "with `remaining = cols - cursor.x` (Terminal.zig:3445). The old leg here walked down through the "
       "buffer, which is text the application never named and rows the damage report then repainted blank.");
  rc_clear_dirty(&g);
  put(&g, "\033[1;11H\033[999X");
  eq_span(&g, 0, 10, 19, "an over-long ECH is still one row");
  eq_u("and the viewport's last row is not part of it", (unsigned)rc_row_dirty(&g, 5), 0, "");
  rc_clear_dirty(&g);
  put(&g, "\033[1;11H\033[0X");
  eq_u("a zero count erases nothing", (unsigned)rc_row_dirty(&g, 0), 0,
       "the parameter is read raw, so `CSI 0X` is not `CSI X`, which is one cell: MSFT's arithmetic gives an "
       "empty range the same way (startCol + 0 == startCol). ghostty clamps the count to 1 instead "
       "(@max(count_req, 1), :3446) and is the odd one out; a count of zero asking for nothing is the "
       "reading this model keeps, because it is the one that needs no special case");
  rc_clear_dirty(&g);
  put(&g, "\033[1;11H\033[X");
  eq_span(&g, 0, 10, 10, "no parameter is the default of one");
  rc_clear_dirty(&g);
  put(&g, "\033[1;21H");
  eq_u("a cursor parked on the margin dirties nothing", (unsigned)rc_row_dirty(&g, 0), 0, "");
  put(&g, "ab");                                 /* both cells fall off the end and wrap */
  eq_span(&g, 0, 19, 19, "only the column the row had room for");
  eq_span(&g, 1, 0, 0, "the wrap put the next glyph on the following row");

  rc_clear_dirty(&g);
  {
    uint16_t w = 0x4E00;                          /* a two-column glyph */
    put(&g, "\033[1;10H");
    putu(&g, &w, 1);
    eq_span(&g, 0, 9, 10, "a wide glyph claims both of its cells, or half of it paints");
  }

  rc_clear_dirty(&g);
  put(&g, "\033[2J");
  for (int r = 0; r < 6; r++) eq_full(&g, r, "ED 2 cannot name its columns, so it says the whole row");
  rc_clear_dirty(&g);
  put(&g, "\033[3;1H\033[2L");
  for (int r = 0; r < 6; r++) eq_full(&g, r, "IL shifts every row below the cursor: the viewport is all damage");
  rc_clear_dirty(&g);
  put(&g, "\033[3;1H\033[2M");
  for (int r = 0; r < 6; r++) eq_full(&g, r, "DL likewise");
}

/*
 * DECSET 2026 as the model sees it. The hold itself belongs to the seam (RenderJni.cpp::paint_flush) and this
 * file has no console to watch it with, so what is pinned here are the two things the seam reads: the bit, and
 * the damage the bit defers. The second is the load-bearing one. The seam throws a whole plan away and counts
 * on the rows it was built from still being marked when the region ends; a model that cleared its own dirty
 * flags mid-region would turn "paint one frame instead of ten" into "paint nothing at all", and nothing on the
 * screen would say which of the two happened. Render.java's caseSyncOutput is the other half -- the one that
 * can only be asserted where a console exists.
 */
static void sync_output()
{
  static RcGrid g;
  rc_reset(&g, 20, 6, 0x07);
  eq_u("no region after a reset", (unsigned)g.sync, 0, "the census and the bit both come from rc_reset's memset");
  eq_u("and nothing counted", g.nSyncEngages, 0u, "");

  put(&g, "\033[?2026h");
  eq_u("BSU opens the region", (unsigned)g.sync, 1, "");
  eq_u("and is counted as one region", g.nSyncEngages, 1u, "");
  eq_u("without making the frame suspect", (unsigned)g.modelSuspect, 0, "a mode this file knows cannot be a swallowed byte");
  put(&g, "\033[?2026h");
  eq_u("a nested BSU does not stack", (unsigned)g.sync, 1, "xterm has no depth: the first ESU ends the region");
  eq_u("it counts", g.nSyncNested, 1u, "");
  eq_u("and does not open a second region", g.nSyncEngages, 1u, "the denominator stays honest");

  put(&g, "ab");
  eq_u("the region's writes are dirty", (unsigned)rc_row_dirty(&g, 0), 1, "");
  eq_u("and the bit does not consume them", (unsigned)g.sync, 1, "the model has no console to hold for");
  put(&g, "\033[?2026l");
  eq_u("ESU closes the region", (unsigned)g.sync, 0, "");
  eq_u("leaving the damage exactly where the seam left it", (unsigned)rc_row_dirty(&g, 0), 1,
       "this is the whole deferral contract: the next flush repaints what the region accumulated");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?2026l");
  eq_u("an ESU nobody armed changes nothing", (unsigned)g.sync, 0, "inert, not an error");
  eq_u("and opens no region to be counted against", g.nSyncEngages, 0u, "");

  /* I29's boundary, drawn from the model's side: a reply belongs to the reader, so the region must not be able
     to arm-or-not-arm it. The seam's half of the same rule is that it writes the queue during a hold; if the
     parser refused to arm while sync was set, a `tput rows` inside a frame would hang until the timeout. */
  put(&g, "\033[?2026h\033[6n");
  eq_u("a query inside a region still arms its reply", (unsigned)rc_report_pending(&g), 1u, "");
  eq_u("and arming it does not end the region", (unsigned)g.sync, 1, "");
  while (rc_report_pending(&g) > 0) { rc_report_take(&g, NULL); rc_report_result(&g, 1); }

  put(&g, "\033[?2026h");
  eq_u("the region is the one from the query leg, not a second", (unsigned)g.sync, 1, "nested");
  put(&g, "\033c");
  eq_u("RIS ends the region with everything else it ends", (unsigned)g.sync, 0,
       "leaving the bit set would hold the reset's own scroll forever");
  put(&g, "\033[?2026h");
  eq_u("and again", (unsigned)g.sync, 1, "");
  put(&g, "\033[!p");
  eq_u("DECSTR is the same full_reset and ends it the same way", (unsigned)g.sync, 0, "");
  eq_u("three BSUs, two openings", g.nSyncEngages, 2u,
       "the third was nested, and a reset closes a region without being an ESU or an engage -- the census "
       "counts what the application asked for, not what the mode ended up doing about it");

  rc_reset(&g, 20, 6, 0x07);
  eq_u("the family reads back clean after a geometry reset", g.nSyncNested, 0u, "");
  eq_u("including the holds", g.nSyncHeld, 0u, "rc_reset memsets the census with the grid");
}

/* ======================================================== 5. resumability ===================== */

static int grid_equal(const RcGrid *a, const RcGrid *b, char *why, size_t n)
{
  if (a->cx != b->cx || a->cy != b->cy)
  {
    snprintf(why, n, "cursor (%d,%d) vs (%d,%d)", a->cx, a->cy, b->cx, b->cy);
    return 0;
  }
  if (a->attr != b->attr) { snprintf(why, n, "attr 0x%04X vs 0x%04X", a->attr, b->attr); return 0; }
  if (a->charset != b->charset) { snprintf(why, n, "charset %d vs %d", a->charset, b->charset); return 0; }
  if (a->mode != b->mode) { snprintf(why, n, "mode %d vs %d", a->mode, b->mode); return 0; }
  if (a->nCells != b->nCells) { snprintf(why, n, "nCells %lu vs %lu", a->nCells, b->nCells); return 0; }
  if (a->nAstral != b->nAstral) { snprintf(why, n, "nAstral %lu vs %lu", a->nAstral, b->nAstral); return 0; }
  /* The damage overlay is part of what a chunk means. Two feeds that leave the same cells behind but
     disagree about which columns to repaint are not equivalent: one of them shows a stale screen. The
     split-feed leg is exactly where a range computed from a half-parsed sequence would first differ. */
  for (int r = 0; r < a->rows; r++)
  {
    if (RC_DTY(a, r) != RC_DTY(b, r))
    {
      snprintf(why, n, "damage row %d flagged %d vs %d", r, RC_DTY(a, r), RC_DTY(b, r));
      return 0;
    }
    if (!RC_DTY(a, r)) continue;
    if (RC_LO(a, r) != RC_LO(b, r) || RC_HI(a, r) != RC_HI(b, r))
    {
      snprintf(why, n, "damage row %d is %d..%d vs %d..%d", r,
               RC_LO(a, r), RC_HI(a, r), RC_LO(b, r), RC_HI(b, r));
      return 0;
    }
  }
  for (int r = 0; r < a->rows; r++)
    for (int c = 0; c < a->cols; c++)
      if (RC_CELLS(a, r)[c].ch != RC_CELLS(b, r)[c].ch || RC_CELLS(a, r)[c].attr != RC_CELLS(b, r)[c].attr)
      {
        snprintf(why, n, "cell(%d,%d) %04X/%04X vs %04X/%04X", r, c,
                 RC_CELLS(a, r)[c].ch, RC_CELLS(a, r)[c].attr, RC_CELLS(b, r)[c].ch, RC_CELLS(b, r)[c].attr);
        return 0;
      }
  /* The row state -- why a line ended, and what the shell claimed the row for (I20, I23) -- is part of what a
     chunk means even though no byte of it reaches the console. A 133 split across a chunk boundary that
     marked a different row than the same 133 delivered whole is the bug class this section exists to catch,
     and nothing above would notice. So does the FTCS content the cursor carries, because that is what decides
     the *next* line feed's claim. */
  for (int r = 0; r < a->rows; r++)
    if (RC_ST(a, r).wrap != RC_ST(b, r).wrap || RC_ST(a, r).mark != RC_ST(b, r).mark || RC_ST(a, r).col != RC_ST(b, r).col)
    {
      snprintf(why, n, "row %d state %d/%d/%d vs %d/%d/%d", r,
               RC_ST(a, r).wrap, RC_ST(a, r).mark, RC_ST(a, r).col, RC_ST(b, r).wrap, RC_ST(b, r).mark, RC_ST(b, r).col);
      return 0;
    }
  if (a->semanticContent != b->semanticContent || a->semanticClearEol != b->semanticClearEol)
  {
    snprintf(why, n, "semantic %d/%d vs %d/%d", a->semanticContent, a->semanticClearEol,
             b->semanticContent, b->semanticClearEol);
    return 0;
  }
  if (a->lastUnit != b->lastUnit) { snprintf(why, n, "lastUnit %u vs %u", a->lastUnit, b->lastUnit); return 0; }
  if (a->lastExit != b->lastExit) { snprintf(why, n, "lastExit %d vs %d", a->lastExit, b->lastExit); return 0; }
  return 1;
}

/*
 * Every grammar and geometry input, replayed one UTF-16 unit per rc_feed call against the
 * whole-string result. Both grids use the same geometry (20x6, default 0x07), so the comparison is
 * about the parser alone. A mismatch means a sequence means something different depending on where
 * the chunk boundary fell -- the failure class that put a literal "[33m" on the screen.
 */
static void check_resumable()
{
  static RcGrid whole, split;
  int bad = 0;
  char why[128];
  for (int i = 0; i < g_ncorpus; i++)
  {
    rc_reset(&whole, 20, 6, 0x07);
    rc_reset(&split, 20, 6, 0x07);
    putraw(&whole, g_corpus[i]);
    put1(&split, g_corpus[i]);
    g_checks++;
    if (grid_equal(&whole, &split, why, sizeof why)) continue;
    g_fails++;
    bad++;
    printf("FAIL  chunk-dependent: \"%s\" -> %s\n", g_corpus[i], why);
    if (bad > 6) break;
  }
  printf("resume  %d corpus strings replayed unit by unit\n", g_ncorpus);
}

/* ================================================================== 6. paint plan ============= */

/*
 * rc_plan_paint is the geometry the shipped Java writer kept tripping over, and it needs no console:
 * a view is seven integers. The shape used here is the one Windows Terminal and ConEmu present -- a
 * 120-column window whose buffer is exactly as wide as it, 9001 rows tall -- because the free slide and
 * the paid buffer scroll depend on where the window sits vertically. A buffer wider than the window is
 * conhost's default profile on this machine, and it has its own cases (geo_wrap_wide_buffer, and the
 * "wide buffer" / "h-scroll" plans below): the model row is bufW - winL, so those two shapes are the
 * whole difference.
 *
 * putraw(), not put(): these strings are about console geometry, and section 5 replays the corpus
 * against a 20x6 grid, where they would prove nothing.
 */
static RcView view(int bufW, int bufH, int winL, int winT, int winR, int winB,
                   uint16_t attr, int on, int curX, int curY)
{
  RcView v;
  v.bufW = bufW; v.bufH = bufH;
  v.winL = winL; v.winT = winT; v.winR = winR; v.winB = winB;
  v.attr = attr; v.cursorOn = on; v.curX = curX; v.curY = curY;
  /* A view nobody could read a cursor height from. 0 rather than 100: the plan is only allowed to claim
     a DECSCUSR change when it actually saw a console to compare against (Paint.cpp tests curHeight > 0),
     and a shape test says so out loud instead of inheriting a plausible-looking default. */
  v.curHeight = 0;
  return v;
}

/* The shape Windows Terminal and ConEmu present: the buffer is exactly as wide as the window, so the
   model row and the window row are the same thing. A wider buffer is its own case below.
   Out-parameter form, because C++ will not take the address of a returned struct. */
static void view36(RcView *v, int winT)
{
  *v = view(120, 9001, 0, winT, 119, winT + 35, 0x07, 1, 0, winT);
}

static void plan_plain(void)
{
  static RcGrid g; RcPlan p; RcView v;
  rc_reset(&g, 120, 36, 0x07);
  putraw(&g, "hello");
  view36(&v, 0);
  rc_plan_paint(&g, &v, &p);
  eq_u("plain: paints", (unsigned)p.reason, (unsigned)RC_PLAN_OK, "reason");
  eq_u("plain: one run", (unsigned)p.nRuns, 1, "row 0 only");
  eq_u("plain: run row", (unsigned)p.run[0].top, 0, "");
  eq_u("plain: run rows", (unsigned)p.run[0].nrows, 1, "");
  eq_u("plain: no slide", (unsigned)p.slideTo, (unsigned)-1, "nothing scrolled");
  eq_u("plain: no buffer scroll", (unsigned)p.bufScroll, 0, "");
  eq_u("plain: row0", (unsigned)p.row0, 0, "the window top");
  eq_u("plain: width is the buffer row", (unsigned)p.paintCols, 120, "bufW - winL, which is g->cols");
  eq_u("plain: run left", (unsigned)p.run[0].lo, 0, "the word starts at column 0");
  eq_u("plain: run right", (unsigned)p.run[0].hi, 4, "and the rectangle ends with it, not at the margin");
  eq_u("plain: cells", (unsigned long)p.cells, 5ul, "five cells, not a buffer row");
  eq_u("plain: cursor x", (unsigned)p.curTX, 5, "5 columns in");
  eq_u("plain: cursor y", (unsigned)p.curTY, 0, "row 0 of the window");
  eq_u("plain: cursor needs moving", (unsigned)p.cursorMoved, 1, "console has it at (0,0)");
  eq_u("plain: attribute unchanged", (unsigned)p.attrChanged, 0, "0x07 both sides");
  eq_u("plain: visibility unchanged", (unsigned)p.setVisible, 0, "");
}

/*
 * Where the cursor is parked when the line it follows is wider than the window. conhost slides the
 * viewport sideways to include a cursor it is told about -- the same behaviour Paint.cpp rule 3 spends
 * on purpose in the vertical axis, and the reason a wide buffer has one wrap point rather than two (see
 * the 2026-09-23 measurement in Render.java's caseWrap). So the plan clamps the parked column into the
 * window and the model keeps the real one: printing a 300-column table row must not shove the user's
 * view 180 columns to the right.
 */
static void plan_cursor_past_window(void)
{
  static RcGrid g; static uint16_t line[200]; RcPlan p; RcView v;
  int i;
  for (i = 0; i < 200; i++) line[i] = 'x';
  v = view(200, 9001, 0, 100, 119, 135, 0x07, 1, 0, 100);

  rc_reset(&g, 200, 36, 0x07);
  putu(&g, line, 80);
  rc_plan_paint(&g, &v, &p);
  eq_u("inside: parked where the model says", (unsigned)p.curTX, 80, "nothing to clamp");

  rc_reset(&g, 200, 36, 0x07);
  putu(&g, line, 150);                        /* past winR, still inside dwSize.X */
  eq_u("past: the model is at column 150", (unsigned)g.cx, 150, "no wrap before 200");
  rc_plan_paint(&g, &v, &p);
  eq_u("past: paints", (unsigned)p.reason, (unsigned)RC_PLAN_OK, "a window narrower than the row is not a decline");
  eq_u("past: width is the buffer row", (unsigned)p.paintCols, 200, "");
  eq_u("past: clamped to the window's last column", (unsigned)p.curTX, 119, "150 would drag the viewport");
  eq_u("past: the call is still made", (unsigned)p.cursorMoved, 1, "the console is at 0");
  v.curX = 119;                               /* the clamped park landed where the plan said */
  rc_plan_paint(&g, &v, &p);
  eq_u("past: stable, so it cannot walk the window sideways", (unsigned)p.cursorMoved, 0,
       "curTX 119 == the console's 119");
}

static void plan_scroll_is_free(void)
{
  static RcGrid g; RcPlan p; RcView v;
  rc_reset(&g, 120, 36, 0x07);
  rc_clear_dirty(&g);
  putraw(&g, "\033[36;1HA\r\nB");           /* the newline on the last row scrolls the viewport */
  eq_u("scroll counted in the model", (unsigned)g.pendingScrolls, 1, "");
  view36(&v, 100);
  rc_plan_paint(&g, &v, &p);
  eq_u("slide: no buffer scroll", (unsigned)p.bufScroll, 0, "the window can still travel down");
  eq_u("slide: park the cursor on", (unsigned)p.slideTo, 136, "winT+1+rows-1: conhost slides to include it");
  eq_u("slide: row0 follows", (unsigned)p.row0, 101, "model row 0 is now buffer row 101");
  eq_u("slide: one run", (unsigned)p.nRuns, 1, "the row written before the scroll, plus the scrolled-in row");
  eq_u("slide: run row", (unsigned)p.run[0].top, 34, "'A' rode up from row 35 and was never painted");
  eq_u("slide: run rows", (unsigned)p.run[0].nrows, 2,
       "two rows, not a screen: the other 34 shifted rows are already on screen at their new meaning");
  eq_u("slide: cells", (unsigned long)p.cells, 2ul * 120ul, "two rows, not a screen");
  eq_u("slide: cursor y", (unsigned)p.curTY, 136, "B sits on the bottom row, in buffer coords");
  rc_paint_done(&g);
  eq_u("paint_done consumes the scroll", (unsigned)g.pendingScrolls, 0, "");
  eq_u("paint_done clears damage", (unsigned)rc_row_dirty(&g, 35), 0, "");
}

static void plan_scroll_at_buffer_bottom(void)
{
  static RcGrid g; RcPlan p; RcView v;
  rc_reset(&g, 120, 36, 0x07);
  rc_clear_dirty(&g);
  putraw(&g, "\033[36;1HA\r\nB");
  view36(&v, 9001 - 36);
  rc_plan_paint(&g, &v, &p);   /* the window is already on the last row */
  eq_u("bottom: no slide", (unsigned)p.slideTo, (unsigned)-1, "nowhere left to go");
  eq_u("bottom: buffer scroll", (unsigned)p.bufScroll, 1, "the console moves the cells itself");
  eq_u("bottom: row0", (unsigned)p.row0, 9001 - 36, "the window stays at the bottom");
  eq_u("bottom: fill attribute", (unsigned)p.scrollAttr, 0x07, "the live attribute, as ConEmu does");
  eq_u("bottom: one run", (unsigned)p.nRuns, 1, "");
  eq_u("bottom: cursor needs moving", (unsigned)p.cursorMoved, 1, "its old row means something else now");

  /* straddling case: one row of slide available, the second scroll has to move the buffer */
  rc_reset(&g, 120, 36, 0x07);
  rc_clear_dirty(&g);
  putraw(&g, "\033[36;1HA\r\nB\r\nC");
  eq_u("straddle: two scrolls", (unsigned)g.pendingScrolls, 2, "");
  view36(&v, 9001 - 37);
  rc_plan_paint(&g, &v, &p);   /* free room for exactly one row */
  eq_u("straddle: slide", (unsigned)p.slideTo, 9000, "one row down puts the window on the last row");
  eq_u("straddle: rest is a buffer scroll", (unsigned)p.bufScroll, 1, "");
  eq_u("straddle: row0", (unsigned)p.row0, 9001 - 36, "ends at the bottom either way");
}

/* The alt screen's half of the same promise, where it can actually be seen: the model drops its scroll
 * queue at a switch (geo_alt), and the plan is what turns that into "nothing moved the console" plus "every
 * alt row is written again". A slide here would drag the user's view through the real buffer to make room
 * for a screen that is about to be blanked, and a buffer scroll would eat the main screen's scrollback --
 * both are what rule 1 is for on the main screen and neither is allowed on the alt. */
static void plan_alt(void)
{
  static RcGrid g; RcPlan p; RcView v;
  rc_reset(&g, 120, 36, 0x07);
  rc_clear_dirty(&g);
  putraw(&g, "\033[?1049h");
  view36(&v, 100);
  rc_plan_paint(&g, &v, &p);
  eq_u("alt entry: no slide", (unsigned)p.slideTo, (unsigned)-1, "the queue was empty and stays empty");
  eq_u("alt entry: no buffer scroll", (unsigned)p.bufScroll, 0, "the console's scrollback is the main screen's");
  eq_u("alt entry: one run", (unsigned)p.nRuns, 1, "");
  eq_u("alt entry: the viewport", (unsigned)p.run[0].nrows, 36, "a switch is a whole-screen repaint");
  eq_u("alt entry: every column", (unsigned long)p.cells, 36ul * 120ul, "");
  eq_u("alt entry: nothing dropped", (unsigned)p.drop, 0, "no row of the alt is above the window");

  /* Now the scroll *inside* the alt: three lines from the bottom row, which on the main screen would queue
     two slides and cost two rows of repaint (plan_scroll_is_free). */
  putraw(&g, "\033[36;1HL1\r\nL2\r\nL3");
  eq_u("alt scroll: nothing queued", (unsigned)g.pendingScrolls, 0, "there is no row above the alt to slide into");
  rc_plan_paint(&g, &v, &p);
  eq_u("alt scroll: no slide", (unsigned)p.slideTo, (unsigned)-1, "the window does not move");
  eq_u("alt scroll: no buffer scroll", (unsigned)p.bufScroll, 0, "the buffer does not move either");
  eq_u("alt scroll: the whole screen is the damage", (unsigned)p.run[0].nrows, 36,
       "a row that moved while clean is still a row that changed on screen");
  eq_text(&g, 35, 2, "L3", "the model scrolled, so the repaint carries the new rows");
  eq_text(&g, 33, 2, "L1", "two rows up from where it was written");

  /* Leaving is the same transaction in the other direction, and it is the one the user sees: the pager
     exits and the prompt's screen reappears in one paint, with nothing moved. */
  putraw(&g, "\033[?1049l");
  rc_plan_paint(&g, &v, &p);
  eq_u("alt exit: no slide", (unsigned)p.slideTo, (unsigned)-1, "");
  eq_u("alt exit: no buffer scroll", (unsigned)p.bufScroll, 0, "");
  eq_u("alt exit: full viewport run", (unsigned)p.run[0].nrows, 36, "what the alt overwrote goes back");

  /* With a gutter, the switch must reach the viewport only. This is the assertion that keeps the snapshot
     the size of the window: paint the scrollback here and an alt entry would cost a screenful of rows the
     console already shows correctly. */
  rc_reset_hist(&g, 120, 36, 36, 0x07);
  rc_clear_dirty(&g);
  putraw(&g, "\033[?1049h");
  view36(&v, 100);
  rc_plan_paint(&g, &v, &p);
  eq_u("alt entry with a gutter: row0 is above the window", (unsigned)p.row0, 64, "winT - gutter");
  eq_u("gutter: the run starts at the viewport", (unsigned)p.run[0].top, 36, "the 36 scrollback rows stay put");
  eq_u("gutter: and is the viewport tall", (unsigned)p.run[0].nrows, 36, "");
  eq_u("gutter: nothing dropped", (unsigned)p.drop, 0, "the clean rows above are not damage with nowhere to go");
}

static void plan_scroll_carries_damage(void)
{
  static RcGrid g; RcPlan p; RcView v;
  rc_reset(&g, 120, 36, 0x07);
  rc_clear_dirty(&g);
  putraw(&g, "\033[36;1HL1\r\nL2\r\nL3");     /* two viewport scrolls inside one chunk */
  eq_u("two scrolls buffered", (unsigned)g.pendingScrolls, 2, "");
  int d = 0;
  for (int r = 0; r < 36; r++) if (rc_row_dirty(&g, r)) d++;
  eq_u("damage rode with the content", d, 3, "rows 33, 34 and 35 -- not 35 alone");
  eq_u("L1's new row is dirty", (unsigned)rc_row_dirty(&g, 33), 1,
       "a flag left at the old row paints a blank over nothing and loses L1");
  eq_u("a row above the damage stays clean", (unsigned)rc_row_dirty(&g, 32), 0, "");
  eq_text(&g, 33, 2, "L1", "the write that preceded the scroll rode up to row 33");
  eq_text(&g, 35, 2, "L3", "the last line stays on the bottom row");
  view36(&v, 100);
  rc_plan_paint(&g, &v, &p);
  eq_u("contiguous damage is one run", (unsigned)p.nRuns, 1, "");
  eq_u("run top", (unsigned)p.run[0].top, 33, "");
  eq_u("run rows", (unsigned)p.run[0].nrows, 3, "");
  eq_u("slide two rows", (unsigned)p.slideTo, 137, "winT+2+rows-1");
  eq_u("row0 follows", (unsigned)p.row0, 102, "");
  eq_u("three rows of cells, not a screen", (unsigned long)p.cells, 3ul * 120ul, "");
}

/* The gutter: model rows above the viewport, holding text this chunk wrote and has not painted yet.
 *
 * A 36-row viewport alone cannot carry a chunk of more than one screenful -- the earliest lines get
 * shifted out of the grid while still waiting to be painted, and the buffer keeps blanks where ConEmu
 * leaves text. rc_reset_hist() adds the extra rows; the plan then maps them to the buffer rows *above*
 * the window, which is exactly where a slide leaves them. */
static void plan_gutter(void)
{
  static RcGrid g; RcPlan p; RcView v;
  rc_reset_hist(&g, 120, 36, 36, 0x07);       /* 72 model rows, the last 36 of them the window */
  rc_clear_dirty(&g);
  eq_u("gutter: scroll room", (unsigned)rc_scroll_room(&g), 36, "");
  eq_u("gutter: cursor starts on the viewport top", (unsigned)g.cy, 36, "not model row 0");

  /* 40 lines from the viewport top: five of them scroll past its edge into the gutter */
  for (int i = 1; i <= 40; i++)
  {
    char s[16];
    snprintf(s, sizeof s, "%02d\r\n", i);
    putraw(&g, s);
  }
  eq_u("gutter: scrolled", (unsigned)g.pendingScrolls, 5, "lines 36..40 each needed a row");
  eq_text(&g, 31, 2, "01", "line 1 rode into the gutter, it is still to be painted");
  eq_text(&g, 35, 2, "05", "the last gutter row");
  eq_text(&g, 36, 2, "06", "and the window starts here");
  eq_text(&g, 70, 2, "40", "the newest line, one row above the blank the last scroll left");
  eq_u("gutter: its rows are dirty", (unsigned)rc_row_dirty(&g, 31), 1, "");
  eq_u("gutter: above the damage stays clean", (unsigned)rc_row_dirty(&g, 30), 0, "");

  view36(&v, 100);
  rc_plan_paint(&g, &v, &p);
  eq_u("gutter: slide", (unsigned)p.slideTo, 140, "winT+5+winRows-1: the viewport, not the whole grid");
  eq_u("gutter: row0 is the model's, not the window's", (unsigned)p.row0, 69, "winT+5-gutter");
  eq_u("gutter: winTop is the window's", (unsigned)p.winTop, 105, "");
  eq_u("gutter: nothing dropped", (unsigned)p.drop, 0, "");
  eq_u("gutter: one run over the whole damage", (unsigned)p.nRuns, 1, "");
  eq_u("gutter: run top", (unsigned)p.run[0].top, 31, "buffer row 100: the scrollback the window left behind");
  eq_u("gutter: run rows", (unsigned)p.run[0].nrows, 41, "5 gutter rows + the 36 of the viewport");
  eq_u("gutter: cells", (unsigned long)p.cells, 41ul * 120ul, "");
  eq_u("gutter: cursor y", (unsigned)p.curTY, 140, "model row 71 == the window's last row");

  /* A buffer with no room above the window: the slide is impossible, so the scroll is paid with the
     buffer -- which pushes those five lines out of the console for good. Counted, not hidden: this is
     what a zero-scrollback terminal really does, and a plan that silently dropped *more* would be a bug. */
  v = view(120, 36, 0, 0, 119, 35, 0x07, 1, 0, 0);
  rc_plan_paint(&g, &v, &p);
  eq_u("no scrollback: slides nowhere", (unsigned)p.slideTo, (unsigned)-1, "");
  eq_u("no scrollback: buffer scroll", (unsigned)p.bufScroll, 5, "the console moves the cells");
  eq_u("no scrollback: row0", (unsigned)p.row0, (unsigned)-36, "the whole gutter is above the buffer");
  eq_u("no scrollback: the gutter is dropped", (unsigned)p.drop, 5, "one per scroll, as the buffer eats them");
  eq_u("no scrollback: run starts at the window", (unsigned)p.run[0].top, 36, "");
  eq_u("no scrollback: run rows", (unsigned)p.run[0].nrows, 36, "the viewport exactly");
}

/* The same anchor, asked the other question: an adopt has to know which rows to *read*, and a resize that
 * rebuilt the grid under it must not answer "the window's" when the model had a claim.
 *
 * conhost's rule for exactly this moment is worth taking whole (screenInfo.cpp:1103-1115): "in general we
 * want to avoid moving the virtual bottom unless it's aligned with the visible viewport" -- updated when the
 * viewport's bottom sweeps across it on the way to its new size, or when keeping it would leave the virtual
 * viewport poking above the buffer's top. The first is a slide the *user* made with the mouse while dragging
 * the window; the second is the guard that keeps a small buffer's content from being read at a negative row.
 *
 * And the sweep is a resize's rule only -- conhost keeps the two moments in different functions,
 * `_InternalSetViewportSize` (953, the check at 1110-1112) for a new window size and `SetViewportOrigin`
 * (642) for a scroll, where the sole adjustment is a one-directional advance (714). Hence the `reshaped`
 * argument, and the case at the bottom that fails if the flag is dropped.
 *
 * Carried in bottom form (`prevBase + prevRows - 1`) because the rebuilt grid has a different `rows`: the row
 * the content ends on is the one that means the same thing on both sides of the resize. */
static void adopt_anchor(void)
{
  /* A model with no claim -- a first adopt, a fresh session -- has nothing but the window to go on. Every
     other test in this file is that case; naming it here is what stops "we read the window" being mistaken
     for the rule rather than the fallback. */
  eq_u("adopt: unclaimed follows the window",
       (unsigned)rc_anchor_adopt(0, 0, 0, 0, 1, 0, 29, 400, 60, 30), (unsigned)(-30), "winT - gutter");

  /* The measured shape, and the reason the rule exists: the user scrolled to the top of a 400-row buffer
     (rows 0..29 in view, all of them their history), the model owns 340..399, and they drag the window from
     30 to 24 rows. Nothing about that gesture moved a cell, so the claim travels: the content's bottom row
     399 is 24 rows of viewport plus a 24-row gutter above it, i.e. model row 0 at 352. An adopt that read
     the *window* here would lift 24 history rows into the application's screen and paint them back at
     376..399 -- the user's own scrollback, one screen down, which is the reported damage arriving through
     the resize door. */
  eq_u("adopt: a resize keeps a claim the view never touched",
       (unsigned)rc_anchor_adopt(1, 340, 60, 29, 1, 0, 23, 400, 48, 24), (unsigned)352, "376..399, out of sight");

  /* A window that grows *over* the claim is a different gesture: the view is about to cover the content, so
     the anchor is the view's again -- conhost's first two clauses, which are one test each because they
     straddle in opposite directions. */
  eq_u("adopt: the view sweeping down over the content takes it",
       (unsigned)rc_anchor_adopt(1, 171, 60, 29, 1, 221, 250, 400, 60, 30), (unsigned)191,
       "the claim ended at 230, the window now ends at 250");
  eq_u("adopt: and sweeping up does too",
       (unsigned)rc_anchor_adopt(1, 340, 60, 399, 1, 310, 339, 400, 60, 30), (unsigned)280,
       "the user dragged the view back up to the content");
  /* Landing exactly on it is not a sweep: conhost compares `<` and `>`, and so does this. */
  eq_u("adopt: a view that reaches the anchor keeps it",
       (unsigned)rc_anchor_adopt(1, 340, 60, 29, 1, 370, 399, 400, 60, 30), (unsigned)340, "");

  /* The guard, stated with the numbers that make it fire rather than the sweep's: a claim too near the top of
     the buffer to anchor a 30-row viewport (its gutter would start above row 0) is conhost's `_virtualBottom
     < newViewport.Height() - 1`, and the read it prevents is one that would start at row -19. `prevWinB`
     equals the new bottom here on purpose -- nothing swept, so only the height can be what drops the claim. */
  eq_u("adopt: a claim too high for the new window is dropped",
       (unsigned)rc_anchor_adopt(1, -49, 60, 129, 1, 100, 129, 400, 60, 30), (unsigned)70,
       "the anchor ended at row 10, below the new viewport's own height");

  /* And too low: the buffer shrank from under the model (conhost clamps the window back into it, and the
     view went to 0..29 with it). The plan declines a paint at those rows and the adopt must not resurrect
     the claim, or the read would ask for rows the buffer no longer has. */
  eq_u("adopt: a claim below the buffer is dropped",
       (unsigned)rc_anchor_adopt(1, 380, 60, 399, 1, 0, 29, 400, 60, 30), (unsigned)(-30),
       "it ended at 439 of a 400-row buffer");

  /* A resize whose window never came near the claim: the user sat at the top of the buffer and dragged the
     bottom from 29 to 39. The fallback would read at row -40 -- i.e. at the history under their eyes, once
     the plan clipped it -- while the bottom that travels puts the new 40-row viewport at 360..399, still out
     of sight. This is also the arithmetic proof that the *bottom* is the form to carry: a grow whose window
     bottom does land on vb leaves fallback and carry identical (winT - winRows == vb - 2*winRows + 1), so a
     test of the rule has to move the window where the two disagree. */
  eq_u("adopt: a window grown away from the claim still carries it",
       (unsigned)rc_anchor_adopt(1, 340, 60, 29, 1, 0, 39, 400, 80, 40), (unsigned)320,
       "not winT - gutter == -40");

  /* The flag's own case, and the reason it exists: the same numbers as the sweeping-down check above, with a
     re-adopt that only re-read a console whose shape never changed. Applying the sweep here would drop the
     anchor precisely when the user had scrolled a whole screen away from the window -- the one situation the
     anchor is there for, and rule 2 arriving through the recovery path instead of the paint path. */
  eq_u("adopt: a scroll is not a resize",
       (unsigned)rc_anchor_adopt(1, 171, 60, 29, 0, 221, 250, 400, 60, 30), (unsigned)171,
       "the window's bottom passed the anchor, but nothing was resized");
}

/* The anchor: where the model's rows are is the model's business, not the window's.
 *
 * This is the case the shipped painter got wrong, and it is the one every other plan test cannot see: they
 * all hand the planner a window and take the row mapping from it, which is exactly right for a model that
 * has never painted and exactly wrong for one twenty minutes into a session. The user moving the view over
 * scrollback changes srWindow and no cell at all, so a plan that re-derives `row0` from it aims its
 * rectangles at the history the user was reading. Measured on a real console 2026-09-24: content at buffer
 * rows 30..59, view dragged to row 0, one prompt line through the renderer -> buffer row 29 rewritten, row
 * 30 blanked, 72 rectangles, nothing declined.
 *
 * conhost solves the same problem with `_virtualBottom`, "not affected by the user scrolling the viewport,
 * only when API calls cause the viewport to move" (screenInfo.hpp:218), and ghostty will not let a program
 * address the viewport at all (point.zig:26-30). Both then decline to follow output with the view:
 * ghostty's default is `{ keystroke = true, output = false }` (Config.zig:10446) and SnapOnOutput refuses
 * once the user has walked away (screenInfo.cpp:1715-1726). The three checks below are those two rules on
 * one axis. */
static void plan_anchor(void)
{
  static RcGrid g; RcPlan p; RcView v;

  /* A model that owns rows 100..135, a user looking at 20..55, and a two-cell edit. */
  rc_reset(&g, 120, 36, 0x07);
  rc_clear_dirty(&g);
  rc_set_base(&g, 100);
  putraw(&g, "NEW");
  view36(&v, 20);
  rc_plan_paint(&g, &v, &p);
  eq_u("anchor: paints", (unsigned)p.reason, (unsigned)RC_PLAN_OK, "a moved view is not a geometry change");
  eq_u("anchor: row0 is the model's", (unsigned)p.row0, 100, "not the view's 20: the edit goes where the text is");
  eq_u("anchor: run still row 0", (unsigned)p.run[0].top, 0, "model rows, which the executor maps with row0");
  eq_u("anchor: nothing slid", (unsigned)p.slideTo, (unsigned)-1, "sliding would drag the view through the buffer");
  eq_u("anchor: and nothing scrolled", (unsigned)p.bufScroll, 0, "no row moved in the model either");
  eq_u("anchor: the window stays put", (unsigned)p.winTop, 20, "the row the user scrolled to, as found");
  eq_u("anchor: cursor is off the view", (unsigned)p.cursorOffView, 1, "buffer row 100 of a window at 20..55");
  eq_u("anchor: so it is not parked", (unsigned)p.cursorMoved, 0, "parking there is how a slide happens");

  /* The same chunk one scroll later: the buffer pays, the view does not move. */
  rc_reset(&g, 120, 36, 0x07);
  rc_clear_dirty(&g);
  rc_set_base(&g, 100);
  putraw(&g, "\033[36;1HA\r\nB");
  eq_u("anchor: one scroll queued", (unsigned)g.pendingScrolls, 1, "setup");
  view36(&v, 20);
  rc_plan_paint(&g, &v, &p);
  eq_u("scrolled away: no free slide", (unsigned)p.slideRows, 0, "rule 2: the view is not ours to move");
  eq_u("scrolled away: the buffer pays", (unsigned)p.bufScroll, 1, "which is what conhost does with the same newline");
  eq_u("scrolled away: row0 unchanged", (unsigned)p.row0, 100, "a buffer scroll moves cells under the anchor");
  eq_u("scrolled away: window unmoved", (unsigned)p.winTop, 20, "");

  /* The default, stated so it cannot be mistaken for the bug: a model that has never claimed a row has no
     evidence but the window, and follows it. This is every other plan test in this file, named. */
  rc_reset(&g, 120, 36, 0x07);
  rc_clear_dirty(&g);
  putraw(&g, "\033[36;1HA\r\nB");
  view36(&v, 20);
  rc_plan_paint(&g, &v, &p);
  eq_u("unclaimed: the window is the anchor", (unsigned)p.row0, 21, "winT+slide, as it has always been");
  eq_u("unclaimed: and it slides", (unsigned)p.slideTo, 56, "the first paint defines where the model lives");
  eq_u("unclaimed: cursor moved", (unsigned)p.cursorMoved, 1, "it is inside the window the plan just chose");

  /* A view *below* the claim advances it, and never the other way round (screenInfo.cpp:714-717): an
     anchor left behind the content would paint the next frame into rows nobody is looking at. */
  rc_reset(&g, 120, 36, 0x07);
  rc_clear_dirty(&g);
  rc_set_base(&g, 100);
  putraw(&g, "LOW");
  view36(&v, 120);
  rc_plan_paint(&g, &v, &p);
  eq_u("ahead of the anchor: paints", (unsigned)p.reason, (unsigned)RC_PLAN_OK, "");
  eq_u("ahead of the anchor: row0 follows the view", (unsigned)p.row0, 120, "never pulled back to 100");
  eq_u("ahead of the anchor: the slide is on the table again", (unsigned)p.cursorOffView, 0, "");

  /* An anchor the buffer cannot hold is a geometry change, and the answer to that is the one this module
     already has: decline, and let the caller re-read the console. A shrink from under the model is the way
     to get here, and writing at row 8990+72 of a 9001-row buffer is not an alternative. */
  rc_reset(&g, 120, 36, 0x07);
  rc_clear_dirty(&g);
  rc_set_base(&g, 8990);
  putraw(&g, "EDGE");
  view36(&v, 9001 - 36);
  rc_plan_paint(&g, &v, &p);
  eq_u("past the end: declines", (unsigned)p.reason, (unsigned)RC_PLAN_NOGEOM, "re-adopt, then paint");
  eq_u("past the end: names no rows", (unsigned)p.row0, 0, "nothing may address a row it did not plan");
  eq_u("past the end: no scroll asked for", (unsigned)p.bufScroll, 0, "");
  eq_u("past the end: no columns", (unsigned)p.paintCols, 0, "");

  /* And the claim is droppable: an operation that failed to land leaves the model not knowing where its own
     rows are, which is worth a repaint of the viewport and not a rectangle at a guess. */
  rc_drop_base(&g);
  eq_u("dropped: the viewport goes dirty", (unsigned)rc_row_dirty(&g, 35), 1, "the promise is a repaint, not silence");
  rc_plan_paint(&g, &v, &p);
  eq_u("dropped: re-derived from the window", (unsigned)p.row0, 8965, "the same answer the unclaimed model gives");
}

/* Rule 1b, on the two shapes the console gate measured and no arithmetic can be trusted without: which
 * buffer rows a buffer scroll moves, and where it puts them.
 *
 * The destination `ScrollConsoleScreenBuffer` is handed is absolute, and conhost turns it into a displacement
 * by subtracting the source's own top (getset.cpp:948, then TextBuffer::ScrollAndClear). A plan whose slide
 * paid none of the debt therefore wants the rows the *anchor* held -- `base + k` downward, where k is the whole
 * shift -- landing on `row0`. Get either end wrong and the damage is invisible in the window, because every
 * row of the window is dirty and repainted anyway; what it moves instead is the scrollback above it, which is
 * the one thing rule 2 exists to protect.
 *
 * And the reach is two-valued, which is the part a first cut here got wrong in the other direction: once the
 * claim this flush *leaves behind* has the buffer's last row, the rows above it are the ring's own tail and a
 * new line can only be paid for by evicting the oldest one, so the source starts at `by` and lands on row 0
 * (conhost `_stream.cpp:123-126` -> `TextBuffer::IncrementCircularBuffer`). It is the plan's destination that
 * decides, not the anchor it started from: a slide that saturates against the bottom of the buffer always ends
 * on that row, whatever the claim looked like before the flush. Both branches are pinned below, on the same
 * numbers. */
static void plan_scroll_band(void)
{
  static RcGrid g; RcPlan p; RcView v;
  int top = -1, bottom = -1, n;

  /* The saturated case the gate measured, and the buffer's-full case besides: 60 model rows over a 400-row
     buffer, the anchor at 340 with the window on the buffer's last row, and 20 newlines the window has no
     room left to slide for. The claim ends on row 399, so there is nowhere below it to write and the scroll
     is an eviction: the whole buffer rides up and the top 20 lines leave. */
  rc_reset_hist(&g, 200, 30, 30, 0x07);
  rc_clear_dirty(&g);
  rc_set_base(&g, 340);
  putraw(&g, "\033[30;1HA\r\n");             /* the viewport's last row, so the newline is a scroll */
  for (int i = 0; i < 19; i++) putraw(&g, "B\r\n");
  eq_u("band: the debt is 20 scrolls", (unsigned)g.pendingScrolls, 20, "setup");
  v = view(200, 400, 0, 370, 99, 399, 0x07, 1, 0, 399);
  rc_plan_paint(&g, &v, &p);
  eq_u("band: nothing left to slide", (unsigned)p.slideRows, 0, "setup: the window is on the buffer's bottom");
  eq_u("band: the buffer pays all of it", (unsigned)p.bufScroll, 20, "setup");
  eq_u("band: row0 stays claimed", (unsigned)p.row0, 340, "a buffer scroll moves cells under the anchor");
  eq_u("band: the claim reaches the buffer's last row", (unsigned)(p.row0 + g.rows),
       (unsigned)v.bufH, "setup: the plan's own destination decides which of the two reaches applies, and "
                         "nothing else -- the anchor this flush started from is a different row and a "
                         "different answer (see the mixed case below)");
  n = rc_scroll_band(&p, g.rows, v.bufH, &top, &bottom);
  eq_u("full: the source starts at the buffer's top", (unsigned)top, 20,
       S("`by` rows down, because the `by` above it are the lines leaving the terminal (got %d..%d)", top, bottom));
  eq_u("full: and runs to the claim's last row", (unsigned)bottom, 399, "");
  eq_u("full: every live row rides up", (unsigned)n, 380, "the 60 inside the claim and the 320 above it");
  eq_u("full: it lands on row 0", (unsigned)(top - p.bufScroll), 0,
       "the destination is absolute; `by` above this source row is the buffer's first row");
  eq_u("full: the scrollback is in it", (unsigned)(top < p.row0), 1,
       S("rows 0..%d are the user's, and a full buffer owes their eviction for this line -- in order, one "
         "shift, not a rewrite", p.row0 - 1));
  /* The half the eviction must not disturb: inside the claim, the rows that move and where they land are the
     same as they were for a band scroll, because the model's own shift of `by` is unchanged. Get *that* end
     wrong and the paint below the eviction is misfiled by `by` rows -- damage in the newest lines rather than
     in the oldest ones, which is the harder direction to notice. */
  eq_u("full: the user's rows that join the band", (unsigned)(p.row0 - top), 320,
       S("rows %d..%d of their scrollback ride with it, in one shift and in order", top, p.row0 - 1));
  eq_u("full: the claim's own rows ride as before", (unsigned)(bottom - p.row0 + 1), 60,
       "the whole claim is inside the band, and 60 is what the band scroll moved before this branch existed");
  eq_u("full: the shift carries 40 of them into the claim",
       (unsigned)(bottom - (p.row0 + p.bufScroll) + 1), 40,
       S("and the %d the shift cannot carry are new lines the paint writes", p.bufScroll));
  for (int r = g.rows - p.bufScroll; r < g.rows; r++)
    eq_u("full: the rows it leaves behind are painted", (unsigned)rc_row_dirty(&g, r), 1,
         S("model row %d has no cell above it to move down: the scroll vacates it", r));

  /* The mixed flush, and the case the first cut of this function got wrong: 19 of the debt paid by sliding the
     window, the 20th by the buffer. The slide saturates -- `free_slide` was exactly 19 -- and a saturated slide
     always lands the claim on the buffer's last row, because row0 = base + (bufH - rows - base) = bufH - rows.
     So this is the eviction branch even though the *anchor* the flush started from stopped 19 rows short of
     it: the buffer holds 401 live lines once these 20 newlines are in, and a row cannot hold two of them. The
     source still stops where the old claim stopped, because the 19 rows below it moved no cell -- the slide
     moved the window, not the content. */
  rc_reset_hist(&g, 200, 30, 30, 0x07);
  rc_clear_dirty(&g);
  rc_set_base(&g, 321);
  putraw(&g, "\033[30;1HA\r\n");
  for (int i = 0; i < 19; i++) putraw(&g, "B\r\n");
  v = view(200, 400, 0, 351, 99, 380, 0x07, 1, 0, 380);
  rc_plan_paint(&g, &v, &p);
  eq_u("mixed: slide pays 19", (unsigned)p.slideRows, 19, "setup: the buffer has 19 rows left below the window");
  eq_u("mixed: and the buffer 1", (unsigned)p.bufScroll, 1, "setup");
  eq_u("mixed: a saturated slide ends on the last row", (unsigned)(p.row0 + g.rows), (unsigned)v.bufH,
       "the corollary, and the reason this flush evicts while the one below does not");
  eq_u("mixed: though the anchor it started from did not", (unsigned)(p.row0 - p.slideRows + g.rows),
       (unsigned)(v.bufH - p.slideRows), "381: a reach keyed on that row is what lost a line in the middle");
  n = rc_scroll_band(&p, g.rows, v.bufH, &top, &bottom);
  eq_u("mixed: so the source starts at the debt", (unsigned)top, 1,
       "the one line above it leaves the top of the buffer, in order, rather than being overwritten in place");
  eq_u("mixed: and ends where the *anchor* ended", (unsigned)bottom, 380,
       S("not 399: rows 381..399 are the slide's doing, and the slide moves no cell (got %d..%d)", top, bottom));
  eq_u("mixed: rows to move", (unsigned)n, 380, "the user's 339 above the claim and the 41 inside it");
  eq_u("mixed: lands on row 0", (unsigned)(top - p.bufScroll), 0, "");
  eq_u("mixed: the band carries 40 of the claim's rows",
       (unsigned)(bottom - (p.row0 + p.bufScroll) + 1), 40,
       S("%d..%d land on the claim's first 40 rows", p.row0 + p.bufScroll, bottom));
  eq_u("mixed: 40 plus the 19 slid and the 1 new is the grid",
       (unsigned)(40 + p.slideRows + p.bufScroll), (unsigned)g.rows,
       "the slide's rows are painted, not carried: it moved the window and no cell");

  /* The branch the mixed case proves is not dead: a debt the model carries while the user is looking at their
     own scrollback, with buffer rows still empty below the claim. The window is not on the model's rows, so
     rule 2 offers no slide at all and the whole debt is the buffer's; but the claim ends at row 259 of 400,
     so nothing here is owed an eviction. Moving the user's rows on this flush is the same mistake in the other
     direction -- it destroys lines the terminal still had room for. */
  rc_reset_hist(&g, 200, 30, 30, 0x07);
  rc_clear_dirty(&g);
  rc_set_base(&g, 200);
  putraw(&g, "\033[30;1HA\r\n");
  for (int i = 0; i < 4; i++) putraw(&g, "B\r\n");
  v = view(200, 400, 0, 100, 99, 129, 0x07, 1, 0, 129);   /* the user scrolled 270 rows above the bottom */
  rc_plan_paint(&g, &v, &p);
  eq_u("room: the view is the user's", (unsigned)p.slideRows, 0, "rule 2: no slide for a window we do not own");
  eq_u("room: so the buffer pays all 5", (unsigned)p.bufScroll, 5, "setup");
  eq_u("room: and the claim stops short of the last row", (unsigned)(p.row0 + g.rows < v.bufH), 1,
       "200 + 60 < 400: the 140 rows below it are empty, so an eviction would be theft");
  n = rc_scroll_band(&p, g.rows, v.bufH, &top, &bottom);
  eq_u("room: the source stays inside the claim", (unsigned)top, 205, "");
  eq_u("room: to the claim's last row", (unsigned)bottom, 259, "");
  eq_u("room: rows to move", (unsigned)n, 55, "the 60 the model holds less the 5 it cannot carry");
  eq_u("room: lands on the claim", (unsigned)(top - p.bufScroll), (unsigned)p.row0, "");
  eq_u("room: nothing of the user's is in it", (unsigned)(top >= p.row0), 1,
       S("rows 0..%d are theirs and this flush owes them nothing (got %d..%d)", p.row0 - 1, top, bottom));

  /* A debt the whole band cannot pay, with room still below it: not a scroll at all. scroll_up() blanks and
     marks every row when the shift is the grid's height, so the paint that follows covers the band completely
     and moving nothing is both the safe answer and the cheap one. */
  memset(&p, 0, sizeof p);
  p.row0 = 300; p.slideRows = 0; p.bufScroll = 60;
  n = rc_scroll_band(&p, 60, 400, &top, &bottom);
  eq_u("whole: nothing to move", (unsigned)n, 0, "an empty source is a no-op, not a failed call");

  /* The same debt on a buffer that is full, by contrast, *is* a scroll: 60 lines of output the model cannot
     carry are 60 lines the terminal has to evict, and the eviction is owed whether or not the band kept
     anything. This is the pair that says the two reaches are not one rule wearing two hats. */
  memset(&p, 0, sizeof p);
  p.row0 = 340; p.slideRows = 0; p.bufScroll = 60;
  n = rc_scroll_band(&p, 60, 400, &top, &bottom);
  eq_u("whole: on a full buffer the eviction is still owed", (unsigned)n, 340,
       S("%d..%d ride up by 60, the top 60 leave", top, bottom));
  eq_u("whole: and it lands on row 0", (unsigned)(top - p.bufScroll), 0, "");

  /* And the gutter's own clamp: a claim that reaches above the buffer's first row has cells there in the
     model and no rows to hold them on screen. The band may start at row 0 and no lower -- but the *shift* it
     carries is still `by`, which is what puts the request's destination above row 0. That is left to conhost
     on purpose: ScrollRegion pins the target to the clip and shrinks the source to match
     (host/output.cpp:365-397), the same result as "shift by `by`, lose what hangs off the top". Clamping `by`
     down here instead would under-move the model's own rows, which is damage inside the claim. */
  memset(&p, 0, sizeof p);
  p.row0 = -10; p.slideRows = 0; p.bufScroll = 5;
  n = rc_scroll_band(&p, 60, 400, &top, &bottom);
  eq_u("gutter: clamped to the first row", (unsigned)top, 0, "");
  eq_u("gutter: ends where the claim ends", (unsigned)bottom, 49, "");
  eq_u("gutter: still a band", (unsigned)(n > 0), 1, S("%d rows", n));
  eq_u("gutter: and the debt is not reduced to pay for the clamp", (unsigned)(p.bufScroll - top), 5,
       S("dest = top - by = %d, above the buffer: conhost's to trim, not this band's", top - p.bufScroll));
  eq_u("gutter: rows conhost actually moves", (unsigned)(bottom - p.bufScroll + 1), 45,
       S("it moves [%d..%d] onto [0..%d]: the band's first %d rows are the lines leaving the top, and the rows "
         "it vacates are painted anyway", p.bufScroll, bottom, bottom - p.bufScroll, p.bufScroll - top));
}

/* rc_feed() must not wait for flush() when a chunk outruns the gutter: the hook is what keeps the
 * earliest lines alive, and it runs with a consistent grid and a half-consumed input. The witness here
 * is the one that matters -- every line of a five-screenful chunk reaches a paint operation. */
static int g_fires, g_fireBadRoom, g_fireUncovered;
static unsigned long g_paintLines;

static void hook_watch(void *ctx)
{
  RcGrid *g = (RcGrid *)ctx;
  RcView v; RcPlan p;
  g_fires++;
  if (g->pendingScrolls != rc_scroll_room(g)) g_fireBadRoom++;
  view36(&v, 48);                    /* any window position with room above it: damage, not geometry */
  rc_plan_paint(g, &v, &p);
  g_fireUncovered += p.drop;
  for (int r = 0; r < g->rows; r++)
  {
    if (!rc_row_dirty(g, r)) continue;
    int in = 0;
    for (int i = 0; i < p.nRuns; i++)
      if (r >= p.run[i].top && r < p.run[i].top + p.run[i].nrows) { in = 1; break; }
    if (!in) g_fireUncovered++;      /* damaged and not scheduled: the next scroll would bury it */
  }
  for (int i = 0; i < p.nRuns; i++)
    for (int r = p.run[i].top; r < p.run[i].top + p.run[i].nrows; r++)
      if (RC_CELLS(g, r)[0].ch >= '0' && RC_CELLS(g, r)[0].ch <= '9') g_paintLines++;
  rc_paint_done(g);                          /* stand in for the painter */
}

static void plan_gutter_hook(void)
{
  static RcGrid g;
  rc_reset_hist(&g, 120, 36, 4, 0x07);        /* a small gutter so the hook fires often */
  g.onFlush = hook_watch;
  g.flushCtx = &g;
  g_fires = g_fireBadRoom = g_fireUncovered = 0;
  g_paintLines = 0;
  for (int i = 1; i <= 200; i++)
  {
    char s[16];
    snprintf(s, sizeof s, "%03d\r\n", i);
    putraw(&g, s);
  }
  eq_u("hook: fired per gutter load", (unsigned)g_fires, 41, "165 scrolls / room 4");
  eq_u("hook: every fire at the room limit", (unsigned)g_fireBadRoom, 0, "");
  eq_u("hook: a fire never left a row unpainted", (unsigned)g_fireUncovered, 0,
       "run later and the gutter would already have overflowed");
  eq_u("hook: left one scroll for the final flush", (unsigned)g.pendingScrolls, 1, "");
  eq_u("hook: scrolls counted once", (unsigned)g.nScrolls, 165, "lines 36..200 each needed a row");

  RcView v; RcPlan p;
  view36(&v, 48);
  rc_plan_paint(&g, &v, &p);
  eq_u("hook: final plan drops nothing", (unsigned)p.drop, 0, "");
  for (int i = 0; i < p.nRuns; i++)
    for (int r = p.run[i].top; r < p.run[i].top + p.run[i].nrows; r++)
      if (RC_CELLS(&g, r)[0].ch >= '0' && RC_CELLS(&g, r)[0].ch <= '9') g_paintLines++;
  rc_paint_done(&g);
  eq_u("hook: all 200 lines reached a paint", (unsigned long)g_paintLines, 200ul,
       "five screenfuls through a 36-row window: none of it may vanish");
  eq_u("hook: painting left the grid alone", (unsigned)rc_row_dirty(&g, 39), 0, "");
}

static void plan_runs(void)
{
  static RcGrid g; RcPlan p; RcView v;
  rc_reset(&g, 120, 36, 0x07);
  rc_clear_dirty(&g);
  putraw(&g, "\033[1;1H1\033[2;1H2\033[6;1H6");
  view36(&v, 0);
  rc_plan_paint(&g, &v, &p);
  eq_u("runs: two", (unsigned)p.nRuns, 2, "rows 0-1 and row 5");
  eq_u("runs: first top", (unsigned)p.run[0].top, 0, "");
  eq_u("runs: first len", (unsigned)p.run[0].nrows, 2, "contiguous rows merge");
  eq_u("runs: second top", (unsigned)p.run[1].top, 5, "");
  eq_u("runs: second len", (unsigned)p.run[1].nrows, 1, "");
  eq_u("runs: first left", (unsigned)p.run[0].lo, 0, "each row was written at column 0");
  eq_u("runs: first right", (unsigned)p.run[0].hi, 0, "one column, not the buffer row");
  eq_u("runs: cells", (unsigned long)p.cells, 3ul, "three rows x one column");

  /* more separate runs than the plan can name: repaint the whole damaged band as one */
  rc_reset(&g, 120, 36, 0x07);
  rc_clear_dirty(&g);
  for (int i = 1; i <= 9; i++)
  {
    char s[16];
    snprintf(s, sizeof s, "\033[%d;1HX", i * 3);
    putraw(&g, s);
  }
  view36(&v, 0);
  rc_plan_paint(&g, &v, &p);
  eq_u("overflow: one band", (unsigned)p.nRuns, 1, "capped, not dropped");
  eq_u("overflow: band top", (unsigned)p.run[0].top, 2, "first damaged row (line 3)");
  eq_u("overflow: band rows", (unsigned)p.run[0].nrows, 25, "through line 27, clean rows included");
  eq_u("overflow: band right", (unsigned)p.run[0].hi, 0, "every mark is in column 0, so the band is one wide");
  eq_u("overflow: band cells", (unsigned long)p.cells, 25ul, "the cap widens a band to its damage, not to the row");
}

/*
 * B2 at the plan level: the rectangle conhost is told about is the damage, not the row. This is the half
 * of the change that loses pixels silently -- too wide only costs time, too narrow erases work the model
 * already believes it painted -- so the two cases MSFT names are pinned here, and the width the model
 * *stores* is pinned alongside them so nobody reads "paints less" as "keeps less" (I7).
 */
static void plan_damage_range(void)
{
  static RcGrid g; RcPlan p; RcView v;

  rc_reset(&g, 2000, 36, 0x07);
  putraw(&g, "\033[1;1501HX");              /* column 1500 of a buffer row wider than any window */
  v = view(2000, 9001, 0, 100, 119, 135, 0x07, 1, 0, 100);
  rc_plan_paint(&g, &v, &p);
  eq_u("wide: paints", (unsigned)p.reason, (unsigned)RC_PLAN_OK, "a 2000-column model row is still the model (I7)");
  eq_u("wide: the row is still 2000 cells", (unsigned)p.paintCols, 2000, "the geometry test is untouched by B2");
  eq_u("wide: one run", (unsigned)p.nRuns, 1, "");
  eq_u("wide: run left", (unsigned)p.run[0].lo, 1500, "the rectangle starts where the damage is");
  eq_u("wide: run right", (unsigned)p.run[0].hi, 1500, "");
  eq_u("wide: one cell moved, not a row", (unsigned long)p.cells, 1ul, "this is what B2 buys");

  /* A scroll gives the damage a new row number; the columns belong to the content. The scrolled-in row
     is whole and not next door -- the write was on row 3, the newline on the viewport's last -- so the
     plan keeps them as two rectangles and the translation is visible in one of them. */
  rc_reset(&g, 120, 36, 0x07);
  rc_clear_dirty(&g);
  putraw(&g, "\033[4;41Habc\033[36;1H\r\n");
  eq_span(&g, 2, 40, 42, "the row rode up one and its columns came with it");
  eq_full(&g, 35, "the row that scrolled in is unknown, so it is all of it");
  eq_u("translated: still clean above", (unsigned)rc_row_dirty(&g, 1), 0, "the shift may not claim neighbours");
  view36(&v, 100);
  rc_plan_paint(&g, &v, &p);
  eq_u("translated: two runs", (unsigned)p.nRuns, 2, "damage and scrolled-in row are not contiguous");
  eq_u("translated: run0 top", (unsigned)p.run[0].top, 2, "");
  eq_u("translated: run0 left", (unsigned)p.run[0].lo, 40, "");
  eq_u("translated: run0 right", (unsigned)p.run[0].hi, 42, "");
  eq_u("translated: run1 top", (unsigned)p.run[1].top, 35, "");
  eq_u("translated: run1 is whole", (unsigned)p.run[1].hi, 119, "");
  eq_u("translated: cells", (unsigned long)p.cells, 3ul + 120ul, "three cells and one row, not two rows");

  /* Contiguous rows merge into one rectangle, which is the union of their columns: paying for the gap
     between two damaged ends is the price of one call instead of two, and the bound is the damage. */
  rc_reset(&g, 120, 36, 0x07);
  rc_clear_dirty(&g);
  putraw(&g, "\033[1;11Ha\033[2;91Hb");
  view36(&v, 0);
  rc_plan_paint(&g, &v, &p);
  eq_u("merged: one run", (unsigned)p.nRuns, 1, "rows 0 and 1 are neighbours");
  eq_u("merged: union left", (unsigned)p.run[0].lo, 10, "");
  eq_u("merged: union right", (unsigned)p.run[0].hi, 90, "");
  eq_u("merged: cells", (unsigned long)p.cells, 2ul * 81ul, "81 columns twice, not the buffer row twice");

  /* The capped band is the one place a row is painted that nothing damaged. Its width still has to
     cover every damaged row in it -- including the first, whose column no later row shares. */
  rc_reset(&g, 120, 36, 0x07);
  rc_clear_dirty(&g);
  putraw(&g, "\033[1;11Ha");
  for (int i = 1; i <= 9; i++)
  {
    char s[24];
    snprintf(s, sizeof s, "\033[%d;101HX", i * 3);
    putraw(&g, s);
  }
  view36(&v, 0);
  rc_plan_paint(&g, &v, &p);
  eq_u("capped: one band", (unsigned)p.nRuns, 1, "");
  eq_u("capped: band top", (unsigned)p.run[0].top, 0, "the first damaged row");
  eq_u("capped: band rows", (unsigned)p.run[0].nrows, 27, "through the last, clean rows included");
  eq_u("capped: band left", (unsigned)p.run[0].lo, 10, "column 10 belongs to row 0 alone");
  eq_u("capped: band right", (unsigned)p.run[0].hi, 100, "");
  eq_u("capped: cells", (unsigned long)p.cells, 27ul * 91ul, "the band's union, not the buffer row");
}

static void plan_declines(void)
{
  static RcGrid g; RcPlan p;
  RcView v;
  rc_reset(&g, 120, 36, 0x07);
  putraw(&g, "x");

  /* Narrowing the *window* is not a geometry loss: the rows still describe the buffer they were built
     for, and the painter writes from winL to the buffer's edge whatever the window shows. The two
     changes that do invalidate the model are the buffer row's width and the viewport's height. */
  view36(&v, 0); v.winR = 99;                        /* the window was resized narrower */
  rc_plan_paint(&g, &v, &p);
  eq_u("narrower window: paints", (unsigned)p.reason, (unsigned)RC_PLAN_OK,
       "the model row is the buffer row, and neither moved");

  view36(&v, 0); v.winL = 20;                        /* the view was scrolled sideways */
  rc_plan_paint(&g, &v, &p);
  eq_u("h-scroll: declines", (unsigned)p.reason, (unsigned)RC_PLAN_NOGEOM, "the model is 120 wide, the row is 100");

  view36(&v, 0); v.winB = 34;                        /* one row shorter */
  rc_plan_paint(&g, &v, &p);
  eq_u("shorter window: declines", (unsigned)p.reason, (unsigned)RC_PLAN_NOGEOM, "winRows is 36");

  /* This is the shape this module got wrong until 2026-09-23: a 120-column window inside the 2000-column
     buffer that conhost's own profile gives a fresh console (measured: 2000x9001 buffer, 120x60 window).
     A 120-column model would wrap a report that conhost is going to print 2000 columns wide. */
  view36(&v, 0); v.bufW = 2000;
  rc_plan_paint(&g, &v, &p);
  eq_u("wide buffer: declines", (unsigned)p.reason, (unsigned)RC_PLAN_NOGEOM,
       "the buffer row is 2000, the model was built for 120");
  eq_u("wide buffer: paints nothing", (unsigned)p.paintCols, 0, "");

  rc_reset(&g, 120, 36, 0x07);
  putraw(&g, "\033[10;10H");                       /* a cursor move is not damage */
  view36(&v, 0); v.curX = 0; v.curY = 0;
  rc_plan_paint(&g, &v, &p);
  eq_u("cursor only: nothing to paint", (unsigned)p.reason, (unsigned)RC_PLAN_EMPTY, "");
  eq_u("cursor only: no runs", (unsigned)p.nRuns, 0, "");
  eq_u("cursor only: still moves the cursor", (unsigned)p.cursorMoved, 1, "");
  eq_u("cursor only: target", (unsigned)p.curTY, 9, "model row 9 at winT 0");

  putraw(&g, "\033[3;3H");                          /* and if the console is already there, no call */
  view36(&v, 0); v.curX = 2; v.curY = 2;
  rc_plan_paint(&g, &v, &p);
  eq_u("already there: no cursor call", (unsigned)p.cursorMoved, 0, "");

  view36(&v, 0); v.attr = 0x30;                      /* the console holds a colour we do not */
  rc_plan_paint(&g, &v, &p);
  eq_u("attribute drift is noticed", (unsigned)p.attrChanged, 1, "chunk must write it back");
  view36(&v, 0); v.cursorOn = 0;
  rc_plan_paint(&g, &v, &p);
  eq_u("hidden cursor while ?25h is in effect", (unsigned)p.setVisible, 1, "");

  /* a horizontally scrolled view: the model's column 0 is the window's left edge, and the row still
     runs from there to the buffer's right edge -- so it is wider than the window by whatever the user
     scrolled off, and the paint starts at winL rather than at 0. */
  rc_reset(&g, 120, 36, 0x07);
  putraw(&g, "x");
  v = view(160, 9001, 40, 0, 159, 35, 0x07, 1, 40, 0);
  rc_plan_paint(&g, &v, &p);
  eq_u("h-scroll: reason", (unsigned)p.reason, (unsigned)RC_PLAN_OK, "");
  eq_u("h-scroll: width", (unsigned)p.paintCols, 120, "160 - 40");
  eq_u("h-scroll: starts at the window's left", (unsigned)(p.run[0].top), 0, "rect Left is v.winL");
  eq_u("h-scroll: cursor x", (unsigned)p.curTX, 41, "winL + model column 1");
}

/* Snap-on-input: the row a keystroke is allowed to bring into view, and the four reasons it may not.
 *
 * This is the other half of rule 2's contract. Rule 2 says a flush may not move a window the user scrolled
 * away from; a keystroke is the one event that says the user is done looking and wants their prompt, and
 * conhost implements exactly that pair (input.cpp:177 -> SnapOnInput -> _makeCursorVisible ->
 * MakeCursorVisible, screenInfo.cpp:1631-1712). Two of its facts are pinned here because getting them wrong
 * is damage rather than a cosmetic miss: the target is the *cursor's* row, so the window moves the least way
 * that reveals it (snapping to the buffer's last row would throw a user who read one line of history past
 * everything above the prompt), and an invisible cursor means an application owns the screen, so a key must
 * not drag the view under it mid-frame.
 *
 * The row arithmetic is the same kind the plan is checked on -- buffer rows, a claim, and a window -- and it
 * is checked on nothing else, because the call that finally moves the window is one the console answers and
 * the live gate witnesses. */
static void plan_snap(void)
{
  static RcGrid g; RcView v; int row = -1, col = -1;

  /* 60 model rows over a 400-row buffer: 30 of gutter, then the 30 the window shows. Claimed at buffer row
     340, the viewport's rows are 370..399 and the prompt line -- the model's last -- is buffer row 399. */
  rc_reset_hist(&g, 200, 30, 30, 0x07);
  rc_clear_dirty(&g);
  rc_set_base(&g, 340);
  putraw(&g, "\033[30;1HP");                  /* viewport-relative: row 30 of a 30-row window is the prompt line */
  eq_u("snap: the cursor is on the model's last row", (unsigned)g.cy, 59,
       "CSI r H addresses the viewport, never the gutter (Render.cpp::clxy), so 30 of 30 lands on row 59");
  eq_u("snap: and the claim puts it on the buffer's last", (unsigned)(g.baseRow + g.cy), 399, "setup");

  /* The user scrolled to the top of the buffer. A flush may not follow output down here; a keystroke may. */
  v = view(200, 400, 0, 0, 199, 29, 0x07, 1, 0, 0);
  eq_u("snap: off the view the user moved", (unsigned)rc_snap_view(&g, &v, &row, &col),
       (unsigned)RC_SNAP_PARK, "");
  eq_u("snap: aims at the cursor's own row", (unsigned)row, 399,
       "not the buffer's bottom, not the window's: the row the model's cursor sits on, and conhost slides to it");
  eq_u("snap: and at its column", (unsigned)col, (unsigned)g.cx, "the window starts at column 0 here");

  /* Back on the prompt: nothing to do, and no console call. This is every keystroke of an ordinary session. */
  v = view(200, 400, 0, 370, 199, 399, 0x07, 1, 0, 399);
  eq_u("snap: already looking at it", (unsigned)rc_snap_view(&g, &v, &row, &col),
       (unsigned)RC_SNAP_NOCHANGE, "the common case, and the one that must cost nothing");
  eq_u("snap: so no row is named", (unsigned)row, (unsigned)-1, "a PARK is the only answer that names one");

  /* The other direction, and the case that says the target is the cursor rather than the bottom of the
     buffer: the prompt row is *above* a window the user pushed past it, so the least displacement is upward.
     A snap-to-last-row would move nothing here, and the user would still be looking at blank rows. */
  putraw(&g, "\033[1;1H");                   /* clamped into the viewport: its first row, model row 30 */
  eq_u("snap: the cursor is now on the viewport's first row", (unsigned)g.cy, 30, "setup");
  v = view(200, 410, 0, 375, 199, 404, 0x07, 1, 0, 400);
  eq_u("snap: a view below the prompt is the same defect", (unsigned)rc_snap_view(&g, &v, &row, &col),
       (unsigned)RC_SNAP_PARK, "");
  eq_u("snap: and the park is upward, onto the claimed row", (unsigned)row, 370, S("got %d", row));

  /* An invisible cursor is conhost's guard, and not decoration: ?25l means an application took the screen,
     and a key that yanks the view under it is the app's business rather than the terminal's. */
  putraw(&g, "\033[?25l");
  v = view(200, 410, 0, 0, 199, 29, 0x07, 1, 0, 0);
  eq_u("snap: an invisible cursor is not made visible by a key",
       (unsigned)rc_snap_view(&g, &v, &row, &col), (unsigned)RC_SNAP_NOCHANGE, "");
  putraw(&g, "\033[?25h");
  eq_u("snap: and the same view snaps once the cursor is back",
       (unsigned)rc_snap_view(&g, &v, &row, &col), (unsigned)RC_SNAP_PARK, "the guard was the flag alone");

  /* A column past the window's right edge must not drag the view sideways -- Paint.cpp rule 4 measured that
     conhost slides horizontally for a cursor parked outside it. The row is the point of a snap; the columns
     the user chose to look at are not up for revision because their line was wider than the window. */
  while (g.cx < 150) putraw(&g, "z");
  eq_u("snap: setup walked the column past the window", (unsigned)(g.cx > 99), 1, "setup");
  v = view(200, 400, 0, 0, 99, 29, 0x07, 1, 0, 0);
  eq_u("snap: sideways is out of scope", (unsigned)rc_snap_view(&g, &v, &row, &col),
       (unsigned)RC_SNAP_PARK, "");
  eq_u("snap: so the column is clamped into the window", (unsigned)col, 99, S("got %d", col));
  eq_u("snap: and the row still is the model's", (unsigned)row, 370, S("got %d", row));

  /* Two answers that must be no-ops rather than chases: a model that never painted has only the user's window
     to go on, and a claim past the buffer's last row has no view that could show it. */
  rc_set_base(&g, 340);
  rc_drop_base(&g);
  v = view(200, 400, 0, 0, 199, 29, 0x07, 1, 0, 0);
  eq_u("snap: no claim, no snap", (unsigned)rc_snap_view(&g, &v, &row, &col), (unsigned)RC_SNAP_NOCHANGE,
       "the window is the only truth an unanchored model has, and it is the user's");
  rc_set_base(&g, 900);
  eq_u("snap: a claim off the buffer is not chased",
       (unsigned)rc_snap_view(&g, &v, &row, &col), (unsigned)RC_SNAP_NOCHANGE,
       "parking a cursor at a row the buffer does not have is a failed call, not a view");

  /* A console whose shape is not the model's: the caller re-adopts, exactly as it does for a plan. */
  rc_set_base(&g, 340);
  v = view(200, 400, 0, 0, 199, 24, 0x07, 1, 0, 0);
  eq_u("snap: a shorter window is a resize, not a snap",
       (unsigned)rc_snap_view(&g, &v, &row, &col), (unsigned)RC_SNAP_NOGEOM, "");
  v = view(320, 400, 0, 0, 319, 29, 0x07, 1, 0, 0);
  eq_u("snap: a wider row neither", (unsigned)rc_snap_view(&g, &v, &row, &col),
       (unsigned)RC_SNAP_NOGEOM, "cols is bufW - winL, rule 1's own test");

  /* A snap moves a window and writes no cell, so everything the next flush reads about the model has to be
     as it left it. rc_snap_view takes the grid by const pointer, which is the compiler's half of this claim;
     the two rows below are the half it cannot check. */
  eq_u("snap: the claim outlives it unchanged", (unsigned)g.baseRow, 340, "");
  eq_u("snap: and no scroll debt was spent on it", (unsigned)g.pendingScrolls, 0, "");
}

/* ================================================================== main ====================== */

/*
 * B2's safety net over everything this file can feed. Narrowing the rectangle turns a forgotten `mark`
 * into a lost repaint that no other check would notice -- the model is right and the screen is stale --
 * so for every corpus string, through a grid with and without a gutter: a run's columns stay inside the
 * row, and no damaged cell is left out of the plan.
 */
static void check_damage_bounds(void)
{
  static RcGrid g;
  const int cols = 20, winRows = 6;
  const int hists[2] = { 0, 6 };              /* a plain grid, and one with a screen of gutter above it */
  for (int i = 0; i < g_ncorpus; i++)
  {
    for (int s = 0; s < 2; s++)
    {
      const int hist = hists[s];
      rc_reset_hist(&g, cols, winRows, hist, 0x07);
      putraw(&g, g_corpus[i]);
      /* Plenty of room above the window: every scroll this chunk buffered is paid for with a free slide,
         so row0 stays positive and no damaged row can be excused for lacking a buffer row under it. */
      RcView v = view(cols, 9001, 0, 100, cols - 1, 100 + winRows - 1, 0x07, 1, 0, 100);
      RcPlan p;
      rc_plan_paint(&g, &v, &p);
      g_checks++;
      if (p.reason == RC_PLAN_NOGEOM)
      {
        g_fails++;
        printf("FAIL  bounds [%d/%d]: shape %dx%d+%d does not match the view\n", i, s, cols, winRows, hist);
        continue;
      }
      /* An empty plan is a legitimate answer -- the string moved no cells. What it may not do is name
         runs, or drop a damaged row on the floor while claiming there was no damage. */
      if (p.reason == RC_PLAN_EMPTY)
      {
        g_checks++;
        if (p.nRuns == 0 && p.drop == 0) continue;
        g_fails++;
        printf("FAIL  bounds [%d/%d]: empty plan with %d runs and %d dropped rows\n", i, s, p.nRuns, p.drop);
        continue;
      }
      int ok = 1;
      for (int j = 0; j < p.nRuns && ok; j++)
        ok = (p.run[j].lo >= 0 && p.run[j].lo <= p.run[j].hi && p.run[j].hi < cols);
      if (!ok)
      {
        g_fails++;
        printf("FAIL  bounds [%d/%d]: a rectangle outside the row\n", i, s);
        continue;
      }
      for (int r = 0; r < g.rows && ok; r++)
      {
        if (!rc_row_dirty(&g, r)) continue;
        int covered = 0;
        for (int j = 0; j < p.nRuns; j++)
          if (r >= p.run[j].top && r < p.run[j].top + p.run[j].nrows &&
              p.run[j].lo <= RC_LO(&g, r) && p.run[j].hi >= RC_HI(&g, r)) { covered = 1; break; }
        if (!covered)
        {
          ok = 0; g_fails++;
          printf("FAIL  bounds [%d/%d]: row %d damaged %d..%d and scheduled nowhere\n",
                 i, s, r, RC_LO(&g, r), RC_HI(&g, r));
        }
      }
    }
  }
  printf("bounds  %d corpus strings x 2 shapes, every damaged row inside a run\n", g_ncorpus);
}

int main(int argc, char **argv)
{
  const char *colors = (argc > 1) ? argv[1] : "colors-native.txt";

  check_colors(colors);
  check_widths();

  gm_split_sgr();
  gm_double_esc();
  gm_abandon_and_restart();
  gm_osc();
  gm_osc_family();
  gm_ftcs();
  gm_charset();
  gm_palette();
  gm_osc9();
  gm_clipboard();
  gm_reports();
  gm_dropped();
  gm_wrap_suspect();
  gm_state_reset();
  gm_argcap();
  gm_echo();
  gm_pending();

  geo_wrap();
  geo_decawm();
  geo_wrap_wide_buffer();
  geo_surrogates();
  geo_scroll();
  geo_erase();
  geo_cursor();
  geo_alt();
  geo_lines();
  geo_tabs();
  geo_region();
  status_bar();
  geo_windowops();
  geo_irm();
  geo_colon();
  geo_edit();
  geo_jline_stream();
  geo_ftcs();
  geo_sgr_bits();
  geo_damage();
  geo_census();
  geo_osc_families();
  sync_output();

  plan_plain();
  plan_cursor_past_window();
  plan_scroll_is_free();
  plan_scroll_carries_damage();
  plan_scroll_at_buffer_bottom();
  plan_alt();
  plan_gutter();
  plan_anchor();
  plan_scroll_band();
  plan_snap();
  adopt_anchor();
  plan_gutter_hook();
  plan_runs();
  plan_damage_range();
  plan_declines();

  check_resumable();
  check_damage_bounds();

  printf("checks=%d fails=%d\n", g_checks, g_fails);
  if (g_fails) { printf("RENDERCHECK: FAILED\n"); return 1; }
  printf("RENDERCHECK: ok\n");
  return 0;
}

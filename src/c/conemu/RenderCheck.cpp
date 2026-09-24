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
  for (int i = 0; i < upto; i++)
  {
    unsigned ch = g->cells[row][i].ch;
    unsigned w = (unsigned char)(want[i] ? want[i] : ' ');
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
  if ((int)g->dirtyLo[row] == lo && (int)g->dirtyHi[row] == hi) return;
  g_fails++;
  printf("FAIL  span row %d: got %d..%d want %d..%d  {%s}\n",
         row, g->dirtyLo[row], g->dirtyHi[row], lo, hi, ctx);
}

/* A row that knows no narrower answer: the whole buffer row. */
static void eq_full(const RcGrid *g, int row, const char *ctx)
{
  eq_span(g, row, 0, g->cols - 1, ctx);
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

static void put(RcGrid *g, const char *s)
{
  corpus_add(s);
  putraw(g, s);
}

static void putu(RcGrid *g, const uint16_t *u, int n) { rc_feed(g, u, n); }

static void put1(RcGrid *g, const char *s)         /* one unit per call: the chunk-boundary hammer */
{
  while (*s)
  {
    uint16_t u = (uint16_t)(unsigned char)*s++;
    rc_feed(g, &u, 1);
  }
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
  eq_u("other OSC counted", g.nUnsupported[RC_UN_OSC_OTHER], 4, "10, 4, 52 and a bare introducer");
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
  eq_u("ESC ( 0 remap", g.cells[0][0].ch, 0x2500, "q -> horizontal line");
  put(&g, "\033(B");
  putu(&g, &q, 1);
  eq_u("ESC ( B restores", g.cells[0][1].ch, 'q', "default set");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033)0q");                                 /* G1 is unreachable upstream, and so here */
  eq_text(&g, 0, 1, "q", "an ESC ) designator has no effect on G0");

  rc_reset(&g, 20, 4, 0x07);
  put1(&g, "\033(");
  eq_u("mid-designator", (unsigned)g.mode, RC_ESC_INTERIM, "waiting for the set byte");
  put1(&g, "0");
  eq_u("charset state after a split designator", (unsigned)g.charset, 1, "resumed");
  putu(&g, &q, 1);
  eq_u("split designator took effect", g.cells[0][0].ch, 0x2500, "");
}

static void gm_dropped()
{
  static RcGrid g;
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[?31mX");
  eq_u("CSI ? drops the SGR", g.attr, 0x07, "Pvt set (Ansi.cpp:3494)");
  eq_text(&g, 0, 1, "X", "still one cell");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[38:2:1:2:3mX");
  eq_u("colon subparameters drop the SGR", g.attr, 0x07, "':' is a private byte");
  eq_text(&g, 0, 1, "X", "and are not repainted either");

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
  eq_u("and the glyph is on the next row, not split", g.cells[1][0].ch, 0x3042, "leading half");
  eq_u("with its trailing cell", g.cells[1][1].attr & RC_LVB_TRAILING, RC_LVB_TRAILING, "");
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
  eq_u("a colon CSI is counted once", un(&g, RC_UN_COLON), 1, "");
  eq_u("as colon, not as a mode set", un(&g, RC_UN_MODE), 0, "the two are different decisions");
  eq_u("and paints the text it carried", g.cells[0][0].ch, 'X', "only the colour is dropped");
  eq_u("which is not a reason to distrust the frame", (unsigned)rc_model_suspect(&g), 0, "");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]0;t\007");
  eq_u("a title is counted where it belongs", un(&g, RC_UN_OSC_OTHER), 0, "it is acted on, not swallowed");
  eq_u("and sets nothing suspect", (unsigned)rc_model_suspect(&g), 0, "it changes no cell and moves no cursor");
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

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[999999999999mX");
  eq_u("digits saturate", (unsigned)g.args[0], 65535, "deviation #3: no wrap to a small number");
  eq_u("an enormous SGR applies nothing", g.attr, 0x07, "not a code we know");
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
  echo_eq("a private or colon SGR applies nothing, so it echoes nothing", &g, "", "Ansi.cpp:3494");
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
  eq_u("row 0 last column still blank", g.cells[0][9].ch, ' ', "the wide glyph did not split");
  eq_u("wide front", g.cells[1][0].ch, 0x4E00, "");
  eq_u("wide front attr", g.cells[1][0].attr & RC_LVB_LEADING, RC_LVB_LEADING, "LEADING");
  eq_u("wide back", g.cells[1][1].ch, 0x4E00, "conhost repeats the code point");
  eq_u("wide back attr", g.cells[1][1].attr & RC_LVB_TRAILING, RC_LVB_TRAILING, "TRAILING");
  eq_u("wide back keeps the colour", g.cells[1][1].attr & 0xF0, g.cells[1][0].attr & 0xF0, "");
  eq_u("cursor after wide", (unsigned)g.cx, 2, "");
  eq_u("two columns charged", g.nCells, 11, "9 narrow + 1 wide");

  /* exactly two columns left: it fits, and the fill triggers the wrap */
  rc_reset(&g, 10, 3, 0x07);
  put(&g, "01234567");
  putu(&g, &wide, 1);
  eq_u("wide at cols-2 front", g.cells[0][8].attr & RC_LVB_LEADING, RC_LVB_LEADING, "");
  eq_u("wide at cols-2 back", g.cells[0][9].attr & RC_LVB_TRAILING, RC_LVB_TRAILING, "");
  eq_u("cursor wrapped after a full row", (unsigned)g.cx, 0, "");
  eq_u("row wrapped after a full row", (unsigned)g.cy, 1, "");
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
  eq_u("column 119 is on the line", g.cells[0][119].ch, 'z', "the window's last column");
  eq_u("column 120 is on the line too", g.cells[0][120].ch, 'z', "off screen, and still a cell");
  eq_u("column 199 is the last", g.cells[0][199].ch, 'z', "");
  eq_u("row 1 untouched", g.cells[1][0].ch, ' ', "no phantom wrapped row");

  for (i = 0; i < 1800; i++) u[i] = 'y';
  putu(&g, u, 1800);
  eq_u("filling the last column wraps at once", (unsigned)g.cx, 0, "the same rule geo_wrap pins on a 10-column row");
  eq_u("so the cursor is already on the next row", (unsigned)g.cy, 1,
       "nothing is left sitting past the buffer's edge; the real console is the witness (Render.java)");
  eq_u("the last column of the buffer row", g.cells[0][1999].ch, 'y', "");
  putu(&g, &one, 1);
  eq_u("the next cell starts that row", g.cells[1][0].ch, 'z', "wrapped at the buffer's edge");
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
  eq_u("astral front", g.cells[0][0].ch, 0xD83D, "the pair reaches the grid as two WCHARs");
  eq_u("astral back", g.cells[0][1].ch, 0xDE00, "");
  eq_u("astral is wide", g.cells[0][0].attr & RC_LVB_LEADING, RC_LVB_LEADING,
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
  eq_u("completed front", g.cells[0][0].ch, 0xD83D, "");
  eq_u("wantLow cleared on completion", g.wantLow, 0, "");

  rc_reset(&g, 20, 3, 0x07);
  putu(&g, pair, 1);
  putu(&g, &a, 1);
  eq_u("an uncompleted high surrogate", g.cells[0][0].ch, 0xFFFD, "replaced, never half-painted");
  /* U+FFFD is EAW=A, measured 2 on the CJK faces and 1 on the Western ones, so by the ruling (I14) it
     costs two columns and whatever follows lands one column further along than it did before. */
  eq_u("the replacement takes the whole cell pair", g.cells[0][1].attr & RC_LVB_TRAILING,
       RC_LVB_TRAILING, "U+FFFD's own trailing cell, not a stray glyph");
  eq_u("the unit after a replacement still lands", g.cells[0][2].ch, 'A', "");
  eq_u("wantLow cleared", g.wantLow, 0, "");

  rc_reset(&g, 20, 3, 0x07);
  const uint16_t low = 0xDE00;
  putu(&g, &low, 1);
  eq_u("a lone low surrogate", g.cells[0][0].ch, 0xFFFD, "");
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
  eq_u("scrolled fill char", g.cells[1][1].ch, ' ', "");
  eq_u("scrolled fill attr", g.cells[1][1].attr, 0x27, "the live attribute, not the default");
  eq_u("scrolls counted", g.nScrolls, 1, "");

  rc_reset(&g, 8, 3, 0x07);
  put(&g, "a\r\nb\r\nc");
  eq_text(&g, 2, 1, "c", "the third row is the bottom of a 3-row viewport");
  put(&g, "\033[S");
  eq_text(&g, 0, 1, "b", "CSI S scrolls up one");
  eq_text(&g, 1, 1, "c", "");
  eq_u("CSI S left the bottom blank", g.cells[2][0].ch, ' ', "");
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
  eq_u("EL 0 blank", g.cells[2][3].ch, ' ', "");
  eq_u("EL 0 attr is the live one", g.cells[2][3].attr, 0x27, "not the default");
  put(&g, "\033[1D\033[1K");
  eq_text(&g, 2, 2, "  ", "EL 1 clears from the line start through the cursor");
  eq_text(&g, 2, 4, "    ", "EL 1 leaves the rest of the row");

  rc_reset(&g, 10, 3, 0x07);
  put(&g, "AB\033[42m\033[2K");
  eq_text(&g, 0, 2, "  ", "EL 2 clears the whole row");
  eq_u("EL 2 attr", g.cells[0][9].attr, 0x27, "");

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
  eq_u("ECH attr", g.cells[0][2].attr, 0x07, "the live attribute, which is still the default");

  rc_reset(&g, 10, 3, 0x07);
  put(&g, "ABCDEFGH\033[1;3H\033[0J");
  eq_text(&g, 0, 3, "AB ", "ED 0 clears from the cursor to the end of the row");
  eq_text(&g, 0, 8, "AB      ", "and the tail too");
  eq_text(&g, 1, 0, "", "ED 0 clears the rows below");
  eq_u("ED 0 left row 1 blank", g.cells[1][0].ch, ' ', "");

  /* a trailing half must not survive an erase over it, or the grid diff shows a ghost cell */
  const uint16_t wide = 0x4E00;
  rc_reset(&g, 10, 3, 0x07);
  putu(&g, &wide, 1);
  put(&g, "\033[1;1H\033[2K");
  eq_u("erase kills TRAILING", g.cells[0][1].attr & RC_LVB_TRAILING, 0, "");
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
  eq_u("BS still erases nothing", g.cells[0][0].ch, 0x3042, "the move is not a delete");

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
  eq_u("TAB snaps to a multiple of 8", g.cells[0][8].ch, 'b', "((x+8)>>3)<<3 from x=1");
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
  eq_u("DA counted", g.nUnsupported[RC_UN_REPORT], 1, "");
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
     spent on a window slide or a buffer scroll (Paint.cpp rule 2) because those rows are still wanted
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
  eq_u("DL left row 3 blank", g.cells[3][0].ch, ' ', "");
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

  /* Rejected regions clear the region rather than being ignored (Ansi.cpp:3147-3150). */
  put(&g, "\033[3;2r");
  eq_u("top above bottom clears", (unsigned)g.regSet, 0, "");
  put(&g, "\033[2r");
  eq_u("one argument alone clears", (unsigned)g.regSet, 0, "");
  put(&g, "\033[r");
  eq_u("no argument clears", (unsigned)g.regSet, 0, "");
  put(&g, "\033[1;99r");
  eq_u("a region clamped to the full height is normalised away", (unsigned)g.regSet, 0,
       "same rows, but the paths that carry history out of the gutter branch on exactly this");

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

  /* A hard reset drops what ConEmu's FullReset drops -- and what it forgets to drop, we drop too. */
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
  eq_text(&g, 0, 1, " ", "DECSTR is FullReset upstream (Ansi.cpp:3644-3649), not an attribute reset");
  rc_reset(&g, 8, 3, 0x07);
  put(&g, "A\033[1!p");
  eq_text(&g, 0, 1, "A", "and upstream gates that on ArgC == 0 (:3645)");

  /* The census and the suspicion: a known-inert sequence is counted and trusted; a final byte neither
     this switch nor ConEmu has a case for is neither. */
  rc_reset(&g, 8, 3, 0x07);
  put(&g, "\033[?12h\033[?7l\033[?1h\033[?2004h\033[?1000h\033[?1005l");
  eq_u("?12, ?7 and ?1 are counted as modes", g.nUnsupported[RC_UN_MODE], 3, "");
  eq_u("bracketed paste has its own bucket", g.nUnsupported[RC_UN_DECBP], 1, "");
  eq_u("the mouse family has its own, and ?1005 is in it", g.nUnsupported[RC_UN_MOUSE], 2, "");
  eq_u("none of them doubts the frame", (unsigned)g.modelSuspect, 0,
       "this is the full repaint that used to be paid for a cnorm");
  put(&g, "\033[1\\");
  eq_u("an unknown final is counted", g.nUnsupported[RC_UN_SUP], 1, "no case here, none upstream");
  eq_u("and makes the frame suspect", (unsigned)g.modelSuspect, 1, "S3: the reach is not known");
  rc_clear_model_suspect(&g);
  put(&g, "\033[Z");
  eq_u("CBT joins the SUP count", g.nUnsupported[RC_UN_SUP], 2, "");
  eq_u("but CBT cannot make the frame suspect", (unsigned)g.modelSuspect, 0,
       "ConEmu has no case for it either (:3051) and no tab stop to move to (HTS is ignored at :2731)");
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
}

/* The character-editing family, which the shipped output never sends but an application on this terminal
   may: ICH, DCH, and the DECSCUSR parameter the painter turns into a cursor height. */
static void geo_edit()
{
  static RcGrid g;
  rc_reset(&g, 8, 3, 0x07);
  put(&g, "ABCD");
  put(&g, "\033[1;2H\033[2@");
  eq_text(&g, 0, 8, "A  BCD  ", "ICH blanks *at* the cursor and pushes the tail from there right");
  eq_u("ICH leaves the cursor where it was", (unsigned)g.cx, 1, "");
  put(&g, "\033[1;2H\033[P");
  eq_text(&g, 0, 8, "A BCD   ", "DCH pulls the tail back left over the gap and blanks the row's end");
  put(&g, "\033[1;2H\033[99P");
  eq_text(&g, 0, 2, "A ", "an over-long DCH clears the row from the cursor and stops at the margin");
  eq_text(&g, 0, 8, "A       ", "nothing wrapped, nothing moved on the row below");
  eq_text(&g, 1, 1, " ", "row 1 never had anything on it, and still has nothing");

  rc_reset(&g, 8, 3, 0x07);
  put(&g, "ABCDEFGH");
  put(&g, "\033[1;8H\033[2@");
  eq_text(&g, 0, 7, "ABCDEFG", "ICH at the last column can only open the one cell left");
  eq_u("and paints nothing outside the row", g.cells[0][7].ch, ' ', "n clamps to cols-cx");

  /* The halves of a wide glyph travel as cells, so a shift can split one. Upstream hands the same pair to
     ScrollConsoleScreenBuffer and gets the same answer (ExtConsole.cpp:1675-1690 moves cells, not glyphs),
     which is why this pins the oddity instead of the wish. */
  const uint16_t wide = 0x3042;                        /* U+3042, EAW W */
  rc_reset(&g, 8, 3, 0x07);
  putu(&g, &wide, 1);
  put(&g, "A");
  eq_u("setup: the leading half", g.cells[0][0].attr & RC_LVB_LEADING, RC_LVB_LEADING, "");
  eq_u("setup: the trailing half", g.cells[0][1].attr & RC_LVB_TRAILING, RC_LVB_TRAILING, "");
  put(&g, "\033[1;1H\033[1@");
  eq_u("ICH moved the leading half right", g.cells[0][1].attr & RC_LVB_LEADING, RC_LVB_LEADING, "");
  eq_u("and the trailing half kept its own bit", g.cells[0][2].attr & RC_LVB_TRAILING, RC_LVB_TRAILING, "");
  eq_u("the blank is at the cursor column", g.cells[0][0].ch, ' ', "");
  eq_u("A rode one column further right", g.cells[0][3].ch, 'A', "");
  put(&g, "\033[1;1H\033[P");
  eq_u("DCH shifted the pair back: front half at column 0", g.cells[0][0].attr & RC_LVB_LEADING,
       RC_LVB_LEADING, "the split is undone by moving the same cells left, not by re-joining them");
  eq_u("trailing half at column 1", g.cells[0][1].attr & RC_LVB_TRAILING, RC_LVB_TRAILING, "");
  eq_u("and no third cell claims the code point", g.cells[0][2].ch, 'A', "");

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
  eq_u("the cell it painted is the glyph remembered", g.cells[0][2].ch, 'X', "");
  eq_span(&g, 0, 2, 2, "one column of damage");
  put(&g, "\033[?3b");
  eq_u("a private byte is not REP", (unsigned)g.cx, 3, "upstream gates the whole case on !PvtLen (:3072)");
  eq_u("and it is counted as inert rather than unknown", g.nUnsupported[RC_UN_MODE], 1, "");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[1;3H\033[2b");
  eq_u("before anything is written, REP repeats a space", g.cells[0][2].ch, ' ',
       "lastUnit is seeded by rc_reset_hist; upstream's m_LastWrittenChar is whatever survived the last reset");
  eq_span(&g, 0, 2, 3, "a space still damages the cells it is written to");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033(0q");
  eq_u("the drawing set remaps the glyph", g.cells[0][0].ch, 0x2500, "`ESC ( 0` then q");
  put(&g, "\033[2b");
  eq_u("and REP repeats the same line glyph", g.cells[0][1].ch, 0x2500, "the remap is still live");
  put(&g, "\033(B\033[2b");
  eq_u("leaving the set shows what was remembered: the letter", g.cells[0][3].ch, 'q',
       "the code point is stored before the charset is applied, so a repeat after `ESC ( B` is plain text");
  eq_u("one letter per repeat", g.cells[0][4].ch, 'q', "");

  rc_reset(&g, 20, 4, 0x07);
  {
    uint16_t w = 0x4E00;                            /* U+4E00, EAW W */
    putu(&g, &w, 1);
  }
  put(&g, "\033[2b");
  eq_u("a wide glyph costs two columns per repeat", (unsigned)g.cx, 6, "one write plus two repeats");
  eq_u("and keeps the pair convention", (unsigned)(g.cells[0][4].attr & RC_LVB_LEADING),
       (unsigned)RC_LVB_LEADING, "otherwise half a glyph paints");
  eq_u("its partner trailing", (unsigned)(g.cells[0][5].attr & RC_LVB_TRAILING),
       (unsigned)RC_LVB_TRAILING, "");

  rc_reset(&g, 20, 4, 0x07);
  {
    const uint16_t astral[2] = { 0xD83D, 0xDE00 };  /* U+1F600 */
    putu(&g, astral, 2);
  }
  const uint16_t hi = g.cells[0][0].ch, lo = g.cells[0][1].ch;
  put(&g, "\033[1b");
  eq_u("REP of an astral writes the pair again, high half first", g.cells[0][2].ch, hi,
       "upstream's m_LastWrittenChar is one wchar_t, so a repeat there is the same half twice");
  eq_u("low half second", g.cells[0][3].ch, lo, "");
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
    eq_u(S("jline box letter %d draws its glyph", i + 1), g.cells[0][i].ch, box[i], "");
  eq_u("and `ESC ( B` closes the set, so the letter after it is text", g.cells[0][11].ch, 'z',
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
  eq_u("the cell painted before 39/49 keeps it too", g.cells[0][0].attr, 0x8007, "0x07 + underline");
  eq_u("the cell painted after 39/49", g.cells[0][1].attr, 0x8007, "underline is still set");

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
  eq_u("the painted cell uses the cleared attribute", g.cells[0][0].attr, 0x07, "");

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
  eq_span(&g, 0, 10, 19, "ECH spends its count on the row's tail first");
  eq_span(&g, 1, 0, 19, "and crosses the margin into the next row, as the buffer-relative fill upstream does");
  eq_u("two rows' worth is all the count asked for", (unsigned)rc_row_dirty(&g, 2), 0, "");
  rc_clear_dirty(&g);
  put(&g, "\033[1;11H\033[999X");
  eq_span(&g, 0, 10, 19, "an over-long ECH clamps to what the buffer has");
  eq_span(&g, 5, 0, 19, "every row down to the last one");
  rc_clear_dirty(&g);
  put(&g, "\033[1;11H\033[0X");
  eq_u("a zero count erases nothing", (unsigned)rc_row_dirty(&g, 0), 0,
       "upstream reads ArgV[0] raw: `CSI 0X` is not `CSI X`, which is one cell (:3802)");
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
    if (a->rowDirty[r] != b->rowDirty[r])
    {
      snprintf(why, n, "damage row %d flagged %d vs %d", r, a->rowDirty[r], b->rowDirty[r]);
      return 0;
    }
    if (!a->rowDirty[r]) continue;
    if (a->dirtyLo[r] != b->dirtyLo[r] || a->dirtyHi[r] != b->dirtyHi[r])
    {
      snprintf(why, n, "damage row %d is %d..%d vs %d..%d", r,
               a->dirtyLo[r], a->dirtyHi[r], b->dirtyLo[r], b->dirtyHi[r]);
      return 0;
    }
  }
  for (int r = 0; r < a->rows; r++)
    for (int c = 0; c < a->cols; c++)
      if (a->cells[r][c].ch != b->cells[r][c].ch || a->cells[r][c].attr != b->cells[r][c].attr)
      {
        snprintf(why, n, "cell(%d,%d) %04X/%04X vs %04X/%04X", r, c,
                 a->cells[r][c].ch, a->cells[r][c].attr, b->cells[r][c].ch, b->cells[r][c].attr);
        return 0;
      }
  /* The row state -- why a line ended, and what the shell claimed the row for (I20, I23) -- is part of what a
     chunk means even though no byte of it reaches the console. A 133 split across a chunk boundary that
     marked a different row than the same 133 delivered whole is the bug class this section exists to catch,
     and nothing above would notice. So does the FTCS content the cursor carries, because that is what decides
     the *next* line feed's claim. */
  for (int r = 0; r < a->rows; r++)
    if (a->rowWrap[r] != b->rowWrap[r] || a->rowMark[r] != b->rowMark[r] || a->markCol[r] != b->markCol[r])
    {
      snprintf(why, n, "row %d state %d/%d/%d vs %d/%d/%d", r,
               a->rowWrap[r], a->rowMark[r], a->markCol[r], b->rowWrap[r], b->rowMark[r], b->markCol[r]);
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
 * viewport sideways to include a cursor it is told about -- the same behaviour Paint.cpp rule 2 spends
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
 * both are what rule 2 is for on the main screen and neither is allowed on the alt. */
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
      if (g->cells[r][0].ch >= '0' && g->cells[r][0].ch <= '9') g_paintLines++;
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
      if (g.cells[r][0].ch >= '0' && g.cells[r][0].ch <= '9') g_paintLines++;
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
              p.run[j].lo <= g.dirtyLo[r] && p.run[j].hi >= g.dirtyHi[r]) { covered = 1; break; }
        if (!covered)
        {
          ok = 0; g_fails++;
          printf("FAIL  bounds [%d/%d]: row %d damaged %d..%d and scheduled nowhere\n",
                 i, s, r, g.dirtyLo[r], g.dirtyHi[r]);
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
  gm_dropped();
  gm_wrap_suspect();
  gm_argcap();
  gm_echo();
  gm_pending();

  geo_wrap();
  geo_wrap_wide_buffer();
  geo_surrogates();
  geo_scroll();
  geo_erase();
  geo_cursor();
  geo_alt();
  geo_lines();
  geo_region();
  status_bar();
  geo_edit();
  geo_jline_stream();
  geo_ftcs();
  geo_sgr_bits();
  geo_damage();

  plan_plain();
  plan_cursor_past_window();
  plan_scroll_is_free();
  plan_scroll_carries_damage();
  plan_scroll_at_buffer_bottom();
  plan_alt();
  plan_gutter();
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

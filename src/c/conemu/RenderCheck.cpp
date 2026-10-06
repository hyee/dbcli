#include "Render.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "HostTypes.h"
#include "../luauf8/ansi_width_tables.h"
#include "Paint.h"
#include "vendor/ConEmuRgbMap.h"
#include "vendor/X11ColorNames.h"

static int g_checks, g_fails;

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
  if (upto <= 0)
  {
    g_fails++;
    printf("FAIL  eq_text(row %d, upto %d) would compare no cells  {%s}\n", row, upto, ctx);
    return;
  }
  if (upto > g->cols)
  {
    g_fails++;
    printf("FAIL  eq_text(row %d, upto %d) reaches past a %d-column grid  {%s}\n", row, upto, g->cols, ctx);
    return;
  }
  for (int i = 0; i < upto; i++)
  {
    unsigned ch = RC_CELLS(g, row)[i].ch;
    const unsigned w = ((int)i < (int)strlen(want)) ? (unsigned)(unsigned char)want[i] : ' ';
    if (ch == w) continue;
    g_fails++;
    printf("FAIL  cell(%d,%d)=0x%04X want 0x%04X  {%s}\n", row, i, ch, w, ctx);
    return;
  }
}

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

static void eq_full(const RcGrid *g, int row, const char *ctx)
{
  eq_span(g, row, 0, g->cols - 1, ctx);
}

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

static char g_corpus[768][128];
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

static void grid_ok(const RcGrid *g, const char *ctx)
{
  char msg[256];
  g_checks++;
  if (!rc_validate_grid(g, msg, (int) sizeof msg)) return;
  g_fails++;
  printf("  FAIL grid invariants after %s: %s\n", ctx, msg);
}

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

static void put1(RcGrid *g, const char *s)
{
  while (*s)
  {
    uint16_t u = (uint16_t)(unsigned char)*s++;
    rc_feed(g, &u, 1);
  }
  grid_ok(g, s ? "unit-at-a-time feed" : "unit-at-a-time feed");
}

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
      eq_u("RgbMap identity", RgbMap[n], entry, ctx);

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
    if (cp >= 0xD800 && cp <= 0xDFFF) continue;
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

static void gm_split_sgr()
{
  static RcGrid g;
  rc_reset(&g, 20, 4, 0x07);
  put1(&g, "\033[3");
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
  static RcGrid g;
  rc_reset(&g, 20, 4, 0x07);
  put1(&g, "\033");
  put(&g, "\033[33mX");
  eq_u("ESC ESC cells painted", g.nCells, 1, "only the X");
  eq_u("ESC ESC attr", g.attr, 0x06, "yellow foreground");
}

static void gm_abandon_and_restart()
{
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
  for (int i = 0; i < n; i++) s[i] = (char)t[i];
  s[n] = 0;
  if (want && !strcmp(s, want)) return;
  g_fails++;
  if (!want) printf("FAIL  title: \"%s\" pending, wanted none  {%s}\n", s, ctx);
  else printf("FAIL  title: got \"%s\" want \"%s\"  {%s}\n", s, want, ctx);
}

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

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]1;icon\007\033]2;win\007");
  eq_title(&g, "win", "the last title wins");
  eq_u("both parsed", g.nTitleSet, 2, "one of them reaches the console");

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

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]10;t\007\033]0;\007\033]0t\007\033]t;\007");
  eq_u("near-misses are not titles", g.nUnsupported[RC_UN_OSC_OTHER], 4, "");
  eq_title(&g, NULL, "");

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

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033P1;2$q+\033\\\033Xq\033\\\033^q\033\\\033_q\033\\");
  eq_u("DCS family counted", g.nUnsupported[RC_UN_DCS], 4, "ESC P, X, ^ and _");
  eq_title(&g, NULL, "and none of them set a title");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "AB");
  put(&g, "\033Pq#0;2;0;0;0;0;1Y\n#1;1;0;100;100;100;1,0,0;#1;2;0;100;100;0!0,0;#2;1;50;50;50$3\\#0;0;0;0;0;0E\033\\");
  put(&g, "CD");
  eq_text(&g, 0, 20, "ABCD                ", "the whole sixel body paints no cell, and the markers meet");
  eq_u("one vote, in the DCS bucket", g.nUnsupported[RC_UN_DCS], 1u,
       "and not in the OSC ones -- a payload read as an OSC could reach the title applier");
  eq_u("the titles stayed untouched", g.nTitleSet, 0u, "");
  eq_u("no cursor motion survived the body's newlines", (unsigned)g.cy, 0u,
       "a sixel `Y\\n` that reached move_row would push the page and scroll the window");
  eq_u("and no cell was damaged at all beyond the four markers", (unsigned)g.nCells, 4u, "");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "XY\033Pq#1;1;0;10;10;10;1,0,0;\030Z");
  eq_text(&g, 0, 20, "XYZ                 ", "a CAN abandons the body, and the text after it is text");
  eq_u("and it is the DCS bucket that moves", g.nUnsupported[RC_UN_DCS], 1u, "");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "AB\033Pq#0;2;0;0;0;0;1Y\n#1;1;0;100;100;100;1,0,0;");
  eq_u("an unfinished sixel across a chunk boundary votes nothing", g.nUnsupported[RC_UN_DCS], 0u,
       "it is resumable state, not an error");
  eq_text(&g, 0, 20, "AB                  ", "and none of its body has been painted");
  put(&g, "#2;1;50;50;50\033\\CD");
  eq_u("the terminator closes it with exactly one vote", g.nUnsupported[RC_UN_DCS], 1u, "");
  eq_text(&g, 0, 20, "ABCD                ", "the two halves still leave the markers meeting");

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

  rc_reset(&g, 20, 4, 0x07);
  put1(&g, "\033]0;split\007");
  eq_title(&g, "split", "unit by unit, the way a chunk boundary delivers it");
  putraw(&g, "\033]0;held");
  eq_u("an open OSC is pending, not abandoned", (unsigned)g.mode, RC_OSC, "");
  eq_u("and it has counted nothing", g.nUnsupported[RC_UN_OSC_OTHER], 0, "");
  eq_title(&g, NULL, "nothing to apply yet");
  putraw(&g, "\007");
  eq_title(&g, "held", "the next chunk closes it");

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

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]0;abcdef\007");
  {
    uint16_t small[3];
    eq_u("a too-small take refuses", (unsigned)rc_title_take(&g, small, 3), (unsigned)-1, "");
    eq_u("and the title is still there", (unsigned)rc_title_pending(&g), 1, "");
  }
  eq_title(&g, "abcdef", "a bigger buffer gets it later");
}

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

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133\007");
  put(&g, "\033]133;\007");
  put(&g, "\033]133;Q\007");
  put(&g, "\033]133;AX\007");
  put(&g, "\033]133;L;k=c\007");
  put(&g, "\033]133;L;\007");
  put(&g, "\033]0133;A\007");
  put(&g, "\033]1334;A\007");
  put(&g, "\033]1000000;A\007");
  eq_u("every one counted as an OSC we did not act on", g.nUnsupported[RC_UN_OSC_OTHER], 9, "");
  eq_u("and none of them marked a row", (unsigned)rc_prompt_marks(&g), 0, "");
  eq_u("nothing reached the cursor either", (unsigned)g.cy, 0, "");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;A;aid=14;cl=line\007");
  eq_u("unknown options are skipped", (unsigned)rc_row_mark(&g, 0), RC_PM_PROMPT, "a future shell may send them");
  put(&g, "\033[1;4H\033]133;P;zz\007");
  eq_u("a field with no '=' names no key and is skipped too", (unsigned)rc_row_mark(&g, 0), RC_PM_PROMPT, "");
  eq_u("and the second prompt did not move the one already there", (unsigned)rc_mark_col(&g, 0), 0,
       "MSFT emplaces a prompt only when the row has none (Row.cpp:1263)");
  eq_u("one mark laid, not two", (unsigned)rc_prompt_marks(&g), 1, "");

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

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;A\033[31m");
  eq_u("an ESC abandons it", g.nUnsupported[RC_UN_OSC_OTHER], 1, "deviation #1");
  eq_u("no row was marked", (unsigned)rc_prompt_marks(&g), 0, "");
  eq_u("and the CSI after it still applied", g.attr, 0x04, "");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;A\030");
  eq_u("so does a CAN", g.nUnsupported[RC_UN_OSC_OTHER], 1, "");
  eq_u("and it marked nothing", (unsigned)rc_prompt_marks(&g), 0, "");

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
  put(&g, "\033)0q");
  eq_text(&g, 0, 1, "q", "an ESC ) designator alone still does not touch G0/GL");
  eq_u("but the slot is loaded now", (unsigned)g.carried.charset[1], 1, "#85: `)0` designates G1, it is no longer unreachable");
  eq_u("and a acted-on designator votes nothing", g.nUnsupported[RC_UN_CHARSET], 0,
       "`0` is a set this build renders; counting it would make the census mean 'failed' where it means 'done'");
  put(&g, "\016q");
  eq_u("SO brings G1 into GL and the same byte draws a line", RC_CELLS(&g, 0)[1].ch, 0x2500,
       "this is the whole point of the ticket: the byte did not change, the slot did");
  put(&g, "\017q");
  eq_u("SI puts G0 back and the byte is a letter again", RC_CELLS(&g, 0)[2].ch, 'q', "");
  eq_u("neither shift cost a refusal", g.nUnsupported[RC_UN_SUP], 0,
       "SO/SI were `default: break` before and are modelled now");
  eq_u("counted inert, not suspected", (unsigned)g.modelSuspect, 0, "the arm is read, not assumed");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033)Uq");
  eq_u("Latin-1 into G1 loads nothing", (unsigned)g.carried.charset[1], 0, "one bit per slot: only DEC graphics is drawable");
  eq_u("and names itself in the census", g.nUnsupported[RC_UN_CHARSET], 1,
       "`U` is a set this build cannot render; the old claim was `no case for it`, which #85 made false");
  put(&g, "\016q");
  eq_u("SO to a plain G1 draws the letter", RC_CELLS(&g, 0)[0].ch, 'q', "");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033(0\016\033.cq");
  eq_u("LS2R's `ESC .` is an intermediate that reaches the final dispatch", (unsigned)g.mode, RC_GROUND, "");
  eq_u("  ...and the `c` behind it is RIS, so G0 is unloaded", (unsigned)g.carried.charset[0], 0, "");
  eq_u("  ...GL un-shifted with it", (unsigned)g.carried.gshift, 0, "");
  eq_text(&g, 0, 1, "q", "  ...and the byte after it draws a letter, which is what proves the reset landed");
  eq_u("  and none of that cost a vote", g.nUnsupported[RC_UN_SUP] + g.nUnsupported[RC_UN_CHARSET], 0,
       "the ticket expected a count here; the truth is a reset, so a count would be the lie");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033(0q\033Dq");
  rc_reset(&g, 20, 4, 0x07);
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033(0");
  put(&g, "\033)B\016");
  eq_u("G0 loaded, G1 loaded plain, GL on G1", (unsigned)g.carried.gshift, 1u, "");
  put(&g, "\033(Bq");
  eq_u("`ESC ( B` unloaded G0", (unsigned)g.carried.charset[0], 0u, "the rmacs path, exactly as #24 ruled");
  eq_u("  and left GL on G1", (unsigned)g.carried.gshift, 1u,
       "clearing the shift here would rewrite #24: a status line drawn in GL is not the capability's to move");
  eq_text(&g, 0, 1, "q", "  the glyph is a letter because **GL is on the plain G1**, not because anything was unloaded");
  const int row = g.cy, col = g.cx;
  put(&g, "\033(0");
  eq_u("  cursor did not move for a designation", g.cy, (unsigned)row, "");
  put(&g, "q");
  eq_u("...and still a letter: G0 was reloaded under a GL that is not looking at it",
       RC_CELLS(&g, row)[col].ch, 'q', "the cell the designation did not move the cursor away from");
  put(&g, "\017");
  put(&g, "q");
  eq_u("SI finally reveals the loaded G0", RC_CELLS(&g, row)[col + 1].ch, 0x2500,
       "the one place in this feed where a box can appear, and it appears only because the shift moved,"
       " not because a designation was cleared");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033(0q\033Dq");
  eq_u("row 0 draws out of G0, which is what `ESC ( 0` just designated", RC_CELLS(&g, 0)[0].ch, 0x2500, "");
  eq_u("ESC D moved down a row and kept **the column** (that is what separates it from NEL)",
       RC_CELLS(&g, 1)[1].ch, 0x2500, "row 1, column 1: the first glyph left the cursor at col 1 and IND held it");
  eq_u("  and row 1 column 0 stayed empty", RC_CELLS(&g, 1)[0].ch, ' ', "an IND that homed would put a box here");
  eq_u("  GL is still G0 after the motion", (unsigned)g.carried.gshift, 0u, "a cursor control is not a shift control");
  eq_u("  and neither byte cost a vote", g.nUnsupported[RC_UN_SUP] + g.nUnsupported[RC_UN_CHARSET], 0,
       "ESC D is modelled; the census must not call performed motion 'unrecognised'");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033(0q\033Eq");
  eq_u("NEL lands the next glyph one row down at the **left edge**", RC_CELLS(&g, 1)[0].ch, 0x2500,
       "row 1, column 0: ESC E is IND plus a return to the margin, and the pair with the row above is what"
       " separates the two controls");
  eq_u("  cursor row is 1 after it", (unsigned)g.cy, 1u, "the second glyph was the one that moved to column 1");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\022\024\031Z");
  eq_text(&g, 0, 1, "Z", "the C0 informational bytes paint nothing and do not displace the byte behind them;"
       " `control()` answers BEL/BS/HT/LF/CR/SO/SI and every other C0 falls to `default:`");
  put(&g, "\005Y");
  eq_text(&g, 0, 2, "ZY", "ENQ neither paints nor displaces");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033*0q");
  eq_u("ESC * 0 loads G2", (unsigned)g.carried.charset[2], 1, "");
  eq_text(&g, 0, 1, "q", "  and it changes nothing on screen: GL cannot be moved there");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033~0q");
  eq_u("ESC ~ 0 loads G3", (unsigned)g.carried.charset[3], 1, "");
  eq_text(&g, 0, 1, "q", "  ditto for G3");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033*0");
  eq_u("`ESC * 0` before the alias", (unsigned)g.carried.charset[2], 1, "");
  put(&g, "\033+3q");
  eq_u("ESC + 3 aliases **G2**, so it overwrites what `*` put there", (unsigned)g.carried.charset[2], 0u,
       "ISO 2022's `+` designates G2, not G3, and `3` is UK -- a leg asking only 'did + do something'"
       " would pass either way");
  eq_u("G3 is untouched by the alias", (unsigned)g.carried.charset[3], 0u, "");
  eq_text(&g, 0, 1, "q", "and the byte after it is still plain, because GL never moved");

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
  eq_u("charset state after a split designator", (unsigned)g.carried.charset[0], 1, "resumed");
  putu(&g, &q, 1);
  eq_u("split designator took effect", RC_CELLS(&g, 0)[0].ch, 0x2500, "");
}

static void gm_palette()
{
  static RcGrid g;

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

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]4;1;rgb:11/22/33\007");
  eq_u("rgb:r/g/b lands in the attribute table", g.carried.pal16[1], 0x00332211, "COLORREF: red 0x11, green 0x22, blue 0x33");
  eq_u("and asks for exactly that entry to be written", g.carried.palTouched, 1u << 1, "");
  put(&g, "\033]4;2;#4080c0\007");
  eq_u("#RRGGBB parses", g.carried.pal16[2], 0x00C08040, "");
  put(&g, "\033]4;3;#0f0\007");
  eq_u("#RGB replicates the nibble", g.carried.pal16[3], 0x0000FF00,
       "MSFT's sharp-form multiplier would say 0xF0 here while its rgb: form says 0xFF; this uses one rule");
  put(&g, "\033]4;4;#0000ffff0000\007");
  eq_u("#RRRRGGGGBBBB scales down", g.carried.pal16[4], 0x0000FF00, "");
  put(&g, "\033]4;5;rgb:f/ff/0f0\007");
  eq_u("the rgb: form allows unequal widths", g.carried.pal16[5], 0x000FFFFF, "f->0xFF, ff->0xFF, 0f0->0x0F");

  put(&g, "\033]4;6;red\007");
  eq_u("a known name resolves", g.carried.pal16[6], 0x000000FFu, "COLORREF of 255/0/0");
  eq_u("the name costs a refusal for nothing", g.nUnsupported[RC_UN_OSC_OTHER], 0,
       "it is dispatched now; a counted name here would make the census say 'could not act' about an act");
  put(&g, "\033]4;8;#ff0000\007");
  eq_u("and lands on the very bytes the sharp form gives", g.carried.pal16[8], g.carried.pal16[6],
       "one colour, two spellings, one answer -- the reason the table stores r/g/b and not strings");
  put(&g, "\033]4;9;MediumSpringGreen\007");
  const uint32_t camel = g.carried.pal16[9];
  put(&g, "\033]4;10;medium spring green\007");
  eq_u("the spaced spelling is the same colour", g.carried.pal16[10], camel, "0/250/154");
  eq_u("the camel spelling is the table's own number", camel, 0x009AFA00u,
       "rgb.txt spells medium spring green 0 250 154; the generator pins all four readings of that row, "
       "so this leg pins only what the parser must hand back");
  put(&g, "\033]4;11;ORANGE\007");
  eq_u("folding is case-insensitive", g.carried.pal16[11], 0x0000A5FFu, "orange is 255/165/0");
  put(&g, "\033]4;12;grey50\007");
  eq_u("a greyscale ramp name resolves", g.carried.pal16[12], 0x007F7F7Fu, "127/127/127 -- X11's number, not MSFT's 128");

  put(&g, "\033]4;13;nosuchcolourname\007");
  eq_u("an unknown name is counted", g.nUnsupported[RC_UN_OSC_OTHER], 1,
       "I34's census survives the name arm: a name we do not have is still something the stream asked for");
  eq_u("and stores nothing", g.carried.palTouched,
       (1u << 1) | (1u << 2) | (1u << 3) | (1u << 4) | (1u << 5) |
       (1u << 6) | (1u << 8) | (1u << 9) | (1u << 10) | (1u << 11) | (1u << 12),
       "bits 1..6 and 8..12, and not 13");
  put(&g, "\033]4;14;redwhite\007");
  eq_u("a prefix of a name is not the name", g.nUnsupported[RC_UN_OSC_OTHER], 2,
       "the search is exact; 'red' plus three bytes must not answer red");
  put(&g, "\033]4;7;#red\007");
  eq_u("a sharp form is never a name", g.nUnsupported[RC_UN_OSC_OTHER], 3,
       "one spelling, one shape: a near-miss of #RRGGBB must not fall back");
  put(&g, "\033]4;7;rgb:1/2\007");
  eq_u("a truncated rgb: form is counted", g.nUnsupported[RC_UN_OSC_OTHER], 4, "");
  put(&g, "\033]4;300;#ffffff\007");
  eq_u("an index past the table is counted too", g.nUnsupported[RC_UN_OSC_OTHER], 5, "");
  put(&g, "\033]4;7;#12\007");
  eq_u("a sharp form with a bad width is counted", g.nUnsupported[RC_UN_OSC_OTHER], 6, "");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]4;196;rgb:ff/00/00\007");
  eq_u("index 196 goes into the 256 table", g.carried.palette[196], 0x000000FFu, "pure red as a COLORREF");
  eq_u("and asks the console for nothing", g.carried.palTouched, 0, "there is no console slot 196");
  eq_u("the attribute table is untouched", g.carried.pal16[4], 0x00000080u, "attribute 4 is still the standard dark red");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[38;2;18;52;86mX");
  const unsigned before = g.attr & 0xF;
  put(&g, "\033]4;9;rgb:12/34/56\007");
  put(&g, "\033[38;2;18;52;86mY");
  eq_u("the same colour now folds to the entry that was made for it", g.attr & 0xF, 9,
       "an exact match in the table the application just wrote");
  eq_u("and that fold was elsewhere before the change", before, 1,
       "the bucket logic answers 1 for 0x12/0x34/0x56; the exact match answers 9 only after the write");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]4;0;rgb:01/02/03;1;?\007");
  eq_u("a set and an ask in one payload arm one reply", (unsigned)rc_report_pending(&g), 1, "");
  eq_u("the pair before the ask was applied", g.carried.pal16[0], 0x00030201u, "");
  {
    struct RcReportItem it;
    eq_u("its kind is OSC", (unsigned)rc_report_take(&g, &it), (unsigned)RC_REP_OSC, "");
    eq_u("it names the resource", (unsigned)it.mode, 4, "");
    eq_u("and the index that asked", (unsigned)it.y, 1, "not 0: that one was set, not asked about");
    eq_u("with the colour the console will show", it.status, g.carried.pal16[1], "");
  }

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]10;rgb:80/00/00\007");
  eq_u("the default foreground moved to the nearest index", g.carried.defAttr & 0xF, 4,
       "the table is indexed by console attribute, and 4 is FORE_RED");
  eq_u("and the console's own attribute is not", g.attr & 0xF, 7,
       "on this console that field *is* the pen, so an OSC 10 cannot be pushed at it (I34)");
  eq_u("the background nibble did not move", (g.carried.defAttr >> 4) & 0xF, 0, "");
  put(&g, "\033]11;rgb:00/ff/00\007");
  eq_u("the default background follows the same rule", (g.carried.defAttr >> 4) & 0xF, 10, "");
  put(&g, "\033]11;?\007");
  {
    struct RcReportItem it;
    rc_report_take(&g, &it);
    eq_u("a default query carries no index", (unsigned)it.y, 0, "only `4` names one");
    eq_u("and answers with the colour of the index chosen", it.status, g.carried.pal16[10],
         "the effective colour, not the RGB that was asked for (I34)");
  }
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]10;red\007");
  const unsigned fgByName = g.carried.defAttr & 0xF;
  eq_u("one field moved the foreground nibble and no more", (g.carried.defAttr >> 4) & 0xF, 0u,
       "a single-field OSC 10 owns the foreground alone");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]11;green\007");
  const unsigned bgByName = (g.carried.defAttr >> 4) & 0xF;
  eq_u("one field moved the background nibble and no more", g.carried.defAttr & 0xF, 7u, "the default pen is untouched");
  eq_u("and the name landed where that colour's RGB form lands", bgByName, 10u,
       "`green` and rgb:00/ff/00 are one colour, so they must be one index");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]10;red;green\007");
  eq_u("names resolve on the OSC 10/11 path, so the walk costs no refusal",
       g.nUnsupported[RC_UN_OSC_OTHER], 0u, "one resource per field, and both fields are names this build has");
  eq_u("the first field took the foreground", g.carried.defAttr & 0xF, fgByName, "");
  eq_u("the second walked on to the background", (g.carried.defAttr >> 4) & 0xF, bgByName,
       "a loop that read both fields as foreground cannot produce this pair");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]4;3;rgb:ff/ff/ff\007\033]104\007");
  eq_u("104 with no payload restores the standard table", g.carried.pal16[3], 0x00808000u, "");
  eq_u("and marks all sixteen for the console", g.carried.palTouched, 0xFFFFu,
       "restoring is a write like any other, and the console keeps the user's other entries");
  put(&g, "\033]4;4;rgb:ff/ff/ff\007\033]4;5;rgb:ff/ff/ff\007\033]104;4\007");
  eq_u("104 with an index restores that one", g.carried.pal16[4], 0x00000080u, "");
  eq_u("and leaves its neighbour set", g.carried.pal16[5], 0x00FFFFFFu, "");
  put(&g, "\033]104;7;x;8\007");
  eq_u("104 stops at the first index it cannot parse", g.nUnsupported[RC_UN_OSC_OTHER], 1,
       "MSFT:846 records that this is xterm's choice over VTE's");
  eq_u("so the index after the junk was never reached", g.carried.pal16[8], 0x00808080u, "still the standard grey");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]10;rgb:80/00/00\007\033]110\007");
  eq_u("110 with an empty payload restores the default foreground", g.carried.defAttr & 0xF, 7,
       "the seed the handle found, not a guess at a colour");
  put(&g, "\033]10;rgb:80/00/00\007\033]110;1\007");
  eq_u("110 with a payload counts and does nothing", g.nUnsupported[RC_UN_OSC_OTHER], 1,
       "MSFT:855-866 notes xterm and VTE disagree here");
  eq_u("and the default stays where it was", g.carried.defAttr & 0xF, 4, "the same FORE_RED the write chose");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]4;1;rgb:00/00/00");
  put(&g, "\033[5n");
  eq_u("an unterminated palette write counts and applies nothing", g.nUnsupported[RC_UN_OSC_OTHER], 1,
       "the same rule titles and 133 use");
  eq_u("nothing was touched", g.carried.palTouched, 0, "");
  eq_u("and the abandoned sequence still left the queue alone", (unsigned)rc_report_pending(&g), 1,
       "the `CSI 5n` that restarted the parser is its own question");
}

static void gm_osc9()
{
  static RcGrid g;

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]9;4;1;50\007");
  eq_u("9;4 stores the state", (unsigned)g.carried.taskbarState, 1, "");
  eq_u("and the progress", (unsigned)g.carried.taskbarProgress, 50, "");
  eq_u("and says it saw one", (unsigned)g.carried.taskbarSeen, 1, "state 0 is an instruction, not an absence");
  eq_u("with nothing counted", g.nUnsupported[RC_UN_OSC_PRIV], 0, "");

  put(&g, "\033]9;4;2;150\007");
  eq_u("progress past 100 clamps", (unsigned)g.carried.taskbarProgress, 100,
       "MSFT :3601-3605: a program that means 750% means the bar is full");
  eq_u("and the state came along", (unsigned)g.carried.taskbarState, 2, "");

  put(&g, "\033]9;4;9;50\007");
  eq_u("a state past 4 is refused outright", (unsigned)g.carried.taskbarState, 2,
       "MSFT returns without applying (:3596-3600) -- the old value stays");
  eq_u("and counted as the private family it is", g.nUnsupported[RC_UN_OSC_PRIV], 1, "");

  put(&g, "\033]9;4\007");
  eq_u("bare 9;4 is the remove form", (unsigned)g.carried.taskbarState, 0, "");
  eq_u("with the progress cleared too", (unsigned)g.carried.taskbarProgress, 0, "");
  put(&g, "\033]9;4;3;25\007\033]9;4;\007");
  eq_u("an empty state field is not an error", (unsigned)g.carried.taskbarState, 0,
       "MSFT only bails on a field that is both unparseable and non-empty (:3581-3584)");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]9;9;\"D:/\"\007");
  eq_u("9;9 strips one pair of quotes", (unsigned)g.carried.nCwd, 3, "ConEmu's documented spelling");
  eq_u("first unit", g.carried.cwd[0], L'D', "");
  eq_u("second unit", g.carried.cwd[1], L':', "");
  eq_u("third unit", g.carried.cwd[2], L'/', "");
  put(&g, "\033]9;9;/tmp\007");
  eq_u("and an unquoted path is taken anyway", (unsigned)g.carried.nCwd, 4, "MSFT :3616-3621 does the same");
  put(&g, "\033]9;9;C:\001x\007");
  eq_u("a control character in the path refuses it", (unsigned)g.carried.nCwd, 4, "still /tmp");
  eq_u("counted", g.nUnsupported[RC_UN_OSC_PRIV], 1, "");
  put(&g, "\033]9;9;\"a\"b\"\007");
  eq_u("and an inner quote survives the strip only to fail legality", (unsigned)g.carried.nCwd, 4,
       "the pair comes off, then `a\"b` is rejected -- til::is_legal_path's own test case");
  put(&g, "\033]9;9;\007");
  eq_u("an empty path stores nothing", (unsigned)g.carried.nCwd, 4, "");
  eq_u("and counts -- the third refusal in a row", g.nUnsupported[RC_UN_OSC_PRIV], 3,
       "the control character, the inner quote and the empty field each vote once");

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

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]9;7;calc.exe\007");
  eq_u("9;7 counts and stores nothing", g.nUnsupported[RC_UN_OSC_PRIV], 1,
       "the #687 shape: the answer is that no path through this file runs it");
  eq_u("no directory", (unsigned)g.carried.nCwd, 0, "");
  eq_u("no taskbar", (unsigned)g.carried.taskbarSeen, 0, "");
  put(&g, "\033]9;2;boom\007\033]9;3;E=1\007\033]9;1;5\007\033]9;6;GuiMacro(\"x\")\007");
  eq_u("MessageBox, set-env, sleep and GuiMacro all just count", g.nUnsupported[RC_UN_OSC_PRIV], 5, "");
  put(&g, "\033]9\007");
  eq_u("a bare 9 with no subcommand counts", g.nUnsupported[RC_UN_OSC_PRIV], 6, "");
  put(&g, "\033]9;x\007");
  eq_u("and so does an unparseable subcommand", g.nUnsupported[RC_UN_OSC_PRIV], 7, "");
  put(&g, "\033]9;4;1;60");
  eq_u("an unterminated 9;4 has applied nothing yet", (unsigned)g.carried.taskbarProgress, 0,
       "the payload is still open, so there is nothing to count either");
  eq_u("and has not counted yet", g.nUnsupported[RC_UN_OSC_PRIV], 7,
       "#107's rule in the other direction: unfinished is resumable, not refused (the 7 is the running "
       "total of the refusals above, which is why this arm cannot be moved to a fresh grid)");

     static RcGrid f;
  rc_reset(&f, 20, 4, 0x07);
  put(&f, "\033]9;5\007\033]9;8;PATH\007\033]9;10\007\033]9;10;2\007\033]9;11;just a note\007");
  eq_u("9;5, 9;8, 9;10, 9;10;2 and 9;11 each vote once", f.nUnsupported[RC_UN_OSC_PRIV], 5,
       "five refused ids and five votes -- a family member swallowed without a record is the failure mode");
  eq_u("and none of them put anything in the reply queue", (unsigned)rc_report_pending(&f), 0u,
       "9;8 is the shape that matters here: ConEmu sends the *value of an environment variable* back to the "
       "application. An information-disclosure face cannot be witnessed by a grid diff, only by the queue");
  eq_u("no title came out of the comment form", f.nTitleSet, 0, "9;11 is a comment, not a window title");
  eq_u("no environment or directory state moved", (unsigned)f.carried.nCwd, 0, "");
  eq_u("9;10 did not change how the next byte parses", (unsigned)f.attr, 0x07,
       "xterm emulation requests are refused, and #109's `?2 = permanently set` answer depends on that");
  put(&f, "Z");
  eq_text(&f, 0, 20, "Z                   ", "the parser is still the same parser afterwards");

  {
    int firstBad = 0;
    for (int sub = 0; sub <= 31; sub++)
    {
      char seq[40];
      sprintf(seq, "\033]9;%d\007", sub);
      rc_reset(&f, 20, 4, 0x07);
      put(&f, seq);
      const int acts = (sub == 4 || sub == 12);
      const unsigned votes = f.nUnsupported[RC_UN_OSC_PRIV];
      if (votes != (acts ? 0u : 1u)) { firstBad = sub; break; }
      if (!acts && (f.carried.nCwd || f.carried.taskbarSeen || f.nTitleSet || rc_report_pending(&f) || f.semanticContent))
      { firstBad = 1000 + sub; break; }
    }
    eq_u("ids 0..31: only 9;4 and 9;12 act, and a refusal never moves state either", (unsigned)firstBad, 0u,
         "the number is the id that broke the rule (1000+n = it voted but also changed state)");
  }
  put(&g, "\033[\007");
  eq_u("the abandoned 9;4 counts once", g.nUnsupported[RC_UN_OSC_PRIV], 8,
       "same rule as titles and 133: a half-read command is not a claim, but it is a record");
  eq_u("and still applies nothing", (unsigned)g.carried.taskbarProgress, 0, "");
  put(&g, "\033P9;7;calc.exe\033\\\033]9;12\007");
  eq_u("a DCS wearing the same digits is the DCS counter", g.nUnsupported[RC_UN_DCS], 1,
       "osc_finish separates the framings before any subcommand is read");
  eq_u("while the real 9;12 acted", (unsigned)g.semanticContent, RC_SC_INPUT, "");
  eq_u("and the frame is still trusted", (unsigned)g.modelSuspect, 0,
       "a private OSC that was refused must not poison the picture, only be counted");
}

static int b64s(const char *s, uint8_t *out, int cap)
{
  uint16_t u[64];
  int n = 0;
  while (s[n] && n < 64) { u[n] = (uint16_t)(unsigned char)s[n]; n++; }
  return rc_b64_decode(u, n, out, cap);
}

static void gm_clipboard()
{
  static RcGrid g;
  uint8_t out[64];

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

  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]52;;YWJj\007");
  eq_u("an empty selection means the clipboard", (unsigned)rc_clip_pending(&g), 1, "");
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

  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]52;c;?\007\033]52;;?\007");
  eq_u("two reads, two counts", (unsigned)g.nClipRead, 2, "");
  eq_u("nothing armed", (unsigned)rc_clip_pending(&g), 0, "even with the write policy on");
  eq_u("and no reply was queued", (unsigned)rc_report_pending(&g), 0,
       "answering is the whole thing being refused");

  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]52;c\007\033]52;YWJj\007");
  eq_u("no selection field, twice", (unsigned)g.nClipBad, 2,
       "`52;c` has no payload field and `52;base64` has no selection field");
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]52;c;YW*j\007");
  eq_u("a bad encoding is a decode failure", (unsigned)g.nClipBad, 1, "");
  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]52;c;YWJj\033[0mq");
  eq_u("an abandoned OSC is framing, not a clipboard refusal", g.nUnsupported[RC_UN_OSC_OTHER], 1,
       "the rule I21 states for every family: never applied, and counted where it belongs");
  eq_u("and the clipboard counter stays clean", g.nUnsupported[RC_UN_OSC_CLIP], 0,
       "it never reached a terminator, so it never asked for anything");
  eq_u("the byte after the ESC is re-examined", (unsigned)RC_CELLS(&g, 0)[0].ch, (unsigned)'q',
       "deviation #1: an ESC that abandons an OSC is an introducer again, not a swallowed byte");

  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]52;c;QQAg\007");
  eq_u("a decoded NUL refuses the whole payload", (unsigned)g.nClipBad, 1,
       "storing the prefix would hand the user half a paste with no way to know");
  eq_u("nothing armed", (unsigned)rc_clip_pending(&g), 0, "");

  {
    static uint16_t big[RC_OSC_MAX];
    int i, k = 0;
    big[k++] = 0x1B; big[k++] = ']'; big[k++] = '5'; big[k++] = '2'; big[k++] = ';';
    big[k++] = 'c'; big[k++] = ';';
    for (i = 0; i < RC_CLIP_ENC_MAX + 8; i++) big[k++] = 'a';
    big[k++] = 0x07;
    rc_reset(&g, 20, 3, 0x07);
    rc_feed(&g, big, k);
    eq_u("over the cap is refused", (unsigned)g.nClipBad, 1, "");
    eq_u("and nothing armed", (unsigned)rc_clip_pending(&g), 0, "");
    eq_u("the sequence was still consumed", (unsigned)g.mode, (unsigned)RC_GROUND, "");
  }
  rc_set_clipboard_policy(RC_CLIP_DENY);
}

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

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?2026h\033[?2026$p\033[?2026l");
  eq_u("one request, one reply", (unsigned)rc_report_pending(&g), 1, "neither the DECSET nor the RESET speaks");
  {
    struct RcReportItem it;
    eq_u("its kind is DECRPM", (unsigned)rc_report_take(&g, &it), (unsigned)RC_REP_DECRPM, "");
    eq_u("the reply names the mode that was asked", (unsigned)it.mode, 2026,
         "jline4 reads the number back out of the reply, so a reply about the wrong id is worse than none");
    eq_u("and the state it had when the request was read", (unsigned)it.status, 1,
         "the `?2026l` that followed is a later fact, exactly as a cursor move after a CPR is");
  }
  eq_u("answering a query votes in no census", g.nUnsupported[RC_UN_MODE], 0, "");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?2027$p");
  eq_u("reflow answers, and says it has no such state", (unsigned)rc_report_pending(&g), 1,
       "GAP G11: 2027 is grapheme-cluster reflow and this build wraps at cells with no cluster state to "
       "report -- which is exactly what status 0 = not recognized says. The silence this arm used to pin was "
       "the odd answer: MSFT initialises its reply to DECRPM_Unsupported and returns it for every id it does "
       "not name (adaptDispatch.cpp:1939), ghostty answers .not_recognized (modes.zig:80-102), wezterm sends "
       "0 for an Unspecified code (terminalstate/mod.rs:1520-1526).");
  {
    struct RcReportItem it;
    rc_report_take(&g, &it);
    eq_u("under the number that was asked", (unsigned)it.mode, 2027u, "the reply is indexed by id");
    eq_u("and with the not-recognized digit", (unsigned)it.status, 0u,
         "not 1, not 2: the model holds no bit for this number, and 0 is the only status that says so");
  }
  eq_u("an answered query votes nothing, even about a mode we lack", g.nUnsupported[RC_UN_MODE], 0,
       "the vote belongs to the DECSET that could not be stored; #87's pairing rule stays, its silence half "
       "does not");

  put(&g, "\033[?2048$p");
  {
    struct RcReportItem it;
    eq_u("in-band size reports answer, because there is a state to answer with",
         (unsigned)rc_report_pending(&g), 1, "");
    rc_report_take(&g, &it);
    eq_u("the reply names the id that was asked", (unsigned)it.mode, 2048, "");
    eq_u("and says not-set, which is the default", (unsigned)it.status, 2,
         "on by request only: an unsolicited report is bytes the program did not write");
    eq_u("answering it votes nothing", g.nUnsupported[RC_UN_MODE], 0,
         "and since GAP G11 the 2027 query above answers rather than voting, so this grid's mode census is "
         "empty -- which is the point of the pair: a reply and a refusal are two different records");
    put(&g, "\033[?2048h\033[?2048$p");
    eq_u("a DECSET is a store, not a refusal", (unsigned)rc_report_pending(&g), 1, "");
    rc_report_take(&g, &it);
    eq_u("and the answer after it is set", (unsigned)it.status, 1, "");
    eq_u("with no vote for either the h or the $p", g.nUnsupported[RC_UN_MODE], 0,
         "2048 is owned end to end (#82), and since G11 the query answers instead of voting");
    put(&g, "\033[?2048l\033[?2048$p");
    rc_report_take(&g, &it);
    eq_u("and off again is a store too", (unsigned)it.status, 2, "");
  }

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
    eq_u("a region nobody opened is reported as reset", (unsigned)second.status, 2,
         "1, not a permanent number: the mode is understood and currently off, and jline4 reads both 1 and 2 as SUPPORTED (:685)");
  }

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?25$p");
  {
    struct RcReportItem it;
    rc_report_take(&g, &it);
    eq_u("a fresh grid reports the cursor visible", (unsigned)it.status, 1, "");
  }
  put(&g, "\033[?25l\033[?25$p");
  {
    struct RcReportItem it;
    rc_report_take(&g, &it);
    eq_u("and `?25l` is a fact the reply carries", (unsigned)it.status, 2, "");
  }
  put(&g, "\033[?1049h\033[?1049$p\033[?47$p");
  {
    struct RcReportItem alt, legacy;
    rc_report_take(&g, &alt);
    rc_report_take(&g, &legacy);
    eq_u("1049 on the alternate screen answers set", (unsigned)alt.status, 1, "");
    eq_u("and 47 is the same slot, so it cannot disagree", (unsigned)legacy.status, 1,
         "three spellings, one bit (I14): a reply that contradicted the DECSET that moved it would be the lie");
  }

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?999$p");
  eq_u("a number neither leg models is answered, with the digit that says so",
       (unsigned)rc_report_pending(&g), 1, "GAP G11: MSFT DECRPM_Unsupported (adaptDispatch.cpp:1939), "
       "ghostty .not_recognized (modes.zig:80-102), wezterm recognized=false (mod.rs:1523-1526)");
  {
    struct RcReportItem it;
    rc_report_take(&g, &it);
    eq_u("under the id that was asked", (unsigned)it.mode, 999u, "");
    eq_u("and not with a set or a reset", (unsigned)it.status, 0u,
         "the model holds no bit for 999, so 0 is the only digit that is not an invention");
  }
  eq_u("and the answered query voted nothing", g.nUnsupported[RC_UN_MODE], 0,
       "the vote is the record of a DECSET that could not be stored, not of a question");
  put(&g, "\033[2026$p");
  eq_u("the non-private request is counted, because that spelling owns no mode",
       g.nUnsupported[RC_UN_MODE], 1,
       "ANSI 2026 does not exist; the probe always carries the `?`. This is the one case where answering "
       "would be an invention about a sequence the references do not recognise either");
  eq_u("and armed nothing", (unsigned)rc_report_pending(&g), 0, "");
  put(&g, "\033[?1;2$p");
  eq_u("a request with two parameters is not one", g.nUnsupported[RC_UN_MODE], 2,
       "DECRQM takes one number; the MSFT/ghostty arms both require it (`g->nArgs == 1` here, "
       "interim_is(g,'$') with PvtLen 1 there)");
  put(&g, "\033[?$p");
  eq_u("and one with no parameter is not either", g.nUnsupported[RC_UN_MODE], 3, "");
  put(&g, "\033[?2026!p");
  eq_u("a different interim with the same final still votes SUP", g.nUnsupported[RC_UN_SUP], 1,
       "`!` is DECSTR's byte, and with a parameter it is nothing at all");
  eq_u("while the census of modes did not move", g.nUnsupported[RC_UN_MODE], 3, "");

  rc_reset(&g, 20, 6, 0x07);
  for (int i = 0; i < RC_REPORT_MAX + 3; i++) put(&g, "\033[6n");
  eq_u("the queue holds its stated depth", (unsigned)rc_report_pending(&g), (unsigned)RC_REPORT_MAX, "");
  eq_u("and says so, three times", g.nReportFull, 3, "a refusal, not an eviction");
  eq_u("the first entry is still the first asked", (unsigned)take_xy(&g, &ry, &rx), (unsigned)RC_REP_CPR, "");
  eq_u("at the position it was asked from", (unsigned)ry, 0, "nine identical queries, no cursor moves");
  rc_report_result(&g, 1);
  eq_u("a reply the console took is counted once", g.nReportOk, 1, "");
  rc_report_result(&g, 0);
  eq_u("and a failed write is counted separately", g.nReportFail, 1, "so the two are never confused");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[5n");
  eq_u("armed before the reset", (unsigned)rc_report_pending(&g), 1, "");
  rc_reset(&g, 20, 6, 0x07);
  eq_u("gone after it", (unsigned)rc_report_pending(&g), 0, "");
}

static void eq_b(const char *what, const uint16_t *got, int n, const uint16_t *want, int wn, const char *ctx)
{
  int same = (n == wn);
  for (int i = 0; same && i < wn; i++) if (got[i] != want[i]) same = 0;
  char buf[200];
  int p = snprintf(buf, sizeof buf, "%s  want", ctx && ctx[0] ? ctx : "");
  for (int i = 0; i < wn && p < 110; i++) p += snprintf(buf + p, sizeof buf - p, " %u", (unsigned)want[i]);
  p += snprintf(buf + p, sizeof buf - p, "  got");
  for (int i = 0; i < n && p < 180; i++) p += snprintf(buf + p, sizeof buf - p, " %u", (unsigned)got[i]);
  eq_u(what, (unsigned)(same ? 0 : 1), 0, buf);
}

#define REC(state_, flags_, mods_, x_, y_) (m.buttonState = (state_), m.eventFlags = (flags_), \
    m.ctrlKeyState = (mods_), m.x = (x_), m.y = (y_), m.px = -1, m.py = -1, rc_mouse_report(&g, &m, t, 48))
#define RECP(state_, flags_, mods_, x_, y_, px_, py_) (m.buttonState = (state_), m.eventFlags = (flags_), \
    m.ctrlKeyState = (mods_), m.x = (x_), m.y = (y_), m.px = (px_), m.py = (py_), rc_mouse_report(&g, &m, t, 48))

static void gm_inputreports()
{
  static RcGrid g;
  uint16_t t[48];
  struct RcMouseRec m;
  unsigned long c5[5];
  int n;

  rc_reset(&g, 80, 24, 0x07);
  memset(&m, 0, sizeof m);
  n = REC(1, 0, 0, 9, 4);
  eq_u("no mode, no report", (unsigned)n, 0, "");
  rc_report_counts(&g, c5);
  eq_u("and the quiet record is counted", c5[2], 1, "so a zero report count elsewhere is not this zero");
  eq_u("focus is silent without ?1004", (unsigned)rc_focus_report(&g, 1, t, 48), 0, "");
  rc_report_counts(&g, c5);
  eq_u("and that silence is not a report said", c5[1], 0, "");

  rc_reset(&g, 80, 24, 0x07);
  put(&g, "\033[?1000h");
  const uint16_t kPress[]  = {27, 91, 77, 32, 42, 37};
  const uint16_t kRelease[] = {27, 91, 77, 35, 42, 37};
  const uint16_t kMods[]   = {27, 91, 77, 52, 42, 37};
  n = REC(1, 0, 0, 9, 4);
  eq_b("a press reports six units, in the X10 shape", t, n, kPress, 6, "code 0, cell (9,4) -> 10,5");
  n = REC(1, 0, 0, 9, 4);
  eq_u("and the same state again is not an event", (unsigned)n, 0,
       "a Windows record names which buttons are down, so nothing moved here");
  n = REC(0, 0, 0, 9, 4);
  eq_b("the release collapses to button 3", t, n, kRelease, 6, "ghostty :207-213, MSFT :152-156");
  n = REC(1, 0, RC_MS_SHIFT | RC_MS_CTRL, 9, 4);
  eq_b("shift and ctrl ride the same digit (4 and 16)", t, n, kMods, 6, "MSFT :181-183, ghostty :229-234");

  n = REC(1, RC_MS_MOVED, 0, 12, 4);
  eq_u("?1000h does not report a drag", (unsigned)n, 0, "");
  put(&g, "\033[?1002h");
  const uint16_t kDrag[] = {27, 91, 77, 64, 45, 37};
  n = REC(1, RC_MS_MOVED, 0, 12, 4);
  eq_b("?1002h reports it, with the 32 motion bit set", t, n, kDrag, 6, "code 0+32 -> 64");
  n = REC(1, RC_MS_MOVED, 0, 12, 4);
  eq_u("the same cell and button again is not a second report", (unsigned)n, 0,
       "MSFT's sameCoord (mouseInput.cpp:336-338) and ghostty's last_cell (:108-117)");
  put(&g, "\033[?1003h");
  const uint16_t kAny[] = {27, 91, 77, 67, 46, 37};
  n = REC(0, RC_MS_MOVED, 0, 13, 4);
  eq_b("?1003h reports motion with no button at all, as 3+32", t, n, kAny, 6, "code 35 -> 67");

  const uint16_t kWUp[] = {27, 91, 77, 96, 46, 37};
  const uint16_t kWDown[] = {27, 91, 77, 97, 46, 37};
  const uint16_t kHRight[] = {27, 91, 77, 99, 46, 37};
  n = REC(1u << 16, RC_MS_WHEELED, 0, 13, 4);
  eq_b("one notch up is code 64", t, n, kWUp, 6, "MSFT :166-169");
  n = REC((uint32_t)(uint16_t)(-120) << 16, RC_MS_WHEELED, 0, 13, 4);
  eq_b("a negative delta is 65", t, n, kWDown, 6, "");
  n = REC(1u << 16, RC_MS_HWHEELED, 0, 13, 4);
  eq_b("horizontal right is 67, not 64", t, n, kHRight, 6, "");

  rc_reset(&g, 80, 24, 0x07);
  put(&g, "\033[?9h");
  const uint16_t k9[] = {27, 91, 77, 32, 38, 38};
  n = REC(1, 0, RC_MS_ALT, 5, 5);
  eq_b("?9h reports the press without the alt bit", t, n, k9, 6, "the legacy shape has no room for modifiers");
  n = REC(1, RC_MS_MOVED, 0, 6, 5);
  eq_u("and ?9h is not a motion mode", (unsigned)n, 0, "ghostty's x10 arm");
  n = REC(0, 0, 0, 6, 5);
  eq_u("nor does it report a release", (unsigned)n, 0, "X10 mode 9 has no release at all");

  rc_reset(&g, 80, 24, 0x07);
  put(&g, "\033[?1000h\033[?1005h");
  const uint16_t kUtf[] = {27, 91, 77, 32, 112, 56};
  n = REC(1, 0, 0, 79, 23);
  eq_b("utf8 sends the code points, not the bytes", t, n, kUtf, 6, "33+79=112, 33+23=56 (ghostty :134-148)");
  rc_reset(&g, 80, 24, 0x07);
  put(&g, "\033[?1000h\033[?1006h");
  const uint16_t kSgr[] = {27, 91, 60, 48, 59, 56, 48, 59, 50, 52, 77};
  const uint16_t kSgrUp[] = {27, 91, 60, 48, 59, 56, 48, 59, 50, 52, 109};
  n = REC(1, 0, 0, 79, 23);
  eq_b("SGR is `<code;x;yM`", t, n, kSgr, 11, "MSFT mouseInput.cpp:476");
  n = REC(0, 0, 0, 79, 23);
  eq_b("and keeps the release as a button, saying so in lower case", t, n, kSgrUp, 11,
       "the one thing X10 could not express");
  rc_reset(&g, 80, 24, 0x07);
  put(&g, "\033[?1000h\033[?1015h");
  const uint16_t kUrx[] = {27, 91, 51, 50, 59, 56, 48, 59, 50, 52, 77};
  n = REC(1, 0, 0, 79, 23);
  eq_b("urxvt has no < and no release of its own", t, n, kUrx, 11, "ghostty :158-162");
  rc_reset(&g, 80, 24, 0x07);
  put(&g, "\033[?1000h\033[?1016h");
  n = REC(1, 0, 0, 79, 23);
  eq_u("sgr-pixels with no pixel to say reports nothing", (unsigned)n, 0,
       "a Windows mouse record names a cell; this is the one honest refusal in the family");
  n = RECP(0, 0, 0, 79, 23, 640, 300);
  const uint16_t kPixRel[] = {27, 91, 60, 48, 59, 54, 52, 48, 59, 51, 48, 48, 109};
  eq_b("and once the observer supplies pixels it reports them, release and all", t, n, kPixRel, 13,
       "ghostty :164-172; the button state moved even on the record it could not report");

  rc_reset(&g, 80, 24, 0x07);
  put(&g, "\033[?1005h\033[?1006h\033[?1005l");
  {
    struct RcReportItem it;
    put(&g, "\033[?1005$p");
    rc_report_take(&g, &it);
    eq_u("?1005$p answers reset, because the stream turned it off", (unsigned)it.status, 2, "");
    put(&g, "\033[?1006$p");
    rc_report_take(&g, &it);
    eq_u("and ?1006$p answers set, which is the format the next report takes", (unsigned)it.status, 1, "");
  }
  put(&g, "\033[?1005h");
  {
    struct RcReportItem it;
    put(&g, "\033[?1006$p");
    rc_report_take(&g, &it);
    eq_u("turning 1005 on leaves 1006's bit set -- nobody turned it off", (unsigned)it.status, 1,
         "ghostty keeps the same split between `modes` (what was asked) and `flags.mouse_format` (what is used)");
  }
  rc_reset(&g, 80, 24, 0x07);
  put(&g, "[?1000h[?1006h[?1005h");
  const uint16_t kWide[] = {27, 91, 77, 32, 283, 36};
  n = REC(1, 0, 0, 250, 3);
  eq_b("the last enable wins, and utf8 reaches past cell 223", t, n, kWide, 6,
       "33+250=283; MSFT picks utf8 too, from a bit test (mouseInput.cpp:364-368), but this is the last-wins "
       "field ghostty (stream_terminal.zig:1700-1703) and wezterm keep");
  rc_reset(&g, 80, 24, 0x07);
  put(&g, "[?1000h");
  n = REC(1, 0, 0, 250, 3);
  eq_u("while the plain X10 shape drops it rather than clamp it", (unsigned)n, 0,
       "ghostty mouse_encode.zig:120-124; MSFT's s_MaxDefaultCoordinate=94 clamps instead (mouseInput.cpp:11), "
       "which prints a position the pointer was not at -- this build declines to say one");

  rc_reset(&g, 80, 24, 0x07);
  const uint16_t kIn[] = {27, 91, 73}, kOut[] = {27, 91, 79};
  put(&g, "\033[?1004h");
  n = rc_focus_report(&g, 1, t, 48);
  eq_b("?1004h in is ESC [ I", t, n, kIn, 3, "MSFT terminalInput.cpp:447, ghostty focus.zig:22, wezterm mod.rs:907");
  n = rc_focus_report(&g, 0, t, 48);
  eq_b("and out is ESC [ O", t, n, kOut, 3, "");
  put(&g, "\033[?1004l");
  eq_u("after the reset the same event says nothing", (unsigned)rc_focus_report(&g, 1, t, 48), 0,
       "an unsolicited byte is I26");
  rc_report_counts(&g, c5);
  eq_u("the two that were due are the two that are counted", c5[1], 2, "");

  rc_reset(&g, 80, 24, 0x07);
  put(&g, "\033[?1000h\033[?1006h");
  n = REC(1, 0, 0, 3, 3);
  eq_u("before the reset, SGR", (unsigned)n, 9, "");
  put(&g, "\033c");
  n = REC(0, 0, 0, 3, 3);
  eq_u("RIS drops the level, so the release is silent", (unsigned)n, 0, "");
  put(&g, "\033[?1000h");
  const uint16_t kX10b[] = {27, 91, 77, 32, 36, 36};
  n = REC(1, 0, 0, 3, 3);
  eq_b("and a fresh request speaks the default protocol", t, n, kX10b, 6,
       "the format went back to X10 with the bits, not only the bits");

  rc_reset(&g, 80, 24, 0x07);
  put(&g, "\033[?1000h\033[?1006h");
  n = REC(1, 0, 0, 3, 3);
  eq_u("armed before the soft reset", (unsigned)n, 9, "");
  n = REC(0, 0, 0, 3, 3);
  eq_u("released", (unsigned)n, 9, "");
  put(&g, "\033[!p");
  n = REC(1, 0, 0, 3, 3);
  const uint16_t kSgrSm[] = {27, 91, 60, 48, 59, 52, 59, 52, 77};
  eq_b("DECSTR leaves both the level and the protocol it chose", t, n, kSgrSm, 9,
       "the bits and the format are one agreement; a reset that cleared one of them would answer `?1006$p` "
       "with one shape and report in another");

  rc_reset(&g, 80, 24, 0x07);
  put(&g, "\033[?1000h");
  m.buttonState = 1; m.eventFlags = 0; m.ctrlKeyState = 0; m.x = 3; m.y = 3; m.px = m.py = -1;
  eq_u("a two-unit buffer refuses", (unsigned)rc_mouse_report(&g, &m, t, 2), (unsigned)(int)-1, "");
  rc_report_counts(&g, c5);
  eq_u("and the refusal counted nothing", c5[0], 0, "no report was produced");
  n = rc_mouse_report(&g, &m, t, 48);
  const uint16_t kRetry[] = {27, 91, 77, 32, 36, 36};
  eq_b("the same record in a real buffer still reports", t, n, kRetry, 6,
       "the press was not spent on the refusal");
  rc_report_counts(&g, c5);
  eq_u("once", c5[0], 1, "");

  rc_reset(&g, 80, 24, 0x07);
  n = REC(1, 0, 0, 7, 7);
  eq_u("the press with no level is silent", (unsigned)n, 0, "");
  put(&g, "\033[?1000h");
  const uint16_t kLateRel[] = {27, 91, 77, 35, 40, 40};
  n = REC(0, 0, 0, 7, 7);
  eq_b("and the release after the mode is armed still reports", t, n, kLateRel, 6,
       "the state is what the console said, not what the modes wanted");
#undef REC
#undef RECP
}

static void geo_gaps(void)
{
  static RcGrid g;
  int i, c;

  rc_reset_hist(&g, 20, 5, 3, 0x07);
  put(&g, "ZZZZZZZZZZZZZZZZZZZZ");
  for (i = 0; i < 6; i++) put(&g, "abcdefghij\r\n");
  put(&g, "\033[?6h");
  put(&g, "\033[7");
  put(&g, "\033[3;18H");
  put(&g, "\033[2;4r\033[3;17s");
  put(&g, "\033[?4h");
  const int savedY = g.cy, savedX = g.cx;
  put(&g, "\033#8");
  eq_u("the cursor is at the window's top row, not at the saved place", (unsigned)g.cy,
       (unsigned)(g.rows - g.winRows), "MSFT adaptDispatch.cpp:3161 puts it at 1,1 of the page");
  eq_u("and at column 0", (unsigned)g.cx, 0u, "");
  eq_u("the save is still the save (DECALN does not write it)", (unsigned)g.carried.saveY, (unsigned)savedY, "");
  eq_u("and neither is the saved column", (unsigned)g.carried.saveX, (unsigned)savedX,
       "the row above is the twin this test lost: screen_alignment touches saveOrigin only, so a regression "
       "that clobbered the saved column would have passed here with savedX declared and never read");
  eq_u("every viewport row is 'E'", (unsigned)RC_CELLS(&g, g.rows - g.winRows)[0].ch, (unsigned)'E', "");
  eq_u("across the whole width", (unsigned)RC_CELLS(&g, g.rows - 1)[19].ch, (unsigned)'E', "");
  int allE = 1;
  for (i = g.rows - g.winRows; i < g.rows; i++)
    for (c = 0; c < g.cols; c++) if (RC_CELLS(&g, i)[c].ch != 'E') allE = 0;
  eq_u("and nothing in the viewport is not 'E'", (unsigned)allE, 1u,
       "wezterm performer.rs:652-673 and ghostty Terminal.zig:3753-3760 both memset the row");
  eq_u("the scrollback above the window keeps what it held", (unsigned)RC_CELLS(&g, 0)[0].ch, (unsigned)'Z',
       "MSFT's own test asserts exactly this asymmetry (ScreenBufferTests.cpp:7352-7354): the fill is the "
       "viewport, not the buffer");
  eq_u("origin mode is off", (unsigned)g.carried.originMode, 0u, "adaptDispatch.cpp:3156");
  eq_u("the saved origin went with it, so a later DECRC cannot walk into a band that is gone",
       (unsigned)g.carried.saveOrigin, 0u, "");
  eq_u("the vertical margins are gone", (unsigned)g.carried.regSet, 0u, ":3157");
  eq_u("the horizontal pair is gone", (unsigned)g.carried.marginSet, 0u, ":3158-3159");
  eq_u("and the right margin is the page edge again", (unsigned)g.carried.rightMargin, (unsigned)(g.cols - 1), "");
  put(&g, "x");
  eq_u("a write after the fill lands at the top-left", (unsigned)RC_CELLS(&g, g.rows - g.winRows)[0].ch,
       (unsigned)'x', "the cursor is where DECALN left it, and the row was not re-filled");
  put(&g, "\033[?4$p");
  {
    struct RcReportItem it;
    rc_report_take(&g, &it);
    eq_u("a mode DECALN does not name survives it", (unsigned)it.status, 1u,
         "MSFT's list of what the alignment test touches is short; inventing a wider reset would be a claim "
         "about sequences the application never sent");
  }
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[1;4;31m");
  put(&g, "\033#8");
  eq_u("bold is gone", (unsigned)g.sgr.bold, 0u, "textAttribute.cpp:397-402 sets _attrs to Normal");
  eq_u("underline is gone", (unsigned)g.sgr.underline, 0u, "");
  eq_u("the colour stays", (unsigned)g.sgr.fg, 1u, ":31 foreground index, reserved by SetStandardErase");
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[3;7H");
  const int beforeY = g.cy, beforeX = g.cx;
  put(&g, "\033#3");
  eq_u("DECSCA's double-high top moves nothing", (unsigned)g.cy, (unsigned)beforeY, "");
  eq_u("and does not touch the cursor column either", (unsigned)g.cx, (unsigned)beforeX,
       "the fall-through this replaces restored a saved cursor from here");
  eq_u("it is counted as an unsupported ask", g.nUnsupported[RC_UN_SUP], 1, "");
  put(&g, "\033#5");
  eq_u("single-width is a no-op that is still recorded", g.nUnsupported[RC_UN_SUP], 2, "");

  rc_reset(&g, 40, 6, 0x07);
  put(&g, "\033[2;1H\033H");
  put(&g, "\033[3C\033H");
  eq_u("a stop the application set is there", (unsigned)g.carried.tabStop[3], 1u, "#70's HTS");
  put(&g, "\033[?5W");
  eq_u("DECST8C takes it away", (unsigned)g.carried.tabStop[3], 0u,
       "MSFT adaptDispatch.cpp:2784-2792 clears _tabStopColumns and re-arms the default interval");
  eq_u("and the every-8 default is back", (unsigned)g.carried.tabStop[8], 1u, "MSFT's SetEvery8Columns, 8 not 5");
  put(&g, "\033[1;1H\033[?9W");
  eq_u("a parameter neither reference claims is refused", (unsigned)g.carried.tabStop[8], 1u,
       "the defaults stay where DECST8C put them; 9 is not a spelling anyone has");
  eq_u("and the ask is in the census", g.nUnsupported[RC_UN_MODE], 1, "");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033]0;sales report\007\033[21t");
  eq_u("`21t` arms one reply", (unsigned)rc_report_pending(&g), 1,
       "wezterm terminalstate/mod.rs:2175-2183 and ghostty stream_terminal.zig:1468-1471 both answer it; "
       "MSFT's WindowManipulation enum stops at 18, so silence there is an absent family, not a refusal");
  eq_u("and its kind is the title", (unsigned)rc_report_take(&g, NULL), (unsigned)RC_REP_TITLE, "");
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[21t");
  eq_u("a session that never set a title arms one reply too", (unsigned)rc_report_pending(&g), 1,
       "and the painter answers nothing for it -- nTitle 0 is a fact, not a string to send");
  {
    struct RcReportItem it;
    rc_report_take(&g, &it);
    eq_u("under the same kind", (unsigned)it.kind, (unsigned)RC_REP_TITLE, "");
  }
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[>q\033[>0q");
  eq_u("XTVERSION, in both spellings, arms two replies", (unsigned)rc_report_pending(&g), 2,
       "ghostty stream_terminal.zig:1442-1447 and wezterm csi.rs:2224-2233 accept `>q` and `>0q`");
  eq_u("and the kind is the DCS", (unsigned)rc_report_take(&g, NULL), (unsigned)RC_REP_XTVER, "");
  rc_report_take(&g, NULL);
  put(&g, "\033[>1q");
  eq_u("a non-zero parameter is not the request", g.nUnsupported[RC_UN_SUP], 1, "");
  put(&g, "\033[q");
  eq_u("and the bare `q` is still XTSSZ, counted as before", g.nUnsupported[RC_UN_SUP], 2,
       "DECSCUSR needs its space interim (#88)");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033]7;/var/log/app.log\007");
  eq_u("a bare path is stored", (unsigned)g.carried.nCwd, 16u, "the same field OSC 9;9 writes (Render.h's cwd)");
  eq_u("starting with the slash it named", (unsigned)g.carried.cwd[0], (unsigned)'/', "");
  put(&g, "\033]7;file://dbhost/tmp/deploy\007");
  eq_u("the file:// authority is cut, not stored", (unsigned)g.carried.cwd[0], (unsigned)'/',
       "MSFT PathCreateFromUrlWlands on the same rule (adaptDispatch.cpp:2621-2637); ghostty keeps the raw "
       "payload and says the embedder decodes it (stream_terminal.zig:1527-1545) -- the cut is the smaller "
       "of the two, and it is the one that leaves the field meaning the same thing either way it arrived");
  eq_u("and the path survives the cut", (unsigned)g.carried.nCwd, 11u, "/tmp/deploy");
  put(&g, "\033]7;file://dbhost\007");
  eq_u("an authority with no path is refused", (unsigned)g.carried.nCwd, 11u,
       "the previous value stays: overwriting a directory with the root would be an act nobody sent");
  put(&g, "\033]7;\007");
  eq_u("and so is an empty payload", (unsigned)g.carried.nCwd, 11u, "path_is_legal's own rule, shared with 9;9");
  grid_ok(&g, "geo_gaps");
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

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[3\030""31m");
  eq_text(&g, 0, 3, "31m", "CAN abandons the CSI, the tail is painted as text");
  eq_u("CAN leaves attr", g.attr, 0x07, "no colour applied");

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

static unsigned un(const RcGrid *g, enum RcUnsupported which)
{
  return which < RC_UN_MAX ? (unsigned)g->nUnsupported[which] : 0u;
}

static void gm_wrap_suspect()
{
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
  put(&g, "1234567890123456789");
  {
    static const uint16_t hira = 0x3042;
    putu(&g, &hira, 1);
  }
  eq_u("a glyph moved whole pads the row it left", (unsigned)rc_row_wrap(&g, 0), RC_WRAP_PAD, "");
  eq_u("and the glyph is on the next row, not split", RC_CELLS(&g, 1)[0].ch, 0x3042, "leading half");
  eq_u("with its trailing cell", RC_CELLS(&g, 1)[1].attr & RC_LVB_TRAILING, RC_LVB_TRAILING, "");
  eq_u("padded, not forced, so a copy does not join the rows", (unsigned)rc_row_wrap(&g, 1), RC_WRAP_NONE, "");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "aaaaaaaaaaaaaaaaaaaa");
  eq_u("forced by a full row", (unsigned)rc_row_wrap(&g, 0), RC_WRAP_FORCED, "");
  put(&g, "\033[1;11H");
  eq_u("moving the cursor does not undo it", (unsigned)rc_row_wrap(&g, 0), RC_WRAP_FORCED, "");
  put(&g, "\033[K");
  eq_u("erasing to the margin does", (unsigned)rc_row_wrap(&g, 0), RC_WRAP_NONE, "");
  put(&g, "aaaaaaaaaaaaaaaaaaaa");
  put(&g, "\033[1;11H\033[5X");
  eq_u("erasing short of the margin leaves it standing", (unsigned)rc_row_wrap(&g, 0), RC_WRAP_FORCED, "");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "aaaaaaaaaaaaaaaaaaaa");
  put(&g, "bbbbbbbbbbbbbbbbbbbb");
  put(&g, "ccccccccccccccccccccdddddddddddddddddddd");
  eq_text(&g, 0, 4, "bbbb", "the scroll moved the content up");
  eq_u("with its reason", (unsigned)rc_row_wrap(&g, 0), RC_WRAP_FORCED, "");
  eq_u("and the row that came in is not wrapped", (unsigned)rc_row_wrap(&g, 3), RC_WRAP_NONE, "");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "aaaaaaaaaaaaaaaaaaaa");
  put(&g, "\033[1;1H\033[L");
  eq_u("IL shifts the claim down with the rows", (unsigned)rc_row_wrap(&g, 1), RC_WRAP_FORCED, "");
  eq_u("and the row it inserted has none", (unsigned)rc_row_wrap(&g, 0), RC_WRAP_NONE, "");
  put(&g, "\033[1;1H\033[M");
  eq_u("DL carries it up too", (unsigned)rc_row_wrap(&g, 0), RC_WRAP_FORCED, "");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[2;4r");
  eq_u("a scroll region is counted nowhere", un(&g, RC_UN_DECSTBM), 0, "the slot is dead but kept in place");
  eq_u("and makes the model suspect nowhere", (unsigned)rc_model_suspect(&g), 0, "its rows are known");
  eq_u("with the region itself live", (unsigned)g.carried.regSet, 1, "");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[?1049h");
  eq_u("the alt switch is not counted as unmodelled", un(&g, RC_UN_ALTBUF), 0, "");
  eq_u("and does not make the model suspect", (unsigned)rc_model_suspect(&g), 0,
       "a repaint of the whole window is enough for a screen the model chose");
  eq_u("it is counted where it belongs", g.nAltSwitch, 1, "one switch taken");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[?1000h");
  eq_u("mouse tracking is no longer a refusal", un(&g, RC_UN_MOUSE), 0,
       "#81: the family went from `ignored(RC_UN_MOUSE)` to a stored bit, so this is the same re-baseline "
       "#83 and #82 made for 2004 and 2048 -- and the old assertion is exactly as wrong as theirs would be");
  eq_u("because it is stored", (unsigned)(g.carried.mouseModes & (1u << 1)), (unsigned)(1u << 1),
       "bit 1 is 1000; the mapping is mouseBit() and `?1000$p` reads the same bit");
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

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[?1049h");
  eq_u("the alt screen is live", (unsigned)g.alt, 1, "");
  put(&g, "\033[31mRED");
  put(&g, "\033[1;3r\033[2;7H");
  put(&g, "\033[5 q");
  put(&g, "\033(0");
  put(&g, "\033)0\016");
  const unsigned scrolled = g.nScrolls;
  put(&g, "\033[!p");
  eq_u("DECSTR leaves the screen it was asked on", (unsigned)g.alt, 1, "");
  eq_text(&g, 0, 3, "RED", "and erases nothing, so the program's display is still there");
  eq_u("its cursor does not move", (unsigned)g.cy, 1, "");
  eq_u("nor its column", (unsigned)g.cx, 6, "");
  eq_u("nothing was pushed into history", (unsigned)(g.nScrolls == scrolled), 1, "");
  eq_u("DECSTR drops G0", (unsigned)g.carried.charset[0], 0, "a program that died in graphics mode leaves nothing behind");
  eq_u("and G1", (unsigned)g.carried.charset[1], 0,
       "named on its own because a leg that only checked what GL points at could pass with G1 still loaded");
  eq_u("and un-shifts GL back to G0", (unsigned)g.carried.gshift, 0,
       "SI is the default. The three arms above and this one are independent on purpose: in the state set up "
       "here both G0 and G1 are loaded, so clearing either one alone would already make the next `q` a letter, "
       "and only the fields spelled separately pin what a soft reset actually put back");
  put(&g, "q");
  eq_u("so an ordinary letter is an ordinary letter again", RC_CELLS(&g, 1)[6].ch, 'q',
       "the consequence the whole correction is about: this is U+2500 on the screen for the rest of the "
       "session when any of the four facts above is wrong");
  eq_u("the rendition is back to normal", (unsigned)(g.attr & 0x0F), 7, "");
  eq_u("the region is put back to the page", (unsigned)g.carried.regSet, 0, "");
  eq_u("the cursor shape is left alone", (unsigned)g.cursorShape, 5,
       "DECSTR's list has no shape in it, and the application that asked for one is still on this screen");
  put(&g, "\033[8");
  eq_u("a restore after a soft reset lands where the terminal already was", (unsigned)g.cy, 1,
       "the active buffer's saved state is cleared, not left pointing at a stale row (:3005-3008)");
  eq_u("and no cells moved on the way", RC_CELLS(&g, 0)[0].ch, 'R', "");

  put(&g, "\033c");
  eq_u("RIS leaves the alt screen", (unsigned)g.alt, 0, "");
  eq_u("and homes the cursor", (unsigned)g.cy, 0, "");
  eq_u("having run a viewport of rows up into history", (unsigned)(g.nScrolls > scrolled), 1, "");
  put(&g, "\033(B\033(0");
  eq_u("the charset is loaded by ESC ( 0", (unsigned)g.carried.charset[0], 1, "");
  put(&g, "\033)0\016");
  put(&g, "\033c");
  eq_u("and RIS drops it", (unsigned)g.carried.charset[0], 0, "a program that died in graphics mode leaves nothing behind");
  eq_u("RIS drops G1 with it", (unsigned)g.carried.charset[1], 0, "#85: all four slots, not just the one ESC ( could reach");
  eq_u("and un-shifts GL", (unsigned)g.carried.gshift, 0,
       "leaving SO standing over a cleared slot would be a half-reset: the shift and its slots are one claim");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[2;4r");
  put(&g, "\033[3;5H\033]133;P\007");
  eq_u("the mark is on its row", (unsigned)rc_row_mark(&g, 2), RC_PM_PROMPT, "");
  eq_u("at the column it was made", (unsigned)rc_mark_col(&g, 2), 4, "");
  put(&g, "\033[3;1H\033[1L");
  eq_u("IL inside the region blanks the row", RC_CELLS(&g, 2)[0].ch, ' ', "");
  eq_u("and the blanked row keeps no mark", (unsigned)rc_row_mark(&g, 2), RC_PM_NONE, "");
  eq_u("nor a column for the mark it no longer has", (unsigned)rc_mark_col(&g, 2), 0,
       "a stale column beside RC_PM_NONE is read as 'select from here' by a jump-to-prompt consumer");
  put(&g, "\033[5;5H\033]133;P\007");
  eq_u("a row the region refused keeps its own mark", (unsigned)rc_row_mark(&g, 4), RC_PM_PROMPT, "");
  eq_u("and its own column", (unsigned)rc_mark_col(&g, 4), 4, "");

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
  put(&g, "\033(0");
  put(&g, "n");
  put(&g, "\033[2b");
  eq_u("the repeat replays the code point, so it is remapped the same way", RC_CELLS(&g, 0)[9].ch,
       RC_CELLS(&g, 0)[8].ch, "a stored glyph instead of a stored letter would print 'n' here");
  eq_u("twice over", RC_CELLS(&g, 0)[10].ch, RC_CELLS(&g, 0)[8].ch, "");
}

static void gm_argcap()
{
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

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "abcdefghij\033[1;6H");
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

  rc_reset(&g, 20, 4, 0x07);
  put1(&g, "\033[33m");
  echo_eq("a unit-at-a-time SGR echoes complete", &g, "\033[33m", "");

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

  const uint16_t wide = 0x4E00;
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

  rc_reset(&g, 10, 3, 0x07);
  put(&g, "01234567");
  putu(&g, &wide, 1);
  eq_u("wide at cols-2 front", RC_CELLS(&g, 0)[8].attr & RC_LVB_LEADING, RC_LVB_LEADING, "");
  eq_u("wide at cols-2 back", RC_CELLS(&g, 0)[9].attr & RC_LVB_TRAILING, RC_LVB_TRAILING, "");
  eq_u("cursor wrapped after a full row", (unsigned)g.cx, 0, "");
  eq_u("row wrapped after a full row", (unsigned)g.cy, 1, "");
}

static void geo_decawm()
{
  static RcGrid g;
  const uint16_t wide = 0x4E00;
  const uint16_t narrowAstral[2] = { 0xD834, 0xDD1E };
  struct RcReportItem it;

  rc_reset(&g, 10, 3, 0x07);
  put(&g, "\033[?7l0123456789abc");
  eq_text(&g, 0, 10, "012345678c", "three characters past the margin overwrote the last cell");
  eq_u("cursor holds at the margin", (unsigned)g.cx, 9, "the cell a fixed-width status line keeps redrawing");
  eq_u("cursor never left the row", (unsigned)g.cy, 0, "nothing scrolled for a line that ended here");
  eq_u("the row claims no wrap", (unsigned)rc_row_wrap(&g, 0), (unsigned)RC_WRAP_NONE,
       "copy and export must not join a row the application ended");
  eq_u("the row below is blank", (unsigned)RC_CELLS(&g, 1)[0].ch, (unsigned)' ', "");

  put(&g, "\033[?7hZ");
  eq_u("the character that filled the row landed in it", (unsigned)RC_CELLS(&g, 0)[9].ch, (unsigned)'Z', "");
  eq_u("the row that had ended is forced", (unsigned)rc_row_wrap(&g, 0), (unsigned)RC_WRAP_FORCED, "");
  eq_u("cursor wrapped to the next row", (unsigned)g.cy, 1, "");
  put(&g, "Y");
  eq_text(&g, 1, 1, "Y", "and the next character starts it");

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

  rc_reset(&g, 10, 3, 0x07);
  putu(&g, &wide, 1);
  put(&g, "\033[1;1HA");
  eq_u("overwrite of the front half", (unsigned)RC_CELLS(&g, 0)[0].ch, (unsigned)'A', "");
  eq_u("ends the back half too", (unsigned)RC_CELLS(&g, 0)[1].ch, (unsigned)' ',
       "conhost trims the cluster the same way (Row.cpp's ReplaceCharacters)");
  eq_u("no stray trailing bit", (unsigned)(RC_CELLS(&g, 0)[1].attr & RC_LVB_TRAILING), 0,
       "left alone, it would be copied as part of a glyph that is no longer there");

  eq_u("the oracle widths U+1D11E as one column", (unsigned)rc_width(0x1D11E), 1,
       "this case is about the two-unit arm, and it only reaches that arm if the glyph is narrow");
  rc_reset(&g, 10, 3, 0x07);
  put(&g, "\033[?7l012345678");
  putu(&g, narrowAstral, 2);
  eq_u("neither half landed", (unsigned)RC_CELLS(&g, 0)[9].ch, (unsigned)' ', "");
  eq_u("and nothing wrapped to the next row", (unsigned)RC_CELLS(&g, 1)[0].ch, (unsigned)' ', "");

  rc_reset(&g, 10, 3, 0x07);
  put(&g, "\033[?7$p");
  eq_u("one request, one reply", (unsigned)rc_report_pending(&g), 1, "");
  eq_u("its kind", (unsigned)rc_report_take(&g, &it), (unsigned)RC_REP_DECRPM, "");
  eq_u("the mode that was asked about", (unsigned)it.mode, 7, "");
  eq_u("set, out of reset", (unsigned)it.status, 1, "DECAWM is on after a reset in VT and in both references");
  put(&g, "\033[?7l\033[?7$p");
  eq_u("the set spelled here is the one that answers", (unsigned)rc_report_pending(&g), 1,
       "`?7l` itself is silent");
  rc_report_take(&g, &it);
  eq_u("and says reset", (unsigned)it.status, 2, "");
  eq_u("none of this voted in the census", (unsigned)g.nUnsupported[RC_UN_MODE], 0,
       "an answered query is not an unmodelled request");

  put(&g, "\033[?7l\033[!p\033[?7$p");
  rc_report_take(&g, &it);
  eq_u("DECSTR restores it", (unsigned)it.status, 1,
       "a mode with no terminfo entry is still a mode a reset owns");
  put(&g, "\033[?7l\033c\033[?7$p");
  rc_report_take(&g, &it);
  eq_u("RIS restores it", (unsigned)it.status, 1, "");

  rc_reset(&g, 10, 3, 0x07);
  put(&g, "\033[7l\033[7h");
  eq_u("the two GATM spellings are counted as modes", (unsigned)g.nUnsupported[RC_UN_MODE], 2,
       "only the private spelling is DECAWM");
  eq_u("and left the wrap alone", (unsigned)g.carried.wrapMode, 1, "");
  put(&g, "0123456789");
  eq_u("so the row still wraps", (unsigned)rc_row_wrap(&g, 0), (unsigned)RC_WRAP_FORCED, "");
}

static void geo_wrap_wide_buffer(void)
{
  static RcGrid g;
  static uint16_t u[2001];
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
  const uint16_t pair[] = {0xD83D, 0xDE00};
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
  eq_u("the replacement takes the whole cell pair", RC_CELLS(&g, 0)[1].attr & RC_LVB_TRAILING,
       RC_LVB_TRAILING, "U+FFFD's own trailing cell, not a stray glyph");
  eq_u("the unit after a replacement still lands", RC_CELLS(&g, 0)[2].ch, 'A', "");
  eq_u("wantLow cleared", g.wantLow, 0, "");

  rc_reset(&g, 20, 3, 0x07);
  const uint16_t low = 0xDE00;
  putu(&g, &low, 1);
  eq_u("a lone low surrogate", RC_CELLS(&g, 0)[0].ch, 0xFFFD, "");
}

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
                               "other osc, dcs, report, colon, osc clip, charset") == 0), 1,
       "this is the text a rollout reads; renaming one here has to rename it in Render.java's report and in "
       "NativeRenderer's UNMODELLED, and the live gate now checks the first of those at run time");
  eq_u("an out-of-range slot names nothing", (rc_census_name(RC_UN_MAX) == NULL) ? 1u : 0u, 1u, "");

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

struct OscFx
{
  unsigned long un[RC_UN_MAX];
  unsigned long nTitleSet, nTitleTrunc, nClipSet, nClipBad, nClipSel, nClipRead;
  unsigned long nPromptMark, nReportOk, nReportFail, nReportFull;
  uint32_t pal16[16];
  RcRowState rowState[RC_MAX_ROWS];
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
  for (i = 0; i < 16; i++) f->pal16[i] = g->carried.pal16[i];
  for (i = 0; i < RC_MAX_ROWS; i++) f->rowState[i] = RC_ST(g, i);
  f->cx = g->cx; f->cy = g->cy; f->attr = g->attr; f->defAttr = g->carried.defAttr;
  f->titlePending = g->titlePending; f->clipPending = g->clipPending;
  f->nClip = g->nClip; f->nCwd = g->carried.nCwd;
  f->semanticContent = g->semanticContent; f->semanticClearEol = g->semanticClearEol;
  f->taskbarState = g->carried.taskbarState; f->taskbarProgress = g->carried.taskbarProgress;
  f->taskbarSeen = g->carried.taskbarSeen; f->lastExit = g->lastExit; f->palTouched = g->carried.palTouched;
}

static void geo_osc_families()
{
  static RcGrid g;
  static const struct { int code; const char *setup, *probe; } probe[] = {
    {    0, NULL,            "\033]0;gate title\007"  },
    {    1, NULL,            "\033]1;gate icon\007"   },
    {    2, NULL,            "\033]2;gate title\007"  },
    {    4, NULL,            "\033]4;1;rgb:ff/00/00\007" },
    {    7, NULL,            "\033]7;/gate/cwd\007"     },
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
  put(&g, "ABCDEFGH\033[42m\033[3;1H");
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

  const uint16_t hira = 0x3042;
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
  put(&g, "\033[2;4r\033[4;1H");
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
  eq_u("DECSCNM ?25 hides", (unsigned)g.carried.cursorVisible, 0, "");
  put(&g, "\033[?25h");
  eq_u("?25 shows", (unsigned)g.carried.cursorVisible, 1, "");
  put(&g, "\033[?47h\033[?1049l\033[?1000h\033[?2004h\033[1;2r\033[c");
  eq_u("alt switches taken", g.nAltSwitch, 2, "47 in and 1049 out -- one behaviour for the family");
  eq_u("nothing counted as an unmodelled alt buffer", g.nUnsupported[RC_UN_ALTBUF], 0, "");
  eq_u("mouse is no longer counted", g.nUnsupported[RC_UN_MOUSE], 0,
       "#81: `?1000h` in the sequence above is a store now, and the bucket keeps only what is refused (1001)");
  eq_u("and the store survived a DA1", (unsigned)g.carried.mouseModes, (unsigned)(1u << 1),
       "⚠ the feed ends in `CSI c`, which is DA1, NOT RIS (`ESC c`) -- it clears nothing, and a bit that "
       "answered 2 here would have meant the mouse mode rode through an unrelated query. The RIS arm of "
       "this claim is pinned in geo_mousemodes, where the sequence is spelled correctly");
  eq_u("bracketed paste is no longer counted", g.nUnsupported[RC_UN_DECBP], 0,
       "#83 turned this refusal into a store: `?2004 h/l` is a mode now, and the bucket is left to the "
       "OSC form, which asks for an executed paste and still has no surface here");
  eq_u("and the same sequence did set the bit", (unsigned)g.carried.bracketedPaste, 1,
       "a leg that only checks a count falling would also pass on a store that never happened");

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
  eq_u("and the region it asked for is live", (unsigned)g.carried.regSet, 1, "`CSI c` above is DA, not RIS");
}

static void geo_alt()
{
  static RcGrid g;
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "main\r\nsecond\r\nthird\r\n");
  rc_clear_dirty(&g);
  put(&g, "\033[2;6H");
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

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "zzz\r\n");
  put(&g, "\033[?47h\033[1;1Hq\033[?1047l");
  eq_text(&g, 0, 3, "zzz", "a 47 entry is undone by a 1047 exit");
  put(&g, "\033[?1047h\033[2;1Hw\033[?47l");
  eq_u("and the other way round", (unsigned)rc_in_alt(&g), 0, "");
  eq_text(&g, 0, 3, "zzz", "the row written to inside the alt is gone with it");
  eq_u("four switches", g.nAltSwitch, 4, "");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "keep\r\n");
  put(&g, "\033[?1049h\033[1;1Htemp\033[?1049h");
  eq_text(&g, 0, 4, "    ", "the second entry re-clears");
  eq_u("and stays on the alt", (unsigned)rc_in_alt(&g), 1, "");
  put(&g, "\033[?1049l");
  eq_text(&g, 0, 4, "keep", "the main screen survived the alt's own replacement");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "abcd\r\n\r\n\r\n");
  put(&g, "\033[7\033[3;5H\033[?1049l");
  eq_u("no-op leave stays on main", (unsigned)rc_in_alt(&g), 0, "");
  eq_u("cursor unmoved by it: row", (unsigned)g.cy, 2, "ESC 7 saved (0,3); a restore would have moved it");
  eq_u("cursor unmoved by it: column", (unsigned)g.cx, 4, "");
  eq_u("and no switch was taken", g.nAltSwitch, 0, "a no-op is not an event");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[?1049h\033[?25l\033[?1049l");
  eq_u("hidden inside the alt, hidden outside", (unsigned)g.carried.cursorVisible, 0, "as upstream ships it");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "main\r\n\033[?1049h\033[1;1Hgone\r\nmore\033c");
  eq_u("RIS left the alt", (unsigned)rc_in_alt(&g), 0, "");
  eq_text(&g, 0, 4, "    ", "the reset took the main screen's rows with it, as upstream's does");
  eq_text(&g, 1, 4, "    ", "and the alt's text went with the alt instead of leaking here");

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

  rc_reset_hist(&g, 20, 4, 4, 0x07);
  put(&g, "gutter\r\n\r\n\r\n\r\n");
  eq_u("a gutter row exists", (unsigned)g.pendingScrolls, 1, "setup");
  rc_clear_dirty(&g);
  put(&g, "\033[?1049h");
  eq_text(&g, 3, 6, "gutter", "the alt blanked the viewport and left the scrollback alone");
  eq_u("the gutter row is not dirty", (unsigned)rc_row_dirty(&g, 3), 0, "nothing about it changed");
  eq_u("the viewport is", (unsigned)rc_row_dirty(&g, 4), 1, "");
  put(&g, "altalt");
  put(&g, "\033[2J");
  put(&g, "\033[1;1HA\033[4;1HD");
  put(&g, "\r\n");
  eq_text(&g, 6, 1, "D", "the alt's own rows moved up");
  eq_text(&g, 7, 1, " ", "and a blank came in at its bottom");
  eq_text(&g, 4, 1, " ", "the row that left the alt's top is gone for good");
  eq_text(&g, 3, 6, "gutter", "and the scrollback above the alt is not part of its scroll");
  put(&g, "\033[?1049l");
  eq_text(&g, 3, 6, "gutter", "and it is still there afterwards");

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

  rc_reset(&g, 8, 4, 0x07);
  put(&g, "aaa\r\nbbb\r\nccc");
  put(&g, "\033[2;4H");
  put(&g, "\033[1M");
  eq_u("DL homes the cursor", (unsigned)g.cx, 0, "the left margin, which is column 0 without DECVSSM");
  eq_u("and leaves it on the row it deleted from", (unsigned)g.cy, 1, "");
  eq_text(&g, 1, 3, "ccc", "the delete itself happened");
  put(&g, "\033[3;6H");
  put(&g, "\033[1L");
  eq_u("IL homes it the same way", (unsigned)g.cx, 0, "");
  eq_u("on its own row", (unsigned)g.cy, 2, "");
  eq_text(&g, 1, 3, "ccc", "and pushed nothing that the cursor left behind");

  rc_reset(&g, 8, 5, 0x07);
  put(&g, "\033[2;4r");
  put(&g, "\033[1;1H1\033[2;1H2\033[3;1H3\033[4;1H4\033[5;1H5");
  put(&g, "\033[3;5H\033[1M");
  eq_u("DL in a region homes the cursor too", (unsigned)g.cx, 0, "");
  eq_u("and stays on its row", (unsigned)g.cy, 2, "");
  eq_text(&g, 2, 1, "4", "the region's rows moved");
  eq_text(&g, 0, 1, "1", "the row above the region did not");
  put(&g, "\033[1;7H");
  put(&g, "\033[1M");
  eq_u("a cursor the region refused keeps its column", (unsigned)g.cx, 6,
       "IL/DL outside the margins do nothing at all, cursor included");
  eq_u("and its row", (unsigned)g.cy, 0, "");
  eq_text(&g, 0, 1, "1", "and nothing moved underneath it");
}

static void geo_tabs()
{
  static RcGrid g;

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

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[1;6H\033H");
  eq_u("set tab stop leaves the cursor where it was", (unsigned)g.cx, 5, "`ESC H` does not move");
  put(&g, "\033[1;1H\t");
  eq_u("and the next tab finds it", (unsigned)g.cx, 5, "the table, not the arithmetic");
  put(&g, "\t");
  eq_u("while the default stop after it is still there", (unsigned)g.cx, 8,
       "MSFT materializes the defaults rather than replacing them (`_InitTabStopsForWidth`, :2799)");

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

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[3g\033c\t");
  eq_u("RIS puts the defaults back", (unsigned)g.cx, 8,
       "ghostty resets the table in its full reset (Terminal.zig:4943); MSFT's HardReset leaves it alone, and "
       "a session that cannot ask for its defaults back has no way to ask");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[3g\033[!p\t");
  eq_u("DECSTR does not", (unsigned)g.cx, 19, "neither reference touches tabs on a soft reset (I37's family)");

  {
    static uint8_t keep[RC_MAX_COLS];
    int keepDefaults;
    rc_reset(&g, 20, 4, 0x07);
    put(&g, "\033[1;6H\033H");
    memcpy(keep, g.carried.tabStop, sizeof keep);
    keepDefaults = g.carried.tabsDefaults;
    rc_reset_hist(&g, 40, 4, 0, 0x07);
    memcpy(g.carried.tabStop, keep, sizeof g.carried.tabStop);
    g.carried.tabsDefaults = keepDefaults;
    rc_tabs_widen(&g, 20);
    eq_u("a claimed stop is still claimed past a resize", (unsigned)g.carried.tabStop[5], 1, "the part build_model carries");
    eq_u("a column that did not exist gets the interval", (unsigned)g.carried.tabStop[24], 1,
         "MSFT fills only the newly allocated tail (:2805-2815), and so do we");
    eq_u("while a column that did is not re-decided", (unsigned)g.carried.tabStop[16], 1, "it was a stop and stays one");
    put(&g, "\033[1;17H\033[0g");
    rc_reset_hist(&g, 60, 4, 0, 0x07);
    memcpy(g.carried.tabStop, keep, sizeof g.carried.tabStop);
    g.carried.tabsDefaults = 1;
    g.carried.tabStop[16] = 0;
    rc_tabs_widen(&g, 40);
    eq_u("a cleared stop below the old width is not resurrected", (unsigned)g.carried.tabStop[16], 0,
         "the widen starts where the old grid ended, which is the whole point of passing `from`");
    eq_u("and the new tail does get the interval", (unsigned)g.carried.tabStop[48], 1, "");
    rc_reset_hist(&g, 60, 4, 0, 0x07);
    memset(g.carried.tabStop, 0, sizeof g.carried.tabStop);
    g.carried.tabsDefaults = 0;
    rc_tabs_widen(&g, 20);
    eq_u("with the flag down, a resize adds nothing", (unsigned)g.carried.tabStop[24], 0,
         "rc_tabs_widen obeys the flag -- and it is asked about column 24, because a widen starts where the "
         "old grid ended: the first version of this leg read column 8, which no widen ever fills, so it could "
         "not have failed for any reason at all");
    rc_reset(&g, 20, 4, 0x07);
    put(&g, "\033[3g");
    keepDefaults = g.carried.tabsDefaults;
    memcpy(keep, g.carried.tabStop, sizeof keep);
    rc_reset_hist(&g, 60, 4, 0, 0x07);
    memcpy(g.carried.tabStop, keep, sizeof g.carried.tabStop);
    g.carried.tabsDefaults = keepDefaults;
    rc_tabs_widen(&g, 20);
    eq_u("`CSI 3g` is what a resize then respects", (unsigned)g.carried.tabStop[24], 0,
         "the clear is a claim about the interval, not just about the array -- and the interval's only "
         "exposure to a resize is the tail, so that is where the question has to be asked");
    rc_reset(&g, 20, 4, 0x07);
    put(&g, "\033[3g\033[5g");
    keepDefaults = g.carried.tabsDefaults;
    memcpy(keep, g.carried.tabStop, sizeof keep);
    rc_reset_hist(&g, 60, 4, 0, 0x07);
    memcpy(g.carried.tabStop, keep, sizeof g.carried.tabStop);
    g.carried.tabsDefaults = keepDefaults;
    rc_tabs_widen(&g, 20);
    eq_u("and DECST8C puts it back, resize included", (unsigned)g.carried.tabStop[24], 1,
         "the same column, the opposite answer, one `CSI 5g` apart");
  }

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[1;6H\033H\033[?1049h\033[1;1H");
  put(&g, "\t");
  eq_u("the custom stop is still there on the alternate screen", (unsigned)g.cx, 5,
       "MSFT's table is on the terminal (:2649), ghostty's on the Terminal (Terminal.zig:56)");
  put(&g, "\033[?1049l");
  eq_u("and leaving it does not lose the stop either", (unsigned)g.cx, 5, "the same table, both ways");

  rc_reset(&g, 20, 4, 0x07);
  {
    static const uint16_t cjk = 0x4E00u;
    put(&g, "\033[1;9H");
    putu(&g, &cjk, 1);
  }
  eq_u("a wide glyph took two columns", (unsigned)g.cx, 10, "setup");
  put(&g, "\033[1;17H\033[Z");
  eq_u("back-tabs stop at 8, the leading half", (unsigned)g.cx, 8, "a stop the cursor can stand on");
  put(&g, "X");
  eq_u("writing there evicts its trailing half", (unsigned)RC_CELLS(&g, 0)[9].ch, ' ',
       "I35's narrow-over-leading rule: a narrow write on a LEADING clears the TRAILING it orphaned");
  eq_u("and the cursor moves on by one", (unsigned)g.cx, 9, "the glyph it replaced was two columns wide");
}

static void geo_region()
{
  static RcGrid g;

  rc_reset(&g, 8, 5, 0x07);
  put(&g, "\033[2;4r");
  eq_u("region live", (unsigned)g.carried.regSet, 1, "");
  eq_u("region top", (unsigned)g.carried.regTop, 1, "1-based parameters, counted from the viewport");
  eq_u("region bottom", (unsigned)g.carried.regBot, 3, "");
  eq_u("and a modelled sequence leaves the frame trusted", (unsigned)g.modelSuspect, 0, "");

  put(&g, "\033[H1\033[2;1H2\033[3;1H3\033[4;1H4\033[5;1H5");
  put(&g, "\033[4;1HX\n");
  eq_text(&g, 0, 1, "1", "the row above the region never moved");
  eq_text(&g, 1, 1, "3", "the region rotated up into the cursor row");
  eq_text(&g, 2, 1, "X", "");
  eq_text(&g, 3, 1, " ", "the blank opens at the region's bottom, not at the window's");
  eq_text(&g, 4, 1, "5", "and the row under it is untouched -- this is the Status-bar case");
  eq_u("a LF at the region bottom keeps its row", (unsigned)g.cy, 3, "");
  eq_u("a region scroll asks the console for nothing", (unsigned)g.pendingScrolls, 0,
       "only a whole-viewport scroll can be a window slide");
  eq_u("and is still counted as a scroll", g.nScrolls, 1, "");

  put(&g, "\033[3;2r");
  eq_u("top above bottom leaves the live region alone", (unsigned)g.carried.regSet, 1, "");
  eq_u("at its own top", (unsigned)g.carried.regTop, 1, "");
  eq_u("and its own bottom", (unsigned)g.carried.regBot, 3, "");
  put(&g, "\033[2r");
  eq_u("one argument names the top", (unsigned)g.carried.regTop, 1, "row 2 of the viewport");
  eq_u("and the bottom defaults to the viewport's last row", (unsigned)g.carried.regBot, 4, "");
  put(&g, "\033[r");
  eq_u("no argument is the reset form", (unsigned)g.carried.regSet, 0, "");
  put(&g, "\033[1;99r");
  eq_u("a whole-viewport request is normalised away", (unsigned)g.carried.regSet, 0,
       "whatever the parameter that got it there: the paths that carry history out of the gutter branch on this");
  rc_reset(&g, 8, 5, 0x07);
  put(&g, "\033[4;99r");
  eq_u("a bottom past the viewport clamps instead of refusing", (unsigned)g.carried.regSet, 1,
       "MSFT would ignore this whole request; the app asked for rows 4..end and that is what it gets");
  eq_u("top", (unsigned)g.carried.regTop, 3, "");
  eq_u("bottom is the viewport's last row", (unsigned)g.carried.regBot, 4, "");

  rc_reset(&g, 8, 5, 0x07);
  put(&g, "\033[0;3r");
  eq_u("CSI 0;3r means CSI 1;3r: top", (unsigned)g.carried.regTop, 0, "");
  eq_u("and bottom", (unsigned)g.carried.regBot, 2, "");

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

  put(&g, "\033[2;1H\033M");
  eq_text(&g, 1, 1, " ", "RI at the region top opened a blank there");
  eq_text(&g, 2, 1, " ", "and pushed the region down");
  eq_text(&g, 3, 1, "3", "the row that fell out of the region's bottom is gone");
  eq_u("RI spent no window scroll", (unsigned)g.pendingScrolls, 0, "");
  put(&g, "\033[4;1H\033M");
  eq_u("RI below the region top is only a move", (unsigned)g.cy, 2, "");

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

  rc_reset(&g, 8, 5, 0x07);
  put(&g, "\033[2;4r\033[1;3H");
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

  rc_reset_hist(&g, 8, 3, 2, 0x07);
  put(&g, "\033[1;3r");
  eq_u("no region for a full-height request", (unsigned)g.carried.regSet, 0, "");
  put(&g, "\033[3;1HZ\n");
  eq_u("so its LF asks the console to scroll", (unsigned)g.pendingScrolls, 1, "");
  rc_reset_hist(&g, 8, 3, 2, 0x07);
  put(&g, "\033[3;99r");
  eq_u("a region inside a guttered grid: top", (unsigned)g.carried.regTop, 4, "the viewport's last model row");
  eq_u("bottom clamped", (unsigned)g.carried.regBot, 4, "");
  put(&g, "\033[3;1HZ\n");
  eq_text(&g, 4, 1, " ", "one-row region: the LF blanked it in place");
  eq_u("and asked the console for nothing", (unsigned)g.pendingScrolls, 0, "");

  rc_reset_hist(&g, 4, 4, 8, 0x07);
  put(&g, "\033[1;1Hr0\033[2;1Hr1\033[3;1Hr2\033[4;1Hr3");
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

  rc_reset(&g, 8, 4, 0x07);
  put(&g, "\033[3;5H\033[?1048h\033[1;1H");
  eq_u("moved away", (unsigned)g.cy, 0, "");
  put(&g, "\033[?1048l");
  eq_u("?1048l restored the row", (unsigned)g.cy, 2, "");
  eq_u("and the column", (unsigned)g.cx, 4, "");
  put(&g, "\033[1;1H\033[7\033[2;2H\033[?1048h\033[8");
  eq_u("and DECSC finds the ?1048 save, not its own", (unsigned)g.cy, 1, "one slot, so the later save won");
  eq_u("in both columns", (unsigned)g.cx, 1, "XTermSaveRestoreCursor keeps one position, not two");

  rc_reset(&g, 8, 3, 0x07);
  put(&g, "\033[2;3r\033[?25l\033[1 qX\033c");
  eq_u("RIS cleared the region", (unsigned)g.carried.regSet, 0, "");
  eq_u("RIS showed the cursor", (unsigned)g.carried.cursorVisible, 1, "");
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

  rc_reset(&g, 8, 3, 0x07);
  put(&g, "A\033[?!p");
  eq_text(&g, 0, 1, "A", "`CSI ? ! p` resets nothing -- upstream's Pvt would read \"?!\"");
  eq_u("and the refusal is counted", g.nUnsupported[RC_UN_SUP], 1,
       "an unknown final with a body we did not run, exactly as the parameterised spelling above");

  rc_reset(&g, 8, 3, 0x07);
  put(&g, "\033[p\033[61p");
  eq_text(&g, 0, 1, " ", "and neither of them paints, moves or clears anything beyond that");
  eq_u("a bare `p` and `61p` are each counted", g.nUnsupported[RC_UN_SUP], 2, "neither is DECSTR");
  eq_u("counted without suspicion", (unsigned)g.modelSuspect, 0,
       "the reach is known-inert, so no full repaint is bought");

  rc_reset(&g, 8, 3, 0x07);
  put(&g, "\033[?12h\033[?7l\033[?1h\033[?2004h\033[?1000h\033[?1005l\033[?7h");
  eq_u("?12 is still counted as a mode", g.nUnsupported[RC_UN_MODE], 1,
       "?7 left this list when DECAWM became a modelled mode (I35), and ?1 left it when #114 stored DECCKM;"
       " both are still in the stream above, which is the proof -- the count fell by one for each of them");
  eq_u("and ?1h really stored the bit rather than being dropped", (unsigned)g.carried.cursorKeys, 1u,
       "the census going quiet is only honest if the mode was acted on; a silent drop would look identical here");
  eq_u("and the mode is back on", (unsigned)g.carried.wrapMode, 1, "the trailing `?7h` is part of the stream, not a fix-up");
  eq_u("bracketed paste is stored and not bucketed", g.nUnsupported[RC_UN_DECBP], 0,
       "the bucket means the OSC `]2004;` request to execute a paste (#83); this stream has no OSC in it");
  eq_u("with the bit set by the `?2004h` above", (unsigned)g.carried.bracketedPaste, 1, "");
  put(&g, "\033[?2004$p");
  {
    struct RcReportItem it;
    eq_u("one DECRPM armed", (unsigned)rc_report_take(&g, &it), (unsigned)RC_REP_DECRPM, "");
    eq_u("about 2004", (unsigned)it.mode, 2004, "jline4 looks the number up out of the reply");
    eq_u("and it is set", (unsigned)it.status, 1, "");
  }
  put(&g, "\033[?2004l\033[?2004$p");
  {
    struct RcReportItem it;
    rc_report_take(&g, &it);
    eq_u("turning it off is a store too", (unsigned)g.carried.bracketedPaste, 0, "");
    eq_u("and the answer follows", (unsigned)it.status, 2, "2 = not set, 1 = set: DEC's pair, and the only one this build sends");
  }

  eq_u("the mouse family is stored, not refused", g.nUnsupported[RC_UN_MOUSE], 0,
       "#81 rewrote this leg: the feed above sends `?1000h` and `?1005l`, and both are bits now");
  eq_u("?1000h set bit 1", (unsigned)(g.carried.mouseModes & (1u << 1)), (unsigned)(1u << 1), "");
  eq_u("and ?1005l left bit 5 clear", (unsigned)(g.carried.mouseModes & (1u << 5)), 0u,
       "one bit per number (ghostty's ModePacked shape): setting 1000 must not answer for 1005, "
       "and clearing 1005 must not disturb 1000");
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

  /* DECSTBM homes the cursor -- T-03. Its own rc_reset, because the sequence above leaves a region and a
     suspect count behind, and a leg that inherits state cannot say what it proved. */
  rc_reset(&g, 8, 5, 0x07);
  /* Park the cursor away from home first. rc_reset leaves it at (0,0) on a buffer with no history, so a
     "homes it" assertion written against the fresh grid passes without the implementation doing anything
     -- green either way is the same as having no leg. */
  put(&g, "\033[4;3H");
  eq_u("setup: the cursor is where I put it", (unsigned)g.cy, 3, "");
  eq_u("setup: and in the column I put it", (unsigned)g.cx, 2, "");
  put(&g, "\033[2;4r");
  eq_u("a region homes the cursor to its top", (unsigned)g.cy, 0u,
       "the stream's DECSTBM always homes: conhost's dispatch passes homeCursor=true for every CSI r that "
       "reaches it (OutputStateMachineEngine.cpp:456-457 -> adaptDispatch.cpp:2299), and ghostty ends "
       "setTopAndBottomMargin with an unconditional setCursorPos(1,1) (Terminal.zig:2609). The reason string "
       "this row used to carry cited SetScrollRegion -- an internal scroll routine, not the VT dispatch "
       "port -- which is how a non-homing implementation got pinned as the spec.");
  eq_u("and homes it to column 0", (unsigned)g.cx, 0u, "");
  put(&g, "\033[4;3H\033[3;2r");
  eq_u("an ignored set moves nothing, the cursor included", (unsigned)g.cy, 3,
       "top above bottom is refused before any state is touched");
  eq_u("and leaves the live region alone", (unsigned)g.carried.regSet, 1, "");
  put(&g, "\033[4;3H\033[r");
  eq_u("the no-parameter form drops the region", (unsigned)g.carried.regSet, 0, "");
  eq_u("and homes as well, same dispatch", (unsigned)g.cy, 0u, "");
}

/* WORK_ORDER_1006 T-11/T-12: what a rebuild keeps and what it drops. build_model (RenderExec.cpp) makes a
   fresh grid with rc_reset_hist and then copies RcCarried whole -- the legs below replay exactly those two
   steps on a live grid, so each "survived"/"gone" answer is the model's own, not a paraphrase of it. They
   assert today's truth: every reason names the defect it pins, and a fix flips the assertion. */
static void rebuild_consequences()
{
  static RcGrid g;

  /* T-11a: DECSET ?25 l now survives a rebuild */
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?25l");
  eq_u("setup: the stream hid the cursor", (unsigned)g.carried.cursorVisible, 0, "");
  {
    RcCarried keep = g.carried;
    const int oC = g.cols, oR = g.rows, oW = g.winRows;
    rc_reset_hist(&g, 20, 6, 0, 0x07);
    g.carried = keep;
    carried_readopt(&g, oC, oR, oW);
  }
  eq_u("T-11a: the same rebuild keeps the hide", (unsigned)g.carried.cursorVisible, 0,
       "cursorVisible rides RcCarried and rc_modes' row 25 now says carried=1, so a window resize no "
       "longer revokes `CSI ?25l` behind the app's back -- the #114 cursorKeys rule applied to the one "
       "field it had missed; before the fix rc_reset_hist forced the bit back to 1 and Paint's setVisible "
       "arm lit the host cursor while mode_status kept answering as if the hide were in force");

  /* T-11b: the vertical band now crosses a rebuild like the horizontal one */
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?69h\033[2;4r\033[3;10s");
  eq_u("setup: the scroll band is armed", (unsigned)g.carried.regSet, 1, "");
  eq_u("setup: and so are the column margins", (unsigned)g.carried.marginSet, 1, "");
  {
    RcCarried keep = g.carried;
    const int oC = g.cols, oR = g.rows, oW = g.winRows;
    rc_reset_hist(&g, 20, 6, 0, 0x07);
    g.carried = keep;
    carried_readopt(&g, oC, oR, oW);
  }
  eq_u("T-11b: the same-size rebuild keeps the band", (unsigned)g.carried.regSet, 1, "");
  eq_u("top unchanged", (unsigned)g.carried.regTop, 1, "");
  eq_u("bottom unchanged", (unsigned)g.carried.regBot, 3, "");
  eq_u("and the horizontal band with it", (unsigned)g.carried.marginSet, 1,
       "regSet/regTop/regBot ride RcCarried and carried_readopt re-clamps them exactly like the margin "
       "pair -- msfterm's keep-and-clamp answer (adaptDispatch.cpp:276-296); ghostty (Terminal.zig:4188-"
       "4194) and wezterm (terminalstate/mod.rs:1003-1004) reset both bands instead, but this code's "
       "horizontal precedent was already keep-and-clamp, so vertical now matches horizontal here too");
  {
    RcCarried keep = g.carried;
    const int oC = g.cols, oR = g.rows, oW = g.winRows;
    rc_reset_hist(&g, 20, 4, 2, 0x07);
    g.carried = keep;
    carried_readopt(&g, oC, oR, oW);
  }
  eq_u("a shrink to four window rows rebases the band", (unsigned)g.carried.regTop, 3,
       "the viewport's gutter grew from 0 to 2, so viewport rows 1..3 are now absolute 3..5");
  eq_u("and clamps the bottom", (unsigned)g.carried.regBot, 5, "");
  eq_u("band still armed", (unsigned)g.carried.regSet, 1, "");
  {
    RcCarried keep = g.carried;
    const int oC = g.cols, oR = g.rows, oW = g.winRows;
    rc_reset_hist(&g, 20, 1, 5, 0x07);
    g.carried = keep;
    carried_readopt(&g, oC, oR, oW);
  }
  eq_u("a shrink to one window row drops the band", (unsigned)g.carried.regSet, 0,
       "after the rebase and clamp the band covers the whole (single-row) viewport, and a full-window "
       "band is no band -- same convention DECSTBM itself uses when the stream asks for the whole screen");

  /* T-11c: DECRC after a rebuild returns to the cell DECSC stood on */
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[3;5HX");
  put(&g, "\033" "7");
  {
    RcCarried keep = g.carried;
    const int oC = g.cols, oR = g.rows, oW = g.winRows;
    rc_reset_hist(&g, 20, 6, 0, 0x07);
    g.carried = keep;
    carried_readopt(&g, oC, oR, oW);
  }
  put(&g, "\033" "8");
  eq_u("T-11c: DECRC after a rebuild returns to the saved row", (unsigned)g.cy, 2, "");
  eq_u("and the saved column", (unsigned)g.cx, 5,
       "saveX/saveY ride RcCarried and carried_readopt rebases the row by the viewport shift -- wezterm "
       "adjusts its saved cursor through a resize the same way (terminalstate/mod.rs:1016-1021); before "
       "the fix half the save crossed (saveOrigin) and the position restored to the home corner");
  {
    RcCarried keep = g.carried;
    const int oC = g.cols, oR = g.rows, oW = g.winRows;
    rc_reset_hist(&g, 20, 6, 6, 0x07);
    g.carried = keep;
    carried_readopt(&g, oC, oR, oW);
  }
  put(&g, "\033" "8");
  eq_u("a gutter-growing rebuild keeps the screen place", (unsigned)g.cy, 8,
       "the viewport moved down six rows, so saved viewport row 2 is absolute row 8 now");

  /* T-12c: RIS records a full window of scroll debt and retires the bare-home arm -- on purpose */
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[1;1Hr0\033[2;1Hr1\033[3;1Hr2\033[4;1Hr3\033[5;1Hr4");
  put(&g, "\033c");
  eq_u("setup: RIS owes the host a whole window", (unsigned)g.pendingScrolls, 6, "");
  eq_u("and disarmed the takeover arm on its way out", (unsigned)g.carried.unpushed, 0, "");
  put(&g, "\033[3;1H");
  put(&g, "\033[H");
  eq_u("T-12c: a bare home after RIS pays none of it", (unsigned)g.pendingScrolls, 6,
       "intended, not debt left to rot: RIS cleared the screen and homed the cursor itself, so the "
       "takeover arm's own gate (cy > tr on a bare home) could not fire anyway and full_reset retires "
       "carried.unpushed deliberately; the pendingScrolls balance is ordinary paint economy -- the next "
       "flush pays it, and with a live handle scroll_up's onFlush arm pays it inside the RIS dispatch "
       "itself, because a full window of scrolls is exactly what fills the gutter");
}

static void status_bar()
{
  static RcGrid g;

  rc_reset(&g, 8, 5, 0x07);
  put(&g, "\033[4;1HZ");
  put(&g, "\033" "7");
  put(&g, "\033[1;4r");
  put(&g, "\033" "8");
  eq_u("the region is the viewport minus the status row", (unsigned)g.carried.regTop, 0, "model rows 0..3 scroll");
  eq_u("bottom", (unsigned)g.carried.regBot, 3, "");
  eq_u("and the caller came back from the save", (unsigned)g.cy, 3, "row 3, not the row the region ends on");
  eq_u("in the column it was in", (unsigned)g.cx, 1, "'Z' had already moved it one column right");

  put(&g, "\033[5;1HSTATUS");
  put(&g, "\033" "8");
  eq_text(&g, 4, 8, "STATUS  ", "the bar is the viewport's last row, written to its full width");
  eq_u("the cursor did not stay in the status row", (unsigned)g.cy, 3,
       "this is the reference implementation's fault: a region change whose save it never replays");
  eq_u("at the column it was saved at", (unsigned)g.cx, 1, "");
  eq_u("painting a status line scrolled nothing", (unsigned)g.nScrolls, 0, "");
  eq_u("and asked the console for no scroll", (unsigned)g.pendingScrolls, 0,
       "row 4 is outside the region, so writing it cannot move the window");

  rc_paint_done(&g);
  put(&g, "\033[1;1HA\033[2;1HB\033[3;1HC\033[4;1HD\n");
  eq_text(&g, 0, 1, "B", "the region scrolled under the cursor at its bottom edge");
  eq_text(&g, 2, 1, "D", "");
  eq_text(&g, 3, 1, " ", "the LF blanked the row the cursor left");
  eq_text(&g, 4, 6, "STATUS", "the bar survived the scroll -- this is the whole point of the region");
  eq_u("one region scroll", (unsigned)g.nScrolls, 1, "");
  eq_u("the window advances", (unsigned)g.pendingScrolls, 1,
       "a top-of-page region scroll is a page scroll, and the evicted line is history, not garbage");
  eq_u("and the bar's row owes a repaint", (unsigned)rc_row_dirty(&g, 4), 1,
       "it keeps its content but not its buffer row -- MSFT's static-band copy at :2476");

  put(&g, "\033" "7\033[1;1r\033" "8");
  eq_u("csr(0, 0) through %i is a region, not a reset", (unsigned)g.carried.regSet, 1,
       "Status.java's reset; Display.java:112 turns a 0x0 size into rows=1 -- the same trap, one layer down");
  eq_u("a one-row region: top", (unsigned)g.carried.regTop, 0, "");
  eq_u("bottom", (unsigned)g.carried.regBot, 0, "so only the viewport's first row can scroll any more");
  put(&g, "\033" "7\033[r\033" "8");
  eq_u("the bare form is the reset", (unsigned)g.carried.regSet, 0, "");
  eq_u("and it moved nothing", (unsigned)g.cy, 3, "`CSI r` homes no cursor (Ansi.cpp:4146-4174)");

  static RcGrid g2;
  rc_reset(&g2, 20, 6, 0x07);
  put(&g2, "\033[1;1HAAAA\nBBBB\nCCCC\nDDDD");
  put(&g2, "\033" "7\033[1;4r\033" "8");
  put(&g2, "\033[5;1H----------\n==========");
  eq_text(&g2, 4, 11, "---------- ", "the bar's first row keeps its row, and ends there");
  eq_text(&g2, 5, 11, "========== ", "the newline between the bar's lines moved down, it did not scroll");
  eq_text(&g2, 0, 5, "AAAA ", "row 0 of the region is where the caller left it");
  eq_text(&g2, 3, 5, "DDDD ", "and so is its bottom row -- nothing rotated");
  eq_u("a line feed below the region scrolled nothing", (unsigned)g2.nScrolls, 0, "");
  eq_u("the cursor is on the bar's second row", (unsigned)g2.cy, 5, "");
  put(&g2, "\n");
  eq_u("at the page bottom, still below the region, still no scroll", (unsigned)g2.nScrolls, 0,
       "MSFT clamps to page.Bottom() - 1 rather than cycling the buffer (:2448-2452)");
  eq_u("the cursor stays on the last row", (unsigned)g2.cy, 5, "");
  eq_text(&g2, 5, 11, "========== ", "the bar's last row survived its own trailing newline");
}

static void geo_takeover()
{
  static RcGrid g;
  rc_reset_hist(&g, 20, 6, 14, 0x07);
  put(&g, "main\r\nsecond\r\nthird\r\nfourth\r\nfifth\r\nsixth\r\nseventh\r\n");
  rc_clear_dirty(&g);
  put(&g, "\033[?1049h");
  put(&g, "\033[1;5r");
  put(&g, "\033[6;1HSTAT");
  put(&g, "\033[1;1HA1\r\nA2\r\nA3\r\nA4\r\nA5\n");
  eq_text(&g, 12, 1, "main", "P1-2: the main screen's gutter rows are the snapshot to restore, not history to rotate");
  eq_text(&g, 13, 1, "second", "");
  eq_u("P1-2: an alt page feed charges no scroll", (unsigned)g.pendingScrolls, 0,
       "entering the alt zeroes the debt (no scrollback to pay into) and a region feed inside it adds nothing");
  eq_text(&g, 14, 1, "A2", "the alt's own region rotated internally");
  eq_text(&g, 17, 1, "A5", "");
  eq_text(&g, 18, 1, "  ", "the rotation's incoming blank");
  eq_text(&g, 19, 1, "STAT", "the TUI's status row below the region holds what it held");
  put(&g, "\033[?1049l");
  eq_text(&g, 14, 1, "third", "leaving the alt restores the main screen row for row");
  eq_text(&g, 13, 1, "second", "");

  rc_reset_hist(&g, 20, 6, 14, 0x07);
  put(&g, "L1\nL2\nL3\nL4\nL5\nL6\nL7\nL8");
  eq_u("natural scrolling armed the takeover", (unsigned)g.pendingScrolls, 2, "");
  eq_text(&g, 14, 2, "L3", "the viewport's top row before the takeover");
  eq_u("the cursor is where the output stopped", (unsigned)g.cy, 19, "");

  put(&g, "\033[H");
  eq_u("the takeover banked the live viewport", (unsigned)g.pendingScrolls, 2 + 6,
       "rows 14..19 held content and the cursor sat below the top: six rows pushed");
  eq_text(&g, 13, 2, "L8", "the last painted row rode the push into the gutter");
  eq_text(&g, 14, 2, "  ", "the viewport is the blanks the push scrolled in");
  eq_text(&g, 19, 2, "  ", "");
  eq_u("and disarmed itself", (unsigned)g.carried.unpushed, 0, "");
  eq_u("the cursor homed", (unsigned)g.cy, 14, "");

  rc_paint_done(&g);
  put(&g, "\033[H");
  eq_u("a second home is a repaint, not a second push", (unsigned)g.pendingScrolls, 0, "");
  put(&g, "\033[20;1H");
  eq_u("parked on the bottom row", (unsigned)g.cy, 19, "");
  put(&g, "\033[1;1H");
  eq_u("an addressed 1;1 is not a takeover", (unsigned)g.pendingScrolls, 0,
       "the contract's voice is the parameterless \\E[H; explicit addressing means the row it names");
  eq_u("and it still moves the cursor", (unsigned)g.cy, 14, "");
  put(&g, "\033[20;1H");
  put(&g, "\033[4;1H");
  eq_u("an upward mid-screen jump charges nothing either", (unsigned)g.pendingScrolls, 0,
       "only the bare jump to the viewport's top is a takeover");
  eq_u("and it still moves the cursor", (unsigned)g.cy, 17, "");

  rc_paint_done(&g);
  put(&g, "\033[1;4r");
  put(&g, "\033[4;1HL9\r\nL10\r\nL11");
  const unsigned debtWithRegion = g.pendingScrolls;
  eq_u("armed inside the region", (unsigned)g.carried.unpushed, 1, "");
  put(&g, "\033[H");
  eq_u("P1-1: a region is live, so the takeover stands down", (unsigned)g.pendingScrolls, debtWithRegion,
       "the bank is whole-model; paying it at the region's bottom would desync host and model");
  eq_u("and the flag stays armed for a later bar-less home", (unsigned)g.carried.unpushed, 1, "");
  eq_u("the cursor still homed", (unsigned)g.cy, 14, "");
  put(&g, "\033[r");
  put(&g, "\033[5;1Hx");
  put(&g, "\033[H");
  eq_u("with the region gone the home banks again", (unsigned)g.pendingScrolls, debtWithRegion + 5,
       "the cursor sat on model row 18, so the bank is the five rows below the top");
}

static void geo_oracle_teeth()
{
  static RcGrid g;
  static RcGrid saved;
  char msg[256];
  int viol;

  rc_reset_hist(&g, 6, 20, 4, 0x07);
  saved = g;
  viol = rc_validate_grid(&g, msg, (int) sizeof msg);
  g_checks++;
  if (viol) { g_fails++; printf("  FAIL oracle: a fresh, legal grid was reported dirty: %s\n", msg); }

  g.cx = g.cols;
  viol = rc_validate_grid(&g, msg, (int) sizeof msg);
  g_checks++;
  if (!viol) { g_fails++; printf("  FAIL oracle is silent on a cursor at column == cols (cx=%d cols=%d)\n",
                                 g.cx, g.cols); }
  else
  {
    g_checks++;
    if (!strstr(msg, "cursor column")) { g_fails++; printf("  FAIL oracle named something else: %s\n", msg); }
  }

  g = saved;
  g.winRows = g.rows + 1;
  viol = rc_validate_grid(&g, msg, (int) sizeof msg);
  g_checks++;
  if (!viol) { g_fails++; printf("  FAIL oracle is silent on winRows(%d) above rows(%d)\n", g.winRows, g.rows); }
  else
  {
    g_checks++;
    if (!strstr(msg, "winRows")) { g_fails++; printf("  FAIL oracle mis-named the tall window: %s\n", msg); }
  }
}

static void geo_mousemodes()
{
  static RcGrid g;
  static const int ID[]  = { 9, 1000, 1002, 1003, 1004, 1005, 1006, 1015, 1016 };
  static const int BIT[] = { 0, 1, 2, 3, 4, 5, 6, 7, 8 };
  const int n = (int)(sizeof ID / sizeof ID[0]);
  char seq[24];
  int i;

  for (i = 0; i < n; i++)
  {
    rc_reset(&g, 20, 6, 0x07);
    sprintf(seq, "\033[?%dh", ID[i]);
    put(&g, seq);
    eq_u(S("?%dh sets its own bit", ID[i]), (unsigned)g.carried.mouseModes, (unsigned)(1u << BIT[i]),
         S("got 0x%x want 0x%x -- one bit per number, per ghostty's ModePacked",
           (unsigned)g.carried.mouseModes, (unsigned)(1u << BIT[i])));
    eq_u(S("?%dh costs no refusal", ID[i]), g.nUnsupported[RC_UN_MOUSE], 0u,
         "the bucket is for numbers this build does not hold (1001); a stored mode voting there is #85's "
         "'recognised but called unrecognised' error in a new costume");
    eq_u(S("?%dh moves no cell", ID[i]), (unsigned)rc_model_suspect(&g), 0u,
         "no repaint for a mode the screen cannot show; the census is where an ask stays visible");
  }

  rc_reset(&g, 20, 6, 0x07);
  for (i = 0; i < n; i++)
  {
    struct RcReportItem it;
    sprintf(seq, "\033[?%d$p", ID[i]);
    put(&g, seq);
    eq_u(S("?%d$p arms a reply before it was ever set", ID[i]), (unsigned)rc_report_pending(&g), 1u,
         "the model holds the bit (at 0), which is what makes the number answerable at all (#93: the status is DEC's, 2 for a bit that is clear)");
    rc_report_take(&g, &it);
    eq_u(S("  ...a DECRPM about %d", ID[i]), (unsigned)it.mode, (unsigned)ID[i],
         "jline4 looks the number up out of the reply (parseDecrpm at AbstractTerminal.java:675, reached with "
         "m.mode() from :651), so a reply filed "
         "under another id is worse than silence");
    eq_u(S("  ...answered 2 = not set", ID[i]), (unsigned)it.status, 2u, "");
    sprintf(seq, "\033[?%dh", ID[i]);
    put(&g, seq);
    sprintf(seq, "\033[?%d$p", ID[i]);
    put(&g, seq);
    rc_report_take(&g, &it);
    eq_u(S("  ...and 1 = set after `?%dh`", ID[i]), (unsigned)it.status, 1u, "");
    sprintf(seq, "\033[?%dl", ID[i]);
    put(&g, seq);
    sprintf(seq, "\033[?%d$p", ID[i]);
    put(&g, seq);
    rc_report_take(&g, &it);
    eq_u(S("  ...and back to 2 after `?%dl`", ID[i]), (unsigned)it.status, 2u,
         "the reset arm: a bit that could only be set would answer 2 forever and lie on the next prompt");
  }

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?1000h\033[?1002h\033[?1006h");
  eq_u("three modes at once", (unsigned)g.carried.mouseModes,
       (unsigned)((1u << 1) | (1u << 2) | (1u << 6)),
       "1000 + 1002 + 1006: ghostty stores three bools and so do we, because `?1000$p` must still say 2 after "
       "1002 arrives -- a last-wins field would answer 1 and claim a mode nobody turned off");
  put(&g, "\033[?1002l");
  eq_u("clearing the middle leaves the other two", (unsigned)g.carried.mouseModes,
       (unsigned)((1u << 1) | (1u << 6)), "the whole reason for bit-per-number");

  put(&g, "\033c");
  eq_u("RIS drops every mouse bit", (unsigned)g.carried.mouseModes, 0u,
       "power-up state, the same reasoning as bracketedPaste and inbandResize");
  put(&g, "\033[?1003h\033[!p");
  eq_u("DECSTR leaves it set", (unsigned)g.carried.mouseModes, (unsigned)(1u << 3),
       "MSFT's SoftReset names InsertReplace/Origin/AllowDECSLRM and no mouse mode (adaptDispatch.cpp:2989)");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?1001h");
  eq_u("?1001 is still refused", g.nUnsupported[RC_UN_MOUSE], 1u,
       "neither reference recognises it (ghostty's table has no 1001; wezterm parses it into an empty arm, "
       "mod.rs:1892-1897), and this build reports no events for it to modify");
  eq_u("and it sets no bit", (unsigned)g.carried.mouseModes, 0u, "");
  eq_u("it votes the mouse bucket, not the mode one", g.nUnsupported[RC_UN_MODE], 0u,
       "a reader scanning the census for 'asked about the mouse' has to find it there");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?9$p\033[?1000$p\033[?1002$p\033[?1003$p\033[?1004$p"
          "\033[?1005$p\033[?1006$p\033[?1015$p\033[?1016$p");
  eq_u("all nine answers survive one payload", (unsigned)rc_report_pending(&g), (unsigned)n,
       "a program that wants to know which mouse protocol to speak asks every number in one write; the queue "
       "is bounded so it cannot leak, not so that a family can be truncated");
  eq_u("and none of them was refused", g.nReportFull, 0u,
       "a refusal here is a reader blocked on a reply that exists and was thrown away");
  {
    struct RcReportItem it;
    const char *seen = "";
    int order_ok = 1;
    for (i = 0; i < n; i++)
    {
      if (!rc_report_take(&g, &it)) { order_ok = 0; break; }
      if ((int)it.mode != ID[i]) { order_ok = 0; seen = "wrong id"; break; }
    }
    eq_u("in the order they were asked, each under its own number", (unsigned)order_ok, 1u,
         S("FIFO is the whole claim: %s. A reply that arrives shuffled is read as an answer about the wrong "
           "mode, which jline4 would then cache -- parseDecrpm(response, m.mode()) at "
           "AbstractTerminal.java:651 -> :675 looks each id up in the concatenated response.", seen));
    eq_u("and the queue is empty afterwards", (unsigned)rc_report_pending(&g), 0u,
         "a tenth reply left over would be spoken at the next reader's expense");
  }
  grid_ok(&g, "geo_mousemodes");
}

static void geo_decrpm_unmodelled()
{
  static RcGrid g;
  static const int UNMODELLED[] = { 12, 1034, 1048, 2000, 2027, 2031 };
  const int n = (int)(sizeof UNMODELLED / sizeof UNMODELLED[0]);

  rc_reset(&g, 20, 6, 0x07);
  for (int i = 0; i < n; i++)
  {
    char seq[40];
    sprintf(seq, "\033[?%d$p", UNMODELLED[i]);
    const unsigned long before = g.nUnsupported[RC_UN_MODE];
    put(&g, seq);
    eq_u("every id gets an answer", (unsigned)rc_report_pending(&g), 1, seq);
    struct RcReportItem it;
    const int kind = rc_report_take(&g, &it);
    eq_u("and it is a DECRPM", (unsigned)kind, (unsigned)RC_REP_DECRPM, seq);
    eq_u("for the number that was asked", (unsigned)it.mode, (unsigned)UNMODELLED[i], seq);
    eq_u("with the digit that says so", (unsigned)it.status, 0u,
         "0 = not recognized; 1 or 2 here would be the lie the old silence was avoiding");
    eq_u("and no mode vote, because the question was answered", g.nUnsupported[RC_UN_MODE] - before, 0u, seq);
  }
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?2027h");
  eq_u("the set still votes", g.nUnsupported[RC_UN_MODE], 1, "2027 is not stored, and that is the ask on record");
  put(&g, "\033[?2027$p");
  {
    struct RcReportItem it;
    rc_report_take(&g, &it);
    eq_u("and the query still answers 0, one vote later", (unsigned)it.status, 0u,
         "the two facts are about different sequences, and neither is allowed to swallow the other");
    eq_u("while answering added no vote of its own", g.nUnsupported[RC_UN_MODE], 1, "");
  }

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?1h\033[?4h\033[?6h\033[?69h\033[?2004h\033[?2026h\033[?2048h\033[?1$p\033[?4$p\033[?6$p\033[?69$p"
          "\033[?2004$p\033[?2026$p\033[?2048$p");
  eq_u("every state-holding id answers", (unsigned)rc_report_pending(&g), 7,
       "if one of these drops, the caller reads NOT_SUPPORTED for a mode we do hold."
       " ?3 is deliberately NOT in this seven: it answers from a permanent 4, never from a bit, and its"
       " legs are geo_deccolm");
  eq_u("and answering them votes nothing", g.nUnsupported[RC_UN_MODE], 0, "");
  {
    struct RcReportItem it;
    int bad = 0;
    for (int q = 0; q < 7; q++)
    {
      if (!rc_report_take(&g, &it) || it.status != 1) bad = q + 1;
    }
    eq_u("and all seven answer set, DEC's way", (unsigned)bad, 0u,
         "the value IS the slot that went wrong (1-based): 0 = every one of the seven answered 1 = set, which is"
         " what the payload earned by setting them. A 2 here is the pre-#93 inversion (this build used to send"
         " 2 for set) or a bit lost between the DECSET and the query");
    eq_u("the queue gave up all seven", (unsigned)rc_report_pending(&g), 0u, "");
  }
  grid_ok(&g, "geo_decrpm_silence");
}

static void geo_ckm()
{
  static RcGrid g;
  struct RcReportItem it;

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?1$p");
  eq_u("a fresh grid answers DECCKM at all", (unsigned)rc_report_pending(&g), 1u,
       "the bit exists, so the answer exists -- silence here is the pre-#114 build");
  eq_u("and the reply is taken", (unsigned)(rc_report_take(&g, &it) ? 1 : 0), 1u, "");
  eq_u("a fresh grid is reset, DEC's way (2)", (unsigned)it.status, 2u,
       "VT's power-up state for the cursor keys");
  eq_u("the id in the reply is the id asked", (unsigned)it.mode, 1u, "");

  put(&g, "\033[?1h\033[?1$p");
  eq_u("?1h answers set (1)", (unsigned)(rc_report_take(&g, &it) ? it.status : -1), 1u,
       "1 = set is #93's correction; a 2 here is the old inversion");
  put(&g, "\033[?1l\033[?1$p");
  eq_u("and ?1l answers reset again", (unsigned)(rc_report_take(&g, &it) ? it.status : -1), 2u,
       "a mode that only ever says 1 is a constant, not a state");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?1h");
  eq_u("the mode costs no cell", (unsigned)g.nCells, 0u, "DECCKM has no screen face in this model");
  eq_u("and no census vote, because it was acted on", g.nUnsupported[RC_UN_MODE], 0u,
       "a stored mode still voting MODE would tell the reader the terminal refused it");

  put(&g, "\033[?1h\033[!p\033[?1$p");
  eq_u("DECSTR leaves exactly one reply", (unsigned)rc_report_pending(&g), 1u, "");
  eq_u("DECSTR puts DECCKM back to reset", (unsigned)(rc_report_take(&g, &it) ? it.status : -1), 2u,
       "MSFT names CursorKey in SoftReset; a 1 here means the bit survived a reset that should have cleared it");
  put(&g, "\033[?1h\033c\033[?1$p");
  eq_u("RIS clears it too", (unsigned)(rc_report_take(&g, &it) ? it.status : -1), 2u, "as at power-up");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?2$p");
  eq_u("DECANM answers now", (unsigned)rc_report_pending(&g), 1u,
       "silence would claim the terminal has no idea what parsing mode it is in");
  eq_u("the reply is taken", (unsigned)(rc_report_take(&g, &it) ? 1 : 0), 1u, "");
  eq_u("the id in the reply is the id asked", (unsigned)it.mode, 2u, "");
  eq_u("and 3 = permanently set is the only true digit for it", (unsigned)it.status, 3u,
       "this parser has no VT52 table to switch into (ESC D is IND, ESC E is NEL); MSFT answers the same"
       " question from its state machine's parser mode, adaptDispatch.cpp:1957-1958");
  put(&g, "\033[?2h\033[?2$p");
  eq_u("?2h leaves it at 3", (unsigned)(rc_report_take(&g, &it) ? it.status : -1), 3u,
       "a permanent answer that a DECSET could move would be the lie this whole row exists to avoid");
  put(&g, "\033[?2l\033[?2$p");
  eq_u("and ?2l leaves it at 3", (unsigned)(rc_report_take(&g, &it) ? it.status : -1), 3u, "");
  eq_u("the two sets vote and the three asks vote nothing", g.nUnsupported[RC_UN_MODE], 2u,
       "the refusal to change parsing is still a refusal; answering the question is not");
  grid_ok(&g, "geo_ckm");
}

static void geo_deccolm()
{
  static RcGrid g;
  struct RcReportItem it;

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?3$p");
  eq_u("a fresh grid answers DECCOLM at all", (unsigned)rc_report_pending(&g), 1u,
       "silence was the pre-#109 build, and a caller cannot tell it from a dead terminal");
  eq_u("the reply is taken", (unsigned)(rc_report_take(&g, &it) ? 1 : 0), 1u, "");
  eq_u("the id in the reply is the id asked", (unsigned)it.mode, 3u, "");
  eq_u("and the status is 4 = permanently reset", (unsigned)it.status, 4u,
       "1 would claim 132 columns are active; 2 would claim a mode this terminal will let you set."
       " Both are I26, and jline4 reads 4 (and only 4, of 1/2/3/4) as NOT_SUPPORTED");

  put(&g, "\033[?3h\033[?3$p");
  eq_u("?3h leaves the answer at 4", (unsigned)(rc_report_take(&g, &it) ? it.status : -1), 4u,
       "if this ever reads 1, something started storing a bit the painter cannot honour");
  put(&g, "\033[?3l\033[?3$p");
  eq_u("and ?3l leaves it at 4", (unsigned)(rc_report_take(&g, &it) ? it.status : -1), 4u, "");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?3h");
  eq_u("DECCOLM writes no cell", (unsigned)g.nCells, 0u, "a mode that resized the grid would resize the window");
  eq_u("the grid is still 20 columns wide", (unsigned)g.cols, 20u,
       "the measurement says the only API that changes this also moves the user's window");
  eq_u("and the set still votes the mode bucket", g.nUnsupported[RC_UN_MODE], 1u,
       "the refusal stays counted; the reply is what makes it legible to the app");
  put(&g, "\033[?3l");
  eq_u("the reset votes too", g.nUnsupported[RC_UN_MODE], 2u, "");
  grid_ok(&g, "geo_deccolm");
}

static void geo_inband()
{
  static RcGrid g, h2;
  struct RcReportItem it;

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?2048h");
  eq_u("storing the promise queues nothing", (unsigned)rc_report_pending(&g), 0,
       "the notice is about a change, not about the mode being asked for");
  eq_u("and no cell moved either", (unsigned)g.nCells, 0, "");

  rc_reset_hist(&h2, 20, 6, 18, 0x07);
  eq_u("the notice is taken", rc_notify_geometry(&h2), 1, "a queue with room says so");
  eq_u("exactly one entry", (unsigned)rc_report_pending(&h2), 1,
       "one geometry is one report; a second flush must not repeat it (the seam gates on what it last told)");
  {
    const int kind = rc_report_take(&h2, &it);
    eq_u("the kind is the one 18t answers with", (unsigned)kind, (unsigned)RC_REP_WINOP,
         "no new report kind: one geometry gets one name (I42)");
    eq_u("mode carries the viewport's rows", (unsigned)it.mode, 6,
         "not the model's 24 rows -- a program sizing itself to the gutter would paint off screen");
    eq_u("status carries the model's columns", (unsigned)it.status, 20, "the same pair, the same order");
    eq_u("and the queue is empty again", (unsigned)rc_report_pending(&h2), 0, "");
  }

  rc_reset(&g, 20, 6, 0x07);
  for (int q = 0; q < RC_REPORT_MAX; q++) put(&g, "\033[?2026$p");
  eq_u("a queue full by its own stated depth", (unsigned)rc_report_pending(&g), (unsigned)RC_REPORT_MAX, "");
  eq_u("one more refuses, and the refusal is a return value", rc_notify_geometry(&g), 0,
       "the caller has to be able to tell 'told' from 'no room', or it would write off the notice");
  eq_u("the queue did not evict anything", (unsigned)rc_report_pending(&g), (unsigned)RC_REPORT_MAX, "");
  eq_u("and the refusal left a number", (unsigned)g.nReportFull, 1, "a full queue is a limit, not a leak");
  while (rc_report_pending(&g) > 0) rc_report_take(&g, NULL);
  eq_u("once there is room the same call succeeds", rc_notify_geometry(&g), 1, "");
  eq_u("and nothing was lost by the wait", (unsigned)rc_report_pending(&g), 1, "");
  eq_u("a grid that is not there is refused, not crashed", rc_notify_geometry(NULL), 0, "");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?2048h\033[!p\033[?2048$p");
  eq_u("DECSTR leaves exactly one answer", (unsigned)rc_report_pending(&g), 1,
       "the reset itself speaks in no census");
  rc_report_take(&g, &it);
  eq_u("and it is not-set: DECSTR clears 2048 with the family", (unsigned)it.status, 2, "");
  put(&g, "\033[?2048h\033c\033[?2048$p");
  rc_report_take(&g, &it);
  eq_u("RIS clears it too", (unsigned)it.status, 2, "as at power-up, and power-up sends no reports");
  put(&g, "\033[2048$p");
  eq_u("the unadorned spelling answers nothing", (unsigned)rc_report_pending(&g), 0,
       "only ANSI 4 has a non-private licence, and 2048 is not it");
  eq_u("and it votes as a refused mode", un(&g, RC_UN_MODE), 1, "");
  grid_ok(&g, "geo_inband");
}

static void geo_margins()
{
  static RcGrid g;
  struct RcReportItem it;

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?69h\033[5;16s");
  eq_u("DECLRMM on, then DECSLRM: the pair is stored", (unsigned)g.carried.marginSet, 1, "");
  eq_u("the left margin is column 4 (0-based)", (unsigned)g.carried.leftMargin, 4, "");
  eq_u("the right margin is column 15", (unsigned)g.carried.rightMargin, 15, "");
  eq_u("and a valid pair homes the cursor to the left margin", (unsigned)g.cx, 4,
       "DEC's VT420 rule; MSFT passes homeCursor=true from the `CSI s` arm");
  eq_u("on the first row", (unsigned)g.cy, 0, "");
  eq_u("and nothing in this cost a census vote", g.nUnsupported[RC_UN_MODE], 0,
       "a mode and a sequence that both have bodies must not read as refusals");

  put(&g, "\033[?69$p");
  eq_u("one request, one reply", (unsigned)rc_report_pending(&g), 1, "");
  rc_report_take(&g, &it);
  eq_u("the reply names 69", (unsigned)it.mode, 69, "");
  eq_u("and says it is set", (unsigned)it.status, 1, "");
  put(&g, "\033[?6h");
  eq_u("DECOM is on", (unsigned)g.carried.originMode, 1, "");
  eq_u("and setting it homes the cursor again", (unsigned)g.cx, 4, "MSFT :1794's sentence, in our own words");
  put(&g, "\033[?6$p");
  rc_report_take(&g, &it);
  eq_u("6 answers as a mode the model holds", (unsigned)it.status, 1, "");
  put(&g, "\033[?6l\033[?69l\033[?6$p\033[?69$p");
  eq_u("two requests, two replies", (unsigned)rc_report_pending(&g), 2, "");
  rc_report_take(&g, &it);
  eq_u("6 now answers reset", (unsigned)it.status, 2, "1 and 2 both reach jline4 as SUPPORTED");
  rc_report_take(&g, &it);
  eq_u("and 69 too", (unsigned)it.status, 2, "");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[5;16s");
  eq_u("with the mode off, `CSI 5;16s` sets no margin", (unsigned)g.carried.marginSet, 0,
       "MSFT :2369-2379: `CSI s` is ANSISYSSC when DECSLRM is not allowed");
  eq_u("and a save is not a move", (unsigned)g.cx, 0, "");
  put(&g, "\033[3;9H");
  eq_u("the cursor does go where the next request says", (unsigned)g.cx, 8,
       "without this line the restore below would pass on a grid that never moved");
  eq_u("and to the row it says", (unsigned)g.cy, 2, "");
  put(&g, "\033[u");
  eq_u("and the save-cursor that mode 69 leaves behind is the one that walks back", (unsigned)g.cx, 0, "");
  eq_u("row and all", (unsigned)g.cy, 0, "");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?69h\033[5;16s");
  put(&g, "\033[1;1H");
  eq_u("without origin, row 1 is still the viewport's top", (unsigned)g.cy, 0, "");
  eq_u("and column 1 is clamped INTO the margins, not offset by them", (unsigned)g.cx, 4,
       "MSFT clamps in margins whatever the mode (`:366`); the base is the only thing `?6` moves");
  put(&g, "\033[1;20H");
  eq_u("and a column past the right margin is clamped to it", (unsigned)g.cx, 15, "");
  put(&g, "\033[?6h");
  put(&g, "\033[2;3H");
  eq_u("under origin, row 2 is the second row", (unsigned)g.cy, 1, "");
  eq_u("and column 3 counts from the left margin", (unsigned)g.cx, 6, "4 + 3 - 1");
  put(&g, "\033[99;99H");
  eq_u("a wild row is clamped to the last row", (unsigned)g.cy, 5, "");
  eq_u("and a wild column to the right margin", (unsigned)g.cx, 15, "");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[2;5r\033[?69h\033[5;16s\033[?6h");
  put(&g, "\033[1;1H");
  eq_u("region 2..5 plus origin: row 1 is the region's top", (unsigned)g.cy, 1, "");
  eq_u("and column 1 is the left margin", (unsigned)g.cx, 4, "");
  put(&g, "\033[9;9H");
  eq_u("a row past the region stops at its bottom", (unsigned)g.cy, 4,
       "this is the band that differs from the viewport's, and the reason `?6` needs margins to be a witness");

  put(&g, "\033[1;2H");
  eq_u("the cursor is where the base says it is", (unsigned)g.cx, 5, "");
  eq_u("on the region's top row", (unsigned)g.cy, 1, "");
  put(&g, "\033[?69h\033[16;5s");
  eq_u("an inverted pair is refused", (unsigned)g.carried.marginSet, 1, "the live pair stays");
  eq_u("its left edge is untouched", (unsigned)g.carried.leftMargin, 4, "");
  eq_u("and a refused request teleports no cursor", (unsigned)g.cx, 5, "silent and still, like DECSTBM's arm");
  eq_u("the refusal costs no census vote", g.nUnsupported[RC_UN_MODE], 0,
       "DECSTBM's inverted arm behaves the same way and for the same reason");
  put(&g, "\033[1;20s");
  eq_u("a pair covering the whole page is cleared, not stored", (unsigned)g.carried.marginSet, 0,
       "MSFT: \"Client requests setting margins to the entire screen - clear them instead of setting them\"");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[1;1HABCDEFGHIJKLMNOPQRST");
  put(&g, "\033[?69h\033[5;16s");
  put(&g, "\033[1;7H\033[0K");
  eq_u("EL erases to the right margin", RC_CELLS(&g, 0)[15].ch, ' ', "");
  eq_u("and no further: column 16 keeps its glyph", RC_CELLS(&g, 0)[16].ch, 'Q', "");
  eq_u("the cells left of the cursor survive", RC_CELLS(&g, 0)[5].ch, 'F', "");
  eq_u("and the untouched head of the row is still text", RC_CELLS(&g, 0)[0].ch, 'A',
       "a left margin is not a request to erase what it hides");

  put(&g, "\033[?7l\033[1;15Hxyz");
  eq_u("with wrap off the cursor is pinned at the right margin", (unsigned)g.cx, 15, "");
  eq_u("the last glyph stands on the margin", RC_CELLS(&g, 0)[15].ch, 'z', "");
  eq_u("and nothing was written past it", RC_CELLS(&g, 0)[16].ch, 'Q', "still the original Q");
  put(&g, "\033[?7l\033[1;16H");
  {
    const uint16_t wide = 0x4E00;
    putu(&g, &wide, 1);
    eq_u("with wrap off a wide glyph that does not fit is declined", (unsigned)g.cx, 15, "");
    eq_u("and the margin cell it could not fit is blanked, not left stale", RC_CELLS(&g, 0)[15].ch, ' ',
         "MSFT Row.cpp:474-481 clears the cell it could not fit; the glyph is gone, so the row must not keep"
         " a character the application never sent");
  }
  put(&g, "\033[?7h\033[1;16H");
  {
    const uint16_t wide = 0x4E00;
    putu(&g, &wide, 1);
    eq_u("with wrap on the same glyph takes the next row", (unsigned)g.cy, 1, "");
    eq_u("and stands inside the band, not at column 0", (unsigned)g.cx, 6, "columns 4..5, cursor past them");
    eq_u("whole, with its trailing half where the band says", RC_CELLS(&g, 1)[5].attr & RC_LVB_TRAILING,
         (unsigned)RC_LVB_TRAILING, "");
    eq_u("and the glyph itself landed on the left margin", RC_CELLS(&g, 1)[4].ch, 0x4E00, "");
    eq_u("the narrowed row claims a pad, not a forced wrap", (unsigned)RC_ST(&g, 0).wrap,
         (unsigned)RC_WRAP_PAD, "nothing reached the margin and ran off: the row was declined a glyph");
  }

  put(&g, "\033[?7h");
  put(&g, "\033[1;16Hab");
  eq_u("with wrap on, the row breaks at the margin", (unsigned)g.cy, 1, "the second character opened the next row");
  eq_u("inside the band, not at the page edge", (unsigned)g.cx, 5,
       "'a' hit the margin and claimed the wrap, 'b' was written at column 4 and advanced one");
  eq_u("and the narrow row claims its wrap", (unsigned)RC_ST(&g, 0).wrap, (unsigned)RC_WRAP_FORCED, "");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[1;10H");
  {
    const uint16_t wide = 0x4E00;
    putu(&g, &wide, 1);
  }
  eq_u("setup: the glyph's head is at 9", RC_CELLS(&g, 0)[9].ch, 0x4E00, "");
  eq_u("and its trailing half is at 10", RC_CELLS(&g, 0)[10].attr & RC_LVB_TRAILING,
       (unsigned)RC_LVB_TRAILING, "");
  put(&g, "\033[?69h\033[5;10s");
  eq_u("the narrowing did not eat the glyph outside the band", RC_CELLS(&g, 0)[10].ch, 0x4E00,
       "margins do not erase what they hide -- if this reads blank, DECSLRM grew an erase it was never given");
  eq_u("the head stays a head", RC_CELLS(&g, 0)[9].attr & RC_LVB_LEADING, (unsigned)RC_LVB_LEADING, "");
  eq_u("and DECSLRM homes the cursor onto the band's left edge", (unsigned)g.cx, 4,
       "the first reading of this leg called 4 a bug and the design was right: `CSI s` homes (MSFT's "
       "homeCursor), so a glyph left outside the band is left there by the narrowing, not by a move");
  put(&g, "\033[1;10HX");
  eq_u("the write lands on the band's last column", RC_CELLS(&g, 0)[9].ch, 'X', "");
  eq_u("and the orphan it created is healed", RC_CELLS(&g, 0)[10].attr & RC_LVB_TRAILING, 0u,
       "overwriting a pair's head must blank its tail (#66's rule, now seen from outside the margin)");
  grid_ok(&g, "a margin narrowed under a wide glyph");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?69h\033[5;16s\033[3;9H\033[2L");
  eq_u("IL leaves the row where it was", (unsigned)g.cy, 2, "");
  eq_u("and homes the column to the left margin, not to 0", (unsigned)g.cx, 4, "#64 said `g->cx = 0` until #80");
  put(&g, "\033[2M");
  eq_u("DL agrees with IL about where home is", (unsigned)g.cx, 4, "");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?69h\033[5;16s\033[?6h\033[3;8H\0337");
  eq_u("the saved position is the addressed one", (unsigned)g.cx, 11, "");
  put(&g, "\033[?6l\033[1;1H");
  eq_u("leaving origin walks the cursor to the page's own corner", (unsigned)g.cy, 0, "");
  put(&g, "\0338");
  eq_u("and the restore brings the mode back with it", (unsigned)g.carried.originMode, 1,
       "MSFT stores IsOriginModeRelative with the position (:481) and restores it (:497)");
  eq_u("so the cursor lands where it was saved, not where the new base would put it", (unsigned)g.cx, 11,
       "with origin left off, the same column would be an address into the page instead");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?69h\033[?6h\033[5;16s");
  put(&g, "\033c");
  eq_u("RIS clears the pair", (unsigned)g.carried.marginSet, 0, "");
  eq_u("and DECOM", (unsigned)g.carried.originMode, 0, "");
  eq_u("and DECLRMM", (unsigned)g.carried.declrmm, 0, "");
  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[?69h\033[?6h\033[5;16s\033[!p");
  eq_u("DECSTR clears the pair", (unsigned)g.carried.marginSet, 0,
       "MSFT's SoftReset resets InsertReplace, Origin and AllowDECSLRM in one statement");
  eq_u("and DECOM", (unsigned)g.carried.originMode, 0, "");
  eq_u("and DECLRMM", (unsigned)g.carried.declrmm, 0, "");

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[6h");
  eq_u("the standard spelling sets no origin", (unsigned)g.carried.originMode, 0,
       "`CSI 6 h` is DECSCRM in both references; `?6` is DECOM");

  grid_ok(&g, "geo_margins");
}

static void geo_windowops()
{
  static RcGrid g;
  uint16_t out[RC_TITLE_MAX];

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

  rc_reset(&g, 80, 24, 0x07);
  put(&g, "\033[19t\033[14t\033[16t");
  eq_u("none of the three answers", (unsigned)rc_report_pending(&g), 0,
       "19t would report the same two numbers as 18t under a prefix that promises a second geometry, and "
       "14t/16t have no pixel source here that is not a nominal constant");
  eq_u("and all three are counted", (unsigned)un(&g, RC_UN_REPORT), 3,
       "the count is how a rollout learns whether an application asked");

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

  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]0;\007\033[22;1t\033[23;1t");
  eq_u("an empty OSC 0 is no title, so there is nothing to restore",
       (unsigned)rc_title_pending(&g), 0, "");
  eq_u("and the pop of what it saved refuses once", (unsigned)un(&g, RC_UN_REPORT), 1, "");

  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033]0;AAA\007\033[22;0t");
  put(&g, "\033]0;BBB\007\033[22;0t");
  put(&g, "\033]0;CCC\007\033[22;0t");
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

  rc_reset(&g, 6, 3, 0x07);
  put(&g, "\033[?4hABCDEF");
  eq_text(&g, 0, 6, "ABCDEF", "each glyph opened room for itself until the row was full, and the last one "
                              "reached the margin where there is nothing left to push");
  put(&g, "\033[1;5HZ");
  eq_text(&g, 0, 6, "ABCDZE", "E rode right over F, and F is gone: an insert that kept the row's length kept it");
  put(&g, "\033[1;6HY");
  eq_text(&g, 0, 6, "ABCDZY", "so the write overwrites the last cell instead of inserting zero columns");

  rc_reset(&g, 10, 3, 0x07);
  {
    const uint16_t wide = 0x3042;
    put(&g, "AB");
    putu(&g, &wide, 1);
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

  rc_reset(&g, 20, 3, 0x07);
  put(&g, "ABCDEFGHIJKLMNOP");
  rc_clear_dirty(&g);
  put(&g, "\033[?4h\033[1;5HZ");
  eq_u("an IRM write claims from the cursor", (unsigned)RC_LO(&g, 0), 4, "where its first changed cell is");
  eq_u("to the end of the row", (unsigned)RC_HI(&g, 0), 19, "P moved one column right, so the screen must hear about it");

  rc_reset(&g, 20, 6, 0x07);
  {
    struct RcReportItem it;
    put(&g, "\033[?4$p");
    rc_report_take(&g, &it);
    eq_u("a fresh grid is in replace mode", (unsigned)it.status, 2, "off is a state, not an absence");
    put(&g, "\033[?4h\033[?4$p");
    rc_report_take(&g, &it);
    eq_u("`?4h` is the difference the reply carries", (unsigned)it.status, 1, "");
    put(&g, "\033[4$p");
    rc_report_take(&g, &it);
    eq_u("and the ANSI spelling answers the same question", (unsigned)it.status, 1,
         "the mode was set by that spelling, so a probe using it must not be told the number is unknown");
    eq_u("with nothing left counted", (unsigned)un(&g, RC_UN_MODE), 0,
         "IRM is modelled, so neither `4h` nor `4$p` is a mode this build cannot name");
    put(&g, "\033[2026$p");
    eq_u("while a number with no ANSI registration is still counted", (unsigned)un(&g, RC_UN_MODE), 1,
         "ANSI 2026 does not exist; answering it would be inventing the spelling (the rest of the "
         "non-private field is #87's)");
  }

  rc_reset(&g, 10, 3, 0x07);
  put(&g, "\033[?4hAB");
  put(&g, "\033[1;2H\033c");
  eq_u("RIS is back in replace mode", (unsigned)g.carried.insertMode, 0, "");
  put(&g, "\033[?4h");
  put(&g, "\033[!p");
  eq_u("and so is DECSTR", (unsigned)g.carried.insertMode, 0, "the same list MSFT's SoftReset works through");
  put(&g, "\033[?4h");
  eq_u("the mode is on again for the alt's sake", (unsigned)g.carried.insertMode, 1, "setup");
  put(&g, "\033[?1049h");
  eq_u("entering the alternate screen does not change it", (unsigned)g.carried.insertMode, 1,
       "it is terminal state, like DECAWM and the tab table (I38's ruling on the other axis)");
  put(&g, "\033[?1049l");
  eq_u("and leaving finds it where it was", (unsigned)g.carried.insertMode, 1, "");
}

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

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[31m");
  const unsigned int red = (unsigned)g.attr;
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[38:9:1m\033[31m");
  eq_u("an unknown kind colours nothing", (unsigned)un(&g, RC_UN_COLON), 1,
       "9 is neither 2 nor 5, so the arm is not carried");
  put(&g, "\033[31m");
  eq_u("and the colour that follows still arrives", (unsigned)g.attr, red,
       "the refused arm consumes its own sub-parameters instead of leaking them into the loop");

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[58;5;1m");
  eq_u("`58;5;1` does not set bold", (unsigned)g.sgr.bold, 0,
       "its parameters belong to 58; the old code read `1` as a rendition");
  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033[58:5::14m");
  eq_u("and the colon form of the same thing is parsed, counted and inert", (unsigned)un(&g, RC_UN_COLON), 1,
       "no field exists for an underscore's colour, and inventing one nobody can read is the I26 shape");
  eq_u("with no attribute moved", (unsigned)g.sgr.bold, 0, "");

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
  rc_clear_dirty(&g);
  put(&g, "\033[1;2H\033[2@");
  eq_text(&g, 0, 8, "A  BCD  ", "ICH blanks *at* the cursor and pushes the tail from there right");
  eq_u("ICH leaves the cursor where it was", (unsigned)g.cx, 1, "");
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

  const uint16_t wide = 0x3042;
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
  putu(&g, &wide, 1);
  put(&g, "AB");
  put(&g, "\033[1;3H\033[1@");
  eq_text(&g, 0, 6, "x   AB", "the glyph is destroyed whole and the tail still shifts one column");
  no_orphan(&g, 0, "ICH with the cursor on a trailing half");

  rc_reset(&g, 8, 3, 0x07);
  put(&g, "x");
  putu(&g, &wide, 1);
  put(&g, "AB");
  put(&g, "\033[1;2H\033[1P");
  eq_text(&g, 0, 5, "x AB", "the head goes with the erase and the tail that slid into it goes too");
  no_orphan(&g, 0, "DCH with the cursor on a leading half");

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
  putu(&g, &wide, 1);
  eq_u("the new glyph owns its own two cells", RC_CELLS(&g, 0)[1].attr & RC_LVB_LEADING, RC_LVB_LEADING, "");
  no_orphan(&g, 0, "a wide cell written over a pair");

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

  put(&g, "\033[! q");
  eq_u("an interim of two bytes selects no cursor shape", (unsigned)g.cursorShape, 3,
       "unchanged from the leg above: Pvt would be \"!\", two bytes, and the arm wants length 1");
  eq_u("and the sequence is counted as the unknown final it was", g.nUnsupported[RC_UN_SUP], 3, "");
  put(&g, "\033[          q");
  eq_u("a run of intermediates past the buffer still selects nothing", (unsigned)g.cursorShape, 3,
       "the extras are dropped as they are upstream, where a full Pvt stops appending (:1788)");
  eq_u("and counted once more", g.nUnsupported[RC_UN_SUP], 4, "");

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
    uint16_t w = 0x4E00;
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
    const uint16_t astral[2] = { 0xD83D, 0xDE00 };
    putu(&g, astral, 2);
  }
  const uint16_t hi = RC_CELLS(&g, 0)[0].ch, lo = RC_CELLS(&g, 0)[1].ch;
  put(&g, "\033[1b");
  eq_u("REP of an astral writes the pair again, high half first", RC_CELLS(&g, 0)[2].ch, hi,
       "upstream's m_LastWrittenChar is one wchar_t, so a repeat there is the same half twice");
  eq_u("low half second", RC_CELLS(&g, 0)[3].ch, lo, "");
}

static void putu_wide(RcGrid *g)
{
  const uint16_t u[6] = { 0x4E2D, 0x6587, 'a', 'b' };
  rc_feed(g, u, 4);
  grid_ok(g, "a uint16 feed");
}

static void geo_jline_stream()
{
  static RcGrid g;

  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033(0jklmnqtuvwx\033(Bz");
  const unsigned box[11] = { 0x2518, 0x2510, 0x250C, 0x2514, 0x253C, 0x2500,
                             0x251C, 0x2524, 0x2534, 0x252C, 0x2502 };
  for (int i = 0; i < 11; i++)
    eq_u(S("jline box letter %d draws its glyph", i + 1), RC_CELLS(&g, 0)[i].ch, box[i], "");
  eq_u("and `ESC ( B` closes the set, so the letter after it is text", RC_CELLS(&g, 0)[11].ch, 'z',
       "otherwise a plain 'z' would silently become a greater-or-equal");

  /* Recaptured under the 2026-10-05 caps (aligned with xterm-256color): Display.perform picks the
     single-step cap while cost(single)*n <= cost(multi), so with cub1=^H (1 byte) a 5-column move
     is still CUB (5 > 4) but a 3-column move is now three backspaces where the old \E[D (3 bytes)
     made CUB win at every n >= 2. */
  rc_reset(&g, 32, 3, 0x07);
  put(&g, "select * from dual;");
  put(&g, "\033[5Dv$session\033[4P;\010\010\010");
  eq_text(&g, 0, 26, "select * from v$session;  ", "jline's own redraw lands the line it meant");
  eq_u("with the cursor on the column jline asked for", (unsigned)g.cx, 21, "");
  eq_text(&g, 1, 3, "   ", "and nothing above or below it moved");

  /* the single-step arm itself: backspaces over a wide glyph step off the trailing half, the same
     helper CSI D uses, so an edit walking left through CJK lands where jline's model says it is */
  rc_reset(&g, 32, 3, 0x07);
  putu_wide(&g);
  eq_u("the seed leaves the cursor on column 6", (unsigned)g.cx, 6, "");
  put(&g, "\010\010");
  eq_u("two backspaces land between the glyphs", (unsigned)g.cx, 4, "");
  put(&g, "\010\010");
  eq_u("and two more step off both trailing halves to the margin", (unsigned)g.cx, 0, "");
  put(&g, "XY");
  eq_u("the rewrite overwrites the first glyph", RC_CELLS(&g, 0)[0].ch, 'X', "");
  eq_u("and leaves the second one standing", RC_CELLS(&g, 0)[2].ch, 0x6587, "");
}

static void geo_ftcs()
{
  static RcGrid g;

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

  rc_reset(&g, 20, 4, 0x07);
  put(&g, "\033]133;A\007$ \033]133;B\007ls\r\n");
  eq_u("Enter inside B's input marks the next row a continuation", (unsigned)rc_row_mark(&g, 1),
       RC_PM_CONTINUATION, "a wrapped prompt and an entered one are the same kind of row");
  put(&g, "\033]133;P\007");
  eq_u("a primary prompt overwrites that guess", (unsigned)rc_row_mark(&g, 1), RC_PM_PROMPT, "");

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

  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033[1;31m");
  eq_u("bold red", g.attr & 0x0F, 0x0C, "dark red | FOREGROUND_INTENSITY");
  put(&g, "\033[0;31m");
  eq_u("plain red", g.attr & 0x0F, 0x04, "");
  put(&g, "\033[1;101m");
  eq_u("bold with a bright background", g.attr & 0x0F, 0x04, "brightBack steals the intensity bit");

  rc_reset(&g, 20, 3, 0x07);
  put(&g, "\033[91m");
  eq_u("bright fg 91", g.attr & 0x0F, 0x0C, "red + intensity");
  put(&g, "\033[0;101m");
  eq_u("bright bg 101", g.attr & 0xF0, 0xC0, "");

  rc_reset(&g, 20, 3, 0x8007);
  eq_u("underscore seeded from the default", g.attr, 0x8007, "DisplayParm::Reset seeds colours only");
  put(&g, "\033[0mX");
  eq_u("SGR 0 drops it", g.attr, 0x07, "measured upstream behaviour");
  eq_u("the painted cell uses the cleared attribute", RC_CELLS(&g, 0)[0].attr, 0x07, "");

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

  rc_reset(&g, 20, 6, 0x07);
  put(&g, "\033[1;11HX");
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
  put(&g, "ab");
  eq_span(&g, 0, 19, 19, "only the column the row had room for");
  eq_span(&g, 1, 0, 0, "the wrap put the next glyph on the following row");

  rc_clear_dirty(&g);
  {
    uint16_t w = 0x4E00;
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

  rc_reset_hist(&g, 20, 6, 4, 0x07);
  put(&g, "\033[1;1HTOP");
  eq_u("the setup damaged the viewport's top row", (unsigned)rc_row_dirty(&g, 4), 1u, "TOP painted");
  put(&g, "\033[6;1H\n");
  eq_u("the scroll carried that damage into the gutter", (unsigned)rc_row_dirty(&g, 3), 1u,
       "without a damaged gutter row this leg cannot see the half that must survive");
  eq_u("and the row scrolled in blank is damage", (unsigned)rc_row_dirty(&g, 9), 1u,
       "I22: a change that cannot name its columns says the whole row");
  unsigned dty[10], gutterMask = 0;
  for (int r = 0; r < 10; r++) dty[r] = (unsigned)rc_row_dirty(&g, r);
  for (int r = 0; r < 4; r++) gutterMask |= dty[r] << r;
  rc_adopt_clean(&g);
  for (int r = 4; r < 10; r++) eq_u("an adopt clears a viewport row it read", (unsigned)rc_row_dirty(&g, r), 0u,
       "the read just put the console's own cells there: writing them back is a re-emission, not a repair");
  {
    unsigned after = 0;
    for (int r = 0; r < 4; r++) after |= (unsigned)rc_row_dirty(&g, r) << r;
    eq_u("and leaves every gutter row's damage alone", after, gutterMask,
         "align_grid reads [winT, winT+winRows) and never the scrollback above it");
  }

  put(&g, "\033[4;1Hn");
  unsigned now = 0;
  for (int r = 0; r < 10; r++) now |= (unsigned)rc_row_dirty(&g, r) << r;
  eq_u("a fresh chunk after an adopt damages its own row only", now, (1u << 3) | (1u << 7),
       "row 7 is the new text; row 3 is the gutter damage the adopt was told not to touch");
}

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

static int grid_equal(const RcGrid *a, const RcGrid *b, char *why, size_t n)
{
  if (a->cx != b->cx || a->cy != b->cy)
  {
    snprintf(why, n, "cursor (%d,%d) vs (%d,%d)", a->cx, a->cy, b->cx, b->cy);
    return 0;
  }
  if (a->attr != b->attr) { snprintf(why, n, "attr 0x%04X vs 0x%04X", a->attr, b->attr); return 0; }
  for (int gs = 0; gs < 4; gs++)
    if (a->carried.charset[gs] != b->carried.charset[gs])
    { snprintf(why, n, "charset[%d] %d vs %d", gs, (int)a->carried.charset[gs], (int)b->carried.charset[gs]); return 0; }
  if (a->carried.gshift != b->carried.gshift) { snprintf(why, n, "gshift %d vs %d", (int)a->carried.gshift, (int)b->carried.gshift); return 0; }
  if (a->mode != b->mode) { snprintf(why, n, "mode %d vs %d", a->mode, b->mode); return 0; }
  if (a->nCells != b->nCells) { snprintf(why, n, "nCells %lu vs %lu", a->nCells, b->nCells); return 0; }
  if (a->nAstral != b->nAstral) { snprintf(why, n, "nAstral %lu vs %lu", a->nAstral, b->nAstral); return 0; }
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

static RcView view(int bufW, int bufH, int winL, int winT, int winR, int winB,
                   uint16_t attr, int on, int curX, int curY)
{
  RcView v;
  v.bufW = bufW; v.bufH = bufH;
  v.winL = winL; v.winT = winT; v.winR = winR; v.winB = winB;
  v.attr = attr; v.cursorOn = on; v.curX = curX; v.curY = curY;
  v.curHeight = 0;
  return v;
}

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
  putu(&g, line, 150);
  eq_u("past: the model is at column 150", (unsigned)g.cx, 150, "no wrap before 200");
  rc_plan_paint(&g, &v, &p);
  eq_u("past: paints", (unsigned)p.reason, (unsigned)RC_PLAN_OK, "a window narrower than the row is not a decline");
  eq_u("past: width is the buffer row", (unsigned)p.paintCols, 200, "");
  eq_u("past: clamped to the window's last column", (unsigned)p.curTX, 119, "150 would drag the viewport");
  eq_u("past: the call is still made", (unsigned)p.cursorMoved, 1, "the console is at 0");
  v.curX = 119;
  rc_plan_paint(&g, &v, &p);
  eq_u("past: stable, so it cannot walk the window sideways", (unsigned)p.cursorMoved, 0,
       "curTX 119 == the console's 119");
}

static void plan_scroll_is_free(void)
{
  static RcGrid g; RcPlan p; RcView v;
  rc_reset(&g, 120, 36, 0x07);
  rc_clear_dirty(&g);
  putraw(&g, "\033[36;1HA\r\nB");
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
  rc_plan_paint(&g, &v, &p);
  eq_u("bottom: no slide", (unsigned)p.slideTo, (unsigned)-1, "nowhere left to go");
  eq_u("bottom: buffer scroll", (unsigned)p.bufScroll, 1, "the console moves the cells itself");
  eq_u("bottom: row0", (unsigned)p.row0, 9001 - 36, "the window stays at the bottom");
  eq_u("bottom: fill attribute", (unsigned)p.scrollAttr, 0x07, "the live attribute, as ConEmu does");
  eq_u("bottom: one run", (unsigned)p.nRuns, 1, "");
  eq_u("bottom: cursor needs moving", (unsigned)p.cursorMoved, 1, "its old row means something else now");

  rc_reset(&g, 120, 36, 0x07);
  rc_clear_dirty(&g);
  putraw(&g, "\033[36;1HA\r\nB\r\nC");
  eq_u("straddle: two scrolls", (unsigned)g.pendingScrolls, 2, "");
  view36(&v, 9001 - 37);
  rc_plan_paint(&g, &v, &p);
  eq_u("straddle: slide", (unsigned)p.slideTo, 9000, "one row down puts the window on the last row");
  eq_u("straddle: rest is a buffer scroll", (unsigned)p.bufScroll, 1, "");
  eq_u("straddle: row0", (unsigned)p.row0, 9001 - 36, "ends at the bottom either way");
}

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

  putraw(&g, "\033[36;1HL1\r\nL2\r\nL3");
  eq_u("alt scroll: nothing queued", (unsigned)g.pendingScrolls, 0, "there is no row above the alt to slide into");
  rc_plan_paint(&g, &v, &p);
  eq_u("alt scroll: no slide", (unsigned)p.slideTo, (unsigned)-1, "the window does not move");
  eq_u("alt scroll: no buffer scroll", (unsigned)p.bufScroll, 0, "the buffer does not move either");
  eq_u("alt scroll: the whole screen is the damage", (unsigned)p.run[0].nrows, 36,
       "a row that moved while clean is still a row that changed on screen");
  eq_text(&g, 35, 2, "L3", "the model scrolled, so the repaint carries the new rows");
  eq_text(&g, 33, 2, "L1", "two rows up from where it was written");

  putraw(&g, "\033[?1049l");
  rc_plan_paint(&g, &v, &p);
  eq_u("alt exit: no slide", (unsigned)p.slideTo, (unsigned)-1, "");
  eq_u("alt exit: no buffer scroll", (unsigned)p.bufScroll, 0, "");
  eq_u("alt exit: full viewport run", (unsigned)p.run[0].nrows, 36, "what the alt overwrote goes back");

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
  putraw(&g, "\033[36;1HL1\r\nL2\r\nL3");
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

static void plan_gutter(void)
{
  static RcGrid g; RcPlan p; RcView v;
  rc_reset_hist(&g, 120, 36, 36, 0x07);
  rc_clear_dirty(&g);
  eq_u("gutter: scroll room", (unsigned)rc_scroll_room(&g), 36, "");
  eq_u("gutter: cursor starts on the viewport top", (unsigned)g.cy, 36, "not model row 0");

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

  v = view(120, 36, 0, 0, 119, 35, 0x07, 1, 0, 0);
  rc_plan_paint(&g, &v, &p);
  eq_u("no scrollback: slides nowhere", (unsigned)p.slideTo, (unsigned)-1, "");
  eq_u("no scrollback: buffer scroll", (unsigned)p.bufScroll, 5, "the console moves the cells");
  eq_u("no scrollback: row0", (unsigned)p.row0, (unsigned)-36, "the whole gutter is above the buffer");
  eq_u("no scrollback: the gutter is dropped", (unsigned)p.drop, 5, "one per scroll, as the buffer eats them");
  eq_u("no scrollback: run starts at the window", (unsigned)p.run[0].top, 36, "");
  eq_u("no scrollback: run rows", (unsigned)p.run[0].nrows, 36, "the viewport exactly");
}

static void plan_sgr_stack(void)
{
  static RcGrid g;
  rc_reset_hist(&g, 80, 24, 24, 0x07);

  for (int i = 1; i <= 12; i++)
  {
    char s[32];
    snprintf(s, sizeof s, "\033[%dm\033[#{", i <= 7 ? 30 + i : 33 + i);
    putraw(&g, s);
  }
  eq_u("sgrpush: depth caps at ten", (unsigned)g.carried.sgrDepth, 10, "twelve pushes, ten slots");
  int ok_order = 1;
  for (int i = 12; i >= 3; i--)
  {
    putraw(&g, "\033[#}");
    const int want = i <= 7 ? (int)g.sgr.fg : (int)g.sgr.bg;
    if (want != (i <= 7 ? i : i - 7)) { ok_order = 0; break; }
  }
  eq_u("sgrpush: ring drops the bottom", (unsigned)ok_order, 1,
       "pops hand back 12..3; pushes 1 and 2 were dropped by the ring");
  eq_u("sgrpush: drained", (unsigned)g.carried.sgrDepth, 0, "");

  putraw(&g, "\033[31m");
  const unsigned fg_before = (unsigned)g.sgr.fg;
  putraw(&g, "\033[#}");
  eq_u("sgrpush: empty pop leaves the pen", (unsigned)g.sgr.fg, fg_before, "no change, no crash");
  eq_u("sgrpush: empty pop stays empty", (unsigned)g.carried.sgrDepth, 0, "");

  putraw(&g, "\033[1;35m\033[#{");
  putraw(&g, "\033[m\033c");
  eq_u("sgrpush: RIS empties the pen", (unsigned)g.sgr.bold, 0, "reset rendition");
  eq_u("sgrpush: RIS keeps the stack", (unsigned)g.carried.sgrDepth, 1, "the saved entry survived");
  putraw(&g, "\033[#}");
  eq_u("sgrpush: pop after RIS restores", (unsigned)g.sgr.fg, 5, "magenta was under the reset");
  putraw(&g, "\033[36m\033[#{");
  putraw(&g, "\033[!p");
  eq_u("sgrpush: DECSTR keeps the stack", (unsigned)g.carried.sgrDepth, 1, "");
  putraw(&g, "\033[#}");
  eq_u("sgrpush: pop after DECSTR restores", (unsigned)g.sgr.fg, 6, "");

  putraw(&g, "\033[1;31m");
  putraw(&g, "\033[1#{");
  putraw(&g, "\033[m\033[34m");
  eq_u("sgrpush: parts setup is blue", (unsigned)g.sgr.fg, 4, "");
  eq_u("sgrpush: parts setup lost bold", (unsigned)g.sgr.bold, 0, "");
  putraw(&g, "\033[#}");
  eq_u("sgrpush: part pop restores bold", (unsigned)g.sgr.bold, 1, "the saved part comes back");
  eq_u("sgrpush: part pop keeps colour", (unsigned)g.sgr.fg, 4, "the unsaved part stays as it is");

  putraw(&g, "\033[32m");
  putraw(&g, "\033[5#{");
  putraw(&g, "\033[33m");
  putraw(&g, "\033[#}");
  eq_u("sgrpush: empty push pops to nothing", (unsigned)g.sgr.fg, 3,
       "nothing was saved, so nothing was restored: yellow stays");

  putraw(&g, "\033[3}");
  eq_u("sgrpush: bare } is not a pop", (unsigned)g.carried.sgrDepth, 0, "no stack effect from the unclaimed final");
}

static void plan_xt_modes(void)
{
  static RcGrid g;
  rc_reset_hist(&g, 80, 24, 24, 0x07);

  putraw(&g, "\033[?25h\033[?25s\033[?25l");
  eq_u("xt: setup has the cursor hidden", (unsigned)g.carried.cursorVisible, 0, "");
  putraw(&g, "\033[?25r");
  eq_u("xt: restore re-runs the act", (unsigned)g.carried.cursorVisible, 1, "the saved on came back");

  putraw(&g, "\033[?7r");
  eq_u("xt: never-saved restores off", (unsigned)g.carried.wrapMode, 0, "wrap was on by default and the restore closed it");

  putraw(&g, "\033[?1000h\033[?1000s\033[?1000l\033[?1000s");
  putraw(&g, "\033[?1000h");
  putraw(&g, "\033[?1000r");
  eq_u("xt: one slot, last save wins", (unsigned)(g.carried.mouseModes & 0x0002u), 0,
       "the second save recorded off, so the restore closed the bit the h had opened (bit 1 is ?1000)");

  putraw(&g, "\033[?4h\033[?4s\033[?4l\033c\033[?4h");
  putraw(&g, "\033[?4r");
  eq_u("xt: RIS cleared the table", (unsigned)g.carried.insertMode, 0, "no save survived, so the restore reads off");
  putraw(&g, "\033[?4h\033[?4s\033[?4l\033[!p");
  putraw(&g, "\033[?4r");
  eq_u("xt: DECSTR kept the table", (unsigned)g.carried.insertMode, 1, "the save outlived the soft reset");

  rc_reset_hist(&g, 80, 24, 24, 0x07);
  putraw(&g, "\033[?2026h\033[?2026s\033[?2026r");
  eq_u("xt: 2026 restore counts nested", (unsigned)g.nSyncNested, 1,
       "the second engage through the restore door is named, not absorbed");

  putraw(&g, "\033[2;10r");
  eq_u("xt: fork setup has a region", (unsigned)g.carried.regSet, 1, "");
  putraw(&g, "\033[?r");
  eq_u("xt: bare ?r still resets the region", (unsigned)g.carried.regSet, 0, "the parameterless private form kept DECSTBM");

  putraw(&g, "\033[5;9H\033[25s\033[10;1H\033[u");
  eq_u("xt: plain 25s stayed SCOSC", (unsigned)g.cy, (unsigned)(g.rows - g.winRows + 5 - 1),
       "the restore walked the cursor to the saved model row 5, not to anything about modes");

  rc_reset_hist(&g, 80, 24, 24, 0x07);
  putraw(&g, "\033[2;10r");
  putraw(&g, "\033[?9999r");
  eq_u("xt: unknown id leaves the region alone", (unsigned)g.carried.regSet, 1,
       "`? 9999 r` is a counted refusal, not a nonsense margin");
}

static void plan_rect_family(void)
{
  static RcGrid g;
  rc_reset_hist(&g, 40, 6, 6, 0x07);

  putraw(&g, "AB\r\nCD\r\nEF\r\n");
  putraw(&g, "\033[2;3$z");
  eq_u("rect: DECERA row 1 untouched", (unsigned)RC_CELLS(&g, 6)[0].ch, 'A', "");
  eq_u("rect: DECERA inside cell untouched", (unsigned)RC_CELLS(&g, 7)[1].ch, 'D', "");
  eq_u("rect: DECERA cleared the named cell", (unsigned)RC_CELLS(&g, 7)[2].ch, ' ', "row 2 col 3");
  eq_u("rect: DECERA cleared to the page edge", (unsigned)RC_CELLS(&g, 9)[1].ch, ' ',
       "row 4 col 2 by the b=0 default");

  putraw(&g, "\033[9;2;3;4$z");
  eq_u("rect: inverted rect does nothing", (unsigned)RC_CELLS(&g, 6)[0].ch, 'A', "");

  putraw(&g, "\033[31m\033[2;1;2;6;35$x");
  eq_u("fra: the character", (unsigned)RC_CELLS(&g, 7)[0].ch, '#', "35 is #");
  eq_u("fra: the pen's colour", (unsigned)RC_CELLS(&g, 7)[0].attr, 0x04, "red pen filled the rect");
  eq_u("fra: outside the rect keeps the old text", (unsigned)RC_CELLS(&g, 6)[0].ch, 'A', "row 1");
  putraw(&g, "\033[9;1;9;40;31$x");
  eq_u("fra: out-of-range character paints nothing", (unsigned)RC_CELLS(&g, 6)[0].ch, 'A',
       "the cell kept its text");

  rc_reset_hist(&g, 40, 6, 6, 0x07);
  putraw(&g, "\033[1\"qP\033[2\"qQ");
  eq_u("sca: the protected write carries the bit", (unsigned)RC_PROT(&g, 6)[0], 1, "the P");
  eq_u("sca: 2 clears the pen", (unsigned)RC_PROT(&g, 6)[1], 0, "the Q");
  putraw(&g, "\033[1;1;1;1;9$z");
  eq_u("era: non-selective clears protection", (unsigned)RC_PROT(&g, 6)[0], 0,
       "DECERA has no respect for the bit");

  rc_reset_hist(&g, 40, 6, 6, 0x07);
  putraw(&g, "\033[31mA\033[1\"qB\033[2\"q\033[mC\r\nXY");
  putraw(&g, "\033[?2J");
  eq_u("sed: unprotected text goes", (unsigned)RC_CELLS(&g, 6)[0].ch, ' ', "the A");
  eq_u("sed: protected text stays", (unsigned)RC_CELLS(&g, 6)[1].ch, 'B', "the B");
  eq_u("sed: unprotected text keeps its colour", (unsigned)RC_CELLS(&g, 6)[0].attr, 0x04, "the red");
  eq_u("sed: the row below went too", (unsigned)RC_CELLS(&g, 7)[0].ch, ' ', "the X");

  putraw(&g, "\033[1;1H\033[1\"qZZ\033[2\"qW");
  putraw(&g, "\033[1;3H\033[?K");
  eq_u("sel: unprotected W goes", (unsigned)RC_CELLS(&g, 6)[2].ch, ' ', "");
  eq_u("sel: protected ZZ stays", (unsigned)RC_CELLS(&g, 6)[0].ch, 'Z', "");

  rc_reset_hist(&g, 40, 6, 6, 0x07);
  putraw(&g, "KEEP\r\nGONE\r\n");
  putraw(&g, "\033[2;1H\033[?J");
  eq_u("sed: no protection, ?0J is ED 0", (unsigned)RC_CELLS(&g, 7)[0].ch, ' ',
       "the selective half met its twin");

  rc_reset_hist(&g, 40, 6, 6, 0x07);
  putraw(&g, "A\033[1\"qB\033[2\"qCD");
  putraw(&g, "\033[1;2;1;3${");
  eq_u("sera: the protected inside stays", (unsigned)RC_CELLS(&g, 6)[1].ch, 'B', "the B");
  eq_u("sera: the unprotected inside goes", (unsigned)RC_CELLS(&g, 6)[2].ch, ' ', "the C");
  eq_u("sera: outside stays", (unsigned)RC_CELLS(&g, 6)[3].ch, 'D', "the D");

  rc_reset_hist(&g, 40, 6, 6, 0x07);
  putraw(&g, "ABCDEF\r\n");
  putraw(&g, "\033[1;1;1;5;1;1;2$v");
  eq_text(&g, 6, 7, "AABCDE ", "deccra right onto itself: the backwards walk did not eat the source");

  rc_reset_hist(&g, 40, 6, 6, 0x07);
  putraw(&g, "ABCDEF\r\n");
  putraw(&g, "\033[1;2;1;6;1;1;1$v");
  eq_text(&g, 6, 7, "BCDEFF ", "deccra left onto itself: forwards, and the copy landed whole");

  rc_reset_hist(&g, 40, 6, 6, 0x07);
  RC_CELLS(&g, 6)[0].ch = 0x4E2D; RC_CELLS(&g, 6)[0].attr = 0x07 | RC_LVB_LEADING;
  RC_CELLS(&g, 6)[1].ch = 0x4E2D; RC_CELLS(&g, 6)[1].attr = 0x07 | RC_LVB_TRAILING;
  RC_CELLS(&g, 6)[2].ch = 'X';   RC_CELLS(&g, 6)[2].attr = 0x07;
  putraw(&g, "\033[1;2;1;2$z");
  eq_u("pair: the fill healed the orphan's front", (unsigned)RC_CELLS(&g, 6)[0].attr, 0x07u,
       "no leading half claims a cell whose back the fill took");
  eq_u("pair: and its glyph went with it", (unsigned)RC_CELLS(&g, 6)[0].ch, ' ',
       "an orphaned half is blanked, not left as a lone half");

  rc_reset_hist(&g, 40, 6, 6, 0x07);
  putraw(&g, "abcdef\r\n");
  putraw(&g, "\033[1;3H\033[2}");
  eq_text(&g, 6, 7, "ab  cdef", "decic opened two blanks at the cursor");
  putraw(&g, "\033[1;3H\033[2~");
  eq_text(&g, 6, 7, "abcdef  ", "decdc closed them, the tail walked off the row");

  putraw(&g, "\033[2;6r\033[1;1H\033[3}");
  eq_text(&g, 6, 7, "abcdef  ", "decic refused: the cursor row is outside the region");

  putraw(&g, "\033[1\"q\033[!p");
  eq_u("reset: DECSTR clears the pen", (unsigned)g.carried.penProt, 0, "");
}

static void adopt_anchor(void)
{
  eq_u("adopt: unclaimed follows the window",
       (unsigned)rc_anchor_adopt(0, 0, 0, 0, 1, 0, 29, 400, 60, 30), (unsigned)(-30), "winT - gutter");

  eq_u("adopt: a resize keeps a claim the view never touched",
       (unsigned)rc_anchor_adopt(1, 340, 60, 29, 1, 0, 23, 400, 48, 24), (unsigned)352, "376..399, out of sight");

  eq_u("adopt: the view sweeping down over the content takes it",
       (unsigned)rc_anchor_adopt(1, 171, 60, 29, 1, 221, 250, 400, 60, 30), (unsigned)191,
       "the claim ended at 230, the window now ends at 250");
  eq_u("adopt: and sweeping up does too",
       (unsigned)rc_anchor_adopt(1, 340, 60, 399, 1, 310, 339, 400, 60, 30), (unsigned)280,
       "the user dragged the view back up to the content");
  eq_u("adopt: a view that reaches the anchor keeps it",
       (unsigned)rc_anchor_adopt(1, 340, 60, 29, 1, 370, 399, 400, 60, 30), (unsigned)340, "");

  eq_u("adopt: a claim too high for the new window is dropped",
       (unsigned)rc_anchor_adopt(1, -49, 60, 129, 1, 100, 129, 400, 60, 30), (unsigned)70,
       "the anchor ended at row 10, below the new viewport's own height");

  eq_u("adopt: a claim below the buffer is dropped",
       (unsigned)rc_anchor_adopt(1, 380, 60, 399, 1, 0, 29, 400, 60, 30), (unsigned)(-30),
       "it ended at 439 of a 400-row buffer");

  eq_u("adopt: a window grown away from the claim still carries it",
       (unsigned)rc_anchor_adopt(1, 340, 60, 29, 1, 0, 39, 400, 80, 40), (unsigned)320,
       "not winT - gutter == -40");

  eq_u("adopt: a scroll is not a resize",
       (unsigned)rc_anchor_adopt(1, 171, 60, 29, 0, 221, 250, 400, 60, 30), (unsigned)171,
       "the window's bottom passed the anchor, but nothing was resized");
}

static void plan_anchor(void)
{
  static RcGrid g; RcPlan p; RcView v;

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

  rc_reset(&g, 120, 36, 0x07);
  rc_clear_dirty(&g);
  putraw(&g, "\033[36;1HA\r\nB");
  view36(&v, 20);
  rc_plan_paint(&g, &v, &p);
  eq_u("unclaimed: the window is the anchor", (unsigned)p.row0, 21, "winT+slide, as it has always been");
  eq_u("unclaimed: and it slides", (unsigned)p.slideTo, 56, "the first paint defines where the model lives");
  eq_u("unclaimed: cursor moved", (unsigned)p.cursorMoved, 1, "it is inside the window the plan just chose");

  rc_reset(&g, 120, 36, 0x07);
  rc_clear_dirty(&g);
  rc_set_base(&g, 100);
  putraw(&g, "LOW");
  view36(&v, 120);
  rc_plan_paint(&g, &v, &p);
  eq_u("ahead of the anchor: paints", (unsigned)p.reason, (unsigned)RC_PLAN_OK, "");
  eq_u("ahead of the anchor: row0 follows the view", (unsigned)p.row0, 120, "never pulled back to 100");
  eq_u("ahead of the anchor: the slide is on the table again", (unsigned)p.cursorOffView, 0, "");

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

  rc_drop_base(&g);
  eq_u("dropped: the viewport goes dirty", (unsigned)rc_row_dirty(&g, 35), 1, "the promise is a repaint, not silence");
  rc_plan_paint(&g, &v, &p);
  eq_u("dropped: re-derived from the window", (unsigned)p.row0, 8965, "the same answer the unclaimed model gives");
}

static void plan_scroll_band(void)
{
  static RcGrid g; RcPlan p; RcView v;
  int top = -1, bottom = -1, n;

  rc_reset_hist(&g, 200, 30, 30, 0x07);
  rc_clear_dirty(&g);
  rc_set_base(&g, 340);
  putraw(&g, "\033[30;1HA\r\n");
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

  rc_reset_hist(&g, 200, 30, 30, 0x07);
  rc_clear_dirty(&g);
  rc_set_base(&g, 200);
  putraw(&g, "\033[30;1HA\r\n");
  for (int i = 0; i < 4; i++) putraw(&g, "B\r\n");
  v = view(200, 400, 0, 100, 99, 129, 0x07, 1, 0, 129);
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

  memset(&p, 0, sizeof p);
  p.row0 = 300; p.slideRows = 0; p.bufScroll = 60;
  n = rc_scroll_band(&p, 60, 400, &top, &bottom);
  eq_u("whole: nothing to move", (unsigned)n, 0, "an empty source is a no-op, not a failed call");

  memset(&p, 0, sizeof p);
  p.row0 = 340; p.slideRows = 0; p.bufScroll = 60;
  n = rc_scroll_band(&p, 60, 400, &top, &bottom);
  eq_u("whole: on a full buffer the eviction is still owed", (unsigned)n, 340,
       S("%d..%d ride up by 60, the top 60 leave", top, bottom));
  eq_u("whole: and it lands on row 0", (unsigned)(top - p.bufScroll), 0, "");

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

static int g_fires, g_fireBadRoom, g_fireUncovered;
static unsigned long g_paintLines;

static void hook_watch(void *ctx)
{
  RcGrid *g = (RcGrid *)ctx;
  RcView v; RcPlan p;
  g_fires++;
  if (g->pendingScrolls != rc_scroll_room(g)) g_fireBadRoom++;
  view36(&v, 48);
  rc_plan_paint(g, &v, &p);
  g_fireUncovered += p.drop;
  for (int r = 0; r < g->rows; r++)
  {
    if (!rc_row_dirty(g, r)) continue;
    int in = 0;
    for (int i = 0; i < p.nRuns; i++)
      if (r >= p.run[i].top && r < p.run[i].top + p.run[i].nrows) { in = 1; break; }
    if (!in) g_fireUncovered++;
  }
  for (int i = 0; i < p.nRuns; i++)
    for (int r = p.run[i].top; r < p.run[i].top + p.run[i].nrows; r++)
      if (RC_CELLS(g, r)[0].ch >= '0' && RC_CELLS(g, r)[0].ch <= '9') g_paintLines++;
  rc_paint_done(g);
}

static void plan_gutter_hook(void)
{
  static RcGrid g;
  rc_reset_hist(&g, 120, 36, 4, 0x07);
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

static void plan_damage_range(void)
{
  static RcGrid g; RcPlan p; RcView v;

  rc_reset(&g, 2000, 36, 0x07);
  putraw(&g, "\033[1;1501HX");
  v = view(2000, 9001, 0, 100, 119, 135, 0x07, 1, 0, 100);
  rc_plan_paint(&g, &v, &p);
  eq_u("wide: paints", (unsigned)p.reason, (unsigned)RC_PLAN_OK, "a 2000-column model row is still the model (I7)");
  eq_u("wide: the row is still 2000 cells", (unsigned)p.paintCols, 2000, "the geometry test is untouched by B2");
  eq_u("wide: one run", (unsigned)p.nRuns, 1, "");
  eq_u("wide: run left", (unsigned)p.run[0].lo, 1500, "the rectangle starts where the damage is");
  eq_u("wide: run right", (unsigned)p.run[0].hi, 1500, "");
  eq_u("wide: one cell moved, not a row", (unsigned long)p.cells, 1ul, "this is what B2 buys");

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

  rc_reset(&g, 120, 36, 0x07);
  rc_clear_dirty(&g);
  putraw(&g, "\033[1;11Ha\033[2;91Hb");
  view36(&v, 0);
  rc_plan_paint(&g, &v, &p);
  eq_u("merged: one run", (unsigned)p.nRuns, 1, "rows 0 and 1 are neighbours");
  eq_u("merged: union left", (unsigned)p.run[0].lo, 10, "");
  eq_u("merged: union right", (unsigned)p.run[0].hi, 90, "");
  eq_u("merged: cells", (unsigned long)p.cells, 2ul * 81ul, "81 columns twice, not the buffer row twice");

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

  view36(&v, 0); v.winR = 99;
  rc_plan_paint(&g, &v, &p);
  eq_u("narrower window: paints", (unsigned)p.reason, (unsigned)RC_PLAN_OK,
       "the model row is the buffer row, and neither moved");

  view36(&v, 0); v.winL = 20;
  rc_plan_paint(&g, &v, &p);
  eq_u("h-scroll: declines", (unsigned)p.reason, (unsigned)RC_PLAN_NOGEOM, "the model is 120 wide, the row is 100");

  view36(&v, 0); v.winB = 34;
  rc_plan_paint(&g, &v, &p);
  eq_u("shorter window: declines", (unsigned)p.reason, (unsigned)RC_PLAN_NOGEOM, "winRows is 36");

  view36(&v, 0); v.bufW = 2000;
  rc_plan_paint(&g, &v, &p);
  eq_u("wide buffer: declines", (unsigned)p.reason, (unsigned)RC_PLAN_NOGEOM,
       "the buffer row is 2000, the model was built for 120");
  eq_u("wide buffer: paints nothing", (unsigned)p.paintCols, 0, "");

  rc_reset(&g, 120, 36, 0x07);
  putraw(&g, "\033[10;10H");
  view36(&v, 0); v.curX = 0; v.curY = 0;
  rc_plan_paint(&g, &v, &p);
  eq_u("cursor only: nothing to paint", (unsigned)p.reason, (unsigned)RC_PLAN_EMPTY, "");
  eq_u("cursor only: no runs", (unsigned)p.nRuns, 0, "");
  eq_u("cursor only: still moves the cursor", (unsigned)p.cursorMoved, 1, "");
  eq_u("cursor only: target", (unsigned)p.curTY, 9, "model row 9 at winT 0");

  putraw(&g, "\033[3;3H");
  view36(&v, 0); v.curX = 2; v.curY = 2;
  rc_plan_paint(&g, &v, &p);
  eq_u("already there: no cursor call", (unsigned)p.cursorMoved, 0, "");

  view36(&v, 0); v.attr = 0x30;
  rc_plan_paint(&g, &v, &p);
  eq_u("attribute drift is noticed", (unsigned)p.attrChanged, 1, "chunk must write it back");
  view36(&v, 0); v.cursorOn = 0;
  rc_plan_paint(&g, &v, &p);
  eq_u("hidden cursor while ?25h is in effect", (unsigned)p.setVisible, 1, "");

  rc_reset(&g, 120, 36, 0x07);
  putraw(&g, "x");
  v = view(160, 9001, 40, 0, 159, 35, 0x07, 1, 40, 0);
  rc_plan_paint(&g, &v, &p);
  eq_u("h-scroll: reason", (unsigned)p.reason, (unsigned)RC_PLAN_OK, "");
  eq_u("h-scroll: width", (unsigned)p.paintCols, 120, "160 - 40");
  eq_u("h-scroll: starts at the window's left", (unsigned)(p.run[0].top), 0, "rect Left is v.winL");
  eq_u("h-scroll: cursor x", (unsigned)p.curTX, 41, "winL + model column 1");
}

static void plan_snap(void)
{
  static RcGrid g; RcView v; int row = -1, col = -1;

  rc_reset_hist(&g, 200, 30, 30, 0x07);
  rc_clear_dirty(&g);
  rc_set_base(&g, 340);
  putraw(&g, "\033[30;1HP");
  eq_u("snap: the cursor is on the model's last row", (unsigned)g.cy, 59,
       "CSI r H addresses the viewport, never the gutter (Render.cpp::clxy), so 30 of 30 lands on row 59");
  eq_u("snap: and the claim puts it on the buffer's last", (unsigned)(g.baseRow + g.cy), 399, "setup");

  v = view(200, 400, 0, 0, 199, 29, 0x07, 1, 0, 0);
  eq_u("snap: off the view the user moved", (unsigned)rc_snap_view(&g, &v, &row, &col),
       (unsigned)RC_SNAP_PARK, "");
  eq_u("snap: aims at the cursor's own row", (unsigned)row, 399,
       "not the buffer's bottom, not the window's: the row the model's cursor sits on, and conhost slides to it");
  eq_u("snap: and at its column", (unsigned)col, (unsigned)g.cx, "the window starts at column 0 here");

  v = view(200, 400, 0, 370, 199, 399, 0x07, 1, 0, 399);
  eq_u("snap: already looking at it", (unsigned)rc_snap_view(&g, &v, &row, &col),
       (unsigned)RC_SNAP_NOCHANGE, "the common case, and the one that must cost nothing");
  eq_u("snap: so no row is named", (unsigned)row, (unsigned)-1, "a PARK is the only answer that names one");

  putraw(&g, "\033[1;1H");
  eq_u("snap: the cursor is now on the viewport's first row", (unsigned)g.cy, 30, "setup");
  v = view(200, 410, 0, 375, 199, 404, 0x07, 1, 0, 400);
  eq_u("snap: a view below the prompt is the same defect", (unsigned)rc_snap_view(&g, &v, &row, &col),
       (unsigned)RC_SNAP_PARK, "");
  eq_u("snap: and the park is upward, onto the claimed row", (unsigned)row, 370, S("got %d", row));

  putraw(&g, "\033[?25l");
  v = view(200, 410, 0, 0, 199, 29, 0x07, 1, 0, 0);
  eq_u("snap: an invisible cursor is not made visible by a key",
       (unsigned)rc_snap_view(&g, &v, &row, &col), (unsigned)RC_SNAP_NOCHANGE, "");
  putraw(&g, "\033[?25h");
  eq_u("snap: and the same view snaps once the cursor is back",
       (unsigned)rc_snap_view(&g, &v, &row, &col), (unsigned)RC_SNAP_PARK, "the guard was the flag alone");

  while (g.cx < 150) putraw(&g, "z");
  eq_u("snap: setup walked the column past the window", (unsigned)(g.cx > 99), 1, "setup");
  v = view(200, 400, 0, 0, 99, 29, 0x07, 1, 0, 0);
  eq_u("snap: sideways is out of scope", (unsigned)rc_snap_view(&g, &v, &row, &col),
       (unsigned)RC_SNAP_PARK, "");
  eq_u("snap: so the column is clamped into the window", (unsigned)col, 99, S("got %d", col));
  eq_u("snap: and the row still is the model's", (unsigned)row, 370, S("got %d", row));

  rc_set_base(&g, 340);
  rc_drop_base(&g);
  v = view(200, 400, 0, 0, 199, 29, 0x07, 1, 0, 0);
  eq_u("snap: no claim, no snap", (unsigned)rc_snap_view(&g, &v, &row, &col), (unsigned)RC_SNAP_NOCHANGE,
       "the window is the only truth an unanchored model has, and it is the user's");
  rc_set_base(&g, 900);
  eq_u("snap: a claim off the buffer is not chased",
       (unsigned)rc_snap_view(&g, &v, &row, &col), (unsigned)RC_SNAP_NOCHANGE,
       "parking a cursor at a row the buffer does not have is a failed call, not a view");

  rc_set_base(&g, 340);
  v = view(200, 400, 0, 0, 199, 24, 0x07, 1, 0, 0);
  eq_u("snap: a shorter window is a resize, not a snap",
       (unsigned)rc_snap_view(&g, &v, &row, &col), (unsigned)RC_SNAP_NOGEOM, "");
  v = view(320, 400, 0, 0, 319, 29, 0x07, 1, 0, 0);
  eq_u("snap: a wider row neither", (unsigned)rc_snap_view(&g, &v, &row, &col),
       (unsigned)RC_SNAP_NOGEOM, "cols is bufW - winL, rule 1's own test");

  eq_u("snap: the claim outlives it unchanged", (unsigned)g.baseRow, 340, "");
  eq_u("snap: and no scroll debt was spent on it", (unsigned)g.pendingScrolls, 0, "");
}

static void plan_cursor_shape(void)
{
  static RcGrid g; RcPlan p; RcView v;
  static const int styles[] = { -1, 0, 1, 2, 3, 4, 5, 6 };
  static const char *const names[] =
  {
    "nothing asked", "the default", "steady block(1)", "steady block(2)",
    "blinking block", "steady underline", "steady bar(5)", "blinking bar(6)"
  };
  static const int heights[] = { 0, 15, 100, 100, 15, 15, 15, 15 };
  char seq[16];
  const int nstyles = (int)(sizeof styles / sizeof styles[0]);
  int was, back, k, st, bar;

  was = rc_cursor_shape_api(0);
  eq_u("#88 default: the planner starts out without the shape API", (unsigned)was, 0u,
       "a non-zero default would ask every Win7 console, and every leg written before #88, the new question");

  for (k = 0; k < nstyles; k++)
  {
    st = styles[k];
    rc_reset(&g, 120, 36, 0x07);
    putraw(&g, "hello");
    if (st >= 0) { snprintf(seq, sizeof seq, "\033[%d q", st); putraw(&g, seq); }
    view36(&v, 0);
    v.curHeight = 100;
    rc_plan_paint(&g, &v, &p);
    eq_u(S("absent: %s opens no shape door", names[k]), (unsigned)p.setStyle, 0u,
         S("setStyle=%d, and 0 is the only answer this build gave before #88", p.setStyle));
    eq_u(S("absent: %s names no shape word", names[k]), (unsigned)p.shapeStyle, (unsigned)-1,
         S("shapeStyle=%d: -1 means nobody chose a door", p.shapeStyle));
    eq_u(S("absent: %s still folds to the height it always had", names[k]), (unsigned)p.shapeHeight,
         (unsigned)heights[k], S("want %d, cursor_height()'s untouched table", heights[k]));
    eq_u(S("absent: %s goes out the height door", names[k]), (unsigned)p.setShape,
         (unsigned)((st >= 0 && heights[k] > 0 && heights[k] != 100) ? 1 : 0),
         S("the console reads 100, the parameter wants %d", heights[k]));
  }

  back = rc_cursor_shape_api(1);
  eq_u("#88 flip: the seam hands back the answer it replaced", (unsigned)back, (unsigned)was,
       "Paint.cpp:91 returns the previous value precisely so a leg (or a re-open) can restore it");

  for (k = 0; k < nstyles; k++)
  {
    st = styles[k];
    bar = (st == 5 || st == 6);
    rc_reset(&g, 120, 36, 0x07);
    putraw(&g, "hello");
    if (st >= 0) { snprintf(seq, sizeof seq, "\033[%d q", st); putraw(&g, seq); }
    view36(&v, 0);
    v.curHeight = 100;
    rc_plan_paint(&g, &v, &p);
    eq_u(S("present: %s goes out the shape door", names[k]), (unsigned)p.setStyle, bar ? 1u : 0u,
         S("setStyle=%d", p.setStyle));
    eq_u(S("present: %s carries one shape word, no modifier bits", names[k]), (unsigned)p.shapeStyle,
         (unsigned)(bar ? RC_CURSOR_STYLE_VERTICAL_BAR : -1),
         S("shapeStyle=%d; 2 is wincon.h's CONSOLE_CURSOR_STYLE_VERTICAL_BAR", p.shapeStyle));
    eq_u(S("present: %s never opens both doors at once", names[k]), (unsigned)p.setShape,
         (unsigned)(bar ? 0 : ((st >= 0 && heights[k] > 0 && heights[k] != 100) ? 1 : 0)),
         S("setShape=%d against setStyle=%d -- one cursor, one owner", p.setShape, p.setStyle));
  }

  rc_reset(&g, 120, 36, 0x07);
  putraw(&g, "hello");
  putraw(&g, "\033[5 q");
  view36(&v, 0);
  rc_plan_paint(&g, &v, &p);
  eq_u("present, nothing measured: 5 is said with the bar anyway", (unsigned)p.setStyle, 1u,
       "the second door exists so a bar does not wait on a height nobody read");
  eq_u("present, nothing measured: and the height door stays shut", (unsigned)p.setShape, 0u,
       "no SetConsoleCursorInfo call is owed when the console's height is unknown");
  rc_reset(&g, 120, 36, 0x07);
  putraw(&g, "hello");
  putraw(&g, "\033[2 q");
  view36(&v, 0);
  rc_plan_paint(&g, &v, &p);
  eq_u("present, nothing measured: a block asks for neither door", (unsigned)p.setStyle, 0u,
       "0..4 keep the story #87 shipped, including this one");

  eq_u("unit: 5 asks for nothing where the API is absent", (unsigned)rc_cursor_style_for(5, 0), (unsigned)-1, "");
  eq_u("unit: 6 asks for nothing where the API is absent", (unsigned)rc_cursor_style_for(6, 0), (unsigned)-1, "");
  for (k = 0; k < nstyles; k++)
  {
    st = styles[k];
    bar = (st == 5 || st == 6);
    eq_u(S("unit: %s means the vertical bar where the API is present", names[k]),
         (unsigned)rc_cursor_style_for(st, 1), (unsigned)(bar ? RC_CURSOR_STYLE_VERTICAL_BAR : -1),
         "the whole decision, in one row per parameter");
  }

  back = rc_cursor_shape_api(was);
  eq_u("#88 restore: the flag goes back to the answer it had", (unsigned)back, 1u,
       "if this reads 0 the flip above never landed, and the present arm proved nothing");
  rc_reset(&g, 120, 36, 0x07);
  putraw(&g, "hello");
  putraw(&g, "\033[5 q");
  view36(&v, 0);
  v.curHeight = 100;
  rc_plan_paint(&g, &v, &p);
  eq_u("#88 restore: and 5 folds to a height again", (unsigned)p.setStyle, 0u,
       S("setShape=%d after the restore, which is the -37 answer", p.setShape));
  eq_u("#88 restore: the height door reopens for it", (unsigned)p.setShape, 1u, "15 into a console at 100");
}

static void check_damage_bounds(void)
{
  static RcGrid g;
  const int cols = 20, winRows = 6;
  const int hists[2] = { 0, 6 };
  for (int i = 0; i < g_ncorpus; i++)
  {
    for (int s = 0; s < 2; s++)
    {
      const int hist = hists[s];
      rc_reset_hist(&g, cols, winRows, hist, 0x07);
      putraw(&g, g_corpus[i]);
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
  gm_inputreports();
  geo_gaps();
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
  rebuild_consequences();
  status_bar();
  geo_takeover();
  geo_decrpm_unmodelled();
  geo_mousemodes();
  geo_ckm();
  geo_deccolm();
  geo_oracle_teeth();
  geo_inband();
  geo_margins();
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
  plan_cursor_shape();
  plan_sgr_stack();
  plan_xt_modes();
  plan_rect_family();
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

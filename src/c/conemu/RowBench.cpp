/* RowBench.cpp -- #75's "先量单价": what does one model scroll cost, measured on this machine, at the
 * shapes production actually takes?
 *
 * The claim under test is that `scroll_up()` moves the whole model on every line feed that reaches the
 * bottom of the viewport, so the price of printing a screenful is (rows-1) row copies per line -- while a
 * row-pointer rotation would move one pointer per row instead. Whether that is worth an ABI-shaped
 * refactor is a measurement, not an argument, so this file measures:
 *
 *   T_scroll  a stream of lines that scrolls every line (steady state, after a warmup)
 *   T_nosc    the SAME cell writes with no line feed at all (CUP back to one row) -- the baseline that
 *             everything except the scroll costs
 *   T_memcpy  the raw row-to-row copies a scroll performs, with none of the parser around them
 *   T_rotate  the rotation's own cost: moving `rows-1` indexes instead of `rows-1` rows
 *
 * (T_scroll - T_nosc) / scrolls is the unit price the model really pays, bookkeeping included; T_memcpy
 * says how much of that is the byte movement and T_rotate says what the replacement would cost.
 *
 * Console-free on purpose: rc_feed is the whole cost centre, and the painter's console calls are the same
 * in either design. Built by bench.sh, which is deliberately not the gate -- a measurement has no pass
 * condition and must not be able to break one:
 *   bash src/c/conemu/bench.sh --bench   # the table DESIGN.md section 5 publishes
 */
#include <cstdio>
#include <cstring>
#include <ctime>
#include <vector>

#include "Render.h"

static double now_ns()
{
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

/* The model the seam builds: a window of `winRows` and a gutter equal to it, capped by RC_MAX_ROWS.
 * Kept in a struct because a stack RcGrid is 4 MB and the host gate's rule is `static` for the same
 * reason (RenderCheck.cpp's own note). */
static RcGrid g;

static void build(int cols, int winRows)
{
  int hist = winRows;
  if (winRows + hist > RC_MAX_ROWS) hist = RC_MAX_ROWS - winRows;
  rc_reset_hist(&g, cols, winRows, hist, 0x07);
}

/* Feed `lines` lines of `w` characters each, ending every line with CR LF: the steady state where each
 * line feed lands on the viewport's bottom row and scrolls. */
static double feed_scroll(int cols, int w, int lines, unsigned long *scrolls)
{
  std::vector<uint16_t> buf;
  buf.push_back('\r');
  for (int i = 0; i < w; i++) buf.push_back((uint16_t)'a' + (i % 26));
  buf.push_back('\n');
  const unsigned long before = g.nScrolls;
  double t0 = now_ns();
  for (int i = 0; i < lines; i++) rc_feed(&g, buf.data(), (int)buf.size());
  double t1 = now_ns();
  *scrolls = g.nScrolls - before;
  return t1 - t0;
}

/* The same writes with no line feed: every line lands on one row, so nothing rotates. The parser cost,
 * the per-cell cost and the dirty bookkeeping are all here; only the scroll is missing. */
static double feed_noscroll(int cols, int w, int lines, unsigned long *scrolls)
{
  std::vector<uint16_t> buf;
  char cup[24];
  int n = snprintf(cup, sizeof cup, "\033[%d;1H", g.rows);   /* the model's last row */
  for (int i = 0; i < n; i++) buf.push_back((uint16_t)(unsigned char)cup[i]);
  for (int i = 0; i < w; i++) buf.push_back((uint16_t)'a' + (i % 26));
  const unsigned long before = g.nScrolls;
  double t0 = now_ns();
  for (int i = 0; i < lines; i++) rc_feed(&g, buf.data(), (int)buf.size());
  double t1 = now_ns();
  *scrolls = g.nScrolls - before;
  return t1 - t0;
}

/* The scroll's own byte movement, with nothing else: `scrolls` rounds of (rows-1) row copies. */
static double raw_memcpy(unsigned long scrolls, int cols)
{
  const size_t rowBytes = (size_t)cols * sizeof(RcCell);
  double t0 = now_ns();
  for (unsigned long i = 0; i < scrolls; i++)
    for (int r = 0; r + 1 < g.rows; r++)
      memcpy(&g.cells[r], &g.cells[r + 1], rowBytes);
  double t1 = now_ns();
  return t1 - t0;
}

/* What the replacement pays for the same number of moves: one index per row, rotated. */
static int idx[RC_MAX_ROWS];
static double raw_rotate(unsigned long scrolls)
{
  double t0 = now_ns();
  for (unsigned long i = 0; i < scrolls; i++)
  {
    for (int r = 0; r + 1 < g.rows; r++) idx[r] = idx[r + 1];
    idx[g.rows - 1] = 0;    /* the recycled row: a rotation hands the writer the oldest row's storage */
  }
  double t1 = now_ns();
  return t1 - t0;
}

int main()
{
  struct Shape { int cols; int winRows; int w; } shapes[] = {
    /* The two ends of the real range: an 80-column shell window with a short prompt, and the profile this
       machine's conhost defaults to (a 2000-column buffer), with the report widths dbcli prints. */
    {   80,  30,   80 },
    {   80,  30,   20 },
    {  120,  36,  120 },
    {  200,  50,  200 },
    {  200,  50,   40 },
    { 1000,  50, 1000 },
    { 2000,  50, 2000 },
    { 2000,  50,   60 },     /* a wide buffer holding a narrow report: the shape that makes this cheap */
    { 2000, 128,  120 },
    { 2000, 128, 2000 },
  };

  printf("%6s %6s %6s %6s %6s | %9s %9s %9s %9s %9s | %8s\n",
         "cols", "rows", "win", "w", "scr", "ns/lf", "ns/nosc", "ns/scr*", "ns/copy", "ns/rot", "MB/scr");
  for (unsigned s = 0; s < sizeof shapes / sizeof shapes[0]; s++)
  {
    const int cols = shapes[s].cols, win = shapes[s].winRows, w = shapes[s].w;
    build(cols, win);
    const int lines = 4000;

    /* warmup: get the cursor to the viewport's bottom so every measured line feeds scrolls */
    unsigned long junk;
    (void)feed_scroll(cols, w, g.rows + 2, &junk);

    unsigned long sc = 0, sc2 = 0;
    double ts = feed_scroll(cols, w, lines, &sc);
    build(cols, win);
    (void)feed_noscroll(cols, w, g.rows + 2, &junk);
    double tn = feed_noscroll(cols, w, lines, &sc2);
    build(cols, win);
    double tm = raw_memcpy(sc ? sc : 1, cols);
    double tr = raw_rotate(sc ? sc : 1);

    /* scr* is the price the model pays per scroll, measured as the difference between the two feeds and
       divided by the scrolls the first one actually performed -- a line that fills the row wraps, so a
       line can feed two scrolls and `lines` is not the divisor. */
    const double perLf = ts / lines, perNosc = tn / lines;
    const double perScr = sc ? (ts - tn) / sc : 0.0;
    const double perCopy = sc ? tm / sc : 0.0, perRot = sc ? tr / sc : 0.0;
    const double mb = (double)(g.rows - 1) * cols * sizeof(RcCell) / (1024.0 * 1024.0);
    printf("%6d %6d %6d %6d %6lu | %9.0f %9.0f %9.0f %9.0f %9.0f | %8.3f\n",
           cols, g.rows, win, w, sc, perLf, perNosc, perScr, perCopy, perRot, mb);
  }
  return 0;
}

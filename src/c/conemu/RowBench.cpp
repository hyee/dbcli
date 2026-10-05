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

static RcGrid g;

static void build(int cols, int winRows)
{
  int hist = winRows;
  if (winRows + hist > RC_MAX_ROWS) hist = RC_MAX_ROWS - winRows;
  rc_reset_hist(&g, cols, winRows, hist, 0x07);
}

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

static double feed_noscroll(int cols, int w, int lines, unsigned long *scrolls)
{
  std::vector<uint16_t> buf;
  char cup[24];
  int n = snprintf(cup, sizeof cup, "\033[%d;1H", g.rows);
  for (int i = 0; i < n; i++) buf.push_back((uint16_t)(unsigned char)cup[i]);
  for (int i = 0; i < w; i++) buf.push_back((uint16_t)'a' + (i % 26));
  const unsigned long before = g.nScrolls;
  double t0 = now_ns();
  for (int i = 0; i < lines; i++) rc_feed(&g, buf.data(), (int)buf.size());
  double t1 = now_ns();
  *scrolls = g.nScrolls - before;
  return t1 - t0;
}

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

static int idx[RC_MAX_ROWS];
static double raw_rotate(unsigned long scrolls)
{
  double t0 = now_ns();
  for (unsigned long i = 0; i < scrolls; i++)
  {
    for (int r = 0; r + 1 < g.rows; r++) idx[r] = idx[r + 1];
    idx[g.rows - 1] = 0;
  }
  double t1 = now_ns();
  return t1 - t0;
}

int main()
{
  struct Shape { int cols; int winRows; int w; } shapes[] = {
    {   80,  30,   80 },
    {   80,  30,   20 },
    {  120,  36,  120 },
    {  200,  50,  200 },
    {  200,  50,   40 },
    { 1000,  50, 1000 },
    { 2000,  50, 2000 },
    { 2000,  50,   60 },
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

    const double perLf = ts / lines, perNosc = tn / lines;
    const double perScr = sc ? (ts - tn) / sc : 0.0;
    const double perCopy = sc ? tm / sc : 0.0, perRot = sc ? tr / sc : 0.0;
    const double mb = (double)(g.rows - 1) * cols * sizeof(RcCell) / (1024.0 * 1024.0);
    printf("%6d %6d %6d %6d %6lu | %9.0f %9.0f %9.0f %9.0f %9.0f | %8.3f\n",
           cols, g.rows, win, w, sc, perLf, perNosc, perScr, perCopy, perRot, mb);
  }
  return 0;
}

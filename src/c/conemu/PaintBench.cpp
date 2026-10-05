#include <windows.h>
#include <algorithm>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static LARGE_INTEGER s_freq;

static double usec_since(LARGE_INTEGER a)
{
  LARGE_INTEGER b;
  QueryPerformanceCounter(&b);
  return (double)(b.QuadPart - a.QuadPart) * 1e6 / (double)s_freq.QuadPart;
}

static void prepareConsole(void)
{
  HANDLE std_out = GetStdHandle(STD_OUTPUT_HANDLE);
  if (GetFileType(std_out) == FILE_TYPE_PIPE)
  {
    FreeConsole();
    if (!AllocConsole()) { printf("AllocConsole failed (%lu)\n", (unsigned long)GetLastError()); exit(2); }
    HWND hwnd = GetConsoleWindow();
    if (hwnd) ShowWindow(hwnd, SW_HIDE);
  }
}

static HANDLE openCon(void)
{
  return CreateFileW(L"CONOUT$", GENERIC_READ | GENERIC_WRITE,
                     FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
}

static BOOL setGeometry(HANDLE con, int bufW, int bufH, int winW, int winH)
{
  COORD size;
  size.X = (SHORT)bufW;
  size.Y = (SHORT)bufH;
  SetConsoleScreenBufferSize(con, size);
  SMALL_RECT wr;
  wr.Left = 0;
  wr.Top = 0;
  wr.Right = (SHORT)(winW - 1);
  wr.Bottom = (SHORT)(winH - 1);
  BOOL ok = SetConsoleWindowInfo(con, TRUE, &wr);
  size.X = 0; size.Y = 0;
  SetConsoleCursorPosition(con, size);
  return ok;
}

struct Stat
{
  double min, med, max;
};

static Stat measure(const char *label, int reps, BOOL (*fn)(void *), void *ctx)
{
  double *t = (double *)malloc((size_t)reps * sizeof *t);
  for (int i = 0; i < 5; i++) fn(ctx);
  for (int i = 0; i < reps; i++)
  {
    LARGE_INTEGER a;
    QueryPerformanceCounter(&a);
    fn(ctx);
    t[i] = usec_since(a);
  }
  std::sort(t, t + reps);
  Stat s;
  s.min = t[0];
  s.med = t[reps / 2];
  s.max = t[reps - 1];
  free(t);
  if (label) printf("%-46s min %8.1f us  med %8.1f us  max %8.1f us\n", label, s.min, s.med, s.max);
  return s;
}

struct Rect
{
  HANDLE con;
  CHAR_INFO *cells;
  SMALL_RECT area;
  COORD bufSize;
  COORD src;
  int cols, rows;
};

static BOOL f_writeRect(void *p)
{
  Rect *r = (Rect *)p;
  return WriteConsoleOutputW(r->con, r->cells, r->bufSize, r->src, &r->area);
}

struct Read
{
  HANDLE con;
};

static BOOL f_readView(void *p)
{
  Read *r = (Read *)p;
  CONSOLE_SCREEN_BUFFER_INFO csbi;
  CONSOLE_CURSOR_INFO ci;
  GetConsoleScreenBufferInfo(r->con, &csbi);
  GetConsoleCursorInfo(r->con, &ci);
  return TRUE;
}

struct Park
{
  HANDLE con;
  COORD where;
};

static BOOL f_park(void *p)
{
  Park *k = (Park *)p;
  return SetConsoleCursorPosition(k->con, k->where);
}

struct Scroll
{
  HANDLE con;
  COORD dest;
};

struct Attr
{
  HANDLE con;
};

static BOOL f_attr(void *p)
{
  Attr *a = (Attr *)p;
  return SetConsoleTextAttribute(a->con, 0x07);
}

static BOOL f_scroll(void *p)
{
  Scroll *s = (Scroll *)p;
  CONSOLE_SCREEN_BUFFER_INFO csbi;
  CHAR_INFO fill;
  if (!GetConsoleScreenBufferInfo(s->con, &csbi)) return FALSE;
  SMALL_RECT whole;
  whole.Left = 0;
  whole.Top = 0;
  whole.Right = csbi.dwSize.X - 1;
  whole.Bottom = csbi.dwSize.Y - 1;
  memset(&fill, 0, sizeof fill);
  fill.Attributes = csbi.wAttributes;
  fill.Char.UnicodeChar = ' ';
  return ScrollConsoleScreenBufferW(s->con, &whole, NULL, s->dest, &fill);
}

typedef struct BenchCell { unsigned short ch, attr; } BenchCell;

static CHAR_INFO *g_scratch;
static BenchCell *g_grid;

static BOOL f_buildRows(void *p)
{
  int *a = (int *)p;
  const int cols = a[0], rows = a[1], pc = a[2];
  for (int r = 0; r < rows; r++)
  {
    CHAR_INFO *dst = g_scratch + (size_t)r * pc;
    const BenchCell *src = g_grid + (size_t)r * cols;
    int c;
    for (c = 0; c < cols; c++)
    {
      dst[c].Attributes = src[c].attr;
      dst[c].Char.UnicodeChar = src[c].ch;
    }
    const unsigned short tail = src[cols - 1].attr;
    for (; c < pc; c++)
    {
      dst[c].Attributes = tail;
      dst[c].Char.UnicodeChar = ' ';
    }
  }
  return TRUE;
}

int main(void)
{
  QueryPerformanceFrequency(&s_freq);
  prepareConsole();
  {
    LARGE_INTEGER a;
    Sleep(20);
    QueryPerformanceCounter(&a);
    Sleep(20);
    printf("clock: %ld Hz; a 20 ms Sleep measures %.0f us\n", (long)s_freq.QuadPart, usec_since(a));
  }
  HANDLE con = openCon();
  if (con == INVALID_HANDLE_VALUE) { printf("no CONOUT$ (%lu)\n", (unsigned long)GetLastError()); return 2; }

  const int REPS = 200;
  const int WIN_W = 100, WIN_H = 30;
  const int COLS_AT = 4096;
  g_scratch = (CHAR_INFO *)malloc((size_t)COLS_AT * 40 * sizeof(CHAR_INFO));
  g_grid = (BenchCell *)malloc((size_t)COLS_AT * 40 * sizeof(BenchCell));
  for (size_t i = 0; i < (size_t)COLS_AT * 40; i++)
  {
    g_grid[i].ch = 'A';
    g_grid[i].attr = 0x07;
  }

  printf("=== per-flush fixed cost (window 100x30, buffer 200 wide) ===\n");
  setGeometry(con, 200, 200, WIN_W, WIN_H);
  Read rd = { con };
  measure("read view (screen buffer info + cursor info)", REPS, f_readView, &rd);
  Park pk = { con, { 0, 5 } };
  measure("park cursor (a viewport slide is made of this)", REPS, f_park, &pk);
  Attr at = { con };
  measure("SetConsoleTextAttribute", REPS, f_attr, &at);
  Scroll sc = { con, { 0, -1 } };
  measure("scroll buffer by 1 row", REPS, f_scroll, &sc);
  printf("     -> Paint.h calls a slide free; this last line is the one call it avoids per scroll.\n");

  printf("\n=== WriteConsoleOutputW vs width (rule I7 paints to the BUFFER edge) ===\n");
  printf("%-8s %-6s %10s %12s %14s\n", "bufW", "rows", "med us", "ns/cell", "cells");
  const int widths[] = { 100, 120, 200, 600, 1200, 2000, 3000, 4096 };
  const int rowcnt[] = { 1, 8, 30 };
  for (int wi = 0; wi < (int)(sizeof widths / sizeof *widths); wi++)
  {
    const int bw = widths[wi];
    int winW = bw < WIN_W ? bw : WIN_W;
    if (!setGeometry(con, bw, 200, winW, WIN_H))
    {
      printf("bufW=%d refused (%lu)\n", bw, (unsigned long)GetLastError());
      continue;
    }
    for (int ri = 0; ri < (int)(sizeof rowcnt / sizeof *rowcnt); ri++)
    {
      const int rows = rowcnt[ri];
      const int cols = bw;
      if (cols > COLS_AT) continue;
      Rect rr;
      rr.con = con;
      rr.cells = g_scratch;
      rr.bufSize.X = (SHORT)cols;
      rr.bufSize.Y = (SHORT)rows;
      rr.src.X = 0;
      rr.src.Y = 0;
      rr.area.Left = 0;
      rr.area.Top = 0;
      rr.area.Right = (SHORT)(cols - 1);
      rr.area.Bottom = (SHORT)(rows - 1);
      rr.cols = cols;
      rr.rows = rows;
      Stat s = measure(NULL, REPS, f_writeRect, &rr);
      char label[32];
      snprintf(label, sizeof label, "bufW=%d rows=%d", bw, rows);
      printf("%-8d %-6d %10.1f %12.2f %14d   %s\n", cols, rows, s.med,
             s.med * 1000.0 / ((double)cols * rows), cols * rows, label);
    }
  }

  printf("\n=== our own staging cost (build_row, no console call) ===\n");
  int arg[3];
  const int stage[][3] = { { 100, 30, 120 }, { 100, 30, 200 }, { 100, 30, 2000 }, { 100, 30, 4096 } };
  for (int i = 0; i < (int)(sizeof stage / sizeof *stage); i++)
  {
    arg[0] = stage[i][0];
    arg[1] = stage[i][1];
    arg[2] = stage[i][2];
    Stat s = measure(NULL, REPS * 2, f_buildRows, arg);
    printf("cols=%4d rows=%2d paintCols=%4d: med %7.1f us  %6.2f ns/cell\n",
           arg[0], arg[1], arg[2], s.med, s.med * 1000.0 / ((double)arg[2] * arg[1]));
  }

  CloseHandle(con);
  return 0;
}

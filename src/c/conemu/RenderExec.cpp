/* RenderExec.cpp -- the console executor: reads the console's shape, applies the plan,
   injects replies, owns the handle lifecycle. No Java_* export lives here. */

#include "RenderExec.h"
#include <jni.h>
#include <windows.h>
#include <stdlib.h>
#include <string.h>
#include "Paint.h"
#include "Render.h"

int console_window_is_pty(void)
{
  static const wchar_t PSEUDO[] = L"PseudoConsoleWindow";
  HWND w = GetConsoleWindow();
  if (!w) return 0;
  wchar_t name[32];
  const int n = GetClassNameW(w, name, (int)(sizeof name / sizeof name[0]));
  if (n != (int)(sizeof PSEUDO / sizeof PSEUDO[0]) - 1) return 0;
  for (int i = 0; i < n; i++)
  {
    wchar_t a = name[i], b = PSEUDO[i];
    if (a >= L'A' && a <= L'Z') a = (wchar_t)(a - L'A' + L'a');
    if (b >= L'A' && b <= L'Z') b = (wchar_t)(b - L'A' + L'a');
    if (a != b) return 0;
  }
  return 1;
}

int clip_apply(const wchar_t *wide, int chars, DWORD *why)
{
  if (!OpenClipboard(NULL)) { *why = GetLastError(); return RC_CLIP_OPEN; }
  if (!EmptyClipboard()) { *why = GetLastError(); CloseClipboard(); return RC_CLIP_EMPTY; }
  if (chars > 0)
  {
    const SIZE_T bytes = (SIZE_T)(chars + 1) * sizeof(wchar_t);
    HGLOBAL hg = GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (!hg) { *why = GetLastError(); CloseClipboard(); return RC_CLIP_ALLOC; }
    void *p = GlobalLock(hg);
    if (p) memcpy(p, wide, bytes);
    GlobalUnlock(hg);
    if (!p || !SetClipboardData(CF_UNICODETEXT, hg))
    {
      *why = GetLastError();
      GlobalFree(hg);
      CloseClipboard();
      return RC_CLIP_SET;
    }
  }
  CloseClipboard();
  return RC_CLIP_OK;
}

int view_of(HANDLE con, RcView *v, CONSOLE_SCREEN_BUFFER_INFO *csbi)
{
  if (!GetConsoleScreenBufferInfo(con, csbi)) return 0;
  v->bufW = csbi->dwSize.X;
  v->bufH = csbi->dwSize.Y;
  v->winL = csbi->srWindow.Left;
  v->winT = csbi->srWindow.Top;
  v->winR = csbi->srWindow.Right;
  v->winB = csbi->srWindow.Bottom;
  v->attr = (uint16_t)csbi->wAttributes;
  v->curX = csbi->dwCursorPosition.X;
  v->curY = csbi->dwCursorPosition.Y;
  {
    CONSOLE_CURSOR_INFO ci;
    memset(&ci, 0, sizeof ci);
    const BOOL ok = GetConsoleCursorInfo(con, &ci);
    v->cursorOn = ok ? (ci.bVisible ? 1 : 0) : -1;
    v->curHeight = ok ? ci.dwSize : -1;
  }
  return 1;
}

void build_row(const RcGrid *g, int row, int lo, int hi, CHAR_INFO *dst)
{
  const RcCell *src = RC_CELLS(g, row);
  for (int c = lo; c <= hi; c++)
  {
    dst[c - lo].Attributes = src[c].attr;
    CH_UNICODE(dst[c - lo]) = src[c].ch;
  }
}

LONG write_rect(HANDLE con, const RcView *v, const RcPlan *p, int top, int nrows,
                       int lo, int hi, const CHAR_INFO *cells)
{
  COORD size, coord;
  SMALL_RECT rect;
  size.X = (SHORT)(hi - lo + 1);
  size.Y = (SHORT)nrows;
  coord.X = 0;
  coord.Y = 0;
  rect.Left = (SHORT)(v->winL + lo);
  rect.Right = (SHORT)(v->winL + hi);
  rect.Top = (SHORT)(p->row0 + top);
  rect.Bottom = (SHORT)(p->row0 + top + nrows - 1);
  SetLastError(0);
  return WriteConsoleOutputW(con, cells, size, coord, &rect) ? 0L : (LONG)GetLastError();
}

LONG scroll_region(HANDLE con, const RcView *v, const RcPlan *p, int modelRows,
                          int by, uint16_t attr)
{
  CHAR_INFO fill;
  COORD dest;
  SMALL_RECT src;
  int top, bottom;
  if (!rc_scroll_band(p, modelRows, v->bufH, &top, &bottom)) return 0L;
  memset(&fill, 0, sizeof fill);
  fill.Attributes = attr;
  CH_UNICODE(fill) = ' ';
  dest.X = v->winL;
  dest.Y = (SHORT)(top - by);
  src.Left = (SHORT)v->winL;
  src.Top = (SHORT)top;
  src.Right = (SHORT)(v->winL + p->paintCols - 1);
  src.Bottom = (SHORT)bottom;
  SetLastError(0);
  return ScrollConsoleScreenBufferW(con, &src, NULL, dest, &fill) ? 0L : (LONG)GetLastError();
}

LONG park_cursor(HANDLE con, int x, int y)
{
  COORD c;
  c.X = (SHORT)x;
  c.Y = (SHORT)y;
  SetLastError(0);
  return SetConsoleCursorPosition(con, c) ? 0L : (LONG)GetLastError();
}

static void w_lit(wchar_t *b, int *n, int cap, const char *s)
{
  for (; *s && *n + 1 < cap; s++) b[(*n)++] = (wchar_t)(unsigned char)*s;
}

static void w_dec(wchar_t *b, int *n, int cap, int v)
{
  char t[12];
  if (v < 0) v = 0;
  snprintf(t, sizeof t, "%d", v);
  w_lit(b, n, cap, t);
}

static void w_hex4(wchar_t *b, int *n, int cap, unsigned v)
{
  char t[8];
  snprintf(t, sizeof t, "%04x", v & 0xFFFFu);
  w_lit(b, n, cap, t);
}

int reply_text(int kind, const RcGrid *g, const RcView *v, const RcPlan *p,
                      const struct RcReportItem *it, wchar_t *out, int cap)
{
  int n = 0;
  switch (kind)
  {
    case RC_REP_DSR:
      w_lit(out, &n, cap, "\x1b[0n");
      break;
    case RC_REP_CPR:
    {
      int row = p->row0 + it->y - p->winTop + 1;
      if (row < 1) row = 1;
      if (row > g->winRows) row = g->winRows;
      w_lit(out, &n, cap, "\x1b[");
      w_dec(out, &n, cap, row);
      w_lit(out, &n, cap, ";");
      w_dec(out, &n, cap, it->x + 1);
      w_lit(out, &n, cap, "R");
      break;
    }
    case RC_REP_DECRPM:
      w_lit(out, &n, cap, "\x1b[?");
      w_dec(out, &n, cap, it->mode);
      w_lit(out, &n, cap, ";");
      w_dec(out, &n, cap, it->status);
      w_lit(out, &n, cap, "$y");
      break;
    case RC_REP_WINOP:
      w_lit(out, &n, cap, "\x1b[8;");
      w_dec(out, &n, cap, (int)it->mode);
      w_lit(out, &n, cap, ";");
      w_dec(out, &n, cap, (int)it->status);
      w_lit(out, &n, cap, "t");
      break;
    case RC_REP_OSC:
    {
      const uint32_t c = it->status;
      w_lit(out, &n, cap, "\x1b]");
      w_dec(out, &n, cap, (int)it->mode);
      if (it->mode == 4) { w_lit(out, &n, cap, ";"); w_dec(out, &n, cap, it->y); }
      w_lit(out, &n, cap, ";rgb:");
      w_hex4(out, &n, cap, (c & 0xFFu) * 0x0101u);
      w_lit(out, &n, cap, "/");
      w_hex4(out, &n, cap, ((c >> 8) & 0xFFu) * 0x0101u);
      w_lit(out, &n, cap, "/");
      w_hex4(out, &n, cap, ((c >> 16) & 0xFFu) * 0x0101u);
      w_lit(out, &n, cap, "\x1b\\");
      break;
    }
    case RC_REP_TITLE:
    {
      if (g->carried.nTitle <= 0) return 0;
      const int keep = cap - 4;
      int c = g->carried.nTitle < keep ? g->carried.nTitle : keep;
      w_lit(out, &n, cap, "\x1b]l");
      for (int i = 0; i < c; i++) if (n < cap - 3) out[n++] = (wchar_t)g->carried.title[i];
      w_lit(out, &n, cap, "\x1b\\");
      break;
    }
    case RC_REP_XTVER:
      w_lit(out, &n, cap, "\x1bP>|");
      w_lit(out, &n, cap, RENDER_BUILD);
      w_lit(out, &n, cap, "\x1b\\");
      break;
    case RC_REP_DA:
      w_lit(out, &n, cap, "\x1b[?61;4;6;7;14;21;22;23;24;28;32;42c");
      break;
    case RC_REP_DA2:
      w_lit(out, &n, cap, "\x1b[>0;10;1c");
      break;
    default:
      break;
  }
  (void)v;
  out[n] = 0;
  return n;
}

int write_input_units(RcHandle *h, const wchar_t *txt, int n)
{
  INPUT_RECORD rec[160];
  int nrec = 0;
  const int room = (int)(sizeof rec / sizeof rec[0]);
  for (int i = 0; i < n && nrec + 2 <= room; i++)
  {
    rec[nrec].EventType = KEY_EVENT;
    rec[nrec].Event.KeyEvent.bKeyDown = TRUE;
    rec[nrec].Event.KeyEvent.wRepeatCount = 1;
    rec[nrec].Event.KeyEvent.wVirtualKeyCode = 0;
    rec[nrec].Event.KeyEvent.wVirtualScanCode = 0;
    rec[nrec].Event.KeyEvent.uChar.UnicodeChar = txt[i];
    rec[nrec].Event.KeyEvent.dwControlKeyState = 0;
    rec[nrec + 1] = rec[nrec];
    rec[nrec + 1].Event.KeyEvent.bKeyDown = FALSE;
    nrec += 2;
  }
  DWORD written = 0;
  return WriteConsoleInputW(h->in, rec, (DWORD)nrec, &written) && written == (DWORD)nrec;
}

void flush_reports(RcHandle *h, const RcView *v, const RcPlan *p)
{
  RcGrid *g = h->g;
  if (g->carried.inbandResize && (g->winRows != h->repRows || g->cols != h->repCols) && rc_notify_geometry(g))
  {
    h->repRows = g->winRows;
    h->repCols = g->cols;
  }
  while (rc_report_pending(g) > 0)
  {
    struct RcReportItem it;
    const int kind = rc_report_take(g, &it);
    wchar_t txt[RC_TITLE_MAX + 32];
    const int n = reply_text(kind, g, v, p, &it, txt, (int)(sizeof txt / sizeof txt[0]));
    if (n <= 0) { rc_report_result(g, 0); continue; }
    if (h->in == INVALID_HANDLE_VALUE)
      h->in = CreateFileW(L"CONIN$", GENERIC_READ | GENERIC_WRITE,
                          FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
    if (h->in == INVALID_HANDLE_VALUE)
    {
      snprintf(h->lastError, sizeof h->lastError, "reply: no CONIN$ (%lu)", (unsigned long)GetLastError());
      h->nApiErrors++;
      rc_report_result(g, 0);
      while (rc_report_pending(g) > 0) { rc_report_take(g, NULL); rc_report_result(g, 0); }
      return;
    }
    const int ok = write_input_units(h, txt, n);
    rc_report_result(g, ok);
    if (!ok)
    {
      snprintf(h->lastError, sizeof h->lastError, "reply=%lu", (unsigned long)GetLastError());
      h->nApiErrors++;
    }
  }
}

int apply_palette(RcHandle *h, const uint32_t *src, uint16_t mask,
                         const CONSOLE_SCREEN_BUFFER_INFO *keep)
{
  CONSOLE_SCREEN_BUFFER_INFOEX ex;
  memset(&ex, 0, sizeof ex);
  ex.cbSize = sizeof ex;
  if (!GetConsoleScreenBufferInfoEx(h->con, &ex)) { h->nApiErrors++; return 0; }
  if (!h->palSaved)
  {
    for (int i = 0; i < 16; i++) h->palOrig[i] = (uint32_t)ex.ColorTable[i];
    h->palSaved = 1;
  }
  for (int i = 0; i < 16; i++)
    if (mask & (uint16_t)(1u << i)) ex.ColorTable[i] = (COLORREF)src[i];
  if (!SetConsoleScreenBufferInfoEx(h->con, &ex))
  {
    snprintf(h->lastError, sizeof h->lastError, "palette=%lu", (unsigned long)GetLastError());
    h->nApiErrors++;
    return 0;
  }
  CONSOLE_SCREEN_BUFFER_INFO now;
  if (GetConsoleScreenBufferInfo(h->con, &now)
      && (now.srWindow.Left != keep->srWindow.Left || now.srWindow.Top != keep->srWindow.Top
          || now.srWindow.Right != keep->srWindow.Right || now.srWindow.Bottom != keep->srWindow.Bottom
          || now.dwSize.X != keep->dwSize.X || now.dwSize.Y != keep->dwSize.Y))
  {
    COORD want;
    want.X = keep->dwSize.X;
    want.Y = keep->dwSize.Y;
    if (want.X != now.dwSize.X || want.Y != now.dwSize.Y) SetConsoleScreenBufferSize(h->con, want);
    SetConsoleWindowInfo(h->con, TRUE, &keep->srWindow);
    CONSOLE_SCREEN_BUFFER_INFO again;
    if (!GetConsoleScreenBufferInfo(h->con, &again)
        || again.srWindow.Bottom != keep->srWindow.Bottom || again.dwSize.Y != keep->dwSize.Y)
    {
      snprintf(h->lastError, sizeof h->lastError, "palette-geometry=%lu", (unsigned long)GetLastError());
      h->nApiErrors++;
    }
  }
  return 1;
}

#define RC_IN_MOUSE        0x0010
#define RC_IN_QUICK_EDIT   0x0040
#define RC_IN_EXTENDED     0x0080
#define RC_OUT_VTP         0x0004

int sync_mouse(RcHandle *h, int on)
{
  if (on == h->inArmed) return 1;
  if (h->in == INVALID_HANDLE_VALUE)
    h->in = CreateFileW(L"CONIN$", GENERIC_READ | GENERIC_WRITE,
                        FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
  if (h->in == INVALID_HANDLE_VALUE)
  {
    snprintf(h->lastError, sizeof h->lastError, "mouse: no CONIN$ (%lu)", (unsigned long)GetLastError());
    h->nApiErrors++;
    return 0;
  }
  if (!h->inSaved)
  {
    if (!GetConsoleMode(h->in, &h->inBase))
    {
      snprintf(h->lastError, sizeof h->lastError, "mouse: mode? (%lu)", (unsigned long)GetLastError());
      h->nApiErrors++;
      return 0;
    }
    h->inSaved = 1;
  }
  if (on == h->inArmed) return 1;
  const DWORD want = on ? ((h->inBase | RC_IN_MOUSE | RC_IN_EXTENDED) & ~(DWORD)RC_IN_QUICK_EDIT)
                        : h->inBase;
  if (!SetConsoleMode(h->in, want))
  {
    snprintf(h->lastError, sizeof h->lastError, "mouse: set 0x%lx (%lu)", (unsigned long)want,
             (unsigned long)GetLastError());
    h->nApiErrors++;
    return 0;
  }
  h->inArmed = on;
  return 1;
}

int claim_output(RcHandle *h, int on)
{
  if (h->con == INVALID_HANDLE_VALUE) return 0;
  if (!h->outSaved)
  {
    if (!GetConsoleMode(h->con, &h->outBase))
    {
      snprintf(h->lastError, sizeof h->lastError, "vtp: mode? (%lu)", (unsigned long)GetLastError());
      h->nApiErrors++;
      return 0;
    }
    h->outSaved = 1;
  }
  if (on == h->outClaimed) return 1;
  const DWORD want = on ? (h->outBase & ~(DWORD)RC_OUT_VTP) : h->outBase;
  if (!SetConsoleMode(h->con, want))
  {
    snprintf(h->lastError, sizeof h->lastError, "vtp: set 0x%lx (%lu)", (unsigned long)want,
             (unsigned long)GetLastError());
    h->nApiErrors++;
    return 0;
  }
  h->outClaimed = on;
  return 1;
}

void sync_region_host(RcHandle *h);

int paint_flush(RcHandle *h)
{
  RcGrid *g = h->g;
  RcView v;
  RcPlan p;
  CONSOLE_SCREEN_BUFFER_INFO csbi;

#define DECLINE(code) do { h->nDeclines++; \
                           if (g->sync) { g->sync = 0; g->nSyncDeclined++; h->syncHolding = 0; } \
                           if (h->landedChunk) { h->lastReason = p.reason; return FLUSH_RESYNC; } \
                           return (code); } while (0)

  if (h->con == INVALID_HANDLE_VALUE || !view_of(h->con, &v, &csbi))
  {
    snprintf(h->lastError, sizeof h->lastError, "flush: no console (%lu)", (unsigned long)GetLastError());
    g->pendingScrolls = 0;
    rc_drop_base(g);
    return FLUSH_API;
  }
  sync_region_host(h);
  rc_plan_paint(g, &v, &p);
  h->lastReason = p.reason;
  h->nFlush++;
  h->trSeq++;
  h->trReason = p.reason;
  h->trBaseSet = g->baseSet;
  h->trBaseRow = g->baseRow;
  h->trWinT = v.winT;
  h->trBase = p.row0 - p.slideRows;
  h->trSlide = p.slideRows;
  h->trSlideTo = p.slideTo;
  h->trBufScroll = p.bufScroll;
  h->trRow0 = p.row0;
  h->trWinTop = p.winTop;
  h->trRows = g->rows;
  h->trWinRows = g->winRows;
  h->trBufH = v.bufH;
  h->trPend = g->pendingScrolls;
  h->trRuns = p.nRuns;
  h->trCells = p.cells;
  h->trDeclined = (p.reason == RC_PLAN_NOGEOM) ? 1 : 0;
  h->trMoveFail = 0;

  if (!h->painting)
  {
    flush_reports(h, &v, &p);
    rc_paint_done(g);
    h->syncHolding = 0;
    return FLUSH_NOTHING;
  }

  if (p.reason == RC_PLAN_NOGEOM) DECLINE(FLUSH_NOGEOM);

  const int room = rc_scroll_room(g);
  const int gutterFull = (room > 0 && g->pendingScrolls >= room);
  if (g->sync && p.reason != RC_PLAN_EMPTY && !gutterFull)
  {
    const DWORD now = GetTickCount();
    if (h->syncHolding && (DWORD)(now - h->syncSince) > (DWORD)RC_SYNC_TIMEOUT_MS)
    {
      g->sync = 0; g->nSyncTimeout++; h->syncHolding = 0;
    }
    else
    {
      if (!h->syncHolding) { h->syncHolding = 1; h->syncSince = now; }
      g->nSyncHeld++;
      flush_reports(h, &v, &p);
      return FLUSH_HELD;
    }
  }
  else
  {
    if (gutterFull && g->sync && p.reason != RC_PLAN_EMPTY) g->nSyncOverflow++;
    h->syncHolding = 0;
  }

  int landed = h->landedChunk;
  int paintUndone = 0;

  int movedAsPlanned = 1;
  if (p.slideTo >= 0 && !h->ptyMode)
  {
    LONG e = park_cursor(h->con, v.winL, p.slideTo);
    if (e) { snprintf(h->lastError, sizeof h->lastError, "slide=%ld", e); h->nApiErrors++; h->trMoveFail = 1; movedAsPlanned = 0; }
    else { landed = 1; h->landedChunk = 1; }
  }
  if (p.bufScroll > 0)
  {
    if (h->ptyMode)
    {
      int left = p.bufScroll;
      int paid = 0;
      while (left > 0)
      {
        const int n = left > 32 ? 32 : left;
        wchar_t crlf[64];
        for (int i = 0; i < n; i++) { crlf[2 * i] = L'\r'; crlf[2 * i + 1] = L'\n'; }
        COORD bot;
        bot.X = (SHORT)v.winL;
        {
          const int gut = g->rows - g->winRows;
          bot.Y = (SHORT)(g->carried.regSet ? (g->carried.regBot - gut) : (v.bufH - 1));
        }
        DWORD wr = 0;
        if (!SetConsoleCursorPosition(h->con, bot) ||
            !WriteConsoleW(h->con, crlf, (DWORD)(2 * n), &wr, NULL) || wr != (DWORD)(2 * n))
        {
          snprintf(h->lastError, sizeof h->lastError, "lf-scroll: %lu", (unsigned long)GetLastError());
          h->nApiErrors++;
          h->trMoveFail = 1;
          movedAsPlanned = 0;
          break;
        }
        paid += n;
        left -= n;
      }
      if (paid > 0) { landed = 1; h->landedChunk = 1; }
      else if (!landed) DECLINE(FLUSH_API);
    }
    else
    {
      LONG e = scroll_region(h->con, &v, &p, g->rows, p.bufScroll, p.scrollAttr);
      if (e)
      {
        snprintf(h->lastError, sizeof h->lastError, "scroll=%ld", e);
        h->nApiErrors++;
        h->trMoveFail = 1;
        movedAsPlanned = 0;
        if (!landed) DECLINE(FLUSH_API);
      }
      else { landed = 1; h->landedChunk = 1; }
    }
  }
  if (movedAsPlanned) rc_set_base(g, p.row0);
  else rc_drop_base(g);
  h->prevSet = g->baseSet;
  h->prevBase = g->baseRow;
  h->prevRows = g->rows;
  h->prevWinB = p.winTop + g->winRows - 1;

  if (p.nRuns > 0)
  {
    const int need = p.paintCols * g->rows;
    if (need > h->ncells)
    {
      CHAR_INFO *fresh = (CHAR_INFO *)realloc(h->cells, (size_t)need * sizeof(CHAR_INFO));
      if (!fresh)
      {
        snprintf(h->lastError, sizeof h->lastError, "scratch %d cells", need);
        h->nApiErrors++;
        paintUndone = 1;
        if (!landed) DECLINE(FLUSH_API);
      }
      else { h->cells = fresh; h->ncells = need; }
    }
    if (h->cells)
    {
      for (int i = 0; i < p.nRuns; i++)
      {
        const int top = p.run[i].top, nrows = p.run[i].nrows;
        const int lo = p.run[i].lo, hi = p.run[i].hi, w = hi - lo + 1;
        for (int r = 0; r < nrows; r++)
          build_row(g, top + r, lo, hi, h->cells + (size_t)r * w);
        LONG e;
        if (h->faultRun == i) { h->faultRun = -1; e = (LONG)ERROR_INVALID_PARAMETER; }
        else e = write_rect(h->con, &v, &p, top, nrows, lo, hi, h->cells);
        if (e)
        {
          snprintf(h->lastError, sizeof h->lastError, "rect r%d x%d c%d..%d =%ld", top, nrows, lo, hi, e);
          h->nApiErrors++;
          paintUndone = 1;
          break;
        }
        landed = 1;
        h->landedChunk = 1;
        h->nPaints++;
      }
    }
  }

  if (p.attrChanged && !SetConsoleTextAttribute(h->con, (WORD)p.attr))
  {
    snprintf(h->lastError, sizeof h->lastError, "attr=%lu", (unsigned long)GetLastError());
    h->nApiErrors++;
  }
  if (p.setVisible || p.setShape)
  {
    CONSOLE_CURSOR_INFO ci;
    memset(&ci, 0, sizeof ci);
    if (GetConsoleCursorInfo(h->con, &ci))
    {
      if (p.setVisible) ci.bVisible = p.cursorVisible ? TRUE : FALSE;
      if (p.setShape) ci.dwSize = (DWORD)p.shapeHeight;
      if (!SetConsoleCursorInfo(h->con, &ci))
      {
        snprintf(h->lastError, sizeof h->lastError, "cursorinfo=%lu", (unsigned long)GetLastError());
        h->nApiErrors++;
      }
    }
  }
  if (h->setShapeFn)
  {
    const int want = p.setStyle ? p.shapeStyle
                     : (h->lastShapeStyle >= 0 ? RC_CURSOR_STYLE_BLOCK : -1);
    if (want >= 0 && want != h->lastShapeStyle)
    {
      if (h->setShapeFn(h->con, (DWORD)want)) h->lastShapeStyle = want;
      else
      {
        snprintf(h->lastError, sizeof h->lastError, "cursorshape=%lu", (unsigned long)GetLastError());
        h->nApiErrors++;
      }
    }
  }
  if (h->g && h->g->carried.palTouched)
  {
    if (apply_palette(h, h->g->carried.pal16, h->g->carried.palTouched, &csbi)) h->g->carried.palTouched = 0;
  }
  if (p.cursorMoved)
  {
    LONG e = park_cursor(h->con, p.curTX, p.curTY);
    if (e) { snprintf(h->lastError, sizeof h->lastError, "cursor=%ld", e); h->nApiErrors++; }
  }

  if (rc_title_pending(g))
  {
    wchar_t t[RC_TITLE_MAX + 1];
    const int n = rc_title_take(g, (uint16_t *)t, RC_TITLE_MAX);
    if (n < 0) h->nApiErrors++;
    else
    {
      t[n] = 0;
      if (SetConsoleTitleW(t)) g_titleCalls++;
      else { snprintf(h->lastError, sizeof h->lastError, "title=%lu", (unsigned long)GetLastError()); h->nApiErrors++; }
    }
  }

  if (rc_clip_pending(g))
  {
    uint8_t raw[RC_CLIP_MAX];
    const int n = rc_clip_take(g, raw, (int)sizeof raw);
    if (n < 0) h->nApiErrors++;
    else
    {
      wchar_t wide[RC_CLIP_MAX + 1];
      const int wl = (n == 0) ? 0
          : MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, (LPCSTR)raw, n, wide, RC_CLIP_MAX);
      if (n > 0 && wl == 0) { g_clipFails++; snprintf(h->lastError, sizeof h->lastError, "clip=utf8=%lu", (unsigned long)GetLastError()); }
      else
      {
        wide[wl] = 0;
        DWORD why = 0;
        const int r = clip_apply(wide, wl, &why);
        if (r == RC_CLIP_OK) g_clipCalls++;
        else
        {
          static const char stage[] = "?oeas";
          g_clipFails++;
          snprintf(h->lastError, sizeof h->lastError, "clip=%c=%lu",
                   (r >= 0 && r < (int)sizeof stage) ? stage[r] : '?', (unsigned long)why);
        }
      }
    }
  }

  flush_reports(h, &v, &p);

  rc_paint_done(g);
  if (paintUndone) rc_drop_base(g);
#undef DECLINE
  if (!landed && p.reason == RC_PLAN_EMPTY) return FLUSH_NOTHING;
  return FLUSH_PAINTED;
}

void flush_now(void *ctx)
{
  RcHandle *h = (RcHandle *)ctx;
  if (paint_flush(h) < 0) h->g->onFlush = NULL;
}

int build_model(RcHandle *h, int cols, int rows, int defAttr, int *status)
{
  *status = OPEN_OK;
  if (cols > RC_MAX_COLS) { *status = OPEN_WIDE; return 0; }
  int hist = rows;
  if (rows + hist > RC_MAX_ROWS) hist = RC_MAX_ROWS - (int)rows;
  if (hist <= 0) { *status = OPEN_NO_GUTTER; return 0; }
  RcGrid *fresh = (RcGrid *)calloc(1, sizeof(RcGrid));
  if (!fresh) { *status = OPEN_OOM; return 0; }
  if (!rc_reset_hist(fresh, cols, rows, hist, (uint16_t)defAttr))
  {
    free(fresh);
    *status = OPEN_BIG;
    return 0;
  }
  /* Batched, not streamed, on every console kind. Under a pseudo-console this used to be 1, which made
     scroll_up's flush test fire per row: one 40-row dashboard chunk measured 17 flushes and 17
     rectangles against the classic console's 1 and 1 for the same bytes (ProbeFlush, cache/topfix),
     and conhost's serializer re-emits every intermediate state it is shown -- the interleaved first
     refresh of top, #103's scrollback half. The per-scroll urgency bought nothing the chunk-end pay
     does not: the debt is still paid in real line feeds under a pty, the host's scrollback still
     grows one row per paid feed, and a chunk longer than the gutter still flushes at the gutter
     boundary, so streaming survives at the granularity that matters. */
  fresh->streamScrolls = 0;
  RcCarried keep;
  int keepCols = 0, keepRows = 0, keepWin = 0;
  const int haveKeep = h->g != NULL;
  if (haveKeep)
  {
    keep = h->g->carried;
    keepCols = h->g->cols;
    keepRows = h->g->rows;
    keepWin = h->g->winRows;
  }
  drop_model(h);
  h->g = fresh;
  if (haveKeep)
  {
    fresh->carried = keep;
    carried_readopt(fresh, keepCols, keepRows, keepWin);
  }
  h->g->onFlush = flush_now;
  h->g->flushCtx = h;
  h->defAttr = (uint16_t)defAttr;
  h->landedChunk = 0;
  h->lastError[0] = 0;
  return 1;
}

int readopt(RcHandle *h, int *status)
{
  RcView v;
  CONSOLE_SCREEN_BUFFER_INFO csbi;
  *status = OPEN_NO_CONSOLE;
  if (h->con == INVALID_HANDLE_VALUE || !view_of(h->con, &v, &csbi)) return 0;
  const int wasRows = h->g ? h->g->winRows : 0;
  if (!build_model(h, v.bufW - v.winL, v.winB - v.winT + 1, h->defAttr, status)) return 0;
  const int shaped = (wasRows != 0 && h->g->winRows != wasRows);
  return align_grid(h, shaped) ? 1 : (*status = OPEN_NO_CONSOLE, 0);
}

int give_up(RcHandle *h, const char *why)
{
  if (!h->stopped[0]) snprintf(h->stopped, sizeof h->stopped, "%s", why);
  drop_model(h);
  claim_output(h, 0);
  h->adopt = RC_ALIGN;
  h->declines = 0;
  return RENDER_GIVEUP;
}

int refuse(RcHandle *h, int status)
{
  char msg[256];
  snprintf(msg, sizeof msg, "native renderer refused the console: %s", open_name(status));
  return give_up(h, msg);
}

int paint_and_check(RcHandle *h)
{
  const int r = paint_flush(h);
  if (r >= 0 && rc_model_suspect(h->g)) align_grid(h, 0);
  return r;
}

void sync_region_host(RcHandle *h)
{
  if (!h->ptyMode || !h->g) return;
  if (h->g->regionSerial == h->regionFwd) return;
  h->regionFwd = h->g->regionSerial;
  wchar_t b[32];
  int m;
  const int gut = h->g->rows - h->g->winRows;
  if (h->g->carried.regSet)
    m = swprintf(b, (int)(sizeof b / sizeof b[0]), L"\x1b[%d;%dr",
                 h->g->carried.regTop - gut + 1, h->g->carried.regBot - gut + 1);
  else
    m = swprintf(b, (int)(sizeof b / sizeof b[0]), L"\x1b[r");
  if (m <= 0) return;
  const int wasClaimed = h->outClaimed;
  if (wasClaimed) claim_output(h, 0);
  DWORD wr = 0;
  if (!WriteConsoleW(h->con, b, (DWORD)m, &wr, NULL) || wr != (DWORD)m)
  {
    snprintf(h->lastError, sizeof h->lastError, "region-fwd: %lu", (unsigned long)GetLastError());
    h->nApiErrors++;
  }
  if (wasClaimed) claim_output(h, 1);
}

int align_grid(RcHandle *h, int reshaped)
{
  if (!h) return 0;
  RcGrid *g = h->g;
  const int hist = g->rows - g->winRows;
  RcView v;
  CONSOLE_SCREEN_BUFFER_INFO csbi;
  if (h->con == INVALID_HANDLE_VALUE || !view_of(h->con, &v, &csbi)) return 0;
  if (v.bufW - v.winL != g->cols || v.winB - v.winT + 1 != g->winRows) return 0;

  const int base = rc_anchor_adopt(h->prevSet, h->prevBase, h->prevRows, h->prevWinB, reshaped,
                                   v.winT, v.winB, v.bufH, g->rows, g->winRows);
  const int readTop = base + hist;
  const int cells = g->cols * g->winRows;
  CHAR_INFO *buf = (CHAR_INFO *)malloc((size_t)cells * sizeof(CHAR_INFO));
  if (!buf) return 0;
  memset(buf, 0, (size_t)cells * sizeof(CHAR_INFO));
  COORD size, coord;
  SMALL_RECT rect;
  size.X = (SHORT)g->cols;
  size.Y = (SHORT)g->winRows;
  coord.X = 0;
  coord.Y = 0;
  rect.Left = (SHORT)v.winL;
  rect.Right = (SHORT)(v.winL + g->cols - 1);
  rect.Top = (SHORT)readTop;
  rect.Bottom = (SHORT)(readTop + g->winRows - 1);
  BOOL ok = ReadConsoleOutputW(h->con, buf, size, coord, &rect);
  if (!ok)
  {
    free(buf);
    snprintf(h->lastError, sizeof h->lastError, "align read=%lu", (unsigned long)GetLastError());
    return 0;
  }
  for (int r = 0; r < g->winRows; r++)
    for (int c = 0; c < g->cols; c++)
    {
      RC_CELLS(g, hist + r)[c].ch = CH_UNICODE(buf[(size_t)r * g->cols + c]);
      RC_CELLS(g, hist + r)[c].attr = buf[(size_t)r * g->cols + c].Attributes;
    }
  free(buf);
  g->attr = (uint16_t)csbi.wAttributes;
  g->carried.defAttr = h->defAttr;
  g->cx = (v.curX >= v.winL && v.curX < v.bufW) ? v.curX - v.winL : 0;
  g->cy = (v.curY >= readTop && v.curY <= readTop + g->winRows - 1) ? v.curY - base : hist;
  g->pendingScrolls = 0;
  rc_set_base(g, base);
  h->prevSet = g->baseSet;
  h->prevBase = g->baseRow;
  h->prevRows = g->rows;
  h->prevWinB = v.winB;
  g->onFlush = flush_now;
  g->flushCtx = h;
  h->nAligns++;
  rc_forget_row_state(g);
  rc_clear_model_suspect(g);
  rc_adopt_clean(g);
  return 1;
}

/* RenderExec.h -- the seam between the JNI binding and the console executor.
   RenderJni.cpp owns the exports, the handle registry and the argument marshalling;
   RenderExec.cpp owns everything that touches the console or executes the plan. A fact
   that can only be obtained from a live console belongs to the executor (DESIGN.md 2.1);
   this header is what lets the two files share one RcHandle without sharing a TU. */
#ifndef ANSIRENDER_RENDEREXEC_H
#define ANSIRENDER_RENDEREXEC_H

#include <windows.h>
#include <jni.h>

#include "Paint.h"
#include "Render.h"

#define RENDER_BUILD "render-2026-10-05-70"
enum
{
  RENDER_GIVEUP = -1,
  RENDER_RAW = 0,
  RENDER_PAINTED = 1
};

enum
{
  RC_REBUILD = -1,
  RC_ALIGN   = 0,
  RC_ADOPTED = 1
};

#define OPEN_ASK_SHAPE 0
#define OPEN_ASK_ATTR  (-1)

enum
{
  FLUSH_PAINTED = 0,
  FLUSH_NOTHING = 1,
  FLUSH_RESYNC = 2,
  FLUSH_HELD = 3,
  FLUSH_NOGEOM = -1,
  FLUSH_API = -3
};

#define RENDER_MAX_DECLINES 16

enum
{
  OPEN_OK = 0, OPEN_NO_CONSOLE = 1, OPEN_BIG = 2,
  OPEN_WIDE = 3,
  OPEN_NO_GUTTER = 4, OPEN_OOM = 5
};
#define RC_CLIP_OK 0
#define RC_CLIP_OPEN 1
#define RC_CLIP_EMPTY 2
#define RC_CLIP_ALLOC 3
#define RC_CLIP_SET 4
#ifdef __MINGW32__
#define CH_UNICODE(ci) ((ci).Char.UnicodeChar)
#else
#define CH_UNICODE(ci) ((ci).Char.Unicode)
#endif

typedef BOOL(WINAPI *RcSetCursorShape)(HANDLE hConsoleOutput, DWORD ulCursorShape);

typedef struct RcHandle
{
  RcGrid *g;
  int taken;
  CHAR_INFO *cells;
  int ncells;
  HANDLE con;
  int ownsCon;
  HANDLE in;
  uint32_t palOrig[16];
  int    palSaved;
  uint16_t defAttr;
  DWORD  inBase;
  int    inSaved, inArmed;
  DWORD  outBase;
  int    outSaved, outClaimed;
  int landedChunk;
  int adopt, declines;
  char stopped[128];
  int painting;
  int ptyMode;
  uint32_t regionFwd;
  int prevSet, prevBase, prevRows, prevWinB;
  int repRows, repCols;
  RcSetCursorShape setShapeFn;
  int lastShapeStyle;
  int trSeq, trReason, trBaseSet, trBaseRow, trWinT, trBase, trSlide, trSlideTo, trBufScroll, trRow0,
      trWinTop, trRows, trWinRows, trBufH, trPend, trRuns, trDeclined, trMoveFail;
  unsigned long trCells;
  unsigned long nFlush, nPaints, nDeclines, nApiErrors, nAligns, nSnaps;
  int faultRun;
  DWORD syncSince;
  int   syncHolding;
  int lastReason;
  char lastError[128];
} RcHandle;

/* counters the executor folds and stats() reads */
extern RcHandle g_h[4];
extern int g_openStatus;
extern unsigned long g_totUn[RC_UN_MAX], g_totTitle, g_totTitleTrunc, g_titleCalls,
    g_totAltSwitch, g_totAltFail, g_totPromptMark, g_totRepOk, g_totRepFail, g_totRepFull,
    g_totArgTrunc, g_totSyncEngages, g_totSyncNested, g_totSyncHeld, g_totSyncTimeout,
    g_totSyncOverflow, g_totSyncDeclined, g_totClipSet, g_totClipBad, g_totClipSel,
    g_totClipRead;
extern unsigned long g_clipCalls, g_clipFails;

/* the executor surface the JNI side drives */
int console_window_is_pty(void);
int clip_apply(const wchar_t *wide, int chars, DWORD *why);
int view_of(HANDLE con, RcView *v, CONSOLE_SCREEN_BUFFER_INFO *csbi);
int align_grid(RcHandle *h, int reshaped);
void carried_readopt(RcGrid *g, int oldCols);
int build_model(RcHandle *h, int cols, int rows, int defAttr, int *status);
int readopt(RcHandle *h, int *status);
int give_up(RcHandle *h, const char *why);
int refuse(RcHandle *h, int status);
int paint_and_check(RcHandle *h);
void sync_region_host(RcHandle *h);

/* executor internals the JNI side drives directly */
void build_row(const RcGrid *g, int row, int lo, int hi, CHAR_INFO *dst);
LONG write_rect(HANDLE con, const RcView *v, const RcPlan *p, int top, int nrows,
                int lo, int hi, const CHAR_INFO *cells);
LONG scroll_region(HANDLE con, const RcView *v, const RcPlan *p, int modelRows,
                   int by, uint16_t attr);
LONG park_cursor(HANDLE con, int x, int y);
int reply_text(int kind, const RcGrid *g, const RcView *v, const RcPlan *p,
               const struct RcReportItem *it, wchar_t *out, int cap);
int write_input_units(RcHandle *h, const wchar_t *txt, int n);
void flush_reports(RcHandle *h, const RcView *v, const RcPlan *p);
int apply_palette(RcHandle *h, const uint32_t *src, uint16_t mask,
                  const CONSOLE_SCREEN_BUFFER_INFO *keep);
int sync_mouse(RcHandle *h, int on);
int claim_output(RcHandle *h, int on);
int paint_flush(RcHandle *h);
void flush_now(void *ctx);

/* lifecycle the JNI side drives (and the executor's give_up chain folds through) */
void fold_counters(RcHandle *h);
void drop_model(RcHandle *h);
void release_all(RcHandle *h);
const char *open_name(int status);
const char *decline_name(int r);

#endif

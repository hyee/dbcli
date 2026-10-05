#include <jni.h>
#include <windows.h>
#include <stdlib.h>
#include <string.h>
#include "RenderExec.h"
#include "Paint.h"
#include "Render.h"
#define READ_MAX_CELLS 4096
#define STAT_UNSUPPORTED 17
#define STAT_TITLES      (STAT_UNSUPPORTED + RC_UN_MAX)
#define STAT_ALT         (STAT_TITLES + 3)
#define STAT_PROMPT      (STAT_ALT + 2)
#define STAT_REPORT      (STAT_PROMPT + 2)
#define STAT_SNAP        (STAT_REPORT + 3)
#define STAT_SYNC        (STAT_SNAP + 1)
#define STAT_CLIP        (STAT_SYNC + 7)
#define STAT_ARGTRUNC    (STAT_CLIP + 7)
#define STAT_BP          (STAT_ARGTRUNC + 1)
#define STAT_SHAPE       (STAT_BP + 1)
#define STAT_LAST        (STAT_SHAPE + 1)

typedef BOOL(WINAPI *RcSetCursorShape)(HANDLE hConsoleOutput, DWORD ulCursorShape);
RcHandle g_h[4];
int g_openStatus;

unsigned long g_totUn[RC_UN_MAX], g_totTitle, g_totTitleTrunc, g_titleCalls,
                     g_totAltSwitch, g_totAltFail, g_totPromptMark,
                     g_totRepOk, g_totRepFail, g_totRepFull, g_totArgTrunc,
                     g_totSyncEngages, g_totSyncNested, g_totSyncHeld,
                     g_totSyncTimeout, g_totSyncOverflow, g_totSyncDeclined,
                     g_totClipSet, g_totClipBad, g_totClipSel, g_totClipRead;
unsigned long g_clipCalls, g_clipFails;

static RcHandle *slot_of(jlong p)
{
  RcHandle *h = (RcHandle *)(void *)p;
  return (h >= g_h && h < g_h + (int)(sizeof g_h / sizeof g_h[0]) && h->taken) ? h : NULL;
}

static RcHandle *handle(jlong p)
{
  RcHandle *h = slot_of(p);
  return (h && h->g) ? h : NULL;
}

static const char *copyChars(JNIEnv *env, jcharArray text, jint off, jint len, uint16_t **out)
{
  if (!text || len <= 0) return "empty";
  if (off < 0 || len > (jint)(env->GetArrayLength(text) - off)) return "bounds";
  jchar *p = (jchar *)env->GetPrimitiveArrayCritical(text, NULL);
  if (!p) return "critical";
  *out = (uint16_t *)p;
  (void)off;
  return NULL;
}

void fold_counters(RcHandle *h)
{
  if (!h->g) return;
  for (int i = 0; i < RC_UN_MAX; i++) g_totUn[i] += h->g->nUnsupported[i];
  g_totTitle += h->g->nTitleSet;
  g_totTitleTrunc += h->g->nTitleTrunc;
  g_totClipSet += h->g->nClipSet;
  g_totClipBad += h->g->nClipBad;
  g_totClipSel += h->g->nClipSel;
  g_totClipRead += h->g->nClipRead;
  g_totAltSwitch += h->g->nAltSwitch;
  g_totAltFail += h->g->nAltFail;
  g_totPromptMark += h->g->nPromptMark;
  g_totRepOk += h->g->nReportOk;
  g_totRepFail += h->g->nReportFail;
  g_totRepFull += h->g->nReportFull;
  g_totArgTrunc += h->g->nArgTrunc;
  g_totSyncEngages += h->g->nSyncEngages;
  g_totSyncNested += h->g->nSyncNested;
  g_totSyncHeld += h->g->nSyncHeld;
  g_totSyncTimeout += h->g->nSyncTimeout;
  g_totSyncOverflow += h->g->nSyncOverflow;
  g_totSyncDeclined += h->g->nSyncDeclined;
}

void drop_model(RcHandle *h)
{
  fold_counters(h);
  if (!h->g) return;
  free(h->g->snap);
  free(h->g);
  h->g = NULL;
}

void release_all(RcHandle *h)
{
  if (h->palSaved && h->con != INVALID_HANDLE_VALUE)
  {
    CONSOLE_SCREEN_BUFFER_INFO keep;
    if (GetConsoleScreenBufferInfo(h->con, &keep))
      apply_palette(h, h->palOrig, 0xFFFF, &keep);
    h->palSaved = 0;
  }
  if (h->inArmed) sync_mouse(h, 0);
  h->inSaved = 0; h->inBase = 0;
  if (h->outClaimed) claim_output(h, 0);
  h->outSaved = 0; h->outBase = 0;
  drop_model(h);
  free(h->cells);
  h->cells = NULL;
  h->ncells = 0;
  h->prevSet = h->prevBase = h->prevRows = h->prevWinB = 0;
  h->repRows = h->repCols = 0;
  h->lastShapeStyle = -1;
  if (h->con != INVALID_HANDLE_VALUE && h->ownsCon) CloseHandle(h->con);
  h->con = INVALID_HANDLE_VALUE;
  h->ownsCon = 0;
  if (h->in != INVALID_HANDLE_VALUE) CloseHandle(h->in);
  h->in = INVALID_HANDLE_VALUE;
  h->taken = 0;
}

const char *open_name(int status)
{
  switch (status)
  {
    case OPEN_NO_CONSOLE: return "there is no console behind the handle";
    case OPEN_BIG:        return "the window is too tall to model with a scroll gutter (a full screen "
                                 "needs 128 rows at most, and none at all above 255)";
    case OPEN_WIDE:       return "the buffer row is wider than the model (4096 columns at most)";
    case OPEN_NO_GUTTER:  return "no room for a scroll gutter";
    case OPEN_OOM:        return "out of memory or handles";
    default:              return "refused for a reason this build does not name";
  }
}

/* The carried state a rebuild cannot paste verbatim: the margin pair is re-clamped to the
   new width (a pair that no longer narrows anything is dropped, the cursor kept inside it),
   the tab columns the old width never had get the default interval back, and a motion the
   old window witnessed is not evidence in the new one. */
const char *decline_name(int r)
{
  if (r == FLUSH_NOGEOM) return "the console kept changing shape";
  if (r == FLUSH_API)    return "console calls kept failing";
  return "the painter kept declining";
}

extern "C" JNIEXPORT jint JNICALL Java_com_hyee_ansirender_NativeRenderer_render(JNIEnv *env, jclass cls, jlong ph,
                                                            jcharArray text, jint off, jint len)
{
  (void)cls;
  RcHandle *h = slot_of(ph);
  if (!h || len <= 0) return RENDER_RAW;
  if (!h->g) return RENDER_GIVEUP;

  if (h->adopt != RC_ADOPTED)
  {
    const int cheap = (h->adopt == RC_ALIGN) && align_grid(h, 0);
    if (cheap) h->adopt = RC_ADOPTED;
    else
    {
      int status = OPEN_OK;
      if (!readopt(h, &status)) return refuse(h, status);
      h->adopt = RC_ADOPTED;
    }
  }

  h->landedChunk = 0;
  uint16_t *units = NULL;
  const char *bad = copyChars(env, text, off, len, &units);
  if (bad)
  {
    char msg[192];
    snprintf(msg, sizeof msg, "native renderer refused the chunk (%s)", bad);
    return give_up(h, msg);
  }
  rc_feed(h->g, units + off, len);
  sync_mouse(h, h->g->carried.mouseModes != 0);
  env->ReleasePrimitiveArrayCritical(text, (jchar *)units, 0);
  rc_sgr_clear(h->g);
  sync_region_host(h);

  if (!h->painting)
  {
    paint_flush(h);
    h->declines = 0;
    return RENDER_RAW;
  }

  const int r = paint_and_check(h);
  if (r >= 0)
  {
    h->declines = 0;
    if (r == FLUSH_RESYNC) h->adopt = RC_ALIGN;
    return RENDER_PAINTED;
  }
  if (r == FLUSH_NOGEOM && !h->landedChunk)
  {
    int status = OPEN_OK;
    if (readopt(h, &status))
    {
      h->adopt = RC_ADOPTED;
      uint16_t *again = NULL;
      if (!copyChars(env, text, off, len, &again))
      {
        rc_feed(h->g, again + off, len);
        sync_mouse(h, h->g->carried.mouseModes != 0);
        rc_sgr_clear(h->g);
        sync_region_host(h);
        env->ReleasePrimitiveArrayCritical(text, (jchar *)again, 0);
        if (paint_and_check(h) >= 0)
        {
          h->declines = 0;
          return RENDER_PAINTED;
        }
        h->adopt = RC_REBUILD;
      }
    }
  }
  char msg[192];
  if (++h->declines >= RENDER_MAX_DECLINES)
  {
    snprintf(msg, sizeof msg, "native renderer stopped after %d chunk(s) it could not paint (%s);"
             " output is written unparsed", h->declines, decline_name(r));
    return give_up(h, msg);
  }
  h->adopt = RC_REBUILD;
  return RENDER_RAW;
}

extern "C" {

JNIEXPORT jstring JNICALL Java_com_hyee_ansirender_NativeRenderer_build(JNIEnv *env, jclass cls)
{
  char b[192];
  sprintf(b, "%s gcc=[%s] arch=%s sizeof_CHAR_INFO=%u handles=%u", RENDER_BUILD,
          __VERSION__, (sizeof(void *) == 4) ? "x86" : "x64", (unsigned)sizeof(CHAR_INFO),
          (unsigned)(sizeof g_h / sizeof g_h[0]));
  return env->NewStringUTF(b);
}

JNIEXPORT jlong JNICALL Java_com_hyee_ansirender_NativeRenderer_open(JNIEnv *env, jclass cls, jlong console,
                                                           jint cols, jint rows, jint defAttr)
{
  (void)env; (void)cls;
  g_openStatus = OPEN_OK;
  HANDLE con;
  if (console != 0) con = (HANDLE)(void *)console;
  else
  {
    con = CreateFileW(L"CONOUT$", GENERIC_READ | GENERIC_WRITE,
                      FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
    if (con == INVALID_HANDLE_VALUE) { g_openStatus = OPEN_NO_CONSOLE; return 0; }
  }
  if (con == INVALID_HANDLE_VALUE || con == NULL)
  {
    g_openStatus = OPEN_NO_CONSOLE;
    return 0;
  }

  RcView v;
  CONSOLE_SCREEN_BUFFER_INFO csbi;
  if (cols == OPEN_ASK_SHAPE || rows == OPEN_ASK_SHAPE)
  {
    if (!view_of(con, &v, &csbi))
    {
      g_openStatus = OPEN_NO_CONSOLE;
      if (console == 0) CloseHandle(con);
      return 0;
    }
    if (cols == OPEN_ASK_SHAPE) cols = v.bufW - v.winL;
    if (rows == OPEN_ASK_SHAPE) rows = v.winB - v.winT + 1;
  }
  if (defAttr == OPEN_ASK_ATTR)
  {
    if (view_of(con, &v, &csbi)) defAttr = csbi.wAttributes;
    else defAttr = 0x07;
  }

  int hist_status = OPEN_OK;
  RcHandle *slot = NULL;
  for (int i = 0; i < (int)(sizeof g_h / sizeof g_h[0]); i++)
  {
    if (!g_h[i].taken) { slot = &g_h[i]; break; }
  }
  if (!slot)
  {
    g_openStatus = OPEN_OOM;
    if (console == 0) CloseHandle(con);
    return 0;
  }
  slot->taken = 1;
  slot->con = con;
  slot->ownsCon = (console == 0) ? 1 : 0;
  slot->in = INVALID_HANDLE_VALUE;
  slot->outBase = 0; slot->outSaved = 0; slot->outClaimed = 0;
  claim_output(slot, 1);
  slot->prevSet = slot->prevBase = slot->prevRows = slot->prevWinB = 0;
  slot->trSeq = 0;
  slot->adopt = RC_ALIGN;
  slot->declines = 0;
  slot->painting = 1;
  slot->ptyMode = console_window_is_pty();
  slot->stopped[0] = 0;
  slot->cells = NULL;
  slot->ncells = 0;
  slot->defAttr = (uint16_t)defAttr;
  slot->nFlush = slot->nPaints = slot->nDeclines = slot->nApiErrors = slot->nAligns = slot->nSnaps = 0;
  slot->faultRun = -1;
  slot->lastReason = 0;
  slot->lastError[0] = 0;
  if (!build_model(slot, cols, rows, defAttr, &hist_status))
  {
    g_openStatus = hist_status;
    slot->taken = 0;
    slot->con = INVALID_HANDLE_VALUE;
    slot->ownsCon = 0;
    if (console == 0) CloseHandle(con);
    return 0;
  }
  g_openStatus = OPEN_OK;
  slot->regionFwd = slot->g->regionSerial;
  if (!slot->setShapeFn)
  {
    const HMODULE k32 = GetModuleHandleW(L"kernel32.dll");
    if (k32) slot->setShapeFn = (RcSetCursorShape)(void *)GetProcAddress(k32, "SetConsoleCursorShape");
  }
  slot->lastShapeStyle = -1;
  if (slot->setShapeFn) rc_cursor_shape_api(1);
  slot->repRows = slot->g->winRows;
  slot->repCols = slot->g->cols;
  return (jlong)(void *)slot;
}

JNIEXPORT jint JNICALL Java_com_hyee_ansirender_NativeRenderer_openStatus(JNIEnv *env, jclass cls)
{
  (void)env; (void)cls;
  return g_openStatus;
}

JNIEXPORT jstring JNICALL Java_com_hyee_ansirender_NativeRenderer_openReason(JNIEnv *env, jclass cls)
{
  (void)cls;
  return env->NewStringUTF(open_name(g_openStatus));
}

JNIEXPORT jint JNICALL Java_com_hyee_ansirender_NativeRenderer_feed(JNIEnv *env, jclass cls, jlong ph,
                                                          jcharArray text, jint off, jint len)
{
  RcHandle *h = handle(ph);
  if (!h) return 0;
  h->landedChunk = 0;
  uint16_t *units = NULL;
  const char *bad = copyChars(env, text, off, len, &units);
  if (bad)
  {
    snprintf(h->lastError, sizeof h->lastError, "feed: %s", bad);
    return 0;
  }
  rc_feed(h->g, units + off, len);
  sync_mouse(h, h->g->carried.mouseModes != 0);
  env->ReleasePrimitiveArrayCritical(text, (jchar *)units, 0);
  return 1;
}

JNIEXPORT jint JNICALL Java_com_hyee_ansirender_NativeRenderer_flush(JNIEnv *env, jclass cls, jlong ph)
{
  (void)env; (void)cls;
  RcHandle *h = handle(ph);
  if (!h) return FLUSH_API;
  return paint_and_check(h);
}

JNIEXPORT jcharArray JNICALL Java_com_hyee_ansirender_NativeRenderer_sgr(JNIEnv *env, jclass cls, jlong ph)
{
  RcHandle *h = handle(ph);
  if (!h) return NULL;
  const int n = rc_sgr_pending(h->g);
  if (n <= 0) return NULL;
  jcharArray a = env->NewCharArray(n);
  if (!a) return NULL;
  jchar *p = (jchar *)env->GetPrimitiveArrayCritical(a, NULL);
  if (!p) { env->DeleteLocalRef(a); return NULL; }
  const int got = rc_sgr_take(h->g, (uint16_t *)p, n);
  env->ReleasePrimitiveArrayCritical(a, p, 0);
  if (got != n) { env->DeleteLocalRef(a); return NULL; }
  return a;
}

JNIEXPORT jint JNICALL Java_com_hyee_ansirender_NativeRenderer_align(JNIEnv *env, jclass cls, jlong ph)
{
  return (jint)align_grid(handle(ph), 0);
}

JNIEXPORT jint JNICALL Java_com_hyee_ansirender_NativeRenderer_snap(JNIEnv *env, jclass cls, jlong ph)
{
  (void)env; (void)cls;
  RcHandle *h = handle(ph);
  if (!h) return RC_SNAP_NOGEOM;
  if (!h->painting || h->ptyMode) return RC_SNAP_NOCHANGE;
  RcView v;
  CONSOLE_SCREEN_BUFFER_INFO csbi;
  if (h->con == INVALID_HANDLE_VALUE || !view_of(h->con, &v, &csbi))
  {
    snprintf(h->lastError, sizeof h->lastError, "snap: no console (%lu)", (unsigned long)GetLastError());
    return RC_SNAP_NOGEOM;
  }
  int row = -1, col = -1;
  const int r = rc_snap_view(h->g, &v, &row, &col);
  if (r != RC_SNAP_PARK) return (jint)r;
  if (park_cursor(h->con, col, row))
  {
    snprintf(h->lastError, sizeof h->lastError, "snap=%lu", (unsigned long)GetLastError());
    h->nApiErrors++;
    return (jint)r;
  }
  h->nSnaps++;
  return (jint)r;
}

JNIEXPORT jboolean JNICALL Java_com_hyee_ansirender_NativeRenderer_isPseudoConsole(JNIEnv *env, jclass cls)
{
  (void)env; (void)cls;
  return console_window_is_pty() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL Java_com_hyee_ansirender_NativeRenderer_encodeMouse0(
    JNIEnv *env, jclass cls, jlong ph,
    jint x, jint y, jint px, jint py,
    jint buttonState, jint eventFlags, jint ctrlKeyState, jcharArray out)
{
  (void)cls;
  RcHandle *h = handle(ph);
  if (!h || !h->g) return 0;
  struct RcMouseRec m;
  m.x = (int16_t)x;  m.y = (int16_t)y;
  m.px = (int16_t)px; m.py = (int16_t)py;
  m.buttonState = (uint32_t)buttonState;
  m.eventFlags = (uint32_t)eventFlags;
  m.ctrlKeyState = (uint16_t)ctrlKeyState;
  uint16_t buf[40];
  const int n = rc_mouse_report(h->g, &m, buf, (int)(sizeof buf / sizeof buf[0]));
  if (n <= 0 || !out) return n;
  if (env->GetArrayLength(out) < n) return -1;
  env->SetCharArrayRegion(out, 0, n, (const jchar *)buf);
  return n;
}

JNIEXPORT jint JNICALL Java_com_hyee_ansirender_NativeRenderer_encodeFocus0(
    JNIEnv *env, jclass cls, jlong ph, jint focused, jcharArray out)
{
  (void)cls;
  RcHandle *h = handle(ph);
  if (!h || !h->g) return 0;
  uint16_t buf[3];
  const int n = rc_focus_report(h->g, focused != 0, buf, 3);
  if (n <= 0 || !out) return n;
  if (env->GetArrayLength(out) < n) return -1;
  env->SetCharArrayRegion(out, 0, n, (const jchar *)buf);
  return n;
}

JNIEXPORT jlongArray JNICALL Java_com_hyee_ansirender_NativeRenderer_taskbar0(JNIEnv *env, jclass cls, jlong ph)
{
  (void)cls;
  RcHandle *h = slot_of(ph);
  const RcGrid *g = h ? h->g : NULL;
  if (!g) return NULL;
  jlong out[3] = { (jlong)g->carried.taskbarState, (jlong)g->carried.taskbarProgress, (jlong)g->carried.taskbarSeen };
  jlongArray arr = env->NewLongArray(3);
  if (arr) env->SetLongArrayRegion(arr, 0, 3, out);
  return arr;
}

JNIEXPORT void JNICALL Java_com_hyee_ansirender_NativeRenderer_setClipboardPolicy0(JNIEnv *env, jclass cls, jboolean allow)
{
  (void)env; (void)cls;
  rc_set_clipboard_policy(allow ? RC_CLIP_ALLOW : RC_CLIP_DENY);
}

JNIEXPORT jboolean JNICALL Java_com_hyee_ansirender_NativeRenderer_clipboardPolicy0(JNIEnv *env, jclass cls)
{
  (void)env; (void)cls;
  return rc_clipboard_policy() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL Java_com_hyee_ansirender_NativeRenderer_workingDirectory0(JNIEnv *env, jclass cls, jlong ph)
{
  (void)cls;
  RcHandle *h = slot_of(ph);
  const RcGrid *g = h ? h->g : NULL;
  if (!g || g->carried.nCwd <= 0) return NULL;
  return env->NewString((const jchar *)g->carried.cwd, (jsize)g->carried.nCwd);
}

JNIEXPORT jlongArray JNICALL Java_com_hyee_ansirender_NativeRenderer_stats(JNIEnv *env, jclass cls, jlong ph)
{
  RcHandle *h = slot_of(ph);
  jlong out[STAT_LAST];
  memset(out, 0, sizeof out);
  if (h)
  {
    const RcGrid *g = h->g;
    out[0] = (jlong)h->nFlush;
    out[1] = (jlong)h->nPaints;
    out[2] = (jlong)h->nDeclines;
    out[3] = (jlong)h->nApiErrors;
    out[4] = (jlong)h->nAligns;
    if (g)
    {
      out[5] = (jlong)g->nCells;
      out[6] = (jlong)g->nScrolls;
      out[7] = (jlong)g->nAstral;
      out[9] = g->pendingScrolls;
      out[10] = g->cx;
      out[11] = g->cy;
      out[12] = g->attr;
      out[13] = g->carried.defAttr;
      out[14] = g->winRows;
      out[15] = g->rows - g->winRows;
      out[16] = g->nSgrDrop;
    }
    out[8] = h->lastReason;
    for (int i = 0; i < RC_UN_MAX; i++) out[STAT_UNSUPPORTED + i] = (jlong)(g_totUn[i] + (g ? g->nUnsupported[i] : 0));
    out[STAT_TITLES] = (jlong)(g_totTitle + (g ? g->nTitleSet : 0));
    out[STAT_TITLES + 1] = (jlong)(g_totTitleTrunc + (g ? g->nTitleTrunc : 0));
    out[STAT_TITLES + 2] = (jlong)g_titleCalls;
    out[STAT_ALT] = (jlong)(g_totAltSwitch + (g ? g->nAltSwitch : 0));
    out[STAT_ALT + 1] = (jlong)(g_totAltFail + (g ? g->nAltFail : 0));
    out[STAT_PROMPT] = (jlong)(g_totPromptMark + (g ? g->nPromptMark : 0));
    out[STAT_PROMPT + 1] = g ? (jlong)rc_last_exit(g) : (jlong)RC_EXIT_UNKNOWN;
    out[STAT_SNAP] = (jlong)h->nSnaps;
    out[STAT_REPORT] = (jlong)(g_totRepOk + (g ? g->nReportOk : 0));
    out[STAT_REPORT + 1] = (jlong)(g_totRepFail + (g ? g->nReportFail : 0));
    out[STAT_REPORT + 2] = (jlong)(g_totRepFull + (g ? g->nReportFull : 0));
    out[STAT_ARGTRUNC] = (jlong)(g_totArgTrunc + (g ? g->nArgTrunc : 0));
    out[STAT_BP] = g ? g->carried.bracketedPaste : 0;
      out[STAT_SHAPE] = (jlong)h->lastShapeStyle;
    out[STAT_SYNC] = (jlong)(g_totSyncEngages + (g ? g->nSyncEngages : 0));
    out[STAT_SYNC + 1] = (jlong)(g_totSyncNested + (g ? g->nSyncNested : 0));
    out[STAT_SYNC + 2] = (jlong)(g_totSyncHeld + (g ? g->nSyncHeld : 0));
    out[STAT_SYNC + 3] = (jlong)(g_totSyncTimeout + (g ? g->nSyncTimeout : 0));
    out[STAT_SYNC + 4] = (jlong)(g_totSyncOverflow + (g ? g->nSyncOverflow : 0));
    out[STAT_SYNC + 5] = (jlong)(g_totSyncDeclined + (g ? g->nSyncDeclined : 0));
    out[STAT_SYNC + 6] = g ? (jlong)g->sync : 0;
    out[STAT_CLIP] = (jlong)(g_totClipSet + (g ? g->nClipSet : 0));
    out[STAT_CLIP + 1] = (jlong)(g_totClipBad + (g ? g->nClipBad : 0));
    out[STAT_CLIP + 2] = (jlong)(g_totClipSel + (g ? g->nClipSel : 0));
    out[STAT_CLIP + 3] = (jlong)(g_totClipRead + (g ? g->nClipRead : 0));
    out[STAT_CLIP + 4] = (jlong)g_clipCalls;
    out[STAT_CLIP + 5] = (jlong)g_clipFails;
    out[STAT_CLIP + 6] = (jlong)rc_clipboard_policy();
  }
  jlongArray arr = env->NewLongArray(STAT_LAST);
  if (arr) env->SetLongArrayRegion(arr, 0, STAT_LAST, out);
  return arr;
}

JNIEXPORT jstring JNICALL Java_com_hyee_ansirender_NativeRenderer_stopReason(JNIEnv *env, jclass cls, jlong ph)
{
  (void)cls;
  RcHandle *h = slot_of(ph);
  if (!h || !h->stopped[0]) return NULL;
  return env->NewStringUTF(h->stopped);
}

JNIEXPORT void JNICALL Java_com_hyee_ansirender_NativeRenderer_close(JNIEnv *env, jclass cls, jlong ph)
{
  (void)env; (void)cls;
  RcHandle *h = slot_of(ph);
  if (h) release_all(h);
}

JNIEXPORT void JNICALL Java_com_hyee_ansirender_NativeRenderer_setPainting(JNIEnv *env, jclass cls, jlong ph, jboolean on)
{
  (void)env; (void)cls;
  RcHandle *h = handle(ph);
  if (!h) return;
  const int want = on ? 1 : 0;
  if (want == h->painting) return;
  h->painting = want;
  claim_output(h, want);
}

JNIEXPORT jlongArray JNICALL Java_Render_inputMode(JNIEnv *env, jclass cls, jlong ph)
{
  (void)cls;
  RcHandle *h = handle(ph);
  jlong out[10] = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 };
  if (h)
  {
    out[1] = (jlong)h->inBase;
    out[2] = h->inSaved;
    out[3] = h->inArmed;
    out[4] = h->g ? (jlong)h->g->carried.mouseModes : 0;
    unsigned long rc[5];
    rc_report_counts(h->g, rc);
    for (int i = 0; i < 5; i++) out[5 + i] = (jlong)rc[i];
    HANDLE q = h->in;
    if (q == INVALID_HANDLE_VALUE)
      q = CreateFileW(L"CONIN$", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
    if (q != INVALID_HANDLE_VALUE)
    {
      DWORD m = 0;
      if (GetConsoleMode(q, &m)) out[0] = (jlong)m;
      if (h->in == INVALID_HANDLE_VALUE) CloseHandle(q);
    }
  }
  jlongArray arr = env->NewLongArray(10);
  if (arr) env->SetLongArrayRegion(arr, 0, 10, out);
  return arr;
}

JNIEXPORT jlongArray JNICALL Java_Render_outputMode(JNIEnv *env, jclass cls, jlong ph)
{
  (void)cls;
  RcHandle *h = handle(ph);
  jlong out[4] = { 0, 0, 0, 0 };
  HANDLE con = (h && h->con != INVALID_HANDLE_VALUE) ? h->con
               : CreateFileW(L"CONOUT$", GENERIC_READ | GENERIC_WRITE,
                             FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
  if (con != INVALID_HANDLE_VALUE)
  {
    DWORD m = 0;
    if (GetConsoleMode(con, &m)) out[0] = (jlong)m;
    if (!h || h->con == INVALID_HANDLE_VALUE) CloseHandle(con);
  }
  if (h)
  {
    out[1] = (jlong)h->outBase;
    out[2] = h->outSaved;
    out[3] = h->outClaimed;
  }
  jlongArray arr = env->NewLongArray(4);
  if (arr) env->SetLongArrayRegion(arr, 0, 4, out);
  return arr;
}

JNIEXPORT jint JNICALL Java_Render_prepareConsole(JNIEnv *env, jclass cls)
{
  HANDLE std_out = GetStdHandle(STD_OUTPUT_HANDLE);
  if (GetFileType(std_out) == FILE_TYPE_PIPE)
  {
    FreeConsole();
    if (!AllocConsole()) return 0;
    HWND hwnd = GetConsoleWindow();
    if (hwnd) ShowWindow(hwnd, SW_HIDE);
  }
  return 1;
}

JNIEXPORT jint JNICALL Java_Render_setGeometry(JNIEnv *env, jclass cls, jint bufW, jint bufH,
                                               jint winW, jint winH, jint attr)
{
  HANDLE con = CreateFileW(L"CONOUT$", GENERIC_READ | GENERIC_WRITE,
                           FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
  if (con == INVALID_HANDLE_VALUE) return 0;
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
  SetConsoleTextAttribute(con, (WORD)attr);
  size.X = 0;
  size.Y = 0;
  SetConsoleCursorPosition(con, size);
  CloseHandle(con);
  return ok ? 1 : 0;
}

JNIEXPORT jlongArray JNICALL Java_Render_consoleView(JNIEnv *env, jclass cls)
{
  jlong out[9];
  memset(out, 0, sizeof out);
  HANDLE con = CreateFileW(L"CONOUT$", GENERIC_READ | GENERIC_WRITE,
                           FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
  if (con != INVALID_HANDLE_VALUE)
  {
    RcView v;
    CONSOLE_SCREEN_BUFFER_INFO csbi;
    if (view_of(con, &v, &csbi))
    {
      out[0] = v.winT; out[1] = v.winL; out[2] = v.bufW; out[3] = v.bufH;
      out[4] = v.attr; out[5] = v.curX; out[6] = v.curY; out[7] = v.cursorOn; out[8] = v.winB;
    }
    CloseHandle(con);
  }
  jlongArray arr = env->NewLongArray(9);
  if (arr) env->SetLongArrayRegion(arr, 0, 9, out);
  return arr;
}

JNIEXPORT jlongArray JNICALL Java_Render_readCells(JNIEnv *env, jclass cls, jint x, jint y,
                                                   jint w, jint h)
{
  if (w <= 0 || h <= 0 || w * h > READ_MAX_CELLS) return NULL;
  HANDLE con = CreateFileW(L"CONOUT$", GENERIC_READ | GENERIC_WRITE,
                           FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
  if (con == INVALID_HANDLE_VALUE) return NULL;
  CHAR_INFO buf[READ_MAX_CELLS];
  memset(buf, 0, (size_t)(w * h) * sizeof(buf[0]));
  COORD size, coord;
  SMALL_RECT rect;
  size.X = (SHORT)w;
  size.Y = (SHORT)h;
  coord.X = 0;
  coord.Y = 0;
  rect.Left = (SHORT)x;
  rect.Right = (SHORT)(x + w - 1);
  rect.Top = (SHORT)y;
  rect.Bottom = (SHORT)(y + h - 1);
  BOOL ok = ReadConsoleOutputW(con, buf, size, coord, &rect);
  CloseHandle(con);
  if (!ok) return NULL;
  jlongArray out = env->NewLongArray(w * h);
  if (!out) return NULL;
  jlong *vals = (jlong *)env->GetPrimitiveArrayCritical(out, NULL);
  if (!vals) { env->DeleteLocalRef(out); return NULL; }
  for (int i = 0; i < w * h; i++)
    vals[i] = (jlong)((unsigned)CH_UNICODE(buf[i]) | ((unsigned)buf[i].Attributes << 16));
  env->ReleasePrimitiveArrayCritical(out, vals, 0);
  return out;
}

JNIEXPORT jcharArray JNICALL Java_Render_consoleTitle(JNIEnv *env, jclass cls)
{
  (void)cls;
  wchar_t t[512];
  memset(t, 0, sizeof t);
  SetLastError(0);
  const DWORD n = GetConsoleTitleW(t, (DWORD)(sizeof t / sizeof t[0]));
  if (n == 0 && GetLastError() != ERROR_SUCCESS) return NULL;
  jcharArray a = env->NewCharArray((jsize)n);
  if (!a) return NULL;
  jchar *p = (jchar *)env->GetPrimitiveArrayCritical(a, NULL);
  if (!p) { env->DeleteLocalRef(a); return NULL; }
  for (DWORD i = 0; i < n; i++) p[i] = (jchar)t[i];
  env->ReleasePrimitiveArrayCritical(a, p, 0);
  return a;
}

JNIEXPORT jcharArray JNICALL Java_Render_readInput(JNIEnv *env, jclass cls, jint max)
{
  (void)cls;
  wchar_t txt[512];
  int n = 0;
  if (max > (int)(sizeof txt / sizeof txt[0])) max = (int)(sizeof txt / sizeof txt[0]);
  HANDLE in = CreateFileW(L"CONIN$", GENERIC_READ | GENERIC_WRITE,
                          FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
  if (in == INVALID_HANDLE_VALUE) return NULL;
  INPUT_RECORD rec[256];
  DWORD avail = 0, got = 0;
  if (PeekConsoleInputW(in, rec, 256, &avail) && avail > 0 &&
      ReadConsoleInputW(in, rec, avail < 256 ? avail : 256, &got))
  {
    for (DWORD i = 0; i < got && n < max; i++)
      if (rec[i].EventType == KEY_EVENT && rec[i].Event.KeyEvent.bKeyDown) txt[n++] = rec[i].Event.KeyEvent.uChar.UnicodeChar;
  }
  CloseHandle(in);
  jcharArray a = env->NewCharArray(n);
  if (!a) return NULL;
  if (n > 0)
  {
    jchar *p = (jchar *)env->GetPrimitiveArrayCritical(a, NULL);
    if (p) { for (int i = 0; i < n; i++) p[i] = (jchar)txt[i]; env->ReleasePrimitiveArrayCritical(a, p, 0); }
  }
  return a;
}

static jcharArray report_result(JNIEnv *env, RcHandle *h, const uint16_t *txt, int n, int inject)
{
  if (inject && n > 0)
  {
    if (h->in == INVALID_HANDLE_VALUE)
      h->in = CreateFileW(L"CONIN$", GENERIC_READ | GENERIC_WRITE,
                          FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
    int took = 0;
    if (h->in != INVALID_HANDLE_VALUE)
    {
      wchar_t w[48];
      int i;
      for (i = 0; i < n && i < (int)(sizeof w / sizeof w[0]); i++) w[i] = (wchar_t)txt[i];
      took = write_input_units(h, w, i);
    }
    if (took) h->g->nInjectOk++;
    else
    {
      h->g->nInjectFail++;
      snprintf(h->lastError, sizeof h->lastError, "inject=%lu", (unsigned long)GetLastError());
      h->nApiErrors++;
    }
  }
  jcharArray a = env->NewCharArray(n);
  if (!a) return NULL;
  if (n > 0)
  {
    jchar *p = (jchar *)env->GetPrimitiveArrayCritical(a, NULL);
    if (p) { for (int i = 0; i < n; i++) p[i] = (jchar)txt[i]; env->ReleasePrimitiveArrayCritical(a, p, 0); }
  }
  return a;
}

JNIEXPORT jcharArray JNICALL Java_Render_mouseReport(JNIEnv *env, jclass cls, jlong ph, jint x, jint y,
                                                     jint px, jint py, jint buttonState, jint eventFlags,
                                                     jint ctrlKeyState, jint inject)
{
  (void)cls;
  RcHandle *h = handle(ph);
  if (!h || !h->g) return NULL;
  struct RcMouseRec m;
  m.x = (int16_t)x; m.y = (int16_t)y; m.px = (int16_t)px; m.py = (int16_t)py;
  m.buttonState = (uint32_t)buttonState; m.eventFlags = (uint32_t)eventFlags;
  m.ctrlKeyState = (uint16_t)ctrlKeyState;
  uint16_t txt[48];
  const int n = rc_mouse_report(h->g, &m, txt, (int)(sizeof txt / sizeof txt[0]));
  if (n < 0) return NULL;
  return report_result(env, h, txt, n, inject);
}

JNIEXPORT jcharArray JNICALL Java_Render_focusReport(JNIEnv *env, jclass cls, jlong ph, jint focused, jint inject)
{
  (void)cls;
  RcHandle *h = handle(ph);
  if (!h || !h->g) return NULL;
  uint16_t txt[8];
  const int n = rc_focus_report(h->g, focused, txt, (int)(sizeof txt / sizeof txt[0]));
  if (n < 0) return NULL;
  return report_result(env, h, txt, n, inject);
}

JNIEXPORT jint JNICALL Java_Render_readopt(JNIEnv *env, jclass cls, jlong ph)
{
  (void)env; (void)cls;
  RcHandle *h = slot_of(ph);
  if (!h) return 0;
  int status = OPEN_OK;
  return readopt(h, &status) ? 1 : 0;
}

JNIEXPORT jlongArray JNICALL Java_Render_plan(JNIEnv *env, jclass cls, jlong ph)
{
  (void)cls;
  RcHandle *h = slot_of(ph);
  jlong out[19];
  memset(out, 0, sizeof out);
  if (h)
  {
    out[0] = h->trSeq; out[1] = h->trReason; out[2] = h->trBaseSet; out[3] = h->trBaseRow;
    out[4] = h->trWinT; out[5] = h->trBase; out[6] = h->trSlide; out[7] = h->trSlideTo;
    out[8] = h->trBufScroll; out[9] = h->trRow0; out[10] = h->trWinTop; out[11] = h->trRows;
    out[12] = h->trWinRows; out[13] = h->trBufH; out[14] = h->trPend; out[15] = h->trRuns;
    out[16] = h->trDeclined; out[17] = h->trMoveFail; out[18] = (jlong)h->trCells;
  }
  jlongArray arr = env->NewLongArray(19);
  if (arr) env->SetLongArrayRegion(arr, 0, 19, out);
  return arr;
}

typedef BOOL (WINAPI *WriteProcessed3Fn)(LPCWSTR, DWORD, LPDWORD, HANDLE);

JNIEXPORT jint JNICALL Java_Render_faultRect(JNIEnv *env, jclass cls, jlong ph, jint run)
{
  (void)env; (void)cls;
  RcHandle *h = slot_of(ph);
  if (!h) return -2;
  h->faultRun = (int)run;
  return h->faultRun;
}

JNIEXPORT jint JNICALL Java_Render_writeHk(JNIEnv *env, jclass cls, jcharArray text, jint len, jstring dll)
{
  (void)cls;
  static WriteProcessed3Fn fn = NULL;
  static HMODULE mod = NULL;

  if (!dll) return -1;
  const jchar *path = env->GetStringChars(dll, NULL);
  if (!path) return -1;
  wchar_t wpath[MAX_PATH];
  int n = 0;
  for (; n < MAX_PATH - 1 && path[n]; n++) wpath[n] = (wchar_t)path[n];
  wpath[n] = 0;
  env->ReleaseStringChars(dll, path);

  if (!fn)
  {
    mod = LoadLibraryW(wpath);
    if (!mod) return -2;
    fn = (WriteProcessed3Fn)(void *)GetProcAddress(mod, "WriteProcessed3");
    if (!fn) { FreeLibrary(mod); mod = NULL; return -3; }
  }
  if (!text || len <= 0) return 0;

  const jchar *chars = (const jchar *)env->GetPrimitiveArrayCritical(text, NULL);
  if (!chars) return -4;
  HANDLE con = CreateFileW(L"CONOUT$", GENERIC_READ | GENERIC_WRITE,
                           FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
  if (con == INVALID_HANDLE_VALUE) { env->ReleasePrimitiveArrayCritical(text, (void *)chars, 0); return -5; }
  DWORD written = 0;
  const BOOL ok = fn((LPCWSTR)chars, (DWORD)len, &written, con);
  CloseHandle(con);
  env->ReleasePrimitiveArrayCritical(text, (void *)chars, 0);
  return ok ? (jint)written : (jint)-6;
}

JNIEXPORT jint JNICALL Java_Render_consolePalette(JNIEnv *env, jclass cls, jlongArray out)
{
  (void)cls;
  CONSOLE_SCREEN_BUFFER_INFOEX ex;
  memset(&ex, 0, sizeof ex);
  ex.cbSize = sizeof ex;
  HANDLE con = CreateFileW(L"CONOUT$", GENERIC_READ | GENERIC_WRITE,
                           FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
  if (con == INVALID_HANDLE_VALUE) return -1;
  const BOOL ok = GetConsoleScreenBufferInfoEx(con, &ex);
  CloseHandle(con);
  if (!ok) return -2;
  if (!out || env->GetArrayLength(out) < 16) return -3;
  jlong *v = (jlong *)env->GetPrimitiveArrayCritical(out, NULL);
  if (!v) return -4;
  for (int i = 0; i < 16; i++) v[i] = (jlong)(unsigned long)ex.ColorTable[i];
  env->ReleasePrimitiveArrayCritical(out, v, 0);
  return 16;
}

JNIEXPORT jobjectArray JNICALL Java_Render_censusNames(JNIEnv *env, jclass cls)
{
  (void)cls;
  const int n = rc_census_count();
  jclass str = env->FindClass("java/lang/String");
  if (str == NULL) return NULL;
  jobjectArray out = env->NewObjectArray(n, str, NULL);
  if (out == NULL) return NULL;
  for (int i = 0; i < n; i++)
  {
    char one[64];
    const char *nm = rc_census_name(i);
    sprintf(one, "%s|%d", nm ? nm : "?", rc_census_suspect(i));
    jstring s = env->NewStringUTF(one);
    if (s == NULL) return NULL;
    env->SetObjectArrayElement(out, i, s);
    env->DeleteLocalRef(s);
  }
  return out;
}

JNIEXPORT jstring JNICALL Java_Render_validateGrid(JNIEnv *env, jclass cls, jlong ph)
{
  (void)cls;
  RcHandle *h = slot_of(ph);
  char msg[256];
  if (h == NULL || h->g == NULL) return env->NewStringUTF("(no model behind this handle)");
  if (!rc_validate_grid(h->g, msg, (int) sizeof msg)) return env->NewStringUTF("");
  return env->NewStringUTF(msg);
}

JNIEXPORT jlong JNICALL Java_Render_argTrunc(JNIEnv *env, jclass cls, jlong ph)
{
  (void)env; (void)cls;
  RcHandle *h = slot_of(ph);
  return (jlong)(h && h->g ? (long)h->g->nArgTrunc : -1);
}

}

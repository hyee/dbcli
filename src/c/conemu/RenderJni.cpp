/*
 * RenderJni.cpp -- the Windows half of the native renderer: hold a model, parse UTF-16 into it, and
 * execute rc_plan_paint's operation list against a real screen buffer.
 *
 * Two layers live here, and the line between them is "what to paint" versus "when to trust the model".
 * Which rows to write, how wide, whether the window slides or the buffer scrolls, when to touch the
 * attribute -- every one of those decisions is made in Paint.cpp and pinned by RenderCheck's section 6,
 * because they can be enumerated without a console. What this file adds is the translation into API calls
 * plus the two questions only a console can answer: what shape it has right now, and what it actually
 * contains when we take it over.
 *
 * render() is production's only entry point and it owns the whole per-chunk policy: adopt the console on
 * the first chunk, re-adopt it after a geometry change, stop asking after a run of declines, and say why
 * when it gives up. Everything below that -- open/feed/flush/align/stats/close -- is the same machinery
 * with the policy taken out, for the console gate in Render.java, which has to drive one paint at a time
 * and read the reason for every decline. Both layers keep the promise the writer is built on:
 *   - a decline means *nothing was written*, so the caller may put the same bytes in front of the console
 *     itself without duplicating them;
 *   - a failure after the first rectangle landed is therefore never turned into a decline, because
 *     replaying those bytes would print the text twice -- the lesson paid for in §14.2A. A chunk that
 *     painted part of itself is consumed, and the console is re-adopted before the next one.
 *
 * align() is how the model gets a starting point: it reads the window's cells out of the console and
 * adopts the cursor and attribute. It is called once when the renderer takes over and again whenever the
 * console's shape no longer matches the model's -- which needs a fresh model as well, since align()
 * refuses a window of a different size. Neither touches the parser state, so a sequence split across the
 * boundary still completes.
 *
 * Toolchain notes already paid for elsewhere and respected here: JNIEnv is a reference in C++
 * (env->Method()); mingw-w64 spells the CHAR_INFO member UnicodeChar; x86 exports must be undecorated
 * (--kill-at) or HotSpot loads the DLL and then never binds; nothing here may be a Win8+ entrypoint.
 */

#include <jni.h>
#include <windows.h>

#include <stdlib.h>
#include <string.h>

#include "Paint.h"
#include "Render.h"

/* The build's name tag: A/B legs print it, and the control legs rewrite it (make-control*.sh finds this
 * line by prefix), so it is how a log says *which* bytes ran. Bump it whenever shipped code changes --
 * md5 cannot play that role, since two links of one source differ (§9). B2 (I22) is -4; the alternate
 * screen (I24) starts at render-2026-09-24-1.  -2 is the pair that actually carries the -1 features: the
 * DLLs in lib\ were linked before DECSTBM and OSC 133 landed, so their .text said -1 while the source
 * under that name had moved on (x86 47,796 B vs 51,316 B). -3 is the chunk policy moving out of Java:
 * render() now owns adopt / re-adopt / give-up, which is what let the ConEmuHk leg be retired. -4 is what
 * that move made necessary: a slot is claimed by a `taken` flag rather than by having a grid, so a renderer
 * that gave up keeps its handle (and its stopReason) until the caller closes it, and stats() reads that
 * handle -- the sequence census outlives the model, which is the only record a private OSC ever went past.
 * -5 is the width table: `ansi_width_tables.h` was regenerated with the ambiguous ruling (EAW=A counts 2,
 * the 206 measured-narrow code points excepted), and that table is compiled into this DLL, so a -4 binary
 * in lib\ and a -4 source tree are two different models of the screen -- the same trap -2 was named for.
 * -6 is the line feed below a narrowed scroll region: it walks the cursor down instead of rotating the
 * region, which is what a two-row status line needs (Render.cpp line_down; MSFT adaptDispatch.cpp:2443
 * scrolls only at `y == bottomMargin`). A -5 binary and a -6 tree disagree about every row above the bar.
 * -7 closes two census holes that left no number at all: `CSI p` (every spelling but the one DECSTR gates
 * on) and `ESC ) c` / `ESC % c` fell to a bare `break`. Nothing on the screen moves, so this pair is
 * visible only in the stats line -- which is the whole reason it counts as a shipped change. */
#define RENDER_BUILD "render-2026-09-24-7"
#define READ_MAX_CELLS 4096        /* the gate-only cell reader, same bound as Probe.cpp */

/* flush() results. Zero or positive means the chunk is consumed -- the caller must not replay it;
 * negative means nothing landed and the caller puts the *same* bytes in front of the console itself. */
enum
{
  FLUSH_PAINTED = 0,
  FLUSH_NOTHING = 1,               /* nothing damaged: at most a cursor call was made */
  /* The chunk is in the console, but a later part of it could not be: a resize raced with the paint.
     Replaying would print the text twice, so the caller keeps its raw leg out of it and simply re-adopts
     the console before the next chunk. */
  FLUSH_RESYNC = 2,
  FLUSH_NOGEOM = -1,               /* the console's shape is not the model's: re-adopt */
  /* -2 was FLUSH_WIDE: a buffer row longer than the scratch. The model row IS a buffer row now, so the
     only width that can reach the painter is one the grid was built for, and open() refuses anything
     wider. The value stays out of service rather than being given a second meaning. */
  FLUSH_API = -3                   /* a console call failed before anything landed */
};

/* render() results -- the whole vocabulary production sees. 0 and -1 both mean "these bytes are still
 * unwritten, put them on the console yourself"; -1 adds that the renderer is not going to try again,
 * which is what stopReason() explains. Keeping them distinct is what lets the writer report a stop once
 * instead of once per chunk. */
enum
{
  RENDER_GIVEUP = -1,
  RENDER_RAW = 0,
  RENDER_PAINTED = 1
};

/* Consecutive declines after which the model stops being asked. One decline is normal (a resize); a long
 * run means the console is not behaving the way the model expects, and every attempt costs a parse plus a
 * window read. Only a chunk that actually painted breaks the run -- re-adopting in between does not, or
 * the cap would never fire during the one situation it is for: a window whose shape keeps moving under
 * the painter. This is the number Java used to own. */
#define RENDER_MAX_DECLINES 16

/* render()'s three adopt states. A decline is the interesting one: the caller is about to put bytes in
 * front of the console that this model never painted, and the console may then hold a screen the model has
 * no idea about -- including an *emulated* alternate screen, which is model state with no console
 * equivalent. Aligning into that model would keep believing it; rebuilding forgets the alt screen and takes
 * the console as the truth, which is the only claim a fresh align can actually support. */
enum
{
  RC_REBUILD = -1,                   /* throw the model away and build one for the console's shape */
  RC_ALIGN   = 0,                    /* adopt by reading the console into the model we have */
  RC_ADOPTED = 1
};

/* open() sentinels: a shape of 0 means "ask the console", a default attribute of -1 means the live one.
   0x0000 is a legal attribute, so it cannot double as "unset". */
#define OPEN_ASK_SHAPE 0
#define OPEN_ASK_ATTR  (-1)

/* Why open() returned 0, so the caller can say why the fast path is off rather than only that it is. */
enum
{
  OPEN_OK = 0, OPEN_NO_CONSOLE = 1, OPEN_BIG = 2,
  OPEN_WIDE = 3,                   /* the buffer row is wider than RC_MAX_COLS: the model cannot hold a line */
  OPEN_NO_GUTTER = 4, OPEN_OOM = 5
};

/* stats() slots. 17.. is one per member of `enum RcUnsupported` in its own order, and the three slots
 * after that family are the title counters. Growing the family moves the titles, which is why they are
 * derived rather than written out: the Java binding (NativeRenderer.java) and the gate (Render.java) both name slot numbers, and
 * the gate prints both ends of that seam in one run so a slip cannot go unnoticed. The alt counters come
 * after the titles and the FTCS counters after those, and both are new slots -- never a moved one. */
#define STAT_UNSUPPORTED 17
#define STAT_TITLES      (STAT_UNSUPPORTED + RC_UN_MAX)
#define STAT_ALT         (STAT_TITLES + 3)
#define STAT_PROMPT      (STAT_ALT + 2)
#define STAT_LAST        (STAT_PROMPT + 2)

#ifdef __MINGW32__
#define CH_UNICODE(ci) ((ci).Char.UnicodeChar)
#else
#define CH_UNICODE(ci) ((ci).Char.Unicode)
#endif

typedef struct RcHandle
{
  RcGrid *g;                       /* NULL once the model has been given up on */
  /* Whether this slot is somebody's handle. It is not the same question as "does it have a model": a
     renderer that gave up mid-session keeps its slot, its stopped[] sentence and its counters, and until
     it closes a second open() must not be handed that pointer and take its console. */
  int taken;
  CHAR_INFO *cells;                /* paintCols * rows, reused across flushes */
  int ncells;
  HANDLE con;                      /* CONOUT$, or the handle the caller passed */
  int ownsCon;                     /* only a handle we opened here may be closed here */
  uint16_t defAttr;
  /* Content from this chunk has reached the console, so a later decline in the same chunk must not send
     the caller back to a raw write with the same bytes: that is how text gets painted twice. */
  int landedChunk;
  /* render()'s own state. `adopt` is one of RC_* above -- RC_ADOPTED between chunks, and whatever the last
     one left when the console moved or a chunk went unpainted; `declines` counts the run capped by
     RENDER_MAX_DECLINES; `stopped` is why the model is gone, and it is the only string here the caller
     ever reads back. */
  int adopt, declines;
  char stopped[128];
  unsigned long nFlush, nPaints, nDeclines, nApiErrors, nAligns;
  int lastReason;
  char lastError[128];
} RcHandle;

static RcHandle g_h[4];
static int g_openStatus;           /* the last open() failure, for the caller's diagnostics */

/* What the byte stream asked for, over the life of the process: folded in at close() from the model that
 * read it. The categories are about the stream and not about a model, and a resize re-opens the model
 * mid-session -- an alt buffer request or a ConEmu macro that vanished from the report at that moment is
 * exactly the evidence the rollout gate is supposed to gather; the alt switches need this more than most,
 * because the whole point of counting them is "did this session run a full-screen program", which a resize
 * in the middle of `less` would otherwise erase. The prompt marks fold for the same reason and are the
 * cheapest way to tell "the shell emits OSC 133" from "this session's output did not ask for it".
 *
 * The titles *applied* counter is process-wide for the same reason and by a different route: it is
 * incremented where the call is made, and it has to be comparable with the titles parsed.
 * Plain += on diagnostics: this is the same exposure the existing g_openStatus
 * already has, and no painting reads it. */
static unsigned long g_totUn[RC_UN_MAX], g_totTitle, g_totTitleTrunc, g_titleCalls,
                     g_totAltSwitch, g_totAltFail, g_totPromptMark;

/* Is this pointer one of our slots, and still claimed? The claim is what makes junk pointers and
   already-closed ones the same case: both answer NULL, and no call dereferences anything. A renderer that
   has given up is still claimed -- it has a stopReason() the caller has to read before it closes. */
static RcHandle *slot_of(jlong p)
{
  RcHandle *h = (RcHandle *)(void *)p;
  return (h >= g_h && h < g_h + (int)(sizeof g_h / sizeof g_h[0]) && h->taken) ? h : NULL;
}

/* A claimed slot that still has a model, which is what the layer-by-call gate drives: feed, flush, sgr and
   align all dereference the grid. render() uses slot_of() instead, because it has to distinguish "the
   caller's pointer is junk" (write the bytes yourself) from "the renderer stopped, and here is why". */
static RcHandle *handle(jlong p)
{
  RcHandle *h = slot_of(p);
  return (h && h->g) ? h : NULL;
}

/* ------------------------------------------------------------------ JNI plumbing --------------- */

static const char *copyChars(JNIEnv *env, jcharArray text, jint off, jint len, uint16_t **out)
{
  if (!text || len <= 0) return "empty";
  if (off < 0 || len > (jint)(env->GetArrayLength(text) - off)) return "bounds";
  jchar *p = (jchar *)env->GetPrimitiveArrayCritical(text, NULL);
  if (!p) return "critical";
  *out = (uint16_t *)p;            /* Java char[] is already the console's encoding: no transcode */
  (void)off;
  return NULL;
}

/* ------------------------------------------------------------- the console view ---------------- */

static int view_of(HANDLE con, RcView *v, CONSOLE_SCREEN_BUFFER_INFO *csbi)
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

/* One row of one run, built into `dst`, which is `hi-lo+1` cells wide. The model row already IS the
 * buffer row, so the columns right of the window are ordinary cells and we have them; the run's range is
 * only about which of them this frame has to move. */
static void build_row(const RcGrid *g, int row, int lo, int hi, CHAR_INFO *dst)
{
  const RcCell *src = g->cells[row];
  for (int c = lo; c <= hi; c++)
  {
    dst[c - lo].Attributes = src[c].attr;
    CH_UNICODE(dst[c - lo]) = src[c].ch;
  }
}

static LONG write_rect(HANDLE con, const RcView *v, const RcPlan *p, int top, int nrows,
                       int lo, int hi, const CHAR_INFO *cells)
{
  COORD size, coord;
  SMALL_RECT rect;
  size.X = (SHORT)(hi - lo + 1);
  size.Y = (SHORT)nrows;
  coord.X = 0;
  coord.Y = 0;                      /* convention 1: absolute window rect, origin-typed buffer */
  rect.Left = (SHORT)(v->winL + lo);
  rect.Right = (SHORT)(v->winL + hi);
  rect.Top = (SHORT)(p->row0 + top);
  rect.Bottom = (SHORT)(p->row0 + top + nrows - 1);
  SetLastError(0);
  return WriteConsoleOutputW(con, cells, size, coord, &rect) ? 0L : (LONG)GetLastError();
}

static LONG scroll_buffer(HANDLE con, const RcView *v, int by, uint16_t attr)
{
  CHAR_INFO fill;
  COORD dest;
  SMALL_RECT whole;
  memset(&fill, 0, sizeof fill);
  fill.Attributes = attr;
  CH_UNICODE(fill) = ' ';
  dest.X = 0;
  dest.Y = (SHORT)(-by);
  whole.Left = 0;
  whole.Top = 0;
  whole.Right = (SHORT)(v->bufW - 1);
  whole.Bottom = (SHORT)(v->bufH - 1);
  SetLastError(0);
  return ScrollConsoleScreenBufferW(con, &whole, NULL, dest, &fill) ? 0L : (LONG)GetLastError();
}

static LONG park_cursor(HANDLE con, int x, int y)
{
  COORD c;
  c.X = (SHORT)x;
  c.Y = (SHORT)y;
  SetLastError(0);
  return SetConsoleCursorPosition(con, c) ? 0L : (LONG)GetLastError();
}

/* ------------------------------------------------------------------ one paint ------------------ */

/* Execute the pending plan. Needs no JNIEnv, because rc_feed() can ask for it in the middle of a
 * chunk: see the onFlush hook in Render.h. Returns one of the FLUSH_* codes. */
static int paint_flush(RcHandle *h)
{
  RcGrid *g = h->g;
  RcView v;
  RcPlan p;
  CONSOLE_SCREEN_BUFFER_INFO csbi;

  /* A decline is only safe while the console still says what the previous flush said it would. Nothing
     here has to leave the alt screen first, and adding that would be wrong: a decline means these bytes
     were not painted but *were* parsed, so the caller puts them in front of the console unparsed -- which
     is exactly when the emulated alt screen stops being a claim anyone can support. render() answers by
     rebuilding the model rather than re-aligning it, and the console's own screen becomes the truth. A
     restore of the model's snapshot into a console that has its own idea of that screen would be the one
     thing guaranteed to disagree with it. */
#define DECLINE(code) do { h->nDeclines++; if (h->landedChunk) { h->lastReason = p.reason; return FLUSH_RESYNC; } \
                           return (code); } while (0)

  if (h->con == INVALID_HANDLE_VALUE || !view_of(h->con, &v, &csbi))
  {
    snprintf(h->lastError, sizeof h->lastError, "flush: no console (%lu)", (unsigned long)GetLastError());
    g->pendingScrolls = 0;
    rc_mark_all_dirty(g);
    return FLUSH_API;
  }
  rc_plan_paint(g, &v, &p);
  h->lastReason = p.reason;
  h->nFlush++;

  if (p.reason == RC_PLAN_NOGEOM) DECLINE(FLUSH_NOGEOM);

  int landed = h->landedChunk;

  /* Order is the plan's: slide, then scroll, then cells. Any other order moves the wrong rows. */
  if (p.slideTo >= 0)
  {
    LONG e = park_cursor(h->con, v.winL, p.slideTo);
    if (e) { snprintf(h->lastError, sizeof h->lastError, "slide=%ld", e); h->nApiErrors++; }
    else { landed = 1; h->landedChunk = 1; }
  }
  if (p.bufScroll > 0)
  {
    LONG e = scroll_buffer(h->con, &v, p.bufScroll, p.scrollAttr);
    if (e)
    {
      snprintf(h->lastError, sizeof h->lastError, "scroll=%ld", e);
      h->nApiErrors++;
      if (!landed) DECLINE(FLUSH_API);
    }
    else { landed = 1; h->landedChunk = 1; }
  }

  if (p.nRuns > 0)
  {
    const int need = p.paintCols * g->rows;   /* the ceiling: one run over every row at full width */
    if (need > h->ncells)
    {
      CHAR_INFO *fresh = (CHAR_INFO *)realloc(h->cells, (size_t)need * sizeof(CHAR_INFO));
      if (!fresh)
      {
        snprintf(h->lastError, sizeof h->lastError, "scratch %d cells", need);
        h->nApiErrors++;
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
        /* The scratch holds one run at a time, stride the run's own width: WriteConsoleOutputW reads it
           as an nrows x w array, so any other stride shifts every row after the first. */
        for (int r = 0; r < nrows; r++)
          build_row(g, top + r, lo, hi, h->cells + (size_t)r * w);
        LONG e = write_rect(h->con, &v, &p, top, nrows, lo, hi, h->cells);
        if (e)
        {
          snprintf(h->lastError, sizeof h->lastError, "rect r%d x%d c%d..%d =%ld", top, nrows, lo, hi, e);
          h->nApiErrors++;
          break;                       /* the row below would land in the wrong place: stop */
        }
        landed = 1;
        h->landedChunk = 1;
        h->nPaints++;
      }
    }
  }

  if (p.attrChanged) SetConsoleTextAttribute(h->con, (WORD)p.attr);
  if (p.setVisible || p.setShape)
  {
    /* One call for both, because both are the same CONSOLE_CURSOR_INFO: visibility is what ?25h/l has
       always driven here, and the height is what DECSCUSR can honestly mean on a console this build may
       talk to (Paint.cpp::cursor_height; ConEmu makes the same two-way reduction at Ansi.cpp:3677). The
       height is only written when the plan says it disagrees, so a session that never asked keeps whatever
       the user set. */
    CONSOLE_CURSOR_INFO ci;
    memset(&ci, 0, sizeof ci);
    if (GetConsoleCursorInfo(h->con, &ci))
    {
      if (p.setVisible) ci.bVisible = p.cursorVisible ? TRUE : FALSE;
      if (p.setShape) ci.dwSize = (DWORD)p.shapeHeight;
      SetConsoleCursorInfo(h->con, &ci);
    }
  }
  if (p.cursorMoved)
  {
    LONG e = park_cursor(h->con, p.curTX, p.curTY);
    if (e) { snprintf(h->lastError, sizeof h->lastError, "cursor=%ld", e); h->nApiErrors++; }
  }

  /* The window title, last: it is the one effect of a chunk that lives outside the screen buffer, so a
     failure here cannot spoil a rectangle and is counted as an API error rather than declined. ConEmu's own
     parser applies the title where it parses the OSC (Ansi.cpp:3851), which is the parity this restores --
     and it is why a title whose OSC never terminated is dropped in the parser rather than applied from
     here. */
  if (rc_title_pending(g))
  {
    wchar_t t[RC_TITLE_MAX + 1];
    const int n = rc_title_take(g, (uint16_t *)t, RC_TITLE_MAX);
    if (n < 0) h->nApiErrors++;                   /* cannot happen: RC_TITLE_MAX is the model's own cap */
    else
    {
      t[n] = 0;
      if (SetConsoleTitleW(t)) g_titleCalls++;
      else { snprintf(h->lastError, sizeof h->lastError, "title=%lu", (unsigned long)GetLastError()); h->nApiErrors++; }
    }
  }

  rc_paint_done(g);
#undef DECLINE
  if (!landed && p.reason == RC_PLAN_EMPTY) return FLUSH_NOTHING;
  return FLUSH_PAINTED;
}

/* The hook rc_feed() calls when the gutter fills. A decline means the model no longer describes the
 * console, and retrying once per line for the rest of the chunk buys nothing -- so mid-chunk painting
 * is switched off until the next adopt re-arms it, and the chunk's final paint reports the decline (its
 * plan is unchanged). The rows the disabled hook would have painted are lost from the gutter, which is the
 * same thing a raw write of those bytes would have done with them: render() rebuilds before the next one. */
static void flush_now(void *ctx)
{
  RcHandle *h = (RcHandle *)ctx;
  if (paint_flush(h) < 0) h->g->onFlush = NULL;
}

/* ------------------------------------------------------- the chunk policy (was Java) ---------- */

extern "C" {                    /* the same language linkage as its definition below the exports */
static int align_grid(RcHandle *h);
}

/* What the byte stream asked for, over the life of the process, folded in from the model that read it.
 * See g_tot* above for why these are not per-model. Idempotent on a handle with no model, which is what
 * makes give_up() followed by the caller's close() a fold of one, not of two. */
static void fold_counters(RcHandle *h)
{
  if (!h->g) return;
  for (int i = 0; i < RC_UN_MAX; i++) g_totUn[i] += h->g->nUnsupported[i];
  g_totTitle += h->g->nTitleSet;
  g_totTitleTrunc += h->g->nTitleTrunc;
  g_totAltSwitch += h->g->nAltSwitch;
  g_totAltFail += h->g->nAltFail;
  g_totPromptMark += h->g->nPromptMark;
}

static void drop_model(RcHandle *h)
{
  fold_counters(h);
  if (!h->g) return;
  free(h->g->snap);                   /* the alt screen's saved viewport, if it was ever entered */
  free(h->g);
  h->g = NULL;
}

/* Everything the handle owns, including a console we opened ourselves. The paint scratch goes too: with no
   model there is nothing left to paint, and a buffer of CHAR_INFO held by a dead slot is exactly the kind
   of leak a long session remembers. */
static void release_all(RcHandle *h)
{
  drop_model(h);
  free(h->cells);
  h->cells = NULL;
  h->ncells = 0;
  if (h->con != INVALID_HANDLE_VALUE && h->ownsCon) CloseHandle(h->con);
  h->con = INVALID_HANDLE_VALUE;
  h->ownsCon = 0;
  h->taken = 0;                          /* last: until here the slot still answers its own pointer */
}

/* One describable refusal, worded the same way whether it came from open() or from a re-adopt in the
 * middle of a session: the caller shows the user a sentence, and two tables would be two chances for that
 * sentence to be wrong. */
static const char *open_name(int status)
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

/* Give the handle a model for `cols` x `rows` with a `rows`-tall scroll gutter (clipped to RC_MAX_ROWS),
 * seeded to `defAttr`. The old model, if any, is folded and dropped only once the new one exists, so a
 * refusal leaves the handle exactly as it was. Returns 0 with *status set to one of the OPEN_* codes. */
static int build_model(RcHandle *h, int cols, int rows, int defAttr, int *status)
{
  *status = OPEN_OK;
  if (cols > RC_MAX_COLS) { *status = OPEN_WIDE; return 0; }
  int hist = rows;
  if (rows + hist > RC_MAX_ROWS) hist = RC_MAX_ROWS - (int)rows;
  if (hist <= 0) { *status = OPEN_NO_GUTTER; return 0; }
  /* calloc, not malloc: rc_reset_hist() frees the alt screen's snapshot field before it zeroes the grid,
     and it can only do that safely if a first-ever grid reads as zeroed. The pages stay untouched
     either way -- the reset writes the cells it owns. */
  RcGrid *fresh = (RcGrid *)calloc(1, sizeof(RcGrid));
  if (!fresh) { *status = OPEN_OOM; return 0; }
  if (!rc_reset_hist(fresh, cols, rows, hist, (uint16_t)defAttr))
  {
    free(fresh);
    *status = OPEN_BIG;
    return 0;
  }
  drop_model(h);
  h->g = fresh;
  h->g->onFlush = flush_now;                      /* fires inside rc_feed when the gutter is full */
  h->g->flushCtx = h;
  h->defAttr = (uint16_t)defAttr;
  h->landedChunk = 0;
  h->lastError[0] = 0;
  return 1;
}

/* Rebuild the model for the console's shape *right now* and adopt what it shows. This is what a resize
 * needs, and it is why the handle's identity never changes under the caller: a fresh open() would have
 * handed back a different slot, and the pointer Java holds is not something it may ask C to keep up with.
 * defAttr is deliberately *not* re-read from the console -- the first freeze is the one that matters, so
 * an SGR reset keeps returning to the colour the session started on (I12). */
static int readopt(RcHandle *h, int *status)
{
  RcView v;
  CONSOLE_SCREEN_BUFFER_INFO csbi;
  *status = OPEN_NO_CONSOLE;
  if (h->con == INVALID_HANDLE_VALUE || !view_of(h->con, &v, &csbi)) return 0;
  if (!build_model(h, v.bufW - v.winL, v.winB - v.winT + 1, h->defAttr, status)) return 0;
  return align_grid(h) ? 1 : (*status = OPEN_NO_CONSOLE, 0);
}

/* The end of the fast path for this console. The reason is kept once and never overwritten, because the
 * first one is the true one; the sequence census goes with the model rather than being lost with it. */
static int give_up(RcHandle *h, const char *why)
{
  if (!h->stopped[0]) snprintf(h->stopped, sizeof h->stopped, "%s", why);
  drop_model(h);
  h->adopt = RC_ALIGN;
  h->declines = 0;
  return RENDER_GIVEUP;
}

static int refuse(RcHandle *h, int status)
{
  char msg[256];
  snprintf(msg, sizeof msg, "native renderer refused the console: %s", open_name(status));
  return give_up(h, msg);
}

/* paint_flush plus the one re-adopt a swallowed sequence can need: a sequence we dropped without modelling
 * could have moved the console's cursor or chosen which rows scroll, and the model would go on describing a
 * screen that is not there -- no geometry check sees that, because the window still has the shape it claims
 * (S3). Re-adopt once here, where the chunk is finished and nothing is half-parsed. A decline is excluded:
 * the caller is about to put those same bytes in front of the console, which changes it again, and the
 * re-adopt happens before the next chunk anyway. Named so that both entry points run the same code. */
static int paint_and_check(RcHandle *h)
{
  const int r = paint_flush(h);
  if (r >= 0 && rc_model_suspect(h->g)) align_grid(h);
  return r;
}

static const char *decline_name(int r)
{
  if (r == FLUSH_NOGEOM) return "the console kept changing shape";
  if (r == FLUSH_API)    return "console calls kept failing";
  return "the painter kept declining";
}

/**
 * Parse and paint one chunk, owning every decision that used to live in the Java binding: adopt the console
 * on the first chunk, re-adopt it once anything has moved it behind our back, and stop
 * asking after a run of declines that a re-adopt did not break.
 *
 * Returns RENDER_PAINTED when the chunk is on the screen, RENDER_RAW when nothing was written and the
 * caller should put these same bytes in front of the console, and RENDER_GIVEUP when it says that *and*
 * is finished for the rest of the session -- which is the difference between a chunk that went oddly and a
 * session that has silently changed how it paints, and the reason stopReason() exists.
 */
extern "C" JNIEXPORT jint JNICALL Java_com_hyee_ansirender_NativeRenderer_render(JNIEnv *env, jclass cls, jlong ph,
                                                            jcharArray text, jint off, jint len)
{
  (void)cls;
  RcHandle *h = slot_of(ph);
  if (!h || len <= 0) return RENDER_RAW;          /* a pointer we do not own is the caller's bug, not ours */
  if (!h->g) return RENDER_GIVEUP;                /* stopped already: stopReason() has the sentence */

  if (h->adopt != RC_ADOPTED)
  {
    /* The cheap adopt -- read the console into the model we already have -- is only on the table when that
       model is still claiming the same screen the console is showing. After a decline it is not: the caller
       has put unparsed bytes in front of a console this model never painted, and the model may be on an
       emulated alt screen the console has never heard of. Only a rebuild is honest there. Otherwise align
       first, since align fails exactly when the console's shape is not the model's -- which is the case
       that needs a rebuilt grid anyway. */
    const int cheap = (h->adopt == RC_ALIGN) && align_grid(h);
    if (cheap) h->adopt = RC_ADOPTED;
    else
    {
      int status = OPEN_OK;
      if (!readopt(h, &status)) return refuse(h, status);
      h->adopt = RC_ADOPTED;                            /* readopt() aligned as it rebuilt */
    }
  }

  h->landedChunk = 0;                             /* a new chunk: replaying it is on the table again */
  uint16_t *units = NULL;
  const char *bad = copyChars(env, text, off, len, &units);
  if (bad)
  {
    char msg[192];
    snprintf(msg, sizeof msg, "native renderer refused the chunk (%s)", bad);
    return give_up(h, msg);
  }
  rc_feed(h->g, units + off, len);
  env->ReleasePrimitiveArrayCritical(text, (jchar *)units, 0);
  /* The SGR text this chunk consumed is dropped rather than handed over: this renderer is the only thing
     in the process that reads the stream, so there is no attribute state of anyone else's to keep in step.
     It still has to be cleared, or a chunk's worth would ride along into the next one and the capture
     would overflow, which would make the parser's own nSgrDrop counter lie. */
  rc_sgr_clear(h->g);

  const int r = paint_and_check(h);
  if (r >= 0)
  {
    h->declines = 0;
    if (r == FLUSH_RESYNC) h->adopt = RC_ALIGN;         /* painted, but the shape is no longer the model's */
    return RENDER_PAINTED;
  }
  char msg[192];
  if (++h->declines >= RENDER_MAX_DECLINES)
  {
    snprintf(msg, sizeof msg, "native renderer stopped after %d chunk(s) it could not paint (%s);"
             " output is written unparsed", h->declines, decline_name(r));
    return give_up(h, msg);
  }
  h->adopt = RC_REBUILD;                                /* the caller is about to move that console */
  return RENDER_RAW;
}

/* ------------------------------------------------------------------------ exports -------------- */

extern "C" {

JNIEXPORT jstring JNICALL Java_com_hyee_ansirender_NativeRenderer_build(JNIEnv *env, jclass cls)
{
  char b[192];
  sprintf(b, "%s gcc=[%s] arch=%s sizeof_CHAR_INFO=%u handles=%u", RENDER_BUILD,
          __VERSION__, (sizeof(void *) == 4) ? "x86" : "x64", (unsigned)sizeof(CHAR_INFO),
          (unsigned)(sizeof g_h / sizeof g_h[0]));
  return env->NewStringUTF(b);
}

/**
 * Allocate a renderer. Production does not call this on a chunk path -- render() is the whole per-chunk
 * interface -- but the handle it returns *is* the one render() takes, and the console gate in Render.java
 * drives the layers under render() one call at a time through feed()/flush()/align() below.
 *
 *   console   a screen buffer handle, or 0 to open CONOUT$ here. The caller passes the one JLine picked,
 *             because WinSysTerminal may have selected the STD_ERROR console.
 *   cols/rows the model's row width and the viewport height, or 0 to read them from the console: cols
 *             then becomes the *buffer* row (dwSize.X less srWindow.Left), rows the window's height. The
 *             buffer row is the model's width because that is where conhost wraps (see Render.h).
 *   defAttr   the attribute an SGR reset returns to, or -1 for the console's current one. ConEmu froze
 *             that value the first time it rendered, so the caller may pass what it already knows -- and
 *             a re-adopt keeps using it rather than re-reading the console, which is the same rule (I12).
 *
 * The model is given a gutter as tall as the viewport -- one extra screen of text written but not yet
 * painted -- so a chunk larger than the window is painted in full instead of dropping its earliest lines.
 * Returns the handle, or 0 with openStatus() telling why; the caller then writes its bytes unparsed,
 * which is always correct and only slower to look at.
 */
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
    /* The model row is the buffer row (Render.h, `cols`): conhost wraps a raw write at dwSize.X, so a
       120-column window inside a 2000-column buffer has 2000-column lines, and modelling 120 of them
       would wrap text the console never wrapped. A buffer wider than the model can hold is refused here,
       once, instead of declining every chunk: the caller keeps the shipped Java writer. */
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
    g_openStatus = OPEN_OOM;                      /* every slot is taken: nothing was allocated */
    if (console == 0) CloseHandle(con);
    return 0;
  }
  /* The slot is claimed before the model is built, so that the model's flushCtx -- which is this
     pointer -- is stable from the first byte. build_model() may still refuse, and the refusal below hands
     the claim back: the gate's four-slot test counts open() refusals as consuming nothing, and they must. */
  slot->taken = 1;
  slot->con = con;
  slot->ownsCon = (console == 0) ? 1 : 0;
  slot->adopt = RC_ALIGN;
  slot->declines = 0;
  slot->stopped[0] = 0;
  slot->cells = NULL;
  slot->ncells = 0;
  slot->defAttr = (uint16_t)defAttr;
  /* A slot is reused, so a fresh model must not be reported with the previous one's counters: the gate
     reads stats()[2] and [3] as "this model declined / failed nothing", and NativeRenderer's rollout
     report says the same about the model it is running. */
  slot->nFlush = slot->nPaints = slot->nDeclines = slot->nApiErrors = slot->nAligns = 0;
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
  return (jlong)(void *)slot;
}

/** Why the last open() returned 0: one of the OPEN_* codes. Cleared by a successful open. */
JNIEXPORT jint JNICALL Java_com_hyee_ansirender_NativeRenderer_openStatus(JNIEnv *env, jclass cls)
{
  (void)env; (void)cls;
  return g_openStatus;
}

/** The same refusal as a sentence, in the language the user is supposed to read. Java used to own this
 *  table; one copy of it now agrees with stopReason() instead of two that can drift. */
JNIEXPORT jstring JNICALL Java_com_hyee_ansirender_NativeRenderer_openReason(JNIEnv *env, jclass cls)
{
  (void)cls;
  return env->NewStringUTF(open_name(g_openStatus));
}

/**
 * Parse UTF-16 units into the model. Returns 1, or 0 on a bad handle or range. Normally it paints
 * nothing, but a chunk of more than one screenful is painted at the point its gutter fills up --
 * losing those lines is not an option, and a mid-chunk paint is the same operation list a flush() does.
 */
JNIEXPORT jint JNICALL Java_com_hyee_ansirender_NativeRenderer_feed(JNIEnv *env, jclass cls, jlong ph,
                                                          jcharArray text, jint off, jint len)
{
  RcHandle *h = handle(ph);
  if (!h) return 0;
  h->landedChunk = 0;                               /* a new chunk: replaying it is on the table again */
  uint16_t *units = NULL;
  const char *bad = copyChars(env, text, off, len, &units);
  if (bad)
  {
    snprintf(h->lastError, sizeof h->lastError, "feed: %s", bad);
    return 0;
  }
  rc_feed(h->g, units + off, len);
  env->ReleasePrimitiveArrayCritical(text, (jchar *)units, 0);
  return 1;
}

/**
 * Execute the pending plan. See the FLUSH_* codes above: negative means nothing landed and the caller owns
 * those bytes. Gate-only -- production goes through render(), which is this plus the policy.
 */
JNIEXPORT jint JNICALL Java_com_hyee_ansirender_NativeRenderer_flush(JNIEnv *env, jclass cls, jlong ph)
{
  (void)env; (void)cls;
  RcHandle *h = handle(ph);
  if (!h) return FLUSH_API;
  return paint_and_check(h);
}

/**
 * The SGR sequences consumed since the last take, verbatim, or null when there were none. Nothing replays
 * them any more -- this renderer is the only reader of the stream -- so what the export is now for is the
 * gate's witness that the parser captured the escapes it consumed byte for byte. render() clears the
 * accumulator instead of copying it.
 */
JNIEXPORT jcharArray JNICALL Java_com_hyee_ansirender_NativeRenderer_sgr(JNIEnv *env, jclass cls, jlong ph)
{
  RcHandle *h = handle(ph);
  if (!h) return NULL;
  const int n = rc_sgr_pending(h->g);
  if (n <= 0) return NULL;
  jcharArray a = env->NewCharArray(n);
  if (!a) return NULL;                              /* nothing cleared: the next take hands it over */
  jchar *p = (jchar *)env->GetPrimitiveArrayCritical(a, NULL);
  if (!p) { env->DeleteLocalRef(a); return NULL; }
  const int got = rc_sgr_take(h->g, (uint16_t *)p, n);
  env->ReleasePrimitiveArrayCritical(a, p, 0);
  if (got != n) { env->DeleteLocalRef(a); return NULL; }
  return a;
}

/**
 * Adopt whatever the console currently shows: the window's cells, the cursor, the attribute. Called
 * before the first chunk, after any FLUSH_NOGEOM, and after a chunk that swallowed a sequence with the
 * reach to move a cursor (see RcGrid::modelSuspect). Parser state is kept, so a half-parsed escape
 * still finishes.
 */
static int align_grid(RcHandle *h)
{
  if (!h) return 0;
  RcGrid *g = h->g;
  const int hist = g->rows - g->winRows;
  RcView v;
  CONSOLE_SCREEN_BUFFER_INFO csbi;
  if (h->con == INVALID_HANDLE_VALUE || !view_of(h->con, &v, &csbi)) return 0;
  if (v.bufW - v.winL != g->cols || v.winB - v.winT + 1 != g->winRows) return 0;

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
  rect.Top = (SHORT)v.winT;
  rect.Bottom = (SHORT)v.winB;
  BOOL ok = ReadConsoleOutputW(h->con, buf, size, coord, &rect);
  if (!ok)
  {
    free(buf);
    snprintf(h->lastError, sizeof h->lastError, "align read=%lu", (unsigned long)GetLastError());
    return 0;
  }
  /* The window's rows land on the viewport, i.e. on the model's last winRows rows. What sits above
     them in the buffer is the user's scrollback: unread, unpainted, and unreachable by the cursor. */
  for (int r = 0; r < g->winRows; r++)
    for (int c = 0; c < g->cols; c++)
    {
      g->cells[hist + r][c].ch = CH_UNICODE(buf[(size_t)r * g->cols + c]);
      g->cells[hist + r][c].attr = buf[(size_t)r * g->cols + c].Attributes;
    }
  free(buf);
  g->attr = (uint16_t)csbi.wAttributes;
  g->defAttr = h->defAttr;
  /* The cursor may sit right of the window: a raw write of more columns than the window holds leaves it
     there (measured 2026-09-23: 150 units in a 100-column window of a 200-column buffer, srWindow
     unmoved), and those columns are ordinary model columns now, so it is adopted rather than clamped. */
  g->cx = (v.curX >= v.winL && v.curX < v.bufW) ? v.curX - v.winL : 0;
  g->cy = (v.curY >= v.winT && v.curY <= v.winB) ? hist + v.curY - v.winT : hist;
  g->pendingScrolls = 0;
  g->onFlush = flush_now;                            /* re-armed: this model is trusted again */
  g->flushCtx = h;
  h->nAligns++;
  /* Two facts the console cannot answer for us: it reports no wrap reason for a row, and the reason this
     model was distrusted is now moot -- the grid is the screen's again. */
  rc_forget_row_state(g);
  rc_clear_model_suspect(g);
  rc_mark_all_dirty(g);            /* we do not know what the previous chunk was, so repaint the window */
  return 1;
}

JNIEXPORT jint JNICALL Java_com_hyee_ansirender_NativeRenderer_align(JNIEnv *env, jclass cls, jlong ph)
{
  return (jint)align_grid(handle(ph));
}

/** [0] flushes [1] rectangle writes [2] declines [3] api errors [4] aligns [5] cells painted
 *  [6] scrolls [7] astral [8] last reason  [9] pendingScrolls  [10] cx [11] cy (a model row)
 *  [12] attr [13] defAttr [14] winRows [15] gutter rows above the viewport [16] SGR sequences not
 *  echoed because the capture or the accumulator filled up -- colour parity is then best effort
 *
 *  [17+enum RcUnsupported] sequences the stream contained that we consume without modelling, in the
 *  enum's order: [17] unrecognised [18] scroll region [19] alt buffer [20] mouse [21] mode
 *  [22] bracketed paste [23] ConEmu's private OSC 9 [24] any other OSC, which is where a rejected OSC 133
 *  [25] DCS [26] report request
 *  [27] a CSI that carried ':' (see STAT_TITLES, which the family's length moves)
 *  [STAT_TITLES..] titles accepted by the parser, of those truncated at RC_TITLE_MAX, and titles the
 *  console took.
 *  [STAT_ALT..] alt-screen switches (each direction of ?47/?1047/?1049 counts once) and, of the entries,
 *  the ones refused because the snapshot's allocation failed.
 *  [STAT_PROMPT..] OSC 133 marks this process laid down (I23), then the exit code the live grid last read
 *  from a 133;D: RC_EXIT_UNKNOWN before any D arrived, RC_EXIT_UNPARSABLE for one whose code was not a
 *  number. Slots from 17 on are process-wide rather than per-model on purpose (see g_tot*): "did this
 *  session's output ask for an alt buffer, or run a full-screen program, or mark its prompts" is a question
 *  about the byte stream, and a resize in the middle of it must not erase the answer. The last exit code is
 *  the one exception -- the question it answers ("what would a status bar show now") is about the grid
 *  standing here and now, and folding it would mean summing values that do not add. Everything else below
 *  17 describes one model. */
JNIEXPORT jlongArray JNICALL Java_com_hyee_ansirender_NativeRenderer_stats(JNIEnv *env, jclass cls, jlong ph)
{
  RcHandle *h = slot_of(ph);
  jlong out[STAT_LAST];
  memset(out, 0, sizeof out);
  if (h)
  {
    /* slot_of, not handle: a handle that render() gave up on still has to answer this, because the census
       below is the only record of what its stream asked for. Only the model is gone. */
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
      out[13] = g->defAttr;
      out[14] = g->winRows;
      out[15] = g->rows - g->winRows;
      out[16] = g->nSgrDrop;
    }
    out[8] = h->lastReason;
    /* The fold is complete once the model is dropped, and is the model's own while it lives; adding both
       halves unconditionally would double-count every sequence after the first resize. */
    for (int i = 0; i < RC_UN_MAX; i++) out[STAT_UNSUPPORTED + i] = (jlong)(g_totUn[i] + (g ? g->nUnsupported[i] : 0));
    out[STAT_TITLES] = (jlong)(g_totTitle + (g ? g->nTitleSet : 0));
    out[STAT_TITLES + 1] = (jlong)(g_totTitleTrunc + (g ? g->nTitleTrunc : 0));
    out[STAT_TITLES + 2] = (jlong)g_titleCalls;
    out[STAT_ALT] = (jlong)(g_totAltSwitch + (g ? g->nAltSwitch : 0));
    out[STAT_ALT + 1] = (jlong)(g_totAltFail + (g ? g->nAltFail : 0));
    out[STAT_PROMPT] = (jlong)(g_totPromptMark + (g ? g->nPromptMark : 0));
    out[STAT_PROMPT + 1] = g ? (jlong)rc_last_exit(g) : (jlong)RC_EXIT_UNKNOWN;
  }
  jlongArray arr = env->NewLongArray(STAT_LAST);
  if (arr) env->SetLongArrayRegion(arr, 0, STAT_LAST, out);
  return arr;
}

/** Why render() gave up on this console, or null when it has not. The handle stays usable as a pointer
 *  after this -- it just answers RENDER_GIVEUP -- because the caller reads this sentence before it closes. */
JNIEXPORT jstring JNICALL Java_com_hyee_ansirender_NativeRenderer_stopReason(JNIEnv *env, jclass cls, jlong ph)
{
  (void)cls;
  RcHandle *h = slot_of(ph);
  if (!h || !h->stopped[0]) return NULL;
  return env->NewStringUTF(h->stopped);
}

/**
 * Releases the model and, if we opened it, the console. Idempotent, and safe on a handle that render()
 * already gave up on: the sequence census was folded when the model went, and folding it twice would be
 * the one way this report could lie.
 */
JNIEXPORT void JNICALL Java_com_hyee_ansirender_NativeRenderer_close(JNIEnv *env, jclass cls, jlong ph)
{
  (void)env; (void)cls;
  RcHandle *h = slot_of(ph);
  if (h) release_all(h);
}

/* ---- gate-only scaffolding: the same console preparation and cell reader Probe.cpp uses, so
 *      Render.java can run in one process against one DLL. Production never calls these. ---- */

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

/**
 * Put the console into a known shape: buffer bufW x bufH, window winW x winH at its top-left, current
 * attribute `attr`, cursor home. The gate needs a *known* blank tail (buffer wider than the window) to
 * tell "the row was painted to dwSize.X" from "the row was painted to the window", and production never
 * resizes the user's console. Buffer first, window second: the reverse order fails when the window is
 * being enlarged.
 */
JNIEXPORT jint JNICALL Java_Render_setGeometry(JNIEnv *env, jclass cls, jint bufW, jint bufH,
                                               jint winW, jint winH, jint attr)
{
  HANDLE con = CreateFileW(L"CONOUT$", GENERIC_READ | GENERIC_WRITE,
                           FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
  if (con == INVALID_HANDLE_VALUE) return 0;
  COORD size;
  size.X = (SHORT)bufW;
  size.Y = (SHORT)bufH;
  SetConsoleScreenBufferSize(con, size);          /* already this size => fails harmlessly */
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

/** [0] winT [1] winL [2] bufW [3] bufH [4] attr [5] curX [6] curY [7] cursorOn -- what the gate needs
 *  to know where the window slid to. Production reads nothing through here. */
JNIEXPORT jlongArray JNICALL Java_Render_consoleView(JNIEnv *env, jclass cls)
{
  jlong out[8];
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
      out[4] = v.attr; out[5] = v.curX; out[6] = v.curY; out[7] = v.cursorOn;
    }
    CloseHandle(con);
  }
  jlongArray arr = env->NewLongArray(8);
  if (arr) env->SetLongArrayRegion(arr, 0, 8, out);
  return arr;
}

/** Read w*h cells from buffer (x,y) back as (Unicode | Attr<<16), the witness the gate asserts on. */
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

/** The console's current window title as UTF-16 units, or null when the read failed. The only witness
 *  for the one effect an OSC can have that is not in the screen buffer: a grid diff cannot see a title,
 *  so "did SetConsoleTitleW run" has to be asked of the console itself. GetConsoleTitleW returns 0 for
 *  both a failure and an empty title, hence the explicit error check -- the gate's own cases set a
 *  non-empty title, so this distinction is belt-and-braces rather than load-bearing. */
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

typedef BOOL (WINAPI *WriteProcessed3Fn)(LPCWSTR, DWORD, LPDWORD, HANDLE);

/**
 * Hand bytes to the fallback leg itself -- ConEmuHk's WriteProcessed3, the same export ConEmuWriter calls
 * through JNA in production -- and report how many it consumed.
 *
 * Why this exists: every parity claim in DESIGN (the backspace a wide glyph swallows, a DECSTBM the model
 * does not implement, where a line wraps) used to need a live session of the application plus a command that could emit
 * the bytes, because the two legs lived in different processes. Here they are one function call apart, on
 * one console, at a cursor the gate placed, so a claim can be settled by diffing two cell reads. It is the
 * witness for `caseLegsAgree` in Render.java; production never calls it (the writer's own fallback leg is
 * reached by declining the renderer, not by this).
 *
 * The DLL is named by the caller, never searched for: lib\x86\ConEmuHk.dll and lib\x64\ConEmuHk64.dll are
 * bitness-specific, and a gate that guessed would pass on a machine where the deployed tree is elsewhere.
 * ConEmuHk is loaded but not injected here, which is what production does too when the console is not
 * ConEmu's own (ANSICON_DEF=conemu with no ConEmu server), so the parse is real and the GUI hooks are not.
 *
 * Returns chars consumed, or HK_* (see Render.java) when the leg could not be reached at all.
 */
JNIEXPORT jint JNICALL Java_Render_writeHk(JNIEnv *env, jclass cls, jcharArray text, jint len, jstring dll)
{
  (void)cls;
  static WriteProcessed3Fn fn = NULL;
  static HMODULE mod = NULL;

  if (!dll) return -1;                       /* the caller had no DLL to offer: skip, do not fail */
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

}  // extern "C"

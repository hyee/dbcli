#ifndef ANSIRENDER_RENDER_H
#define ANSIRENDER_RENDER_H

#include <stdint.h>

#define RC_MAX_COLS   4096
#define RC_MAX_ROWS   256
#define RC_CSI_ARGS   16
#define RC_ARG_MAX    65535
#define RC_TAB_INTERVAL 8
#define RC_INTERIM_MAX 4
#define RC_TITLE_MAX  256
#define RC_TITLE_STACK 2
#define RC_OSC_MAX    32768
#define RC_SGR_ECHO_MAX 1024
#define RC_SGR_CAP_MAX  64

#define RC_LVB_UNDERSCORE 0x8000
#define RC_LVB_REVERSE    0x4000
#define RC_LVB_LEADING    0x0100
#define RC_LVB_TRAILING   0x0200

enum RcClrKind
{
  RC_CLR4B  = 0,
  RC_CLR8B  = 1,
  RC_CLR24B = 2
};

typedef struct RcSgr
{
  int     fg, bg;
  uint8_t fgKind, bgKind;
  uint8_t bold, brightFore, brightBack;
  uint8_t italic, underline, inverse, crossed;
  int     seeded;
} RcSgr;

typedef struct RcCell
{
  uint16_t ch;
  uint16_t attr;
} RcCell;

#define RC_CENSUS_X(X) \
  X(SUP, "unrecognised", "escape", \
    "a CSI whose final byte neither this dispatch nor ConEmu's parser has a case for, so its reach is assumed rather than known", 1) \
  X(DECSTBM, "decstbm", "scroll region", \
    "dead since DECSTBM became a modelled region (I25); the slot stays where it is because the census is positional", 0) \
  X(ALTBUF, "altbuf", "alt buffer", \
    "the alt-screen snapshot could not be taken -- a switch that was asked for and refused", 0) \
  X(MOUSE, "mouse", "mouse tracking", \
    "mouse tracking asked for; this library generates no mouse reports", 0) \
  X(MODE, "mode", "mode", \
    "a mode this model holds no state for (the private set it does hold answers DECRQM instead)", 0) \
  X(DECBP, "bracketed paste", "bracketed paste", \
    "an OSC ]2004; request to execute a bracketed paste, which the host's input leg owns (#83 stores and answers `CSI ?2004 h/l` instead)", 0) \
  X(OSC_PRIV, "osc9", "private OSC 9", \
    "a ConEmu-private OSC 9 outside the safe subset -- sleep, MessageBox, GuiMacro, DoProcess", 0) \
  X(OSC_OTHER, "other osc", "other OSC", \
    "an OSC neither acted on nor answered, including one that never terminated", 0) \
  X(DCS, "dcs", "DCS", \
    "a DCS payload, read to its terminator and discarded", 0) \
  X(REPORT, "report", "report request", \
    "a query this build will not answer: `CSI ? 6 n`, a DA with a parameter, `CSI 19t`/`14t`/" \
    "`16t` (no second geometry, no honest pixels), a window-op parameter list that is not a " \
    "query, and a title pop with nothing to restore", 0) \
  X(COLON, "colon", "colon subparameter", \
    "a ':' subparameter whose arm this build does not carry: the SGR colours are parsed and applied " \
    "since #78, what this counts is `4:` styles the console cannot draw, `58:` (underline colour, no " \
    "surface for it), a colour whose kind the form cannot name, and a colon on any final but `m`", 0) \
  X(OSC_CLIP, "osc clip", "clipboard refused", \
    "OSC 52 asked for the clipboard and this build did not give it: policy off, a selection this platform has no place for, a payload that failed the strict decode, a request over the cap, or a read", 0) \
  X(CHARSET, "charset", "charset named but not drawable", \
    "an ISO 2022 designator naming a set this build cannot render (Latin-1 and the rest); `0` and `B` are acted on and vote nothing (#85)", 0)
enum RcUnsupported
{
#define RC_CENSUS_ENUM(tok, label, word, sentence, suspect) RC_UN_##tok,
  RC_CENSUS_X(RC_CENSUS_ENUM)
#undef RC_CENSUS_ENUM
  RC_UN_MAX
};

#define RC_STATFAM_X(X) \
  X(TITLES,   STAT_TITLES,   S_TITLES,           SLOT_TITLES) \
  X(TITLES,   -,             S_TITLES_TRUNC,     SLOT_TITLES_TRUNC) \
  X(TITLES,   -,             S_TITLES_APPLIED,   SLOT_TITLES_APPLIED) \
  X(ALT,      STAT_ALT,      S_ALT,              SLOT_ALT) \
  X(ALT,      -,             S_ALT_FAIL,         SLOT_ALT_REFUSED) \
  X(PROMPT,   STAT_PROMPT,   S_PROMPTS,          SLOT_PROMPT_MARKS) \
  X(PROMPT,   -,             S_EXIT,             SLOT_LAST_EXIT) \
  X(REPORT,   STAT_REPORT,   S_REPLIED,          -) \
  X(REPORT,   -,             S_REPLY_FAIL,       -) \
  X(REPORT,   -,             S_REPLY_FULL,       -) \
  X(SNAP,     STAT_SNAP,     S_SNAP,             SLOT_SNAP) \
  X(SYNC,     STAT_SYNC,     S_SYNC_ENGAGES,     SLOT_SYNC_ENGAGES) \
  X(SYNC,     -,             S_SYNC_NESTED,      SLOT_SYNC_NESTED) \
  X(SYNC,     -,             S_SYNC_HELD,        SLOT_SYNC_HELD) \
  X(SYNC,     -,             S_SYNC_TIMEOUT,     SLOT_SYNC_TIMEOUT) \
  X(SYNC,     -,             S_SYNC_OVERFLOW,    SLOT_SYNC_OVERFLOW) \
  X(SYNC,     -,             S_SYNC_DECLINED,    SLOT_SYNC_DECLINED) \
  X(SYNC,     -,             S_SYNC_ON,          SLOT_SYNC_ON) \
  X(CLIP,     STAT_CLIP,     S_CLIP_ARMED,       SLOT_CLIP_ARMED) \
  X(CLIP,     -,             S_CLIP_DECODE,      SLOT_CLIP_DECODE) \
  X(CLIP,     -,             S_CLIP_SELECTION,   SLOT_CLIP_SELECTION) \
  X(CLIP,     -,             S_CLIP_READ,        SLOT_CLIP_READ) \
  X(CLIP,     -,             S_CLIP_WRITES,      SLOT_CLIP_WRITES) \
  X(CLIP,     -,             S_CLIP_FAILS,       SLOT_CLIP_FAILS) \
  X(CLIP,     -,             S_CLIP_POLICY,      SLOT_CLIP_POLICY) \
  X(ARGTRUNC, STAT_ARGTRUNC, S_ARGTRUNC,         SLOT_ARGTRUNC) \
  X(BP,       STAT_BP,       S_BP,               SLOT_BP) \
  X(SHAPE,    STAT_SHAPE,    S_SHAPE,            SLOT_SHAPE)

int rc_census_count(void);
const char *rc_census_name(int slot);
const char *rc_census_sentence(int slot);
int rc_census_suspect(int slot);

int rc_osc_family_count(void);
const char *rc_osc_family_name(int i);
int rc_osc_family_owns(int i, int code);

#define RC_CLIP_ENC_MAX 16384
#define RC_CLIP_MAX     12288

#define RC_CLIP_DENY  0
#define RC_CLIP_ALLOW 1
void rc_set_clipboard_policy(int allow);
int  rc_clipboard_policy(void);

int rc_b64_decode(const uint16_t *src, int n, uint8_t *dst, int cap);

#define RC_OSC_NONE 0
#define RC_OSC_DCS  1
#define RC_OSC_PRIV 2
#define RC_OSC_OTHER 3
#define RC_OSC_TITLE 4

enum RcReport { RC_REP_NONE = -1, RC_REP_DSR = 0, RC_REP_CPR = 1, RC_REP_DA = 2, RC_REP_DA2 = 3,
                RC_REP_DECRPM = 4, RC_REP_OSC = 5,
                RC_REP_WINOP = 6,
                RC_REP_TITLE = 7, RC_REP_XTVER = 8 };

#define RC_REPORT_MAX 64

struct RcReportItem { uint8_t kind; uint16_t y, x; uint32_t mode, status; };

#define RC_MS_MOVED   0x0001u
#define RC_MS_WHEELED 0x0004u
#define RC_MS_HWHEELED 0x0008u
#define RC_MS_LEFT    0x0001u
#define RC_MS_RIGHT   0x0002u
#define RC_MS_MIDDLE  0x0004u
#define RC_MS_SHIFT   0x0010u
#define RC_MS_ALT     (0x0001u | 0x0002u)
#define RC_MS_CTRL    (0x0004u | 0x0008u)

struct RcMouseRec { int16_t x, y;
                    int16_t px, py;
                    uint32_t buttonState;
                    uint32_t eventFlags;
                    uint16_t ctrlKeyState; };

enum RcMouseFormat { RC_MF_X10 = 0, RC_MF_UTF8 = 1, RC_MF_SGR = 2, RC_MF_URXVT = 3, RC_MF_SGR_PX = 4 };

enum RcMouseEvent { RC_ME_NONE = 0, RC_ME_X10 = 1, RC_ME_NORMAL = 2, RC_ME_BUTTON = 3, RC_ME_ANY = 4 };

enum RcRowWrap
{
  RC_WRAP_NONE = 0, RC_WRAP_FORCED = 1, RC_WRAP_PAD = 2
};

enum RcPromptMark
{
  RC_PM_NONE = 0,
  RC_PM_PROMPT = 1,
  RC_PM_CONTINUATION = 2,
  RC_PM_SUCCESS = 3,
  RC_PM_ERROR = 4
};

typedef struct RcRowState
{
  uint8_t  wrap;
  uint8_t  mark;
  uint16_t col;
} RcRowState;

#define RC_ROW_CLEAN { RC_WRAP_NONE, RC_PM_NONE, 0 }

static_assert(sizeof(RcRowState) == 4, "RcRowState must cost exactly what rowWrap+rowMark+markCol did per row");
static_assert(sizeof(RcRowState) * RC_MAX_ROWS == (1 + 1 + 2) * RC_MAX_ROWS,
              "the row-state array must not change the grid's footprint");

enum RcSemanticContent
{
  RC_SC_OUTPUT = 0, RC_SC_INPUT = 1, RC_SC_PROMPT = 2
};

#define RC_EXIT_UNKNOWN     (-1)
#define RC_EXIT_UNPARSABLE  0x7FFFFFFF

#define RC_SGR_STACK 10
#define RC_SP_BOLD   0x01
#define RC_SP_ITAL   0x02
#define RC_SP_UNDER  0x04
#define RC_SP_INVERSE 0x08
#define RC_SP_CROSSED 0x10
#define RC_SP_FORE   0x20
#define RC_SP_BACK   0x40
#define RC_SP_PARAMSED 0x80
#define RC_XT_BITS 12

/* Everything a rebuild carries: state the stream claimed, which a resize does not revoke.
   build_model copies this struct whole; carried_readopt then re-derives what the new width
   and height change (the margin pair and the vertical band are re-clamped, the tab table's
   revealed tail re-defaulted, the saved cursor rebased into the new viewport). */
typedef struct RcCarried
{
  uint32_t palette[256];
  uint32_t pal16[16];
  uint16_t palTouched;
  uint16_t defAttr;
  int      taskbarState, taskbarProgress, taskbarSeen;
  uint8_t  wrapMode, unpushed, insertMode, bracketedPaste, cursorKeys, inbandResize;
  uint8_t  originMode, declrmm, saveOrigin;
  uint8_t  marginSet;
  int      leftMargin, rightMargin;
  uint8_t  regSet;                     /* DECSTBM's band rides a rebuild like the margin pair */
  int      regTop, regBot;             /* above it: carried absolute, re-clamped to the new rows */
  int      saveX, saveY;               /* DECSC's cursor crosses too; saveOrigin always did */
  int      cursorVisible;              /* ?25 is a mode, not geometry: rebuilds keep it */
  uint8_t  charset[4];
  uint8_t  gshift;
  uint16_t mouseModes;
  uint8_t  mouseFormat;
  uint32_t lastBtn;
  RcSgr    sgrStack[RC_SGR_STACK];
  uint8_t  sgrParts[RC_SGR_STACK];
  uint8_t  sgrTop, sgrDepth;
  uint16_t xtOn, xtHave;
  uint8_t  penProt;
  uint8_t  tabStop[RC_MAX_COLS];
  int      tabsDefaults;
  uint16_t cwd[RC_TITLE_MAX];
  int      nCwd;
  uint16_t title[RC_TITLE_MAX];
  int      nTitle;
  uint16_t tstack[RC_TITLE_STACK][RC_TITLE_MAX];
  int      tstackLen[RC_TITLE_STACK];
  int      nTStack;
} RcCarried;

typedef struct RcGrid
{
  RcCarried carried;
  RcCell cells[RC_MAX_ROWS][RC_MAX_COLS];
  uint8_t cellProt[RC_MAX_ROWS][RC_MAX_COLS];
  int of[RC_MAX_ROWS];
  int cols, rows;
  int winRows;
  int cx, cy;
  uint8_t rowDirty[RC_MAX_ROWS];
  uint16_t dirtyLo[RC_MAX_ROWS], dirtyHi[RC_MAX_ROWS];
  RcRowState rowState[RC_MAX_ROWS];
  uint8_t modelSuspect;
  uint8_t alt;
  RcCell *snap;
  RcRowState snapState[RC_MAX_ROWS];

  uint8_t streamScrolls;
  uint32_t regionSerial;



  RcSgr   sgr;
  uint16_t attr;
  uint16_t defAttrSeed;
  uint32_t lastUnit;
  int    lastExit;
  uint8_t semanticContent;
  uint8_t semanticClearEol;
  uint8_t sync;
  int16_t  lastMoveX, lastMoveY;
  uint8_t  lastMoveBtn;
  int      moveSeen;
  unsigned long nSyncEngages;
  unsigned long nSyncNested;
  unsigned long nSyncHeld, nSyncTimeout, nSyncOverflow, nSyncDeclined;
  int    cursorShape;

  int    mode;
  int    priv;
  int    nArgs;
  int    args[RC_CSI_ARGS];
  uint8_t argSub[RC_CSI_ARGS];
  int    digit;
  int    cur;
  uint8_t interims[RC_INTERIM_MAX];
  int    nInterims;
  int    escInterim;
  int    csiColon;
  int    csiSub;
  int    nOsc;
  uint16_t osc[RC_OSC_MAX];
  int    oscKind;
  int    oscClip;
  int    titlePending;
  uint8_t clip[RC_CLIP_MAX];
  int    nClip;
  int    clipPending;
  uint32_t wantLow;

  RcReportItem report[RC_REPORT_MAX];
  int reportHead, reportLen;


  unsigned long nUnsupported[RC_UN_MAX];
  unsigned long nCells, nScrolls, nAstral;
  unsigned long nTitleSet, nTitleTrunc;
  unsigned long nClipSet, nClipBad, nClipSel, nClipRead;
  unsigned long nAltSwitch, nAltFail;
  unsigned long nPromptMark;

  unsigned long nReportOk, nReportFail, nReportFull;
  unsigned long nMouseRep, nFocusRep, nMouseQuiet;
  unsigned long nInjectOk, nInjectFail;

  unsigned long nArgTrunc;

  int pendingScrolls;

  int baseRow;
  int baseSet;

  uint16_t sgrEcho[RC_SGR_ECHO_MAX];
  int      nSgrEcho;
  int      nSgrDrop;
  uint16_t cap[RC_SGR_CAP_MAX];
  int      nCap, capLost;

  void (*onFlush)(void *ctx);
  void *flushCtx;
} RcGrid;

#define RC_PHYS(g, r)   ((g)->of[r])
#define RC_CELLS(g, r)  ((g)->cells[RC_PHYS(g, r)])
#define RC_PROT(g, r)   ((g)->cellProt[RC_PHYS(g, r)])
#define RC_ST(g, r)     ((g)->rowState[RC_PHYS(g, r)])
#define RC_DTY(g, r)    ((g)->rowDirty[RC_PHYS(g, r)])
#define RC_LO(g, r)     ((g)->dirtyLo[RC_PHYS(g, r)])
#define RC_HI(g, r)     ((g)->dirtyHi[RC_PHYS(g, r)])

int rc_validate_grid(const RcGrid *g, char *msg, int len);
void rc_tabs_widen(RcGrid *g, int from);

#define RC_SYNC_TIMEOUT_MS 100

enum
{
  RC_GROUND = 0, RC_ESC, RC_ESC_INTERIM, RC_CSI, RC_OSC, RC_OSC_ESC
};

#ifdef __cplusplus
extern "C" {
#endif

int  rc_reset(RcGrid *g, int cols, int rows, uint16_t defAttr);

int  rc_reset_hist(RcGrid *g, int cols, int winRows, int histRows, uint16_t defAttr);

/* After build_model copies a carried struct onto the fresh grid: re-derive what the new
   width and height change. Lives with the model state, not the console side, so the host
   RenderCheck legs exercise it directly. */
void carried_readopt(RcGrid *g, int oldCols, int oldRows, int oldWinRows);

int  rc_scroll_room(const RcGrid *g);

void rc_feed(RcGrid *g, const uint16_t *units, int n);

uint16_t rc_attr(const RcGrid *g, const RcSgr *s);

int rc_width(uint32_t cp);

int  rc_row_dirty(const RcGrid *g, int row);
void rc_clear_dirty(RcGrid *g);
void rc_mark_all_dirty(RcGrid *g);
void rc_adopt_clean(RcGrid *g);

void rc_set_base(RcGrid *g, int row);
void rc_drop_base(RcGrid *g);

int  rc_row_wrap(const RcGrid *g, int row);
void rc_forget_row_state(RcGrid *g);

int  rc_row_mark(const RcGrid *g, int row);
int  rc_mark_col(const RcGrid *g, int row);
int  rc_last_exit(const RcGrid *g);
unsigned long rc_prompt_marks(const RcGrid *g);

int  rc_model_suspect(const RcGrid *g);
void rc_clear_model_suspect(RcGrid *g);

int  rc_in_alt(const RcGrid *g);

int  rc_sgr_pending(const RcGrid *g);

int  rc_sgr_take(RcGrid *g, uint16_t *dst, int cap);

void rc_sgr_clear(RcGrid *g);

int  rc_title_pending(const RcGrid *g);

int  rc_title_take(RcGrid *g, uint16_t *dst, int cap);

int  rc_clip_pending(const RcGrid *g);
int  rc_clip_take(RcGrid *g, uint8_t *dst, int cap);

int  rc_report_pending(const RcGrid *g);

int  rc_report_take(RcGrid *g, struct RcReportItem *out);

int  rc_notify_geometry(RcGrid *g);

void rc_report_result(RcGrid *g, int written);

int rc_mouse_report(RcGrid *g, const struct RcMouseRec *m, uint16_t *out, int cap);

int rc_focus_report(RcGrid *g, int focused, uint16_t *out, int cap);

void rc_report_counts(const RcGrid *g, unsigned long *out);

#ifdef __cplusplus
}
#endif

#endif

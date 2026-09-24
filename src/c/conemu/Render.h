/*
 * Render.h -- the console-free model behind the native Windows console renderer.
 *
 * Why a model at all: today two parsers share one byte stream (the Java fast path paints cells,
 * ConEmuHk parses escapes) and every disagreement between them shows up on screen as literal
 * "[33m" or as a colour that only the fallback leg has. This module owns both halves -- it parses
 * ANSI *and* holds the resulting grid -- so the caller only ever paints a rectangle that already
 * matches what the model says is on screen. It deliberately has no dependency on windows.h, JNI or
 * the console API: the same code that will run inside the DLL can be executed and diffed on a Linux
 * host, which is what makes the parity gate cheap.
 *
 * Parity targets, each settled by measurement rather than by reading alone:
 *   cell widths   src/c/luauf8/ansi_width.c cp_width() + its Unicode 15 tables. The jansi / JLine
 *                 WCWidth family is explicitly NOT used (user ruling 2026-09-22: it has defects).
 *   escape framing  ansi_width.c esc_end(), which is NOT bit-for-bit ConEmu: ConEmu parks an ESC
 *                 inside Code.Pvt and keeps eating until the next 0x40..0x7E (Ansi.cpp:1771-1787,
 *                 with its own TODO at :1730), so "\e[3\e[31m" paints "31m" as text and applies no
 *                 colour. We abandon and restart instead. Deviation #1, recorded in .dsh/memory.
 *   SGR -> attribute  ConEmu's ReSetDisplayParm (Ansi.cpp:761-831) feeding ExtPrepareColor
 *                 (ExtConsole.cpp:292-341), including the paint-time "never paint fg==bg" bump that
 *                 only rides along with a COLORREF-folded background.
 *   pending bytes   a resumable state machine rather than ConEmu's gsPrevAnsiPart + reparse
 *                 (Ansi.cpp:1595-1669). Deviation #2: the reparse path clamps nAdd and can silently
 *                 lose bytes past 512; a resumable machine has no such window.
 */

#ifndef ANSIRENDER_RENDER_H
#define ANSIRENDER_RENDER_H

#include <stdint.h>

/* The model row is a whole *buffer* row (see `cols`), so this is the widest console buffer we will
   model. Measured 2026-09-23: this machine's default conhost profile is a 2000x9001 buffer with a
   120x60 window, Windows Terminal keeps buffer == window, ConEmu too (239 there). Above the cap the
   JNI open() returns OPEN_WIDE and the caller keeps the shipped Java writer, which is what runs today. */
#define RC_MAX_COLS   4096
#define RC_MAX_ROWS   256
#define RC_CSI_ARGS   16   /* ConEmu's ArgV holds 16 (Ansi.h:174); surplus args are dropped, not rejected */
#define RC_TITLE_MAX  256  /* OSC payload we keep; longer is truncated, the sequence is still consumed */
#define RC_SGR_ECHO_MAX 1024 /* UTF-16 units of SGR text kept for one chunk, see rc_sgr_take */
#define RC_SGR_CAP_MAX  64   /* one sequence being captured; a longer one is parsed but not echoed */

/* The four attribute bits beyond the colour nibbles that reach a legacy console. */
#define RC_LVB_UNDERSCORE 0x8000
#define RC_LVB_REVERSE    0x4000
#define RC_LVB_LEADING    0x0100  /* COMMON_LVB_LEADING_BYTE: front cell of a 2-column glyph */
#define RC_LVB_TRAILING   0x0200  /* COMMON_LVB_TRAILING_BYTE: back cell, same code point */

/* ConEmu's cbit (Ansi.h:269): how the value in fg/bg must be read. */
enum RcClrKind
{
  RC_CLR4B  = 0,  /* 0..15, a console colour index */
  RC_CLR8B  = 1,  /* 0..255, an xterm index into RgbMap */
  RC_CLR24B = 2   /* a 0x00BBGGRR COLORREF, always folded */
};

/* One-to-one with CEAnsi::DisplayParm (Ansi.h:270-285). */
typedef struct RcSgr
{
  int     fg, bg;
  uint8_t fgKind, bgKind;
  uint8_t bold, brightFore, brightBack;
  uint8_t italic, underline, inverse, crossed;
  int     seeded;   /* ConEmu lazily Reset(false)s on the first SGR of the process (Ansi.cpp:572) */
} RcSgr;

typedef struct RcCell
{
  uint16_t ch;
  uint16_t attr;
} RcCell;

/* Sequences we consume but do not model. Counted, never silently swallowed: the rollout gate needs
 * to know whether real application output contains any of them before it became the only path.
 * The OSC/DCS family is counted separately from the CSI family because those sequences change state
 * *outside* the grid (window title, ConEmu's private "run this program"), so no cell-level witness can
 * ever show them -- the counter is the only record that they were in the stream. */
enum RcUnsupported
{
  /* RC_UN_SUP: a CSI whose final byte neither this dispatch nor ConEmu's Ansi.cpp has a case for. Only the
   * `default:` arm marks the frame suspect on it, because that is the arm whose reach is unknown; the final
   * bytes we count here and know are inert upstream are counted through ignored() and repaint nothing --
   * `Z` with no tab stop to reach, `q` without its interim space, and `a`/`e` (HPR/VPR), which ConEmu's CSI
   * switch simply has no case for and therefore drops on the floor (Ansi.cpp:3816 -> :971). */
  RC_UN_SUP = 0,
  /* RC_UN_DECSTBM is dead since `CSI r` became a modelled region (I25), and RC_UN_ALTBUF now means only
   * "the snapshot's malloc failed" -- both slots are kept where they are, because the JNI census is
   * positional (RenderJni.cpp reads STAT_UNSUPPORTED + i and the Java side hardcodes the indices), so
   * renumbering would silently relabel every counter the rollout gate reads. */
  RC_UN_DECSTBM, RC_UN_ALTBUF, RC_UN_MOUSE, RC_UN_MODE, RC_UN_DECBP,
  RC_UN_OSC_PRIV,   /* ESC ] 9 ; ...: ConEmu-specific -- sleep, MessageBox, GuiMacro, DoProcess. Never executed. */
  RC_UN_OSC_OTHER,  /* any other OSC code we do not act on (4/8/10/52 ...), and an OSC that never terminated */
  RC_UN_DCS,        /* ESC P / X / ^ / _ -- payload framing identical to OSC, discarded */
  /* A CSI that carried ':' among its parameter bytes. Counted separately from the family above because it
   * is not one omission but a decision: colon subparameters (SGR 38:2::r:g:b) parse fine upstream, and we
   * drop the whole sequence for ConEmu parity, since ':' is 0x3A and so a Pvt byte for ConEmu too (I10,
   * I19). The count is what would justify revisiting that if an application ever sends the colon form. */
  RC_UN_REPORT, RC_UN_COLON, RC_UN_MAX
};

/* What an OSC/DCS introducer said. Kept until the sequence terminates, where it decides which counter
 * (or the title) the payload goes to. */
#define RC_OSC_NONE 0
#define RC_OSC_DCS  1
#define RC_OSC_PRIV 2
#define RC_OSC_OTHER 3
#define RC_OSC_TITLE 4

/* A query the stream asked and the console has to answer. The model only *arms* these: writing the reply
 * is a call on the input handle, and this file answers to no handle (the host gate links it with no console
 * at all). The painter takes the queue at the end of a flush, where the cursor it just parked is the fact
 * the reply has to match. RC_REP_NONE is what an empty queue answers with.
 * Each kind has exactly one spelling upstream answers: DSR and CPR are `CSI 5n`/`CSI 6n` (Ansi.cpp:3466-3483),
 * DA is `CSI c` and DA2 is `CSI >c` (:3765-3784). */
enum RcReport { RC_REP_NONE = -1, RC_REP_DSR = 0, RC_REP_CPR = 1, RC_REP_DA = 2, RC_REP_DA2 = 3 };

/* Queries in one chunk are rare but legal (`vim` probes more than once at startup), and a reply the queue
 * had to refuse is a program left waiting, which must be a number and not a rumour. */
#define RC_REPORT_MAX 8

/* One armed query, with the cursor as it stood when the sequence was read: a CPR answers where the cursor
 * *was*, so the painter has to know that position and not the one the chunk ends on. Named at file scope
 * because RcGrid's queue is not the only thing that speaks about it — `rc_report_take` hands one out per
 * call, and a nested type would have to be spelled through the grid everywhere it goes. */
struct RcReportItem { uint8_t kind; uint16_t y, x; };

/* What ended a row's line: the two reasons are distinct upstream (`_wrapForced` and
 * `_doubleBytePadded`, Row.hpp:313-317) and a consumer that joins rows for copy or export has to tell
 * them apart -- a padded row's next glyph was moved whole, so the row's own content is complete. */
enum RcRowWrap
{
  RC_WRAP_NONE = 0, RC_WRAP_FORCED = 1, RC_WRAP_PAD = 2
};

/* Which FTCS (OSC 133) region a row begins, marked where the *command* started. Both reference
 * implementations attach the state to the row, not to the cell stream: MSFT emplaces `Row::_promptData`
 * on `StartPrompt` (Row.cpp:1263) and writes the exit code into that same row on `D`
 * (textBuffer.cpp:3486 EndCurrentCommand, searching upward from the cursor); ghostty sets
 * `page_row.semantic_prompt` (Screen.zig:2860-2869). One byte per row and no mark chain is the whole
 * model, and it is the shape that can travel with a vertical shift -- which is what makes it truthful
 * after a scroll.
 *
 * Note what is *absent*: no COMMAND and no OUTPUT value. That is not a simplification, it is what both
 * references do -- MSFT's row category goes Prompt -> Success/Error and never any further, because the
 * Command/Output kinds live in the *cell attributes* (`_currentAttributes.SetMarkAttributes`), and
 * ghostty's row flag has exactly `none / prompt / prompt_continuation` for the same reason (its
 * input/output distinction is per-cell, `page.zig:2228`). A grid with no per-cell marks can keep the row
 * facts faithfully; keeping the cell facts would need a third attribute plane nobody reads. */
enum RcPromptMark
{
  RC_PM_NONE = 0,
  RC_PM_PROMPT = 1,         /* a prompt started here; no matching `D` has arrived yet */
  RC_PM_CONTINUATION = 2,   /* ghostty's k=c/k=s, and the row a wrapped or entered prompt line lands on */
  RC_PM_SUCCESS = 3,        /* a `D` with exit code 0 ended the command that started on this row */
  RC_PM_ERROR = 4           /* a `D` with any other code, including one that was not a number at all */
};

/* The content the *cursor* is writing, as opposed to the content a row begins in. Kept because it is what
 * makes the marks land without a shell's help: under both references, a line feed taken while the cursor is
 * inside a prompt or user input marks the row it arrives on as a continuation (ghostty Terminal.zig:2330-2357
 * does this in `index()`'s defer; MSFT's equivalent is its `_createPromptMarkIfNeeded` heuristic).
 * RC_SC_INPUT splits in two on one bit, `semanticClearEol`: `B` keeps the input state across line feeds,
 * `I` ends it at the next one -- the only observable difference either implementation has. */
enum RcSemanticContent
{
  RC_SC_OUTPUT = 0, RC_SC_INPUT = 1, RC_SC_PROMPT = 2
};

/* `rc_last_exit()` answers for a `D` whose code was missing, or was not a number. MSFT distinguishes the
   two (`std::nullopt` vs `UINT_MAX`, adaptDispatch.cpp:3735-3743) and ghostty does not (both become 0,
   stream_handler.zig:1439-1444). MSFT's answer is the informative one, so it is the one exposed here --
   and it is the reason `-1` could not be "success": an unknown exit code must not read as a clean run. */
#define RC_EXIT_UNKNOWN     (-1)
#define RC_EXIT_UNPARSABLE  0x7FFFFFFF

typedef struct RcGrid
{
  /* Only cells[r][c] with r < rows and c < cols is live; the fixed stride means the rest is stale
     after any row move, so a painter that reads past cols() repaints garbage. */
  RcCell cells[RC_MAX_ROWS][RC_MAX_COLS];
  int cols, rows;
  /* `cols` is the console's BUFFER row (dwSize.X less srWindow.Left), not the window's width: conhost
     wraps a raw write at dwSize.X and leaves the viewport where it is, which is what makes a 120-column
     window inside a 2000-column buffer print a report 2000 columns wide. Modelling the window instead
     would wrap those lines onto rows the console never used. Column 0 is the window's left edge; the
     cells right of the window are ordinary cells, painted and read back like any other. */
  /* The last winRows model rows ARE the console window; the rows above them are scrollback this chunk
     has already written but not yet painted. Without that gutter, a chunk of more than one screenful
     evicts its own earliest lines: the viewport slides down while they were still waiting to be
     written, and the buffer would keep blanks where ConEmu leaves text. The painter flushes once the
     pending scrolls reach rc_scroll_room(), which is why the cursor never addresses a gutter row. */
  int winRows;
  int cx, cy;             /* cursor, a model row: always inside the viewport, i.e. cy >= rows-winRows */
  int saveX, saveY;       /* DECSC / CSI s */
  uint8_t rowDirty[RC_MAX_ROWS];
  /* The columns a dirty row has to repaint, inclusive, and only meaningful while rowDirty says 1: the
     rectangle conhost gets is as wide as the damage, not as wide as the row. This is a paint-cost rule,
     not a memory rule -- the model still holds and can still paint the whole buffer row (I7), and every
     change that cannot name its columns (an adopt, IL/DL, a row scrolling in blank) says [0, cols-1].
     A run of the plan is the union of its rows' ranges, so a narrow range never hides a wide neighbour. */
  uint16_t dirtyLo[RC_MAX_ROWS], dirtyHi[RC_MAX_ROWS];
  /* Why each row's line continued, RC_WRAP_* (S5). Travels with the content on every vertical shift, and
     is cleared by anything that empties the row's last column: the claim is "text ran to the margin", so a
     row whose tail was erased no longer makes it. align() cannot recover it -- ReadConsoleOutputW returns
     no wrap information -- so an adopt clears the viewport's bits. */
  uint8_t rowWrap[RC_MAX_ROWS];
  /* FTCS semantic marks (RC_PM_*), one per row, and the column the mark started at -- the prompt's own
     start column, which is what a "select this command" consumer needs to avoid taking the whole row.
     Neither is a cell attribute and neither reaches the console: like rowWrap, ReadConsoleOutputW cannot
     return them, so an adopt cannot recover them and every vertical shift must carry them by hand. */
  uint8_t  rowMark[RC_MAX_ROWS];
  uint16_t markCol[RC_MAX_ROWS];
  /* Set when the stream contained a sequence that could have moved the console's cursor or changed which
     rows scroll, and we consumed it without modelling it (S3). The counters say *what* we skipped; this
     says *this frame is no longer known*, and the painter answers by re-adopting the console once. Only
     the CSI dispatch's `default:` arm sets it -- the final byte nobody has a case for, whose reach is
     therefore unknown. Everything counted by name (a mode, a mouse report, a dropped colour, and the two
     inert finals folded into RC_UN_SUP) leaves the frame trusted: Render.cpp::ignored, and
     CONEMU_ANSI_DEFECTS.md for what ConEmu itself does with each. */
  uint8_t modelSuspect;
  /* The alternate screen (?47, ?1047, ?1049 -- one behaviour, as in MSFT's ASB_AlternateScreenBuffer).
     `alt` says which screen the parser and the painter are addressing: 1 = the alt, whose rows are the
     viewport and whose scrollback does not exist. `snap` holds the main screen's viewport rows while the
     alt is engaged, malloc'd on the first entry at this grid's own stride (cols wide, winRows tall) and
     freed by rc_reset_hist(), because a snapshot taken at another buffer width would corrupt the rows it
     is copied back into. NULL = never entered, which is what makes a leave without an enter safe: the restore is guarded on `alt`
     rather than on the pointer, and rc_reset_hist frees this one instead of one cut for a wider grid. The console is never asked to switch anything: it shows
     the model's viewport either way, which is why this costs one full repaint per switch and no new API. */
  uint8_t alt;
  RcCell *snap;
  uint8_t snapWrap[RC_MAX_ROWS];    /* the wrap claims (I20) of the saved rows, same order as snap */
  uint8_t  snapMark[RC_MAX_ROWS];   /* and the FTCS marks, for the same reason: the alt screen must not
                                       lose the row the command started on (Render.cpp::alt_screen) */
  uint16_t snapCol[RC_MAX_ROWS];

  /* DECSTBM (CSI top;bot r). Inclusive model rows, and only live while `regSet`: with no region the
     scroll area is the viewport, which is every sequence the application sent before a full-screen program set one.
     Clamped to the viewport when it is set, and never re-clamped afterwards -- rc_reset_hist() is the
     only thing that changes this grid's geometry, and it zeroes the pair (RenderJni.cpp::build_model, so a
     resize cannot strand a region outside the window it was cut for). ConEmu keeps the same state
     (gDisplayOpt.ScrollRegion/Start/End) and, unlike VT100, does NOT home the cursor when it is set
     (Ansi.cpp:4146-4174 has no SetConsoleCursorPosition); the region is also what the writer's line feed,
     RI, IL/DL and SU/SD scroll inside. IND (`ESC D`) is the exception upstream -- ForwardLF never looks at
     gDisplayOpt -- and this model keeps it region-aware anyway, because an LF that obeys the region and an
     IND that does not would give one screen two answers to the same request. */
  uint8_t regSet;
  int regTop, regBot;

  RcSgr   sgr;
  uint16_t attr;          /* rc_attr() of the current state: what SetConsoleTextAttribute would get */
  uint16_t defAttr;       /* frozen console default (Ansi.cpp:691-709) */
  int    charset;         /* 0 = VTCS_DEFAULT, 1 = VTCS_DRAWING (only ESC ( touches it, Ansi.cpp:2751) */
  /* The last code point written to the grid, for REP (`CSI b`, "repeat the previous glyph"). ConEmu keeps
   * the same thing -- CEAnsi::m_LastWrittenChar (Ansi.h:197) -- and two of its quirks are load-bearing here:
   * it is seeded to L' ' and survives a FullReset (:3070-3087 reads it, never clears it), and it stores the
   * unit *before* the charset remap, so repeating after drawing-mode text replays the plain letter and not
   * the line-drawing glyph (Ansi.cpp:1098-1099). We store a code point, not a unit, so an astral glyph can
   * be repeated whole -- upstream's WCHAR cannot, and stores half a surrogate instead. */
  uint32_t lastUnit;
  /* Exit code reported by the most recent OSC 133 ; D (I23). RC_EXIT_UNKNOWN until one arrives; see the two
   * sentinels above -- MSFT and ghostty disagree about a code that is not a number, and this follows MSFT. */
  int    lastExit;
  /* The FTCS content the cursor is writing (RC_SC_*), and whether it ends at the next line feed. `B` and `I`
   * are the same claim except for this bit, and it is the only one either reference can observe: ghostty
   * resets the content to output in `index()` when clear_eol is set, and otherwise marks the row it arrived
   * on a continuation (Terminal.zig:2330-2357). 0 = output, which is also the state before any 133. */
  uint8_t semanticContent;
  uint8_t semanticClearEol;
  int    cursorVisible;   /* DECSCYM ?25: ConEmu drives SetConsoleCursorInfo (Ansi.cpp:3295-3322) */
  /* DECSCUSR (`CSI Ps SP q`), kept as the parameter rather than as a console value: -1 = nothing has asked
     (so the painter must not touch the console's cursor height at all), 0 = ConEmu's "default", 1/2 =
     block, 3-6 = the thin shape. Upstream can only give a console a block or a 15-row cursor through the
     same Get/SetConsoleCursorInfo pair (Ansi.cpp:3670-3679), so those are the two things the painter can
     emit here too -- and a Win7-safe writer has no third option (a variable-height cursor needs
     SetConsoleCursorShape, which is Windows 10 18297 and later). Paint.cpp::cursor_height maps it. */
  int    cursorShape;

  /* resumable parser state */
  int    mode;            /* RC_GROUND .. */
  int    priv;            /* CSI private byte seen ('?' '>' '<' '=' '!') */
  int    nArgs;
  int    args[RC_CSI_ARGS];
  int    digit;           /* a parameter is being accumulated */
  int    cur;
  int    interim;         /* CSI intermediate bytes (0x20..0x2F) */
  int    csiColon;        /* this CSI carried a ':' subparameter separator; decides RC_UN_COLON */
  /* The OSC/DCS payload being read. `nTitle` is its length so far and `title` its content, because the
     only payload anyone acts on is a window title; the rest is measured by the counters below. */
  int    nTitle;
  uint16_t title[RC_TITLE_MAX];
  int    oscKind;         /* RC_OSC_*: what the introducer said, decided before the payload is read */
  int    oscClip;         /* this payload outgrew title[]: a title is applied truncated and counted */
  int    titlePending;    /* a title OSC terminated and waits for the painter to hand it to the console */
  uint32_t wantLow;     /* a high surrogate ended the last chunk; complete it or paint U+FFFD */

  /* Queries waiting for a reply, oldest first, and the cursor as it stood when each was read. The position
   * is snapshotted because a CPR answers where the cursor was *when it was asked*: `printf '\e[6n\e[2;3H'`
   * asks about row 1 and then moves, and reporting the moved-to row would tell the asker something the
   * screen never showed. It is a model row, so the painter turns it into a screen row with the same
   * `row0 + r` arithmetic it paints with -- if the viewport slides between the query and the flush, the
   * answer slides with it, which is the only answer that can still be true. */
  RcReportItem report[RC_REPORT_MAX];
  int reportHead, reportLen;

  unsigned long nUnsupported[RC_UN_MAX];
  unsigned long nCells, nScrolls, nAstral;
  unsigned long nTitleSet, nTitleTrunc;   /* titles accepted (and, of those, truncated at RC_TITLE_MAX) */
  /* Screen switches taken (both directions) and refused. A refusal is the snapshot's malloc failing: the
     sequence is then consumed with the screen unchanged, which the model can say honestly -- unlike a
     sequence it swallowed after moving something. */
  unsigned long nAltSwitch, nAltFail;
  /* OSC 133 marks landed on a row (I23). Counted separately from the OSC families above because a 133 is
     not something we dropped -- it changed the model -- and a caller that wants to jump between commands
     needs to know whether any of them were marked at all. */
  unsigned long nPromptMark;

  /* Replies the painter wrote, replies the write refused (stdin is no console handle, or it took fewer
   * records than it was given), and queries refused because the queue was already full. Three counters
   * because they are three different questions: does this terminal answer, did it answer into a handle
   * nobody reads, and can it answer that many at once. A query whose model died before its flush is lost
   * with the model and counted on the handle, not here: rc_reset zeroes this struct, so nothing that wants
   * to outlive a resize belongs in it. */
  unsigned long nReportOk, nReportFail, nReportFull;

  /* Rows the viewport has scrolled up since the painter last caught up. The painter turns each one
     into a window slide (free: the cells stay where they are) or a buffer scroll, so a scroll costs
     no cell writes -- only the rows that scroll *into* the viewport are marked dirty. */
  int pendingScrolls;

  /* Where the model's rows live in the buffer: the buffer row of model row 0, and whether the model has
     ever claimed one. This is conhost's `_virtualBottom` (screenInfo.hpp:218: "Tracks the last virtual
     position the viewport was at. This is not affected by the user scrolling the viewport, only when API
     calls cause the viewport to move") turned into a row-0 anchor, and ghostty's `.active` pin, which is
     the region a program may write and is *not* the `.viewport` pin the user moves (point.zig:12-50:
     "programs cannot address the scrollback or the visible viewport").
     It exists because srWindow is not such a fact. The user can drag the view over scrollback at any time
     without touching a cell, and a painter that re-derived its rows from the live window then wrote the
     current frame into the history it was asked not to disturb -- measured 2026-09-24: the view at row 0
     of a buffer whose content sat at row 30, one prompt line through the renderer, rewrote buffer row 29
     and blanked row 30. Unset until an adopt or a paint claims the rows; while unset the window is the only
     evidence of where the model would go, and deriving it is both correct and what a model that has never
     painted owes. May be negative when the gutter reaches above the buffer's first row. */
  int baseRow;
  int baseSet;

  /* The SGR sequences consumed since the last rc_sgr_take()/rc_sgr_clear(), verbatim. This exists because
     ConEmuHk kept a process-wide copy of the attribute state (CEAnsi::gDisplayParm) and re-applied it
     whenever it rendered a chunk itself, so a chunk this model painted left that copy stale -- the exact
     hazard that showed up as a black screen in the Java fast path. That leg is retired, so nothing
     replays these bytes any more: what is left is the witness, which the gate uses to prove the parser
     captured the escapes it consumed byte for byte. `cap` holds the sequence being parsed, which may
     have started in an earlier chunk. */
  uint16_t sgrEcho[RC_SGR_ECHO_MAX];
  int      nSgrEcho;
  int      nSgrDrop;      /* sequences not echoed: the capture or the accumulator filled up */
  uint16_t cap[RC_SGR_CAP_MAX];
  int      nCap, capLost;

  /* Called from inside rc_feed() the moment the gutter is full, so a chunk bigger than the model can
     hold is painted in the middle of parsing instead of losing its earliest lines. The hook may call
     rc_paint_done() and must not touch the parser: it runs with a consistent grid and a half-consumed
     input buffer. NULL in the host tests, which never paint. */
  void (*onFlush)(void *ctx);
  void *flushCtx;
} RcGrid;

/* RC_ESC_N is deliberately absent: esc_end() measures SS2/SS3 (ESC N, ESC O) as the introducer only,
 * because both consoles then print the following graphic byte -- so the parser returns to ground
 * immediately and the next unit is ordinary text, not a swallowed shift-out. */
enum
{
  RC_GROUND = 0, RC_ESC, RC_ESC_INTERIM, RC_CSI, RC_OSC, RC_OSC_ESC
};

#ifdef __cplusplus
extern "C" {
#endif

/* Clears the model to `cols` x `rows` and seeds the SGR state from defAttr, the way ConEmu's first
 * ReSetDisplayParm would. The whole grid is then the viewport (no gutter). Returns 0 when the
 * geometry is out of range. */
int  rc_reset(RcGrid *g, int cols, int rows, uint16_t defAttr);

/* The same, with a gutter: the grid is winRows + histRows tall and only its last winRows rows are the
 * console window. histRows 0 is exactly rc_reset(). */
int  rc_reset_hist(RcGrid *g, int cols, int winRows, int histRows, uint16_t defAttr);

/* Gutter height: viewport scrolls the model can absorb before the painter has to catch up. 0 when the
 * model has no gutter, which is how the host tests run. */
int  rc_scroll_room(const RcGrid *g);

/* Consume n UTF-16 units. Incomplete sequences stay in the model and are resumed by the next call,
 * so a sequence split across any number of chunks parses exactly once. */
void rc_feed(RcGrid *g, const uint16_t *units, int n);

/* The console attribute for an SGR state: ExtPrepareColor's order, with Far3Color's folding and its
 * fg==bg correction applied only when the background actually went through that fold. */
uint16_t rc_attr(const RcSgr *s, uint16_t defAttr);

/* Display columns of one code point, per the ansi_width tables (0, 1 or 2; controls come back 0). */
int rc_width(uint32_t cp);

/* Test/painter helpers: damage queries and a direct cell write that keeps the wide-cell pair rule. */
int  rc_row_dirty(const RcGrid *g, int row);
void rc_clear_dirty(RcGrid *g);
void rc_mark_all_dirty(RcGrid *g);

/* Claiming where the model's rows are (see RcGrid::baseRow). rc_set_base is what a flush owes once the
   operations it planned actually landed; rc_drop_base is the other half of the promise: the console did
   something the model cannot account for, so the next flush re-derives the anchor from the window and
   repaints the viewport rather than writing rectangles at rows nothing owns. Dropping the claim therefore
   marks the damage -- a caller that forgot one would keep the stale screen. */
void rc_set_base(RcGrid *g, int row);
void rc_drop_base(RcGrid *g);

/* Why a row's line continued: RC_WRAP_NONE / _FORCED / _PAD (S5). A consumer that joins rows for copy,
   pagination or export needs this, and nothing else in the model can tell a soft break from a hard one. */
int  rc_row_wrap(const RcGrid *g, int row);
void rc_forget_row_state(RcGrid *g);       /* drops the viewport's wrap claims *and* its semantic marks: an
                                              adopt can read back neither (see Render.cpp) */

/* Which FTCS region a row begins, RC_PM_* (I23), and at which column. Neither reaches the console, so
   neither survives an adopt -- same contract as rc_row_wrap. `rc_last_exit` is the exit code of the most
   recent OSC 133 ; D, or -1 if none arrived; `rc_prompt_marks` counts marks this grid has laid down, which
   is how a caller tells "this shell integrates" from "this stream never said 133 once". */
int  rc_row_mark(const RcGrid *g, int row);
int  rc_mark_col(const RcGrid *g, int row);
int  rc_last_exit(const RcGrid *g);
unsigned long rc_prompt_marks(const RcGrid *g);

/* Set when a sequence that could move the cursor or choose the scrolling rows was consumed unmodelled
   (S3). The painter re-adopts the console once after a chunk lands, then clears it. */
int  rc_model_suspect(const RcGrid *g);
void rc_clear_model_suspect(RcGrid *g);

/* 1 while the alt screen is engaged (see RcGrid::alt). The painter must not spend a scroll on a window
   slide or a buffer scroll then: an alternate screen has no scrollback, so the row that leaves its top is
   gone and the whole viewport is repainted instead. */
int  rc_in_alt(const RcGrid *g);

/* Units of SGR text waiting to be taken; 0 after a take or a clear, or when the chunk had none. */
int  rc_sgr_pending(const RcGrid *g);

/* Copy the pending SGR text into dst (at most cap units) and clear it. Returns the units copied, or -1
   when cap is too small -- in that case nothing is cleared, because losing the echo means losing colour
   parity with the fallback leg, which is a bug rather than a policy. */
int  rc_sgr_take(RcGrid *g, uint16_t *dst, int cap);

/* Discard the pending SGR text without copying it. A caller that owns every byte of the stream has no
   one to replay it to, but it must still drain the accumulator once per chunk or the sequences of the
   whole session pile up in it -- and then overflow, which would make nSgrDrop lie about the parser. */
void rc_sgr_clear(RcGrid *g);

/* A window title is the one OSC effect that leaves no trace in the grid, so the painter has to pull it
   out before the next sequence overwrites the buffer. Non-zero when one is waiting. */
int  rc_title_pending(const RcGrid *g);

/* Copy the pending title into dst (at most cap units) and clear the flag; returns its length, which may
   be 0 -- an explicit empty title (ESC ] 0 ; "" ST) is still a title. -1 when cap is too small, and then
   nothing is cleared. Callers pass RC_TITLE_MAX. */
int  rc_title_take(RcGrid *g, uint16_t *dst, int cap);

/* How many queries are waiting for an answer. The painter loops on this until it drains the queue, and the
   host gate reads it to prove a query armed exactly one reply -- no more, because answering twice would
   leave bytes in the input buffer for the next reader, and no less, because a caller that waits would hang
   on the gap. */
int  rc_report_pending(const RcGrid *g);

/* Pop the oldest armed query: returns its kind (RC_REP_NONE when the queue is empty) and, when `row` and
 * `col` are not NULL, the model row and column the cursor stood on when it was asked. The counter of the
 * outcome belongs to rc_report_result, not here, because only the caller knows whether the console took it. */
int  rc_report_take(RcGrid *g, int *row, int *col);

/* Say what became of the query the take above this call returned: 1 = the console took every record, 0 = the
   write failed or fell short. One call per take, in that order; the model keeps no per-entry history, only
   the two counts. They are here rather than open fields so the model stays the only thing that owns them. */
void rc_report_result(RcGrid *g, int written);

#ifdef __cplusplus
}
#endif

#endif /* ANSIRENDER_RENDER_H */

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
 * visible only in the stats line -- which is the whole reason it counts as a shipped change.
 * -8 is two of them, and both are about rows and bytes that leave the process. The first is the anchor:
 * `row0` used to be re-derived from `srWindow.Top` on every flush, so a user who scrolled up over the
 * scrollback and then let output arrive had *their* history repainted -- measured 2026-09-24: view at
 * buffer row 0, content at row 30, one prompt line, and row 29 was overwritten while row 30 went blank, 72
 * rectangles, nothing declined. The model now claims its own buffer rows (`RcGrid::baseRow`, the same thing
 * conhost's `_virtualBottom` and ghostty's `.active` pin are), a slide is only ever paid for a view the
 * model owns, a scroll moves the model's own rows rather than the whole buffer (`scroll_region`), and the
 * cursor is no longer parked outside the window a plan leaves behind. The second is the answer leg: DSR and
 * DA were counted and dropped, so a program that asked hung. A query now arms a queue entry carrying the
 * cursor as it stood, and `flush_reports` writes the reply back as key events on CONIN$ -- which is why the
 * stats line grew three slots and this build grew a gate-only export.
 * -9 is -8's other half: an *adopt* had the same bug the paint had. A resize rebuilds the grid, which threw
 * the row claim away with it, and the re-read then took its rows from `srWindow` -- so a user who scrolled to
 * their history and then dragged the window shorter watched that history get adopted into the application's
 * screen and painted back one viewport lower. The claim now lives on the handle in bottom form (`prevBase +
 * prevRows - 1`, because a rebuilt grid's `rows` differ and the last content row is the one that means the
 * same thing on both sides) and `rc_anchor_adopt` carries it across, with conhost's straddle rule behind a
 * `reshaped` flag: that rule belongs to a new window size and not to a scroll
 * (`_InternalSetViewportSize` vs `SetViewportOrigin`, screenInfo.cpp:953 / 642), and applying it to every
 * re-adopt would drop the anchor exactly when the user had scrolled furthest away. A -8 binary and a -9 tree
 * agree on every paint and disagree on the first resize after a scroll up, which is why the gate grew a
 * resize leg and this stamp moved with it.
 * -10 is an eye, not a behaviour: `plan()` reports the last flush's own geometry -- the anchor it started
 * from, what it slid, what it paid with the buffer, the row0 it therefore addressed model row 0 at, and
 * whether a move call failed. Every one of those was already in the plan; none of them survived it, and a
 * gate that can only read the console has to infer a claim from where the ink fell. That inference is exactly
 * what the scrolled-backbuffer cases turn on: two rows of the same numbered line, 341 buffer rows apart, is
 * a model painting at a claim its window does not have, and nothing on screen says so. Production is
 * unchanged by it -- the fields are stores on the flush path, and the export is not on its symbol list.
 * -11 is what that eye was for. A buffer scroll -- the leg that pays a newline once the window has no room
 * left to slide -- was addressing `ScrollConsoleScreenBuffer`'s destination as a *relative* offset, and the
 * API has no such reading: conhost turns the target into a displacement by subtracting the source's own top
 * (`getset.cpp:948`, then `TextBuffer::ScrollAndClear`). So `-by` asked for a shift of `-(by + srcTop)`, and
 * the source rect was the band as the plan re-claimed it rather than the band the anchor held before the
 * slide. Together, on the far side of the slide cap (base 340, window 370, `by` 20 -- measured in
 * Render.java's scrolled-back case, and the reason it reads as duplicates 341 and 361 rows apart): the whole
 * model band was hoisted to buffer rows 0..58, over the user's scrollback, and the rows the model then
 * painted as its own were left holding cells by `by` rows too high. Invisible in the window -- those rows are
 * dirty and repainted either way -- and exactly what the user sees by scrolling up. rc_scroll_band now owns
 * that arithmetic, where RenderCheck can pin it without a console; the same call's *column* was shifted by
 * `-winL` for the same reason, which no gate can currently produce (I22) and which the fix closes anyway. A
 * -10 binary and a -11 tree agree on every flush that slides and disagree on the first one that has to pay
 * with the buffer, which is to say: on the scrollback of any session long enough to need one.
 * -12 is the other half of that same scroll, and it is the #34 defect: the *reach* was band-only everywhere,
 * including where the buffer had no room left. Write 380 lines of somebody else's text and then 200 of this
 * program's into a 400-row buffer, against the same program writing the same bytes through the console API
 * directly: the console keeps the last 400 lines in order, while the renderer froze the first 340 of the
 * earlier text in rows 0..339 and destroyed 141 of this program's own -- newest lines dropped, older ones
 * kept, the ring run backwards. A buffer that is full has only one answer to a new line, and conhost's is
 * `IncrementCircularBuffer` (`_stream.cpp:123-126`), which moves the whole buffer and evicts its top; the
 * band stays the limit while there are unused rows *below* it, which is the case -8 measured and -11 fixed
 * the destination of. rc_scroll_band now decides between the two, and the rows inside the claim move to the
 * same places either way, so the paint is untouched by this -- what changes is everything above it. A -11
 * binary and a -12 tree agree on every flush that has room below the claim, which is most of a session, and
 * disagree on the first one after the window reaches the buffer's last row, which is the start of scrolling
 * for anything longer than a screenful.
 * -13 says *which* flush that is, and the first cut of -12 got it wrong in the direction only a census can
 * see. The question is the claim's last row as this flush leaves it (`row0 + rows`), not as it started
 * (`base + rows`), because a slide spends buffer rows without moving a single cell: 19 of a 20-line debt paid
 * by sliding the window still leaves the 20th owed an eviction, and paying it with a band scroll instead left
 * 401 live lines in a 400-row buffer -- measured, in the new census this gate runs, as 399 rows of an
 * unbroken numbered session, one line missing from the middle of it and the last row blank. Sliding as far as
 * the buffer allows puts `row0` on `bufH - rows` by construction, so every mixed flush is an eviction and the
 * band answer survives only where the model has unused rows below it while the user is looking somewhere else
 * -- which is now pinned on both sides in RenderCheck. A -12 binary
 * and a -13 tree agree on every flush of a session the window has never run out of room for, and disagree from
 * the first newline that slides the window to the bottom of the buffer.
 * -14 is a leg the renderer was missing rather than a bug it had. A flush may not move a window the user
 * scrolled away from (rule 2, and -8 is what made that true), and conhost pairs that ban with
 * `SnapOnInput`: a key-down brings the cursor back into view (input.cpp:171-178 -> screenInfo.cpp:1631-1666).
 * conhost fires that snap only for a console in VTP mode, which is the mode this renderer exists for the
 * absence of -- so on a ConEmu-rendered console nothing at all moved the view back, and a user who scrolled
 * up to read output and then typed watched their characters go into a screenful of history they could not
 * see. rc_snap_view decides (Paint.h, pinned by RenderCheck without a console), `snap` executes one
 * SetConsoleCursorPosition -- least displacement, no cell written -- and WinSysTerminal calls it on a key
 * that conhost itself would treat as input. A -13 binary and a -14 tree agree on every paint and disagree
 * on the first keystroke after a scroll up.
 * -15 answers a question the Java side has been guessing at: is this console a ConPTY one? WT_SESSION is
 * inherited by a classic conhost window started from inside a WT session, so every env-var test of it
 * mis-classifies that window, and the previous answer at this stamp painted cells into a buffer a
 * serializer was already turning back into VT for a terminal that parses them (see
 * Java_com_hyee_ansirender_NativeRenderer_isPseudoConsole for the source-cited read of VtIo mode off the
 * window class). This stamp changes no paint; it moves the decision to where the fact is. A -14 binary and a
 * -15 tree agree on every console the classifier got right and disagree on the one it got wrong.
 * -16 gates DECRC (`CSI u`) on the private marker. Upstream ConEmu restores unconditionally, and that is
 * a defect a consumer can prove: jline4's capability probe batch opens with kitty's `CSI ?u` query
 * (AbstractTerminal.probeModes), so every probe round jerked the cursor to the last DECSC. WT and ghostty
 * route a private-marker final to their query/ignore arms, which is where this now agrees with them. This
 * stamp changes no paint either; it changes where the cursor stands after a probe.
 * -17 is DECSET 2026. A synchronized region defers its frames now -- *every* frame, including the chunk that
 * opens the region, which is where an application writes the top of its new screen -- and the deferral has two
 * escape hatches that are deliberately not the same: the 100 ms clock ends the region and clears the mode,
 * because a leaked BSU must not cost the rest of the session its pictures, while a full scrollback gutter
 * paints this frame and leaves the region open, because a held scroll evicts history no one can repaint.
 * Six counters came with it (engages, nested, held, timeout, overflow, declined) and the stats array grew by
 * them: RenderJni.cpp, Render.java's slot table and NativeRenderer's are one contract read positionally, and
 * the live gate checks the length. This stamp changes what reaches the screen and when.
 * -18 is the interim set plus DECRQM. CSI intermediates accumulate into a set compared by whole length the way
 * upstream compares its Pvt buffer (Ansi.cpp:1788, :3645, :3657), which retires two spellings that used to pass
 * here as legal: `CSI ! SP q` set a cursor shape, and `CSI ? ! p` ran a hard reset. And `CSI ? <mode> $ p`
 * answers now, for the three bits this model holds (25, the alternate-screen family, 2026) and using only
 * statuses 1 and 2. The permanent pair is never sent: DEC and xterm read 4 as "permanently set" while jline4's
 * doc reads 4 as "permanently reset", so a number those two readers invert lies to one of them -- for 2048 it
 * would promise window sizes arriving in the data stream -- and the asker looks replies up by mode number, so
 * an unanswered id costs it nothing (`parseDecrpm`, AbstractTerminal.java:675-690). No stats slot moved: the
 * queue entry carries the mode and the status, and written replies were already counted.
 * -21 is the OSC 9 safe subset (T7). 9;4 stores a taskbar state and progress, 9;9 stores a working
 * directory as text, and 9;12 is routed into the FTCS 133;B path rather than reimplemented; both stored facts
 * are read-only through the seam (NativeRenderer.taskbar / workingDirectory) and survive a rebuild, because a
 * resize is not a re-open. Nothing here acts: no window means no taskbar to paint, and a directory taken from
 * an output stream stays a string. Every other subcommand -- 9;1 sleep, 9;2 MessageBox, 9;3 set-env, 9;6
 * GuiMacro, 9;7 DoProcess -- keeps counting RC_UN_OSC_PRIV and running nothing, exactly as MSFT sends them to
 * UnknownSequence.
 * -22 is DECAWM (I35): `CSI ?7 h/l` decides whether the margin ends the line or the row wraps at it. The
 * mode left the census's MODE bucket, DECRQM answers it, and RIS/DECSTR put it back on. With it off a glyph
 * that cannot fit the last column is dropped whole -- MSFT clears the same cell it could not fit, and says
 * why (Row.cpp:474-494, "there's no correct alternative way to handle this situation") -- and the cursor
 * holds at the margin instead of opening a row, so a fixed-width status line overwrites one cell forever and
 * no RC_WRAP_FORCED claim is made for a row that never overflowed. Two things came with it: writing a narrow
 * glyph over a wide one's front half now blanks the orphaned back half (the pair is I16's unit, and with no
 * wrap this would be manufactured on every row rather than only where a CUP happened to land), and the
 * margin clamp steps off a trailing half, because a cursor must never rest inside a glyph. The terminfo
 * entry keeps `smam`/`rmam` out, which is a different question from the mode: the entry also describes
 * sessions where ConEmu's own parser reads the stream, and its `?7` arm leaves SetConsoleMode commented out.
 * -19 is DECSTBM's validation, found by re-reading every "upstream does not do it either" reason in these
 * files for an independent one. `CSI 3r` now means rows 3..bottom instead of clearing the region (upstream
 * demands ArgC >= 2 at Ansi.cpp:3142, so a one-parameter call was a silent reset), and an inverted `3;2r` is
 * ignored instead of clearing -- ignoring and clearing are different acts, because clearing hands the next
 * line feed the whole viewport, which is the #47/#48 failure with a new trigger. Both references agree on
 * those two; where this build still splits from MSFT is the clamp it keeps (an out-of-range bottom is pulled
 * to the viewport's last row, and `Pt == Pb` is accepted as a one-row region, because Status.reset() arrives
 * as `CSI 1;1r` and refusing it would leave the bar's region stuck on).
 * -20 is the palette: OSC 4/10/11/104/110/111 (I34), with the grammar taken from MSFT because ConEmu parses
 * these and does nothing. An index below 16 changes a console attribute's colour -- written back through
 * SetConsoleScreenBufferInfoEx read-modify-write, so naming one entry cannot recolour the other fifteen --
 * and at or above 16 it changes only which index a 256-colour or true-colour SGR folds to, because a 4-bit
 * attribute has nowhere else to put it. close() restores the table the handle found. Two things came with
 * it that are not the mode: the vendored fold's `static LastColor/LastIndex` memo is now bypassed when a
 * caller supplies a table (it keyed on the colour alone and would freeze a pre-change answer), and
 * `defAttr` was being copied into the SGR slots as if it were an index when it is an attribute -- with
 * ClrMap an involution, the double conversion is invisible for the palindromic entries and wrong for the
 * rest, so a profile whose default foreground is FORE_BLUE got a red pen over blue cells out of one
 * rc_reset. Control: reverting that conversion fails exactly the four new assertions, all of them
 * `got 0x4 want 0x1`. *
 * -23 is the census table (T6). One static row per RcUnsupported slot -- label, sentence, and whether
 * counting it makes the frame suspect -- so `unsupported()` reads a column where it used to compare against
 * one enum member, and the labels stop being a third thing written down (the enum's comments, this file's
 * stats layout, and two Java report tables said the same eleven names four ways). Nothing moved by a byte:
 * the slot order is the ABI, `stats()` still hands back numbers, and the equality proof is the host gate
 * pinning the whole normalised label list plus a live leg that now compares all eleven names with the dll
 * instead of four indices. `Java_Render_censusNames` is gate-only, like `consolePalette`.
 * -24 is OSC 52 (I36), and the refactor that made room for it. The if-chain that decided what an OSC means
 * is now a table of families -- one row per code set, with the name the report prints and the handler the
 * payload goes to -- because a chain cannot be asked whether two codes are claimed twice or whether a family
 * it forgot exists; `geo_osc_families` asks both, over every code a sender can write. The sink that had been
 * a title buffer is now sized for payloads (RC_OSC_MAX, with the title clipping itself to RC_TITLE_MAX as
 * before, which the existing truncation case still pins). A strict RFC 4648 decoder refuses a whole payload
 * rather than decoding its prefix, and refuses whitespace inside it, so a sender that wrapped its base64 is
 * counted rather than pasted wrong. The whitelist is `c` and the empty field only: Windows has one
 * clipboard, so folding `p` or `s` onto it would answer a different question than the one asked -- where
 * ghostty folds, it is folding onto a primary selection that really exists there. Reads (`52;c;?`) are
 * refused whatever the policy says: the reply would put what the user copied into the console's input
 * stream. The policy defaults to off and is only reachable from the host -- a call, or ANSI_CLIPBOARD read
 * at class init -- because a sequence that could enable itself would make the default mean nothing. Six
 * counters and a policy bit joined the census, appended where I19 says; the live leg reads the system
 * clipboard back through AWT, so the claim is the user's own clipboard, not the model's memory of it.
 * Stamping caveat, learned the hard way this session: a binary can ship with a stale stamp. The -15 build
 * was rebuilt twice without bumping it, so the deployed lib/render.dll and the staged #44 build carried the
 * same string while being different bytes. A version string identifies intent, not content -- ship census
 * is md5 plus size, and the stamp is bumped as part of the edit, never as a closing decoration. */
#define RENDER_BUILD "render-2026-09-26-29"
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
  /* DECSET 2026 held this one: the chunk is parsed and the model owns its bytes, but no console call was
     made and the damage is left marked for the flush that ends the region. Positive, because the caller must
     not replay the bytes -- they are in the model, which is the thing the eventual paint will draw. */
  FLUSH_HELD = 3,
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
 * after the titles and the FTCS counters after those, and the query-reply counters after them -- all new
 * slots, never a moved one. */
#define STAT_UNSUPPORTED 17
#define STAT_TITLES      (STAT_UNSUPPORTED + RC_UN_MAX)
#define STAT_ALT         (STAT_TITLES + 3)
#define STAT_PROMPT      (STAT_ALT + 2)
#define STAT_REPORT      (STAT_PROMPT + 2)   /* replies written, failed, and refused for want of a slot */
#define STAT_SNAP        (STAT_REPORT + 3)   /* views a keystroke brought back onto the model's cursor */
/* DECSET 2026: regions opened, nested BSU, flushes held, and the three ways a region ends without its ESU.
   Appended for the rule every slot in this table follows -- the Java side reads these positionally, so a new
   counter is added at the end and an existing one never moves. The last slot is the live bit, not a count:
   a session that ends inside a region is a different finding from one that never entered. */
#define STAT_SYNC        (STAT_SNAP + 1)
/* OSC 52, appended after the sync family: armed, refused-decode, refused-selection, refused-read, then the
   painter's applied and failed, and last the policy as it stands -- so a census that reports no clipboard
   write can be read as "the switch is off" or as "nobody asked", without guessing. STAT_LAST moves from
   "one past the sync block" to "one past this one", which leaves every earlier index where the Java side
   already reads it. */
#define STAT_CLIP        (STAT_SYNC + 7)
/* The one limit in the parser that a caller cannot otherwise see: a `CSI` whose parameter list is longer than
   RC_CSI_ARGS keeps the first sixteen, exactly as ConEmu's ArgV does, and the surplus is gone. Appended after
   the clipboard block because that is the rule every slot here follows -- nothing that already ships an index
   moves. `Render.java` asserts its own table against this length and against the jar's, so a slot added here
   and forgotten there is a red gate, not a silent zero. */
#define STAT_ARGTRUNC    (STAT_CLIP + 7)
#define STAT_LAST        (STAT_ARGTRUNC + 1)

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
  /* CONIN$, opened the first time this stream asks a question that needs an answer (DSR, DA) and kept until
     close(). Lazily because a session that never asks should not pay for a handle, and a process that has no
     console input at all -- a redirected or headless one -- must not fail any earlier than the query. */
  HANDLE in;
  /* The console's own 16 entries as this handle first found them, and whether it has changed any of them
     since. The palette is console state that outlives the process on a shared buffer, so a renderer that
     recoloured it and left would be a vandal (I34). */
  uint32_t palOrig[16];
  int    palSaved;
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
  /* The rows this handle's model last claimed, kept here rather than only in the grid because a resize
     rebuilds the grid and must not lose the claim with it: rc_anchor_adopt carries it across. `prevWinB` is
     the window's bottom as the last plan left it, which is the half the grid has no room for -- and the half
     that tells a slide the painter made from a scroll the user made. Zeroed when the slot goes back to the
     pool, so a reused handle starts with nothing but the window to go on. */
  int prevSet, prevBase, prevRows, prevWinB;
  /* What the last plan asked the console for, named rather than inferred. Everything the gate can read off
     the screen -- the buffer, the window, the cursor -- says where the console is; none of it says where the
     painter *believed* its rows were, and the defect this records is exactly the difference between the two.
     A row the model wrote at a claim nothing on screen reveals is the #35 class of damage, and it is invisible
     in the cell census. Java_Render_plan reads these back; painting them costs a store per flush. */
  int trSeq, trReason, trBaseSet, trBaseRow, trWinT, trBase, trSlide, trSlideTo, trBufScroll, trRow0,
      trWinTop, trRows, trWinRows, trBufH, trPend, trRuns, trDeclined, trMoveFail;
  unsigned long nFlush, nPaints, nDeclines, nApiErrors, nAligns, nSnaps;
  /* Gate-only fault injection: fail the *i*-th run of the next plan instead of calling the console, once.
     The defect it witnesses (#44) lives on an error path no console state can be coaxed into -- a
     WriteConsoleOutputW that succeeds for run 0 and fails for run 1 -- and "the model lied about having
     painted" is exactly the thing a cell read can see and a green regression cannot. -1 is armed off, which
     is what every handle starts at and what the arming export sets it back to after one hit, so a fault can
     never survive into a later case. Production has no way to reach a non-negative value. */
  int faultRun;
  /* DECSET 2026: the tick of the first flush this region held, valid only while syncHolding is set. The
     timeout is not a nicety -- a program that dies between BSU and ESU would otherwise leave every later
     chunk parsed, modelled and never painted, which is a frozen screen rather than a stale one. MSFT's
     renderer waits 100 ms and then paints anyway, clearing the mode on the way
     (renderer.cpp::_synchronizeWithOutput); this is the same rule read from the only clock this seam has,
     which is the arrival of the next flush.
     A separate `holding` flag rather than a sentinel in the tick itself, because tick 0 is a legal value:
     it is GetTickCount()'s reading at process start and again every 49.7 days, and storing "no region" as
     0 would make the seam forget one hold in that window in exchange for a field. The elapsed test is a
     DWORD subtraction, which is wrap-safe by construction -- the only comparison that survives the clock
     rolling over underneath it. GetTickCount, not GetTickCount64: build.sh's Win8+ API whitelist rejects
     the latter, and this file is built for XP-era consoles as well as for the ones that have it. */
  DWORD syncSince;
  int   syncHolding;
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
                     g_totAltSwitch, g_totAltFail, g_totPromptMark,
                     g_totRepOk, g_totRepFail, g_totRepFull, g_totArgTrunc,
                     g_totSyncEngages, g_totSyncNested, g_totSyncHeld,
                     g_totSyncTimeout, g_totSyncOverflow, g_totSyncDeclined,
                     /* OSC 52: the four reasons the parser gave, folded the way the title pair is. They are
                        counted apart because a rollout reading a single number cannot tell "the host never
                        turned this on" from "applications are sending base64 this build rejects". */
                     g_totClipSet, g_totClipBad, g_totClipSel, g_totClipRead;
/* What the clipboard API answered, on the same reasoning as the titles applied above. */
static unsigned long g_clipCalls, g_clipFails;

/* Put `chars` UTF-16 units from `wide` on the clipboard as CF_UNICODETEXT, or -- when chars is 0 -- leave the
 * clipboard empty. open/empty/set/close, which is the order Win32 documents: without the EmptyClipboard a
 * clear has no way to be expressed at all, and a write leaves whatever other formats the previous owner put
 * there sitting on the clipboard beside it. Returns RC_CLIP_OK, or which call said no (*why is the Win32
 * error, kept apart because "another window owns the clipboard" and "the memory manager refused" are
 * different things to read in a teardown line). */
#define RC_CLIP_OK 0
#define RC_CLIP_OPEN 1
#define RC_CLIP_EMPTY 2
#define RC_CLIP_ALLOC 3
#define RC_CLIP_SET 4

static int clip_apply(const wchar_t *wide, int chars, DWORD *why)
{
  if (!OpenClipboard(NULL)) { *why = GetLastError(); return RC_CLIP_OPEN; }  /* another window owns it */
  if (!EmptyClipboard()) { *why = GetLastError(); CloseClipboard(); return RC_CLIP_EMPTY; }
  if (chars > 0)
  {
    const SIZE_T bytes = (SIZE_T)(chars + 1) * sizeof(wchar_t);     /* +1: CF_UNICODETEXT is NUL-terminated */
    HGLOBAL hg = GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (!hg) { *why = GetLastError(); CloseClipboard(); return RC_CLIP_ALLOC; }
    void *p = GlobalLock(hg);
    if (p) memcpy(p, wide, bytes);
    GlobalUnlock(hg);
    if (!p || !SetClipboardData(CF_UNICODETEXT, hg))
    {
      /* After a successful SetClipboardData the system owns the block, so it is freed on this branch
         only -- freeing it on both is the classic way to corrupt the clipboard. */
      *why = GetLastError();
      GlobalFree(hg);
      CloseClipboard();
      return RC_CLIP_SET;
    }
  }
  CloseClipboard();
  return RC_CLIP_OK;
}

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

/* Scroll the rows a buffer scroll owes up by `by`, filling the rows they vacate.
 *
 * Which rows those are is the planner's answer, not this call's: rc_scroll_band (Paint.cpp rule 1b) gives the
 * band as the *anchor* claimed it before this plan slid the window, moving up by `by` onto the band as it
 * claims it after -- and, once the claim has the buffer's last row and there is no room left below it, the
 * whole buffer instead, so that the oldest lines leave the top the way a terminal's do. A first cut here took
 * the whole buffer unconditionally, and the measurement that ruled it out is worth keeping straight: with the
 * window at buffer row 30 of a 60-row buffer and the user scrolled up to row 0, it moved 30 rows of somebody
 * else's history and dropped its top line to pay for one line of this program's output. The damage was not
 * the reach but the *unconditional* reach -- that buffer was full, so the eviction itself was owed. What is
 * never owed, and what a band-relative source buys, is moving rows the model has no claim on while rows
 * below the claim still sit unused; conhost's ordinary output scroller passes GetVirtualViewport() rather
 * than srWindow (`screenBuffer.cpp:2109,2065`; the field is "not affected by the user scrolling the
 * viewport", screenInfo.hpp:218) and reaches the ring only at `_stream.cpp:123-126`, past the last row.
 * ghostty says the same thing as a type for the ordinary case: a program may address the `.active` rows and
 * nothing else (point.zig:26-30).
 *
 * The destination is an absolute row, which is the half that was wrong here for the whole life of this
 * function: `ScrollConsoleScreenBuffer`'s fourth argument is "the new upper-left position", and conhost turns
 * it into a displacement by subtracting the source's own top (`getset.cpp:948` -- the empty-request guard
 * compares `source.top == target.y` outright, and `TextBuffer::ScrollAndClear` shifts by
 * `target - source.TopLeft`). Handing it the relative `-by` therefore asked for a shift of `-(by + srcTop)`,
 * which on the far side of the slide cap -- base 340, `by` 20 -- moved the model's whole band to buffer rows
 * 0..58. Measured, and it is the #35 defect: the visible window never showed the difference, because its rows
 * are dirty and repainted anyway, and everything the shift destroyed was above it, in the scrollback the user
 * scrolls up to read. */
static LONG scroll_region(HANDLE con, const RcView *v, const RcPlan *p, int modelRows,
                          int by, uint16_t attr)
{
  CHAR_INFO fill;
  COORD dest;
  SMALL_RECT src;
  int top, bottom;
  if (!rc_scroll_band(p, modelRows, v->bufH, &top, &bottom)) return 0L;  /* nothing left to move: not an error */
  memset(&fill, 0, sizeof fill);
  fill.Attributes = attr;
  CH_UNICODE(fill) = ' ';
  dest.X = v->winL;
  dest.Y = (SHORT)(top - by);                 /* absolute, and `by` rows above where the band starts now */
  /* This one subtraction may ask for a row above the buffer's first, and that is the band's own answer rather
     than a bug in it: rc_scroll_band clamps `top` to row 0 without reducing `by`, because a claim whose
     anchor sits above row 0 has already lost those rows -- conhost trims the request to [by..bottom] ->
     [0..bottom-by] itself (host/output.cpp:365-397), and RenderCheck's "gutter:" case pins that arithmetic.
     Shortening `by` here would instead move the model's rows to rows the model no longer claims. */
  src.Left = (SHORT)v->winL;
  src.Top = (SHORT)top;
  src.Right = (SHORT)(v->winL + p->paintCols - 1);
  src.Bottom = (SHORT)bottom;
  SetLastError(0);
  return ScrollConsoleScreenBufferW(con, &src, NULL, dest, &fill) ? 0L : (LONG)GetLastError();
}

static LONG park_cursor(HANDLE con, int x, int y)
{
  COORD c;
  c.X = (SHORT)x;
  c.Y = (SHORT)y;
  SetLastError(0);
  return SetConsoleCursorPosition(con, c) ? 0L : (LONG)GetLastError();
}

/* ------------------------------------------------------ the answers a query asked for ------------- */

/* Two small writers, because the replies are built by hand rather than with a wide printf: `swprintf` with
 * a size argument is the C99 form, and mingw's CRT puts either spelling behind a feature test depending on
 * the standard level. A query that went unanswered hangs the asker, so the formatter must not be the thing
 * that depends on a CRT dialect. */
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

/* The reply text for one queued query, without the introducer: the queue entry says which query, and `it`
 * carries the model position the cursor stood on when it was read, plus the mode and status a DECRQM asked
 * about. Returns the length.
 *
 * DA1 is conhost's own string minus `;52`, the clipboard access that parameter advertises and that this
 * renderer does not model -- conhost says the same thing itself when its ClipboardWrite feature is off
 * (adaptDispatch.cpp:1454-1461), and the service class `61` is what the emulator underneath really reports.
 * Parity is the point rather than pedantry: a chunk this library declines goes to the console unparsed, and
 * conhost answers *that* query, so a program must not meet two identities in one session. DA2 is conhost's
 * `>0;10;1` (adaptDispatch.cpp:1471-1474): a VT100, firmware 1.0, PC keyboard.
 *
 * DECRPM is the one reply whose text is decided before the queue is walked, because it is about a point in
 * the stream rather than about the screen at the end of it: `it->mode` is the number that was asked and
 * `it->status` is what that mode was when the request was read. ConEmu has no such reply, so there is no
 * upstream string to copy -- the shape is the VT500 one, `CSI ? <mode> ; <status> $ y`, and only the two
 * statuses this model can prove ever appear; Render.cpp's `mode_status` says why the permanent pair are left
 * unasked and unanswered. */
static int reply_text(int kind, const RcGrid *g, const RcView *v, const RcPlan *p,
                      const struct RcReportItem *it, wchar_t *out, int cap)
{
  int n = 0;
  switch (kind)
  {
    case RC_REP_DSR:                              /* "are you there" -- "ready" */
      w_lit(out, &n, cap, "\x1b[0n");
      break;
    case RC_REP_CPR:
    {
      /* The same arithmetic the painter used to place the cursor in this frame: model row `it->y` is buffer
         row `row0 + y`, and a CPR counts from the *window's* top, so the window the plan leaves behind is
         part of the answer. Clamped, because a cursor below a window the user has scrolled up to the top of
         is not on any screen -- a row of 0 or a row past the bottom would be an answer no parser was
         written to read. */
      int row = p->row0 + it->y - p->winTop + 1;
      if (row < 1) row = 1;
      if (row > g->winRows) row = g->winRows;
      /* Columns need no clamp: the model row is the buffer row (I7), so a column right of the window is a
         real cell the user scrolls sideways to see, and conhost reports exactly that (position less the
         viewport origin, 1-based). */
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
    case RC_REP_OSC:
    {
      /* `OSC 4;<idx>;rgb:RRRR/GGGG/BBBB ST`, or without the index for a default (`OSC 10;...`). That is
         MSFT's own spelling scaled to 16 bits per component -- adaptDispatch.cpp:3338 and :3417, whose
         comment says the scaling exists "to match xterm's 16-bit color report format". The colour
         reported is the one this console will really show: for a default that is the entry the request
         folded to, not the RGB that was asked for, because a 4-bit terminal has no other answer to give
         (I34). */
      const uint32_t c = it->status;                    /* COLORREF order, 0x00BBGGRR */
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

/* Hand every armed query its answer, as key events on the console's input stream -- which is how conhost
 * does it: "this will generate two key presses (one down, one up) for every character in the string and
 * place them into the head of the console's input stream" (outputStream.cpp:43-45), built by
 * SynthesizeKeyEvent(down, 1, vk 0, scan 0, ch, ctrlState 0) (inputBuffer.cpp:799-816). Nothing about the
 * screen moves here, which is why this is the last thing a flush does rather than part of the plan: the
 * reply is about the *reader*, and a program blocked on `tput rows` must be woken even by a chunk that
 * painted nothing at all.
 *
 * Only ever called on a flush that is returning success. A declined chunk is replayed to the console
 * unparsed and conhost answers the same query itself, so answering here too would leave a second reply in
 * the input stream for the next reader to trip over. */
static void flush_reports(RcHandle *h, const RcView *v, const RcPlan *p)
{
  RcGrid *g = h->g;
  while (rc_report_pending(g) > 0)
  {
    struct RcReportItem it;
    const int kind = rc_report_take(g, &it);
    wchar_t txt[64];
    const int n = reply_text(kind, g, v, p, &it, txt, (int)(sizeof txt / sizeof txt[0]));
    if (n <= 0) { rc_report_result(g, 0); continue; }   /* a kind with no reply: counted, never silent */
    if (h->in == INVALID_HANDLE_VALUE)
      h->in = CreateFileW(L"CONIN$", GENERIC_READ | GENERIC_WRITE,
                          FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
    if (h->in == INVALID_HANDLE_VALUE)
    {
      /* No input stream to answer into: this handle is attached to a console with no readable input, and
         every question the stream asked from now on goes unanswered. One sentence in lastError, and the
         census count, is the whole report -- a per-query retry here buys nothing. */
      snprintf(h->lastError, sizeof h->lastError, "reply: no CONIN$ (%lu)", (unsigned long)GetLastError());
      h->nApiErrors++;
      rc_report_result(g, 0);
      while (rc_report_pending(g) > 0) { rc_report_take(g, NULL); rc_report_result(g, 0); }
      return;
    }
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
    const BOOL ok = WriteConsoleInputW(h->in, rec, (DWORD)nrec, &written);
    rc_report_result(g, (ok && written == (DWORD)nrec) ? 1 : 0);
    if (!ok || written != (DWORD)nrec)
    {
      snprintf(h->lastError, sizeof h->lastError, "reply=%lu", (unsigned long)GetLastError());
      h->nApiErrors++;
    }
  }
}

/* Push palette entries at the console, and put the geometry back if the round trip moved it.
 *
 * Read-modify-write, because `SetConsoleScreenBufferInfoEx` replaces the *whole* table: an application that
 * set one colour must not silently recolour the user's other fifteen. `src` supplies the colours for the bits
 * set in `mask`; the first write of a handle also records what the console had, so close() can hand it back.
 *
 * The round trip is not inert, and this is the part that was paid for: on this machine's conhost, writing the
 * struct straight back after reading it costs the window one row (srWindow.Bottom 29 -> 28 for a 30-row
 * window). The next plan then reads "the console's shape is not the model's" and declines, so setting a
 * colour would have shrunk the user's viewport and refused to paint for the rest of the session -- and the
 * same thing happened at close(), where a 24-row leg found a 23-row window. Repair it through the API that
 * owns the window rect, and only when the console actually disagrees. `keep` is the shape to preserve: the
 * flush passes what it read at the top of the same frame, and close() reads one fresh, because there is no
 * frame to agree with. Returns 0 when the palette write itself failed. */
static int apply_palette(RcHandle *h, const uint32_t *src, uint16_t mask,
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
  /* `wAttributes` is left exactly as it was read. On this console that field *is* the pen -- the flush above
     has just set it from the plan -- so writing the model's default into it would fight
     SetConsoleTextAttribute every frame for a colour the application asked for once. An OSC 10/11 is
     therefore model-side here: every cell this library writes carries an explicit attribute, so the effect is
     complete for output and differs only for a fill conhost makes itself (I34). */
  if (!SetConsoleScreenBufferInfoEx(h->con, &ex))
  {
    /* Left dirty on purpose: the next flush tries again, and the count says it is not landing. */
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
     thing guaranteed to disagree with it. A decline also ends any synchronized region: the hold is a claim that
     the model and the console will meet again at the ESU, and a chunk that could not be executed is the one
     event that proves they will not -- the frame the region was protecting is now the frame the adopt path has
     to repaint anyway, so holding the next one would only delay the recovery. */
#define DECLINE(code) do { h->nDeclines++; \
                           if (g->sync) { g->sync = 0; g->nSyncDeclined++; h->syncHolding = 0; } \
                           if (h->landedChunk) { h->lastReason = p.reason; return FLUSH_RESYNC; } \
                           return (code); } while (0)

  if (h->con == INVALID_HANDLE_VALUE || !view_of(h->con, &v, &csbi))
  {
    snprintf(h->lastError, sizeof h->lastError, "flush: no console (%lu)", (unsigned long)GetLastError());
    g->pendingScrolls = 0;
    rc_drop_base(g);                 /* nothing was read, so nothing is known about where the rows are */
    return FLUSH_API;
  }
  rc_plan_paint(g, &v, &p);
  h->lastReason = p.reason;
  h->nFlush++;
  /* The census of this flush, taken before anything is executed: a plan that later fails halfway is exactly
     the case worth reading back, and a field filled after the calls would say nothing about it. `trBase` is
     the claim the plan started from, which is the row0 it computed minus whatever it then slid -- the one
     number the screen itself cannot show. */
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
  h->trDeclined = (p.reason == RC_PLAN_NOGEOM) ? 1 : 0;
  h->trMoveFail = 0;

  if (p.reason == RC_PLAN_NOGEOM) DECLINE(FLUSH_NOGEOM);

  /* DECSET 2026, and the whole of what the mode does from here: the plan this chunk produced is thrown away
     unexecuted, the damage it was built from is left marked, and the next flush therefore paints everything
     the region accumulated in one go. Nothing is *stored* about the deferred rows -- the model already holds
     them, and a second copy of a 4 MB grid to say "these cells changed" would be the worst kind of honesty.
     *
     The timeout is what makes this safe to ship rather than merely correct: the hold is a promise that an ESU
     arrives, and the only evidence that it did not is the next chunk asking to be painted. So the region's
     first held flush starts a clock -- and is itself held, see below -- and a flush that finds the clock past
     RC_SYNC_TIMEOUT_MS paints, and clears the mode while it is at it, exactly as MSFT's renderer does
     (renderer.cpp:540-570: `WaitOnAddress` for at most `timeout = 100` ms, then
     `SetRenderMode(Mode::SynchronizedOutput, false)`), because an application that leaked its BSU must not
     have the rest of its session swallowed one frame at a time. A region that never sees another chunk needs
     no such mercy: nothing is waiting to be shown, and the screen holds the last frame it was given.
     *
     The replies go out either way. A query's answer is about the reader, not the screen (see
     flush_reports above), and a program that asks `tput rows` inside its own synchronized region while we
     wait for its ESU is a program that hangs. Its CPR is answered from the plan this flush declined, which
     describes exactly where the rows will be when the region ends.
     *
     An empty plan is not held: a chunk of cursor moves only opens or closes the region, and counting those as
     holds would make the census say "frames were deferred" about a session that deferred none.
     *
     The hold has a capacity limit, and it is the console's, not the region's. scroll_up asks for a paint once
     pendingScrolls fills the gutter (Render.cpp:471) because that is the last moment the rows about to be
     evicted still exist on screen; a flush that answers "not yet" to that request does not stop the model
     scrolling, so the next line the program prints pushes history out of a buffer the console never painted
     and it is gone. So a full gutter outranks the mode: paint this frame, count the preemption, and leave the
     region open -- the next chunk can hold again, and it will get its own RC_SYNC_TIMEOUT_MS of it. */
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
      /* The frame that starts the clock is deferred like every other one in the region. Letting it through
         would be a different and much weaker promise -- "the second frame onward is atomic" -- and the first
         frame is where the tear shows: an application writes its BSU together with the top of the new screen,
         so a renderer that paints that chunk has just drawn the top of the new frame over the old one before
         starting to be careful. The clock is still one per region: only a flush that finds no clock running
         sets one, and a held flush never re-arms it, so 100 ms bounds the age of the region and not the gap
         between its chunks -- MSFT's floor of ~10 FPS for a region that never closes, unchanged. */
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
  /* Set by anything that leaves a row this plan owns unpainted. The moves have `movedAsPlanned` and the
     anchor to fall back on; the *cells* had no watch at all -- `rc_paint_done` at the end of the flush
     clears the whole dirty array, so a run that was refused stayed stale on the screen while the model
     called it current, and nothing re-marked it. `paintUndone` is that watch. */
  int paintUndone = 0;

  /* Order is the plan's: slide, then scroll, then cells. Any other order moves the wrong rows.
     `movedAsPlanned` is why the two are watched at all: the model's anchor may only move with rows the
     console really moved, or every later rectangle would be addressed to a row nothing owns. */
  int movedAsPlanned = 1;
  if (p.slideTo >= 0)
  {
    LONG e = park_cursor(h->con, v.winL, p.slideTo);
    if (e) { snprintf(h->lastError, sizeof h->lastError, "slide=%ld", e); h->nApiErrors++; h->trMoveFail = 1; movedAsPlanned = 0; }
    else { landed = 1; h->landedChunk = 1; }
  }
  if (p.bufScroll > 0)
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
  /* The model owns these buffer rows from here on -- including when nothing moved, which is the case that
     matters: claiming the anchor at the first paint is what stops a later flush from re-deriving it from a
     window the user has since dragged over scrollback. A slide carries it down with the window; a buffer
     scroll leaves it where it is and moves the cells under it, so both plans end on the same `p.row0`, and
     a pair that did not land may not be claimed at all. */
  if (movedAsPlanned) rc_set_base(g, p.row0);
  else rc_drop_base(g);
  /* The claim travels to the handle in the form a rebuild can carry: bottom rather than top, because the
     next grid's `rows` may not be this one's. Only what the console really moved may be remembered, so a
     pair that did not land leaves `prevSet` at whatever the grid says. */
  h->prevSet = g->baseSet;
  h->prevBase = g->baseRow;
  h->prevRows = g->rows;
  h->prevWinB = p.winTop + g->winRows - 1;

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
        paintUndone = 1;               /* every row of this plan is still unpainted */
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
        /* The gate's armed fault takes this run's place, once (see RcHandle::faultRun). It reports the same
           shape a real refusal does -- a nonzero error, nothing on screen -- because the code under test is
           what happens *after* the error, not the error itself. */
        LONG e;
        if (h->faultRun == i) { h->faultRun = -1; e = (LONG)ERROR_INVALID_PARAMETER; }
        else e = write_rect(h->con, &v, &p, top, nrows, lo, hi, h->cells);
        if (e)
        {
          snprintf(h->lastError, sizeof h->lastError, "rect r%d x%d c%d..%d =%ld", top, nrows, lo, hi, e);
          h->nApiErrors++;
          paintUndone = 1;             /* and the runs after this one never ran either */
          break;                       /* the row below would land in the wrong place: stop */
        }
        landed = 1;
        h->landedChunk = 1;
        h->nPaints++;
      }
    }
  }

  if (p.attrChanged && !SetConsoleTextAttribute(h->con, (WORD)p.attr))
  {
    /* An attribute the host refused is an attribute the console does not have, and the model's next frame
       will not repaint it -- it only writes what changed. Counted, because a silent mismatch between the
       model's attribute and the cell's is exactly the kind of divergence that reads as a colour bug. */
    snprintf(h->lastError, sizeof h->lastError, "attr=%lu", (unsigned long)GetLastError());
    h->nApiErrors++;
  }
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
      if (!SetConsoleCursorInfo(h->con, &ci))
      {
        snprintf(h->lastError, sizeof h->lastError, "cursorinfo=%lu", (unsigned long)GetLastError());
        h->nApiErrors++;
      }
    }
  }
  if (h->g && h->g->palTouched)
  {
    /* OSC 4 wrote some of the first sixteen entries (I34). The write and the geometry repair it
       forces are the same code close() uses, so neither path can move the user's window. */
    if (apply_palette(h, h->g->pal16, h->g->palTouched, &csbi)) h->g->palTouched = 0;
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

  /* The clipboard, placed next to the title for the same reason: it is an effect of the chunk that lives
   * outside the screen buffer, so a failure here cannot spoil a rectangle and is counted rather than
   * declined.
   *
   * The UTF-8 to UTF-16 conversion is strict (`MB_ERR_INVALID_CHARS`), which is a deliberate split from
   * ghostty handing the bytes over unvalidated (`stream_terminal.zig:722-725`): it stores `text/plain` and
   * the reader interprets it later, while a Windows clipboard entry has to *be* UTF-16 now, so malformed
   * input chooses between U+FFFD sprinkles and no write at all. "Nothing, and a counter" is the answer the
   * application can still act on; a quietly repaired paste is data the sender never sent.
   *
   * A zero-length payload is a real request -- clear the clipboard -- so n == 0 writes an empty string
   * rather than being skipped (xterm's grammar, and ghostty's `52;;` test at
   * `osc/parsers/clipboard_operation.zig:109-122`).
   *
   * Nothing here is restored on close(). The palette is, because OSC 4 changes console state this library
   * was handed and leaves behind; the clipboard is the user's, and snapshotting it at open() would mean
   * *reading* it -- the operation the read half of this sequence is refused for.
   *
   * One exposure it keeps from the title: a model rebuilt between the chunk that armed the request and the
   * flush that would have applied it drops the pending write. Both are one-chunk effects, and the
   * alternative is a 12 KB copy on every resize. */
  if (rc_clip_pending(g))
  {
    uint8_t raw[RC_CLIP_MAX];
    const int n = rc_clip_take(g, raw, (int)sizeof raw);
    if (n < 0) h->nApiErrors++;                  /* cannot happen: RC_CLIP_MAX is the model's own cap */
    else
    {
      wchar_t wide[RC_CLIP_MAX + 1];
      /* A zero-length payload is a request to clear the register, and it has no text to convert:
         MultiByteToWideChar answers 0 for an empty input, which is the same answer it gives for invalid
         bytes. Treating the two alike made `OSC 52;;` -- the one spelling that means "forget what I copied"
         -- fail as if it were a bad encoding. */
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
          /* Which Win32 call refused, and with what: `clip=o=5` is a clipboard another window owns right
             now, `clip=s=1418` is a format nobody will render, and reading them alike would send a rollout
             looking in the wrong place. */
          static const char stage[] = "?oeas";                        /* indexed by RC_CLIP_* */
          g_clipFails++;
          snprintf(h->lastError, sizeof h->lastError, "clip=%c=%lu",
                   (r >= 0 && r < (int)sizeof stage) ? stage[r] : '?', (unsigned long)why);
        }
      }
    }
  }

  /* The queries this chunk armed, answered after the screen they describe is on the console and before the
     model is told the frame is over: a CPR reports where the cursor was when the question was read, and the
     rows it is measured against are the ones this flush just placed. */
  flush_reports(h, &v, &p);

  /* Done first, dropped second, and the order is the whole fix. rc_paint_done consumes the scrolls the plan
     performed and clears the damage array; on a flush whose runs were refused, that cleared array is a lie
     about rows still sitting unpainted on the console, and nothing else would ever re-mark them.
     rc_drop_base is the re-mark -- it is the same recourse a refused *move* already takes, for the same
     reason: better one whole-viewport repaint on the next flush than a model that quietly disagrees with the
     screen until a geometry change or a re-adopt happens to rebuild it. The anchor claim is not touched: a
     refused *run* addresses the right rows and misses their contents, which is a weaker failure than the
     refused *move* above, where the addresses themselves went wrong. */
  rc_paint_done(g);
  if (paintUndone) rc_drop_base(g);
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
static int align_grid(RcHandle *h, int reshaped);
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
  /* Hand the console back the palette this handle found, before the model that remembers it goes away.
     Read-modify-write for the same reason the flush does it, and the entries still owed (a refusal left
     them dirty) go back too -- the user's table is the one that was there first. */
  if (h->palSaved && h->con != INVALID_HANDLE_VALUE)
  {
    CONSOLE_SCREEN_BUFFER_INFO keep;
    if (GetConsoleScreenBufferInfo(h->con, &keep))
      apply_palette(h, h->palOrig, 0xFFFF, &keep);
    h->palSaved = 0;
  }
  drop_model(h);
  free(h->cells);
  h->cells = NULL;
  h->ncells = 0;
  /* The claim goes with the slot: a reused handle must start as knowing nothing but the window, or a
     previous session's rows would anchor the next one's first paint. */
  h->prevSet = h->prevBase = h->prevRows = h->prevWinB = 0;
  if (h->con != INVALID_HANDLE_VALUE && h->ownsCon) CloseHandle(h->con);
  h->con = INVALID_HANDLE_VALUE;
  h->ownsCon = 0;
  if (h->in != INVALID_HANDLE_VALUE) CloseHandle(h->in);
  h->in = INVALID_HANDLE_VALUE;
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
  /* Colours and the default attribute are application-set state, and a rebuild is the application's
     resize, not its reset: dropping them here would hand a session back the colours it asked to leave
     behind. `defAttr` is frozen against the *console* (I12), never against an OSC 10/11 that moved it. */
  uint32_t keepPal[256], keep16[16];
  uint16_t keepTouched = 0;
  uint16_t keepAttr = (uint16_t)defAttr;
  /* The OSC 9 face (T7) is application-set state too: a resize is not a re-open, and a shell that told the
     terminal where it is does not repeat itself because the window changed height. */
  int keepTb[3] = { 0, 0, 0 }, keepCwd = 0, keepWrap = 1;
  int keepCols = 0, keepTabsDefaults = 1;
  uint8_t keepTab[RC_MAX_COLS];
  uint16_t keepCwdBuf[RC_TITLE_MAX];
  const int haveKeep = h->g != NULL;
  if (haveKeep)
  {
    memcpy(keepPal, h->g->palette, sizeof keepPal);
    memcpy(keep16, h->g->pal16, sizeof keep16);
    keepTouched = h->g->palTouched;
    keepAttr = h->g->defAttr;
    keepTb[0] = h->g->taskbarState; keepTb[1] = h->g->taskbarProgress; keepTb[2] = h->g->taskbarSeen;
    keepWrap = h->g->wrapMode;
    /* The tab table is the same kind of fact as the palette: something the application claimed, which a
     * resize did not revoke. Beyond the old width the defaults reappear if nobody cleared them
     * (`rc_tabs_widen`), which is MSFT's `_InitTabStopsForWidth` (:2799-2817) and the half of the rule that
     * separates a resize from a reset. */
    memcpy(keepTab, h->g->tabStop, sizeof keepTab);
    keepTabsDefaults = h->g->tabsDefaults;
    keepCols = h->g->cols;
    keepCwd = h->g->nCwd;
    if (keepCwd > 0) memcpy(keepCwdBuf, h->g->cwd, (size_t)keepCwd * sizeof keepCwdBuf[0]);
  }
  drop_model(h);
  h->g = fresh;
  if (haveKeep)
  {
    memcpy(fresh->palette, keepPal, sizeof keepPal);
    memcpy(fresh->pal16, keep16, sizeof keep16);
    fresh->palTouched = keepTouched;
    fresh->defAttr = keepAttr;
    fresh->taskbarState = keepTb[0];
    fresh->taskbarProgress = keepTb[1];
    fresh->taskbarSeen = keepTb[2];
    fresh->wrapMode = (uint8_t)keepWrap;   /* a resize is not a request to start wrapping again */
    memcpy(fresh->tabStop, keepTab, sizeof keepTab);
    fresh->tabsDefaults = keepTabsDefaults;
    rc_tabs_widen(fresh, keepCols);   /* a resize is not a reset: only the tail it revealed gets the interval */
    if (keepCwd > 0) { memcpy(fresh->cwd, keepCwdBuf, (size_t)keepCwd * sizeof fresh->cwd[0]); }
    fresh->nCwd = keepCwd;
  }
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
  const int wasRows = h->g ? h->g->winRows : 0;
  if (!build_model(h, v.bufW - v.winL, v.winB - v.winT + 1, h->defAttr, status)) return 0;
  /* Only a rebuild that changed the window's height is a resize. conhost draws the same line
     (_InternalSetViewportSize vs SetViewportOrigin, Paint.cpp), and a re-adopt that merely re-read a console
     whose shape never changed must not drop an anchor the user's scroll-wheel put a whole screen away from
     the window -- that is the one case the anchor exists for. */
  const int shaped = (wasRows != 0 && h->g->winRows != wasRows);
  return align_grid(h, shaped) ? 1 : (*status = OPEN_NO_CONSOLE, 0);
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
  if (r >= 0 && rc_model_suspect(h->g)) align_grid(h, 0);
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
    const int cheap = (h->adopt == RC_ALIGN) && align_grid(h, 0);
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
  slot->in = INVALID_HANDLE_VALUE;                /* CONIN$ is opened by the first query that needs it */
  slot->prevSet = slot->prevBase = slot->prevRows = slot->prevWinB = 0;
  slot->trSeq = 0;                              /* a new session has no last plan to report */
  slot->adopt = RC_ALIGN;                         /* a new session: the window is all it knows */
  slot->declines = 0;
  slot->stopped[0] = 0;
  slot->cells = NULL;
  slot->ncells = 0;
  slot->defAttr = (uint16_t)defAttr;
  /* A slot is reused, so a fresh model must not be reported with the previous one's counters: the gate
     reads stats()[2] and [3] as "this model declined / failed nothing", and NativeRenderer's rollout
     report says the same about the model it is running. */
  slot->nFlush = slot->nPaints = slot->nDeclines = slot->nApiErrors = slot->nAligns = slot->nSnaps = 0;
  slot->faultRun = -1;                      /* a reused slot must not inherit a fault it never armed */
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
 * Adopt whatever the console currently shows: the model's rows, the cursor, the attribute. Called before the
 * first chunk, after any FLUSH_NOGEOM, and after a chunk that swallowed a sequence with the reach to move a
 * cursor (see RcGrid::modelSuspect). Parser state is kept, so a half-parsed escape still finishes.
 *
 * "The model's rows" and "the window's rows" are the same thing until the model has a claim on the buffer --
 * and after a resize rebuilt the grid under a view the user had scrolled away, they are not: the claim
 * carries (rc_anchor_adopt), and the read follows it, so the rows the user is looking at are left alone
 * rather than adopted into the application's screen and painted back one viewport lower. `reshaped` is
 * that caller's knowledge, which this function cannot recover: by the time it runs, the grid already has the
 * new height and the console already has the new window, and the two agree by construction.
 */
static int align_grid(RcHandle *h, int reshaped)
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
  const int readTop = base + hist;    /* buffer row of the model's first viewport row */
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
  /* The rows read land on the viewport, i.e. on the model's last winRows rows. What sits above them in the
     buffer is the user's scrollback: unread, unpainted, and unreachable by the cursor -- and when the anchor
     was carried across a rebuild, some of it sits *below* the window the user scrolled to as well. */
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
  g->cy = (v.curY >= readTop && v.curY <= readTop + g->winRows - 1) ? v.curY - base : hist;
  g->pendingScrolls = 0;
  /* The rows the read came from are now the model's, and from here the painter never asks the view again: a
     user who scrolls up a moment later moves a view, not a mapping. This is the claim a first flush would
     otherwise make -- and the claim a resize rebuilds the grid *around*, which is the whole point of reading
     at `base` instead of at `v.winT`. */
  rc_set_base(g, base);
  h->prevSet = g->baseSet;
  h->prevBase = g->baseRow;
  h->prevRows = g->rows;
  h->prevWinB = v.winB;
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
  return (jint)align_grid(handle(ph), 0);
}

/**
 * Bring the model's cursor row back into the window, because the user just typed at it. conhost does this
 * for itself in `SnapOnInput` -- for a VTP console only (input.cpp:171-178), and this renderer runs where
 * VTP is off, so the leg has to exist here or nowhere. See Paint.h::rc_snap_view for why the target is the
 * cursor's row and not the buffer's last one.
 *
 * One console call, and it is the call the slide already makes: `SetConsoleCursorPosition` makes the row
 * visible by moving the window the least way it can, which is the same `MakeCursorVisible` conhost's snap
 * routes through. No cell is written. The buffer already holds the rows this model painted, and the window
 * only changes which of them the user is looking at -- so a snap cannot damage history, which is the whole
 * reason it is allowed to move a view the user chose. The plan's other operations are not on this path:
 * pendingScrolls and the damage stay exactly as they are, and a snap between two flushes is invisible to the
 * next one except that its window now sits on the model's rows again.
 *
 * The enum from Paint.h is returned verbatim, so a caller that wants to know whether anything moved reads
 * RC_SNAP_PARK back; a park that the console refused is counted as an API error and answers NOCHANGE-style
 * 1 all the same, because the model's claim is what it was either way and the next flush re-derives the
 * view from the console like every flush does.
 */
JNIEXPORT jint JNICALL Java_com_hyee_ansirender_NativeRenderer_snap(JNIEnv *env, jclass cls, jlong ph)
{
  (void)env; (void)cls;
  RcHandle *h = handle(ph);
  if (!h) return RC_SNAP_NOGEOM;
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

/**
 * Is the console this process is attached to a pseudo-console -- the headless conhost a ConPTY client
 * (Windows Terminal, VS Code, any agent driving a pty) puts between the application and the terminal that
 * parses the escapes itself?
 *
 * The answer is read off the console's window rather than off an environment variable, because the two
 * disagree in exactly the case that matters: WT_SESSION is inherited by a plain conhost window started from
 * inside a WT session (`cmd /c start cmd`), and that window parses nothing, so an env-var test hands it to
 * the wrong writer. conhost is the authority -- `GetConsoleWindow` returns the `PseudoConsoleWindow` handle
 * if and only if `gci.IsInVtIoMode()` is set (getset.cpp:1262-1275), and the real `ConsoleWindowClass`
 * window otherwise (window.cpp:39). The class name is therefore VtIo mode read directly, and VtIo mode is
 * precisely "somebody above me is re-serializing my buffer to VT".
 *
 * That is the fact a writer choice turns on. Under VtIo a WriteConsoleOutputW is not a write to cells at
 * all: `VtIo::Writer::WriteInfos` (VtIo.cpp:771-830) walks the run and turns it into VT for the terminal,
 * so every rule this renderer holds about rows, rectangles and the buffer scroll is applied twice -- once
 * by a model and once by a serializer that has no notion of one. And the repaint an *adopt* performs covers
 * cells this program merely read, cmd's own text among them, which is output the terminal has already
 * shown; re-emitting it puts it in the scrollback again. Wide pairs are the sharpest edge of that path: a
 * run beginning on a glyph's trailing half, or ending on its leading one, is replaced by a space
 * (VtIo.cpp:786-806) -- the pair survives in the buffer and is lost on the way out.
 *
 * The comparison is done by hand rather than with `_wcsicmp`/`lstrcmpiW`, because which wide comparator a
 * given CRT and a given import library expose is exactly the dialect question the formatters below are
 * commented for. A console with no window answers false, which is this library's own safe side: with no
 * window nothing above us is re-serializing, so a caller that wants escapes rendered still has to do it.
 */
JNIEXPORT jboolean JNICALL Java_com_hyee_ansirender_NativeRenderer_isPseudoConsole(JNIEnv *env, jclass cls)
{
  (void)env; (void)cls;
  static const wchar_t PSEUDO[] = L"PseudoConsoleWindow";
  HWND w = GetConsoleWindow();
  if (!w) return JNI_FALSE;
  wchar_t name[32];
  const int n = GetClassNameW(w, name, (int)(sizeof name / sizeof name[0]));
  if (n != (int)(sizeof PSEUDO / sizeof PSEUDO[0]) - 1) return JNI_FALSE;
  for (int i = 0; i < n; i++)
  {
    wchar_t a = name[i], b = PSEUDO[i];
    if (a >= L'A' && a <= L'Z') a = (wchar_t)(a - L'A' + L'a');
    if (b >= L'A' && b <= L'Z') b = (wchar_t)(b - L'A' + L'a');
    if (a != b) return JNI_FALSE;
  }
  return JNI_TRUE;
}

/** [0] flushes [1] rectangle writes [2] declines [3] api errors [4] aligns [5] cells painted
 *  [6] scrolls [7] astral [8] last reason  [9] pendingScrolls  [10] cx [11] cy (a model row)
 *  [12] attr [13] defAttr [14] winRows [15] gutter rows above the viewport [16] SGR sequences not
 *  echoed because the capture or the accumulator filled up -- colour parity is then best effort
 *
 *  [17+enum RcUnsupported] sequences the stream contained that we consume without modelling, in the
 *  enum's order, one slot per row of `rc_census` in Render.cpp -- which is where their names, their
 *  sentences and the one that sets `modelSuspect` now live. They are deliberately not restated here: this
 *  array is positional across three files (I19) and a second copy of the labels is a third thing to forget
 *  to update. `Render.java` reads the table through `censusNames()` and compares all eleven at run time.
 *  [27] is the last of the family, a CSI that carried ':' (see STAT_TITLES, which the family's length moves)
 *  [STAT_TITLES..] titles accepted by the parser, of those truncated at RC_TITLE_MAX, and titles the
 *  console took.
 *  [STAT_ALT..] alt-screen switches (each direction of ?47/?1047/?1049 counts once) and, of the entries,
 *  the ones refused because the snapshot's allocation failed.
 *  [STAT_PROMPT..] OSC 133 marks this process laid down (I23), then the exit code the live grid last read
 *  from a 133;D: RC_EXIT_UNKNOWN before any D arrived, RC_EXIT_UNPARSABLE for one whose code was not a
 *  number.
 *  [STAT_SNAP] views a keystroke brought back onto the model's cursor row: the SnapOnInput this console
 *  will not do for itself, because conhost fires that only in VTP mode and this renderer exists for the
 *  mode where it is off (input.cpp:171-178).
 *  [STAT_REPORT..] query replies the console took, replies whose write failed or fell short, and queries
 *  refused because eight were already waiting. A non-zero middle or last entry is the difference between a
 *  program that got its answer and one that is still waiting for it.
 *  [STAT_SYNC..] DECSET 2026: regions opened, nested BSUs, flushes deferred, and the three ways a region can
 *  end without its ESU (a frame that waited past the timeout, a gutter that filled up under the hold, a chunk
 *  that could not be executed at all). The last slot is the live bit rather than a count -- a stream that ends
 *  inside a region is a finding, not a rate. Slots from 17 on are process-wide
 *  rather than per-model on purpose (see g_tot*): "did this session's output ask for an alt buffer, or run a
 *  full-screen program, or mark its prompts" is a question about the byte stream, and a resize in the middle
 *  of it must not erase the answer. The last exit code is the one exception -- the question it answers
 *  ("what would a status bar show now") is about the grid standing here and now, and folding it would mean
 *  summing values that do not add. Everything else below 17 describes one model. */
/* The OSC 9 safe subset's stored face (T7), for the host that has a place to put it. Both are read-only and
 * both answer null when there is nothing to say: no model, or -- for the directory -- no `9;9` yet. The
 * taskbar triple carries `seen` apart from `state` because state 0 is a real instruction ("remove the
 * indicator") and must not be confused with "this stream never asked".
 * This library deliberately does not act on either: it owns no window, so there is no taskbar to paint, and
 * it does not change the process's directory from an output stream -- that is the whole of the #687 posture,
 * kept while the safe subset is parsed. */
JNIEXPORT jlongArray JNICALL Java_com_hyee_ansirender_NativeRenderer_taskbar0(JNIEnv *env, jclass cls, jlong ph)
{
  (void)cls;
  RcHandle *h = slot_of(ph);
  const RcGrid *g = h ? h->g : NULL;
  if (!g) return NULL;
  jlong out[3] = { (jlong)g->taskbarState, (jlong)g->taskbarProgress, (jlong)g->taskbarSeen };
  jlongArray arr = env->NewLongArray(3);
  if (arr) env->SetLongArrayRegion(arr, 0, 3, out);
  return arr;
}

/** OSC 52's switch, and the only way it can be turned on: by the host that loaded this library. Nothing in
 *  the byte stream can reach it, which is what makes "off" mean off. */
JNIEXPORT void JNICALL Java_com_hyee_ansirender_NativeRenderer_setClipboardPolicy0(JNIEnv *env, jclass cls, jboolean allow)
{
  (void)env; (void)cls;
  rc_set_clipboard_policy(allow ? RC_CLIP_ALLOW : RC_CLIP_DENY);
}

/** The other half of the same switch, read back from the library that owns it. A host needs it to tell
 *  "the export is missing, so an old dll silently kept it off" from "this dll was told off" -- the first is
 *  a version problem the launcher can report, the second is the state it asked for. */
JNIEXPORT jboolean JNICALL Java_com_hyee_ansirender_NativeRenderer_clipboardPolicy0(JNIEnv *env, jclass cls)
{
  (void)env; (void)cls;
  return rc_clipboard_policy() ? JNI_TRUE : JNI_FALSE;
}

/** The last `OSC 9;9` path, or null. Text only -- see the comment above for why nothing opens it. */
JNIEXPORT jstring JNICALL Java_com_hyee_ansirender_NativeRenderer_workingDirectory0(JNIEnv *env, jclass cls, jlong ph)
{
  (void)cls;
  RcHandle *h = slot_of(ph);
  const RcGrid *g = h ? h->g : NULL;
  if (!g || g->nCwd <= 0) return NULL;
  return env->NewString((const jchar *)g->cwd, (jsize)g->nCwd);
}

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
    out[STAT_SNAP] = (jlong)h->nSnaps;
    out[STAT_REPORT] = (jlong)(g_totRepOk + (g ? g->nReportOk : 0));
    out[STAT_REPORT + 1] = (jlong)(g_totRepFail + (g ? g->nReportFail : 0));
    out[STAT_REPORT + 2] = (jlong)(g_totRepFull + (g ? g->nReportFull : 0));
    out[STAT_ARGTRUNC] = (jlong)(g_totArgTrunc + (g ? g->nArgTrunc : 0));
    out[STAT_SYNC] = (jlong)(g_totSyncEngages + (g ? g->nSyncEngages : 0));
    out[STAT_SYNC + 1] = (jlong)(g_totSyncNested + (g ? g->nSyncNested : 0));
    out[STAT_SYNC + 2] = (jlong)(g_totSyncHeld + (g ? g->nSyncHeld : 0));
    out[STAT_SYNC + 3] = (jlong)(g_totSyncTimeout + (g ? g->nSyncTimeout : 0));
    out[STAT_SYNC + 4] = (jlong)(g_totSyncOverflow + (g ? g->nSyncOverflow : 0));
    out[STAT_SYNC + 5] = (jlong)(g_totSyncDeclined + (g ? g->nSyncDeclined : 0));
    /* Not a counter: whether a region is open *now*. The distinction is the one S_EXIT already makes in the
       prompt family -- a census of what happened cannot say what the terminal currently believes, and a
       synchronized region whose ESU never arrived is exactly that question. */
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

/** [0] winT [1] winL [2] bufW [3] bufH [4] attr [5] curX [6] curY [7] cursorOn [8] winB -- what the gate
 *  needs to know where the window slid to. The bottom is the ninth because a `SetConsoleScreenBufferInfoEx`
 *  that moves the window without moving its top is otherwise invisible to every other field here, and that is
 *  exactly the failure the palette leg had to find. Production reads nothing through here. */
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

/** The characters sitting in the console's input stream, consumed by this call. Gate-only, and the only
 *  witness that can say what a reply *said*: flush_reports already counts whether WriteConsoleInputW took its
 *  records, and a count is not an answer -- a CPR one row off hangs the program that asked for it, which is
 *  exactly the bug this function exists to catch. Peek, then read exactly what the peek found, so a gate run
 *  with nobody typing cannot block. Key-up events are skipped, because a reply is one down/up pair per
 *  character and the character is in both halves. */
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
  /* Peek before reading: a console nobody is typing into would block a plain ReadConsoleInputW, and this
     gate runs on an allocated console with no window to type into. */
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

/**
 * Rebuild this handle's model for the console's shape *now* and adopt what it shows: `readopt()`, the same
 * call render() makes on the chunk after a geometry decline. It is exported for the gate alone because that
 * is the only difference between the two -- production reaches it through render()'s own state machine, and
 * a case that drove close()+open() instead would be testing a *new* session, which has no anchor to carry
 * across the resize, and would never notice.
 *
 * The handle is unchanged by it (that is readopt's promise: the pointer Java holds is not something it may
 * ask C to keep up with), so the gate keeps driving the same model afterwards. Returns 1 on a rebuilt and
 * re-aligned model, 0 with openStatus() naming the refusal.
 */
JNIEXPORT jint JNICALL Java_Render_readopt(JNIEnv *env, jclass cls, jlong ph)
{
  (void)env; (void)cls;
  RcHandle *h = slot_of(ph);
  if (!h) return 0;
  int status = OPEN_OK;
  return readopt(h, &status) ? 1 : 0;
}

/**
 * The last plan this handle executed, field by field: `plan(h)`, for the gate alone.
 *
 * [0] seq (plans since this slot was claimed) [1] reason (enum RcPlanReason) [2] baseSet [3] baseRow
 * [4] winT as the plan read it [5] the anchor the plan started from [6] rows it slid the window
 * [7] slideTo (the row it parked the cursor on, -1 for none) [8] bufScroll [9] row0 -- the buffer row it
 * then addressed model row 0 at [10] winTop it left the window on [11] rows [12] winRows [13] bufH
 * [14] pendingScrolls it spent [15] runs [16] declined on geometry [17] a move call that failed
 *
 * Everything the gate can see otherwise is where the console is; none of it is where the painter believed its
 * rows were, and the class of defect these fields exist for is the difference between the two -- a row written
 * at a claim the screen cannot show. Production has no use for it (the plan is consumed by the flush that
 * built it), so this is exported for the witness and nothing else. `seq` is what says so: a plan from before
 * the current session would be a stale answer, and a gate that did not notice would be reading its own
 * history back as evidence.
 */
JNIEXPORT jlongArray JNICALL Java_Render_plan(JNIEnv *env, jclass cls, jlong ph)
{
  (void)cls;
  RcHandle *h = slot_of(ph);
  jlong out[18];
  memset(out, 0, sizeof out);
  if (h)
  {
    out[0] = h->trSeq; out[1] = h->trReason; out[2] = h->trBaseSet; out[3] = h->trBaseRow;
    out[4] = h->trWinT; out[5] = h->trBase; out[6] = h->trSlide; out[7] = h->trSlideTo;
    out[8] = h->trBufScroll; out[9] = h->trRow0; out[10] = h->trWinTop; out[11] = h->trRows;
    out[12] = h->trWinRows; out[13] = h->trBufH; out[14] = h->trPend; out[15] = h->trRuns;
    out[16] = h->trDeclined; out[17] = h->trMoveFail;
  }
  jlongArray arr = env->NewLongArray(18);
  if (arr) env->SetLongArrayRegion(arr, 0, 18, out);
  return arr;
}

typedef BOOL (WINAPI *WriteProcessed3Fn)(LPCWSTR, DWORD, LPDWORD, HANDLE);

/**
 * Arm the one-shot write_rect fault (RcHandle::faultRun) on run `run` of the next plan; `run < 0` disarms.
 * Gate-only scaffolding, in the family of Java_Render_plan/readopt: production cannot reach it and
 * NativeRenderer has no binding for it. Returns the value now armed, so the caller reads the slot back
 * instead of trusting that arming took.
 */
JNIEXPORT jint JNICALL Java_Render_faultRect(JNIEnv *env, jclass cls, jlong ph, jint run)
{
  (void)env; (void)cls;
  RcHandle *h = slot_of(ph);
  if (!h) return -2;                          /* no such handle: nothing is armed anywhere */
  h->faultRun = (int)run;
  return h->faultRun;
}

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

/* gate-only: the console's own 16 palette entries, read straight off CONOUT$ rather than through a handle,
 * because the leg that needs it most is the one that runs after close() has invalidated the handle.
 * Production has no caller; build.sh's export whitelist carries the name. */
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

/** The census table, as a gate can read it: one "name|suspect" per RcUnsupported slot, in the enum's order.
 *  Gate-only, because the production census is numbers and the words already live in the Java report. What
 *  this buys is the half of I19's positional contract that nothing checked: `Render.java` compares its own
 *  eleven labels against these, item by item, so a slot renamed on one side of the seam fails a gate instead
 *  of printing a confident wrong number into a rollout log. */
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

/* gate-only: the grid's invariants, read back over the live part of the model (Render.h::rc_validate_grid says
   what is on the list, and why every item on it is silent on a screen when it breaks). The host gate has the
   same eye and links Render.cpp directly, so it cannot speak for the binary that ships; this is the leg that
   can. An empty string is the clean answer. */
JNIEXPORT jstring JNICALL Java_Render_validateGrid(JNIEnv *env, jclass cls, jlong ph)
{
  (void)cls;
  RcHandle *h = slot_of(ph);
  char msg[256];
  if (h == NULL || h->g == NULL) return env->NewStringUTF("(no model behind this handle)");
  if (!rc_validate_grid(h->g, msg, (int) sizeof msg)) return env->NewStringUTF("");
  return env->NewStringUTF(msg);
}

/* gate-only: how many parameters this model has dropped for want of room (Render.cpp::push_arg, #74). The
   host gate can read the field straight out of the struct it links, which makes it no witness at all for the
   binary that ships -- the same gap -25's four console legs were built to close. Production has no reason to
   ask: the sequence it acted on is already on the screen. */
JNIEXPORT jlong JNICALL Java_Render_argTrunc(JNIEnv *env, jclass cls, jlong ph)
{
  (void)env; (void)cls;
  RcHandle *h = slot_of(ph);
  return (jlong)(h && h->g ? (long)h->g->nArgTrunc : -1);
}

}  // extern "C"

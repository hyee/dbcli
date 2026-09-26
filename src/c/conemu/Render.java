/**
 * Stage-1 driver for render.dll (RenderJni.cpp), built by src/c/conemu/build.sh.
 *
 * What this proves that no host test can: that the operation list rc_plan_paint produces actually
 * lands in conhost, and that what conhost then *stores* is what the model claimed. The witness is
 * ReadConsoleOutputW over the buffer -- the same convention Probe.java settled in stage 0 -- because a
 * pty stream or a Java-side log is not evidence about a screen buffer (see .dsh/memory
 * reference-windows-console-grid-witness).
 *
 * The geometry is chosen to be adversarial, not convenient: a 100x30 window inside a 200x400 buffer.
 * A model row is a whole *buffer* row (Render.h, `cols`), so the painter writes 200 columns while only
 * 100 of them are on screen -- which is exactly what makes "wrapped at the window" and "wrapped at
 * dwSize.X" observable as different cells. ConEmu's EL erases to dwSize.X, so that is what the
 * assertions below demand, and caseWideBuffer repeats the shape a default conhost profile really has
 * (measured 2026-09-23 on this box: a 2000x9001 buffer with a 120x60 window; Windows Terminal and ConEmu
 * keep buffer == window, where the two widths agree by construction).
 *
 * Every case also demands apiErrors == 0: a console call that failed and was papered over is the
 * failure mode that shows up as text painted twice or a row that silently never appears.
 *
 * Pure ASCII on purpose: JDK 8's javac defaults to the platform encoding (GBK on this box), so the CJK
 * cases are spelled as escapes.
 *
 * The renderer is driven through com.hyee.ansirender.NativeRenderer -- the production class, compiled here from
 * src/java rather than duplicated -- because a gate against its own copy of the declarations would pass
 * happily while the shipped ABI did not bind. What stays declared here is the scaffolding production has
 * no equivalent of: shaping the console and reading its cells back.
 */
import com.hyee.ansirender.NativeRenderer;

public class Render {

    static { System.loadLibrary("render"); }        /* for the gate-only natives below */
    /* gate-only */
    static native int prepareConsole();
    static native int setGeometry(int bufW, int bufH, int winW, int winH, int attr);
    static native long[] readCells(int x, int y, int w, int h);
    static native long[] consoleView();
    static native char[] consoleTitle();
    /** The console's own 16 palette entries, read off CONOUT$ -- gate-only, and it takes no handle because
     *  the leg that needs it most runs after close() has invalidated one. See I34's restore claim. */
    static native int consolePalette(long[] out16);
    /** Drain up to `max` characters off the console's input stream -- the witness for a DSR/DA reply. */
    static native char[] readInput(int max);
    /** "name|suspect" for every census slot, in the C enum's order -- the table `stats()` indexes into. */
    static native String[] censusNames();
    /** Hand bytes to ConEmuHk's WriteProcessed3 -- the fallback leg itself -- on this console. */
    static native int writeHk(char[] text, int len, String dll);
    /** Rebuild this handle's model for the console's shape now, carrying its row claim across: the real
     *  recovery a resize takes, which production reaches through render() and a gate cannot. */
    static native int readopt(long h);
    /** The last flush's own geometry: [0] seq [1] reason [2] baseSet [3] baseRow [4] winT read [5] anchor
     *  [6] slide [7] slideTo [8] bufScroll [9] row0 [10] winTop left behind [11] rows [12] winRows
     *  [13] bufH [14] pendingScrolls spent [15] runs [16] declined [17] a move call that failed.
     *  Where the model believes its rows are is not readable off the console, and every case below that is
     *  about a row written at a claim turns on it. */
    static native long[] plan(long h);
    /** Arm a one-shot write_rect fault on run `run` of the next plan this handle flushes (`run < 0` disarms)
     *  and return what is now armed. Gate-only: the #44 defect needs a console call to fail *mid-plan*, and
     *  no console state can be coaxed into that. See RcHandle::faultRun. */
    static native int faultRect(long h, int run);
    /** The grid's own invariants, read out of the shipped dll after a chunk lands. Empty string means clean. */
    static native String validateGrid(long h);
    /* How many parameters the model behind this handle dropped for want of room. Gate-only, like
       validateGrid: production has no reason to ask, and the host gate cannot answer it for the shipped dll. */
    static native long argTrunc(long h);

    private static long open(int cols, int rows, int defAttr) {
        return NativeRenderer.open(0, cols, rows, defAttr);   /* 0: the DLL opens CONOUT$ itself */
    }

    private static int feed(long h, char[] t, int off, int len) { return NativeRenderer.feed(h, t, off, len); }
    private static int flush(long h) { return NativeRenderer.flush(h); }
    private static int align(long h) { return NativeRenderer.align(h); }
    private static int snap(long h) { return NativeRenderer.snap(h); }
    private static long[] stats(long h) { return NativeRenderer.stats(h); }
    private static void close(long h) { NativeRenderer.close(h); }

    /* The window is a quarter of the buffer's width, so a painted row extends past everything the user
       can see until they scroll right: that off-screen part is ordinary model cells now, and the cases
       below assert it. WIDE_* is this machine's default conhost shape, ratio and all. */
    static final int BUF_W = 200, BUF_H = 400, WIN_W = 100, WIN_H = 30, DEF = 0x07;
    static final int WIDE_BUF_W = 2000, WIDE_BUF_H = 300, WIDE_WIN_W = 120;

    private static long handle;
    private static int checks, failures;
    private static int winT;                       /* buffer row of the viewport's top row */

    /* stats() slots from 17 up: one per member of enum RcUnsupported in Render.h, in that order, and the
       three title counters after the family. Adding a counter therefore moves the titles -- which is the
       mistake these names exist to make impossible. com.hyee.ansirender.NativeRenderer's SLOT_* constants are the
       other end of the same seam, and the line that prints them is the witness that both agree. The alt
       pair sits after the titles and the OSC 133 pair after that, and the query-reply triple after those, at
       the end, so a new counter can only ever extend this. The last of the two prompt slots is the one
       per-model counter in the family: see the comment on
       Java_com_hyee_ansirender_NativeRenderer_stats for why that one does not fold at close(). S_SNAP is the
       one after the reply triple -- a per-model count of the views a keystroke moved, asserted by
       caseSnapOnInput rather than only printed, because that counter is the sole witness that a snap
       reached the console at all: the window's row is equally explainable by a scroll that came from
       somewhere else. */
    /* S_UN + RC_UN_MAX is where the families after the census start, and RC_UN_MAX is 12 since OSC 52
       joined it. The offsets below are +12 on through the sync family for that reason; they were +11 for
       eleven slots, and `RenderJni.cpp` moves them by itself because it writes `STAT_UNSUPPORTED +
       RC_UN_MAX`. That is the whole I19 contract in one line: a slot is appended, never moved, and
       everything after it shifts together on both sides of the seam. */
    private static final int S_UN = 17, S_COLON = S_UN + 10, S_TITLES = S_UN + 11 + 1,
            S_TITLES_TRUNC = S_UN + 12 + 1, S_TITLES_APPLIED = S_UN + 13 + 1, S_ALT = S_UN + 14 + 1,
            S_ALT_FAIL = S_UN + 15 + 1, S_PROMPTS = S_UN + 16 + 1, S_EXIT = S_UN + 17 + 1,
            S_REPLIED = S_UN + 18 + 1, S_REPLY_FAIL = S_UN + 19 + 1, S_REPLY_FULL = S_UN + 20 + 1,
            S_SNAP = S_UN + 21 + 1,
            /* DECSET 2026, appended in the same order as STAT_SYNC in RenderJni.cpp: the regions that opened,
               the nested BSUs, the flushes held, and the three ways a region ended without its ESU. Last is the
               bit itself -- the only slot in this table that is a state rather than a count, and the reason the
               family cannot be read from the counts before it. The engages count is the denominator the other
               four need: held=400 says nothing until you know whether that was 400 regions or four. */
            S_SYNC = S_UN + 23, S_SYNC_ENGAGES = S_UN + 23, S_SYNC_NESTED = S_UN + 24,
            S_SYNC_HELD = S_UN + 25, S_SYNC_TIMEOUT = S_UN + 26, S_SYNC_OVERFLOW = S_UN + 27,
            S_SYNC_DECLINED = S_UN + 28, S_SYNC_ON = S_UN + 29,
            /* OSC 52, in RenderJni.cpp's STAT_CLIP order: armed by the parser, then the three reasons a
               request was refused, then what the clipboard API answered, then the policy bit. The family's
               census slot is the last name in the label list below, which the gate compares against the
               dll's own table. */
            S_CLIP_ARMED = S_UN + 30, S_CLIP_DECODE = S_UN + 31, S_CLIP_SELECTION = S_UN + 32,
            S_CLIP_READ = S_UN + 33, S_CLIP_WRITES = S_UN + 34, S_CLIP_FAILS = S_UN + 35,
            S_CLIP_POLICY = S_UN + 36, S_LEN = S_UN + 37;

    public static void main(String[] args) {
        System.out.println("render build: " + NativeRenderer.build());
        if (prepareConsole() == 0) { System.out.println("FAIL cannot prepare a console"); System.exit(1); }
        /* Which console that is: every leg below assumes the renderer owns the screen. On a pseudo-console
           (ConPTY) it does not -- a write of cells is re-serialized to VT and parsed again one level up, so
           the grid would agree with itself and disagree with the terminal. The gate allocates its own
           conhost when stdout is a pipe, so the expected answer here is false, and this line is what says
           which of the two a given log came from. */
        System.out.println("console: " + (NativeRenderer.isPseudoConsole()
                ? "pseudo (ConPTY) -- the cell witness below is not testing what it looks like"
                : "the gate's own conhost window"));
        if (setGeometry(BUF_W, BUF_H, WIN_W, WIN_H, DEF) == 0) {
            System.out.println("FAIL cannot set console geometry"); System.exit(1);
        }
        handle = open(BUF_W, WIN_H, DEF);
        if (handle == 0) { System.out.println("FAIL open returned no handle"); System.exit(1); }
        gate("align adopts the console", align(handle) == 1, null);
        flushQuietly();                            /* the full-window repaint align asked for */
        /* align() adopted whatever the console was already showing -- in a shell that runs this gate twice,
           that includes the previous run's last frame, attribute and all. Everything below is about what
           the renderer puts on screen, so start from a clean window through the renderer itself. The reset
           comes first because an erase fills with the *current* attribute, conhost's rule and the model's. */
        paint("clean start", "\u001b[0m\u001b[2J\u001b[H");
        tail("the window is blank at the default attribute", winT, 0, DEF);

        casePlainText();
        caseColour();
        caseSgrEcho();
        caseOscTitle();
        caseSemanticPrompt();
        caseReports();
        caseEraseToBufferWidth();
        caseWideGlyph();
        caseLegsAgree();
        caseWrap();
        caseDecawm();
        caseBareLf();
        caseNarrowRepaint();
        caseScroll();
        caseAltScreen();
        caseManyScreens();
        caseRealign();
        caseSuspectAlign();
        caseNoScrollback();
        caseHookDecline();
        caseWideBuffer();
        caseScrollKeepsHistory();
        caseFullBufferEvicts();
        caseSnapOnInput();
        caseOpenRefusal();
        casePartialPaintFailure();
        /* Each of these four legs calls standardGeometry(), which re-opens the handle and blanks the viewport:
           they cannot go above a case whose claim is about rows an earlier case left in the buffer, because
           that is exactly the content they erase. */
        caseEditRows();
        caseEchClamp();
        caseHealPairs();
        caseSoftReset();
        caseArgClamp();
        caseTabStops();
        caseInsert();
        caseColon();
        caseWindowOps();
        caseRelativeCursor();
        caseSyncOutput();
        caseSyncOverflow();
        /* Last, on purpose: this leg repaints the console palette and erases the viewport to prove an
           OSC 10 reached the screen, and a leg that clears the screen cannot sit in the middle of a run
           whose later rows are read back as they were left. */
        casePalette();
        caseOsc9();
        caseClipboard();

        long[] s = stats(handle);
        gate("no console call failed", s[3] == 0, "apiErrors=" + s[3] + " lastError check below");
        gate("the grid oracle ran against every chunk of this run", gridRuns > 300 && gridBad == 0,
                "runs=" + gridRuns + " violations=" + gridBad);
        gate("every SGR sequence was echoed", s[16] == 0, "sgrNotEchoed=" + s[16]
                + ": a capture too small to hold a chunk would show up here, not on screen");
        System.out.println("  stats: flushes=" + s[0] + " rectangles=" + s[1] + " declines=" + s[2]
                + " apiErrors=" + s[3] + " aligns=" + s[4] + " cells=" + s[5] + " scrolls=" + s[6]);
        /* Process-wide, by design: what the whole run's byte stream asked for, not what the last model
           saw. This is the line a rollout reads to find out whether real output contains any of them.
           The length is asserted rather than assumed: these slot numbers are a seam between enum
           RcUnsupported in Render.h and com.hyee.ansirender.NativeRenderer's SLOT_* constants, and growing the
           family moves the title counters along with it. */
        gate("stats carries the counters the report names", s.length >= S_LEN,
                "length=" + s.length + (s.length >= S_LEN ? " for a table of " + S_LEN
                        : ": render.dll is older than this gate's slot table of " + S_LEN));
        /* The other half of that contract. The line above compares the dll's array with *this file's* slot
           numbers; nothing so far compared this file's with the library's own report -- the text that ships in
           dbcli.jar and that a rollout actually reads. The two tables are in different trees and reach the same
           array by index, so the check is reflective: renumber one side and forget the other has to fail here,
           naming the slot, instead of printing a census whose numbers belong to somebody else's counters. */
        /* The census's other half. `reportSlotAgrees` compares four *indices*; nothing compared the eleven
           *words* those indices are printed with, which is the failure where a rollout log says "mouse=4"
           about a counter that moved. Read them from the dll and check them one by one. */
        final String[] LABELS = { "unrecognised", "decstbm", "altbuf", "mouse", "mode", "bracketed paste",
                "osc9", "other osc", "dcs", "report", "colon", "osc clip" };
        final String[] cn = censusNames();
        gate("render.dll names every census slot", cn != null && cn.length == LABELS.length,
                cn == null ? "null" : "the table has " + cn.length + " rows against " + LABELS.length
                        + " labels in this gate");
        if (cn != null && cn.length == LABELS.length) {
            int suspect = 0;
            for (int i = 0; i < cn.length; i++) {
                final int bar = cn[i].indexOf('|');
                gate("census slot " + i + " is named what the report calls it",
                        bar > 0 && LABELS[i].equals(cn[i].substring(0, bar)),
                        "the dll says \"" + cn[i] + "\" for a label this gate prints as \"" + LABELS[i] + "\"");
                if (bar > 0 && "1".equals(cn[i].substring(bar + 1))) suspect++;
            }
            gate("one and only one census slot doubts the frame", suspect == 1, "count=" + suspect);
        }
        reportSlotAgrees("SLOT_UNSUPPORTED", S_UN);
        reportSlotAgrees("SLOT_SYNC_OVERFLOW", S_SYNC_OVERFLOW);
        reportSlotAgrees("SLOT_SYNC_ON", S_SYNC_ON);
        reportSlotAgrees("SLOT_LAST", S_LEN);
        if (s.length >= S_LEN) {
            System.out.println("  not modelled: unrecognised=" + s[S_UN] + " decstbm=" + s[S_UN + 1]
                    + " altbuf=" + s[S_UN + 2] + " mouse=" + s[S_UN + 3] + " mode=" + s[S_UN + 4]
                    + " bracketed paste=" + s[S_UN + 5] + " osc9=" + s[S_UN + 6] + " other osc="
                    + s[S_UN + 7] + " dcs=" + s[S_UN + 8] + " report=" + s[S_UN + 9] + " colon=" + s[S_COLON]
                    + "; titles=" + s[S_TITLES] + " (" + s[S_TITLES_TRUNC] + " truncated), "
                    + s[S_TITLES_APPLIED] + " applied"
                    + "; alt switches=" + s[S_ALT] + " (" + s[S_ALT_FAIL] + " refused)"
                    + "; prompts marked=" + s[S_PROMPTS] + ", last 133;D exit=" + s[S_EXIT]
                    + "; replies written=" + s[S_REPLIED] + " (" + s[S_REPLY_FAIL] + " failed, "
                    + s[S_REPLY_FULL] + " refused for a full queue)"
                    + "; views snapped back on input=" + s[S_SNAP]
                    + "; sync updates=" + s[S_SYNC_ENGAGES] + " (" + s[S_SYNC_NESTED] + " nested, "
                    + s[S_SYNC_HELD] + " flushes held, ended early by " + s[S_SYNC_TIMEOUT] + " timeout / "
                    + s[S_SYNC_OVERFLOW] + " gutter / " + s[S_SYNC_DECLINED] + " decline)");
        }
        close(handle);
        /* The other half of I34's promise: the console keeps the palette its user chose. This is read after
           the close rather than asserted inside casePalette because that is the only moment the restore has
           actually run -- and `paletteBefore` was taken before this process touched a single entry. */
        if (paletteBefore != null) {
            final long[] after = palette();
            gate("close() handed the console back the palette it found",
                    after != null && paletteDiff(after, paletteBefore, -1) == null,
                    after == null ? "unreadable" : String.valueOf(paletteDiff(after, paletteBefore, -1)));
        }
        System.out.println("checks=" + checks + " failures=" + failures);
        if (failures > 0) { System.out.println("RENDERGATE: FAILED"); System.exit(1); }
        System.out.println("RENDERGATE: ok");
    }

    /** one chunk through the renderer, asserting it was accepted rather than declined */
    private static void paint(String what, String s) {
        char[] c = s.toCharArray();
        if (feed(handle, c, 0, c.length) == 0) { gate(what + ": feed", false, "feed returned 0"); return; }
        int r = flush(handle);
        drainSgr();                           /* production takes the echo every chunk; so does the gate */
        winT = (int) consoleView()[0];    /* a scroll in this chunk moved the window; the rows follow it */
        /* 3 is FLUSH_HELD: the bytes are in the model and the picture is waiting for the synchronized region
           to end. It is a consumed chunk, not a failure, and a gate that refused it would refuse the mode. */
        gate(what + ": accepted", r == 0 || r == 1 || r == 3, "flush=" + r);
        gridClean(what);
    }

    /**
     * The model's invariants, asked of the binary that ships rather than of the source the host gate links.
     * A violation prints where it happens, with the chunk that produced it. The tally is asserted at the end
     * of the run rather than assumed from an absence of red: a new arm that never ran is a green that means
     * nothing (§6 rule 12).
     */
    private static int gridRuns, gridBad;
    private static void gridClean(String after) {
        final String bad = validateGrid(handle);
        gridRuns++;
        if (bad == null) {
            gridBad++;
            System.out.println("  FAIL the grid oracle could not run after " + after);
            return;
        }
        if (bad.length() == 0) return;
        gridBad++;
        System.out.println("  FAIL grid invariants after " + after + ": " + bad);
    }

    private static void flushQuietly() { flush(handle); drainSgr(); }

    /**
     * One index of {@code NativeRenderer}'s slot table, read from the class by name, against this gate's own
     * constant for the same counter. Read reflectively because the fields are private and must stay private --
     * a report table is not an API, and widening it to satisfy a test would be the test dictating the library.
     */
    private static void reportSlotAgrees(String field, int want) {
        final int got;
        try {
            final java.lang.reflect.Field f = NativeRenderer.class.getDeclaredField(field);
            f.setAccessible(true);
            got = f.getInt(null);
        } catch (ReflectiveOperationException e) {
            gate("the report has a slot named " + field, false, e.toString());
            return;
        }
        gate("the shipped report's " + field + " is this gate's slot", got == want,
                "NativeRenderer." + field + "=" + got + " Render=" + want);
    }

    private static void drainSgr() { NativeRenderer.sgr(handle); }

    // ---- witnesses ---------------------------------------------------------------------------

    /** one buffer row, read fresh: a repaint of the same row must not be compared against a cache */
    private static long[] row(int bufRow) {
        return readCells(0, bufRow, BUF_W, 1);
    }

    /** one cell's attribute, for the legs that must compare two spellings against each other rather than
        against a number this file would have to re-derive from the fold table */
    private static int cellAttr(int bufRow, int col) {
        long[] r = row(bufRow);
        return (r == null || col >= r.length) ? -1 : (int) ((r[col] >>> 16) & 0xFFFF);
    }

    private static void cell(String what, int bufRow, int col, char ch, int attr) {
        checks++;
        long[] r = row(bufRow);
        if (r == null || col >= r.length) {
            failures++;
            System.out.println("  FAIL " + what + ": row " + bufRow + " unreadable");
            return;
        }
        long got = r[col];
        int gch = (int) (got & 0xFFFF), gattr = (int) ((got >>> 16) & 0xFFFF);
        if (gch == ch && gattr == attr) return;
        failures++;
        System.out.println("  FAIL " + what + ": (" + bufRow + "," + col + ") = U+"
                + Integer.toHexString(gch) + " 0x" + Integer.toHexString(gattr)
                + ", want U+" + Integer.toHexString(ch) + " 0x" + Integer.toHexString(attr));
    }

    /**
     * The tail of a row, to the buffer's right edge (dwSize.X). A model row *is* that row, so these are
     * ordinary cells like any others: the painter writes the model's own cells there, an erase's blanks
     * included, and nothing about them is derived from "the row's last visible column".
     */
    private static void tail(String what, int bufRow, int from, int attr) {
        for (int c = from; c < BUF_W; c++) cell(what, bufRow, c, ' ', attr);
    }

    /**
     * One row read once, every column in [from,to] checked against the same cell, one verdict. A
     * 2000-column buffer row is 1900 cells nobody looks at individually; reading them cell by cell would
     * be 1900 ReadConsoleOutputW calls, and the count of checks is not the point of this one.
     */
    private static void span(String what, int bufRow, int from, int to, char ch, int attr) {
        checks++;
        long[] r = readCells(from, bufRow, to - from + 1, 1);
        if (r == null) {
            failures++;
            System.out.println("  FAIL " + what + ": row " + bufRow + " unreadable");
            return;
        }
        for (int i = 0; i < r.length; i++) {
            int gch = (int) (r[i] & 0xFFFF), gattr = (int) ((r[i] >>> 16) & 0xFFFF);
            if (gch == ch && gattr == attr) continue;
            failures++;
            System.out.println("  FAIL " + what + ": (" + bufRow + "," + (from + i) + ") = U+"
                    + Integer.toHexString(gch) + " 0x" + Integer.toHexString(gattr)
                    + ", want U+" + Integer.toHexString(ch) + " 0x" + Integer.toHexString(attr));
            return;
        }
    }

    private static void text(String what, int bufRow, int col, String s, int attr) {
        for (int i = 0; i < s.length(); i++)
            cell(what, bufRow, col + i, s.charAt(i), attr);
    }

    /**
     * One row compared, cell and attribute for cell, against the same row read earlier. For the facts
     * where the point is "nothing changed" rather than "this is here": an earlier frame's rows, which a
     * case cannot restate as a literal without writing them itself.
     */
    private static void same(String what, int bufRow, long[] was) {
        checks++;
        if (was == null) {
            System.out.println("  skip " + what + ": row " + bufRow + " is above the buffer");
            return;
        }
        long[] now = row(bufRow);
        if (now == null || now.length != was.length) {
            failures++;
            System.out.println("  FAIL " + what + ": row " + bufRow + " unreadable");
            return;
        }
        for (int c = 0; c < now.length; c++) {
            if (now[c] == was[c]) continue;
            failures++;
            System.out.println("  FAIL " + what + ": (" + bufRow + "," + c + ") = U+"
                    + Integer.toHexString((int) (now[c] & 0xFFFF)) + " 0x"
                    + Integer.toHexString((int) ((now[c] >>> 16) & 0xFFFF))
                    + ", was U+" + Integer.toHexString((int) (was[c] & 0xFFFF)) + " 0x"
                    + Integer.toHexString((int) ((was[c] >>> 16) & 0xFFFF)));
            return;
        }
    }

    private static void gate(String what, boolean ok, String detail) {
        checks++;
        System.out.println((ok ? "  ok   " : "  FAIL ") + what + (detail == null ? "" : "  " + detail));
        if (!ok) failures++;
    }

    /** move the viewport cursor to a window row without painting */
    private static void gotoRow(int modelRow) {
        paint("goto " + modelRow, "\u001b[" + (modelRow + 1) + ";1H");
    }

    /**
     * What the renderer has written back to the console's input stream, consumed by the read. A reply is the
     * only effect in this library that leaves the process, so the console's own queue is the only witness
     * that can tell "answered" from "answered wrongly".
     */
    private static String input(int max) {
        char[] c = readInput(max);
        return c == null ? "<unreadable>" : new String(c);
    }

    /** A reply spelled the way a log can show it: ESC is not printable, and a raw one reads as noise. */
    private static String vis(String s) {
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            final char c = s.charAt(i);
            if (c == 0x1b) b.append("\\e");
            else if (c < 0x20 || c == 0x7f) b.append("\\x").append(Integer.toHexString(c));
            else b.append(c);
        }
        return b.toString();
    }

    /** Drain the queue and demand exactly `want`, one verdict. */
    private static void eqInput(String what, String want) {
        final String got = input(256);
        gate(what, got.equals(want), "got=" + vis(got) + " want=" + vis(want));
    }

    /**
     * The hold's own clock is {@code RC_SYNC_TIMEOUT_MS}, and the seam's only tick is the next flush, so a
     * timeout leg has to make the test itself wait. Sleeping here is the only way to pass that wall without
     * lowering the constant the production code reads.
     */
    private static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    /**
     * Render.h's {@code RC_SYNC_TIMEOUT_MS}. The gate cannot read a C macro, and a leg that guessed a smaller
     * number would be asserting that the clock is *at least* that big rather than what it is, so the pair is
     * stated here and the host gate ({@code RenderCheck.cpp}, {@code sync_output}) is the leg that checks the
     * real constant's behaviour; this is the number the two console legs budget their chunks against.
     */
    private static final int SYNC_CLOCK_MS = 100;

    /**
     * How long one chunk costs this console, in milliseconds -- the minimum of three probes, because a chunk
     * that happens to be preempted says nothing about the writer. {@link #caseSyncOutput} needs it to know
     * whether it can afford a region of two held chunks: the clock the mode starts is 100 ms old no matter how
     * slowly the test got there, so on a console where a paint costs a hundred milliseconds, a second chunk
     * arrives to a region the timeout already ended. That is the host being slow, not the renderer being wrong,
     * and the leg shortens itself and says so rather than reporting the difference as a failure.
     */
    private static long chunkCostMs() {
        long best = Long.MAX_VALUE;
        for (int i = 0; i < 3; i++) {
            final long t0 = System.nanoTime();
            paint("cost probe " + i, "\u001b[0m\u001b[2J\u001b[H");
            final long dt = System.nanoTime() - t0;
            if (dt < best) best = dt;
        }
        return Math.max(1, best / 1_000_000);
    }

    // ---- cases -------------------------------------------------------------------------------

    private static void casePlainText() {
        gotoRow(0);
        paint("plain text", "hello world");
        text("plain", winT, 0, "hello world", DEF);
        tail("plain tail", winT, 11, DEF);
        /* the console's own cursor, not the model's: this is the row conhost will write next */
        long[] v = consoleView();
        gate("plain leaves the cursor at (11, winT)", v[5] == 11 && v[6] == winT,
                "(" + v[5] + "," + v[6] + ") winT=" + winT);
    }

    /** defAttr 0x07 is fg 7 on bg 0, so 31m is attribute 0x04 -- not 0x0C (see the colour oracle). */
    private static void caseColour() {
        gotoRow(1);
        paint("colour", "\u001b[31mRED\u001b[0m plain");
        text("red", winT + 1, 0, "RED", 0x04);
        text("reset", winT + 1, 3, " plain", DEF);
        tail("colour tail", winT + 1, 9, DEF);
    }

    /**
     * The echo ConEmuHk is fed after a paint, across the JNI boundary: the SGR bytes verbatim and in
     * order, and nothing else. A cursor move or an erase must not appear in it -- replaying one would
     * move the real cursor out from under whatever the terminal is doing. The attributes the same chunk
     * paints are asserted too, because the echo and the paint have to agree about where the chunk left
     * the colour state for the sequence that follows it.
     */
    private static void caseSgrEcho() {
        gotoRow(3);
        char[] c = "\u001b[31mred\u001b[1m bold\u001b[0m\u001b[K tail".toCharArray();
        if (feed(handle, c, 0, c.length) == 0) { gate("echo: feed", false, null); return; }
        int r = flush(handle);
        char[] e = NativeRenderer.sgr(handle);
        winT = (int) consoleView()[0];
        gate("echo: accepted", r == 0 || r == 1, "flush=" + r);
        String got = e == null ? "" : new String(e);
        gate("the SGR bytes, verbatim", "\u001b[31m\u001b[1m\u001b[0m".equals(got), visible(got));
        gate("a second take is empty", NativeRenderer.sgr(handle) == null, null);
        text("echo red", winT + 3, 0, "red", 0x04);
        text("echo bold", winT + 3, 3, " bold", 0x0C);        /* 1m brightens a 4-bit foreground */
        text("echo after reset", winT + 3, 8, " tail", DEF);  /* \e[0m came before the EL */
        tail("echo tail", winT + 3, 13, DEF);
    }

    /** Control characters made visible, so a failure line shows what was actually captured. */
    private static String visible(String s) {
        StringBuilder b = new StringBuilder("\"");
        for (int i = 0; i < s.length(); i++) {
            char ch = s.charAt(i);
            b.append(ch < 32 ? "<" + (int) ch + ">" : String.valueOf(ch));
        }
        return b.append('"').toString();
    }

    /**
     * The one effect of an OSC that a grid can never witness: the window title lives outside the screen
     * buffer, so the only proof is the console's own GetConsoleTitleW -- which is also the parity being
     * restored here, since the fallback leg sets the title at Ansi.cpp:3851 and this renderer did not.
     *
     * The rest of the family has no witness but its counter, and that is the point of the case: an
     * "ESC ] 9 ; 7 ; calc.exe" is a request to run a program, and what a renderer owes the user is the
     * record that it saw one and did nothing. There is no code path here that could run anything, so what
     * is asserted is the counter moving and the title not moving with it.
     */
    private static void caseOscTitle() {
        long[] a = stats(handle);
        paint("a title is not a rectangle", "\u001b]0;render gate\u0007");
        long[] b = stats(handle);
        gate("the console took the title", "render gate".equals(title()), visible(title()));
        gate("nothing was painted for it", b[5] == a[5], "cells=" + (b[5] - a[5]));
        gate("one title parsed", b[S_TITLES] - a[S_TITLES] == 1, "titles=" + (b[S_TITLES] - a[S_TITLES]));
        gate("one title reached the console", b[S_TITLES_APPLIED] - a[S_TITLES_APPLIED] == 1,
                "applied=" + (b[S_TITLES_APPLIED] - a[S_TITLES_APPLIED]));
        gate("a title is not a dropped sequence", b[S_UN + 7] - a[S_UN + 7] == 0,
                "other OSC=" + (b[S_UN + 7] - a[S_UN + 7]));

        /* ST rather than BEL, and code 2 rather than 0: three spellings of the same three lines
           upstream (Ansi.cpp:3842-3854). */
        paint("title by ST", "\u001b]2;via ST\u001b\\");
        gate("ST terminates it too", "via ST".equals(title()), visible(title()));

        /* A payload longer than the model's own buffer: still consumed, still a title, applied clipped.
         * The alternative -- drop it as malformed -- would lose the sequence to the console, which is the
         * one outcome I19 says never to produce silently. RC_TITLE_MAX counts the whole payload, "0;"
         * included, so what reaches the console is the first (256-2) units of it. */
        StringBuilder long9 = new StringBuilder();
        for (int i = 0; i < 300; i++) long9.append((char) ('a' + i % 26));
        final String clipped = long9.substring(0, 254);
        a = stats(handle);
        paint("a title past RC_TITLE_MAX", "\u001b]0;" + long9 + "\u0007");
        b = stats(handle);
        gate("the clipped title was parsed", b[S_TITLES] - a[S_TITLES] == 1,
                "titles=" + (b[S_TITLES] - a[S_TITLES]));
        gate("and counted as truncated", b[S_TITLES_TRUNC] - a[S_TITLES_TRUNC] == 1,
                "truncated=" + (b[S_TITLES_TRUNC] - a[S_TITLES_TRUNC]));
        gate("and still reached the console", b[S_TITLES_APPLIED] - a[S_TITLES_APPLIED] == 1,
                "applied=" + (b[S_TITLES_APPLIED] - a[S_TITLES_APPLIED]));
        gate("with the model's own cap, not a dropped tail", clipped.equals(title()),
                "len=" + title().length() + " " + visible(title()));

        a = stats(handle);
        paint("OSC 9 counted, not executed", "\u001b]9;7;calc.exe\u0007");
        b = stats(handle);
        gate("the private family has its own counter", b[S_UN + 6] - a[S_UN + 6] == 1,
                "osc9=" + (b[S_UN + 6] - a[S_UN + 6]));
        gate("it parsed no title", b[S_TITLES] - a[S_TITLES] == 0, "titles=" + (b[S_TITLES] - a[S_TITLES]));
        gate("the title is unchanged", clipped.equals(title()), visible(title()));

        a = stats(handle);
        gotoRow(6);
        paint("an abandoned title", "\u001b]0;stale\u001b[31mR\u001b[0m\u001b[K");
        b = stats(handle);
        gate("the abandoned OSC was counted", b[S_UN + 7] - a[S_UN + 7] == 1,
                "other OSC=" + (b[S_UN + 7] - a[S_UN + 7]));
        gate("but its title was never applied", clipped.equals(title()), visible(title()));
        text("the colour after it applied", winT + 6, 0, "R", 0x04);
        tail("and the row was erased again", winT + 6, 1, DEF);

        /* DCS is framing, not state: a whole payload consumed, its own counter, no title. */
        a = stats(handle);
        paint("DCS counted", "\u001bP1;2$q+\u001b\\");
        b = stats(handle);
        gate("the DCS family has its own counter", b[S_UN + 8] - a[S_UN + 8] == 1,
                "dcs=" + (b[S_UN + 8] - a[S_UN + 8]));
        gate("and it set no title", b[S_TITLES] - a[S_TITLES] == 0, "titles=" + (b[S_TITLES] - a[S_TITLES]));
        gate("no console call failed on any of it", b[3] - a[3] == 0, "apiErrors=" + (b[3] - a[3]));
    }

    /** The console's own title, or a marker when the read failed -- so a failure line says which. */
    private static String title() {
        char[] t = consoleTitle();
        return t == null ? "<unreadable>" : new String(t);
    }

    /**
     * OSC 133 is the one family whose whole effect is invisible on the screen: a mark says "this row is a
     * prompt" to a reader that is not the console, so conhost paints nothing for it and a screenshot can
     * tell a working implementation from a dropped one no better than the reverse. What this gate can
     * witness is the seam a rollout actually reads -- the counter moved, the sequence was not mistaken for
     * an unmodelled OSC, the cursor and the grid are byte for byte what they were, and a window title was
     * not overwritten by a payload that never asked for one. The row-level semantics (which row a fresh
     * line claims, what a D searches upward for) are pinned far more cheaply against a grid in
     * RenderCheck.cpp, and this function cannot see that grid.
     */
    private static void caseSemanticPrompt() {
        gotoRow(8);
        paint("clear the row to be marked", "\u001b[0m\u001b[2K");
        tail("so a blank row is a fact and not a memory", winT + 8, 0, DEF);
        long[] a = stats(handle);
        gate("no 133 earlier in this run reported an exit", a[S_EXIT] == -1, "lastExit=" + a[S_EXIT]);
        paint("a bare mark", "\u001b]133;A\u0007");
        long[] b = stats(handle);
        gate("one prompt marked", b[S_PROMPTS] - a[S_PROMPTS] == 1, "marks=" + (b[S_PROMPTS] - a[S_PROMPTS]));
        gate("and it was not dropped as an unknown OSC", b[S_UN + 7] - a[S_UN + 7] == 0,
                "other OSC=" + (b[S_UN + 7] - a[S_UN + 7]));
        gate("nothing was painted for it", b[5] - a[5] == 0, "cells=" + (b[5] - a[5]));
        gate("the cursor did not move", b[10] == a[10] && b[11] == a[11],
                "cursor=" + a[10] + "," + a[11] + " -> " + b[10] + "," + b[11]);
        gate("and no window title was claimed", b[S_TITLES] - a[S_TITLES] == 0,
                "titles=" + (b[S_TITLES] - a[S_TITLES]));
        tail("the marked row is still blank", winT + 8, 0, DEF);

        /* A prompt and the input on it, in one chunk: the text has to land exactly where it would have
           without the marks, since the marks are the only thing here that ConEmu itself never had. On a
           fresh row, because the mark above already owns row 8 and re-marking a row that is already a
           prompt changes nothing -- which is the point, and would be invisible if this reused the row. */
        gotoRow(9);
        paint("clear the second row", "\u001b[0m\u001b[2K");
        a = stats(handle);
        paint("marked prompt and input", "\u001b]133;A\u0007c> \u001b]133;B\u0007select 1;");
        b = stats(handle);
        text("the marked line reads as typed", winT + 9, 0, "c> select 1;", DEF);
        tail("to the end of it", winT + 9, 12, DEF);
        gate("the mark counted once, not twice", b[S_PROMPTS] - a[S_PROMPTS] == 1,
                "marks=" + (b[S_PROMPTS] - a[S_PROMPTS]) + ": 133;B starts input, it does not mark a row");

        /* A letter this model has no case for is counted where ConEmu's own silence would be counted, and
         * marks nothing: the alternative is a frame that looks modelled because the count went up. */
        a = stats(handle);
        paint("an unknown 133 letter", "\u001b]133;Q\u0007");
        b = stats(handle);
        gate("counted as an unmodelled OSC", b[S_UN + 7] - a[S_UN + 7] == 1,
                "other OSC=" + (b[S_UN + 7] - a[S_UN + 7]));
        gate("and it marked nothing", b[S_PROMPTS] - a[S_PROMPTS] == 0,
                "marks=" + (b[S_PROMPTS] - a[S_PROMPTS]));

        /* The exit code is the one value in this family a status bar would read straight off the model, so
         * the gate pins both legs of it through the same seam: a number, and something that is not one.
         * 2147483647 is RC_EXIT_UNPARSABLE -- the same coercion MSFT applies (TermControl reports a garbage
         * code as an error rather than as status 0). Both arrive at column 16, where the typing left off,
         * and neither may put a glyph there. */
        a = b;
        paint("exit code 7", "\u001b]133;D;7\u0007");
        b = stats(handle);
        gate("the grid knows the code", b[S_EXIT] == 7, "lastExit=" + b[S_EXIT]);
        gate("and painted nothing for it", b[5] == a[5], "cells=" + (b[5] - a[5]));
        a = b;
        paint("exit code that is not one", "\u001b]133;D;abc\u0007");
        b = stats(handle);
        gate("and knows it could not read that one", b[S_EXIT] == 2147483647L, "lastExit=" + b[S_EXIT]);
        gate("again with no glyph for it", b[5] == a[5], "cells=" + (b[5] - a[5]));
        tail("the marked line is unchanged", winT + 9, 16, DEF);
    }

    /**
     * DSR and DA: the two families whose whole effect is a reply, which no grid read can see and no cell
     * count can miss. The witness is therefore the console's own input queue, and it earns its keep: a
     * counter says only that WriteConsoleInputW took *something*, while a CPR one row off is a program
     * redrawing the wrong line and believing it saw the screen. The order of a multi-query chunk is asserted
     * too, because the asker reads its replies in the order it asked, and the snapshot rule -- answer where
     * the cursor stood when the question was read, not where it stands now -- is the one thing here that a
     * naive drain gets wrong.
     */
    /**
     * The palette, witnessed on the console rather than in the model (I34). The host gate already proves
     * what the parser stored; what only a live run can prove is that the change reached CONOUT$'s ColorTable,
     * that a read-modify-write left the user's other fifteen alone -- twice, because the second write is the
     * one that could have reverted the first -- that a colour query comes back as bytes in xterm's 16-bit
     * form, and that an OSC 10 reaches the screen through the pen and the erase.
     * These legs run on the gate's own handle on purpose: two live handles on one console each carry their
     * own row claim (I27/I28), and a second one's second flush declines as NOGEOM for reasons that have
     * nothing to do with colours. The restore-at-close() witness therefore lives at the end of main(), where
     * the real close happens, and `paletteBefore` is what it compares against.
     * The leg ends by putting the console back: 104 restores the standard table and 110/111 the default
     * attribute, so no later leg inherits a recoloured pen.
     */
    /**
     * The OSC 9 safe subset, read back through the API the host uses (T7). The host gate proves the parse;
     * what this leg adds is that the two stored facts survive the thing a real session does to a model --
     * a resize, which rebuilds it -- and that the dangerous half still leaves nothing behind.
     */
    private static void caseOsc9() {
        paint("OSC 9;4", "\u001b]9;4;1;50\u0007");
        long[] tb = NativeRenderer.taskbar(handle);
        gate("9;4 reaches the caller as state and progress",
                tb != null && tb.length == 3 && tb[0] == 1 && tb[1] == 50 && tb[2] == 1,
                tb == null ? "null" : java.util.Arrays.toString(tb));

        paint("a clamped 9;4", "\u001b]9;4;2;150\u0007");
        tb = NativeRenderer.taskbar(handle);
        gate("progress is clamped before anyone sees it", tb != null && tb[1] == 100 && tb[0] == 2,
                tb == null ? "null" : java.util.Arrays.toString(tb));

        paint("OSC 9;9", "\u001b]9;9;\"D:/x\"\u0007");
        gate("9;9 strips the quotes ConEmu's spelling adds", "D:/x".equals(NativeRenderer.workingDirectory(handle)),
                "got=" + NativeRenderer.workingDirectory(handle));

        paint("the dangerous one", "\u001b]9;7;calc.exe\u0007");
        tb = NativeRenderer.taskbar(handle);
        final String cwd = NativeRenderer.workingDirectory(handle);
        gate("9;7 changes neither stored fact", tb != null && tb[0] == 2 && tb[1] == 100 && "D:/x".equals(cwd),
                "taskbar=" + java.util.Arrays.toString(tb) + " cwd=" + cwd);

        gate("and a rebuild carries both", readopt(handle) == 1, "readopt refused");
        tb = NativeRenderer.taskbar(handle);
        gate("the taskbar pair survived the rebuild", tb != null && tb[0] == 2 && tb[1] == 100,
                tb == null ? "null" : java.util.Arrays.toString(tb));
        gate("and so did the directory", "D:/x".equals(NativeRenderer.workingDirectory(handle)),
                "got=" + NativeRenderer.workingDirectory(handle));
    }

    /**
     * I36: OSC 52, against the real clipboard. The host gate can prove the parser armed the right bytes;
     * only this leg shows the request travelled through the model, out of the flush, into the system
     * clipboard, and back out as the same text -- which is what a host is buying when it turns the switch
     * on. Three things are pinned beside the happy path: the default is off (so the request that this case
     * then enables has to be refused first, and counted); the read form is refused with the switch on,
     * because answering it would put the user's own clipboard into the input stream; and a refused request
     * must leave the clipboard holding what it held, which only a readback can show -- and, to be a
     * readback at all, that one has to come from outside this process (see the helpers below).
     *
     * The clipboard belongs to the user, so this case saves it and puts it back.
     */
    private static void caseClipboard() {
        final String marker = "native-renderer-" + System.nanoTime();
        /* The encoder is load-bearing for every case below, so it is pinned to RFC 4648's own vectors first:
           a tail branch that lost its mask would otherwise throw halfway through the case (or, worse, hand
           the strict decoder a well-formed-looking string that encodes something else) and the numbers this
           case reports would stop meaning what they say. */
        gate("the test's own base64 matches RFC 4648",
                eqStr(b64("a"), "YQ==") && eqStr(b64("ab"), "YWI=") && eqStr(b64("abc"), "YWJj")
                        && eqStr(b64(""), ""),
                "a=" + b64("a") + " ab=" + b64("ab") + " abc=" + b64("abc"));
        /* Read what the person owns before touching anything. The case has to seed a value of its own to tell
           "the library wrote" from "the reader is lying", and a gate that does that without remembering who
           had the register leaves the user's clipboard holding test text. `user` is what goes back. */
        final String user = clipText();
        if (!clipSeed("clipboard-gate-before")) {
            System.out.println("  SKIP clipboard: no out-of-process clipboard witness (pwsh Set-/Get-Clipboard)");
            clipRestore(user);
            return;
        }
        clipDown = false;
        final String before = clipText();
        if (!eqStr(before, "clipboard-gate-before")) {
            /* The register is not ours to witness. Every leg below either re-seeds it or reads it back, and a
               value from another process would then be reported as this library's doing -- which is a claim
               about a security boundary, so the case declines to make any at all. Measured: with a script
               writing the clipboard every 250 ms this leg is what fails first, and the nine reds it used to
               produce all said "the renderer wrote to the clipboard anyway". */
            clipSkip("the witness can read what it just wrote", "read back " + show(before)
                    + "; an outside process owns the register, so this case has no witness");
            clipRestore(user);
            return;
        }
        gate("the witness can read what it just wrote", true, "read back " + show(before));

        /* ---- off, which is the state a session gets without having asked ---- */
        gotoRow(3);
        long[] a = stats(handle);
        paint("clipboard, policy off", "\u001b]52;c;" + b64sent(marker) + "\u0007X");
        long[] b = stats(handle);
        gate("nothing was written", b[S_CLIP_WRITES] == a[S_CLIP_WRITES],
                "writes=" + b[S_CLIP_WRITES] + " after " + a[S_CLIP_WRITES]);
        gate("the refusal is counted", b[S_UN + 11] - a[S_UN + 11] == 1,
                "clip refused=" + (b[S_UN + 11] - a[S_UN + 11])
                        + ": a sequence that did nothing must still leave a number");
        gate("and not also as an unknown OSC", b[S_UN + 7] == a[S_UN + 7],
                "other osc moved by " + (b[S_UN + 7] - a[S_UN + 7]) + ": code 52 has its own family now");
        clipUnchanged("the clipboard still holds what it held", before);
        cell("the text after the OSC painted anyway", winT + 3, 0, 'X', DEF);

        /* ---- on ---- */
        NativeRenderer.setClipboardPolicy(true);
        gate("the dll says so", NativeRenderer.clipboardPolicy(), "the call did not reach the library");
        a = stats(handle);
        paint("clipboard, policy on", "\u001b]52;c;" + b64sent(marker) + "\u0007");
        b = stats(handle);
        gate("one write reached the clipboard", b[S_CLIP_WRITES] == a[S_CLIP_WRITES] + 1,
                "writes=" + b[S_CLIP_WRITES] + " failed=" + b[S_CLIP_FAILS]);
        gate("and nothing was refused", b[S_UN + 11] == a[S_UN + 11], "refused=" + b[S_UN + 11]);
        clipIs("the text is the text that was sent", marker);

        /* UTF-8 across the same path: the parser keeps bytes, the painter converts them, and a clipboard
           that mangled them would look right in the model and wrong to the user. */
        final String cjk = "中文-a";
        a = stats(handle);
        paint("clipboard, not ascii", "\u001b]52;c;" + b64sent(cjk) + "\u0007");
        clipIs("the wide characters survive the round trip", cjk);
        gate("and it cost one more write", stats(handle)[S_CLIP_WRITES] == a[S_CLIP_WRITES] + 1,
                "writes=" + stats(handle)[S_CLIP_WRITES]);

        /* An empty payload is a request to clear, not the absence of one. */
        a = stats(handle);
        paint("clipboard, clear", "\u001b]52;;\u0007");
        gate("clearing is a write too", stats(handle)[S_CLIP_WRITES] == a[S_CLIP_WRITES] + 1,
                "writes=" + stats(handle)[S_CLIP_WRITES]);
        /* "empty" is one read, and the reader cannot tell an empty string from no text format at all: both
           come back as nothing printed. Either is the outcome the request asked for, so the assertion says
           the weaker true thing rather than pretending to distinguish them. */
        clipIs("and the clipboard is empty", "");

        /* ---- refusals, with the switch on, and the clipboard left alone ---- */
        clipSeed(marker);
        a = stats(handle);
        paint("clipboard, a target windows has no place for", "\u001b]52;p;" + b64sent("nope") + "\u0007");
        b = stats(handle);
        gate("`p` is refused rather than folded onto the clipboard",
                b[S_CLIP_SELECTION] == a[S_CLIP_SELECTION] + 1, "selection refusals=" + b[S_CLIP_SELECTION]);
        gate("no write happened", b[S_CLIP_WRITES] == a[S_CLIP_WRITES], "writes=" + b[S_CLIP_WRITES]);
        clipUnchanged("so the clipboard still holds the marker", marker);

        a = stats(handle);
        paint("clipboard, a bad encoding", "\u001b]52;c;YW*j\u0007");
        b = stats(handle);
        gate("a payload outside the alphabet is refused whole",
                b[S_CLIP_DECODE] == a[S_CLIP_DECODE] + 1, "decode refusals=" + b[S_CLIP_DECODE]);
        clipUnchanged("nothing was overwritten with the good prefix", marker);

        a = stats(handle);
        paint("clipboard, a read", "\u001b]52;c;?\u0007");
        b = stats(handle);
        gate("a read is refused with the write switch on", b[S_CLIP_READ] == a[S_CLIP_READ] + 1,
                "read refusals=" + b[S_CLIP_READ]);
        final char[] drained = readInput(16);
        gate("and nothing was answered into the input stream", drained == null || drained.length == 0,
                drained == null ? "null" : "read back " + new String(drained));
        clipUnchanged("the clipboard was not read either", marker);

        /* ---- back to the default, and the register back to whoever owned it ---- */
        NativeRenderer.setClipboardPolicy(false);
        gate("the switch is off again", !NativeRenderer.clipboardPolicy(), "policy still on");
        if (user == null || user.length() == 0) {
            clipClear();
            String restored = clipText();
            if (restored != null && restored.length() != 0) {
                /* One retry, and the reason is measured: a run of this gate spawns a pwsh per clipboard read,
                   and one x64 attempt came back holding the test's own marker -- the clear had not landed. A
                   single flaky child must not read as "the gate wrecked the user's clipboard", which is the
                   one claim in this case that is about the *user* rather than about the library. */
                clipClear();
                restored = clipText();
            }
            gate("and what the owner had is back, which here was nothing",
                    restored == null || restored.length() == 0, "read back " + show(restored));
        } else {
            clipSeed(user);
            String back = clipText();
            if (!eqStr(back, user)) {
                clipSeed(user);                     // one retry: a child that failed is not a claim about the library
                back = clipText();
            }
            /* Not clipIs(): that helper is allowed to *skip* when the register is contended, and this leg is
               the one place a skip would be a lie -- if the restore did not land, the user's clipboard is
               holding test text, and the gate has to say so rather than decline to answer. */
            gate("and the register is back to the text its owner had", eqStr(back, user),
                    "read back " + show(back) + " want " + show(user));
        }
        gate("and the policy slot says off at the end of the run", stats(handle)[S_CLIP_POLICY] == 0,
                "policy=" + stats(handle)[S_CLIP_POLICY]);
    }

    /* The clipboard, seen from outside this JVM.
     *
     * AWT is the obvious reader and it is the wrong one for this case. Once this process has called
     * setContents it *is* the clipboard owner, and its Clipboard answers from the object it was handed
     * instead of asking the window system again -- so every readback after the gate's own seed returns the
     * gate's string whatever the library wrote. That is a false green in its worst shape: the counters said
     * a write happened, the readback said the text never changed, and the two were describing different
     * clipboards. A second process cannot share the writer's cache, and Set-/Get-Clipboard is the cheapest
     * out-of-process witness on every box this runs on. When pwsh is missing the case says so and skips
     * rather than falling back to the reader that can lie.
     * <p>
     * The second lesson from the same leg, learned the hard way on 2026-09-26: a second process also cannot
     * own a machine-wide register exclusively. One x64 run came back with a single red whose readback was 24
     * box-drawing characters -- a value no path in this library can produce, written by something else on the
     * box between our seed and our read. That is the mirror image of the AWT trap: not a reader that cannot
     * see, but one that sees somebody else's write, and it accuses the renderer of exactly the thing the
     * feature is switched off by default to prevent. So every read here is now classified before it is
     * reported (see {@link #clipIs} and {@link #clipUnchanged}), and the counters -- which no other process
     * can touch -- carry the claims. Running a deliberate competitor (a script writing the clipboard every
     * 250 ms, {@code cache/p63/clip-hammer.ps1}) is how the shape of that handling was settled. */
    private static final String CLIP_IN =
            "[Console]::InputEncoding=[Text.Encoding]::UTF8; $t=[Console]::In.ReadToEnd();"
            + " if ($t.Length -eq 0) { Clear-Clipboard } else { Set-Clipboard -Value $t }";
    private static final String CLIP_OUT =
            "[Console]::OutputEncoding=[Text.Encoding]::UTF8; Get-Clipboard -Raw";

    /** The clipboard's text, or null when the witness could not run at all. Nothing printed is "". */
    private static String clipText() {
        final String out = clipChild(CLIP_OUT, null);
        return out == null ? null : trimEol(out);
    }

    /** Put text on the clipboard from the witness process. Empty text clears, which is what the library's
     *  own empty payload has to be compared against. */
    private static boolean clipSeed(final String text) {
        return clipChild(CLIP_IN, text == null ? "" : text) != null;
    }

    private static boolean clipClear() {
        return clipChild(CLIP_IN, "") != null;
    }

    /** One read, one assertion. Reading the clipboard costs a process, so the case asks for a sentence and
     *  the value in it comes from the same single read.
     * <p>
     * The register is machine-wide, so a mismatch has two possible authors. A value this run offered is the
     * library's and stays a red; anything else came from outside, and the leg retries the read once before
     * saying so. A second mismatch makes the whole case un-witnessable, which is reported as a skip: a red
     * here reads as "the renderer put text on the clipboard that was refused", and that claim needs the
     * counters behind it to mean anything. */
    private static void clipIs(final String what, final String want) {
        if (clipDown) {
            clipSkip(what, "the register was lost to another process earlier in this case");
            return;
        }
        final String first = clipText();
        if (eqStr(first, want)) {
            gate(what, true, "read back " + show(first));
            return;
        }
        if (first != null && CLIP_OFFERED.contains(first)) {
            gate(what, false, "read back a payload this run offered, but not the one expected: " + show(first));
            return;
        }
        final String again = clipText();
        if (eqStr(again, want)) {
            gate(what, true, "read " + show(first) + " first and the expected value after it:"
                    + " the register changed hands mid-read");
            return;
        }
        clipDown = true;
        clipSkip(what, "an outside process holds " + show(again) + ", so no claim about what was written can"
                + " be read back; the write counters above are still the evidence that a write happened");
    }

    /**
     * The "nothing was written" half, and the reason it cannot share {@link #clipIs} with the fidelity half.
     * The claim is about the library, and the library's side of it is the write counter, which the caller
     * asserts in the same breath; this read is corroboration only. So a foreign value here is recovered by
     * taking the register back -- re-seeding proves nothing about the library either way, in this direction --
     * and the verdict says in words that something else held it. Measured, not theorised: one leg of this case
     * came back red holding 24 box-drawing characters, which no path in this library can produce, between a
     * seed and a read that both succeeded. What the recovery cannot do is witness the register while a
     * determined writer holds it; then the seed will not stick, and the honest report is a skip.
     */
    private static void clipUnchanged(final String what, final String want) {
        if (clipDown) {
            clipSkip(what, "the register was lost to another process earlier in this case");
            return;
        }
        final String first = clipText();
        if (eqStr(first, want)) {
            gate(what, true, "read back " + show(first));
            return;
        }
        if (first != null && CLIP_OFFERED.contains(first)) {
            gate(what, false, "read back a payload this run offered: " + show(first)
                    + " -- a refusal that wrote anyway");
            return;
        }
        if (clipSeed(want) && eqStr(clipText(), want)) {
            gate(what, true, "an outside process held " + show(first) + "; the register was taken back and"
                    + " confirmed. The write counter is the claim, this read is the corroboration");
            return;
        }
        clipDown = true;
        clipSkip(what, "an outside process holds " + show(first) + " and would not give the register back");
    }

    /** Set when a read could not be matched and the register could not be taken back. */
    private static boolean clipDown;

    /** A third state, and the shape the rest of this file already uses for it: counted as a check, never as a
     *  failure, and never as a pass either. */
    private static void clipSkip(final String what, final String why) {
        checks++;
        System.out.println("  skip " + what + ": " + why);
    }

    /** The case may leave the register holding whatever the user had, never what the test used. Called on the
     *  way out of a contended run, when the restore itself is unverifiable. */
    private static void clipRestore(final String before) {
        if (before == null || before.length() == 0) {
            clipClear();
        } else {
            clipSeed(before);
        }
        final String now = clipText();
        if (!eqStr(now, before)) {
            System.out.println("  note clipboard left holding " + show(now) + " instead of " + show(before)
                    + ": an outside process is writing the register faster than this gate can restore it");
        }
    }

    /** Run `pwsh -NoProfile -Command <code>`, feeding `stdin` as UTF-8 when it is not null, and return what
     *  the child printed. Null means it could not start, timed out, or exited non-zero. The text goes on
     *  stdin and never into the command line, so no quoting has to be right for the gate to work. */
    private static String clipChild(final String code, final String stdin) {
        try {
            final Process p = new ProcessBuilder("pwsh", "-NoProfile", "-Command", code)
                    .redirectErrorStream(false).start();
            if (stdin != null) {
                final java.io.OutputStream in = p.getOutputStream();
                in.write(stdin.getBytes("UTF-8"));
                in.flush();
                in.close();
            }
            final java.io.ByteArrayOutputStream bo = new java.io.ByteArrayOutputStream();
            final byte[] buf = new byte[2048];
            int n;
            while ((n = p.getInputStream().read(buf)) > 0) {
                bo.write(buf, 0, n);
            }
            if (!p.waitFor(30, java.util.concurrent.TimeUnit.SECONDS)) {
                p.destroy();
                return null;
            }
            return p.exitValue() != 0 ? null : new String(bo.toByteArray(), "UTF-8");
        } catch (Throwable t) {
            return null;
        }
    }

    /** Only the line break the console prints after a value, never one the text itself ends with: what is
     *  on the clipboard is put back on it unchanged, so the restore round-trips a trailing newline. */
    private static String trimEol(final String s) {
        int e = s.length();
        while (e > 0 && (s.charAt(e - 1) == '\n' || s.charAt(e - 1) == '\r')) {
            e--;
        }
        return s.substring(0, e);
    }

    private static String show(final String s) {
        if (s == null) {
            return "(no text)";
        }
        final StringBuilder b = new StringBuilder("\"");
        for (int i = 0; i < s.length() && i < 40; i++) {
            final char c = s.charAt(i);
            if (c == '\r') {
                b.append("\\r");
            } else if (c == '\n') {
                b.append("\\n");
            } else if (c < 0x20) {
                b.append('?');
            } else {
                b.append(c);
            }
        }
        return b.append('"').append(s.length() > 40 ? "..." : "").toString();
    }

    private static boolean eqStr(final String a, final String b) {
        return a == null ? b == null : a.equals(b);
    }

    /**
     * base64 of UTF-8 bytes, written out here rather than imported: the renderer's own decoder is strict
     * about padding and about the unused bits of a final group, and a test that leaned on a library encoder
     * it does not control could produce a string the library is right to refuse.
     */
    private static String b64(final String text) {
        final byte[] raw;
        try {
            raw = text.getBytes("UTF-8");
        } catch (java.io.UnsupportedEncodingException e) {
            throw new IllegalStateException(e);
        }
        final String alpha = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        final StringBuilder b = new StringBuilder();
        int i = 0;
        for (; i + 3 <= raw.length; i += 3) {
            final int v = ((raw[i] & 0xFF) << 16) | ((raw[i + 1] & 0xFF) << 8) | (raw[i + 2] & 0xFF);
            b.append(alpha.charAt(v >> 18 & 63)).append(alpha.charAt(v >> 12 & 63))
                    .append(alpha.charAt(v >> 6 & 63)).append(alpha.charAt(v & 63));
        }
        if (raw.length - i == 1) {
            final int v = (raw[i] & 0xFF) << 16;
            b.append(alpha.charAt(v >> 18 & 63)).append(alpha.charAt(v >> 12 & 63)).append("==");
        } else if (raw.length - i == 2) {
            final int v = ((raw[i] & 0xFF) << 16) | ((raw[i + 1] & 0xFF) << 8);
            b.append(alpha.charAt(v >> 18 & 63)).append(alpha.charAt(v >> 12 & 63))
                    .append(alpha.charAt(v >> 6 & 63)).append('=');
        }
        return b.toString();
    }

    /**
     * The payloads this run has asked the library to put on the clipboard, collected at the call sites rather
     * than written out again by hand. It is what lets a readback that is not what we expected be told apart
     * from an outside writer: see {@link #clipUnchanged}.
     */
    private static final java.util.List<String> CLIP_OFFERED = new java.util.ArrayList<String>();

    private static String b64sent(final String text) {
        if (!CLIP_OFFERED.contains(text)) CLIP_OFFERED.add(text);
        return b64(text);
    }

    private static void casePalette() {
        paletteBefore = palette();
        gate("the console's palette is readable", paletteBefore != null, "consolePalette returned no table");
        if (paletteBefore == null) return;

        paint("OSC 4", "\u001b]4;1;rgb:ff/00/00\u0007A");
        long[] p = palette();
        gate("it moved the entry the application named", p != null && p[1] == 0x000000FF,
                p == null ? "unreadable" : "got=0x" + Long.toHexString(p[1]));
        gate("and left the user's other fifteen alone", p != null && paletteDiff(p, paletteBefore, 1) == null,
                p == null ? "unreadable" : String.valueOf(paletteDiff(p, paletteBefore, 1)));

        final long[] v0 = consoleView();
        paint("a second OSC 4", "\u001b]4;2;rgb:00/ff/00\u0007B");
        final long[] v1 = consoleView();
        /* Named because every other field of the view can look untouched while the window's bottom moves,
           and a moved bottom is a geometry decline the next frame has to eat. */
        gate("and the window it wrote did not move",
                v0[0] == v1[0] && v0[1] == v1[1] && v0[2] == v1[2] && v0[3] == v1[3] && v0[8] == v1[8],
                "winT " + v0[0] + "->" + v1[0] + " winL " + v0[1] + "->" + v1[1]
                        + " buf " + v0[2] + "x" + v0[3] + "->" + v1[2] + "x" + v1[3]
                        + " winB " + v0[8] + "->" + v1[8] + " attr 0x" + Long.toHexString(v0[4])
                        + "->0x" + Long.toHexString(v1[4]));
        p = palette();
        gate("the second write added its own entry", p != null && p[2] == 0x0000FF00,
                p == null ? "unreadable" : "got=0x" + Long.toHexString(p[2]));
        gate("without reverting the first", p != null && p[1] == 0x000000FF,
                p == null ? "unreadable" : "got=0x" + Long.toHexString(p[1]));

        readInput(0);
        paint("a colour query", "\u001b]4;1;?\u0007");
        eqInput("a query answers in xterm's 16-bit form",
                "\u001b]4;1;rgb:ffff/0000/0000\u001b\\");

        /* The default is model-side on this console (I34), so the witness is what a default *does*: an SGR
           reset puts it in the pen, the erase paints the screen with the pen. 0x00000080 is the standard
           table's entry 4, so a correct round trip lands the viewport on attribute 4. */
        paint("OSC 10 then reset then erase", "\u001b]10;rgb:80/00/00\u0007\u001b[m\u001b[2J");
        cell("the default the query named is the default the screen shows", winT + 2, 0, ' ', 0x04);

        paint("restore", "\u001b]104\u0007\u001b]110\u0007\u001b]111\u0007");
        p = palette();
        gate("104 put the standard table back on the console",
                p != null && p[1] == 0x00800000 && p[2] == 0x00008000,
                p == null ? "unreadable" : "1=0x" + Long.toHexString(p[1]) + " 2=0x" + Long.toHexString(p[2]));
        paint("a reset and an erase after the restore", "\u001b[m\u001b[2J");
        cell("and the default attribute came back too", winT + 2, 0, ' ', 0x07);
    }

    private static long[] paletteBefore;

    private static long[] palette() {
        long[] p = new long[16];
        return consolePalette(p) == 16 ? p : null;
    }

    private static String paletteDiff(long[] a, long[] b, int skip) {
        for (int i = 0; i < 16; i++) {
            if (i == skip) continue;
            if (a[i] != b[i]) return "entry " + i + ": got 0x" + Long.toHexString(a[i])
                    + " want 0x" + Long.toHexString(b[i]);
        }
        return null;
    }

    private static void caseReports() {
        readInput(0);                                /* start from a queue this case alone has filled */
        long[] a = stats(handle);
        paint("a status request", "\u001b[5n");
        long[] b = stats(handle);
        gate("one reply written", b[S_REPLIED] - a[S_REPLIED] == 1, "written=" + (b[S_REPLIED] - a[S_REPLIED]));
        gate("and the console took it", b[S_REPLY_FAIL] - a[S_REPLY_FAIL] == 0,
                "failed=" + (b[S_REPLY_FAIL] - a[S_REPLY_FAIL]));
        gate("and it was not counted as a question we refuse", b[S_UN + 9] - a[S_UN + 9] == 0,
                "report=" + (b[S_UN + 9] - a[S_UN + 9]));
        gate("nothing was painted for it", b[5] - a[5] == 0, "cells=" + (b[5] - a[5]));
        eqInput("ready", "\u001b[0n");

        /* 1-based, and counted from the top-left of the *window*: the same arithmetic the painter used to
           place the cursor this reply describes, so a row that scrolled between the question and the answer
           moves with it rather than disagreeing with it. */
        paint("a placed cursor and a position request", "\u001b[4;7H\u001b[6n");
        eqInput("the row and column it stood on", "\u001b[4;7R");

        paint("a question, then a move", "\u001b[6n\u001b[9;2H");
        eqInput("answered from the snapshot, not from the cursor now", "\u001b[4;7R");

        a = stats(handle);
        paint("two questions in one chunk", "\u001b[5n\u001b[6n");
        b = stats(handle);
        gate("both answered", b[S_REPLIED] - a[S_REPLIED] == 2, "written=" + (b[S_REPLIED] - a[S_REPLIED]));
        eqInput("oldest first", "\u001b[0n\u001b[9;2R");

        a = stats(handle);
        paint("identity, primary and secondary", "\u001b[c\u001b[>c");
        b = stats(handle);
        gate("two more replies", b[S_REPLIED] - a[S_REPLIED] == 2, "written=" + (b[S_REPLIED] - a[S_REPLIED]));
        /* conhost's own DA1 without `;52`, the clipboard access this renderer does not model, and its DA2
           verbatim (adaptDispatch.cpp:1454-1474). Parity is the point: a chunk this library declines goes to
           the console unparsed and conhost answers *that* one, so a program must not meet two identities. */
        eqInput("DA1 is the machine underneath's own string",
                "\u001b[?61;4;6;7;14;21;22;23;24;28;32;42c\u001b[>0;10;1c");

        /* A report this build will not answer is counted and left unanswered -- which is what a program
           asking for something outside the model has to be able to survive. */
        a = stats(handle);
        paint("an unanswered report", "\u001b[t");
        b = stats(handle);
        gate("counted, not swallowed", b[S_UN + 9] - a[S_UN + 9] == 1, "report=" + (b[S_UN + 9] - a[S_UN + 9]));
        gate("and nothing written to the input stream", b[S_REPLIED] - a[S_REPLIED] == 0,
                "written=" + (b[S_REPLIED] - a[S_REPLIED]));
        eqInput("the queue is empty", "");

        /* The queue's limit, which is a refusal rather than an eviction: dropping an older reply hangs a
         * program already blocked on its first read, and both outcomes leave a number. */
        a = stats(handle);
        StringBuilder many = new StringBuilder();
        for (int i = 0; i < 9; i++) many.append("\u001b[5n");
        paint("nine questions, one eight-deep queue", many.toString());
        b = stats(handle);
        gate("eight answered", b[S_REPLIED] - a[S_REPLIED] == 8, "written=" + (b[S_REPLIED] - a[S_REPLIED]));
        gate("and the ninth refused for a full queue", b[S_REPLY_FULL] - a[S_REPLY_FULL] == 1,
                "full=" + (b[S_REPLY_FULL] - a[S_REPLY_FULL]));
        StringBuilder eight = new StringBuilder();
        for (int i = 0; i < 8; i++) eight.append("\u001b[0n");
        eqInput("none lost, none duplicated", eight.toString());

        /* jline4's capability probe batch, byte for byte (AbstractTerminal.probeModes): kitty's keyboard
           query, the three DECRQM asks, and DA1 as the fence. `CSI ?u` used to follow ConEmu's unconditional
           restore (Ansi.cpp:4194) and teleport the cursor to the last DECSC, and a probe is exactly the
           thing that must never move a cursor -- so this leg saves a position, walks away from it, replays
           the batch and demands the console cursor still stand where it walked to. Of the three DECRQM ids,
           only 2026 is answered: this build has no state for 2027 (grapheme reflow) or 2048 (in-band resize),
           and jline4 reads a missing reply as NOT_SUPPORTED -- the honest verdict -- while any permanent
           status number would be read two opposite ways (AbstractTerminal.java:663-667). So the exact bytes
           below are the contract: one DECRPM for the mode that is modelled, then the fence, nothing else. */
        readInput(0);
        a = stats(handle);
        paint("a saved position the probe must not reach", "\u001b[3;5H\u001b[s\u001b[8;12H");
        long[] walked = consoleView();
        paint("the probe batch", "\u001b[?u\u001b[?2026$p\u001b[?2027$p\u001b[?2048$p\u001b[c");
        long[] afterProbe = consoleView();
        b = stats(handle);
        gate("the probe left the cursor where it stood",
                afterProbe[5] == walked[5] && afterProbe[6] == walked[6],
                "(" + walked[5] + "," + walked[6] + ") -> (" + afterProbe[5] + "," + afterProbe[6] + ")");
        gate("and three ids in it voted as refused modes", b[S_UN + 4] - a[S_UN + 4] == 3,
                "mode=" + (b[S_UN + 4] - a[S_UN + 4]) + " -- `?u`, then 2027 and 2048 unanswered");
        eqInput("the probe's one DECRPM, for 2026, and then the fence",
                "\u001b[?2026;" + (b[S_SYNC_ON] == 1 ? 2 : 1) + "$y"
                        + "\u001b[?61;4;6;7;14;21;22;23;24;28;32;42c");
        paint("the DECRC that save belongs to", "\u001b[u");
        afterProbe = consoleView();
        gate("while the plain `CSI u` still restores", afterProbe[5] == 4 && afterProbe[6] == winT + 2,
                "(" + afterProbe[5] + "," + afterProbe[6] + ") winT=" + winT);
    }

    /**
     * ConEmu's EL erases to dwSize.X, so a green background line must stay green all the way to column
     * 199 -- three quarters of it off screen. Under the buffer-wide model that is the model's own doing
     * (EL fills to `cols`, and `cols` is the buffer row) rather than a fill the painter invents, which is
     * why this case is worth keeping separate from the plain-tail ones.
     */
    private static void caseEraseToBufferWidth() {
        gotoRow(2);
        paint("erase", "\u001b[42mBG\u001b[K rest");
        text("green", winT + 2, 0, "BG", 0x27);
        cell("after EL", winT + 2, 2, ' ', 0x27);
        text("after EL text", winT + 2, 3, "rest", 0x27);
        tail("erase tail", winT + 2, 7, 0x27);
        paint("erase reset", "\u001b[0m");
    }

    /** COMMON_LVB_LEADING on the first cell, TRAILING on the second, same code point in both. */
    private static void caseWideGlyph() {
        gotoRow(4);
        paint("wide", "\u4e2d\u6587");
        cell("wide 0", winT + 4, 0, '\u4e2d', DEF | 0x0100);
        cell("wide 1", winT + 4, 1, '\u4e2d', DEF | 0x0200);
        cell("wide 2", winT + 4, 2, '\u6587', DEF | 0x0100);
        cell("wide 3", winT + 4, 3, '\u6587', DEF | 0x0200);
        tail("wide tail", winT + 4, 4, DEF);
        long[] s = stats(handle);
        gate("two glyphs, four cells", s[5] >= 4, "cells=" + s[5]);
    }

    /**
     * No cell of a wide glyph standing alone on a console row, read off the shipped binary. This is I16's
     * invariant, and it is the one every -25 fix can break: a fill, an insert, a delete or an erase that
     * reaches one half of a pair and not the other leaves a LEADING whose TRAILING is gone, which the user
     * sees as a duplicated character or a box. The host gate has the same check as a helper; the host gate
     * links {@code Render.cpp} directly and so cannot speak for the dll that ships.
     */
    private static void noOrphan(String what, int bufRow) {
        checks++;
        final long[] r = row(bufRow);
        if (r == null) {
            failures++;
            System.out.println("  FAIL " + what + ": row " + bufRow + " unreadable");
            return;
        }
        for (int c = 0; c < r.length; c++) {
            final int attr = (int) ((r[c] >>> 16) & 0xFFFF);
            final boolean lead = (attr & 0x0100) != 0, trail = (attr & 0x0200) != 0;
            if (!lead && !trail) continue;
            final int other = lead ? c + 1 : c - 1;
            final int oattr = (other >= 0 && other < r.length) ? (int) ((r[other] >>> 16) & 0xFFFF) : 0;
            final boolean paired = lead ? ((oattr & 0x0200) != 0 && (r[other] & 0xFFFF) == (r[c] & 0xFFFF))
                                         : ((oattr & 0x0100) != 0);
            if (paired) continue;
            failures++;
            System.out.println("  FAIL " + what + ": (" + bufRow + "," + c + ") is a "
                    + (lead ? "LEADING" : "TRAILING") + " half with no partner: U+"
                    + Integer.toHexString((int) (r[c] & 0xFFFF)) + " 0x" + Integer.toHexString(attr)
                    + " beside 0x" + Integer.toHexString(oattr));
            return;
        }
        System.out.println("  ok   " + what);
    }

    /**
     * IL and DL on a real console. Two claims, both from the reference reading that made -25: the shift
     * itself, and the cursor ending at the region's left margin afterwards (MSFT
     * {@code adaptDispatch.cpp:2150} "the IL and DL controls are also expected to move the cursor to the left
     * margin", ghostty's {@code defer cursorAbsolute(scrolling_region.left, start_y)}). The column is the
     * half an application cannot recover from: a program that redraws a table row by row walks in to a
     * column, deletes the line, and writes the replacement from wherever the cursor ended up, so a kept
     * column is every row printed n cells off, forever.
     */
    private static void caseEditRows() {
        if (!standardGeometry("the IL/DL leg")) return;
        final long[] a = stats(handle);
        /* Each row ends in a wide glyph on purpose: a vertical shift moves cells row by row, and the pair is
           the thing most likely to be left one cell behind. */
        paint("three rows to move", "\u001b[6;1HROW-A\u4e2d\u001b[7;1HROW-B\u6587\u001b[8;1HROW-C\u4e2d");
        paint("walk in to a column, then insert", "\u001b[6;5H\u001b[L");
        long[] v = consoleView();
        gate("IL took the cursor to column 0", v[5] == 0, "cursor=(" + v[5] + "," + v[6] + ")");
        gate("and kept it on the row it inserted", v[6] == winT + 5,
                "(" + v[5] + "," + v[6] + ") want (0," + (winT + 5) + ")");
        span("the inserted row is blank", winT + 5, 0, 9, ' ', DEF);
        text("the rows below moved down", winT + 6, 0, "ROW-A", DEF);
        cell("carrying their wide glyphs with them", winT + 6, 5, '中', DEF | 0x0100);
        cell("head and tail both", winT + 6, 6, '中', DEF | 0x0200);
        text("every one of them", winT + 7, 0, "ROW-B", DEF);
        noOrphan("a vertical shift leaves no half glyph", winT + 6);
        paint("and delete it again", "\u001b[M");
        v = consoleView();
        gate("DL homes the column too", v[5] == 0 && v[6] == winT + 5,
                "(" + v[5] + "," + v[6] + ") want (0," + (winT + 5) + ")");
        text("the deleted row is gone and the next took its place", winT + 5, 0, "ROW-A", DEF);
        text("with the one under it pulled up", winT + 6, 0, "ROW-B", DEF);

        /* A region: the rows outside it are the point. Without the guard a shift below would walk the
           application's prompt out of the bar's band, which is the #47/#48 family. */
        paint("a region of window rows 4..8", "\u001b[4;8r\u001b[6;1HIN-A\u001b[7;1HIN-B\u001b[9;1HOUTSIDE");
        paint("IL inside it, from a column", "\u001b[6;5H\u001b[L");
        v = consoleView();
        gate("the region's IL also homes the column", v[5] == 0 && v[6] == winT + 5,
                "(" + v[5] + "," + v[6] + ") want (0," + (winT + 5) + ")");
        span("the region got a blank row at the cursor", winT + 5, 0, 3, ' ', DEF);
        text("and its own rows moved down inside it", winT + 6, 0, "IN-A", DEF);
        text("the row below the region kept its own text", winT + 8, 0, "OUTSIDE", DEF);
        paint("a cursor outside the region is refused", "\u001b[9;5H\u001b[L");
        v = consoleView();
        gate("a refused IL keeps the column it was refused at", v[5] == 4 && v[6] == winT + 8,
                "(" + v[5] + "," + v[6] + ") want (4," + (winT + 8) + "): nothing moved, so nothing is owed");
        text("and the row it stood on is untouched", winT + 8, 0, "OUTSIDE", DEF);

        final long[] b = stats(handle);
        gate("none of that was counted as unsupported", b[S_UN] - a[S_UN] == 0,
                "unrecognised=" + (b[S_UN] - a[S_UN]));
        gate("and nothing was declined", b[2] - a[2] == 0, "declines=" + (b[2] - a[2]));
        paint("leave the band and the rows", "\u001b[r\u001b[4;1H\u001b[J");
    }

    /**
     * ECH (`CSI Ps X`) erases on the cursor's row and stops there. MSFT says it in prose
     * ({@code adaptDispatch.cpp:706-724}: "only erase characters in the current line, and won't wrap to the
     * next") and clamps with {@code std::min(startCol + numChars, GetLineWidth(row)}; ghostty's
     * {@code remaining = cols - cursor.x} agrees. The version this replaced walked down, so a
     * {@code CSI 999X} -- which is what an application sends when it means "to the end" -- erased the whole
     * viewport below the cursor. That is a data-loss shape, and it is the one leg that can see it: the host
     * gate proves the clamp, this proves the shipped dll applies it.
     */
    private static void caseEchClamp() {
        if (!standardGeometry("the ECH leg")) return;
        final long[] a = stats(handle);
        paint("four rows of text",
                "\u001b[6;1HA1A2A3A4\u001b[7;1HB1B2B3B4\u001b[8;1HC1C2C3C4\u001b[9;1HD1D2D3D4");
        paint("erase past the end of the row", "\u001b[6;3H\u001b[999X");
        long[] v = consoleView();
        gate("ECH leaves the cursor where it was", v[5] == 2 && v[6] == winT + 5,
                "(" + v[5] + "," + v[6] + ") want (2," + (winT + 5) + ")");
        text("the cells before the cursor are not the request", winT + 5, 0, "A1", DEF);
        span("the erase runs to the end of that row", winT + 5, 2, BUF_W - 1, ' ', DEF);
        text("and stops there: the next row is the application's", winT + 6, 0, "B1B2B3B4", DEF);
        text("the one after that too", winT + 7, 0, "C1C2C3C4", DEF);
        text("and the bottom of the viewport is untouched", winT + 8, 0, "D1D2D3D4", DEF);
        paint("CSI 0X erases nothing", "\u001b[7;1H\u001b[0X");
        text("a raw zero parameter is zero cells", winT + 6, 0, "B1B2B3B4", DEF);
        final long[] b = stats(handle);
        gate("ECH is modelled, not counted", b[S_UN] - a[S_UN] == 0, "unrecognised=" + (b[S_UN] - a[S_UN]));
        paint("clear the band", "\u001b[6;1H\u001b[J");
    }

    /**
     * The horizontal shifts, and the fills that can cut a pair in half. ICH/DCH move cells one at a time, so
     * a pair's two halves part; ECH and a narrow glyph written over a wide one's front half each destroy one
     * cell of a pair. All three are answered by one rule -- the pair is the unit -- and every one of them is
     * now healed by the same call, which is what makes a single witness worth having on real cells.
     */
    private static void caseHealPairs() {
        if (!standardGeometry("the pair-integrity leg")) return;
        final long[] a = stats(handle);
        paint("two wide glyphs and two narrow", "\u001b[6;1H\u4e2d\u6587ab");
        cell("the pair as written", winT + 5, 0, '中', DEF | 0x0100);
        cell("and its tail", winT + 5, 1, '中', DEF | 0x0200);
        paint("open one column at the left", "\u001b[6;1H\u001b[1@");
        cell("ICH's blank arrives first", winT + 5, 0, ' ', DEF);
        noOrphan("nothing crossed the shift as a lone half", winT + 5);
        paint("pull it back", "\u001b[6;1H\u001b[1P");
        noOrphan("DCH leaves no half behind", winT + 5);
        /* The narrow case, which is the one that used to be invisible. ICH and DCH move text, so every column
           from the cursor to the row's end is damage even though the only cells whose *value* changed are the
           gap -- and a run is the union of a row's claimed columns, so a claim that stops at the gap paints the
           gap and leaves the shifted text standing where it used to be. The wide-glyph legs above cannot see
           this: their shift breaks a pair, and healing a pair claims the cells it touches. This row has no
           pairs at all, so the only thing covering it is the claim. */
        paint("a narrow row, then ICH 3 at column 5", "\u001b[8;1HABCDEFGH\u001b[8;5H\u001b[3@");
        cell("the opened gap is blank", winT + 7, 4, ' ', DEF);
        cell("and E, which moved, is at the column the model put it in", winT + 7, 7, 'E', DEF);
        cell("with G behind it", winT + 7, 9, 'G', DEF);
        paint("and DCH 3 pulls the same tail back", "\u001b[8;5H\u001b[3P");
        cell("E is under the cursor again", winT + 7, 4, 'E', DEF);
        cell("and H stands at the end of the text", winT + 7, 7, 'H', DEF);
        paint("clear the band", "\u001b[8;1H\u001b[J");
        paint("restate the row", "\u001b[6;1H\u4e2d\u6587ab");
        /* One cell of an erase can reach only the head of a pair. The tail is then a glyph with no head, and
           the user sees it as a second copy of whatever was there; healing it means blanking the partner. */
        paint("erase one cell of a wide glyph", "\u001b[6;2H\u001b[1X");
        cell("the erased cell is blank", winT + 5, 1, ' ', DEF);
        cell("and so is the half that lost its partner", winT + 5, 0, ' ', DEF);
        noOrphan("the erase took the pair, not half of it", winT + 5);
        paint("restate the row again", "\u001b[6;1H\u4e2d\u6587ab");
        paint("a narrow glyph over the head of a pair", "\u001b[6;1HX");
        cell("the narrow one is what is there now", winT + 5, 0, 'X', DEF);
        cell("and the tail it stranded is cleared, not left standing", winT + 5, 1, ' ', DEF);
        noOrphan("overwriting a head takes its tail", winT + 5);
        final long[] b = stats(handle);
        gate("none of the three families is counted", b[S_UN] - a[S_UN] == 0,
                "unrecognised=" + (b[S_UN] - a[S_UN]));
        paint("clear the band", "\u001b[6;1H\u001b[2K");
    }

    /**
     * DECSTR (`CSI ! p`) is the reset that does not touch the screen. Until -25 it called the same routine as
     * RIS: out of the alternate screen, a whole viewport scrolled into history, cursor home. MSFT's
     * {@code SoftReset} (adaptDispatch.cpp:2984-3020) is a list of assignments with no cursor move, no erase
     * and no buffer switch -- those are HardReset's (:3028-3050, where {@code UseMainScreenBuffer} appears) --
     * and it clears the saved cursor of the *active* buffer only (GH#19918, :3005-3008).
     * <p>
     * Every one of those absences is a leg here, because an absence is exactly what a cell diff cannot see:
     * a reset that scrolled a screen into history and a reset that did not can leave the same rows on screen
     * once the application repaints, and only the rows *above* the viewport remember.
     */
    private static void caseSoftReset() {
        if (!standardGeometry("the DECSTR leg")) return;
        final long[] a = stats(handle);
        paint("a screen, a region and a pen",
                "\u001b[0m\u001b[6;1HKEEP-6\u001b[7;1HKEEP-7\u001b[4;8r\u001b[31;1m");
        paint("save the cursor on row 7, then leave", "\u001b[7;5H\u001b7\u001b[9;3H");
        long[] v = consoleView();
        gate("the cursor is where the test moved it", v[5] == 2 && v[6] == winT + 8,
                "(" + v[5] + "," + v[6] + ") want (2," + (winT + 8) + ")");
        paint("DECSTR", "\u001b[!p");
        v = consoleView();
        gate("and the cursor did not move", v[5] == 2 && v[6] == winT + 8,
                "(" + v[5] + "," + v[6] + ") want (2," + (winT + 8) + ")");
        text("the screen was not erased", winT + 5, 0, "KEEP-6", DEF);
        text("and not scrolled: the row above is where it was", winT + 6, 0, "KEEP-7", DEF);
        paint("DECRC after DECSTR", "\u001b8");
        v = consoleView();
        gate("the saved cursor is gone, so the restore lands where it stands",
                v[5] == 2 && v[6] == winT + 8, "(" + v[5] + "," + v[6] + ") want (2," + (winT + 8)
                        + "): row 7 column 5 is the answer a reset that kept the save would give");
        /* The control for that leg: if DECRC were simply broken, the assertion above would pass for the wrong
           reason. Save from a third place and ask for it back. */
        paint("a save and a restore that must still work", "\u001b[11;2H\u001b7\u001b[12;7H\u001b8");
        v = consoleView();
        gate("DECRC still moves after a soft reset", v[5] == 1 && v[6] == winT + 10,
                "(" + v[5] + "," + v[6] + ") want (1," + (winT + 10) + ")");
        paint("the pen is what a soft reset does drop", "\u001b[13;1HR");
        cell("red and bold are gone, so R is the default attribute", winT + 12, 0, 'R', DEF);
        final long[] mid = stats(handle);
        gate("DECSTR moved no census family", mid[S_UN] - a[S_UN] == 0,
                "unrecognised=" + (mid[S_UN] - a[S_UN]));

        /* The buffer switch is the loudest half of the old behaviour, and the alternate screen is the only
           place it can be seen: a reset that left it would put the main screen's rows back under the
           application's feet, and a cell diff on the main screen would never notice. */
        paint("into the alternate screen", "\u001b[?1049h\u001b[6;1HALT");
        text("the alternate screen holds this row", winT + 5, 0, "ALT", DEF);
        cell("and nothing of the main screen", winT + 6, 0, ' ', DEF);
        paint("DECSTR inside it", "\u001b[!p");
        text("a soft reset does not leave the alternate screen", winT + 5, 0, "ALT", DEF);
        cell("and does not bring the main screen's row back", winT + 6, 0, ' ', DEF);
        v = consoleView();
        gate("still no cursor move", v[5] == 3 && v[6] == winT + 5,
                "(" + v[5] + "," + v[6] + ") want (3," + (winT + 5) + ")");
        paint("leave it the normal way", "\u001b[?1049l");
        text("the main screen was there the whole time", winT + 5, 0, "KEEP-6", DEF);
        final long[] b = stats(handle);
        gate("two alternate-screen switches and both were the test's", b[S_ALT] - a[S_ALT] == 2,
                "alt switches=" + (b[S_ALT] - a[S_ALT]));
        gate("and the reset itself was not counted", b[S_UN] - a[S_UN] == 0,
                "unrecognised=" + (b[S_UN] - a[S_UN]) + ": `CSI !p` is a modelled sequence now");
        paint("clear the band", "\u001b[r\u001b[4;1H\u001b[J");
    }

    /**
     * #74 put every `CSI Ps` that means "how many" behind one named bound, and this is the leg that says the
     * binary on this machine agrees with the struct the host gate links. Two things are worth reading off a
     * real console rather than a unit test. The first is the parameter cap: a sequence that names twenty
     * things acts on the sixteen the model holds, and the loss is now a number the caller can ask for instead
     * of a silence. The second is the delete-line bound, which is a data-loss shape: the count used to be
     * clamped to the window's height instead of the rows below the cursor, and with a cursor two rows into the
     * window `CSI 9999M` erased the rows *above* it and left its own row standing.
     */
    private static void caseArgClamp() {
        if (!standardGeometry("the parameter-bound leg")) return;
        final long[] a = stats(handle);
        gate("nothing was truncated when this model opened", argTrunc(handle) == 0,
                "count=" + argTrunc(handle));

        final StringBuilder wide = new StringBuilder("\u001b[");
        for (int i = 1; i <= 20; i++) wide.append(i).append(i == 20 ? "H" : ";");
        paint("a CUP that names twenty parameters", wide.toString());
        long[] v = consoleView();
        gate("the first two are the ones it acted on", v[5] == 1 && v[6] == winT,
                "(" + v[5] + "," + v[6] + ") want (1," + winT + "): row 1, column 2");
        gate("and four parameters had nowhere to go", argTrunc(handle) == 4,
                "count=" + argTrunc(handle) + " want 4: the list holds sixteen (ConEmu's ArgV, Ansi.h:174)");
        paint("a list that fits", "\u001b[2;3H");
        gate("adds nothing to the count", argTrunc(handle) == 4,
                "count=" + argTrunc(handle) + ": it counts lost arguments, not sequences");
        v = consoleView();
        gate("and that CUP still moved the cursor", v[5] == 2 && v[6] == winT + 1,
                "(" + v[5] + "," + v[6] + ") want (2," + (winT + 1) + ")");

        paint("five labelled rows", "\u001b[1;1HDL-1\u001b[2;1HDL-2\u001b[3;1HDL-3\u001b[4;1HDL-4\u001b[5;1HDL-5");
        paint("delete more rows than there are below the cursor", "\u001b[3;1H\u001b[9999M");
        v = consoleView();
        gate("the cursor stays on the row it deleted from", v[6] == winT + 2,
                "row=" + v[6] + " want " + (winT + 2));
        text("the row above the cursor kept its text", winT, 0, "DL-1", DEF);
        text("and so did the one above that", winT + 1, 0, "DL-2", DEF);
        span("the cursor's own row is the first thing erased", winT + 2, 0, 3, ' ', DEF);
        /* Nothing "comes up" here, and that is the answer rather than a gap: a delete of more rows than the
           model has below the cursor empties that band, exactly as a delete of two leaves the third where the
           second was. The ordinary case is `caseEditRows`'s witness; this one is about the reach. */
        span("and every row below it went with it", winT + 3, 0, 3, ' ', DEF);
        span("including the window's last", winT + 4, 0, 3, ' ', DEF);
        final long[] b = stats(handle);
        gate("none of it was counted as unsupported", b[S_UN] - a[S_UN] == 0,
                "unrecognised=" + (b[S_UN] - a[S_UN]) + ": IL, DL and a long CUP are all modelled");
        gate("and nothing was declined", b[2] - a[2] == 0, "declines=" + (b[2] - a[2]));
        paint("leave the rows clean", "\u001b[1;1H\u001b[J");
    }

    /**
     * The tab table, off the shipping binary. The host gate links `Render.cpp` and can look at the array
     * directly; what this case adds is that the bytes a caller sends land where the array says, on a real
     * console, and -- the part no unit test can reach -- that a rebuild carries the table with it. `readopt`
     * is the recovery a resize takes (RenderJni.cpp's build_model), and the stops are application-set state,
     * so a resize that lost them would be a resize that answered a sequence nobody sent.
     */
    /* One trap this case already fell into: `ESC H` is HTS and takes no bracket, while `ESC [ H` is
       CUP. The console answers a mistaken bracket with column 0, which is a wrong answer to a
       different question -- and it is why the tab rules are run against a real console and not only
       against the struct the host gate links. */
    private static void caseTabStops() {
        if (!standardGeometry("the tab-stop leg")) return;
        paint("a claimed stop at column 3", "\u001b[1;4H\u001bH");
        long[] v = consoleView();
        gate("and HTS (no bracket) moves nothing", v[5] == 3 && v[6] == winT,
                "(" + v[5] + "," + v[6] + ") want (3," + winT + ")");
        paint("a tab from the margin", "\u001b[1;1H\t");
        v = consoleView();
        gate("finds the claimed column, not the eighth", v[5] == 3,
                "col=" + v[5] + " want 3: `\\t` walked a table, and the arithmetic it replaced would say 8");
        paint("one more goes on to the default interval", "\t");
        v = consoleView();
        gate("the defaults are still under it", v[5] == 8, "col=" + v[5] + " want 8");
        paint("and a back-tab comes back to the claim", "\u001b[Z");
        v = consoleView();
        gate("CBT backs up to the stop the application set", v[5] == 3, "col=" + v[5] + " want 3");

        paint("clear every stop", "\u001b[3g");
        paint("then tab from column 0", "\u001b[1;1H\t");
        final long first = consoleView()[5];
        paint("and again", "\t");
        final long second = consoleView()[5];
        gate("with nothing to run to, a tab ends at the wall", first == second && first != 3,
                "col=" + first + " then " + second + ": it must not sit still *at* the claim, and must not move");

        /* The carry. Claim a stop, rebuild the model the way a resize does, and ask the same question. */
        paint("claim it again", "\u001b[5g\u001b[1;4H\u001bH");
        paint("tab there", "\u001b[1;1H\t");
        gate("setup: the stop is in use", consoleView()[5] == 3, "col=" + consoleView()[5]);
        gate("the rebuild is accepted", readopt(handle) == 1, "readopt refused");
        paint("tab after the rebuild", "\u001b[1;1H\t");
        v = consoleView();
        gate("the stop survived its own resize", v[5] == 3,
                "col=" + v[5] + " want 3: a resize is not a reset, and the table is a claim");
        paint("and the interval it did not claim is still there", "\u001b[1;10H\t");
        v = consoleView();
        gate("from column 9 a tab reaches 16, which nobody set", v[5] == 16, "col=" + v[5] + " want 16");
        paint("leave the window where the next case expects it", "\u001b[1;1H");
    }

    /**
     * The colon sub-parameters (#78, I41) on a real console. The host gate can compare the two spellings'
     * folded attributes; only the screen can say the colour the sender was holding actually arrived, and the
     * fallback leg is the other half of that claim: what ConEmu's parser does with the same bytes.
     */
    private static void caseColon() {
        if (!standardGeometry("the colon-form leg")) return;
        final long[] a = stats(handle);
        paint("the semicolon form paints a truecolour foreground", "\u001b[20;1H\u001b[38;2;200;40;10mA");
        final int semi = cellAttr(winT + 19, 0);
        gate("and something arrived to be compared", semi != DEF,
                "attr=0x" + Integer.toHexString(semi));
        paint("the colon form, same colour", "\u001b[20;1H\u001b[38:2:200:40:10mB");
        cell("B stands on the same colour the semicolon form put there", winT + 19, 0, 'B', semi);
        paint("and the form with the deprecated colour-space slot left empty",
                "\u001b[20;1H\u001b[38:2::200:40:10mC");
        cell("is the same colour a third time", winT + 19, 0, 'C', semi);
        paint("an indexed colon colour", "\u001b[20;1H\u001b[38:5:196mD");
        final int idx = cellAttr(winT + 19, 0);
        gate("is not the truecolour one", idx != semi, "attr=0x" + Integer.toHexString(idx));
        paint("4:3 asks for a curly underline", "\u001b[20;1H\u001b[4:3mE");
        cell("the underscore it can draw arrives", winT + 19, 0, 'E', idx | 0x8000);
        paint("and 4:0 takes it away", "\u001b[20;1H\u001b[4:0mF");
        cell("F stands on no underline", winT + 19, 0, 'F', idx);
        final long[] b = stats(handle);
        gate("the refused arms are counted, the carried ones not", b[S_COLON] - a[S_COLON] == 1,
                "colon votes=" + (b[S_COLON] - a[S_COLON]) + " (only the curly style)");
        paint("clear the band", "\u001b[20;1H\u001b[J\u001b[1;1H");
    }

    /**
     * The window operations (#79, I42) where the witness has to be the console: the reply <em>bytes</em> are
     * built in the seam (<i>reply_text</i> in RenderJni.cpp), which a host test links but cannot reach, and the
     * title a pop restores is a window property rather than a cell. Both are the kind of claim that goes quiet
     * if nobody reads the input queue and the title bar back.
     */
    private static void caseWindowOps() {
        if (!standardGeometry("the window-op leg")) return;
        final long[] a = stats(handle);

        readInput(0);                                   /* the reply below is the only thing in this queue */
        paint("18t asks for the text area", "\u001b[18t");
        final String rep = input(64);
        final String want = "\u001b[8;" + WIN_H + ";" + BUF_W + "t";
        gate("the answer is the viewport in characters, prefixed 8 as MSFT's function-10 does",
                rep.contains(want), "got=" + vis(rep) + " want " + vis(want)
                        + ": rows are the window's own and columns are the model row's width (I7)");

        readInput(0);
        paint("19t asks for a second geometry", "\u001b[19t");
        paint("14t and 16t ask for pixels", "\u001b[14t\u001b[16t");
        final String none = input(64);
        gate("and all three are left unanswered", none.isEmpty() || "<unreadable>".equals(none),
                "read back " + vis(none) + " -- silence is the answer that cannot be wrong (DESIGN I42)");
        final long[] b = stats(handle);
        gate("with every one of them counted", b[S_UN + 9] - a[S_UN + 9] == 3,
                "report=" + (b[S_UN + 9] - a[S_UN + 9]) + ": the census is how a rollout learns anyone asked");

        /* The title stack, on the real window title. */
        paint("a title", "\u001b]0;native-A\u0007");
        gate("the console took it", "native-A".equals(title()), "read back " + title());
        paint("push it, then take a second title", "\u001b[22;0t\u001b]0;native-B\u0007");
        gate("B is the window's title now", "native-B".equals(title()), "read back " + title());
        paint("and pop", "\u001b[23;0t");
        gate("A comes back through the same SetConsoleTitleW an OSC 0 uses",
                "native-A".equals(title()), "read back " + title());
        final long[] c = stats(handle);
        gate("which is two more title calls, not a side channel",
                c[S_TITLES + 2] - b[S_TITLES + 2] >= 2,
                "titleCalls=" + (c[S_TITLES + 2] - b[S_TITLES + 2])
                        + ": the restore goes through the same sink an OSC 0 does, so the two paths cannot drift");
        paint("a pop with nothing saved", "\u001b[23;0t");
        gate("leaves the title alone", "native-A".equals(title()),
                "read back " + title() + ": the console's own earlier title is not this library's to invent");
    }

    /**
     * IRM (#77, I40) on the screen rather than in the struct. The host gate can already read the model's
     * cells; what only a console can answer is whether the text the model pushed right *arrived* there, and
     * whether the mode survived the rebuild a resize performs -- `readopt` is the path production takes and a
     * gate that cannot reach it would pass while every resize silently dropped the mode.
     */
    private static void caseInsert() {
        if (!standardGeometry("the insert-mode leg")) return;
        final long[] a = stats(handle);
        paint("a row of text", "\u001b[10;1HABCDEFGH");
        paint("IRM on, home to column 5, write one glyph", "\u001b[?4h\u001b[10;5HZ");
        cell("the glyph stands where the cursor was", winT + 9, 4, 'Z', DEF);
        cell("and E, which the write displaced, is one column right of it", winT + 9, 5, 'E', DEF);
        cell("with the rest of the row riding along", winT + 9, 7, 'G', DEF);
        paint("IRM off: the next cell is overwritten, not pushed", "\u001b[?4lY");
        cell("Y took the column under the cursor", winT + 9, 5, 'Y', DEF);
        cell("and what stood there moved nobody", winT + 9, 6, 'F', DEF);

        /* The carry. Restate the row, arm the mode, rebuild the model the way a resize does, and ask the same
           question again. (The first version of this leg left the mode disarmed from the assertion above and
           then passed a green console to a red expectation -- the model was right, the leg was wrong, and it
           is the same mistake §10's -28 row records from the other side.) */
        paint("restate it, arm the mode, home the cursor", "\u001b[10;1HABCDEFGH\u001b[?4h\u001b[10;5H");
        gate("the rebuild is accepted", readopt(handle) == 1, "readopt refused");
        paint("one glyph, with nobody having re-armed the mode", "X");
        cell("X is at the cursor", winT + 9, 4, 'X', DEF);
        cell("and E is still beside it", winT + 9, 5, 'E', DEF);
        cell("because a resize is not a reset: the mode is terminal state, carried like DECAWM and the tabs",
                winT + 9, 6, 'F', DEF);
        paint("RIS puts replace mode back", "\u001bc");
        paint("restate the row and write at column 5", "\u001b[10;1HABCDEFGH\u001b[10;5HW");
        cell("W overwrote E instead of pushing it", winT + 9, 4, 'W', DEF);
        cell("and F did not move", winT + 9, 5, 'F', DEF);
        final long[] b = stats(handle);
        gate("none of it was counted as unknown", b[S_UN] - a[S_UN] == 0,
                "unrecognised=" + (b[S_UN] - a[S_UN]));
        paint("leave the band clear for the next leg", "\u001b[10;1H\u001b[J\u001b[1;1H");
    }

    // ---- both legs, one console ----------------------------------------------------------------
    /*
     * The parity promise in one process. Production compares legs by running a whole session of the application twice
     * (cache\jnatest\native-ab.ps1), which is the honest witness for a real workload but answers one
     * question per run and needs a command that can emit the bytes. Here the same bytes go to the model and
     * to ConEmuHk's WriteProcessed3 two rows apart on the same console, and the two cell reads are diffed
     * directly -- which is how "does a backspace stop inside a wide glyph", "what does a scroll region do
     * to replayed output" and "where does a line that fills a buffer row wrap" get settled in seconds,
     * with the numbers written down either way.
     *
     * A case that expects disagreement is as pinned as one that expects agreement: the gate fails when an
     * accepted divergence disappears, because the day it stops diverging is the day DESIGN \u00a74.1 goes stale
     * and nobody else would notice.
     */
    private static final int AB_A = 10, AB_B = 14;   /* window rows: the model's, then the fallback leg's */
    private static final int AB_ROWS = 3;            /* a band: a wrapped case writes the row below */

    private static void caseLegsAgree() {
        String dll = System.getProperty("hk");
        if (dll == null || dll.isEmpty()) dll = System.getenv("DBCLI_HK");
        if (dll == null || dll.isEmpty()) {
            System.out.println("  SKIP both-leg A/B: no ConEmuHk named (-Dhk=<path> or DBCLI_HK). The"
                    + " fallback leg's answers are then unmeasured, not agreed.");
            return;
        }
        if (!(new java.io.File(dll).isFile())) {
            gate("the ConEmuHk named for the A/B exists", false, dll);
            return;
        }
        System.out.println("  both-leg A/B against " + dll);

        /* Where a backspace stops when the cell behind the cursor is the trailing half of a glyph.
         * Probe.java measured conhost for the same units and it steps the whole glyph (cursor 2 -> 0) and
         * then clears the orphaned partner; ConEmuHk has no backspace handling of its own, so the
         * fallback leg is that answer. A model that steps one column leaves a leading half on screen. */
        legs("wide glyph then BS", "\u3042\b_", Boolean.TRUE, dll);
        legs("wide glyph then two BS", "\u3042\b\b_", Boolean.TRUE, dll);
        /* One of the four BS cases survives as a divergence, and the fallback leg is the wrong side of it.
         * "\u3042a\b_": the model parks the cursor on column 3, steps back to 2 (not a trailer) and overwrites
         * the 'a'. ConEmuHk lands on column 1 and blanks column 0, which is its own counting error rather
         * than a rule the model could copy -- it tracks a wide glyph as one column, so after "wide + narrow"
         * it believes the cursor is one column left of where conhost put it, moves back from there, and
         * writing into a trailing cell makes conhost clear the leading half (CONEMU_ANSI_DEFECTS #852 family:
         * "把格数当成了字符数"). The native [3042L 3042T 005F] vs hk [0020 005F 0061] is the measurement.
         * Accepted because matching it would mean storing a wrong cursor. */
        legs("narrow after wide, then BS", "\u3042a\b_", Boolean.FALSE, dll);
        legs("narrow after wide, then two BS", "\u3042a\b\b_", Boolean.TRUE, dll);
        legs("wide then BS then wide", "\u3042\b\u4e2d", Boolean.TRUE, dll);
        legs("BS at the start of a row", "\bX", Boolean.TRUE, dll);
        legs("tab after a wide glyph", "\u3042\tX", Boolean.TRUE, dll);
        /* An astral code point: two UTF-16 units, one 2-column cell pair. Measured 2026-09-23, the legs
         * store it differently -- native [D83DL D83DT 0058] against hk [FFFDL FFFDT 0058] -- with identical
         * attributes and identical columns. Both agree that the character does not survive: a legacy cell
         * holds one WCHAR, so the model's leading/trailing pair can carry only the high half, and the
         * fallback leg hands the pair to WriteConsoleW and gets U+FFFD twice. The readback cannot say what
         * either leg stored in the trailing cell, because conhost repeats the leading WCHAR there for every
         * 2-column glyph (the CJK cases above show [3042L 3042T]) -- MSFT_TERMINAL_REFERENCE \u00a75 is exactly
         * this contract. Accepted, and the model keeps the raw halves rather than adopting the replacement:
         * a console generation that composes pairs would then have the character, and one that does not
         * shows a box either way. */
        legs("astral pair", "\uD83D\uDE00X", Boolean.FALSE, dll);

        /* The four shapes that tell an immediate wrap from a pending one (MSFT_TERMINAL_REFERENCE \u00a72.2):
         * a line that exactly fills a buffer row, then something that a pending wrap would undo. */
        String full = line(BUF_W);
        legs("full row then CR then Y", full + "\rY", Boolean.TRUE, dll);
        legs("full row then BS then Y", full + "\bY", Boolean.TRUE, dll);
        legs("full row then EL", full + "\u001b[K", Boolean.TRUE, dll);
        legs("full row then CUU then Y", full + "\u001b[A" + "Y", Boolean.TRUE, dll);

        /* DECSTBM, now modelled (I25): a region narrower than the viewport is what the two legs used to be
         * allowed to disagree about, and this case was written to measure that. It reports agreement now,
         * which is the parity claim -- filler on every region row, then an LF at the region bottom: both
         * legs roll the region and leave the row under it holding what it held. The row below is the one
         * Status.java depends on: a pinned bottom line survives a pinned region's scroll.
         *
         * This case runs both legs over the SAME rows, which the two-bands-side-by-side helper cannot do:
         * the region the bytes name is window rows 2..4 wherever the bands sit, so a second band would put
         * the fallback leg's scroll outside the region and the comparison would read two rows of blanks and
         * report agreement (it did, on the first run of this case). */
        legsSame("DECSTBM then a scroll",
                "\u001b[2;4r" + "AAAA\u001b[B" + "BBBB\u001b[B" + "CCCC\n", Boolean.TRUE, dll, 1);
        /* DECAWM off is modelled now (I35), and this is the one pair of legs that must NOT agree. ConEmu's
         * own `?7` arm leaves the SetConsoleMode commented out (Ansi.cpp:3268-3281) and hands the text to
         * WriteConsoleW, where the console's ENABLE_WRAP_AT_EOL is still on: the character past the margin
         * opens a row there and overwrites the last column here. Accepted because matching the fallback leg
         * would mean ignoring a mode both reference terminals act on. The product's own dictionary defines
         * WRAP/UNWRAP (`lua/ansi.lua`) with its call sites commented out, so this is the third-party case --
         * an editor or a progress line drawn through this library -- and not a dbcli behaviour. */
        /* The `?7h` is part of the case, not a courtesy: one grid serves every leg of this run, so a mode
         * left off here would quietly un-wrap caseWrap and everything after it -- which is what the first
         * run of this case did, failing two assertions three cases later. */
        legs("DECAWM off at the margin", "\u001b[?7l" + line(BUF_W) + "Q\u001b[?7h", Boolean.FALSE, dll);
    }

    /** A row of `n` distinguishable columns, so a one-column shift between the legs is visible. */
    private static String line(int n) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < n; i++) sb.append((char) ('A' + i % 26));
        return sb.toString();
    }

    /**
     * Bytes through the model on row AB_A and through the fallback leg on row AB_B, both bands cleaned
     * first through the model so they start identical. `expect` is TRUE (cells must agree), FALSE (they
     * must differ, an accepted divergence) or null (report only, while a question is still open).
     */
    private static void legs(String what, String bytes, Boolean expect, String dll) {
        for (int k = 0; k < AB_ROWS; k++) {
            gotoRow(AB_A + k);
            paint("clean native row", "\u001b[0m\u001b[K");
            gotoRow(AB_B + k);
            paint("clean hk row", "\u001b[0m\u001b[K");
        }
        char[] c = bytes.toCharArray();

        gotoRow(AB_A);
        paint(what + " (native)", bytes);
        long[] afterNative = consoleView();
        long[][] rowsA = new long[AB_ROWS][];
        for (int k = 0; k < AB_ROWS; k++) rowsA[k] = row(winT + AB_A + k);

        gotoRow(AB_B);
        int n = writeHk(c, c.length, dll);
        if (n < 0) {
            gate(what + ": the fallback leg ran", false, "writeHk=" + hkError(n));
            return;
        }
        long[] afterHk = consoleView();
        long[][] rowsB = new long[AB_ROWS][];
        for (int k = 0; k < AB_ROWS; k++) rowsB[k] = row(winT + AB_B + k);

        String diff = null;
        for (int k = 0; k < AB_ROWS && diff == null; k++) {
            long[] x = rowsA[k], y = rowsB[k];
            if (x == null || y == null) { diff = "row " + k + " unreadable"; break; }
            for (int col = 0; col < x.length && col < y.length; col++) {
                if (x[col] == y[col]) continue;
                diff = "first at row +" + k + " col " + col + ": native U+" + hex((int) (x[col] & 0xFFFF))
                        + "/0x" + hex((int) ((x[col] >>> 16) & 0xFFFF)) + " vs hk U+"
                        + hex((int) (y[col] & 0xFFFF)) + "/0x" + hex((int) ((y[col] >>> 16) & 0xFFFF))
                        + " | native [" + dump(x) + "] hk [" + dump(y) + "]";
                break;
            }
        }
        String detail = "bytes=" + c.length + " hkConsumed=" + n
                + " cursorNative=" + afterNative[5] + "," + afterNative[6]
                + " cursorHk=" + afterHk[5] + "," + afterHk[6]
                + " | " + (diff == null ? "cells agree" : diff);
        if (expect == null) {
            System.out.println("  OBSERVE " + what + ": " + detail);
            return;
        }
        gate(what + (expect.booleanValue() ? ": legs agree" : ": legs differ as documented"),
             expect.booleanValue() == (diff == null), detail);
        /* The cursor is not part of the verdict: the model parks it at the window's right column when the
         * line has run past it (caseWrap), which is a deliberate difference in what the *user sees*, not
         * in what is stored. A case that disagrees about cells disagrees about columns too. */
    }

    /**
     * The same comparison for bytes that name absolute window rows, where both legs have to run over one
     * band. Native first, read, clean, then the fallback leg, read, clean; the band is blank between the
     * two so each leg starts from the same frame. `base` is a 0-based window row, so a CSI address inside
     * `bytes` and the rows read agree with each other.
     *
     * <p>The region is reset on both legs afterwards. ConEmuHk keeps ANSI state per process and a region
     * still set would clamp every later case's cursor movement on that leg; the model keeps it in its grid
     * for the same reason, so since DECSTBM became a modelled region the native leg needs the same reset --
     * otherwise the rest of the run scrolls a region nobody asked for.
     */
    private static void legsSame(String what, String bytes, Boolean expect, String dll, int base) {
        char[] c = bytes.toCharArray();
        char[] reset = "\u001b[r".toCharArray();

        cleanBand(base);
        gotoRow(base);
        paint(what + " (native)", bytes);
        long[][] rowsA = new long[AB_ROWS][];
        for (int k = 0; k < AB_ROWS; k++) rowsA[k] = row(winT + base + k);
        paint(what + " (region reset)", "\u001b[r");

        cleanBand(base);
        gotoRow(base);
        int n = writeHk(c, c.length, dll);
        if (n < 0) {
            gate(what + ": the fallback leg ran", false, "writeHk=" + hkError(n));
            return;
        }
        long[][] rowsB = new long[AB_ROWS][];
        for (int k = 0; k < AB_ROWS; k++) rowsB[k] = row(winT + base + k);
        writeHk(reset, reset.length, dll);
        cleanBand(base);

        String diff = null;
        for (int k = 0; k < AB_ROWS && diff == null; k++) {
            long[] x = rowsA[k], y = rowsB[k];
            if (x == null || y == null) { diff = "row " + k + " unreadable"; break; }
            for (int col = 0; col < x.length && col < y.length; col++) {
                if (x[col] == y[col]) continue;
                diff = "first at region row +" + k + " col " + col + ": native U+"
                        + hex((int) (x[col] & 0xFFFF)) + "/0x" + hex((int) ((x[col] >>> 16) & 0xFFFF))
                        + " vs hk U+" + hex((int) (y[col] & 0xFFFF)) + "/0x"
                        + hex((int) ((y[col] >>> 16) & 0xFFFF))
                        + " | native [" + dump(x) + "] hk [" + dump(y) + "]";
                break;
            }
        }
        gate(what + (expect.booleanValue() ? ": legs agree" : ": legs differ as documented"),
             expect.booleanValue() == (diff == null),
             "bytes=" + c.length + " hkConsumed=" + n + " | " + (diff == null ? "cells agree" : diff));
    }

    /** Blank one band of rows through the model, so both legs start from the same frame. */
    private static void cleanBand(int base) {
        for (int k = 0; k < AB_ROWS; k++) {
            gotoRow(base + k);
            paint("clean row " + k, "\u001b[0m\u001b[K");
        }
    }

    /**
     * The first columns of a leg's row, for a failure line. Naming only the first differing cell was
     * enough to prove the legs differ and not enough to say what the other leg would have to do about it:
     * a wide-glyph case turns on whether cell 1 still claims to be part of the glyph in cell 0.
     */
    /** The first cells of a row as text, unreadables as dots: what a scrollback diff has to show to be
     *  readable at all. */
    private static String head(long[] r) {
        StringBuilder sb = new StringBuilder();
        for (int c = 0; c < r.length && c < 26; c++) {
            int ch = (int) (r[c] & 0xFFFF);
            sb.append(ch >= 0x20 && ch < 0x7f ? (char) ch : '.');
        }
        return sb.toString();
    }

    /**
     * How many rows of [from, to) read differently than the snapshot taken at `was` (indexed from `from`),
     * naming the first few in `why` when `why` is not null. A diff that counts without saying which rows
     * moved is a witness that cannot be read: whether the damage is one row or the whole window, and whether
     * the rows moved by one or were overwritten in place, are three different bugs with the same count.
     */
    private static int diffRows(long[][] was, int from, int to, StringBuilder why) {
        int changed = 0, shown = 0;
        for (int r = from; r < to; r++) {
            long[] now = row(r), old = was[r - from];
            boolean diff = now == null || old == null || now.length != old.length;
            for (int c = 0; now != null && old != null && !diff && c < now.length; c++) {
                diff = now[c] != old[c];
            }
            if (!diff) continue;
            changed++;
            if (why != null && shown++ < 6) {
                why.append(" r").append(r).append("[").append(old == null ? "?" : head(old))
                        .append("->").append(now == null ? "?" : head(now)).append("]");
            }
        }
        return changed;
    }

    /** The first buffer row in [from, to) whose line starts with `s`, or -1. Rows are searched rather than
     *  named because which row the model writes to is the plan's business -- which side of its anchor the
     *  answer lands on is the whole of what these cases assert. */
    private static int findRow(String s, int from, int to) {
        for (int r = from; r < to; r++) {
            long[] now = row(r);
            if (now == null || now.length < s.length()) continue;
            boolean hit = true;
            for (int c = 0; c < s.length(); c++) {
                if ((int) (now[c] & 0xFFFF) != s.charAt(c)) { hit = false; break; }
            }
            if (hit) return r;
        }
        return -1;
    }

    private static String dump(long[] r) {
        StringBuilder sb = new StringBuilder();
        for (int c = 0; c < r.length && c < 8; c++) {
            if (c != 0) sb.append(' ');
            sb.append(hex((int) (r[c] & 0xFFFF)));
            int attr = (int) ((r[c] >>> 16) & 0xFFFF);
            if ((attr & 0x0100) != 0) sb.append('L');
            if ((attr & 0x0200) != 0) sb.append('T');
        }
        return sb.toString();
    }

    private static String hex(int v) {
        return String.format("%04X", Integer.valueOf(v));
    }

    /** Why the fallback leg could not be reached at all; negative returns from writeHk. */
    private static String hkError(int n) {
        switch (n) {
            case -1: return "no path or no text";
            case -2: return "LoadLibrary failed";
            case -3: return "no WriteProcessed3 export";
            case -4: return "the bytes could not be read";
            case -5: return "CONOUT$ could not be opened";
            case -6: return "WriteProcessed3 refused the write";
            default: return "code " + n;
        }
    }

    /**
     * Where a line breaks. The window's right edge is not a wrap point: conhost moves to the next row
     * when the last *buffer* column is filled, so 105 columns of text -- a `select * from v$session`
     * wider than the window -- stay on one row and are simply off screen until the user scrolls right.
     * Measured 2026-09-23 by Probe.java: 150 units written raw into a 100-column window of a 200-column
     * buffer land at columns 0..149 of that one row, the cursor ends at column 150, srWindow unmoved.
     *
     * The cursor is the one thing that must not follow: conhost slides the viewport sideways to include a
     * cursor it is told about, and parking at column 105 of this window was measured (same day) to move
     * srWindow to 6..105 -- 300 in a 120-column window moved it to 181..300. So the painter parks the
     * console's cursor at the window's last column while the model keeps the real one, and the next chunk
     * still continues where the line actually is. A wide table row must not drag the user's view right.
     */
    private static void caseWrap() {
        gotoRow(6);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < BUF_W; i++) sb.append((char) ('A' + i % 26));
        paint("wrap", sb.substring(0, 105));
        long[] r = row(winT + 6);
        boolean ok = r != null;
        for (int i = 0; ok && i < 105; i++)
            ok = (int) (r[i] & 0xFFFF) == 'A' + i % 26 && (int) ((r[i] >>> 16) & 0xFFFF) == DEF;
        gate("105 columns are one row, not a row and a fifth", ok, "row " + (winT + 6));
        cell("the row has blanks of its own past the text", winT + 6, 105, ' ', DEF);
        long[] v = consoleView();
        long[] s = stats(handle);
        gate("the console cursor stays inside the window", v[5] == WIN_W - 1 && v[6] == winT + 6,
                "(" + v[5] + "," + v[6] + ") winT=" + winT);
        gate("so the window did not slide after it", v[1] == 0, "winL=" + v[1]);
        gate("while the model still knows the line is at 105", s[10] == 105, "cx=" + s[10]);

        paint("fill the buffer row", sb.substring(105));
        r = row(winT + 6);
        ok = r != null;
        for (int i = 105; ok && i < BUF_W; i++)
            ok = (int) (r[i] & 0xFFFF) == 'A' + i % 26 && (int) ((r[i] >>> 16) & 0xFFFF) == DEF;
        gate("column 199 is a cell like any other", ok, "row " + (winT + 6));
        v = consoleView();
        gate("filling the last column wraps at once", v[5] == 0 && v[6] == winT + 7,
                "(" + v[5] + "," + v[6] + ") winT=" + winT);
        paint("one past the buffer row", "Z");
        cell("so the next character starts the next row", winT + 7, 0, 'Z', DEF);
        span("and that row is blank to the buffer edge", winT + 7, 1, BUF_W - 1, ' ', DEF);
    }

    /**
     * I35: DECAWM off, on a real console. The host gate can prove the model refuses to wrap; only this leg
     * shows the screen holding still with it -- the buffer row's last column carries the last of three
     * overwrites, the row under it never started, and the console cursor is parked at the window's right
     * edge while the model keeps the column it really means. A renderer that clamped its own grid and left
     * conhost's cursor a row down would paint the next chunk into a row the model says does not exist, which
     * is the split this library's whole design exists to refuse.
     */
    private static void caseDecawm() {
        /* Both rows are cleaned through the renderer first. caseWrap, which runs just above, leaves a 'Z'
           at the first column of the row below its own -- precisely where "nothing wrapped" has to be read,
           and the first run of this case failed on that leftover rather than on anything it sent. */
        gotoRow(6);
        paint("decawm clean head", "\u001b[K");
        gotoRow(7);
        paint("decawm clean tail", "\u001b[K");
        gotoRow(6);
        final String fill = line(BUF_W);
        paint("decawm off", "\u001b[?7l" + fill + "XYZ");
        long[] r = row(winT + 6);
        boolean ok = r != null;
        for (int i = 0; ok && i < BUF_W - 1; i++)
            ok = (int) (r[i] & 0xFFFF) == fill.charAt(i) && (int) ((r[i] >>> 16) & 0xFFFF) == DEF;
        gate("the row holds everything up to the margin", ok, "row " + (winT + 6));
        cell("and the margin holds the last of three overwrites", winT + 6, BUF_W - 1, 'Z', DEF);
        cell("the row below never started", winT + 7, 0, ' ', DEF);
        long[] v = consoleView();
        gate("the console cursor stays inside the window", v[5] == WIN_W - 1 && v[6] == winT + 6,
                "(" + v[5] + "," + v[6] + ") winT=" + winT);
        gate("so the window did not slide after it", v[1] == 0, "winL=" + v[1]);
        long[] s = stats(handle);
        gate("while the model still knows the line is at the buffer's last column",
                s[10] == BUF_W - 1, "cx=" + s[10]);

        /* DECSET 7 resumes the wrap from the next character. The fill is immediate and not pending, so the
           character that reaches the margin is drawn there and only the one after it opens a row -- the
           same four-discriminator fact I22 pins for the wrap-on case. */
        paint("decawm on", "\u001b[?7hA");
        cell("the overwrite lands in the margin", winT + 6, BUF_W - 1, 'A', DEF);
        v = consoleView();
        gate("and the cursor wrapped", v[5] == 0 && v[6] == winT + 7,
                "(" + v[5] + "," + v[6] + ") winT=" + winT);
        paint("decawm after wrap", "B");
        cell("the next character starts the row", winT + 7, 0, 'B', DEF);
        span("and that row is blank to the buffer edge", winT + 7, 1, BUF_W - 1, ' ', DEF);

        gotoRow(6);
        paint("decawm restore row", "\u001b[K");
        gotoRow(7);
        paint("decawm restore tail", "\u001b[K");
    }

    /**
     * The newline the application actually sends: JLine hands over "\n" with no CR, and conhost folds the column
     * for it (stage 0 measures this -- Probe writes "ab\ncd" raw and 'c' lands at column 0). Keeping the
     * column here is what made a live `help` list walk one column left per row.
     */
    private static void caseBareLf() {
        gotoRow(10);
        paint("bare lf", "ab\ncd\nef");
        text("bare lf row 0", winT + 10, 0, "ab", DEF);
        text("bare lf row 1", winT + 11, 0, "cd", DEF);
        text("bare lf row 2", winT + 12, 0, "ef", DEF);
        tail("bare lf last row", winT + 12, 2, DEF);
    }

    /**
     * A repaint narrower than the previous one. Two things are pinned here, and they pull in opposite
     * directions, so the case is worth having: text the previous frame wrote and this one did not erase
     * STAYS (no EL was sent, and the model still holds it -- erasing it would be the painter inventing
     * an edit), while the blank tail past the previous frame's last column must not take on the
     * colour that frame was written in.
     */
    private static void caseNarrowRepaint() {
        gotoRow(8);
        StringBuilder sb = new StringBuilder("\u001b[43m");
        for (int i = 0; i < 60; i++) sb.append('Y');
        sb.append("\u001b[0m");
        paint("long frame", sb.toString());
        /* 43m folds to bg 6 on a legacy console, so the yellow row is attribute 0x67 */
        text("long frame", winT + 8, 0, "YYYYYYYYYYYY", 0x67);
        tail("long frame untouched tail", winT + 8, 60, DEF);
        gotoRow(8);
        paint("short frame", "AB");
        text("short frame", winT + 8, 0, "AB", DEF);
        text("short frame leaves the old text", winT + 8, 2,
                "YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY", 0x67);
        tail("short frame tail is not yellow", winT + 8, 60, DEF);

        /*
         * B2, inside the window: a repaint one column wide in the middle of a row that is already on
         * screen. The rectangle's left edge is now `winL + the damage's first column` and its width is the
         * damage, so the two ways of getting it wrong are both visible here -- a column taken from the row
         * instead of from the damage resets the yellow on either side of the Z, and an offset that is off
         * by the window's left edge paints the Z somewhere else and leaves a Y where it was asked for.
         */
        paint("one column in the middle", "\u001b[31GZ");
        cell("mid-column rewrite", winT + 8, 30, 'Z', DEF);
        cell("the yellow left of it stayed", winT + 8, 29, 'Y', 0x67);
        cell("and the yellow right of it", winT + 8, 31, 'Y', 0x67);
        text("so the row is intact either side", winT + 8, 32, "YYYYYYYYYYYY", 0x67);
    }

    /**
     * Three lines written from the viewport's last row: the model scrolls twice, and the plan must
     * repair that by sliding the window down (free) rather than repainting the screen. L1 is two rows
     * above L3 in the buffer, which is what a terminal shows.
     */
    private static void caseScroll() {
        int before = winT;
        gotoRow(WIN_H - 1);
        paint("three lines", "L1\r\nL2\r\nL3");
        gate("the viewport moved down two rows", winT == before + 2, "winT " + before + " -> " + winT);
        text("L1", winT + WIN_H - 3, 0, "L1", DEF);
        text("L2", winT + WIN_H - 2, 0, "L2", DEF);
        text("L3", winT + WIN_H - 1, 0, "L3", DEF);
        tail("scrolled-in row", winT + WIN_H - 1, 2, DEF);
        long[] s = stats(handle);
        gate("the scrolls were consumed", s[9] == 0, "pendingScrolls=" + s[9]);
        gate("the model counted them", s[6] >= 2, "scrolls=" + s[6]);
    }

    /**
     * The gutter's whole reason for existing: one chunk of 95 lines through a 30-row window. Without
     * the unpainted rows above the viewport, the chunk's first 65 lines would be shifted out of the
     * model before anything painted them, and the buffer would keep blanks where ConEmu leaves text --
     * the failure the shipped writer had when a dashboard frame ran off the bottom.
     *
     * The witness is continuity: every label from L1 to L95 must occupy its own consecutive buffer row,
     * L1 far above the window's new top. A single lost line shows up as a jump.
     */
    private static void caseManyScreens() {
        int before = winT;
        gotoRow(0);
        StringBuilder sb = new StringBuilder();
        for (int i = 1; i <= 95; i++) sb.append(String.format("L%-3d", i)).append("\r\n");
        paint("95 lines in one chunk", sb.toString());
        long[] s = stats(handle);
        gate("the model scrolled 66 times", s[6] >= 66, "scrolls=" + s[6]);
        gate("the window slid down with them", winT == before + 66, "winT " + before + " -> " + winT);
        final int first = winT - 66;
        gate("L1 sits above the window, in scrollback", first < winT && first >= 0, "row=" + first);
        for (int i = 1; i <= 95; i++) {
            long[] r = row(first + i - 1);
            boolean okRow = r != null;
            for (int c = 0; okRow && c < 4; c++) {
                long got = r[c];
                char want = String.format("L%-3d", i).charAt(c);
                if ((int) (got & 0xFFFF) != want || (int) ((got >>> 16) & 0xFFFF) != DEF) {
                    okRow = false;
                    cell("L" + i + " at row " + (first + i - 1), first + i - 1, c, want, DEF);
                }
            }
            if (okRow) checks++;
        }
        text("the last line is one above the bottom", winT + WIN_H - 2, 0, "L95 ", DEF);
        tail("and the bottom row is blank", winT + WIN_H - 1, 0, DEF);
    }

    /**
     * The alternate screen on the real console. This is the one sequence where the two legs cannot be
     * interchangeable by construction: the fallback hands ?1049 to conhost, which keeps a second buffer and
     * swaps which one the window shows, while the model keeps one buffer and copies the viewport out and
     * back. Both promise the same thing, and only ReadConsoleOutputW can say whether the screen a program
     * left is the screen it found -- including the rows above the window, which a witness that reads only
     * the viewport cannot see, and the cursor, which no grid of cells shows at all.
     *
     * The case writes nothing outside the alt episode, and compares the rows it must hand back against
     * snapshots of themselves rather than against labels it painted first. That restraint is load-bearing:
     * the rows above the window are scrollback the model keeps but does not own, and a case that wrote two
     * lines of its own there to have something to check would slide the window down and, this close to the
     * top of the buffer, paint gutter rows onto console rows the *next* case then reads as its own.
     * Whatever the earlier cases left on screen witnesses just as well, because it is the same content on
     * both sides of the switch.
     */
    private static void caseAltScreen() {
        long[] s0 = stats(handle);
        final int declines0 = (int) s0[2], altbuf0 = (int) s0[S_UN + 2];
        final int altSwitch0 = (int) s0[S_ALT], refused0 = (int) s0[S_ALT_FAIL];
        final int hist0 = (int) s0[15];

        final int top0 = winT;                       /* the window's row: nothing here may move it */
        long[] above = top0 > 0 ? row(top0 - 1) : null;   /* scrollback: kept, never painted */
        long[] first = row(top0);                          /* and the viewport's own three rows, */
        long[] middle = row(top0 + WIN_H / 2);             /* the bottom one, which a pager's last  */
        long[] last = row(top0 + WIN_H - 1);               /* line would land on, most of all */

        gotoRow(WIN_H / 2);                          /* where a pager is when it switches screens */
        long[] before = consoleView();
        final int curX = (int) before[5], curY = (int) before[6];

        final int n = WIN_H + 5;                     /* five lines more than the viewport holds */
        StringBuilder alt = new StringBuilder("\u001b[?1049h\u001b[H");
        for (int i = 1; i <= n; i++) {
            if (i > 1) alt.append("\r\n");           /* no trailing one: the bottom row stays written */
            alt.append(String.format("A%-3d", i));
        }
        paint("alt screen", alt.toString());
        gate("the window did not move for the alt", winT == top0, "winT " + top0 + " -> " + winT);
        /* The alt scrolled n - WIN_H + 1 times under its own cursor, so the surviving lines run from that
           index to n across the viewport. Consecutive rows, which is the continuity witness
           caseManyScreens uses -- one lost line anywhere in the window shows up as a jump. */
        final int topLine = n - WIN_H + 1;
        text("the alt's oldest surviving line is at the top", winT, 0, String.format("A%-3d", topLine), DEF);
        text("and the rows between it are consecutive", winT + WIN_H / 2, 0,
                String.format("A%-3d", topLine + WIN_H / 2), DEF);
        text("its newest line is on the bottom row", winT + WIN_H - 1, 0, String.format("A%-3d", n), DEF);
        long[] inside = stats(handle);
        gate("a scroll inside the alt queued nothing", inside[9] == 0, "pendingScrolls=" + inside[9]);
        same("the alt's blanking stopped at the window", top0 - 1, above);

        paint("leaving the alt", "\u001b[?1049l");
        gate("and still nothing queued on the way out", stats(handle)[9] == 0, "pendingScrolls");
        same("the window's top row came back", top0, first);
        same("its middle row", top0 + WIN_H / 2, middle);
        same("and the row the alt had overwritten last", top0 + WIN_H - 1, last);
        same("with the scrollback it started with", top0 - 1, above);
        long[] after = consoleView();
        gate("the cursor is back where the program stood",
                after[5] == curX && after[6] == curY,
                "(" + after[5] + "," + after[6] + ") want (" + curX + "," + curY + ")");
        gate("the window is where it was", after[0] == top0, "winT=" + after[0]);

        long[] s1 = stats(handle);
        gate("one switch each way, taken by us", s1[S_ALT] - altSwitch0 == 2,
                "alt switches=" + (s1[S_ALT] - altSwitch0));
        gate("none refused", s1[S_ALT_FAIL] == refused0, "refused=" + s1[S_ALT_FAIL]);
        gate("and none counted as unmodelled", s1[S_UN + 2] == altbuf0, "altbuf=" + s1[S_UN + 2]);
        gate("the episode did not grow the model's own rows", (int) s1[15] == hist0,
                "gutter=" + s1[15] + " was " + hist0 + ": the alt borrows the viewport, not the history");
        gate("the whole episode stayed on the native path", s1[2] == declines0,
                "declines=" + (s1[2] - declines0) + ": a decline would send the bytes to conhost's own alt buffer");
    }

    /**
     * The console window is resized under the renderer: a change the model cannot follow must decline
     * (so Java replays the chunk through WriteProcessed3 and the user sees nothing), and a fresh handle
     * aligned to the new shape must then paint normally. Height is what the model follows; the last stage
     * shows that a *narrower* window alone is not such a change, since a model row is a buffer row.
     */
    private static void caseRealign() {
        if (setGeometry(BUF_W, BUF_H, 80, 24, DEF) == 0) { gate("resize", false, "setGeometry"); return; }
        char[] c = "stale geometry".toCharArray();
        feed(handle, c, 0, c.length);
        int decline = flush(handle);
        drainSgr();                             /* a decline drops the echo: the fallback leg reads them */
        gate("a geometry change declines the chunk", decline == -1, "flush=" + decline);
        long[] s = stats(handle);
        gate("no console call failed on the way", s[3] == 0, "apiErrors=" + s[3]);
        close(handle);

        handle = open(BUF_W, 24, DEF);
        gate("realigned to 24 rows of a 200-column buffer", handle != 0 && align(handle) == 1, null);
        flushQuietly();
        winT = (int) consoleView()[0];
        char[] t = "\u001b[32mok\u001b[0m".toCharArray();
        feed(handle, t, 0, t.length);
        gate("painting works again", flush(handle) == 0, null);
        drainSgr();
        text("after realign", winT, 0, "ok", 0x02);
        /* align() adopted the window, so what was already on this row is still there: "hello world" from
           the first case, minus the two columns the new chunk overwrote. A renderer that lost it would be
           painting blanks it was never asked for. */
        text("after realign keeps the row", winT, 2, "llo world", DEF);
        span("after realign tail", winT, 11, BUF_W - 1, ' ', DEF);

        /* Nothing about this resize puts the model out of register: cols is the buffer row, which did not
           move, and winRows did not either. The 140 columns past the window are painted as usual, which is
           the whole point of modelling a buffer row -- an 80-column terminal printing a 200-column line
           still has that line in its buffer. */
        if (setGeometry(BUF_W, BUF_H, 60, 24, DEF) == 0) { gate("narrow resize", false, "setGeometry"); return; }
        winT = (int) consoleView()[0];
        gotoRow(1);
        paint("window narrower than the model", "wide>\u001b[K");
        text("a narrow window paints", winT + 1, 0, "wide>", DEF);
        span("a narrow window paints to dwSize.X", winT + 1, 5, BUF_W - 1, ' ', DEF);
        s = stats(handle);
        gate("and none of it was declined", s[2] == 0, "declines=" + s[2]);
    }

    /**
     * The self-heal at the layer that pays for it (S3). A sequence we consume without modelling, that could
     * have moved the console's cursor or chosen which rows scroll, leaves the model describing a screen that
     * is not there -- and no geometry check catches that, because the window still has the shape the model
     * claims. So the flush after one re-adopts the console, which is an align and a full-window repaint. A
     * dropped colour must not buy that: the colon form of SGR 38 is what keeps the two apart, and it is why
     * the decision is made per family rather than "anything unmodelled".
     *
     * <p>DECSTBM left this case when the region became modelled (I25): it rolls rows the grid already holds,
     * so it earns neither a counter nor an adopt, and the case says so now. So did `CSI Ps t`, whose upstream
     * body (Ansi.cpp:3688-3762) turned out, on reading, to split into arms that either ask the window a
     * question or answer one -- a report, not an unknown, and it spends RC_UN_REPORT instead. What is left in
     * the unknown arm is a final byte no source has adjudicated at all, and this case has to be seen to test
     * the tripwire rather than any one sequence, so it uses `CSI Ps \`, which has never meant anything in any
     * family: the reach is unknown by construction, and that is exactly what the self-heal is for.
     */
    private static void caseSuspectAlign() {
        gotoRow(6);
        paint("clean the row", "\u001b[0m\u001b[K");
        long[] a = stats(handle);
        paint("a sequence with reach", "\u001b[7;1HTWO\u001b[1\\");
        long[] b = stats(handle);
        gate("a sequence with reach is counted", b[S_UN] - a[S_UN] == 1, "unrecognised=" + (b[S_UN] - a[S_UN]));
        gate("and the console was re-adopted once", b[4] - a[4] == 1, "aligns=" + (b[4] - a[4]));
        paint("paint after an adopt", "\u001b[7;1Hok");
        text("paints after an adopt", winT + 6, 0, "ok", DEF);

        /* One align per chunk, not per row: the adopt clears the flag, so a frame that carries two of them
           still re-adopts once. */
        a = stats(handle);
        paint("two more", "\u001b[1\\\u001b[2\\");
        b = stats(handle);
        gate("two unmodelled finals, one adopt", b[4] - a[4] == 1, "aligns=" + (b[4] - a[4]));
        gate("and both were counted", b[S_UN] - a[S_UN] == 2, "unrecognised=" + (b[S_UN] - a[S_UN]));

        /* A region is the other half of the same claim: setting one and taking it away moves nothing the
           console has to be asked about, so a Status bar that pins its rows costs no repaint at all. */
        a = stats(handle);
        paint("a modelled scroll region", "\u001b[2;4r\u001b[r");
        b = stats(handle);
        gate("a scroll region buys no adopt", b[4] - a[4] == 0, "aligns=" + (b[4] - a[4])
                + ": the rows it would scroll are rows this grid holds");
        gate("and spends no counter", b[S_UN + 1] - a[S_UN + 1] == 0, "decstbm=" + (b[S_UN + 1] - a[S_UN + 1]));

        a = stats(handle);
        paint("a colon colour the build carries", "\u001b[38:2::1:2:3m");
        b = stats(handle);
        gate("a carried colon arm spends the counter on nothing", b[S_COLON] - a[S_COLON] == 0,
                "colon=" + (b[S_COLON] - a[S_COLON]) + ": #78 moved this counter from \"a ':' went past\" to"
                        + " \"an arm of it is not carried\", and a colour it can name is not one of those");
        gate("and buys no repaint", b[4] - a[4] == 0, "aligns=" + (b[4] - a[4])
                + ": a colour that arrives as a cell write needs no window work of its own");
        gate("it was not counted as a mode set either", b[S_UN + 4] - a[S_UN + 4] == 0,
                "mode=" + (b[S_UN + 4] - a[S_UN + 4]) + ": the two are different decisions, and the labels say which");
        a = stats(handle);
        paint("an underline colour", "\u001b[58:5::1m");
        b = stats(handle);
        gate("the arm that has no surface still has its own counter", b[S_COLON] - a[S_COLON] == 1,
                "colon=" + (b[S_COLON] - a[S_COLON]) + ": this is what the slot is for now");

        a = stats(handle);
        paint("mouse tracking", "\u001b[?1000h\u001b[?1006h");
        b = stats(handle);
        gate("mouse modes are counted", b[S_UN + 3] - a[S_UN + 3] == 2, "mouse=" + (b[S_UN + 3] - a[S_UN + 3]));
        gate("and change nothing the model has to trust", b[4] - a[4] == 0, "aligns=" + (b[4] - a[4]));

        /* The two families that reached a final and left no number at all until build -7: `CSI p` in every
           spelling but the one DECSTR gates on, and a charset designator other than `ESC ( 0`. The host gate
           proves the model counts them, but it links Render.cpp directly; this is the leg that says the
           deployed DLL, through a real conhost, does too. It also pins the *kind* of count -- inert, not
           suspected -- because the difference is what the row below would otherwise have cost: a full-window
           repaint per frame that carried one. */
        gotoRow(6);
        paint("clear for the census leg", "\u001b[0m\u001b[K");
        a = stats(handle);
        paint("the -7 arms", "\u001b[p\u001b[61p\u001b)0q");
        b = stats(handle);
        gate("the CSI p family and ESC ) c are counted", b[S_UN] - a[S_UN] == 3,
                "unrecognised=" + (b[S_UN] - a[S_UN]));
        gate("and none of the three buys a repaint", b[4] - a[4] == 0, "aligns=" + (b[4] - a[4])
                + ": a charset with no model moves no cursor, so it must not cost a window repaint");
        text("while the byte after them reached the screen", winT + 6, 0, "q", DEF);

        gotoRow(6);
        paint("leave the row as we found it", "\u001b[0m\u001b[K");
    }

    /**
     * A console with no scrollback: `mode con: cols=120 lines=30` produces it, and it is the shape the
     * live A/B runs in. The renderer cannot be met there with a slide -- free_travel is zero, so every
     * scroll the model counted must be paid with a ScrollConsoleScreenBuffer, and the model's own gutter
     * (open() always gives it one screenful) lands *above* the buffer: row0 goes negative, and the rows it
     * holds are dropped by arithmetic rather than by a decline. No branch of that path had ever faced a
     * real conhost.
     *
     * The witness is a row count, not a verdict string. Two markers, painted and therefore clean: only a
     * scroll can move them. Two scrolls put the lower one on buffer row 3 and push the upper one out of
     * the buffer entirely, leaving a blank where it was painted. winT is asserted in the same breath:
     * sliding moves the window along with the rows, and keeping the window still is the whole point of
     * the shape this console makes impossible to slide in.
     */
    private static void caseNoScrollback() {
        long outer = handle;                       /* caseRealign's handle: parked, not closed */
        handle = 0;
        /* Two calls, in this order: SetConsoleScreenBufferSize fails while the window still hangs below
           the buffer it is being shrunk into, and setGeometry returns only the window call's result. Pull
           the window up to 10 rows first, then the buffer can come down to meet it. The shape is
           therefore asserted from consoleView below rather than trusted from here. */
        setGeometry(BUF_W, BUF_H, WIN_W, 10, DEF);
        if (setGeometry(BUF_W, WIN_H, WIN_W, WIN_H, DEF) == 0) {
            gate("no-scrollback geometry", false, "setGeometry");
            handle = outer;
            return;
        }
        handle = open(BUF_W, WIN_H, DEF);
        gate("opened for a 30-row window", handle != 0 && align(handle) == 1, null);
        flushQuietly();
        long[] v = consoleView();
        winT = (int) v[0];
        gate("the buffer is the window, at its top", v[3] == WIN_H && v[0] == 0,
                "bufH=" + v[3] + " winT=" + v[0]);
        long[] s = stats(handle);
        gate("while the model still has a gutter", s[15] == WIN_H,
                "gutter=" + s[15] + ": a gutter over a bufferless console is what must be dropped");

        /* align() *adopts* what is already on the screen, so the window is not blank after it -- the rows
           here still carry the earlier cases' text. Erase through the renderer instead of assuming: it
           doubles as the ED witness on a buffer that cannot hold what it pushes out. */
        paint("erase the adopted window", "\u001b[2J\u001b[H");
        tail("ED blanked the buffer's top row", 0, 0, DEF);

        gotoRow(0);
        paint("marker at the top", "TOP");
        gotoRow(5);
        paint("marker five down", "MK");
        text("both markers are where they were written", 0, 0, "TOP", DEF);
        text("both markers are where they were written", 5, 0, "MK", DEF);

        gotoRow(WIN_H - 1);
        paint("two scrolls", "L1\r\nL2\r\nL3");
        v = consoleView();
        winT = (int) v[0];
        gate("the window could not travel, so it did not", v[0] == 0 && v[3] == WIN_H,
                "winT=" + v[0] + " bufH=" + v[3]);
        text("the lower marker rode up two buffer rows", 3, 0, "MK", DEF);
        text("the scrolled-in lines sit at the bottom", WIN_H - 3, 0, "L1", DEF);
        text("the scrolled-in lines sit at the bottom", WIN_H - 2, 0, "L2", DEF);
        text("the scrolled-in lines sit at the bottom", WIN_H - 1, 0, "L3", DEF);
        tail("the bottom row is written to the buffer edge", WIN_H - 1, 2, DEF);
        cell("the top marker was pushed out of the buffer", 0, 0, ' ', DEF);
        s = stats(handle);
        gate("no console call failed on the way", s[3] == 0, "apiErrors=" + s[3]);
        gate("the scrolls were consumed", s[9] == 0, "pendingScrolls=" + s[9]);

        /* The hard version of the same shape: one chunk of 95 lines, so 66 scrolls are owed and the
           gutter holds rows the buffer has no room for. All that may survive is the newest screenful,
           contiguous -- a plan that painted a gutter row at a negative buffer row, or that declined
           instead of dropping, would leave a jump or a blank band here. */
        gotoRow(0);
        StringBuilder sb = new StringBuilder();
        for (int i = 1; i <= 95; i++) sb.append(String.format("N%-3d", i)).append("\r\n");
        int before = (int) stats(handle)[6];
        paint("95 lines with nowhere to slide", sb.toString());
        s = stats(handle);
        gate("the model owed every scroll to the buffer", s[6] - before >= 66,
                "scrolls=" + (s[6] - before));
        gate("no console call failed on 66 of them", s[3] == 0, "apiErrors=" + s[3]);
        gate("and the flush was not declined", s[2] == 0, "declines=" + s[2]);
        for (int i = 67; i <= 95; i++) {
            long[] r = row(i - 67);
            String want = String.format("N%-3d", i);
            boolean okRow = r != null;
            for (int c = 0; okRow && c < 4; c++)
                if ((int) (r[c] & 0xFFFF) != want.charAt(c)
                        || (int) ((r[c] >>> 16) & 0xFFFF) != DEF) okRow = false;
            if (!okRow) cell("N" + i + " on buffer row " + (i - 67), i - 67, 0, want.charAt(0), DEF);
            else checks++;
        }
        text("the newest line is one above the bottom", WIN_H - 2, 0, "N95 ", DEF);
        tail("the bottom row is blank", WIN_H - 1, 0, DEF);

        close(handle);
        handle = outer;
    }

    /**
     * Invariant I18 on a real console: when the mid-chunk paint that rc_feed triggers through flush_now is
     * declined (RenderJni.cpp), painting is switched off for the rest of the chunk and the chunk's final
     * flush reports the decline. The host test can only assert that the hook stops firing; here the cost of
     * a missing disarm is countable, because a declined paint never reaches rc_paint_done and so leaves the
     * model's scroll debt owed -- every line after the 30th would re-trip the trigger, giving 38 declines
     * where 2 is right.
     *
     * The other half is recovery: align() re-arms the hook, and the witness that it happened is a second
     * multi-screen chunk painted mid-chunk again (more than one flush, no declines).
     *
     * "Nothing landed" is the property the caller's replay depends on, so a marker painted before the
     * resize is read back after the declined chunk. Bytes that painted and were then replayed through
     * WriteProcessed3 would show up as the marker gone and 95 lines on screen twice over.
     */
    private static void caseHookDecline() {
        long outer = handle;                        /* caseNoScrollback's parked model: alive, untouched */
        handle = 0;
        if (setGeometry(BUF_W, BUF_H, WIN_W, WIN_H, DEF) == 0) {
            gate("hook-case geometry", false, "setGeometry");
            handle = outer;
            return;
        }
        handle = open(BUF_W, WIN_H, DEF);
        gate("opened for the hook case", handle != 0 && align(handle) == 1, null);
        flushQuietly();
        winT = (int) consoleView()[0];
        gotoRow(0);
        paint("marker before the resize", "KEEP");
        final int markRow = winT;

        /* The console's viewport becomes 24 rows under a 30-row model, so every plan from here is NOGEOM.
           The width shrinking to 80 is along for the ride: a model row is the buffer row, and caseRealign
           shows a narrow window on its own does not decline. */
        if (setGeometry(BUF_W, BUF_H, 80, 24, DEF) == 0) {
            gate("hook-case resize", false, "setGeometry");
            close(handle);
            handle = outer;
            return;
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 1; i <= 95; i++) sb.append(String.format("H%-3d", i)).append("\r\n");
        char[] c = sb.toString().toCharArray();
        long[] a = stats(handle);
        gate("the chunk is still taken", feed(handle, c, 0, c.length) == 1, null);
        int r = flush(handle);
        drainSgr();                                 /* a decline drops the echo: the fallback leg reads it */
        long[] b = stats(handle);
        gate("the chunk comes back declined", r == -1, "flush=" + r);
        gate("the hook tried to paint, once", b[0] - a[0] == 2,
                "flushes=" + (b[0] - a[0]) + ": the hook's attempt and the final flush");
        gate("and painting stopped after the first decline", b[2] - a[2] == 2,
                "declines=" + (b[2] - a[2]) + ": 38 would mean the hook was still armed");
        gate("no console call failed on the way", b[3] - a[3] == 0, "apiErrors=" + (b[3] - a[3]));
        gate("the scrolls are still owed, which is what would re-trip it", b[9] > 0,
                "pendingScrolls=" + b[9]);
        text("nothing landed: the marker is where it was", markRow, 0, "KEEP", DEF);

        /* The caller's recovery: a fresh model, aligned to the console's new shape, paints normally --
           and the alignment, not the paint, is what cancels the debt. */
        close(handle);
        if (setGeometry(BUF_W, BUF_H, WIN_W, WIN_H, DEF) == 0) {
            gate("hook-case resize back", false, "setGeometry");
            handle = outer;
            return;
        }
        handle = open(BUF_W, WIN_H, DEF);
        gate("re-opened after the decline", handle != 0 && align(handle) == 1, null);
        flushQuietly();
        winT = (int) consoleView()[0];
        int before = winT;
        gotoRow(0);
        a = stats(handle);
        paint("the same 95 lines, hook armed", sb.toString());
        b = stats(handle);
        gate("align re-armed the hook", b[0] - a[0] >= 2,
                "flushes=" + (b[0] - a[0]) + ": one would mean the whole chunk waited for the final flush");
        gate("and nothing was declined this time", b[2] - a[2] == 0, "declines=" + (b[2] - a[2]));
        gate("the debt was paid by the paints", b[9] == 0, "pendingScrolls=" + b[9]);
        gate("the window slid the whole way down", winT == before + 66, "winT " + before + " -> " + winT);
        text("H1 rode into scrollback, as on the un-hooked path", winT - 66, 0, "H1  ", DEF);
        text("H95 is one above the bottom", winT + WIN_H - 2, 0, "H95 ", DEF);
        tail("and the bottom row is blank", winT + WIN_H - 1, 0, DEF);

        close(handle);
        handle = outer;
    }

    /**
     * The shape a fresh conhost on this machine really has: a 2000x9001 buffer with a 120x60 window,
     * measured 2026-09-23 with cache/jnatest/shape.exe (Windows Terminal and ConEmu keep buffer ==
     * window, where nothing below is a question at all). It is the ratio that justifies modelling a buffer
     * row -- a 300-column dashboard frame is *one line* here, with 180 of its columns waiting off screen
     * for a scroll right -- and the ratio that makes it cost something: every damaged row is 2000 cells,
     * so a full-window repaint is 60000 of them (~2.6 ms measured, PaintBench, against ~6.3 ms for the
     * fallback leg).
     *
     * The window is 30 rows of a 2000-column buffer here rather than 60 of 9001, because what is under
     * test is the width. The witnesses are that nothing wrapped at 120, that the far columns are in the
     * buffer where a read of them finds them, and that an erase reaches dwSize.X.
     */
    private static void caseWideBuffer() {
        long outer = handle;                        /* the parked model: alive, and the one main() reports */
        handle = 0;
        if (setGeometry(WIDE_BUF_W, WIDE_BUF_H, WIDE_WIN_W, WIN_H, DEF) == 0) {
            gate("wide-buffer geometry", false, "setGeometry");
            handle = outer;
            return;
        }
        handle = open(WIDE_BUF_W, WIN_H, DEF);
        gate("a 2000-column model opened", handle != 0 && align(handle) == 1, null);
        if (handle == 0) { handle = outer; return; }
        flushQuietly();
        long[] v = consoleView();
        winT = (int) v[0];
        gate("the window is a twentieth of the buffer", v[2] == WIDE_BUF_W && v[1] == 0 && v[3] == WIDE_BUF_H,
                "bufW=" + v[2] + " winL=" + v[1] + " bufH=" + v[3]);

        paint("erase the adopted window", "\u001b[2J\u001b[H");
        gotoRow(2);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < 300; i++) sb.append((char) ('a' + i % 26));
        paint("300 columns in one line", sb.toString());
        long[] r = readCells(0, winT + 2, WIDE_BUF_W, 1);
        boolean ok = r != null;
        for (int i = 0; ok && i < 300; i++)
            ok = (int) (r[i] & 0xFFFF) == 'a' + i % 26 && (int) ((r[i] >>> 16) & 0xFFFF) == DEF;
        for (int i = 300; ok && i < WIDE_BUF_W; i++)
            ok = (int) (r[i] & 0xFFFF) == ' ' && (int) ((r[i] >>> 16) & 0xFFFF) == DEF;
        gate("300 columns, one row, to the buffer's right edge", ok, "row " + (winT + 2));
        v = consoleView();
        long[] s = stats(handle);
        gate("the parked cursor stayed inside the window",
                v[5] == WIDE_WIN_W - 1 && v[6] == winT + 2, "(" + v[5] + "," + v[6] + ") winT=" + winT);
        gate("so the window did not slide after it", v[1] == 0, "winL=" + v[1]);
        gate("while the model is at column 300", s[10] == 300, "cx=" + s[10]);
        gate("nothing was declined at 2000 columns", s[2] == 0, "declines=" + s[2]);
        gate("no console call failed either", s[3] == 0, "apiErrors=" + s[3]);

        /* B2 on the half of the row nobody can see: two one-column rewrites, one inside the window and one
           1380 columns past its right edge. The first pins the rectangle's left edge against a neighbour
           that is on screen; the second is the only witness this file has that a narrow damage way out in
           the buffer reaches that column and not the one the window's width would have guessed. */
        paint("a column inside the window", "\u001b[3;1H\u001b[151GQ");
        span("column 150 is the rewrite", winT + 2, 150, 150, 'Q', DEF);
        span("and not column 149", winT + 2, 149, 149, (char) ('a' + 149 % 26), DEF);
        span("and not column 151", winT + 2, 151, 151, (char) ('a' + 151 % 26), DEF);
        span("the line still starts where it did", winT + 2, 0, 0, 'a', DEF);
        span("and still ends where it did", winT + 2, 299, 299, (char) ('a' + 299 % 26), DEF);
        paint("a column off screen", "\u001b[1501Gq");
        span("column 1500 is the rewrite", winT + 2, 1500, 1500, 'q', DEF);
        span("its left neighbour is still a blank", winT + 2, 1499, 1499, ' ', DEF);
        span("its right neighbour is still a blank", winT + 2, 1501, 1501, ' ', DEF);
        s = stats(handle);
        gate("and nothing was declined for the width of a rectangle", s[2] == 0, "declines=" + s[2]);

        paint("an erase across a buffer row", "\u001b[2J\u001b[H\u001b[42mX\u001b[K");
        text("green at the left", winT, 0, "X", 0x27);
        span("EL carried the colour across the whole buffer row", winT, 1, WIDE_BUF_W - 1, ' ', 0x27);
        close(handle);
        handle = outer;
    }

    /**
     * Invariant I28 on a real console: a paint the user is not looking at may not rewrite what they are.
     *
     * The bug this pins is the one reported as "退出more模式后，上翻，历史内容也是乱七八糟的，很多被截掉了":
     * the painter used to derive its rows from `srWindow.Top` at every flush, and conhost lets the view
     * travel over the buffer without telling anybody. Scroll up, and the formula hands the painter the rows
     * the user is reading --
     * so the next line the application prints is written over their history and the application's own rows
     * land where the history was (measured 2026-09-24 on a 200x60 shape: view at row 0, content at row 30,
     * one prompt line rewrote row 29 and blanked row 30, 72 rectangles, nothing declined). The fix is that
     * the model owns its anchor -- conhost's `_virtualBottom` (screenInfo.hpp:218), ghostty's `.active` pin
     * (point.zig:12-50) -- and treats the window as evidence about the *view*, never about the content.
     *
     * The shape has to be this buffer, not the 60-row one ScrollRepro first measured: a model is its viewport
     * plus one viewport of gutter, so over a 60-row buffer the model's region *is* the whole buffer and the
     * user's rows would legitimately move. The same distinction holds one row further down: while buffer rows
     * below the claim are still unused, a scroll is paid inside the claim and the user's rows do not move at
     * all, and only once the claim reaches the buffer's bottom is there no in-place answer left -- which is
     * caseFullBufferEvicts' business, and why the history written below stops short of that row.
     *
     * The witness is the whole protected range, read before and after: every one of those rows identical,
     * the prompt found below the anchor rather than at the top of the buffer, and the user's view -- its
     * row and its cursor -- exactly where they left it, because following output with the view is what
     * neither terminal does (ghostty's scroll-to-bottom is `{ keystroke = true, output = false }`,
     * Config.zig:10446; conhost snaps only for output the user has not walked away from,
     * screenInfo.cpp:1715-1726).
     */
    private static void caseScrollKeepsHistory() {
        final String line = "SQL > select * from v$session";
        long outer = handle;                        /* the parked model: alive, and the one main() reports */
        handle = 0;
        /* One call, and it cannot fail on ordering: the buffer's width comes down from 2000 to 200 columns
           while the window is 120 wide, and its height grows from 300 to 400 rows under a window that has
           always fitted in 300. */
        if (setGeometry(BUF_W, BUF_H, WIN_W, WIN_H, DEF) == 0) {
            gate("scrolled-back geometry", false, "setGeometry");
            handle = outer;
            return;
        }
        handle = open(BUF_W, WIN_H, DEF);
        gate("a 30-row window over a 400-row buffer opened", handle != 0 && align(handle) == 1, null);
        if (handle == 0) { handle = outer; return; }
        flushQuietly();
        paint("clean start", "\u001b[0m\u001b[2J\u001b[H");
        winT = (int) consoleView()[0];

        /* History through the renderer, so every row is one the model and the console agree on, and enough of
           it to drive the claim well down the buffer -- 30 lines to fill the window, then one row of slide per
           line -- without reaching the buffer's last row, which would make the scroll an eviction and turn
           this case into the other one.
           In chunks, and GATE_TRACE names where the newest line of each one landed: which row a line ends on
           *is* this case's premise, and one call cannot say where that stops being the buffer row
           the line number suggests. */
        final int CHUNK = 20, NLINES = 100;
        for (int i = 0; i < NLINES; i += CHUNK) {
            final int last = Math.min(i + CHUNK, NLINES) - 1;
            StringBuilder sb = new StringBuilder();
            for (int k = i; k <= last; k++) sb.append("HIST ").append(k).append(" - the user's history\r\n");
            paint("HIST " + i + ".." + last, sb.toString());
            long[] tv = consoleView();
            long[] pl = plan(handle);
            final int newest = findRow("HIST " + last + " -", 0, BUF_H);
            /* The two invariants every flush owes, checked on every chunk rather than inferred from the final
               map: the ink is inside the band the plan addressed, and the console's window is the one the plan
               says it left. A row that satisfies the first and not the second is the model painting somebody
               else's rows; a duplicate of the same line 341 rows away is the model painting the same rows
               twice, which is what this case was written to catch. */
            if (pl[15] > 0) {
                gate("chunk " + last + ": the ink landed inside the band the plan claimed",
                        newest >= pl[9] && newest < pl[9] + pl[11],
                        "newest=" + newest + " row0=" + pl[9] + " rows=" + pl[11] + " base=" + pl[5]
                                + " slide=" + pl[6] + " bufScroll=" + pl[8] + " winT=" + pl[4]);
                gate("and the window is where that plan left it", tv[0] == pl[10],
                        "winT=" + tv[0] + " plan winTop=" + pl[10] + " row0=" + pl[9] + " gutter=" + (pl[11] - pl[12]));
            }
            if (System.getenv("GATE_TRACE") != null) {
                long[] ts = stats(handle);
                System.out.println("  TRACE last=" + last + " newest@" + newest
                        + " winT=" + tv[0] + " cur=" + tv[5] + "," + tv[6] + " bufH=" + tv[3]
                        + " | seq=" + pl[0] + " reason=" + pl[1] + " baseSet=" + pl[2] + " baseRow=" + pl[3]
                        + " winT@plan=" + pl[4] + " base=" + pl[5] + " slide=" + pl[6] + " slideTo=" + pl[7]
                        + " bufScroll=" + pl[8] + " row0=" + pl[9] + " winTop=" + pl[10] + " rows=" + pl[11]
                        + " winRows=" + pl[12] + " runs=" + pl[15] + " declined=" + pl[16] + " moveFail=" + pl[17]
                        + " | cy=" + ts[11] + " pend=" + ts[9] + " scrolls=" + ts[6] + " flush=" + ts[0]);
            }
        }

        long[] v = consoleView();
        winT = (int) v[0];
        long[] s = stats(handle);
        final int hist = (int) s[15];
        final int base = winT - hist;              /* the model's anchor, while the view is still its own */
        gate("the window has slid well down the buffer", winT > WIN_H,
                "winT=" + winT + " of " + BUF_H);
        gate("and the model claims rows no window is looking at", base > WIN_H,
                "base=" + base + " gutter=" + hist + ": the rows above it are what the user can scroll to");
        gate("with buffer rows still unused below the claim", base + (int) s[14] + hist < BUF_H,
                "base=" + base + " rows=" + (s[14] + hist) + " of " + BUF_H
                        + ": that room is what lets a scroll stay inside the claim, which is this case's premise");
        gate("the scroll debt was paid, not carried", s[9] == 0, "pendingScrolls=" + s[9]);
        gate("nothing was declined on the way down", s[2] == 0, "declines=" + s[2]);
        gate("no console call failed either", s[3] == 0, "apiErrors=" + s[3]);
        if (System.getenv("GATE_MAP") != null) {
            System.out.println("  MAP winT=" + winT + " base=" + base + " gutter=" + hist
                    + " cy=" + s[11] + " rows=" + s[14] + " scrolls=" + s[6]);
            for (int r = 0; r < BUF_H; r++) {
                if (r >= 80 && r < BUF_H - 70) continue;      /* the two bands that matter, every row */
                long[] rw = row(r);
                System.out.println("  MAP " + r + " [" + (rw == null ? "?" : head(rw)) + "]");
            }
        }
        /* Where the user's history starts, found rather than assumed: the model's very first line had to make
           room for its own gutter, so the window slid from row 0 down to `hist` before anything was written,
           and the rows above that the console never held at all. The invariant below covers [0, base) --
           written history and untouched blanks alike -- so this only names what the view is sitting on. */
        final int hist0 = findRow("HIST 0 - the user's history", 0, base);
        gate("the oldest line is above the model's claim", hist0 >= 0 && hist0 < base,
                "hist0=" + hist0 + " anchor=" + base);

        long[][] was = new long[base][];
        boolean readable = true;
        for (int r = 0; r < base; r++) {
            was[r] = row(r);
            if (was[r] == null) readable = false;
        }
        gate("every scrollback row is readable", readable, "the diff below is worthless without this");
        if (!readable) {
            close(handle);
            handle = outer;
            return;
        }

        /* The user scrolls up: the view goes to the top of the buffer, not one cell moves, and nothing tells
           the renderer. setGeometry puts the window at (0,0) and the console cursor with it, which is exactly
           the state a scroll wheel leaves behind. */
        if (setGeometry(BUF_W, BUF_H, WIN_W, WIN_H, DEF) == 0) {
            gate("the scroll", false, "setGeometry");
            close(handle);
            handle = outer;
            return;
        }
        v = consoleView();
        gate("the view is at the buffer's top now", v[0] == 0, "winT=" + v[0]);
        s = stats(handle);
        final int cells = (int) s[5];
        paint("one prompt line while the user reads history", line + "\r\n");
        v = consoleView();
        s = stats(handle);

        StringBuilder why = new StringBuilder();
        int changed = diffRows(was, 0, base, why);
        gate("the history the user is reading is untouched, all " + base + " rows", changed == 0,
                "changed=" + changed + why
                        + ": a rewrite at the row just above the claim is the pre-anchor formula, painting at"
                        + " winT - gutter + r; a whole-buffer shift here is the other case's answer, applied"
                        + " while rows below the claim are still free");
        gate("so the flush was not declined instead", s[2] == 0, "declines=" + s[2]);
        gate("and no console call failed", s[3] == 0, "apiErrors=" + s[3]);

        /* Where it did go: below the anchor, in the rows the model owns. Searching rather than naming a row,
           because the line's own newline owes one more buffer scroll and the answer to that is the plan's
           business -- what matters is on which side of the claim it landed. */
        int found = findRow(line, base, BUF_H);
        gate("the prompt landed in the model's own rows, not the scrollback", found >= base,
                "found=" + found + " anchor=" + base);
        if (found >= base) {
            text("and it reads as it was printed", found, 0, line, DEF);
        }
        gate("the model moved its cursor, at the bottom of its region", s[11] == (int) s[14] + hist - 1,
                "cy=" + s[11] + " rows=" + s[14] + " gutter=" + hist);
        if (hist0 >= 0) {
            text("the history the user came up to read is still there, row and all", hist0, 0,
                    "HIST 0 - the user's history", DEF);
            text("line by line, still the rows they were", hist0 + 3, 0, "HIST 3 - the user's history", DEF);
        }

        /* The view is the user's, so nothing here may have touched it: not its row, and not its cursor.
           The second is the half a plan could get wrong while still painting the right rows -- chasing the
           output with SetConsoleCursorPosition would drag the user back down to the bottom. */
        v = consoleView();
        gate("the window stayed where the user scrolled it", v[0] == 0, "winT=" + v[0]);
        gate("and the console cursor did not follow the output",
                v[5] == 0 && v[6] == 0, "(" + v[5] + "," + v[6] + "): cursorOffView means no call at all");
        System.out.println("  cost of one line into a scrolled-back console: cells=" + (s[5] - cells)
                + " flushes=" + s[0] + " scrolls=" + s[6]);

        /* ---- the same claim, tested the way the user's hand really moves: a resize --------------------
         *
         * A scroll and a resize both move srWindow, and the two must not be confused: the first is the
         * user's alone, so the anchor stands and nothing is written; the second changes the shape the
         * anchor was measured in, so rule 1 declines -- and a decline is the only response that cannot
         * damage a cell. What then heals it is an adopt, which reads the *window* into the model
         * (RenderJni.cpp::align_grid) and repaints it, so the promise an adopt has to keep is that the
         * round trip through it is the identity on everything the user can see. That is the resize half of
         * the promise "leaving or entering dbcli must not disturb what the terminal was showing", and it is
         * what the rows below are about.
         *
         * Chosen to be the awkward shape: the view is still at the top of the buffer when the window comes
         * down to 24 rows, so the model that re-adopts is claiming rows the history was occupying. */
        if (setGeometry(BUF_W, BUF_H, WIN_W, 24, DEF) == 0) {
            gate("resize while scrolled up", false, "setGeometry");
            close(handle);
            handle = outer;
            return;
        }
        v = consoleView();
        gate("the view is still where the user put it", v[0] == 0 && v[3] == BUF_H,
                "winT=" + v[0] + " bufH=" + v[3]);
        char[] c = "SQL > resized\r\n".toCharArray();
        feed(handle, c, 0, c.length);
        int rc = flush(handle);
        drainSgr();                                 /* a decline drops the echo: the fallback leg reads them */
        gate("a resize declines the chunk instead of guessing rows", rc == -1, "flush=" + rc);
        gate("and a decline wrote no scrollback row at all", diffRows(was, 0, base, why) == 0, "why=" + why);
        why.setLength(0);

        /* The recovery a resize owes -- and the reason this leg does not close the handle. render()'s state
           machine answers the decline by rebuilding the model for the console's new shape and re-adopting it
           (RenderJni.cpp::readopt), and the point of that pair is that the claim the *old* grid made travels
           with it: rc_anchor_adopt carries `prevBase + prevRows - 1` over the rebuild, because the rebuilt
           grid is 24+24 rows where the old one was 30+30, and the row the content ends on is the one that
           means the same thing on both sides. A leg that drove close() + open() instead would be testing a
           *new* session -- nothing to carry -- and would pass whether or not the carry works. So the same
           handle, readopt(), and every cell of the console snapshotted round it. */
        long[][] mine = new long[BUF_H - base][];
        for (int r = base; r < BUF_H; r++) {
            mine[r - base] = row(r);
        }
        s = stats(handle);
        final int aligns = (int) s[4], declines = (int) s[2];
        gate("the resize rebuilt this handle's model, and only its model", readopt(handle) == 1,
                "readopt returned 0: the console is not the shape the gate just set");
        flushQuietly();                             /* the full-window repaint an adopt asks for */
        v = consoleView();
        s = stats(handle);
        gate("the adopt read the window it claims, so it has to repaint it", s[4] == aligns + 1,
                "aligns=" + s[4] + " was " + aligns);
        gate("and healing a decline is not another decline", s[2] == declines, "declines=" + s[2]);
        changed = diffRows(mine, base, BUF_H, why);
        gate("the rebuild wrote not one cell of the " + (BUF_H - base) + " rows the model owns", changed == 0,
                "changed=" + changed + why + ": an adopt that reads at winT instead of at the carried anchor "
                        + "repaints the history it mistook for the screen");
        why.setLength(0);
        changed = diffRows(was, 0, base, why);
        gate("nor any of the " + base + " scrollback rows the user is looking at", changed == 0,
                "changed=" + changed + why);
        if (hist0 >= 0) {
            text("the history under the view is still the same row", hist0, 0,
                    "HIST 0 - the user's history", DEF);
        }
        gate("the window stayed at the buffer's top through the rebuild", v[0] == 0, "winT=" + v[0]);
        gate("no console call failed through the decline and the adopt", s[3] == 0, "apiErrors=" + s[3]);

        /* And the payoff, which is the same rule 2 the paint leg tested -- one viewport later: the text the
           application prints next still belongs to the model's rows, now 24 rows of viewport plus a 24-row
           gutter, and the 24 rows under the user's eyes are none of its business. An adopt that answered the
           resize with the window would have claimed rows -24..23 here, so this line would land at buffer row
           0, on top of the history, and `found` below would be less than `base`. */
        char[] d = "SQL > resized\r\n".toCharArray();
        feed(handle, d, 0, d.length);
        rc = flush(handle);
        drainSgr();
        gate("after the rebuild, output paints again", rc == 0 || rc == 1, "flush=" + rc);
        found = findRow("SQL > resized", base, BUF_H);
        gate("it landed below the anchor the resize carried, not in the view", found >= base,
                "found=" + found + " old anchor=" + base);
        why.setLength(0);
        changed = diffRows(was, 0, base, why);
        gate("and the user's history is still untouched after that line", changed == 0,
                "changed=" + changed + why);
        v = consoleView();
        gate("the window did not follow the output either", v[0] == 0, "winT=" + v[0]);
        gate("nor the cursor", v[5] == 0 && v[6] == 0, "(" + v[5] + "," + v[6] + ")");
        s = stats(handle);
        gate("throughout, the console never refused a call", s[3] == 0, "apiErrors=" + s[3]);
        System.out.println("  resize at winT=0: anchor carried to row " + (found < 0 ? "?" : String.valueOf(found))
                + " of " + BUF_H + ", " + base + " scrollback rows intact");

        /* Leave the console where the next case expects to find nothing in particular -- it shapes the console
           itself -- and the model's claim with it: closing is the only way to hand the slot back, and an
           unaligned parked model must not be the one that reports this case's declines. */
        close(handle);
        handle = outer;
    }

    /** The line number a buffer row carries, or -1 for a row that is not one of ours. Read off the console
     *  rather than trusted from the model: what survives is the buffer's decision, not the model's. */
    private static int histNumber(long[] rw) {
        if (rw == null) return -1;
        String t = head(rw);
        if (!t.startsWith("HIST ")) return -1;
        int sp = t.indexOf(" -", 5);
        if (sp < 0) return -1;
        try {
            return Integer.parseInt(t.substring(5, sp));
        } catch (NumberFormatException e) {
            return -1;
        }
    }

    /** Scan buffer rows [from,to) for the numbered history lines and report the run they make:
     *  {lowest, highest, how many, how many breaks, the last number before the first break, the buffer row
     *  the break is on}. A break being a line whose number is not its neighbour's successor. A ring reads as
     *  one unbroken run or it destroyed something; there is no third answer, and the three that are not the
     *  count are each a different way of getting it wrong (holes in the middle, duplicates, the newest lines
     *  gone rather than the oldest). */
    private static int[] histRun(int from, int to) {
        int first = -1, last = -1, seen = 0, bad = 0, gapAt = -1, gapRow = -1;
        for (int r = from; r < to; r++) {
            int k = histNumber(row(r));
            if (k < 0) continue;
            if (first < 0) first = k;
            else if (k != last + 1) {
                bad++;
                if (gapAt < 0) { gapAt = last; gapRow = r; }
            }
            last = k;
            seen++;
        }
        return new int[] { first, last, seen, bad, gapAt, gapRow };
    }

    /** The first row of the buffer holding no printable text, or -1 when it is packed top to bottom. */
    private static int firstBlankRow() {
        for (int r = 0; r < BUF_H; r++) {
            long[] rw = row(r);
            if (rw == null) return -1;
            boolean blank = true;
            for (int c = 0; blank && c < rw.length; c++) blank = (int) (rw[c] & 0xFFFF) == ' ';
            if (blank) return r;
        }
        return -1;
    }

    /** One buffer row as far as the gate may print it, and a question mark when the console would not give
     *  the row at all -- a diagnostic must never be the thing that fails the case. */
    private static String rowHead(int r) {
        if (r < 0) return "-";
        long[] rw = row(r);
        return rw == null ? "?" : head(rw);
    }

    /**
     * Invariant I31 on a real console: once the buffer is full, a new line is paid for by the oldest one,
     * and by nothing else.
     *
     * This is the case the renderer had backwards. The rows the model claims are two viewports -- 60 rows --
     * and its scrollback is whatever the console holds above them, so on the far side of the slide cap the
     * two are the same 400 rows wearing one contract: the newest lines of the session belong in them, in
     * order, whether or not this program printed them. The band-only scroll of -11 moved the model's own 60
     * rows and left the 340 above them frozen where they were, which keeps the older text and drops the
     * newer -- 141 lines of this program's own output destroyed while 141 lines nobody was going to read
     * again sat safely in the dark, and the window showed none of it because every window row is dirty and
     * repainted anyway. The oracle is the same program writing the same bytes through the console API with
     * no renderer between them (`StartupRepro`, raw leg vs render leg): conhost keeps the last 400 lines in
     * order, because that is all a ring can keep.
     *
     * So the reach of a scroll is the reach of the buffer exactly when the claim a flush leaves behind has the
     * buffer's last row, and the reach of the claim otherwise -- caseScrollKeepsHistory is the second branch,
     * and the pair of them is what makes the difference a fact rather than a preference. It is the destination
     * and not the anchor that decides, and a slide does not escape it: sliding is how the claim gets to the last
     * row, and it moves no cells, so a flush that slides 19 lines and scrolls the 20th still owes that 20th
     * eviction. Leaving it unpaid was measured, and the census said what it costs: 399 lines in a 400-row buffer,
     * one of them missing from the middle and the last row blank. Inside the claim the rows land where they
     * landed before, so nothing about the paint changes: an eviction only says which rows above it ride up, and
     * the user's view with them, which is the one thing a terminal never lets a program avoid (conhost
     * `_stream.cpp:123-126` answering a row past the last with `TextBuffer::IncrementCircularBuffer`).
     */
    private static void caseFullBufferEvicts() {
        final String line = "SQL > select count(*) from v$session";
        final int CHUNK = 20, NLINES = BUF_H + 20;   /* 20 lines more than the buffer can hold */
        long outer = handle;
        handle = 0;
        if (setGeometry(BUF_W, BUF_H, WIN_W, WIN_H, DEF) == 0) {
            gate("full-buffer geometry", false, "setGeometry");
            handle = outer;
            return;
        }
        handle = open(BUF_W, WIN_H, DEF);
        gate("a 30-row window over a 400-row buffer opened", handle != 0 && align(handle) == 1, null);
        if (handle == 0) { handle = outer; return; }
        flushQuietly();
        paint("clean start", "\u001b[0m\u001b[2J\u001b[H");

        /* Numbered lines through the renderer until the buffer has nothing left but numbered lines. The first
           30 rows the model owns are its gutter, so 30 blanks ride out of the top before any text does: the
           overflow this case measures is 20 lines, and the census below says so in those terms rather than in
           ones this file could talk itself into believing. */
        for (int i = 0; i < NLINES; i += CHUNK) {
            final int last = Math.min(i + CHUNK, NLINES) - 1;
            StringBuilder sb = new StringBuilder();
            for (int k = i; k <= last; k++) sb.append("HIST ").append(k).append(" - the user's history\r\n");
            paint("HIST " + i + ".." + last, sb.toString());
            long[] pl = plan(handle);
            if (pl[15] > 0) {
                final int newest = findRow("HIST " + last + " -", 0, BUF_H);
                gate("chunk " + last + ": the newest line is in the rows the plan addressed",
                        newest >= pl[9] && newest < pl[9] + pl[11],
                        "newest=" + newest + " row0=" + pl[9] + " rows=" + pl[11] + " base=" + pl[5]
                                + " slide=" + pl[6] + " bufScroll=" + pl[8]);
            }
        }

        long[] v = consoleView();
        winT = (int) v[0];
        long[] s = stats(handle);
        final int hist = (int) s[15], rows = (int) (s[14] + hist);
        gate("the window is on the buffer's last row", winT == BUF_H - WIN_H, "winT=" + winT + " of " + BUF_H);
        final int base = winT - hist;              /* the model's anchor, while the view is still its own */
        gate("so the claim ends on the buffer's last row as well", base + rows == BUF_H,
                "base=" + base + " rows=" + rows + " of " + BUF_H
                        + ": there is no row below it left to write into, which is the premise of this case. And"
                        + " because the window is already on the last row, no slide can move that premise: every"
                        + " flush from here plans row0 == base and pays its debt with an eviction.");
        gate("nothing was declined or failed on the way down", s[2] == 0 && s[3] == 0,
                "declines=" + s[2] + " apiErrors=" + s[3]);

        int[] run = histRun(0, BUF_H);
        /* One line of the 400 rows is the cursor's own: every printed line ends in CRLF, and the last of those
           CRLFs scrolls in a fresh empty row for the cursor to sit on. So a packed buffer holds 399 lines of
           text and one blank, and the count below says so rather than assuming the rows are all text. */
        final int blank = 1;
        gate("the buffer is packed: every row but the cursor's own is a line of the session",
                run[2] == BUF_H - blank, "seen=" + run[2] + " first=HIST " + run[0] + " last=HIST " + run[1]
                        + " holes=" + ((BUF_H - blank) - run[2]) + " of which the first is row " + firstBlankRow());
        gate("and the row that is empty is the one the cursor sits on", firstBlankRow() == BUF_H - 1,
                "firstBlankRow=" + firstBlankRow() + ": a hole anywhere else is a line lost in the middle");
        gate("the run is unbroken and in order", run[3] == 0, "breaks=" + run[3]
                + ": HIST " + run[4] + " is the last line before row " + run[5]
                + ", which reads [" + (run[5] < 0 ? "-" : rowHead(run[5])) + "]");
        final int first = NLINES - (BUF_H - blank);
        gate("and the lines that left are the oldest " + first + ", not the newest",
                run[0] == first && run[1] == NLINES - 1,
                "first=HIST " + run[0] + " (want " + first + ") last=HIST " + run[1] + " (want " + (NLINES - 1) + ")");

        long[][] was = new long[BUF_H][];
        boolean readable = true;
        for (int r = 0; r < BUF_H; r++) {
            was[r] = row(r);
            if (was[r] == null) readable = false;
        }
        gate("every row is readable", readable, "the census below is worthless without this");
        if (!readable) {
            close(handle);
            handle = outer;
            return;
        }

        /* The user scrolls up over that, and one prompt line arrives -- the ordinary case of a program
           talking while somebody reads. The view is theirs, so the window may not move; the buffer is full,
           so the rows inside it may not stay. */
        if (setGeometry(BUF_W, BUF_H, WIN_W, WIN_H, DEF) == 0) {
            gate("the scroll", false, "setGeometry");
            close(handle);
            handle = outer;
            return;
        }
        v = consoleView();
        gate("the view is at the buffer's top now", v[0] == 0, "winT=" + v[0]);
        final int cells = (int) stats(handle)[5];
        paint("one prompt line into a full buffer", line + "\r\n");
        v = consoleView();
        s = stats(handle);
        final long[] pl = plan(handle);
        final int by = (int) pl[8];
        gate("the line is a buffer scroll the window could not pay", by > 0 && pl[6] == 0,
                "bufScroll=" + by + " slide=" + pl[6] + " winT@plan=" + pl[4] + " base=" + pl[5]);

        /* Row for row: what the user was reading is now where it must be if the buffer moved as a whole --
           every one of them `by` rows higher, in the same order, none rewritten in place. Compared against
           the capture rather than against a formula, because the paint below the anchor is the part that was
           already right and this is the part that was not. */
        int kept = 0, wrong = 0;
        StringBuilder why = new StringBuilder();
        for (int r = 0; r < base; r++) {
            long[] now = row(r), old = was[r + by];
            boolean diff = now == null || old == null || now.length != old.length;
            for (int c = 0; now != null && old != null && !diff && c < now.length; c++) diff = now[c] != old[c];
            if (diff) {
                wrong++;
                if (why.length() < 300 && wrong <= 4) {
                    why.append(" r").append(r).append("[").append(old == null ? "?" : head(old))
                            .append("->").append(now == null ? "?" : head(now)).append("]");
                }
            } else kept++;
        }
        gate("the " + base + " rows above the claim all rode up by exactly " + by, wrong == 0,
                "wrong=" + wrong + " kept=" + kept + " of " + base + ":" + why);
        run = histRun(0, BUF_H);
        gate("and the session is still one unbroken run of lines", run[3] == 0, "breaks=" + run[3]
                + ": HIST " + run[4] + " is the last line before row " + run[5]
                + ", which reads [" + (run[5] < 0 ? "-" : rowHead(run[5])) + "]"
                + " first=HIST " + run[0] + " last=HIST " + run[1]);
        gate("the oldest " + by + " more left the top, in order, nothing duplicated",
                run[0] == first + by && run[2] == (BUF_H - blank) - by,
                "first=HIST " + run[0] + " (want " + (first + by) + ") seen=" + run[2]
                        + " (want " + ((BUF_H - blank) - by) + ")");
        gate("the newest line the session has is still there", run[1] == NLINES - 1,
                "last=HIST " + run[1] + ": losing this one is the #34 defect, which kept the oldest and"
                        + " destroyed the newer");

        int found = findRow(line, base, BUF_H);
        gate("the prompt landed in the model's own rows", found >= base, "found=" + found + " anchor=" + base);
        if (found >= base) text("and it reads as it was printed", found, 0, line, DEF);
        gate("the window stayed where the user scrolled it", v[0] == 0, "winT=" + v[0]);
        gate("and the console cursor did not follow the output", v[5] == 0 && v[6] == 0,
                "(" + v[5] + "," + v[6] + ")");
        gate("nothing was declined instead", s[2] == 0, "declines=" + s[2]);
        gate("and no console call failed", s[3] == 0, "apiErrors=" + s[3]);
        System.out.println("  cost of one line into a full buffer: cells=" + (s[5] - cells)
                + " flushes=" + s[0] + " scrolls=" + s[6] + " evicted=" + by);

        close(handle);
        handle = outer;
    }

    /**
     * A keystroke is the one event that may move a window the user scrolled away from. Rule 2 forbids a
     * flush from doing it, and conhost pairs that ban with {@code SnapOnInput}: a key-down makes the cursor
     * visible again (input.cpp:171-178 -> screenInfo.cpp:1631-1666). The catch is that conhost fires that
     * snap only for a console in VTP mode, and this renderer exists for consoles where VTP is off -- so the
     * leg is ours or nobody's. {@code rc_snap_view} (Paint.cpp) decides, {@code snap} (RenderJni.cpp)
     * executes one {@code SetConsoleCursorPosition}, and WinSysTerminal calls it on a key-down.
     *
     * <p>Four things are pinned here, one per way getting them wrong is damage rather than a cosmetic miss:
     * <ul>
     * <li>the target is the model's <em>cursor</em> row, not the buffer's last one -- the least displacement
     * that reveals it. Aiming at the bottom instead would throw a user who had read one line of history past
     * everything above the prompt, which is why {@code want < BUF_H - 1} is asserted: it is the gate that
     * makes the two answers differ in the numbers, so a wrong implementation cannot pass by luck;</li>
     * <li>a snap writes no cell. The rows it reveals are the ones this model painted, and everything above
     * them is the user's scrollback, which has to come back byte-identical (the same {@code diffRows}
     * witness caseScrollKeepsHistory uses);</li>
     * <li>an invisible cursor means an application owns the screen, so a key must not drag the view under it
     * mid-frame (conhost's own guard, screenInfo.cpp:1728-1733, and the same one in rc_snap_view);</li>
     * <li>the displacement is least, and that is checkable as a number: the window returns to exactly the row
     * it held before the scroll. "the prompt drifted again" is the sound of this being wrong by one.</li>
     * </ul>
     *
     * <p>The enum below mirrors Paint.h's RC_SNAP_*, and the counter is asserted rather than only printed --
     * a window sitting on the model's rows is equally explainable by a scroll from somewhere else, so
     * nSnaps is the sole witness that the park actually reached the console.
     */
    private static void caseSnapOnInput() {
        final int NOGEOM = 0, NOCHANGE = 1, PARK = 2;   /* Paint.h, in rc_snap_view's order */
        final String PROMPT = "SQL > ready";
        long outer = handle;                            /* the parked model: alive, and main() reports it */
        handle = 0;
        /* Order-independent, as every case here: the previous one left the console wide and 300 rows deep. */
        if (setGeometry(BUF_W, BUF_H, WIN_W, WIN_H, DEF) == 0) {
            gate("snap geometry", false, "setGeometry");
            handle = outer;
            return;
        }
        handle = open(BUF_W, WIN_H, DEF);
        gate("a model with scrollback above it opened", handle != 0 && align(handle) == 1, null);
        if (handle == 0) { handle = outer; return; }
        flushQuietly();
        paint("clean start", "\u001b[0m\u001b[2J\u001b[H");
        winT = (int) consoleView()[0];

        /* Enough history to drive the claim well down -- sixty lines is not: the first thirty fill the
           viewport without sliding the window, and the model's own gutter swallows the next thirty, so the
           claim ends at row 1 and there is no scrollback left to protect. A hundred puts the anchor past the
           window's height, which is what makes "rows above the claim" a real band. And, unlike
           caseScrollKeepsHistory, a prompt line with no trailing newline, because that is the state a
           keystroke is typed into: the cursor parked on the model's last row, nothing owed. */
        final int CHUNK = 20, NLINES = 100;
        for (int i = 0; i < NLINES; i += CHUNK) {
            final int last = Math.min(i + CHUNK, NLINES) - 1;
            StringBuilder sb = new StringBuilder();
            for (int k = i; k <= last; k++) sb.append("SNAP ").append(k).append(" - rows to scroll to\r\n");
            paint("SNAP " + i + ".." + last, sb.toString());
        }
        paint("the prompt", PROMPT);

        long[] v = consoleView();
        winT = (int) v[0];
        long[] s = stats(handle);
        final int hist = (int) s[15];
        final int base = winT - hist;                        /* the model's anchor, while the view is its own */
        /* The row the prompt's ink is actually on, read off the buffer. That is the row a keystroke owes the
           user, and taking it from the console rather than from plan() is what stops this case from agreeing
           with a model that had simply recorded the wrong claim: the snap is judged against the ink. */
        final int want = findRow(PROMPT, 0, BUF_H);
        gate("the prompt was painted, in the rows the model claims", want >= base,
                "want=" + want + " anchor=" + base + " gutter=" + hist);
        gate("the window had slid down the buffer", winT > WIN_H, "winT=" + winT + " of " + BUF_H);
        gate("the model claims rows the user can scroll up to", base > WIN_H,
                "base=" + base + " gutter=" + hist);
        gate("the prompt is the window's bottom row, so a keystroke here costs nothing",
                want == winT + WIN_H - 1, "want=" + want + " winT=" + winT);
        gate("and it is not the buffer's last row", want < BUF_H - 1,
                "want=" + want + " of " + BUF_H + ": that equality is what would let a snap-to-bottom pass");
        final int snaps0 = (int) s[S_SNAP];
        gate("a keystroke with the prompt on screen answers NOCHANGE", snap(handle) == NOCHANGE, null);
        v = consoleView();
        gate("and moved nothing", v[0] == winT, "winT=" + v[0] + " was " + winT);
        gate("counting no snap either", (int) stats(handle)[S_SNAP] == snaps0, "snaps=" + stats(handle)[S_SNAP]);

        /* The user scrolls up to read what the session printed. setGeometry is the wheel: it leaves the
           window at (0,0) and the console cursor with it, and tells the renderer nothing. */
        long[][] was = new long[base][];
        boolean readable = true;
        for (int r = 0; r < base; r++) {
            was[r] = row(r);
            if (was[r] == null) readable = false;
        }
        gate("every scrollback row is readable", readable, "the diff below is worthless without this");
        if (!readable) { close(handle); handle = outer; return; }
        if (setGeometry(BUF_W, BUF_H, WIN_W, WIN_H, DEF) == 0) {
            gate("the scroll", false, "setGeometry");
            close(handle);
            handle = outer;
            return;
        }
        v = consoleView();
        final int oldWinT = winT;
        gate("the view is at the buffer's top now", v[0] == 0, "winT=" + v[0]);
        gate("and the prompt the user is about to type at is below it", want > v[0] + WIN_H - 1,
                "want=" + want + " winB=" + (v[0] + WIN_H - 1));
        s = stats(handle);
        final int cells = (int) s[5], aligns = (int) s[4], flushes = (int) s[0];
        gate("the keystroke snaps", snap(handle) == PARK, null);
        v = consoleView();
        s = stats(handle);
        gate("the window slid the least way that reveals the cursor's row",
                v[0] + WIN_H - 1 == want, "winT=" + v[0] + " winB=" + (v[0] + WIN_H - 1) + " want=" + want);
        gate("which is the row it was on before the scroll, so nothing drifted", v[0] == oldWinT,
                "winT=" + v[0] + " was " + oldWinT);
        gate("and the console cursor sits on that row", v[6] == want, "curY=" + v[6]);
        StringBuilder why = new StringBuilder();
        int changed = diffRows(was, 0, base, why);
        gate("the snap wrote none of the " + base + " scrollback rows", changed == 0,
                "changed=" + changed + why);
        gate("painted no cell either", (int) s[5] == cells, "cells=" + (s[5] - cells));
        gate("and did not re-adopt the console to do it", (int) s[4] == aligns, "aligns=" + s[4]);
        gate("nor flushed anything", (int) s[0] == flushes, "flushes=" + s[0]);
        gate("exactly one snap was counted", (int) s[S_SNAP] == snaps0 + 1, "snaps=" + s[S_SNAP]);
        gate("nothing was declined on the way", s[2] == 0, "declines=" + s[2]);
        gate("and no console call failed", s[3] == 0, "apiErrors=" + s[3]);

        /* Once the view has the row, a keystroke owes nothing again -- and this is the leg that keeps the
           next dozen keys from calling SetConsoleCursorPosition over a view that is already right. */
        gate("a second keystroke answers NOCHANGE", snap(handle) == NOCHANGE, null);
        v = consoleView();
        gate("with the window still where the first put it", v[0] == oldWinT, "winT=" + v[0]);
        gate("and still one snap in total", (int) stats(handle)[S_SNAP] == snaps0 + 1,
                "snaps=" + stats(handle)[S_SNAP]);

        /* ---- an application owns the screen now: a key must not move the view -------------------------
         * `?25l` is how vim, less and every alternate-screen program says so, and conhost reads the same
         * meaning (screenInfo.cpp:1728-1733). Without this guard a keystroke mid-repaint would slide the
         * window under a cursor the program had deliberately hidden, which is damage to a screen the
         * renderer is not painting. */
        paint("a program hides the cursor", "\u001b[?25l");
        v = consoleView();
        gate("the console's cursor is invisible now", v[7] == 0, "cursorOn=" + v[7]);
        if (setGeometry(BUF_W, BUF_H, WIN_W, WIN_H, DEF) == 0) {
            gate("the scroll away from a hidden cursor", false, "setGeometry");
            close(handle);
            handle = outer;
            return;
        }
        v = consoleView();
        gate("the user has scrolled up from the program's screen", v[0] == 0, "winT=" + v[0]);
        gate("so a keystroke refuses to move the view", snap(handle) == NOCHANGE, null);
        v = consoleView();
        gate("the window stayed at the buffer's top", v[0] == 0, "winT=" + v[0]);
        gate("and no snap was counted for it", (int) stats(handle)[S_SNAP] == snaps0 + 1,
                "snaps=" + stats(handle)[S_SNAP]);
        gate("the scrollback is still byte-identical through all of it",
                diffRows(was, 0, base, why) == 0, why.length() > 0 ? why.toString() : null);
        why.setLength(0);

        /* And the guard is a state, not a verdict for the rest of the session: the program gives the cursor
           back, the model knows it (Render.cpp keeps `cursorVisible` from `?25h`), and the very next key
           snaps again. A leg that latched the refusal would leave this user's prompt out of view forever. */
        paint("the program gives the cursor back", "\u001b[?25h");
        v = consoleView();
        gate("the console's cursor is visible again", v[7] == 1, "cursorOn=" + v[7]);
        gate("and the next keystroke snaps", snap(handle) == PARK, null);
        v = consoleView();
        gate("onto the prompt's row, at least displacement", v[0] + WIN_H - 1 == want,
                "winT=" + v[0] + " want=" + want);
        s = stats(handle);
        gate("two snaps counted in this session", (int) s[S_SNAP] == snaps0 + 2, "snaps=" + s[S_SNAP]);
        changed = diffRows(was, 0, base, why);
        gate("still no cell written by either", changed == 0, "changed=" + changed + why);
        why.setLength(0);
        gate("and the console never refused a call", s[3] == 0, "apiErrors=" + s[3]);
        System.out.println("  snap-on-input: window 0 -> " + v[0] + " twice, prompt row " + want
                + " of " + BUF_H + ", " + base + " scrollback rows intact");

        /* The last answer a snap can give, and the one a caller must not act on: the window is no longer the
           model's shape, so the row it would park to means something else on that console. render() reaches
           the same NOGEOM through rc_plan_paint and heals it by re-adopting; the key path has nothing to
           heal, because the next flush re-derives the view from the console anyway. */
        if (setGeometry(BUF_W, BUF_H, WIN_W, 24, DEF) == 0) {
            gate("the geometry for the shape-refusal leg", false, "setGeometry");
        } else {
            gate("a window that is not the model's shape answers NOGEOM", snap(handle) == NOGEOM, null);
        }

        close(handle);
        handle = outer;
    }

    /* open() refusing a console is a contract with the caller, and the number it leaves in openStatus()
       is the whole of it: NativeRenderer keeps the shipped Java writer on any 0, and its report line
       names the reason a rollout reads. Four of the five codes are reachable from explicit arguments, so
       all four are pinned here -- including which one wins when a shape is wrong in two ways at once,
       because a caller that names the wrong reason is worse than one that names none. The numbers are
       RenderJni.cpp's enum, mirrored as *private* constants in NativeRenderer.java:46; nothing but this
       case ties those two lists together, which is exactly why the literals are spelled out again here.
       Refusals must also not consume a model: the table is g_h[4] for the life of the process, so a leak
       would surface as a decline many chunks later, in a real session, pointing nowhere back here. */
    private static void caseOpenRefusal() {
        final int NO_CONSOLE = 1, BIG = 2, WIDE = 3, NO_GUTTER = 4, OOM = 5;
        final int MAX_COLS = 4096, MAX_ROWS = 256;      /* Render.h:36-37, and g_h[4] at RenderJni.cpp:104 */
        long outer = handle;                            /* parked, not closed */
        handle = 0;
        /* Order-independent: this case opens against the wide shape, so ask for it rather than relying on
           caseWideBuffer having left it in place. The parked model is never aligned again afterwards, so
           the console ending wide is the same as it was. */
        if (setGeometry(WIDE_BUF_W, WIDE_BUF_H, WIDE_WIN_W, WIN_H, DEF) == 0) {
            gate("wide geometry for the refusal case", false, "setGeometry");
            handle = outer;
            return;
        }

        gate("a buffer row past the model's maximum is refused",
                open(MAX_COLS + 1, WIN_H, DEF) == 0 && NativeRenderer.openStatus() == WIDE,
                "status=" + NativeRenderer.openStatus());
        gate("a zero-column model is refused, and as the shape case not the width case",
                open(-1, WIN_H, DEF) == 0 && NativeRenderer.openStatus() == BIG,
                "status=" + NativeRenderer.openStatus()
                        + ": note 0 cannot express this -- OPEN_ASK_SHAPE is 0, so cols==0 means 'ask the console'");
        gate("a window that leaves no room for a gutter is refused",
                open(WIDE_BUF_W, MAX_ROWS, DEF) == 0 && NativeRenderer.openStatus() == NO_GUTTER,
                "status=" + NativeRenderer.openStatus());
        gate("width is reported ahead of height when both are wrong",
                open(MAX_COLS + 1, MAX_ROWS, DEF) == 0 && NativeRenderer.openStatus() == WIDE,
                "status=" + NativeRenderer.openStatus());
        gate("a handle that is not a console is refused",
                NativeRenderer.open(-1L, WIDE_BUF_W, WIN_H, DEF) == 0
                        && NativeRenderer.openStatus() == NO_CONSOLE,
                "status=" + NativeRenderer.openStatus());

        /* The boundary the last three turn on: 255 rows still buys one row of gutter, so it must open.
           Close it -- an accepted handle left lying around would be the very leak the loop below claims
           refusals cannot cause, and the case would then be testing itself into a false green. */
        long edge = open(WIDE_BUF_W, MAX_ROWS - 1, DEF);
        gate("one row less is accepted: the limit is the gutter, not the screen", edge != 0,
                "status=" + NativeRenderer.openStatus());
        if (edge != 0) {
            close(edge);
        }

        /* One refused open proves the code; forty prove the refusal is not a slot. This is not a
           hypothetical: the first draft of this case asked for the shape sentinel (0) where it meant
           "zero columns", so those twenty calls opened twenty real models, filled g_h, and the probe
           after them came back OPEN_OOM. The accounting caught the mistake through the door this case
           is meant to guard, which is the best evidence it works. */
        boolean allRefused = true;
        for (int i = 0; i < 20; i++) {
            if (open(MAX_COLS + 1, WIN_H, DEF) != 0) allRefused = false;
            if (open(-1, WIN_H, DEF) != 0) allRefused = false;
        }
        gate("forty refusals burned no model", allRefused, null);
        long probe = NativeRenderer.open(0, WIDE_BUF_W, WIN_H, DEF);
        gate("so a real open still lands after them", probe != 0,
                "status=" + NativeRenderer.openStatus() + ": four slots, and a leak would show up here");
        if (probe != 0) {
            close(probe);
        }

        /* The other half of the same ledger: a full table must refuse with its own code rather than
           pretending, and close() must hand the model back. outer holds one slot already, so three more
           fill g_h[4] and the fourth is the census. */
        long[] held = new long[3];
        int heldN = 0;
        for (int i = 0; i < 3; i++) {
            long h = NativeRenderer.open(0, WIDE_BUF_W, WIN_H, DEF);
            if (h == 0) break;
            held[i] = h;
            heldN++;
        }
        gate("the three spare slots all took a model", heldN == 3, "held=" + heldN + " of 3");
        gate("a fifth model is refused, and says the table is full",
                NativeRenderer.open(0, WIDE_BUF_W, WIN_H, DEF) == 0 && NativeRenderer.openStatus() == OOM,
                "status=" + NativeRenderer.openStatus());
        if (heldN > 0) {
            close(held[0]);
            long back = NativeRenderer.open(0, WIDE_BUF_W, WIN_H, DEF);
            gate("closing one lets the next take its slot", back != 0, "status=" + NativeRenderer.openStatus());
            if (back != 0) close(back);
        }
        for (int i = 1; i < heldN; i++) close(held[i]);
        handle = outer;
    }

    /**
     * #44: a plan that landed part of itself and then had a run refused.
     *
     * The defect was in the tail of the flush, not in the failure: `rc_paint_done(g)` clears the whole dirty
     * array whatever happened to the runs, so a refusal left the model claiming rows it had never written,
     * and its next frame contained them not. Nothing on screen distinguishes that from a chunk nobody ever
     * asked for -- it shows only in what the *following* flush decides to paint. So this leg's job is to
     * make a real WriteConsoleOutputW fail in the middle of a plan, which no console state can be talked
     * into, and then read the next flush's cells.
     *
     * It runs on its own handle, last in the list, and restores the wide shape the case before it left:
     * the session handle's counters are asserted by the census at the end of main(), and an armed fault in
     * that handle would read as a console call that failed and was papered over -- which is the very thing
     * the census forbids.
     */
    private static void casePartialPaintFailure() {
        if (setGeometry(BUF_W, BUF_H, WIN_W, WIN_H, DEF) == 0) {
            gate("standard geometry for the fault leg", false, "setGeometry");
            return;
        }
        long h = open(BUF_W, WIN_H, DEF);
        if (h == 0) { gate("a second model for the fault", false, "open=" + h); return; }
        align(h);
        final char[] clear = "\u001b[0m\u001b[2J\u001b[H".toCharArray();
        feed(h, clear, 0, clear.length);
        flush(h);
        NativeRenderer.sgr(h);
        final int top = (int) consoleView()[0];

        /* Two rows, far apart: a run is one rectangle of consecutive rows, so one chunk that damages rows
           2 and 11 is the smallest plan with a middle to fail in. FIRST is the run that must land, SECOND
           the one that must not. */
        final char[] chunk = "\u001b[3;1HFIRST\u001b[12;1HSECOND".toCharArray();
        long[] a = stats(h);
        gate("the fault arms on the plan's second run", faultRect(h, 1) == 1, "armed=" + faultRect(h, 1));
        feed(h, chunk, 0, chunk.length);
        int r = flush(h);
        NativeRenderer.sgr(h);
        long[] b = stats(h);
        gate("a flush that landed one run is still accepted", r == 0, "flush=" + r);
        gate("the refused run is counted as the console call it was", b[3] - a[3] == 1,
                "apiErrors=" + (b[3] - a[3]));
        long[] pl = plan(h);
        gate("the plan really did have two runs", pl[15] == 2, "runs=" + pl[15]
                + ": one run would make this a whole failure, not a partial one");
        text("the run that landed is on the console", top + 2, 0, "FIRST", DEF);
        cell("and the run after it is not", top + 11, 0, ' ', DEF);

        /* The witness. rc_paint_done ran, so a model that stopped here believes row 11 holds SECOND; the fix
           is the rc_drop_base that follows it, which re-marks every row and so puts row 11 back in the *next*
           plan. Without the drop, a chunk about somewhere else entirely paints row 19 and row 11 stays blank
           for the rest of the session -- and a cell read taken now, not later, is the only thing that can
           tell those two apart. */
        a = b;
        final char[] one = "\u001b[20;1HZ".toCharArray();
        feed(h, one, 0, one.length);
        gate("the next chunk is accepted", flush(h) == 0, null);
        NativeRenderer.sgr(h);
        b = stats(h);
        pl = plan(h);
        text("the row the refusal stranded came back unprompted", top + 11, 0, "SECOND", DEF);
        cell("with the character this chunk actually asked for", top + 19, 0, 'Z', DEF);
        gate("and it cost no second console failure", b[3] - a[3] == 0, "apiErrors=" + (b[3] - a[3]));
        gate("the fault was one-shot: nothing is armed now", faultRect(h, -1) == -1,
                "armed=" + faultRect(h, -1));
        close(h);
    }

    /**
     * HPR ({@code CSI a}) and VPR ({@code CSI e}) on a real screen. ConEmu has no case for either final --
     * they reach its {@code default:} and DumpUnknownEscape -- so on the fallback leg these bytes move
     * nothing at all, which is exactly the state a cell witness can tell apart from "parsed and obeyed".
     * The leg that matters is the pair on the region's bottom row: CUD is clipped there by DECSTBM and VPR
     * walks straight past it, the one behavioural difference MSFT spells out in the comment on each
     * ("Unlike CUD, this is not constrained by margin settings", adaptDispatch.cpp:427/:437).
     */
    private static void caseRelativeCursor() {
        /* DECSTBM at rows 13..16 and both moves measured from inside the viewport: on whatever shape an
           earlier case ended on -- caseNoScrollback leaves a window with no room to slide, and a window
           shorter than row 16 makes every one of these rows land outside it -- winT + 15 is not a row the
           screen has, and the leg reports a geometry problem as a motion problem. */
        if (!standardGeometry("the relative-motion leg")) return;
        final long[] a = stats(handle);
        /* A region of model rows 12..15, and the cursor on its bottom row. Everything below starts there, so
           the two moves are the same distance from the same place and only the margin rule differs. */
        paint("a region and its bottom row", "\u001b[0m\u001b[13;16r\u001b[16;1H");
        long[] v = consoleView();
        gate("the region put the cursor on its bottom row", v[5] == 0 && v[6] == winT + 15,
                "(" + v[5] + "," + v[6] + ") winT=" + winT);
        paint("CUD is clipped by the region", "\u001b[BX");
        text("the clipped CUD printed on the region's bottom row", winT + 15, 0, "X", DEF);
        paint("VPR walks past it", "\u001b[2eY");
        /* VPR is vertical only: it carries the column with it, and X had left the cursor on column 1. So Y
           lands on column 1 of the row two past the region's bottom -- the row CUD could not reach, at a column
           VPR did not touch. Both halves of that claim are on the screen, and a horizontal move would have
           written at column 0. */
        text("the row below the region holds VPR's character", winT + 17, 1, "Y", DEF);
        cell("in the column the cursor was already in", winT + 17, 0, ' ', DEF);
        cell("and the row the region ended on is untouched", winT + 16, 0, ' ', DEF);
        paint("HPR", "\u001b[5aZ");
        text("HPR moved the column on the same row", winT + 17, 7, "Z", DEF);
        cell("leaving the cells it stepped over alone", winT + 17, 6, ' ', DEF);
        cell("from the very first of them", winT + 17, 3, ' ', DEF);
        v = consoleView();
        gate("the cursor is where the two moves say it is", v[5] == 8 && v[6] == winT + 17,
                "(" + v[5] + "," + v[6] + ") want (8," + (winT + 17) + ")");
        paint("both clamp to the viewport", "\u001b[999e\u001b[999a");
        v = consoleView();
        gate("VPR stops at the last row, HPR at the last column",
                v[5] == WIN_W - 1 && v[6] == winT + WIN_H - 1,
                "(" + v[5] + "," + v[6] + ") want (" + (WIN_W - 1) + "," + (winT + WIN_H - 1) + ")");
        final long[] b = stats(handle);
        /* The census is what distinguishes this from a silent regression elsewhere: an unmodelled final would
           have shown up here as two more counts, and the whole point of implementing the pair is that it is
           no longer one. */
        gate("neither final is counted as unsupported", b[S_UN] - a[S_UN] == 0,
                "RC_UN_SUP +" + (b[S_UN] - a[S_UN]));
        gate("and nothing was declined on their account", b[2] - a[2] == 0, "declines +" + (b[2] - a[2]));
        paint("region back to the whole viewport", "\u001b[r");
    }

    /**
     * DECSET 2026 -- the synchronized region, on the console rather than in the model. The claim being
     * witnessed is not "the bit flipped" (the host gate has that) but that a region costs the screen
     * <em>nothing</em> until it closes, and then exactly one paint for everything inside it. jline4's
     * {@code Display} wraps every full-screen update in BSU/ESU, so "rectangle count 0 during the region" is
     * the difference between a table that arrives in one frame and one that flickers into existence.
     * <p>
     * The timeout leg is the safety valve, and the only one that can be driven from a test: an application
     * that dies between its BSU and its ESU must leave a terminal that keeps updating.
     */
    private static void caseSyncOutput() {
        /* The console this case needs is one with scrollback: a region that cannot slide its window is a region
           where the gutter valve fires on every frame, and the legs below are about deferral, not pressure. The
           earlier cases leave whatever shape they ended on, so this takes its own -- see caseNoScrollback. */
        if (!standardGeometry("the synchronized-region leg")) return;
        long[] a = stats(handle);
        paint("BSU on its own", "\u001b[0m\u001b[?2026h");
        long[] b = stats(handle);
        gate("the region is open", b[S_SYNC_ON] == 1, "sync=" + b[S_SYNC_ON]);
        gate("and counted as one region", b[S_SYNC_ENGAGES] - a[S_SYNC_ENGAGES] == 1,
                "engages=" + (b[S_SYNC_ENGAGES] - a[S_SYNC_ENGAGES]));
        /* A chunk that only moves state has no plan to hold, and counting it as a held frame would make the
           census claim deferred pictures that were never candidates for one. */
        gate("but a chunk with nothing to paint is not held", b[S_SYNC_HELD] - a[S_SYNC_HELD] == 0,
                "held=" + (b[S_SYNC_HELD] - a[S_SYNC_HELD]));
        gate("and the console saw no rectangle either", b[1] - a[1] == 0, "rects=" + (b[1] - a[1]));

        paint("a second BSU inside it", "\u001b[?2026h");
        b = stats(handle);
        gate("does not stack a region", b[S_SYNC_ON] == 1 && b[S_SYNC_ENGAGES] - a[S_SYNC_ENGAGES] == 1,
                "engages=" + (b[S_SYNC_ENGAGES] - a[S_SYNC_ENGAGES]));
        gate("but is counted as the nesting it was", b[S_SYNC_NESTED] - a[S_SYNC_NESTED] == 1,
                "nested=" + (b[S_SYNC_NESTED] - a[S_SYNC_NESTED]));

        /* Close what the state legs opened, and time the console while it is shut: a probe inside a region
           measures a held flush, which costs the console nothing, and the number would be a lie about the
           host. The leg below is the only one in this case whose claim depends on wall-clock time. */
        paint("end the state legs' region", "\u001b[?2026l");
        final long cost = chunkCostMs();
        /* SYNC_CLOCK_MS is Render.h's RC_SYNC_TIMEOUT_MS, and the clock starts on the region's first held
           flush, so a second chunk that has to be held as well must arrive inside the remaining window. Two
           chunks' worth of cost leaves the leg no margin on a console slower than that, and there the honest
           version of the claim is the one chunk it can still witness. */
        final int nhold = 2 * cost < SYNC_CLOCK_MS ? 2 : 1;
        if (nhold == 1) {
            System.out.println("  one-chunk hold leg: a chunk costs " + cost + "ms on this console"
                    + " and the region's clock is " + SYNC_CLOCK_MS + "ms");
        }
        a = stats(handle);
        paint("a region and its first row", "\u001b[0m\u001b[?2026h\u001b[21;1HHELD-A");
        if (nhold == 2) paint("and its second row", "\u001b[23;1HHELD-B");
        b = stats(handle);
        gate("every chunk of the region was held", b[S_SYNC_HELD] - a[S_SYNC_HELD] == nhold,
                "held=" + (b[S_SYNC_HELD] - a[S_SYNC_HELD]) + " want " + nhold);
        gate("and none of it reached the console", b[1] - a[1] == 0, "rects=" + (b[1] - a[1]));
        cell("the screen still does not have the first row", winT + 20, 0, ' ', DEF);
        if (nhold == 2) cell("nor the second", winT + 22, 0, ' ', DEF);

        paint("ESU", "\u001b[?2026l");
        b = stats(handle);
        text("the row arrives on the flush that closed the region", winT + 20, 0, "HELD-A", DEF);
        if (nhold == 2) text("the second one with it", winT + 22, 0, "HELD-B", DEF);
        /* One flush for the whole region, and one rectangle per row it held -- the rows did not arrive as
           they were written. That is the difference between a table in one frame and a table flickering into
           existence, which is the reason the mode exists. */
        gate("in one paint, not one per chunk", b[1] - a[1] == nhold, "rects=" + (b[1] - a[1]));
        gate("and the region is closed", b[S_SYNC_ON] == 0, "sync=" + b[S_SYNC_ON]);
        gate("no timeout was needed for any of it", b[S_SYNC_TIMEOUT] - a[S_SYNC_TIMEOUT] == 0,
                "timeouts=" + (b[S_SYNC_TIMEOUT] - a[S_SYNC_TIMEOUT]));

        /* A BSU with no ESU. The release is the *next* flush after the clock runs out, which is also the only
           clock this seam has -- so the leg sleeps, then asks for a frame, and expects that frame to carry
           the row that was sitting in the model. */
        a = stats(handle);
        paint("a region nobody closes", "\u001b[?2026h\u001b[25;1HLEAKED");
        b = stats(handle);
        gate("its row is held", b[S_SYNC_HELD] - a[S_SYNC_HELD] == 1 && b[S_SYNC_ON] == 1,
                "held=" + (b[S_SYNC_HELD] - a[S_SYNC_HELD]) + " sync=" + b[S_SYNC_ON]);
        cell("and not on the screen", winT + 24, 0, ' ', DEF);
        /* Past Render.h's RC_SYNC_TIMEOUT_MS (100), which this gate cannot read from Java. A leg that slept
           half as long would be asserting that the timeout is *at least* this big, not that it fired. */
        sleep(200);
        paint("a later chunk, past the timeout", "\u001b[26;1HLATER");
        b = stats(handle);
        text("the leaked row painted with it", winT + 24, 0, "LEAKED", DEF);
        text("and so did the one that broke the wait", winT + 25, 0, "LATER", DEF);
        gate("the timeout fired once", b[S_SYNC_TIMEOUT] - a[S_SYNC_TIMEOUT] == 1,
                "timeouts=" + (b[S_SYNC_TIMEOUT] - a[S_SYNC_TIMEOUT]));
        gate("and it cleared the mode, so the next frame is not held too", b[S_SYNC_ON] == 0,
                "sync=" + b[S_SYNC_ON]);

        /* A query asked inside a region. Its answer belongs to the reader, and a terminal that held replies
           with the picture would hang the program that is waiting for one -- so this is the leg that proves
           the hold is about the screen and not about the flush. */
        a = stats(handle);
        readInput(0);                                 /* the CPR below is the only thing in this queue */
        paint("a CPR inside a region", "\u001b[0m\u001b[?2026h\u001b[28;1H\u001b[6n\u001b[28;14HPAID");
        final String got = input(64);
        b = stats(handle);
        gate("the reply came while the picture was held",
                got.contains("\u001b[28;1R") && b[S_SYNC_HELD] - a[S_SYNC_HELD] >= 1,
                "got=" + vis(got) + " held=" + (b[S_SYNC_HELD] - a[S_SYNC_HELD]));
        cell("and the row is still off screen", winT + 27, 13, ' ', DEF);
        paint("close it", "\u001b[?2026l");
        text("the region's text lands when it closes", winT + 27, 13, "PAID", DEF);
    }

    /**
     * The hold's capacity limit, which is the console's and not the region's. A synchronized region defers
     * paints while the model keeps scrolling, and the console follows a scrolling model by sliding its window
     * up its own buffer -- {@code rows - winRows} rows of slide, and then no more. Past that the console has to
     * scroll for real, which throws away its top row, and a frame that was never painted cannot be recovered
     * from anywhere. So scroll_up's own relief valve outranks the mode, and this case is the witness that it
     * does: a region longer than the gutter has to put pictures on the screen <em>before</em> its ESU.
     * <p>
     * The gutter is not a number this case invents -- {@code plan()[11] - plan()[12]} is the model's own, and
     * the model's is one viewport, because that is what {@code open()} gives it (RenderJni.cpp, "a gutter as
     * tall as the viewport"). On the standard geometry that is 30 rows, so the leg runs 72 lines and expects
     * the valve two chunks in.
     * <p>
     * Asserting on the counter alone would not be enough — {@code overflow > 0} is a claim about the model's
     * arithmetic. The claim about the console is that the newest line of the chunk which forced a paint is
     * inside the window at that moment, and it is checked on every forced paint rather than inferred at the end.
     */
    private static void caseSyncOverflow() {
        if (!standardGeometry("the gutter-pressure leg")) return;
        paint("a clean viewport, no region", "\u001b[0m\u001b[?2026l\u001b[2J\u001b[H");
        long[] pl = plan(handle);
        final int winRows = (int) pl[12];
        final int gutter = (int) (pl[11] - pl[12]);
        if (gutter <= 0) {
            System.out.println("  skip the gutter-pressure leg: this model has no room to slide into");
            return;
        }
        /* One line per model row, plus the window's own height to get the cursor to the bottom before the
           first scroll: that is where pendingScrolls reaches the gutter from a fresh viewport. The margin past
           it is what makes the leg repeat the thing being tested rather than hit it once. */
        final int nlines = gutter + winRows + 12;
        final long[] a = stats(handle);
        int paintedDuring = 0;                    /* chunks that painted with the mode open */
        for (int i = 0; i < nlines; i += 20) {
            final int last = Math.min(i + 20, nlines) - 1;
            StringBuilder sb = new StringBuilder(i == 0 ? "\u001b[0m\u001b[?2026h" : "");
            for (int k = i; k <= last; k++) sb.append(rowTag(k)).append("\r\n");
            final long[] s = stats(handle);
            final int open = (int) s[S_SYNC_ON];
            final long rects = s[1];
            paint("region lines " + i + ".." + last, sb.toString());
            if (open == 1 && stats(handle)[1] > rects) paintedDuring++;
        }
        long[] b = stats(handle);
        final long over = b[S_SYNC_OVERFLOW] - a[S_SYNC_OVERFLOW];
        final long blew = b[S_SYNC_TIMEOUT] - a[S_SYNC_TIMEOUT];
        /* The counter is the claim about the model's arithmetic; this is the claim about the console: the
           screen changed while the region was still open. Without the valve the whole region would be one held
           frame and every one of these chunks would have painted nothing. */
        gate("the gutter forced frames before the ESU", paintedDuring >= 1,
                "paintedChunks=" + paintedDuring + " over " + nlines + " lines and a " + gutter + "-row gutter");
        gate("and some chunks really were deferred", b[S_SYNC_HELD] - a[S_SYNC_HELD] >= 1,
                "held=" + (b[S_SYNC_HELD] - a[S_SYNC_HELD]));
        /* Every frame the region lost is explained by one of the two hatches, and the two are mutually
           exclusive in the flush that produces them -- a full gutter is not also a timed-out clock. A chunk
           that painted for a third reason while the mode was open is a bug this catches; a chunk that painted
           after the clock ended the region is not counted at all, which is why the tally is over the chunks
           that started with the mode on. */
        gate("each one was the valve or the clock, and only once", over + blew == paintedDuring,
                "overflow=" + over + " timeout=" + blew + " painted=" + paintedDuring);
        gate("the valve fired at least once", over >= 1,
                "overflow=" + over + " painted=" + paintedDuring);
        /* The distinction between the two hatches, stated on the console: filling the gutter paints this
           frame and leaves the region open, while the clock is the release of a region nobody closed and it
           clears the mode. Only the second can explain the region being shut here. */
        gate("a frame lost to the gutter does not end the region", b[S_SYNC_ON] == 1 || blew >= 1,
                "sync=" + b[S_SYNC_ON] + " overflow=" + over + " timeout=" + blew);
        final long rectsAtClose = b[1];
        paint("close it", "\u001b[?2026l");
        b = stats(handle);
        gate("the ESU found nothing left to defer", b[S_SYNC_ON] == 0, "sync=" + b[S_SYNC_ON]);
        gate("and no console call failed on the way", b[3] - a[3] == 0, "apiErrors=" + (b[3] - a[3]));

        /* The convergence claim, and the one that would be lost if the valve had swallowed a scroll: every row
           the window shows is a row of this region's output, in order, with no gap. Reading the last line and
           then walking up from it is deliberate -- findRow gives the row the console really put it on, so the
           walk checks the window's own geometry rather than a row number this test computed. */
        pl = plan(handle);
        final int at = findRow(rowTag(nlines - 1), winT, winT + (int) pl[12]);
        gate("the region's last line is on the screen", at >= 0,
                "want " + rowTag(nlines - 1) + " in rows " + winT + ".." + (winT + (int) pl[12]));
        if (at >= 0) {
            for (int k = 1; k < winRows - 1 && nlines - 1 - k >= 0; k++)
                text("row " + k + " above it is the line before", at - k, 0, rowTag(nlines - 1 - k), DEF);
        }
    }

    /** The region lines of {@link #caseSyncOverflow}, fixed-width so no two of them share a prefix. */
    private static String rowTag(int i) {
        return "OVERFLOW-" + (i < 10 ? "000" : i < 100 ? "00" : i < 1000 ? "0" : "") + i;
    }

    /**
     * Put the console back at the shape the gate opened with and hand {@code handle} a model that matches it,
     * blanking the viewport so a case that reads cells does not have to know what the previous one left there.
     * Returns false -- having said so -- when the geometry cannot be had, which is the only way a leg can be
     * skipped rather than silently wrong.
     */
    private static boolean standardGeometry(String what) {
        if (setGeometry(BUF_W, BUF_H, WIN_W, WIN_H, DEF) == 0) {
            gate(what + ": standard geometry", false, "setGeometry");
            return false;
        }
        final long outer = handle;
        handle = open(BUF_W, WIN_H, DEF);
        gate(what + ": a model over the standard window", handle != 0 && align(handle) == 1, null);
        if (handle == 0) { handle = outer; return false; }
        close(outer);
        flushQuietly();
        paint(what + ": blank start", "\u001b[0m\u001b[2J\u001b[H");
        winT = (int) consoleView()[0];
        return true;
    }
}

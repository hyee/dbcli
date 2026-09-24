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
    /** Drain up to `max` characters off the console's input stream -- the witness for a DSR/DA reply. */
    static native char[] readInput(int max);
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

    private static long open(int cols, int rows, int defAttr) {
        return NativeRenderer.open(0, cols, rows, defAttr);   /* 0: the DLL opens CONOUT$ itself */
    }

    private static int feed(long h, char[] t, int off, int len) { return NativeRenderer.feed(h, t, off, len); }
    private static int flush(long h) { return NativeRenderer.flush(h); }
    private static int align(long h) { return NativeRenderer.align(h); }
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
       Java_com_hyee_ansirender_NativeRenderer_stats for why that one does not fold at close(). */
    private static final int S_UN = 17, S_COLON = S_UN + 10, S_TITLES = S_UN + 11,
            S_TITLES_TRUNC = S_UN + 12, S_TITLES_APPLIED = S_UN + 13, S_ALT = S_UN + 14,
            S_ALT_FAIL = S_UN + 15, S_PROMPTS = S_UN + 16, S_EXIT = S_UN + 17,
            S_REPLIED = S_UN + 18, S_REPLY_FAIL = S_UN + 19, S_REPLY_FULL = S_UN + 20,
            S_LEN = S_UN + 21;

    public static void main(String[] args) {
        System.out.println("render build: " + NativeRenderer.build());
        if (prepareConsole() == 0) { System.out.println("FAIL cannot prepare a console"); System.exit(1); }
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
        caseOpenRefusal();

        long[] s = stats(handle);
        gate("no console call failed", s[3] == 0, "apiErrors=" + s[3] + " lastError check below");
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
                    + s[S_REPLY_FULL] + " refused for a full queue)");
        }
        close(handle);
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
        gate(what + ": accepted", r == 0 || r == 1, "flush=" + r);
    }

    private static void flushQuietly() { flush(handle); drainSgr(); }

    private static void drainSgr() { NativeRenderer.sgr(handle); }

    // ---- witnesses ---------------------------------------------------------------------------

    /** one buffer row, read fresh: a repaint of the same row must not be compared against a cache */
    private static long[] row(int bufRow) {
        return readCells(0, bufRow, BUF_W, 1);
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
        paint("a colon colour", "\u001b[38:2::1:2:3m");
        b = stats(handle);
        gate("the colon form has its own counter", b[S_COLON] - a[S_COLON] == 1,
                "colon=" + (b[S_COLON] - a[S_COLON]));
        gate("and buys no repaint", b[4] - a[4] == 0, "aligns=" + (b[4] - a[4])
                + ": a dropped colour moves no cursor, so it must not cost a window repaint");
        gate("it was not counted as a mode set", b[S_UN + 4] - a[S_UN + 4] == 0,
                "mode=" + (b[S_UN + 4] - a[S_UN + 4]));

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
}

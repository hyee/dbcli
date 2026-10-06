import com.hyee.ansirender.NativeRenderer;

public class Render {

    static { System.loadLibrary("render"); }
    static native int prepareConsole();
    static native int setGeometry(int bufW, int bufH, int winW, int winH, int attr);
    static native long[] readCells(int x, int y, int w, int h);
    static native long[] consoleView();
    static native char[] consoleTitle();
    static native int consolePalette(long[] out16);
    static native char[] readInput(int max);
    static native String[] censusNames();
    static native int writeHk(char[] text, int len, String dll);
    static native int readopt(long h);
    static native long[] plan(long h);
    static native long[] inputMode(long h);
    static native char[] mouseReport(long h, int x, int y, int px, int py,
                                    int buttonState, int eventFlags, int ctrlKeyState, int inject);
    static native char[] focusReport(long h, int focused, int inject);
    static native long[] outputMode(long h);
    static native int faultRect(long h, int run);
    static native String validateGrid(long h);
    static native long argTrunc(long h);

    private static long open(int cols, int rows, int defAttr) {
        return NativeRenderer.open(0, cols, rows, defAttr);
    }

    private static int feed(long h, char[] t, int off, int len) { return NativeRenderer.feed(h, t, off, len); }
    private static int flush(long h) { return NativeRenderer.flush(h); }
    private static int align(long h) { return NativeRenderer.align(h); }
    private static int snap(long h) { return NativeRenderer.snap(h); }
    private static long[] stats(long h) { return NativeRenderer.stats(h); }
    private static void close(long h) { NativeRenderer.close(h); }

    static final int BUF_W = 200, BUF_H = 400, WIN_W = 100, WIN_H = 30, DEF = 0x07;
    static final int WIDE_BUF_W = 2000, WIDE_BUF_H = 300, WIDE_WIN_W = 120;

    private static long handle;
    private static boolean shapePresentArmRan;
    private static int checks, failures;
    private static int winT;

    // BEGIN SLOT TABLE (generated from Render.h by gen_statslots.py -- build.sh verifies)
    private static final int S_UN = 17;
    private static final int S_TITLES = 30;
    private static final int S_TITLES_TRUNC = 31;
    private static final int S_TITLES_APPLIED = 32;
    private static final int S_ALT = 33;
    private static final int S_ALT_FAIL = 34;
    private static final int S_PROMPTS = 35;
    private static final int S_EXIT = 36;
    private static final int S_REPLIED = 37;
    private static final int S_REPLY_FAIL = 38;
    private static final int S_REPLY_FULL = 39;
    private static final int S_SNAP = 40;
    private static final int S_SYNC_ENGAGES = 41;
    private static final int S_SYNC_NESTED = 42;
    private static final int S_SYNC_HELD = 43;
    private static final int S_SYNC_TIMEOUT = 44;
    private static final int S_SYNC_OVERFLOW = 45;
    private static final int S_SYNC_DECLINED = 46;
    private static final int S_SYNC_ON = 47;
    private static final int S_CLIP_ARMED = 48;
    private static final int S_CLIP_DECODE = 49;
    private static final int S_CLIP_SELECTION = 50;
    private static final int S_CLIP_READ = 51;
    private static final int S_CLIP_WRITES = 52;
    private static final int S_CLIP_FAILS = 53;
    private static final int S_CLIP_POLICY = 54;
    private static final int S_ARGTRUNC = 55;
    private static final int S_BP = 56;
    private static final int S_SHAPE = 57;
    private static final int S_LEN = 58;
    // END SLOT TABLE (generated)
    private static final int S_COLON = S_UN + 10;   /* readability alias: the 11th census family */

    public static void main(String[] args) {
        System.out.println("render build: " + NativeRenderer.build());
        if (prepareConsole() == 0) { System.out.println("FAIL cannot prepare a console"); System.exit(1); }
        System.out.println("console: " + (NativeRenderer.isPseudoConsole()
                ? "pseudo (ConPTY) -- the cell witness below is not testing what it looks like"
                : "the gate's own conhost window"));
        if (setGeometry(BUF_W, BUF_H, WIN_W, WIN_H, DEF) == 0) {
            System.out.println("FAIL cannot set console geometry"); System.exit(1);
        }
        handle = open(BUF_W, WIN_H, DEF);
        if (handle == 0) { System.out.println("FAIL open returned no handle"); System.exit(1); }
        gate("align adopts the console", align(handle) == 1, null);
        flushQuietly();
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
        caseWinchPrompt();
        caseAdoptReadOnly();
        caseNoScrollback();
        caseHookDecline();
        caseWideBuffer();
        caseScrollKeepsHistory();
        caseFullBufferEvicts();
        caseSnapOnInput();
        caseOpenRefusal();
        casePartialPaintFailure();
        caseEditRows();
        caseEchClamp();
        caseHealPairs();
        caseSoftReset();
        caseArgClamp();
        caseMargins();
        caseBracketedPaste();
        caseSgrStack();
        caseXtModes();
        caseRectFamily();
        caseMouseModes();
        caseCursorKeys();
        caseDeccolm();
        caseOsc9Family();
        caseMouseArm();
        caseInputReports();
        caseVtp();
        caseCharset();
        caseCursorShape();
        caseTabStops();
        caseInsert();
        caseColon();
        caseWindowOps();
        caseInbandResize();
        caseRelativeCursor();
        caseSyncOutput();
        caseSyncOverflow();
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
        gate("stats() is exactly this gate's slot table", s.length == S_LEN,
                "length=" + s.length + " against a table of " + S_LEN + ": "
                        + (s.length == S_LEN ? "the two agree"
                                : s.length < S_LEN ? "render.dll is older than this gate"
                                : "render.dll reports slots this gate does not read"));
        final String[] LABELS = { "unrecognised", "decstbm", "altbuf", "mouse", "mode", "bracketed paste",
                "osc9", "other osc", "dcs", "report", "colon", "osc clip", "charset" };
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
        reportSlotAgrees("SLOT_ARGTRUNC", S_ARGTRUNC);
        reportSlotAgrees("SLOT_BP", S_BP);
        reportSlotAgrees("SLOT_SHAPE", S_SHAPE);
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
                    + "; cursor-shape PRESENT arm: "
                    + (shapePresentArmRan ? "RAN" : "NOT WITNESSED (this kernel32 does not export SetConsoleCursorShape)")
                    + "; sync updates=" + s[S_SYNC_ENGAGES] + " (" + s[S_SYNC_NESTED] + " nested, "
                    + s[S_SYNC_HELD] + " flushes held, ended early by " + s[S_SYNC_TIMEOUT] + " timeout / "
                    + s[S_SYNC_OVERFLOW] + " gutter / " + s[S_SYNC_DECLINED] + " decline)"
                    + "; parameters dropped=" + s[S_ARGTRUNC]
                    + "; bracketed paste=" + (s[S_BP] != 0 ? "agreed" : "not agreed"));
        }
        close(handle);
        if (paletteBefore != null) {
            final long[] after = palette();
            gate("close() handed the console back the palette it found",
                    after != null && paletteDiff(after, paletteBefore, -1) == null,
                    after == null ? "unreadable" : String.valueOf(paletteDiff(after, paletteBefore, -1)));
        }
        if (vtpBase >= 0) {
            final long[] left = outputMode(0);
            gate("close() handed the console back its own escape parser", left[0] == vtpBase,
                    "left=0x" + Long.toHexString(left[0]) + " base=0x" + Long.toHexString(vtpBase)
                            + ": a renderer that quit and left the host's parser switched off would make"
                            + " every later program in this console print escape sequences as text");
        } else {
            gate("the VTP leg recorded a base to return to", false, "vtpBase=" + vtpBase);
        }
        System.out.println("checks=" + checks + " failures=" + failures);
        if (failures > 0) { System.out.println("RENDERGATE: FAILED"); System.exit(1); }
        System.out.println("RENDERGATE: ok");
    }

    private static void paint(String what, String s) {
        char[] c = s.toCharArray();
        if (feed(handle, c, 0, c.length) == 0) { gate(what + ": feed", false, "feed returned 0"); return; }
        int r = flush(handle);
        drainSgr();
        winT = (int) consoleView()[0];
        gate(what + ": accepted", r == 0 || r == 1 || r == 3, "flush=" + r);
        gridClean(what);
    }

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

    private static long[] row(int bufRow) {
        return readCells(0, bufRow, BUF_W, 1);
    }

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

    private static void tail(String what, int bufRow, int from, int attr) {
        for (int c = from; c < BUF_W; c++) cell(what, bufRow, c, ' ', attr);
    }

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

    private static void gotoRow(int modelRow) {
        paint("goto " + modelRow, "\u001b[" + (modelRow + 1) + ";1H");
    }

    private static String input(int max) {
        char[] c = readInput(max);
        return c == null ? "<unreadable>" : new String(c);
    }

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

    private static void eqInput(String what, String want) {
        final String got = input(256);
        gate(what, got.equals(want), "got=" + vis(got) + " want=" + vis(want));
    }

    private static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
        }
    }

    private static final int SYNC_CLOCK_MS = 100;

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

    private static void casePlainText() {
        gotoRow(0);
        paint("plain text", "hello world");
        text("plain", winT, 0, "hello world", DEF);
        tail("plain tail", winT, 11, DEF);
        long[] v = consoleView();
        gate("plain leaves the cursor at (11, winT)", v[5] == 11 && v[6] == winT,
                "(" + v[5] + "," + v[6] + ") winT=" + winT);
    }

    private static void caseColour() {
        gotoRow(1);
        paint("colour", "\u001b[31mRED\u001b[0m plain");
        text("red", winT + 1, 0, "RED", 0x04);
        text("reset", winT + 1, 3, " plain", DEF);
        tail("colour tail", winT + 1, 9, DEF);
    }

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
        text("echo bold", winT + 3, 3, " bold", 0x0C);
        text("echo after reset", winT + 3, 8, " tail", DEF);
        tail("echo tail", winT + 3, 13, DEF);
    }

    private static String visible(String s) {
        StringBuilder b = new StringBuilder("\"");
        for (int i = 0; i < s.length(); i++) {
            char ch = s.charAt(i);
            b.append(ch < 32 ? "<" + (int) ch + ">" : String.valueOf(ch));
        }
        return b.append('"').toString();
    }

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

        paint("title by ST", "\u001b]2;via ST\u001b\\");
        gate("ST terminates it too", "via ST".equals(title()), visible(title()));

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

        a = stats(handle);
        paint("DCS counted", "\u001bP1;2$q+\u001b\\");
        b = stats(handle);
        gate("the DCS family has its own counter", b[S_UN + 8] - a[S_UN + 8] == 1,
                "dcs=" + (b[S_UN + 8] - a[S_UN + 8]));
        gate("and it set no title", b[S_TITLES] - a[S_TITLES] == 0, "titles=" + (b[S_TITLES] - a[S_TITLES]));
        gate("no console call failed on any of it", b[3] - a[3] == 0, "apiErrors=" + (b[3] - a[3]));

        gotoRow(8);
        a = stats(handle);
        paint("two markers around a sixel body",
                "AB\u001bPq#0;2;0;0;0;0;1Y\n#1;1;0;100;100;100;1,0,0;#1;2;0;100;100;0!0,0;"
                        + "#2;1;50;50;50$3\\#0;0;0;0;0;0E\u001b\\CD");
        b = stats(handle);
        gate("the sixel body is counted once, in the dcs bucket", b[S_UN + 8] - a[S_UN + 8] == 1,
                "dcs=" + (b[S_UN + 8] - a[S_UN + 8]));
        text("the two markers meet with nothing of the body between them", winT + 8, 0, "ABCD", DEF);
        tail("and the rest of that row is still blank", winT + 8, 4, DEF);
        gate("no title survived it", b[S_TITLES] - a[S_TITLES] == 0, "titles=" + (b[S_TITLES] - a[S_TITLES]));
        gate("and no console call failed", b[3] - a[3] == 0, "apiErrors=" + (b[3] - a[3]));
    }

    private static String title() {
        char[] t = consoleTitle();
        return t == null ? "<unreadable>" : new String(t);
    }

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

        gotoRow(9);
        paint("clear the second row", "\u001b[0m\u001b[2K");
        a = stats(handle);
        paint("marked prompt and input", "\u001b]133;A\u0007c> \u001b]133;B\u0007select 1;");
        b = stats(handle);
        text("the marked line reads as typed", winT + 9, 0, "c> select 1;", DEF);
        tail("to the end of it", winT + 9, 12, DEF);
        gate("the mark counted once, not twice", b[S_PROMPTS] - a[S_PROMPTS] == 1,
                "marks=" + (b[S_PROMPTS] - a[S_PROMPTS]) + ": 133;B starts input, it does not mark a row");

        a = stats(handle);
        paint("an unknown 133 letter", "\u001b]133;Q\u0007");
        b = stats(handle);
        gate("counted as an unmodelled OSC", b[S_UN + 7] - a[S_UN + 7] == 1,
                "other OSC=" + (b[S_UN + 7] - a[S_UN + 7]));
        gate("and it marked nothing", b[S_PROMPTS] - a[S_PROMPTS] == 0,
                "marks=" + (b[S_PROMPTS] - a[S_PROMPTS]));

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

    private static void caseClipboard() {
        final String marker = "native-renderer-" + System.nanoTime();
        gate("the test's own base64 matches RFC 4648",
                eqStr(b64("a"), "YQ==") && eqStr(b64("ab"), "YWI=") && eqStr(b64("abc"), "YWJj")
                        && eqStr(b64(""), ""),
                "a=" + b64("a") + " ab=" + b64("ab") + " abc=" + b64("abc"));
        final String user = clipText();
        if (!clipSeed("clipboard-gate-before")) {
            System.out.println("  SKIP clipboard: no out-of-process clipboard witness (pwsh Set-/Get-Clipboard)");
            clipRestore(user);
            return;
        }
        clipDown = false;
        final String before = clipText();
        if (!eqStr(before, "clipboard-gate-before")) {
            clipSkip("the witness can read what it just wrote", "read back " + show(before)
                    + "; an outside process owns the register, so this case has no witness");
            clipRestore(user);
            return;
        }
        gate("the witness can read what it just wrote", true, "read back " + show(before));

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

        NativeRenderer.setClipboardPolicy(true);
        gate("the dll says so", NativeRenderer.clipboardPolicy(), "the call did not reach the library");
        a = stats(handle);
        paint("clipboard, policy on", "\u001b]52;c;" + b64sent(marker) + "\u0007");
        b = stats(handle);
        gate("one write reached the clipboard", b[S_CLIP_WRITES] == a[S_CLIP_WRITES] + 1,
                "writes=" + b[S_CLIP_WRITES] + " failed=" + b[S_CLIP_FAILS]);
        gate("and nothing was refused", b[S_UN + 11] == a[S_UN + 11], "refused=" + b[S_UN + 11]);
        clipIs("the text is the text that was sent", marker);

        final String cjk = "中文-a";
        a = stats(handle);
        paint("clipboard, not ascii", "\u001b]52;c;" + b64sent(cjk) + "\u0007");
        clipIs("the wide characters survive the round trip", cjk);
        gate("and it cost one more write", stats(handle)[S_CLIP_WRITES] == a[S_CLIP_WRITES] + 1,
                "writes=" + stats(handle)[S_CLIP_WRITES]);

        a = stats(handle);
        paint("clipboard, clear", "\u001b]52;;\u0007");
        gate("clearing is a write too", stats(handle)[S_CLIP_WRITES] == a[S_CLIP_WRITES] + 1,
                "writes=" + stats(handle)[S_CLIP_WRITES]);
        clipIs("and the clipboard is empty", "");

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

        NativeRenderer.setClipboardPolicy(false);
        gate("the switch is off again", !NativeRenderer.clipboardPolicy(), "policy still on");
        if (user == null || user.length() == 0) {
            clipClear();
            String restored = clipText();
            if (restored != null && restored.length() != 0) {
                clipClear();
                restored = clipText();
            }
            gate("and what the owner had is back, which here was nothing",
                    restored == null || restored.length() == 0, "read back " + show(restored));
        } else {
            clipSeed(user);
            String back = clipText();
            if (!eqStr(back, user)) {
                clipSeed(user);
                back = clipText();
            }
            gate("and the register is back to the text its owner had", eqStr(back, user),
                    "read back " + show(back) + " want " + show(user));
        }
        gate("and the policy slot says off at the end of the run", stats(handle)[S_CLIP_POLICY] == 0,
                "policy=" + stats(handle)[S_CLIP_POLICY]);
    }

    private static final String CLIP_IN =
            "[Console]::InputEncoding=[Text.Encoding]::UTF8; $t=[Console]::In.ReadToEnd();"
            + " if ($t.Length -eq 0) { Clear-Clipboard } else { Set-Clipboard -Value $t }";
    private static final String CLIP_OUT =
            "[Console]::OutputEncoding=[Text.Encoding]::UTF8; Get-Clipboard -Raw";

    private static String clipText() {
        final String out = clipChild(CLIP_OUT, null);
        return out == null ? null : trimEol(out);
    }

    private static boolean clipSeed(final String text) {
        return clipChild(CLIP_IN, text == null ? "" : text) != null;
    }

    private static boolean clipClear() {
        return clipChild(CLIP_IN, "") != null;
    }

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

    private static boolean clipDown;

    private static void clipSkip(final String what, final String why) {
        checks++;
        System.out.println("  skip " + what + ": " + why);
    }

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

        paint("an OSC 4 spelled as a name", "\u001b]4;5;orange\u0007");
        p = palette();
        gate("the name reached the console as its colour", p != null && p[5] == 0x0000A5FF,
                p == null ? "unreadable" : "got=0x" + Long.toHexString(p[5]));
        paint("the same colour spelled in hex", "\u001b]4;6;#ffa500\u0007");
        p = palette();
        gate("and the two spellings ask the console for one entry",
                p != null && p[5] == p[6] && p[6] == 0x0000A5FF,
                p == null ? "unreadable" : "5=0x" + Long.toHexString(p[5]) + " 6=0x" + Long.toHexString(p[6]));
        paint("a name this build does not have", "\u001b]4;7;nosuchcolourname\u0007");
        p = palette();
        gate("writes nothing, rather than writing a guess", p != null && p[7] == paletteBefore[7],
                p == null ? "unreadable" : "got=0x" + Long.toHexString(p[7])
                        + " want the " + Long.toHexString(paletteBefore[7]) + " this console had");

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
        readInput(0);
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
        eqInput("DA1 is the machine underneath's own string",
                "\u001b[?61;4;6;7;14;21;22;23;24;28;32;42c\u001b[>0;10;1c");

        a = stats(handle);
        paint("an unanswered report", "\u001b[t");
        b = stats(handle);
        gate("counted, not swallowed", b[S_UN + 9] - a[S_UN + 9] == 1, "report=" + (b[S_UN + 9] - a[S_UN + 9]));
        gate("and nothing written to the input stream", b[S_REPLIED] - a[S_REPLIED] == 0,
                "written=" + (b[S_REPLIED] - a[S_REPLIED]));
        eqInput("the queue is empty", "");

        final int[] SIZES = { 8, 16, 24, 32, 48, 64 };
        for (int si = 0; si < SIZES.length; si++) {
            final int ask = SIZES[si];
            readInput(0);
            final long[] p = stats(handle);
            StringBuilder q = new StringBuilder();
            for (int i = 0; i < ask; i++) q.append("\u001b[5n");
            paint("queue depth " + ask, q.toString());
            final long[] r = stats(handle);
            gate("asked " + ask + ", answered " + ask, (int) (r[S_REPLIED] - p[S_REPLIED]) == ask
                    && (int) (r[S_REPLY_FULL] - p[S_REPLY_FULL]) == 0,
                    "wrote=" + (r[S_REPLIED] - p[S_REPLIED]) + " refused=" + (r[S_REPLY_FULL] - p[S_REPLY_FULL])
                            + " want " + ask + " and 0");
            StringBuilder want = new StringBuilder();
            for (int i = 0; i < ask; i++) want.append("\u001b[0n");
            StringBuilder gotBytes = new StringBuilder();
            StringBuilder batches = new StringBuilder();
            for (int round = 0; round < 40; round++) {
                final String s = input(256);
                batches.append(s.length()).append(' ');
                if (s.isEmpty()) break;
                gotBytes.append(s);
            }
            gate("and all " + ask + " arrive, once each, oldest first", gotBytes.toString().equals(want.toString()),
                    "got " + gotBytes.length() + " chars want " + want.length() + " in batches[" + batches
                            + "]: a count the bytes cannot match is a reply the program is still waiting for");
        }

        readInput(0);
        a = stats(handle);
        final int ASK = 72;
        StringBuilder many = new StringBuilder();
        for (int i = 0; i < ASK; i++) many.append("\u001b[5n");
        paint("seventy-two questions, one bounded queue", many.toString());
        b = stats(handle);
        final int wrote = (int) (b[S_REPLIED] - a[S_REPLIED]);
        final int full = (int) (b[S_REPLY_FULL] - a[S_REPLY_FULL]);
        gate("a queue that small refuses", full >= 1, "refused=" + full + " of " + ASK
                + ": if this ever reads 0 the depth passed 72 and this arm's premise, not its expectation, is stale");
        gate("asked equals answered plus refused", wrote + full == ASK,
                "wrote=" + wrote + " refused=" + full + " asked=" + ASK + ": the gap between these is where a"
                        + " dropped-on-the-floor reply would hide -- a limit leaves a number, a leak does not");
        gate("and at least one whole family fits", wrote >= 9, "answered=" + wrote
                + ": #81 made nine the largest thing a stream can ask in one write, so a queue that answers"
                        + " fewer truncates a feature rather than an abuse");
        StringBuilder over = new StringBuilder();
        for (int i = 0; i < wrote; i++) over.append("\u001b[0n");
        StringBuilder gotOver = new StringBuilder();
        StringBuilder overBatches = new StringBuilder();
        for (int round = 0; round < 40; round++) {
            final String s = input(256);
            overBatches.append(s.length()).append(' ');
            if (s.isEmpty()) break;
            gotOver.append(s);
        }
        gate("the ones that were answered are the ones that arrive", gotOver.toString().equals(over.toString()),
                "got " + gotOver.length() + " chars for " + wrote + " replies want " + over.length()
                        + " in batches[" + overBatches + "]");
        final String spilled = input(8);
        gate("and nothing spilled past them", spilled.isEmpty(), "spilled=" + vis(spilled)
                + ": a queue that answered " + wrote + " must have written " + wrote + ", not more");

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
        gate("and one id in it voted as a refused mode", b[S_UN + 4] - a[S_UN + 4] == 1,
                "mode=" + (b[S_UN + 4] - a[S_UN + 4]) + " -- `?u`, then 2027; 2048 answers since #82 so it votes nothing");
        eqInput("the probe's three DECRPMs -- 2026, then 2027 answered 0, then 2048 off -- and the fence",
                "\u001b[?2026;" + (b[S_SYNC_ON] == 1 ? 1 : 2) + "$y"
                                        + "\u001b[?2027;0$y"
                        + "\u001b[?2048;2$y"
                        + "\u001b[?61;4;6;7;14;21;22;23;24;28;32;42c");
        paint("the DECRC that save belongs to", "\u001b[u");
        afterProbe = consoleView();
        gate("while the plain `CSI u` still restores", afterProbe[5] == 4 && afterProbe[6] == winT + 2,
                "(" + afterProbe[5] + "," + afterProbe[6] + ") winT=" + winT);
    }

    private static void caseEraseToBufferWidth() {
        gotoRow(2);
        paint("erase", "\u001b[42mBG\u001b[K rest");
        text("green", winT + 2, 0, "BG", 0x27);
        cell("after EL", winT + 2, 2, ' ', 0x27);
        text("after EL text", winT + 2, 3, "rest", 0x27);
        tail("erase tail", winT + 2, 7, 0x27);
        paint("erase reset", "\u001b[0m");
    }

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

    private static void caseEditRows() {
        if (!standardGeometry("the IL/DL leg")) return;
        final long[] a = stats(handle);
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
        paint("a narrow row, then ICH 3 at column 5", "\u001b[8;1HABCDEFGH\u001b[8;5H\u001b[3@");
        cell("the opened gap is blank", winT + 7, 4, ' ', DEF);
        cell("and E, which moved, is at the column the model put it in", winT + 7, 7, 'E', DEF);
        cell("with G behind it", winT + 7, 9, 'G', DEF);
        paint("and DCH 3 pulls the same tail back", "\u001b[8;5H\u001b[3P");
        cell("E is under the cursor again", winT + 7, 4, 'E', DEF);
        cell("and H stands at the end of the text", winT + 7, 7, 'H', DEF);
        paint("clear the band", "\u001b[8;1H\u001b[J");
        paint("restate the row", "\u001b[6;1H\u4e2d\u6587ab");
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
        paint("a save and a restore that must still work", "\u001b[11;2H\u001b7\u001b[12;7H\u001b8");
        v = consoleView();
        gate("DECRC still moves after a soft reset", v[5] == 1 && v[6] == winT + 10,
                "(" + v[5] + "," + v[6] + ") want (1," + (winT + 10) + ")");
        paint("the pen is what a soft reset does drop", "\u001b[13;1HR");
        cell("red and bold are gone, so R is the default attribute", winT + 12, 0, 'R', DEF);
        final long[] mid = stats(handle);
        gate("DECSTR moved no census family", mid[S_UN] - a[S_UN] == 0,
                "unrecognised=" + (mid[S_UN] - a[S_UN]));

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

    private static void caseMargins() {
        if (!standardGeometry("the margin leg")) return;

        paint("DECLRMM on, then margins at columns 5..20", "\u001b[?69h\u001b[5;20s");
        long[] v = consoleView();
        gate("a valid pair homes the cursor onto the left margin", v[5] == 4 && v[6] == winT,
                "(" + v[5] + "," + v[6] + ") want (4," + winT + ")");

        paint("twenty-four letters, which the band cannot hold", "ABCDEFGHIJKLMNOPQRSTUVWX");
        text("the first sixteen fill the band", winT, 4, "ABCDEFGHIJKLMNOP", DEF);
        text("and the rest continue at the margin, not at column 0", winT + 1, 4, "QRSTUVWX", DEF);
        tail("the row below is clear past the word", winT + 1, 12, DEF);

        paint("a CUP that names column 1, inside the band", "\u001b[1;1H#");
        text("the glyph landed on the margin, not at the page edge", winT, 4, "#", DEF);
        v = consoleView();
        gate("and the cursor sits one past the margin cell", v[5] == 5,
                "x=" + v[5] + " want 5 (the write advanced from the clamped column 4)");

        paint("a region and origin mode together", "\u001b[2;5r\u001b[?6h");
        v = consoleView();
        gate("setting DECOM homes the cursor to the region's top-left", v[5] == 4 && v[6] == winT + 1,
                "(" + v[5] + "," + v[6] + ") want (4," + (winT + 1) + ")");
        paint("addressing now counts from that corner", "\u001b[2;3HZ");
        text("row 2, column 3 of the region", winT + 2, 6, "Z", DEF);

        paint("save, drop the mode, walk away, restore",
              "\u001b[3;8H\u001b7\u001b[?6l\u001b[1;1H\u001b8");
        v = consoleView();
        gate("SCOSR brings the coordinate space back with the position", v[5] == 11 && v[6] == winT + 3,
                "(" + v[5] + "," + v[6] + ") want (11," + (winT + 3) + "): ESC 7/8 carry origin (MSFT :481/:497)");

        paint("RIS clears the whole family", "\u001bc");
        v = consoleView();
        paint("column 1 is reachable again", "\u001b[1;1H@");
        text("the page edge is the page again", winT, 0, "@", DEF);

        paint("claim the band, a region, and origin",
              "\u001b[2;5r\u001b[?69h\u001b[5;20s\u001b[?6h\u001b[1;1HX");
        v = consoleView();
        gate("setup: the glyph stands on the left margin of the region's top row",
                v[5] == 5 && v[6] == winT + 1,
                "(" + v[5] + "," + v[6] + ") want (5," + (winT + 1) + ")");
        gate("the rebuild is accepted", readopt(handle) == 1, "readopt refused");
        paint("address row 1 again after the rebuild", "\u001b[1;1HY");
        v = consoleView();
        gate("the left margin came through the seam", v[5] == 5,
                "x=" + v[5] + " want 5: the write landed on the carried column 4, not at 0");
        gate("and the region came through the seam with it, so origin's row 1 is the band's top",
                v[6] == winT + 1,
                "y=" + v[6] + " want " + (winT + 1) + ": DECSTBM's band rides the rebuild re-clamped now (T-11b), "
                + "so the write lands where the setup glyph stood, not on the viewport's top row");
        text("the write overwrote the setup glyph on the region's top row", winT + 1, 4, "Y", DEF);
        text("and the viewport's own top row stayed clear of it", winT, 4, " ", DEF);
        standardGeometry("leaving the viewport as the next case expects it");
    }

    private static void caseBracketedPaste() {
        if (!standardGeometry("the bracketed-paste leg")) return;
        long[] a = stats(handle);
        if (a.length <= S_BP) {
            gate("stats carries the bracketed-paste slot", false,
                    "length=" + a.length + " want at least " + (S_BP + 1)
                            + ": render.dll predates #83, so this leg has nothing to read");
            return;
        }
        gate("a fresh grid has agreed nothing", a[S_BP] == 0, "slot=" + a[S_BP]);
        paint("the application asks for bracketed paste", "\u001b[?2004h");
        long[] b = stats(handle);
        gate("and the shipped stats() says so", b[S_BP] != 0, "slot=" + b[S_BP] + " want non-zero");
        gate("the census did not gain a refusal for it", b[S_UN + 5] == a[S_UN + 5],
                "bracketed paste=" + (b[S_UN + 5] - a[S_UN + 5]) + ": a stored mode is not an unmodelled one");
        paint("and it is turned off again", "\u001b[?2004l");
        long[] c = stats(handle);
        gate("the reset is a store too", c[S_BP] == 0, "slot=" + c[S_BP]);
        paint("the OSC form asks for an executed paste", "\u001b]2004;1\u0007");
        long[] e = stats(handle);
        gate("the OSC request is counted where the CSI one was not", e[S_UN + 5] - c[S_UN + 5] == 1,
                "bracketed paste=" + (e[S_UN + 5] - c[S_UN + 5]) + " want 1");
        gate("and it still set no state", e[S_BP] == 0, "slot=" + e[S_BP]);
        paint("DECSET 2004 again, for the carry leg", "\u001b[?2004h");
        long[] armed = stats(handle);
        gate("and the bit stands again", armed[S_BP] != 0, "slot=" + armed[S_BP]);
        if (setGeometry(BUF_W, BUF_H, WIN_W, WIN_H - 4, DEF) == 0) {
            gate("the carry leg gets a shorter window", false, "setGeometry");
        } else {
            gate("the rebuild is accepted", readopt(handle) == 1, "readopt refused");
            long[] across = stats(handle);
            gate("a resize is not an un-agreement: the bit rode across the rebuild", across[S_BP] != 0,
                    "slot=" + across[S_BP] + " want non-zero -- DECRQM answers 1 (not set) for a mode the app set");
            paint("and `?2004$p` still says set", "\u001b[?2004$p");
            eqInput("the reply carries status 1 after the rebuild", "\u001b[?2004;1$y");
            setGeometry(BUF_W, BUF_H, WIN_W, WIN_H, DEF);
            readopt(handle);
        }
        paint("RIS clears the family", "\u001bc");
        long[] f = stats(handle);
        gate("the bit is off after RIS", f[S_BP] == 0, "slot=" + f[S_BP]);
        standardGeometry("leaving the viewport as the next case expects it");
    }

    private static void caseSgrStack() {
        if (!standardGeometry("the SGR-stack leg")) return;
        gotoRow(2);
        paint("push red, drop it, write green", "\u001b[31m\u001b[#{\u001b[m\u001b[32mG");
        text("the live pen is green", winT + 2, 0, "G", 0x02);
        gate("the rebuild is accepted", readopt(handle) == 1, "readopt refused");
        paint("pop after the rebuild, then write", "\u001b[#}R");
        text("the pop restored the pushed red across the seam", winT + 2, 1, "R", 0x04);
        paint("red on, save the fore colour alone, then reset and go blue",
              "\u001b[31m\u001b[30#{\u001b[m\u001b[34mB");
        gate("the second rebuild is accepted", readopt(handle) == 1, "readopt refused");
        paint("pop the fore colour back", "\u001b[#}!");
        text("the blue pen the pop is about to replace", winT + 2, 2, "B", 0x01);
        text("the saved colour returned across the seam", winT + 2, 3, "!", 0x04);
        standardGeometry("leaving the pen as the next case expects it");
    }

    private static void caseXtModes() {
        if (!standardGeometry("the XTSAVE leg")) return;
        readInput(0);
        paint("arm, save, close", "\u001b[?1000h\u001b[?1000s\u001b[?1000l");
        paint("ask what the model holds now", "\u001b[?1000$p");
        String r = input(64);
        gate("the closed bit answers reset", r.contains("\u001b[?1000;2$y"), "read back " + vis(r));
        gate("the rebuild is accepted", readopt(handle) == 1, "readopt refused");
        paint("restore across the seam, then ask again", "\u001b[?1000r\u001b[?1000$p");
        r = input(64);
        gate("the save survived build_model and the restore re-ran the act",
                r.contains("\u001b[?1000;1$y"),
                "read back " + vis(r) + " -- a 2 here is a lost save, not an unanswered ask");
        paint("arm bracketed paste, then restore it unsaved", "\u001b[?2004h\u001b[?2004r\u001b[?2004$p");
        r = input(64);
        gate("a restore without a save closes the mode", r.contains("\u001b[?2004;2$y"),
                "read back " + vis(r));
        standardGeometry("leaving the modes as the next case expects them");
    }

    private static void caseRectFamily() {
        if (!standardGeometry("the rect leg")) return;
        gotoRow(1);
        paint("fill a rect with # in a red pen", "\u001b[31m\u001b[2;5;4;20;35$x");
        text("fra: the rect is # and red", winT + 1, 4, "#####", 0x04);
        text("fra: above the rect is untouched", winT, 4, "     ", DEF);
        standardGeometry("cleaning the pen");

        gotoRow(2);
        paint("protect a glyph, then selective-erase the screen",
              "\u001b[1\"qP\u001b[2\"qQ\u001b[?2J");
        text("sed: the protected glyph stood", winT + 2, 0, "P", DEF);
        text("sed: the unprotected one went", winT + 2, 1, " ", DEF);

        gotoRow(3);
        paint("insert two columns mid-row", "abcdef\u001b[1;3H\u001b[2}");
        text("decic: two blanks opened at the cursor", winT + 3, 0, "ab  cdef", DEF);

        paint("and the plain erase still clears protection", "\u001b[4;1;4;4$z");
        text("era: the non-selective rect has no respect for the bit", winT + 3, 0, "  ", DEF);
        standardGeometry("leaving the screen as the next case expects it");
    }

    private static void caseCursorKeys() {
        if (!standardGeometry("the DECCKM leg")) return;
        final long[] a = stats(handle);

        readInput(0);
        paint("ask before anyone armed it", "\u001b[?1$p");
        String r = input(64);
        gate("?1 answers reset (2) on a fresh model", r.contains("\u001b[?1;2$y"), "read back " + vis(r));

        paint("DECCKM on", "\u001b[?1h");
        readInput(0);
        paint("and ask", "\u001b[?1$p");
        r = input(64);
        gate("?1h is answered as set (1), DEC's vocabulary", r.contains("\u001b[?1;1$y"),
                "read back " + vis(r) + " -- a 2 here is #93's inversion or a bit the store lost");

        final int back = readopt(handle);
        readInput(0);
        paint("and ask after the rebuild", "\u001b[?1$p");
        r = input(64);
        gate("a rebuild for the console's shape carries DECCKM", back == 1 && r.contains("\u001b[?1;1$y"),
                "readopt=" + back + " read back " + vis(r)
                        + ": a terminal that says 'set' before a drag and 'reset' after one is answering two"
                        + " different questions with one number (I26, and the same lie #83 fixed for 2004)");

        paint("DECCKM off", "\u001b[?1l");
        readInput(0);
        paint("and ask once more", "\u001b[?1$p");
        r = input(64);
        gate("and ?1l walks it back to reset", r.contains("\u001b[?1;2$y"), "read back " + vis(r));

        readInput(0);
        final long[] c = stats(handle);
        paint("DECANM asked", "\u001b[?2$p");
        r = input(64);
        gate("?2 answers 3 = permanently set", r.contains("\u001b[?2;3$y"), "read back " + vis(r)
                + ": this parser has no VT52 table to switch into, and MSFT answers the same question from"
                + " its state machine's parser mode (adaptDispatch.cpp:1957-1958)");
        paint("DECANM asked to change", "\u001b[?2h");
        readInput(0);
        paint("and asked again", "\u001b[?2$p");
        r = input(64);
        gate("and ?2h cannot move it", r.contains("\u001b[?2;3$y"), "read back " + vis(r));
        final long[] d = stats(handle);
        gate("the set is still counted as refused, the asks are not", d[S_UN + 4] - c[S_UN + 4] == 1,
                "mode=" + (d[S_UN + 4] - c[S_UN + 4]) + ": ?2h votes, ?2$p now answers and must not");

        final long[] b = stats(handle);
        gate("and the only align in this leg is the rebuild we asked for", b[4] - a[4] == 1,
                "aligns=" + (b[4] - a[4]) + ": a mode the screen cannot show must not buy window work, and the"
                        + " one here is the readopt the carry arm deliberately takes");
        gate("and no console call failed", b[3] - a[3] == 0, "apiErrors=" + (b[3] - a[3]));
        standardGeometry("leaving the viewport as the next case expects it");
    }

    private static void caseDeccolm() {
        if (!standardGeometry("the DECCOLM leg")) return;
        final long[] a = stats(handle);

        readInput(0);
        paint("ask about 132 columns", "\u001b[?3$p");
        String r = input(64);
        gate("?3 answers 4 = permanently reset", r.contains("\u001b[?3;4$y"), "read back " + vis(r));

        paint("ask for 132 columns", "\u001b[?3h");
        readInput(0);
        paint("and ask again", "\u001b[?3$p");
        r = input(64);
        gate("?3h does not move the answer", r.contains("\u001b[?3;4$y"), "read back " + vis(r));
        paint("ask for 80 columns", "\u001b[?3l");
        readInput(0);
        paint("and ask a third time", "\u001b[?3$p");
        r = input(64);
        gate("?3l leaves it at 4 as well", r.contains("\u001b[?3;4$y"), "read back " + vis(r));

        final long[] b = stats(handle);
        gate("the two set sequences are counted as refused", b[S_UN + 4] - a[S_UN + 4] == 2,
                "mode=" + (b[S_UN + 4] - a[S_UN + 4]) + ": ?3h and ?3l vote, ?3$p now answers and must not");
        gate("and refusing bought no window work", b[4] - a[4] == 0, "aligns=" + (b[4] - a[4]));
        gate("and no console call failed", b[3] - a[3] == 0, "apiErrors=" + (b[3] - a[3]));
        standardGeometry("leaving the viewport as the next case expects it");
    }

    private static void caseMouseModes() {
        if (!standardGeometry("the mouse-mode leg")) return;
        long[] a = stats(handle);
        final int MOUSE = S_UN + 3;

        readInput(0);
        paint("the nine mouse queries", "\u001b[?9$p\u001b[?1000$p\u001b[?1002$p\u001b[?1003$p\u001b[?1004$p"
                + "\u001b[?1005$p\u001b[?1006$p\u001b[?1015$p\u001b[?1016$p");
        final String all = input(512);
        gate("all nine answer, each under its own number",
                all.contains("\u001b[?9;2$y") && all.contains("\u001b[?1000;2$y")
                        && all.contains("\u001b[?1002;2$y") && all.contains("\u001b[?1003;2$y")
                        && all.contains("\u001b[?1004;2$y") && all.contains("\u001b[?1005;2$y")
                        && all.contains("\u001b[?1006;2$y") && all.contains("\u001b[?1015;2$y")
                        && all.contains("\u001b[?1016;2$y"),
                "read back " + vis(all));

        paint("three modes on", "\u001b[?1000h\u001b[?1002h\u001b[?1006h");
        readInput(0);
        paint("and ask again", "\u001b[?1000$p\u001b[?1002$p\u001b[?1006$p\u001b[?1003$p");
        final String set = input(256);
        gate("the three set ones answer 2, and the untouched one still answers 1",
                set.contains("\u001b[?1000;1$y") && set.contains("\u001b[?1002;1$y")
                        && set.contains("\u001b[?1006;1$y") && set.contains("\u001b[?1003;2$y"),
                "read back " + vis(set) + " -- a single 'current protocol' field could not produce this four-way split");

        long[] b = stats(handle);
        gate("nine queries and three sets cost no refusal", b[MOUSE] - a[MOUSE] == 0,
                "mouse=" + (b[MOUSE] - a[MOUSE]) + ": #81 turned this family from a refusal into a store");
        gate("and no repaint", b[4] - a[4] == 0, "aligns=" + (b[4] - a[4])
                + ": a mode the screen cannot show must not cost the user a window flash");
        gate("and no console call failed", b[3] - a[3] == 0, "apiErrors=" + (b[3] - a[3]));
        gate("and nothing was injected into the input stream beyond the replies",
                b[S_UN + 9] - a[S_UN + 9] == 0, "report=" + (b[S_UN + 9] - a[S_UN + 9])
                        + ": the only bytes that left are the nine answers we just read back");

        if (setGeometry(BUF_W, BUF_H, WIN_W, WIN_H - 4, DEF) == 0) {
            gate("the carry leg gets a shorter window", false, "setGeometry");
        } else {
            gate("the rebuild is accepted", readopt(handle) == 1, "readopt said no");
            winT = (int) consoleView()[0];
            readInput(0);
            paint("and ask after the rebuild", "\u001b[?1000$p\u001b[?1002$p\u001b[?1006$p");
            final String after = input(256);
            gate("all three rode across the rebuild",
                    after.contains("\u001b[?1000;1$y") && after.contains("\u001b[?1002;1$y")
                            && after.contains("\u001b[?1006;1$y"),
                    "read back " + vis(after));
            setGeometry(BUF_W, BUF_H, WIN_W, WIN_H, DEF);
            readopt(handle);
        }

        long[] c = stats(handle);
        paint("?1001, which nobody implements", "\u001b[?1001h");
        long[] d = stats(handle);
        gate("it votes the mouse bucket", d[MOUSE] - c[MOUSE] == 1,
                "mouse=" + (d[MOUSE] - c[MOUSE]) + " want 1: the census must keep saying 'an application asked "
                        + "about the mouse and got nothing' for the numbers we really do not hold");
        readInput(0);
        paint("and it is not answerable", "\u001b[?1001$p");
        final String none = input(64);
        gate("so its query answers the not-recognized digit", none.contains("\u001b[?1001;0$y"),
                "read back " + vis(none) + " -- GAP G11: 0 claims only that no such mode is held, which is what the "
                        + "DECSET above just proved. The silence this arm used to demand left the asker to infer it; "
                        + "MSFT answers DECRPM_Unsupported for every id its switch does not name "
                        + "(adaptDispatch.cpp:1939), ghostty .not_recognized (modes.zig:80-102)");
        standardGeometry("leaving the viewport as the next case expects it");
    }

    private static void caseOsc9Family() {
        if (!standardGeometry("the OSC 9 family leg")) return;
        final char[] title0 = consoleTitle();
        final long[] a = stats(handle);
        readInput(0);
        paint("a marker to compare against", "Z");

        final long t0 = System.nanoTime();
        paint("the refused family in one chunk",
                "\u001b]9;1;5000\u0007\u001b]9;2;boom\u0007\u001b]9;3;Tab\u0007\u001b]9;5\u0007"
                        + "\u001b]9;6;GuiMacro(\"x\")\u0007\u001b]9;7;calc.exe\u0007\u001b]9;8;PATH\u0007"
                        + "\u001b]9;10\u0007\u001b]9;10;2\u0007\u001b]9;11;just a note\u0007");
        final long ms = (System.nanoTime() - t0) / 1000000L;
        final long[] b = stats(handle);

        gate("9;1;5000 did not sleep the stream", ms < 2000,
                "elapsed=" + ms + "ms for a chunk asking to sleep 5000ms (and 9;5 asks to wait for a key)");
        gate("all ten refused ids voted, no more and no less", b[S_UN + 6] - a[S_UN + 6] == 10,
                "osc9=" + (b[S_UN + 6] - a[S_UN + 6]) + ": a family member absorbed without a record is the"
                        + " failure this leg exists for");
        String r = input(64);
        gate("9;8 leaked no environment value into the input stream", r.isEmpty(), "read back " + vis(r));
        final char[] title1 = consoleTitle();
        gate("and no id renamed the window", java.util.Arrays.equals(title0, title1),
                "before=[" + new String(title0) + "] after=[" + new String(title1) + "]");
        text("the marker is where it was and nothing else arrived", winT, 0, "Z", DEF);
        gate("no console call failed on any of it", b[3] - a[3] == 0, "apiErrors=" + (b[3] - a[3]));

        final long[] c = stats(handle);
        paint("the two acting ids", "\u001b]9;4;1;50\u0007\u001b]9;12\u0007");
        final long[] d = stats(handle);
        gate("9;4 and 9;12 vote nothing", d[S_UN + 6] - c[S_UN + 6] == 0,
                "osc9=" + (d[S_UN + 6] - c[S_UN + 6]));
        gate("and they bought no cell, no mark and no reply",
                d[5] - c[5] == 0 && d[S_PROMPTS] - c[S_PROMPTS] == 0,
                "cells=" + (d[5] - c[5]) + " marks=" + (d[S_PROMPTS] - c[S_PROMPTS])
                        + ": a mark is a claim about the stream, not a drawing");
    }

    private static void caseMouseArm() {
        if (!standardGeometry("the mouse-arm leg")) return;
        final int MOUSE = 0x0010, QUICK_EDIT = 0x0040, EXTENDED = 0x0080;

        long[] m0 = inputMode(handle);
        gate("nothing is armed before the stream asks", m0[3] == 0 && m0[2] == 0,
                "armed=" + m0[3] + " saved=" + m0[2] + ": a handle that borrowed the mode at open() would be"
                        + " reporting a base it read before anybody asked for anything");
        final long base = m0[0];
        gate("and the console has a mode to borrow", base != 0, "GetConsoleMode read " + base);

        paint("one mouse mode", "\u001b[?1000h");
        m0 = inputMode(handle);
        gate("the console is armed", (m0[0] & MOUSE) != 0 && m0[3] == 1,
                "mode=0x" + Long.toHexString(m0[0]) + " armed=" + m0[3]);
        gate("quick-edit is off, which is what makes the console report the mouse instead of selecting with it",
                (m0[0] & QUICK_EDIT) == 0, "mode=0x" + Long.toHexString(m0[0])
                        + ": measured on this box -- with quick-edit on, a click yields no MOUSE_EVENT record"
                        + " at all; with it off, one drag yielded 34 (cache/audit90/t5/mouse-report.txt)");
        gate("the base is the mode as we found it, not as we left it", m0[1] == base && m0[2] == 1,
                "base=0x" + Long.toHexString(m0[1]) + " now=0x" + Long.toHexString(m0[0])
                        + ": restoring has to be able to name what it is restoring TO");

        paint("a second mouse mode on top", "\u001b[?1002h\u001b[?1006h");
        long[] m1 = inputMode(handle);
        gate("a second ask does not ratchet the mode", m1[0] == m0[0],
                "0x" + Long.toHexString(m0[0]) + " -> 0x" + Long.toHexString(m1[0])
                        + ": the mode is computed from the base every time, so N arms cannot drift it");
        gate("while the model does keep all three", m1[4] == (2 | 4 | 64), "mouseModes=0x" + Long.toHexString(m1[4]));

        paint("and the soft reset", "\u001b[!p");
        long[] m2 = inputMode(handle);
        gate("DECSTR leaves the console armed, because it leaves the bits set", m2[3] == 1 && m2[4] != 0,
                "armed=" + m2[3] + " modes=0x" + Long.toHexString(m2[4]) + ": the reset and the arming answer"
                        + " to the same owner -- if the bits survived, the console must still be delivering");

        paint("clear the last one", "\u001b[?1000l\u001b[?1002l\u001b[?1006l");
        long[] m3 = inputMode(handle);
        gate("the mode goes back to the base verbatim", m3[0] == base && m3[3] == 0,
                "back=0x" + Long.toHexString(m3[0]) + " base=0x" + Long.toHexString(base) + " armed=" + m3[3]
                        + ": quick-edit included -- leaving the user's console without text selection after the"
                        + " program that asked for the mouse has gone is the vandalism this borrow/return is for");

        paint("arm again, then hard-reset", "\u001b[?1004h\u001bc");
        long[] m4 = inputMode(handle);
        gate("RIS takes the console back too", m4[4] == 0 && m4[3] == 0 && m4[0] == base,
                "modes=0x" + Long.toHexString(m4[4]) + " armed=" + m4[3] + " mode=0x"
                        + Long.toHexString(m4[0]) + ": a power-up reset that left the mouse armed would be a"
                        + " reset with a side effect nobody asked for");

        gate("and the session ends owing the console nothing", m4[0] == base,
                "the first reading and the last are the same word");
        standardGeometry("leaving the viewport as the next case expects it");
    }

    private static void caseInputReports() {
        if (!standardGeometry("the input-report leg")) return;
        final int Q_UI = 5, Q_UF = 6, Q_QUIET = 7, Q_INJ = 8, Q_INJF = 9;

        long[] m0 = inputMode(handle);
        gate("no mouse mode at the start", m0[4] == 0, "mouseModes=0x" + Long.toHexString(m0[4]));
        final char[] qPress = mouseReport(handle, 9, 4, -1, -1, 1, 0, 0, 1);
        gate("a press before any mode encodes nothing", qPress != null && qPress.length == 0,
                qPress == null ? "null, which means the buffer was refused -- not the same answer"
                        : "len=" + qPress.length + " [" + show(qPress) + "]");
        final char[] qRelease = mouseReport(handle, 9, 4, -1, -1, 0, 0, 0, 1);
        gate("and so does its release", qRelease != null && qRelease.length == 0,
                qRelease == null ? "null" : "len=" + qRelease.length + " [" + show(qRelease) + "]");
        gate("both counted as records seen, neither as a report said",
                inputMode(handle)[Q_QUIET] == 2 && inputMode(handle)[Q_UI] == 0,
                "quiet=" + inputMode(handle)[Q_QUIET] + " mouse=" + inputMode(handle)[Q_UI]
                        + ": #108 was closed once on 'nobody can encode this', and the two zeros look alike");
        gate("with nothing in the input stream to match them", readInput(32).length == 0, "");

        paint("the mouse family", "\u001b[?1000h\u001b[?1006h");
        final String sgrPress = "\u001b[<0;10;5M", sgrRelease = "\u001b[<0;10;5m";
        final char[] press = mouseReport(handle, 9, 4, -1, -1, 1, 0, 0, 1);
        gate("the press is SGR", press != null && sgrPress.equals(new String(press)),
                press == null ? "null" : "[" + show(press) + "]");
        final char[] back = readInput(32);
        gate("and it reached CONIN$, where a reader of the console finds it",
                back != null && sgrPress.equals(new String(back)),
                back == null ? "null" : "[" + show(back) + "] bytes=" + (back == null ? -1 : back.length)
                        + ": the host gate can prove the bytes, only a console can prove the delivery");
        long[] m1 = inputMode(handle);
        gate("the encoder counted one report and the console took it",
                m1[Q_UI] == 1 && m1[Q_INJ] == 1 && m1[Q_INJF] == 0,
                "mouse=" + m1[Q_UI] + " injected=" + m1[Q_INJ] + " refused=" + m1[Q_INJF]);

        final char[] release = mouseReport(handle, 9, 4, -1, -1, 0, 0, 0, 0);
        gate("the release says so in lower case", release != null && sgrRelease.equals(new String(release)),
                release == null ? "null" : "[" + show(release) + "]");
        gate("and an inject flag of 0 left the stream alone", readInput(32).length == 0,
                "the same encoder answers both questions, so the leg has to be able to ask them separately");

        mouseReport(handle, 9, 4, -1, -1, 1, 0, 0, 0);
        long[] pre = inputMode(handle);
        gate("the tally before the rebuild is the whole session so far",
                pre[Q_UI] == 3 && pre[Q_QUIET] == 2 && pre[Q_INJ] == 1,
                "mouse=" + pre[Q_UI] + " quiet=" + pre[Q_QUIET] + " injected=" + pre[Q_INJ]);
        gate("the model rebuilds", readopt(handle) == 1, "readopt returned 0: the leg below would prove nothing");
        final char[] afterRebuild = mouseReport(handle, 9, 4, -1, -1, 0, 0, 0, 0);
        gate("and the release after it is still SGR, from a button the new model was told about",
                afterRebuild != null && sgrRelease.equals(new String(afterRebuild)),
                afterRebuild == null ? "null" : "[" + show(afterRebuild) + "]"
                        + " modes=0x" + Long.toHexString(inputMode(handle)[4])
                        + ": #83's shape of loss -- the bits carried, the behaviour did not");

        paint("a hard reset, then the plain ask", "\u001bc\u001b[?1000h");
        final char[] x10 = mouseReport(handle, 9, 4, -1, -1, 1, 0, 0, 0);
        gate("and the report takes the X10 shape",
                x10 != null && x10.length == 6 && x10[0] == 27 && x10[1] == '[' && x10[2] == 'M'
                        && x10[3] == 32 && x10[4] == 42 && x10[5] == 37,
                x10 == null ? "null" : "[" + show(x10) + "]");

        paint("focus reporting", "\u001b[?1004h");
        final char[] fin = focusReport(handle, 1, 1);
        gate("?1004h reports gaining focus as ESC [ I",
                fin != null && "\u001b[I".equals(new String(fin)), fin == null ? "null" : "[" + show(fin) + "]");
        gate("and the stream got it", "\u001b[I".equals(new String(readInput(32))), "");
        final char[] fout = focusReport(handle, 0, 0);
        gate("losing it is ESC [ O", fout != null && "\u001b[O".equals(new String(fout)),
                fout == null ? "null" : "[" + show(fout) + "]");
        paint("and the mode off", "\u001b[?1004l");
        final char[] off = focusReport(handle, 1, 1);
        gate("after ?1004l the same event says nothing", off != null && off.length == 0,
                off == null ? "null" : "[" + show(off) + "]");
        gate("and nothing was written for it", readInput(32).length == 0 && inputMode(handle)[Q_INJF] == 0,
                "an unsolicited report is I26; a failed write is a finding, and there was none");
        long[] mEnd = inputMode(handle);
        gate("the rebuilt grid counts only what it was told, and kept the protocol it was told about",
                mEnd[Q_UI] == 2 && mEnd[Q_UF] == 2 && mEnd[Q_INJ] == 1,
                "mouse=" + mEnd[Q_UI] + " focus=" + mEnd[Q_UF] + " injected=" + mEnd[Q_INJ]
                        + " quiet=" + mEnd[Q_QUIET] + ", against " + pre[Q_UI] + "/" + pre[Q_QUIET] + "/"
                        + pre[Q_INJ] + " before the rebuild: #108's counters are the model's and a rebuild "
                        + "starts a fresh series (Render.h's rc_report_counts says so), which is the honest "
                        + "shape -- folding the old grid's tally would claim injections this model never "
                        + "produced. What the rebuild DOES carry is the protocol and the button state, and the "
                        + "release above is the witness that both survived.");
        standardGeometry("leaving the viewport as the next case expects it");
    }

    private static String show(char[] c) {
        StringBuilder b = new StringBuilder();
        for (int i = 0; i < c.length; i++) { if (i > 0) b.append(' '); b.append((int) c[i]); }
        return b.toString();
    }

    private static long vtpBase = -1;

    private static void caseVtp() {
        if (!standardGeometry("the VTP leg")) return;
        final int VTP = 0x0004;

        long[] v = outputMode(handle);
        gate("the renderer holds this console's own escape parser off", v[2] == 1 && v[3] == 1,
                "saved=" + v[2] + " claimed=" + v[3] + ": the claim is taken at open(), not at the first"
                        + " flush -- bytes that reach the console before the first paint would otherwise be"
                        + " parsed by conhost on 1809+ and by nobody on Windows 7, which is the divergence"
                        + " the owner ruled out on 2026-09-27");
        gate("the live mode is the base with that bit cleared, nothing else touched",
                v[0] == (v[1] & ~VTP),
                "live=0x" + Long.toHexString(v[0]) + " base=0x" + Long.toHexString(v[1])
                        + ": a borrow may subtract one bit from what it found; a mode the library invented"
                        + " would pass the previous assertion and still be a lie about this console");
        vtpBase = v[1];
        if ((v[1] & VTP) != 0) {
            gate("and on this console the borrow really took something away", v[0] != v[1],
                    "base=0x" + Long.toHexString(v[1]) + " live=0x" + Long.toHexString(v[0])
                            + ": the host had a parser and the console no longer does");
        } else {
            gate("SKIP: this console had no host parser to borrow -- the assertions above hold of a"
                    + " renderer that changed nothing, so the WT leg is the witness here", true, null);
        }

        final int back = readopt(handle);
        flushQuietly();
        long[] r = outputMode(handle);
        gate("a rebuild for the console's shape keeps the claim", back == 1 && r[3] == 1 && r[0] == v[0],
                "readopt=" + back + " claimed=" + r[3] + " live=0x" + Long.toHexString(r[0])
                        + " expected=0x" + Long.toHexString(v[0])
                        + ": drop_model is called by the rebuild too, so 'give it back when the model goes'"
                        + " would be wrong here -- it is 'give it back when nothing is painting'");
        standardGeometry("leaving the viewport as the next case expects it");
    }

    private static void caseCharset() {
        if (!standardGeometry("the charset leg")) return;
        gotoRow(1);
        paint("plain G0, anchored", "\u001b(Bq");
        cell("plain G0 draws the letter", winT + 1, 0, 'q', DEF);

        gotoRow(2);
        paint("smacs: G0 becomes the drawing set", "\u001b(0q");
        cell("the drawing set draws a line", winT + 2, 0, '─', DEF);

        gotoRow(3);
        paint("G0 plain again, G1 designated, anchored", "\u001b(B\u001b)0q");
        cell("designating G1 alone draws a letter", winT + 3, 0, 'q', DEF);
        paint("SO brings G1 into GL", "\u000eq");
        cell("and after SO the same byte is a line", winT + 3, 1, '─', DEF);
        paint("SI puts G0 back", "\u000fq");
        cell("SI returns to a letter", winT + 3, 2, 'q', DEF);

        gotoRow(4);
        paint("G0 plain, G1 drawing, GL onto G1", "\u001b(B\u001b)0\u000e");
        if (setGeometry(BUF_W, BUF_H, WIN_W, WIN_H - 4, DEF) == 0) {
            gate("the carry leg gets a shorter window", false, "setGeometry");
        } else {
            gate("the rebuild is accepted", readopt(handle) == 1, "readopt said no");
            winT = (int) consoleView()[0];
            gotoRow(4);
            paint("anchor, then one byte, after the rebuild", "#q");
            cell("  the anchor reached row 4, un-remapped", winT + 4, 0, '#', DEF);
            cell("the shift rode across the rebuild: G1's line, not G0's letter", winT + 4, 1, '─', DEF);
            setGeometry(BUF_W, BUF_H, WIN_W, WIN_H, DEF);
            readopt(handle);
        }
        gotoRow(5);
        paint("G0 drawing, G1 plain, GL on G1", "\u001b(0\u001b)B\u000e");
        paint("rmacs then a byte", "\u001b(Bq");
        cell("rmacs unloaded G0 but not GL: the plain G1's letter", winT + 5, 0, 'q', DEF);
        gotoRow(6);
        paint("both G-sets drawing, GL shifted", "\u001b(0\u001b)0\u000e");
        paint("so a letter is a line", "q");
        cell("the armed state really is armed", winT + 6, 0, '─', DEF);
        gotoRow(7);
        paint("then the soft reset", "\u001b[!p");
        paint("and the same byte", "q");
        cell("DECSTR un-designated and un-shifted: a letter again", winT + 7, 0, 'q', DEF);
        standardGeometry("leaving the viewport as the next case expects it");
    }

    private static void caseCursorShape() {
        if (!standardGeometry("the cursor-shape leg")) return;
        long[] a = stats(handle);
        if (a.length <= S_SHAPE) {
            gate("stats carries the cursor-shape slot", false,
                    "length=" + a.length + " want at least " + (S_SHAPE + 1)
                            + ": render.dll predates #88, so this leg has nothing to read");
            return;
        }
        gate("a fresh handle has said no shape", a[S_SHAPE] == -1, "slot=" + a[S_SHAPE] + " want -1");
        final long errorsBefore = a[3];

        if (a[S_SHAPE] == -1 && errorsBefore == 0) {
            paint("DECSCUSR 5 asks for a vertical bar", "\u001b[5 q");
            long[] b = stats(handle);
            gate("the bar is said, or the export is absent", b[S_SHAPE] == 2 || b[S_SHAPE] == -1,
                    "slot=" + b[S_SHAPE] + " want 2 (accepted) or -1 (no such export)");
            gate("asking for a shape cost no API error", b[3] == errorsBefore,
                    "apiErrors=" + (b[3] - errorsBefore) + " added by the bar request");
            gate("and the census gained no refusal for a modelled CSI", b[S_UN] == a[S_UN],
                    "unrecognised=" + (b[S_UN] - a[S_UN])
                            + ": `5 q` has its own dispatch case, so no census slot may move");
            if (b[S_SHAPE] == 2) {
                shapePresentArmRan = true;
                paint("DECSCUSR 1 walks it back to a block", "\u001b[1 q");
                long[] c = stats(handle);
                gate("the block is said again rather than the bar left standing", c[S_SHAPE] == 1,
                        "slot=" + c[S_SHAPE] + " want 1: lastShapeStyle is the only record the bar was ever there");
                long[] v = consoleView();
                gate("and the height door still answers the model", v.length > 0, "consoleView empty");
                paint("RIS drops the shape", "\u001bc");
                long[] d = stats(handle);
                gate("a reset shape is nobody's shape", d[S_SHAPE] == 1 || d[S_SHAPE] == -1,
                        "slot=" + d[S_SHAPE] + " want 1 (RIS re-asks the block) or -1 (never said again)");
                gate("and the whole walk still cost no API error", d[3] == errorsBefore,
                        "apiErrors=" + d[3] + " against " + errorsBefore);
            } else {
                System.out.println("SKIP this kernel32 has no SetConsoleCursorShape -- the shape arms cannot run");
                shapePresentArmRan = false;
            }
        } else {
            gate("the leg starts from an untouched handle", false,
                    "shape=" + a[S_SHAPE] + " apiErrors=" + errorsBefore + ": an earlier case left state");
        }
        standardGeometry("leaving the viewport as the next case expects it");
    }

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
        final long[] now = stats(handle);
        gate("stats() carries the same count the export does",
                now[S_ARGTRUNC] == argTrunc(handle) && now[S_ARGTRUNC] - a[S_ARGTRUNC] == 4,
                "stats=" + now[S_ARGTRUNC] + " (delta " + (now[S_ARGTRUNC] - a[S_ARGTRUNC]) + ") export="
                        + argTrunc(handle) + " want 4 at slot " + S_ARGTRUNC);
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
        span("and every row below it went with it", winT + 3, 0, 3, ' ', DEF);
        span("including the window's last", winT + 4, 0, 3, ' ', DEF);
        final long[] b = stats(handle);
        gate("none of it was counted as unsupported", b[S_UN] - a[S_UN] == 0,
                "unrecognised=" + (b[S_UN] - a[S_UN]) + ": IL, DL and a long CUP are all modelled");
        gate("and nothing was declined", b[2] - a[2] == 0, "declines=" + (b[2] - a[2]));
        paint("leave the rows clean", "\u001b[1;1H\u001b[J");
    }

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

    private static void caseWindowOps() {
        if (!standardGeometry("the window-op leg")) return;
        final long[] a = stats(handle);

        readInput(0);
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

    private static void caseInbandResize() {
        if (!standardGeometry("the in-band size leg")) return;
        final long[] a = stats(handle);
        if (a.length != S_LEN) {
            gate("stats() is this gate's slot table before the leg reads it", false,
                    "length=" + a.length + " want " + S_LEN + ": render.dll is not the build this leg was cut for");
            return;
        }
        readInput(0);

        final long[] armed = stats(handle);
        paint("the application asks for in-band size reports", "\u001b[?2048h");
        long[] b = stats(handle);
        gate("it costs no refused-mode vote", b[S_UN + 4] - armed[S_UN + 4] == 0,
                "mode=" + (b[S_UN + 4] - armed[S_UN + 4]) + ": a stored promise is not an unmodelled one");
        gate("and no reply was owed, so none was written", b[S_REPLIED] - armed[S_REPLIED] == 0,
                "written=" + (b[S_REPLIED] - armed[S_REPLIED]));
        eqInput("nothing for the shape the session is already in", "");
        paint("and asks whether it is on", "\u001b[?2048$p");
        eqInput("1 = set, which is what the stored bit now earns", "\u001b[?2048;1$y");

        final int newRows = WIN_H - 5;
        gate("the console takes the shorter window", setGeometry(BUF_W, BUF_H, WIN_W, newRows, DEF) != 0,
                "setGeometry " + newRows);
        gate("the rebuild is accepted", readopt(handle) == 1, "readopt refused");
        final long[] before = stats(handle);
        paint("the next chunk", "\u001b[1;1HIB");
        eqInput("arrives with one unsolicited report, spelled like 18t and carrying the new viewport",
                "\u001b[8;" + newRows + ";" + BUF_W + "t");
        final long[] c = stats(handle);
        gate("it is counted as a reply written, not as a refusal", c[S_REPLIED] - before[S_REPLIED] == 1,
                "written=" + (c[S_REPLIED] - before[S_REPLIED]) + " full-queue refusals="
                        + (c[S_REPLY_FULL] - before[S_REPLY_FULL]));
        gate("and no console call failed on the way", c[3] - before[3] == 0, "apiErrors=" + c[3]);
        paint("a chunk that moves nothing", "\u001b[2;1HCD");
        eqInput("says nothing again: one geometry, one report", "");
        paint("and asks, after the rebuild", "\u001b[?2048$p");
        eqInput("the mode is still the application's", "\u001b[?2048;1$y");

        paint("the application takes it back", "\u001b[?2048l");
        paint("and asks, to prove the store worked", "\u001b[?2048$p");
        eqInput("2 = reset, and nothing else", "\u001b[?2048;2$y");
        gate("the window goes back to its height", setGeometry(BUF_W, BUF_H, WIN_W, WIN_H, DEF) != 0,
                "setGeometry " + WIN_H);
        gate("the rebuild is accepted", readopt(handle) == 1, "readopt refused");
        paint("the next chunk after a second real change", "\u001b[1;1HEF");
        eqInput("stays silent while the mode is off", "");
        final long[] d = stats(handle);
        gate("and the silence costs nothing in the census", d[S_REPLY_FULL] - c[S_REPLY_FULL] == 0,
                "full=" + (d[S_REPLY_FULL] - c[S_REPLY_FULL]));
        standardGeometry("leaving the viewport as the next case expects it");
    }

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

    private static final int AB_A = 10, AB_B = 14;
    private static final int AB_ROWS = 3;

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

        legs("wide glyph then BS", "\u3042\b_", Boolean.TRUE, dll);
        legs("wide glyph then two BS", "\u3042\b\b_", Boolean.TRUE, dll);
        legs("narrow after wide, then BS", "\u3042a\b_", Boolean.FALSE, dll);
        legs("narrow after wide, then two BS", "\u3042a\b\b_", Boolean.TRUE, dll);
        legs("wide then BS then wide", "\u3042\b\u4e2d", Boolean.TRUE, dll);
        legs("BS at the start of a row", "\bX", Boolean.TRUE, dll);
        legs("tab after a wide glyph", "\u3042\tX", Boolean.TRUE, dll);
        legs("astral pair", "\uD83D\uDE00X", Boolean.FALSE, dll);

        String full = line(BUF_W);
        legs("full row then CR then Y", full + "\rY", Boolean.TRUE, dll);
        legs("full row then BS then Y", full + "\bY", Boolean.TRUE, dll);
        legs("full row then EL", full + "\u001b[K", Boolean.TRUE, dll);
        legs("full row then CUU then Y", full + "\u001b[A" + "Y", Boolean.TRUE, dll);

        legsSame("DECSTBM then a scroll",
                "\u001b[2;4r" + "AAAA\u001b[B" + "BBBB\u001b[B" + "CCCC\n", Boolean.TRUE, dll, 1);
        legs("DECAWM off at the margin", "\u001b[?7l" + line(BUF_W) + "Q\u001b[?7h", Boolean.FALSE, dll);
    }

    private static String line(int n) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < n; i++) sb.append((char) ('A' + i % 26));
        return sb.toString();
    }

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
    }

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

    private static void cleanBand(int base) {
        for (int k = 0; k < AB_ROWS; k++) {
            gotoRow(base + k);
            paint("clean row " + k, "\u001b[0m\u001b[K");
        }
    }

    private static String head(long[] r) {
        StringBuilder sb = new StringBuilder();
        for (int c = 0; c < r.length && c < 26; c++) {
            int ch = (int) (r[c] & 0xFFFF);
            sb.append(ch >= 0x20 && ch < 0x7f ? (char) ch : '.');
        }
        return sb.toString();
    }

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

    private static void caseDecawm() {
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

    private static void caseBareLf() {
        gotoRow(10);
        paint("bare lf", "ab\ncd\nef");
        text("bare lf row 0", winT + 10, 0, "ab", DEF);
        text("bare lf row 1", winT + 11, 0, "cd", DEF);
        text("bare lf row 2", winT + 12, 0, "ef", DEF);
        tail("bare lf last row", winT + 12, 2, DEF);
    }

    private static void caseNarrowRepaint() {
        gotoRow(8);
        StringBuilder sb = new StringBuilder("\u001b[43m");
        for (int i = 0; i < 60; i++) sb.append('Y');
        sb.append("\u001b[0m");
        paint("long frame", sb.toString());
        text("long frame", winT + 8, 0, "YYYYYYYYYYYY", 0x67);
        tail("long frame untouched tail", winT + 8, 60, DEF);
        gotoRow(8);
        paint("short frame", "AB");
        text("short frame", winT + 8, 0, "AB", DEF);
        text("short frame leaves the old text", winT + 8, 2,
                "YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY", 0x67);
        tail("short frame tail is not yellow", winT + 8, 60, DEF);

        paint("one column in the middle", "\u001b[31GZ");
        cell("mid-column rewrite", winT + 8, 30, 'Z', DEF);
        cell("the yellow left of it stayed", winT + 8, 29, 'Y', 0x67);
        cell("and the yellow right of it", winT + 8, 31, 'Y', 0x67);
        text("so the row is intact either side", winT + 8, 32, "YYYYYYYYYYYY", 0x67);
    }

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

    private static void caseAltScreen() {
        long[] s0 = stats(handle);
        final int declines0 = (int) s0[2], altbuf0 = (int) s0[S_UN + 2];
        final int altSwitch0 = (int) s0[S_ALT], refused0 = (int) s0[S_ALT_FAIL];
        final int hist0 = (int) s0[15];

        final int top0 = winT;
        long[] above = top0 > 0 ? row(top0 - 1) : null;
        long[] first = row(top0);
        long[] middle = row(top0 + WIN_H / 2);
        long[] last = row(top0 + WIN_H - 1);

        gotoRow(WIN_H / 2);
        long[] before = consoleView();
        final int curX = (int) before[5], curY = (int) before[6];

        final int n = WIN_H + 5;
        StringBuilder alt = new StringBuilder("\u001b[?1049h\u001b[H");
        for (int i = 1; i <= n; i++) {
            if (i > 1) alt.append("\r\n");
            alt.append(String.format("A%-3d", i));
        }
        paint("alt screen", alt.toString());
        gate("the window did not move for the alt", winT == top0, "winT " + top0 + " -> " + winT);
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

    private static void caseRealign() {
        if (setGeometry(BUF_W, BUF_H, 80, 24, DEF) == 0) { gate("resize", false, "setGeometry"); return; }
        char[] c = "stale geometry".toCharArray();
        feed(handle, c, 0, c.length);
        int decline = flush(handle);
        drainSgr();
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
        text("after realign keeps the row", winT, 2, "llo world", DEF);
        span("after realign tail", winT, 11, BUF_W - 1, ' ', DEF);

        if (setGeometry(BUF_W, BUF_H, 60, 24, DEF) == 0) { gate("narrow resize", false, "setGeometry"); return; }
        winT = (int) consoleView()[0];
        gotoRow(1);
        paint("window narrower than the model", "wide>\u001b[K");
        text("a narrow window paints", winT + 1, 0, "wide>", DEF);
        span("a narrow window paints to dwSize.X", winT + 1, 5, BUF_W - 1, ' ', DEF);
        s = stats(handle);
        gate("and none of it was declined", s[2] == 0, "declines=" + s[2]);
    }

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

        a = stats(handle);
        paint("two more", "\u001b[1\\\u001b[2\\");
        b = stats(handle);
        gate("two unmodelled finals, one adopt", b[4] - a[4] == 1, "aligns=" + (b[4] - a[4]));
        gate("and both were counted", b[S_UN] - a[S_UN] == 2, "unrecognised=" + (b[S_UN] - a[S_UN]));

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
        gate("a stored mouse mode votes nothing", b[S_UN + 3] - a[S_UN + 3] == 0,
                "mouse=" + (b[S_UN + 3] - a[S_UN + 3]) + ": #81 turned this family from a refusal into a store,"
                        + " and the census has to say so or it is charging a program for a mode it got");
        gate("and still change nothing the model has to trust", b[4] - a[4] == 0, "aligns=" + (b[4] - a[4]));
        a = b;
        paint("the one mouse number left refused", "\u001b[?1001h");
        b = stats(handle);
        gate("the mouse bucket still has a live witness", b[S_UN + 3] - a[S_UN + 3] == 1,
                "mouse=" + (b[S_UN + 3] - a[S_UN + 3]) + " want 1: a slot nothing votes for cannot be checked,"
                        + " and `1001` is the member this build does not hold");
        gate("and a refusal is inert, not suspected", b[4] - a[4] == 0, "aligns=" + (b[4] - a[4])
                + ": reading a byte and deciding to do nothing is not a reason to repaint the window");

        gotoRow(6);
        paint("clear for the census leg", "\u001b[0m\u001b[K");
        a = stats(handle);
        paint("the -7 arms", "\u001b[p\u001b[61p\u001b)0q");
        b = stats(handle);
        gate("the CSI p family is still counted", b[S_UN] - a[S_UN] == 2,
                "unrecognised=" + (b[S_UN] - a[S_UN]) + " want 2: `ESC ) 0` left this slot when #85 modelled G1");
        gate("and a modelled designator votes nothing anywhere", b[S_UN + 12] - a[S_UN + 12] == 0,
                "charset=" + (b[S_UN + 12] - a[S_UN + 12]) + ": `)0` is acted on, not refused");
        paint("a set this build cannot render", "\u001b)Uq");
        long[] c = stats(handle);
        gate("lands in the charset slot, not in unrecognised",
                c[S_UN + 12] - b[S_UN + 12] == 1 && c[S_UN] - b[S_UN] == 0,
                "charset=" + (c[S_UN + 12] - b[S_UN + 12]) + " unrecognised=" + (c[S_UN] - b[S_UN])
                        + ": the census must not keep calling a read arm 'no case for' (I26's near relation)");
        gate("and none of it buys a repaint", c[4] - a[4] == 0, "aligns=" + (c[4] - a[4])
                + ": a charset with no model moves no cursor, so it must not cost a window repaint");
        text("while the byte after them reached the screen", winT + 6, 0, "q", DEF);

        gotoRow(6);
        paint("leave the row as we found it", "\u001b[0m\u001b[K");
    }

    private static void caseNoScrollback() {
        long outer = handle;
        handle = 0;
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

    private static void caseWinchPrompt() {
        if (!standardGeometry("the WINCH redisplay leg")) return;
        final int rows = WIN_H - 4;
        StringBuilder sb = new StringBuilder();
        for (int r = 1; r <= WIN_H; r++)
            sb.append("\u001b[").append(r).append(";1HROW ").append(r).append("\u001b[K");
        gate("the listing was painted through the production path", renderChunk(handle, sb.toString().toCharArray()) == 1,
                null);
        drainSgr();
        if (setGeometry(BUF_W, BUF_H, WIN_W, rows, DEF) == 0) {
            gate("a shorter window", false, "setGeometry");
            return;
        }
        final long[] before = stats(handle);
        final int promptRow = rows - 2;
        final String winch = "\r\u001b[J\u001b[" + promptRow + ";1HSQL> ";
        final int rc = renderChunk(handle, winch.toCharArray());
        drainSgr();
        winT = (int) consoleView()[0];
        final long[] s = stats(handle);
        gate("the WINCH chunk was PAINTED, not handed back raw", rc == 1,
                "render=" + rc + " (0 = RAW: the caller would WriteConsoleW these bytes, and that call"
                        + " parses no escapes)");
        gate("at most the one decline the repair has to remember", s[2] - before[2] <= 1,
                "declines=" + (s[2] - before[2]));
        gate("and no console call failed", s[3] == before[3], "apiErrors=" + (s[3] - before[3]));

        final long[] shape = consoleView();
        final int top = (int) shape[0];
        final int winRows = (int) shape[8] - (int) shape[0] + 1;
        final StringBuilder found = new StringBuilder();
        int escRows = 0;
        for (int i = 0; i < winRows; i++) {
            final long[] row = row(top + i);
            if (row == null) continue;
            final StringBuilder t = new StringBuilder();
            for (int k = 0; k < 8 && k < row.length; k++) t.append((char) (int) (row[k] & 0xFFFF));
            if (t.toString().startsWith("SQL>")) found.append(" win-row ").append(i);
            for (int k = 0; k < row.length; k++)
                if ((int) (row[k] & 0xFFFF) == 0x1B) { escRows++; break; }
        }
        gate("the prompt is on the row the handler addressed", found.length() > 0,
                "found at:" + (found.length() > 0 ? found.toString() : " NOWHERE in the window")
                        + " (addressed viewport row " + promptRow + ", window is " + winRows + " rows)");
        gate("and no row on screen holds a literal ESC -- the raw fallback's signature", escRows == 0,
                "rows with U+001B = " + escRows);
        text("the erase took the stale listing off that row", top + promptRow - 1, 4, " ", DEF);
        standardGeometry("leaving the viewport as the next case expects it");
    }

    private static int renderChunk(long h, char[] c) {
        try {
            final java.lang.reflect.Method m = NativeRenderer.class.getDeclaredMethod(
                    "render", long.class, char[].class, int.class, int.class);
            m.setAccessible(true);
            return ((Integer) m.invoke(null, new Object[] { Long.valueOf(h), c,
                    Integer.valueOf(0), Integer.valueOf(c.length) })).intValue();
        } catch (Throwable e) {
            gate("render() was reachable", false, String.valueOf(e));
            return -99;
        }
    }

    private static void caseAdoptReadOnly() {
        if (!standardGeometry("the adopt-reads-only leg")) return;
        final int window = BUF_W * WIN_H;

        StringBuilder sb = new StringBuilder();
        for (int r = 1; r <= WIN_H; r++) sb.append("\u001b[").append(r).append(";1HROW ").append(r).append("\u001b[K");
        paint("a window full of text", sb.toString());
        long[] p = plan(handle);
        gate("the setup filled the window, so there is a repaint here to withhold",
                p[18] >= window / 2, "cells=" + p[18] + " of a " + window + "-cell window");
        text("the setup is on screen", winT + 6, 0, "ROW 7", DEF);
        final long paints0 = stats(handle)[1];

        gate("align() adopts the window again", align(handle) == 1, null);
        flushQuietly();
        p = plan(handle);
        gate("an adopt of rows it just read names no cells", p[18] == 0,
                "cells=" + p[18] + ": the old answer marked the viewport dirty at the adopt and this shape"
                        + " re-emits " + window + " cells of text the renderer only read");
        gate("and no rectangle reached the console", stats(handle)[1] == paints0,
                "paints=" + (stats(handle)[1] - paints0) + " expected 0");
        text("the adopt left the picture alone", winT + 6, 0, "ROW 7", DEF);
        long[] s = stats(handle);
        gate("no console call failed on the way", s[3] == 0, "apiErrors=" + s[3]);

        if (setGeometry(BUF_W, BUF_H, WIN_W, WIN_H - 6, DEF) == 0) {
            gate("a shorter window", false, "setGeometry");
            return;
        }
        gate("a rebuild for the new shape", readopt(handle) == 1, null);
        flushQuietly();
        p = plan(handle);
        gate("a rebuild emits nothing until the application writes", p[18] == 0,
                "cells=" + p[18] + " after readopt()+flush(): resize used to cost a viewport re-emission"
                        + " on every frame that followed a shape change");
        gate("and the shorter window still shows the rows it adopted", stats(handle)[1] == paints0,
                "paints=" + (stats(handle)[1] - paints0) + " expected 0");

        paint("one glyph after a rebuild", "\u001b[3;1Hx");
        p = plan(handle);
        gate("a real change still gets its rectangle", p[18] >= 1 && p[18] < window / 10,
                "cells=" + p[18] + " against a " + window + "-cell window");
        text("and it is the glyph that was asked for", (int) consoleView()[0] + 2, 0, "x", DEF);
        standardGeometry("leaving the viewport as the next case expects it");
    }

    private static void caseHookDecline() {
        long outer = handle;
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
        drainSgr();
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

    private static void caseWideBuffer() {
        long outer = handle;
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

    private static void caseScrollKeepsHistory() {
        final String line = "SQL > select * from v$session";
        long outer = handle;
        handle = 0;
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

        final int CHUNK = 20, NLINES = 100;
        for (int i = 0; i < NLINES; i += CHUNK) {
            final int last = Math.min(i + CHUNK, NLINES) - 1;
            StringBuilder sb = new StringBuilder();
            for (int k = i; k <= last; k++) sb.append("HIST ").append(k).append(" - the user's history\r\n");
            paint("HIST " + i + ".." + last, sb.toString());
            long[] tv = consoleView();
            long[] pl = plan(handle);
            final int newest = findRow("HIST " + last + " -", 0, BUF_H);
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
        final int base = winT - hist;
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
                if (r >= 80 && r < BUF_H - 70) continue;
                long[] rw = row(r);
                System.out.println("  MAP " + r + " [" + (rw == null ? "?" : head(rw)) + "]");
            }
        }
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

        v = consoleView();
        gate("the window stayed where the user scrolled it", v[0] == 0, "winT=" + v[0]);
        gate("and the console cursor did not follow the output",
                v[5] == 0 && v[6] == 0, "(" + v[5] + "," + v[6] + "): cursorOffView means no call at all");
        System.out.println("  cost of one line into a scrolled-back console: cells=" + (s[5] - cells)
                + " flushes=" + s[0] + " scrolls=" + s[6]);

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
        drainSgr();
        gate("a resize declines the chunk instead of guessing rows", rc == -1, "flush=" + rc);
        gate("and a decline wrote no scrollback row at all", diffRows(was, 0, base, why) == 0, "why=" + why);
        why.setLength(0);

        long[][] mine = new long[BUF_H - base][];
        for (int r = base; r < BUF_H; r++) {
            mine[r - base] = row(r);
        }
        s = stats(handle);
        final int aligns = (int) s[4], declines = (int) s[2];
        gate("the resize rebuilt this handle's model, and only its model", readopt(handle) == 1,
                "readopt returned 0: the console is not the shape the gate just set");
        flushQuietly();
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

        close(handle);
        handle = outer;
    }

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

    private static String rowHead(int r) {
        if (r < 0) return "-";
        long[] rw = row(r);
        return rw == null ? "?" : head(rw);
    }

    private static void caseFullBufferEvicts() {
        final String line = "SQL > select count(*) from v$session";
        final int CHUNK = 20, NLINES = BUF_H + 20;
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
        final int base = winT - hist;
        gate("so the claim ends on the buffer's last row as well", base + rows == BUF_H,
                "base=" + base + " rows=" + rows + " of " + BUF_H
                        + ": there is no row below it left to write into, which is the premise of this case. And"
                        + " because the window is already on the last row, no slide can move that premise: every"
                        + " flush from here plans row0 == base and pays its debt with an eviction.");
        gate("nothing was declined or failed on the way down", s[2] == 0 && s[3] == 0,
                "declines=" + s[2] + " apiErrors=" + s[3]);

        int[] run = histRun(0, BUF_H);
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

    private static void caseSnapOnInput() {
        final int NOGEOM = 0, NOCHANGE = 1, PARK = 2;
        final String PROMPT = "SQL > ready";
        long outer = handle;
        handle = 0;
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
        final int base = winT - hist;
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

        gate("a second keystroke answers NOCHANGE", snap(handle) == NOCHANGE, null);
        v = consoleView();
        gate("with the window still where the first put it", v[0] == oldWinT, "winT=" + v[0]);
        gate("and still one snap in total", (int) stats(handle)[S_SNAP] == snaps0 + 1,
                "snaps=" + stats(handle)[S_SNAP]);

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

        if (setGeometry(BUF_W, BUF_H, WIN_W, 24, DEF) == 0) {
            gate("the geometry for the shape-refusal leg", false, "setGeometry");
        } else {
            gate("a window that is not the model's shape answers NOGEOM", snap(handle) == NOGEOM, null);
        }

        close(handle);
        handle = outer;
    }

    private static void caseOpenRefusal() {
        final int NO_CONSOLE = 1, BIG = 2, WIDE = 3, NO_GUTTER = 4, OOM = 5;
        final int MAX_COLS = 4096, MAX_ROWS = 256;
        long outer = handle;
        handle = 0;
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

        long edge = open(WIDE_BUF_W, MAX_ROWS - 1, DEF);
        gate("one row less is accepted: the limit is the gutter, not the screen", edge != 0,
                "status=" + NativeRenderer.openStatus());
        if (edge != 0) {
            close(edge);
        }

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

    private static void caseRelativeCursor() {
        if (!standardGeometry("the relative-motion leg")) return;
        final long[] a = stats(handle);
        paint("a region and its bottom row", "\u001b[0m\u001b[13;16r\u001b[16;1H");
        long[] v = consoleView();
        gate("the region put the cursor on its bottom row", v[5] == 0 && v[6] == winT + 15,
                "(" + v[5] + "," + v[6] + ") winT=" + winT);
        paint("CUD is clipped by the region", "\u001b[BX");
        text("the clipped CUD printed on the region's bottom row", winT + 15, 0, "X", DEF);
        paint("VPR walks past it", "\u001b[2eY");
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
        gate("neither final is counted as unsupported", b[S_UN] - a[S_UN] == 0,
                "RC_UN_SUP +" + (b[S_UN] - a[S_UN]));
        gate("and nothing was declined on their account", b[2] - a[2] == 0, "declines +" + (b[2] - a[2]));
        paint("region back to the whole viewport", "\u001b[r");
    }

    private static void caseSyncOutput() {
        if (!standardGeometry("the synchronized-region leg")) return;
        long[] a = stats(handle);
        paint("BSU on its own", "\u001b[0m\u001b[?2026h");
        long[] b = stats(handle);
        gate("the region is open", b[S_SYNC_ON] == 1, "sync=" + b[S_SYNC_ON]);
        gate("and counted as one region", b[S_SYNC_ENGAGES] - a[S_SYNC_ENGAGES] == 1,
                "engages=" + (b[S_SYNC_ENGAGES] - a[S_SYNC_ENGAGES]));
        gate("but a chunk with nothing to paint is not held", b[S_SYNC_HELD] - a[S_SYNC_HELD] == 0,
                "held=" + (b[S_SYNC_HELD] - a[S_SYNC_HELD]));
        gate("and the console saw no rectangle either", b[1] - a[1] == 0, "rects=" + (b[1] - a[1]));

        paint("a second BSU inside it", "\u001b[?2026h");
        b = stats(handle);
        gate("does not stack a region", b[S_SYNC_ON] == 1 && b[S_SYNC_ENGAGES] - a[S_SYNC_ENGAGES] == 1,
                "engages=" + (b[S_SYNC_ENGAGES] - a[S_SYNC_ENGAGES]));
        gate("but is counted as the nesting it was", b[S_SYNC_NESTED] - a[S_SYNC_NESTED] == 1,
                "nested=" + (b[S_SYNC_NESTED] - a[S_SYNC_NESTED]));

        paint("end the state legs' region", "\u001b[?2026l");
        final long cost = chunkCostMs();
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
        gate("in one paint, not one per chunk", b[1] - a[1] == nhold, "rects=" + (b[1] - a[1]));
        gate("and the region is closed", b[S_SYNC_ON] == 0, "sync=" + b[S_SYNC_ON]);
        gate("no timeout was needed for any of it", b[S_SYNC_TIMEOUT] - a[S_SYNC_TIMEOUT] == 0,
                "timeouts=" + (b[S_SYNC_TIMEOUT] - a[S_SYNC_TIMEOUT]));

        a = stats(handle);
        paint("a region nobody closes", "\u001b[?2026h\u001b[25;1HLEAKED");
        b = stats(handle);
        gate("its row is held", b[S_SYNC_HELD] - a[S_SYNC_HELD] == 1 && b[S_SYNC_ON] == 1,
                "held=" + (b[S_SYNC_HELD] - a[S_SYNC_HELD]) + " sync=" + b[S_SYNC_ON]);
        cell("and not on the screen", winT + 24, 0, ' ', DEF);
        sleep(200);
        paint("a later chunk, past the timeout", "\u001b[26;1HLATER");
        b = stats(handle);
        text("the leaked row painted with it", winT + 24, 0, "LEAKED", DEF);
        text("and so did the one that broke the wait", winT + 25, 0, "LATER", DEF);
        gate("the timeout fired once", b[S_SYNC_TIMEOUT] - a[S_SYNC_TIMEOUT] == 1,
                "timeouts=" + (b[S_SYNC_TIMEOUT] - a[S_SYNC_TIMEOUT]));
        gate("and it cleared the mode, so the next frame is not held too", b[S_SYNC_ON] == 0,
                "sync=" + b[S_SYNC_ON]);

        a = stats(handle);
        readInput(0);
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
        final int nlines = gutter + winRows + 12;
        final long[] a = stats(handle);
        int paintedDuring = 0;
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
        gate("the gutter forced frames before the ESU", paintedDuring >= 1,
                "paintedChunks=" + paintedDuring + " over " + nlines + " lines and a " + gutter + "-row gutter");
        gate("and some chunks really were deferred", b[S_SYNC_HELD] - a[S_SYNC_HELD] >= 1,
                "held=" + (b[S_SYNC_HELD] - a[S_SYNC_HELD]));
        gate("each one was the valve or the clock, and only once", over + blew == paintedDuring,
                "overflow=" + over + " timeout=" + blew + " painted=" + paintedDuring);
        gate("the valve fired at least once", over >= 1,
                "overflow=" + over + " painted=" + paintedDuring);
        gate("a frame lost to the gutter does not end the region", b[S_SYNC_ON] == 1 || blew >= 1,
                "sync=" + b[S_SYNC_ON] + " overflow=" + over + " timeout=" + blew);
        final long rectsAtClose = b[1];
        paint("close it", "\u001b[?2026l");
        b = stats(handle);
        gate("the ESU found nothing left to defer", b[S_SYNC_ON] == 0, "sync=" + b[S_SYNC_ON]);
        gate("and no console call failed on the way", b[3] - a[3] == 0, "apiErrors=" + (b[3] - a[3]));

        pl = plan(handle);
        final int at = findRow(rowTag(nlines - 1), winT, winT + (int) pl[12]);
        gate("the region's last line is on the screen", at >= 0,
                "want " + rowTag(nlines - 1) + " in rows " + winT + ".." + (winT + (int) pl[12]));
        if (at >= 0) {
            for (int k = 1; k < winRows - 1 && nlines - 1 - k >= 0; k++)
                text("row " + k + " above it is the line before", at - k, 0, rowTag(nlines - 1 - k), DEF);
        }
    }

    private static String rowTag(int i) {
        return "OVERFLOW-" + (i < 10 ? "000" : i < 100 ? "00" : i < 1000 ? "0" : "") + i;
    }

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

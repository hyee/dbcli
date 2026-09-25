package com.hyee.ansirender;

/**
 * The Java half of the native ANSI renderer: a handle, one call per chunk, and the sentences the library
 * can say about itself. Everything else -- parsing the escapes, holding the grid, deciding what to repaint,
 * deciding when to stop trusting the console -- is in {@code render.dll}.
 *
 * <p>The surface is deliberately one call. {@link #write} hands over a chunk and says whether it reached the
 * screen; the library owns the adoption of the console, the re-adoption after anything moved it, the run of
 * declines after which it stops being asked, and the wording of every refusal. A second implementation
 * would have to duplicate those decisions to be correct, which is why they are not here.
 *
 * <p>One rule for callers, and it is the whole contract: a {@code write} that returns false means
 * <em>nothing was painted</em>, so the same characters may be put in front of the console as-is without
 * duplicating them. Once a call returns true the chunk is finished and replaying it prints the text twice.
 * A false that came from {@link #isStopped} is different in kind -- the library has given up for the rest of
 * the session -- and {@link #unavailableReason} has the sentence. Read it before {@link #close}, because the
 * counters it describes go with the model.
 *
 * <p>This class is the library's only Java file: nothing else in {@code com.hyee.ansirender} is needed to
 * compile or run it, not even by the console gate in {@code src/c/conemu/Render.java}, which imports this
 * one class and nothing else. That is what lets a gate compile against the shipped {@code render.dll}
 * instead of against a lookalike.
 *
 * <p>Thread safety: every method that touches the handle is {@code synchronized} on the instance. The old
 * pairing between a write and a separate attribute echo is gone -- the renderer is the only thing in the
 * process reading the stream, so there is no second attribute state to keep in step.
 */
public final class NativeRenderer {

    /** render()'s three answers; see the RENDER_* enum in RenderJni.cpp. */
    private static final int GIVEUP = -1, RAW = 0, PAINTED = 1;

    /**
     * stats() slots, documented next to the function in RenderJni.cpp. Slots from 17 on are one per member
     * of {@code enum RcUnsupported} in Render.h <em>in that order</em>, so UNMODELLED below has to stay in
     * step with it and the three title slots move with that family's length; the gate prints both ends of
     * the seam in one run. The alt pair follows the titles, the OSC 133 pair follows that, and the older a
     * {@code render.dll}, the shorter its array -- which is why every family is length-gated in
     * {@link #unmodelled} rather than the whole line gated once at SLOT_LAST. A dll whose array stops at the
     * titles still has the sequence census, and that census is the only record of a private OSC that went
     * past unexecuted.
     */
    private static final int SLOT_UNSUPPORTED = 17, SLOT_TITLES = 28, SLOT_TITLES_TRUNC = 29,
            SLOT_TITLES_APPLIED = 30, SLOT_ALT = 31, SLOT_ALT_REFUSED = 32, SLOT_PROMPT_MARKS = 33,
            SLOT_LAST_EXIT = 34, SLOT_SNAP = 38,
            /* DECSET 2026's family, in the order RenderJni.cpp's STAT_SYNC gives them: regions opened, nested
               BSUs, flushes deferred, and the ways a region ended before its ESU. SLOT_SYNC_ON is the mode as
               it stands at teardown, not a count, and it is the one worth reading: a session that ended inside a
               synchronized region is a session where an application sent a BSU and never sent the ESU, and the
               counts next to it say whether that ever cost a frame. */
            SLOT_SYNC_ENGAGES = 39, SLOT_SYNC_NESTED = 40, SLOT_SYNC_HELD = 41,
            SLOT_SYNC_TIMEOUT = 42, SLOT_SYNC_OVERFLOW = 43, SLOT_SYNC_DECLINED = 44,
            SLOT_SYNC_ON = 45, SLOT_LAST = 46;

    /** The two answers Render.h gives a 133;D whose exit code was absent or was not a number. */
    private static final long EXIT_UNKNOWN = -1, EXIT_UNPARSABLE = 0x7FFFFFFFL;

    /** What each unsupported-sequence counter is, for the one line at teardown. */
    private static final String[] UNMODELLED = {"escape", "scroll region", "alt buffer", "mouse tracking",
            "mode", "bracketed paste", "private OSC 9", "other OSC", "DCS", "report request",
            "colon subparameter"};

    /**
     * ANSI_RENDER=off|0|false|no switches the renderer off; anything else -- including nothing at all --
     * leaves it on. Turning it off is also the first thing to try when a session paints oddly: the caller is
     * then left with its own raw write, which is always correct and only slower.
     */
    public static boolean isEnabled() {
        String v = System.getenv("ANSI_RENDER");
        return v == null
                || !(v.equals("0")
                        || v.equalsIgnoreCase("off")
                        || v.equalsIgnoreCase("false")
                        || v.equalsIgnoreCase("no"));
    }

    /**
     * ANSI_RENDER_LIB is a directory holding {@code render.dll}, loaded from it by absolute path. Only a
     * fallback: the normal case is that the launcher already has the install's own directory on PATH.
     * Nothing here guesses an install location.
     */
    private static String libDir() {
        return System.getenv("ANSI_RENDER_LIB");
    }

    /** The DLL is registered process-wide, so it is loaded once and never unloaded. */
    private static final Object LOAD_LOCK = new Object();
    private static boolean loaded;
    private static String loadError;

    /* Eager, and only recording a reason: a class the caller has to construct in order to find out it
       cannot work would push the try/catch into every writer. The DLL is one file, so the load also binds
       this class's natives for anything that touches it -- the gate included. */
    static {
        loadLibrary();
    }

    /** Which build of render.dll is loaded -- in the default report, because a stale DLL is the usual
     *  explanation for a gate that passes and a session that does not. */
    public static native String build();

    /**
     * Parse and paint one chunk: the whole per-chunk interface. Returns true when the chunk is on the
     * screen, false when nothing was written and the caller owns those bytes. See the class comment for the
     * difference between the two kinds of false.
     */
    public synchronized boolean write(char[] text, int len) {
        if (h == 0 || len <= 0 || stopped != null) {
            return false;
        }
        final int r = render(h, text, 0, len);
        if (r == PAINTED) {
            return true;
        }
        if (r == GIVEUP) {
            stopped = stopReason(h);          // the census stays readable: it outlives the model
        }
        return false;
    }

    /**
     * The view the user typed at: bring the prompt back if they had scrolled away from it. One call per key
     * press, and it is a no-op unless the model's cursor row is off the window, so a session that never
     * touches the scroll wheel never pays for it.
     *
     * <p>This is the leg conhost refuses to provide here. Its own input path snaps the view on a keystroke
     * only for a console in VTP mode, and the mode this renderer exists for is the one where VTP is off -- so
     * on a classic console driven by this library, nothing else ever moves the window back down and the user
     * types blind into a screen they cannot see. Silent once the library has stopped: a renderer that gave up
     * no longer knows where its rows are.
     *
     * <p>Silent, too, when the console has no symbol to give. A jar newer than the dll beside it throws
     * UnsatisfiedLinkError here, and this runs on the caller's input pump: a view-alignment nicety must not
     * be able to stop a terminal reading keys. So the library swallows that one error, once, and says so --
     * in here rather than in every caller, because the skew is this library's problem and its only witness.
     * The paint keeps working through it; only the snap is lost, which is why it does not set #stopped.
     */
    public synchronized void snapOnInput() {
        if (h == 0 || stopped != null || snapMissing) {
            return;
        }
        try {
            snap(h);
        } catch (UnsatisfiedLinkError e) {
            /* One retry can never succeed: a symbol absent from the export table is absent for the life of
               the process. Trying again would print once per keystroke. */
            snapMissing = true;
            System.err.println("native renderer: no snap-on-input -- " + e.getMessage()
                    + " (the library is older than the jar that loaded it; repaints are unaffected)");
        }
    }

    private boolean snapMissing;

    /**
     * One line of counters at teardown. It is the witness that a session ran on the native path at all: a
     * grid that looks right proves the same thing whether the library painted it or the console did.
     */
    public synchronized void report() {
        /* No line here for the stop reason: reportStopped() in the caller prints it as soon as a chunk
           comes back declined, which is when it is news. Repeating it at teardown turned the one honest
           sentence in this library into two. */
        if (h == 0) {
            return;
        }
        long[] s = stats(h);
        if (s[0] == 0 && s[2] == 0) {
            return;
        }
        /* Slot 16 is counted by the parser, not by a consumer: nothing reads the capture any more, so an
           overflow says only that one chunk carried more SGR than the scratch holds. It is on the line
           because a capture that small is worth seeing, not because the session lost anything. */
        System.err.println("native renderer: " + s[0] + " flush(es), " + s[1] + " rectangle(s), "
                + s[5] + " cell(s), " + s[6] + " scroll(s), " + s[4] + " align(s); " + s[2]
                + " decline(s), " + s[3] + " console call(s) failed, " + s[16]
                + " SGR capture overflow(s)" + unmodelled(s) + snapped(s));
    }

    /** Releases the native model and, if the library opened it, the console. Never unloads the DLL. */
    public synchronized void close() {
        if (h != 0) {
            close(h);
            h = 0;
        }
    }

    /** True when the caller may hand chunks over; false means use its own writer and nothing else. */
    public synchronized boolean isAvailable() {
        return h != 0;
    }

    /** True once the library has stopped for this session -- a declined chunk that will not be retried. */
    public synchronized boolean isStopped() {
        return h != 0 && stopped != null;
    }

    /**
     * Why the renderer is not running: the DLL load failure, a session the library stopped on, or the
     * open() refusal. It answers null only while the renderer is live, so a caller can print this and then
     * believe it. A stopped renderer still answers {@link #isAvailable} until it is closed, because the
     * caller has to reach this string first.
     */
    public synchronized String unavailableReason() {
        if (loadError != null) {
            return loadError;
        }
        if (stopped != null) {
            return stopped;
        }
        if (h != 0) {
            return null;
        }
        return "native renderer refused the console: " + openReason();
    }

    /* ------------------------------------------------------------------ natives ---------------------- */

    /**
     * A renderer for {@code console} (0 to open CONOUT$), sized from the console itself when cols/rows are
     * 0 and seeded from the live attribute when defAttr is negative. 0 on failure; {@link #openReason()}
     * says why. Production calls this once, from the constructor; the gate sizes the model itself.
     */
    public static native long open(long console, int cols, int rows, int defAttr);

    /**
     * Whether the console this process is attached to is a pseudo-console: the headless conhost a ConPTY
     * client (Windows Terminal, VS Code, an agent driving a pty) puts between the application and the
     * terminal that parses the escapes itself.
     *
     * <p>Ask this before choosing a writer, and do not substitute an environment variable for it.
     * {@code WT_SESSION} is inherited by a classic conhost window started from inside a WT session, so the
     * variable mis-classifies exactly the window where the two answers differ; this reads the fact off the
     * console's own window, which is VtIo mode as conhost reports it.
     *
     * <p>True means do not paint. Under a pseudo-console a write of cells is turned back into escape
     * sequences by a serializer that knows nothing about a model, so the rows this renderer chose, the
     * scroll it paid and the screen an adopt merely re-read all reach the user's terminal as new output --
     * and the terminal's scrollback, not this process, decides what history means.
     */
    public static native boolean isPseudoConsole();

    /**
     * {@link #isPseudoConsole()} in the one form a caller may use before it knows whether it is talking to a
     * library that can answer: null means "classify without this fact". A missing render.dll and an older one
     * -- an install whose jar has not caught up with the DLL, or the reverse -- both lack the export, and a
     * terminal-classification step must not turn that into a startup failure. Callers that get null fall
     * back to the environment, which is weaker and says so where it is used.
     */
    public static Boolean pseudoConsole() {
        if (!loadLibrary()) {
            return null;
        }
        try {
            return Boolean.valueOf(isPseudoConsole());
        } catch (Throwable ignored) {
            return null;
        }
    }

    /** render()'s work: adopt if needed, parse, paint, and apply the decline/re-adopt/give-up policy. */
    private static native int render(long h, char[] text, int off, int len);

    /** Why the last open() returned 0, as a sentence in the language the user is supposed to read. */
    public static native String openReason();

    /** Why render() gave up on this console, or null when it has not. */
    private static native String stopReason(long h);

    /** Counters for {@link #report()}; the slot table is in RenderJni.cpp, the names this uses are SLOT_*. */
    public static native long[] stats(long h);

    /**
     * What the last {@code OSC 9;4} asked for, as {@code {state, progress, seen}}, or null when there is
     * nothing to report. The library parses the safe part of ConEmu's private dialect (the same line
     * microsoft/terminal draws at {@code DoConEmuAction}) and stops there: it owns no window, so the caller
     * with a taskbar -- or a status bar -- is the one that acts. {@code state} is 0..4 as the sequence said,
     * {@code progress} is clamped to 0..100, and {@code seen} says whether any {@code 9;4} arrived at all,
     * because state 0 is an instruction ("remove the indicator") and not an absence.
     */
    public static long[] taskbar(long h) {
        if (!loadLibrary()) {
            return null;
        }
        try {
            return taskbar0(h);
        } catch (Throwable ignored) {
            return null;                       /* an older render.dll has no such export */
        }
    }

    private static native long[] taskbar0(long h);

    /**
     * The directory the last {@code OSC 9;9} named, or null. Text only, on purpose: a working directory read
     * out of an output stream is data about where a shell believes it is, and calling {@code chdir} on it
     * from a renderer would be the same class of overreach as the {@code 9;7} this library never runs.
     */
    public static String workingDirectory(long h) {
        if (!loadLibrary()) {
            return null;
        }
        try {
            return workingDirectory0(h);
        } catch (Throwable ignored) {
            return null;
        }
    }

    private static native String workingDirectory0(long h);

    public static native void close(long h);

    /* Low level, and public only because the console gate in src/c/conemu/Render.java drives the layers
       under render() one call at a time to check the grid against the real console. Production calls none
       of them, and a caller that mixes them with write() is adopting a half-finished chunk. */

    public static native int feed(long h, char[] text, int off, int len);

    public static native int flush(long h);

    /** The SGR bytes consumed since the last clear, or null -- the gate's parity witness. */
    public static native char[] sgr(long h);

    /** Adopt the console's current cells, cursor and attribute; 0 when its shape is not the model's. */
    public static native int align(long h);

    /**
     * Move the window so the model's cursor row is on it, the least way that can be done. Writes no cell:
     * the buffer already holds the rows this model painted, and the window only decides which of them the
     * user is looking at. Returns 2 when it asked the console to move, 1 when there was nothing to do, 0
     * when the console's shape is not the model's and an {@link #align} is what that console needs.
     */
    public static native int snap(long h);

    /** The open() refusal as a code, for a gate that asserts which refusal it got. */
    public static native int openStatus();

    /* ------------------------------------------------------------------- state --------------------- */

    private final long console;
    private long h;
    private String stopped;

    /**
     * @param console the screen buffer handle to render into, or 0 to let the library open CONOUT$.
     *                Pass the handle when the caller has already chosen a buffer: it may not be the
     *                standard output one.
     */
    public NativeRenderer(long console) {
        this.console = console;
        if (!loadLibrary()) {
            return;
        }
        h = open(console, 0, 0, -1);
        if (h == 0) {
            return;
        }
        if (align(h) == 0) {
            close(h);
            h = 0;
            stopped = "native renderer could not adopt the console";
        }
    }

    /**
     * The sequences this session's output contained that the renderer consumes without modelling, and the
     * state each of them asked for outside the screen buffer. They are in the report because nothing else
     * can see them: a window title, a semantic prompt mark and a console-private macro all change state that
     * no grid diff and no screenshot shows. The count is the only record that such a sequence went past, and
     * that this renderer did not run it.
     *
     * <p>Each family is present only in a render.dll new enough to report it, so each is gated on
     * {@link #has}: an older dll says which families it could not answer for, instead of the line throwing
     * at teardown -- where an exception would take the whole report with it, sequence census included.
     */
    private static String unmodelled(long[] s) {
        StringBuilder b = new StringBuilder();
        if (!has(s, SLOT_UNSUPPORTED + UNMODELLED.length - 1)) {
            return "; the loaded renderer reports no sequence counters";
        }
        for (int i = 0; i < UNMODELLED.length; i++) {
            if (s[SLOT_UNSUPPORTED + i] == 0) {
                continue;
            }
            b.append(b.length() == 0 ? "; not modelled: " : ", ").append(UNMODELLED[i])
                    .append(' ').append(s[SLOT_UNSUPPORTED + i]);
        }
        if (has(s, SLOT_TITLES_APPLIED) && s[SLOT_TITLES] != 0) {
            b.append("; ").append(s[SLOT_TITLES]).append(" title(s) set");
            if (s[SLOT_TITLES_APPLIED] != s[SLOT_TITLES]) {
                b.append(", ").append(s[SLOT_TITLES_APPLIED]).append(" reached the console");
            }
            if (s[SLOT_TITLES_TRUNC] != 0) {
                b.append(", ").append(s[SLOT_TITLES_TRUNC]).append(" truncated");
            }
        }
        if (has(s, SLOT_ALT_REFUSED) && s[SLOT_ALT] != 0) {
            b.append("; ").append(s[SLOT_ALT]).append(" alt-screen switch(es)");
            if (s[SLOT_ALT_REFUSED] != 0) {
                b.append(", ").append(s[SLOT_ALT_REFUSED]).append(" refused");
            }
        }
        if (has(s, SLOT_PROMPT_MARKS) && s[SLOT_PROMPT_MARKS] != 0) {
            b.append("; ").append(s[SLOT_PROMPT_MARKS]).append(" prompt(s) marked");
        }
        if (has(s, SLOT_LAST_EXIT) && s[SLOT_LAST_EXIT] != EXIT_UNKNOWN) {
            b.append("; last exit ");
            b.append(s[SLOT_LAST_EXIT] == EXIT_UNPARSABLE ? "?not a number"
                    : Long.toString(s[SLOT_LAST_EXIT]));
        }
        /* Only the facts a reader can act on. A region that ended normally is the whole point of the mode and
           needs no line; a flush that was held is worth a number, and a timeout is worth a sentence -- it means
           an application started a synchronized update and never finished it, which is a bug in it that this
           library quietly worked around. An overflow says the opposite: the application behaved, and its region
           was longer than this console's scrollback gutter, so the frames it wanted coalesced anyway. Both are
           per-session findings, not per-frame ones. */
        if (has(s, SLOT_SYNC_TIMEOUT) && s[SLOT_SYNC_TIMEOUT] != 0) {
            b.append("; ").append(s[SLOT_SYNC_TIMEOUT])
                    .append(" synchronized update(s) timed out (a BSU without its ESU)");
        }
        if (has(s, SLOT_SYNC_OVERFLOW) && s[SLOT_SYNC_OVERFLOW] != 0) {
            b.append("; ").append(s[SLOT_SYNC_OVERFLOW])
                    .append(" frame(s) painted early to keep the scrollback gutter from overflowing");
        }
        if (has(s, SLOT_SYNC_ON) && s[SLOT_SYNC_ON] != 0) {
            b.append("; still inside a synchronized update at close");
        }
        return b.toString();
    }

    /** Whether the loaded dll's array reaches slot {@code i} -- see the length gate in {@link #unmodelled}. */
    private static boolean has(long[] s, int i) {
        return s.length > i;
    }

    /**
     * The one clause that is not about the byte stream: how many times a keystroke found the user scrolled
     * away from the prompt and moved the view back. It stays off the line until it happens, because a session
     * that reports it is a session where somebody lost the prompt -- and that is the sentence worth having.
     */
    private static String snapped(long[] s) {
        return has(s, SLOT_SNAP) && s[SLOT_SNAP] != 0
                ? "; " + s[SLOT_SNAP] + " view(s) snapped back on input"
                : "";
    }

    private static boolean loadLibrary() {
        synchronized (LOAD_LOCK) {
            if (loaded) {
                return true;
            }
            try {
                System.loadLibrary("render");
                loaded = true;
                return true;
            } catch (Throwable pathFailure) {
                String dir = libDir();
                if (dir == null || dir.isEmpty()) {
                    loadError = "render.dll not found (ANSI_RENDER_LIB is unset): " + pathFailure;
                    return false;
                }
                try {
                    System.load(new java.io.File(dir, "render.dll").getAbsolutePath());
                    loaded = true;
                    return true;
                } catch (Throwable e) {
                    loadError = "render.dll failed to load: " + e;
                    return false;
                }
            }
        }
    }
}

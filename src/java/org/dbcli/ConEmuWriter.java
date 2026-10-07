package org.dbcli;

import com.hyee.ansirender.NativeRenderer;
import org.jline.nativ.Kernel32;
import org.jline.terminal.impl.AbstractWindowsConsoleWriter;

import java.util.concurrent.atomic.AtomicBoolean;

/**
 * The writer for a console whose escapes <b>this</b> process renders. It speaks ConEmu's escape protocol;
 * the rendering is done by {@link NativeRenderer}, which parses the sequences and paints the cells through
 * render.dll. A console that renders the escapes itself gets {@link WinConsoleWriter}.
 *
 * <p>Which of the two is chosen is decided by {@link WinSysTerminal#createTerminal}. It used to be askable
 * from the environment as well ({@code ANSICON_DEF=conemu}, #99 of 2026-09-27); that claim was retired on
 * 2026-10-07, and the only ways in now are the renderer's own names -- {@code ANSICON_DEF=render} and
 * {@code TERM=windows-render} -- plus the consoles that cannot parse their own escapes, where this writer is
 * the only parser available. The writer with one painter, not two, is then {@link NativeRenderer}'s job, not
 * this class's: the library that paints the cells takes ENABLE_VIRTUAL_TERMINAL_PROCESSING off the console it
 * opened and gives it back when it closes, because "one parser per byte stream" is a property of the painter
 * and every caller of the library has to get it, not only the one whose package happens to be
 * {@code org.dbcli}. The Win7-vs-Win10 divergence this removes is worse than either half of it: a chunk the
 * renderer declines would otherwise be drawn as colour on a 1809 console and as literal text on Windows 7.
 *
 * <p>Until 2026-09-24 this class also loaded ConEmuHk(64).dll and handed it every chunk the renderer
 * declined, through that DLL's exported {@code WriteProcessed3} -- ConEmu's in-process ANSI processor. That
 * leg is gone: the renderer is now the only parser in the process, so a declined chunk has nowhere to be
 * replayed. What happens instead depends on one question this class cannot answer for itself -- whether the
 * console <em>above</em> it reads escapes: if it does ({@code hostParses}), the bytes go out as they are and
 * that terminal parses them; if it does not, they are stripped and only the text is written, because
 * handing sequences to a screen that has nobody to read them is not "slower but correct", it is the literal
 * {@code [33m} on the user's face. The strip says so once. Removing the second parser also removed the two
 * things that existed only to keep it in step: the SGR replay and the exact-length marshalling JNA needed.
 *
 * <p>What is left is deliberately small. A writer whose second leg is "the operating system's console
 * functions" cannot disagree with anything, and the class of bug that made the old pairing necessary -- two
 * parsers, one silently wrong (the {@code [33m} literal, fg==bg) -- has no second member to disagree with
 * any more.
 */
public final class ConEmuWriter extends AbstractWindowsConsoleWriter {

    private final long console;
    /** The parse and the paint. Null when switched off or when it could not take this console. */
    private final NativeRenderer nativeRenderer;
    /** Whether the console above this writer reads the escapes itself (a pseudo-console, or a buffer whose
     *  VTP bit is set). When it does not, {@link #writeConsole} must not hand it literals. */
    private final boolean hostParses;
    private final AtomicBoolean reported = new AtomicBoolean(false);
    private final AtomicBoolean stoppedReported = new AtomicBoolean(false);
    private final AtomicBoolean strippedReported = new AtomicBoolean(false);

    public ConEmuWriter(long console, boolean hostParses) {
        super();
        this.console = console;
        this.hostParses = hostParses;
        NativeRenderer r = NativeRenderer.isEnabled() ? new NativeRenderer(console) : null;
        if (r != null && !r.isAvailable()) {
            report(r.unavailableReason());
            r = null;
        }
        /* A pseudo-console session paints like any other: render.dll owns the parse and the cells, and its
           executor pays every scroll debt with real line feeds so the host terminal's scrollback grows with
           the painted rows (the scroll API would be re-serialised as a blanking repaint -- measured
           2026-09-29, cache/ppty). Nothing here switches the painter off; the setPainting seam stays a
           library capability, not a production policy. */
        this.nativeRenderer = r;
    }

    @Override
    protected synchronized void writeConsole(char[] text, int len) {
        if (len <= 0) {
            return;
        }
        /* write() returning false means nothing was painted, so the bytes below are still whole. A false is
           one of two things -- this chunk was declined, or the renderer has stopped for good -- and only the
           second has a sentence, which reportStopped() prints once before the bytes go out. */
        if (nativeRenderer != null) {
            if (nativeRenderer.write(text, len)) {
                return;
            }
            reportStopped();
        }
        if (hostParses) {
            writeRaw(text, 0, len);
            return;
        }
        /* No painter in this process and no parser in the console above it: the escapes have nobody. Handing
           them over raw is what this used to do, on the strength of a comment claiming that was "always
           correct and only slower" -- it is not correct at all, it fills the screen with `\E[H\E[31m`.
           The fallback is therefore to strip the sequences and write the text: colour and cursor positioning
           are genuinely unavailable here, and saying so by printing the words "colour" cannot show is worse
           than not claiming them. The real fix stays render.dll's -- this path exists so a session that
           cannot load it reads as plain text instead of as garbage, and it says which once. */
        writeStripped(text, len);
    }

    /**
     * The user pressed a key, and this writer is the one holding the renderer that knows where their prompt
     * is. See {@link NativeRenderer#snapOnInput()}: on a console without VTP nobody else brings the view back
     * after they scroll up to read history, so the input pump asks here. No renderer, nothing to say.
     */
    public void snapOnInput() {
        if (nativeRenderer != null) {
            nativeRenderer.snapOnInput();
        }
    }

    /* ------------------------------------------------------------- A1: the input-report injection ----
     *
     * The pump has read a mouse or focus record off CONIN$; the model -- the only thing that parsed the
     * DECSET stream, because this writer took the host's parser off it -- is the one that knows which
     * protocol was armed, so the record goes there and comes back as the bytes the stream asked for.
     * Synchronized on this writer for the same reason writeConsole is: the pump thread and the writer
     * thread are the two hands this renderer has, and the model's tracking state (lastBtn, the
     * one-report-per-cell key) must not interleave with a parse in flight.
     *
     * @return true when the renderer answered -- including its "nothing is due" verdict, which is a
     *         decision the caller must obey rather than paper over with the legacy bytes. False only when
     *         there is no renderer to ask or the dll predates the seam, and the caller falls back to the
     *         X10 encoding it has always had.
     */
    public boolean writeMouseReport(int buttonState, int eventFlags, int ctrlKeyState,
                                    int x, int y, java.io.Writer pipe) throws java.io.IOException {
        final char[] buf = new char[40];
        final int n = encodeMouseInto(buf, x, y, buttonState, eventFlags, ctrlKeyState);
        if (n == -2) {
            return false;
        }
        if (n > 0) {
            pipe.write(buf, 0, n);
        }
        return true;
    }

    /**
     * The encoder alone holds the writer monitor. It has to: it reads the tracking state the parse side
     * writes (mouseFormat, lastBtn, the one-report-per-cell key), and those must not interleave with a parse
     * in flight.
     *
     * <p>The hand-off to the input pipe deliberately happens outside it. {@code pipe} is the reader's ring,
     * and a full ring blocks the writer until the reader drains it -- and the only reader is the thread that
     * runs {@code readLine()}, which is the same thread that paints through this writer. So a locked write
     * there is a cycle: this thread holds the monitor and waits on the ring, the painting thread waits on the
     * monitor, and nothing drains anything. The ring has its own lock and shares no state with the model, so
     * moving the copy out here costs no invariant the monitor was bought for.</p>
     */
    private synchronized int encodeMouseInto(char[] buf, int x, int y, int buttonState, int eventFlags,
                                             int ctrlKeyState) {
        if (nativeRenderer == null) {
            return -2;
        }
        return nativeRenderer.encodeMouse(x, y, -1, -1, buttonState, eventFlags, ctrlKeyState, buf);
    }

    /** Focus is the same seam with nothing to derive: the record says focused, the mode says report. */
    public boolean writeFocusReport(boolean focused, java.io.Writer pipe) throws java.io.IOException {
        final char[] buf = new char[3];
        final int n = encodeFocusInto(buf, focused);
        if (n == -2) {
            return false;
        }
        if (n > 0) {
            pipe.write(buf, 0, n);
        }
        return true;
    }

    /** Locked for the same reason as {@link #encodeMouseInto}, and released for the same reason. */
    private synchronized int encodeFocusInto(char[] buf, boolean focused) {
        if (nativeRenderer == null) {
            return -2;
        }
        return nativeRenderer.encodeFocus(focused, buf);
    }

    /**
     * Drop the escape sequences and keep the text: this is not a renderer, nothing is painted, moved or
     * coloured -- it only refuses to let a sequence reach a screen that has nobody to read it. The grammar is
     * the one the renderer's own table uses: CSI takes parameter bytes up to and including a final in
     * 0x40..0x7E (so {@code \E[<} SGR-mouse and {@code \E[?} private forms are consumed whole), OSC ends at
     * BEL or ST, and DCS/SOS/PM/APC run to ST.
     *
     * <p>It filters in place and returns the length to keep: {@code out} never passes {@code i}, so no second
     * buffer is allocated on a path that already had a large result set to move. Package-private and free of
     * console calls so the shape can be asserted without a screen (cache/strip-1007).</p>
     */
    static int stripSequences(char[] text, int len) {
        int out = 0;
        int i = 0;
        while (i < len) {
            char c = text[i];
            if (c != 0x1B) {
                text[out++] = text[i++];
                continue;
            }
            if (i + 1 >= len) {
                i++;                       // a lone ESC at the chunk edge: drop it, the next chunk is not ours
                continue;
            }
            char d = text[i + 1];
            if (d == '[') {
                i += 2;
                while (i < len && (text[i] < 0x40 || text[i] > 0x7E)) {
                    i++;
                }
                if (i < len) {
                    i++;                   // the final byte
                }
            } else if (d == ']') {
                i += 2;
                while (i < len) {
                    if (text[i] == 0x07) {
                        i++;
                        break;
                    }
                    if (text[i] == 0x1B && i + 1 < len && text[i + 1] == '\\') {
                        i += 2;
                        break;
                    }
                    i++;
                }
            } else if (d == 'P' || d == 'X' || d == '^' || d == '_') {
                i += 2;
                while (i < len) {
                    if (text[i] == 0x1B && i + 1 < len && text[i + 1] == '\\') {
                        i += 2;
                        break;
                    }
                    i++;
                }
            } else if (d == '(' || d == ')' || d == '*' || d == '+' || d == '#') {
                i += 3;                    // designator / DECALN: one indexed byte follows
            } else {
                i += 2;                    // any other two-character escape
            }
        }
        return out;
    }

    private void writeStripped(char[] text, int len) {
        reportStrippedOnce();
        writeRaw(text, 0, stripSequences(text, len));
    }

    /** Once per writer: plain text on a console that lost its painter is a fact the user should hear. */
    private void reportStrippedOnce() {
        if (strippedReported.compareAndSet(false, true)) {
            System.err.println("output is plain text: this console parses no escape sequences and "
                    + "render.dll is not painting (ANSI_RENDER=" + System.getenv("ANSICON_DEF")
                    + "); colour and cursor positioning are unavailable here");
        }
    }

    /** Keeps the output when the renderer cannot take it, instead of dropping it silently. */
    private void writeRaw(char[] text, int off, int len) {
        if (len <= 0) {
            return;
        }
        try {
            char[] rest = text;
            if (off != 0 || text.length != len) {
                rest = new char[len];
                System.arraycopy(text, off, rest, 0, len);
            }
            Kernel32.WriteConsoleW(console, rest, len, new int[1], 0L);
        } catch (Throwable ignored) {
            //nothing left to try
        }
    }

    /** One bounded line, once per writer: this runs inside a failure path, so it must not allocate
     *  a second copy of the buffer or throw on its own way out. */
    private void report(String message) {
        if (reported.compareAndSet(false, true)) {
            System.err.println(message);
        }
    }

    /** Once per writer, and only for a renderer that had started: it is the "why did the colour change
     *  half way through the session" question that has no other answer. */
    private void reportStopped() {
        String why = nativeRenderer.unavailableReason();
        if (why != null && stoppedReported.compareAndSet(false, true)) {
            System.err.println(why);
        }
    }

    @Override
    public void close() {
        if (nativeRenderer != null) {
            nativeRenderer.close();
        }
        super.close();
    }
}

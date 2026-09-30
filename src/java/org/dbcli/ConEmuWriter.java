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
 * <p>Which of the two is chosen is decided by {@link WinSysTerminal#createTerminal}, and since #99 a session
 * may ask for this one explicitly ({@code ANSICON_DEF=conemu}) even on a host whose console could parse. The
 * writer with one painter, not two, is then {@link NativeRenderer}'s job, not this class's: the library that
 * paints the cells takes ENABLE_VIRTUAL_TERMINAL_PROCESSING off the console it opened and gives it back when
 * it closes, because "one parser per byte stream" is a property of the painter and every caller of the
 * library has to get it, not only the one whose package happens to be {@code org.dbcli}. The Win7-vs-Win10
 * divergence this removes is worse than either half of it: a chunk the renderer declines would otherwise be
 * drawn as colour on a 1809 console and as literal text on Windows 7.
 *
 * <p>Until 2026-09-24 this class also loaded ConEmuHk(64).dll and handed it every chunk the renderer
 * declined, through that DLL's exported {@code WriteProcessed3} -- ConEmu's in-process ANSI processor. That
 * leg is gone: the renderer is now the only parser in the process, so a declined chunk has nowhere to be
 * replayed and is written raw instead, once, with the reason on stderr. Removing it also removed the two
 * things that existed only to keep a second parser in step: the SGR replay and the exact-length marshalling
 * JNA needed.
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
    private final AtomicBoolean reported = new AtomicBoolean(false);
    private final AtomicBoolean stoppedReported = new AtomicBoolean(false);

    public ConEmuWriter(long console) {
        super();
        this.console = console;
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
           second has a sentence, which reportStopped() prints once before the bytes go out raw. */
        if (nativeRenderer != null) {
            if (nativeRenderer.write(text, len)) {
                return;
            }
            reportStopped();
        }
        writeRaw(text, 0, len);
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

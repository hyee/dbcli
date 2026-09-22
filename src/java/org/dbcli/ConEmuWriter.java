package org.dbcli;

import com.sun.jna.Native;
import com.sun.jna.NativeLibrary;
import com.sun.jna.Pointer;
import com.sun.jna.ptr.IntByReference;
import com.sun.jna.win32.W32APIOptions;
import org.jline.nativ.Kernel32;
import org.jline.terminal.impl.AbstractWindowsConsoleWriter;

import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Renders ANSI by handing the text to ConEmuHk(64).dll, ConEmu's in-process ANSI processor, so this
 * is the console writer for a console without ENABLE_VIRTUAL_TERMINAL_PROCESSING (Windows 7 and
 * older, or an explicit ANSICON_DEF=conemu): the DLL hooks the console API and WriteProcessed3
 * turns the escape sequences into console API calls. A console that renders the escapes itself gets
 * {@link WinConsoleWriter}.
 */
public final class ConEmuWriter extends AbstractWindowsConsoleWriter {

    /**
     * Exported by both lib\x86\ConEmuHk.dll and lib\x64\ConEmuHk64.dll. Unlike WriteProcessed it
     * takes the console handle instead of resolving GetStdHandle(STD_OUTPUT_HANDLE) itself, which
     * matters because WinSysTerminal may have selected the STD_ERROR_HANDLE console.
     */
    static native boolean WriteProcessed3(
            char[] in_lpBuffer, int in_nLength, IntByReference out_lpNumberOfCharsWritten, Pointer hConsoleOutput);

    //JNA's registration is process wide, so the library is a singleton and it is never disposed:
    //NativeLibrary.dispose() is FreeLibrary, which would unload ConEmuHk and take its console hooks
    //down in the middle of the session.
    private static final Object LIBRARY_LOCK = new Object();
    private static NativeLibrary library;

    private final long console;
    private final boolean rendererAvailable;
    private final BulkCellWriter bulkWriter;
    private final IntByReference charsWritten = new IntByReference();
    private final AtomicBoolean reported = new AtomicBoolean(false);
    //reused when a write is shorter than the array JLine handed over
    private char[] scratch = new char[0];

    public ConEmuWriter(long console) {
        super();
        this.console = console;
        this.rendererAvailable = loadLibrary();
        if (!rendererAvailable) {
            report("dbcli: ConEmuHk is unavailable, console output is written without ANSI rendering");
        }
        //optional fast path (DBCLI_BULK_WRITE=on), see BulkCellWriter
        this.bulkWriter = BulkCellWriter.CONFIG.enabled ? new BulkCellWriter(console) : null;
    }

    private static boolean loadLibrary() {
        synchronized (LIBRARY_LOCK) {
            if (library != null) {
                return true;
            }
            try {
                //os.arch is x86 on a 32 bit JVM: lib\x86\ConEmuHk.dll, otherwise lib\x64\ConEmuHk64.dll
                library = NativeLibrary.getInstance(
                        "ConEmuHk" + ("x86".equals(System.getProperty("os.arch")) ? "" : "64"),
                        W32APIOptions.UNICODE_OPTIONS);
                Native.register(ConEmuWriter.class, library);
                return true;
            } catch (Throwable ignored) {
                library = null;
                return false;
            }
        }
    }

    @Override
    protected synchronized void writeConsole(char[] text, int len) {
        if (len <= 0) {
            return;
        }
        //Fast path: paint the whole chunk as one CHAR_INFO rectangle. It declines (returns false
        //without having touched the console) for anything it cannot express exactly - cursor moves,
        //erase, OSC, tabs, true colour, a line wider than the console - and the ANSI renderer below
        //then handles the chunk. ConEmuHk's own WriteConsoleOutputW hook only forwards the call, so
        //this avoids its per-line ExtWriteText work entirely.
        if (bulkWriter != null && bulkWriter.write(text, len)) {
            syncSgr(bulkWriter.takeSgrSync());
            return;
        }
        if (!rendererAvailable) {
            writeRaw(text, 0, len);
            return;
        }
        charsWritten.setValue(0);
        try {
            boolean ok = WriteProcessed3(marshall(text, len), len, charsWritten, Pointer.createConstant(console));
            int written = charsWritten.getValue();
            if (written < 0 || written > len) {
                written = ok ? len : 0;
            }
            if (written < len) {
                if (!ok) {
                    report("dbcli: ConEmuHk refused console output, falling back to WriteConsoleW");
                }
                writeRaw(text, written, len - written);
            }
        } catch (Throwable e) {
            report("dbcli: ConEmuHk call failed (" + e + "), falling back to WriteConsoleW");
            writeRaw(text, 0, len);
        }
    }

    /**
     * ConEmuHk keeps a process wide copy of the SGR state (CEAnsi::gDisplayParm) and re-applies it to
     * the console every time it renders a chunk itself (Ansi.cpp:2780, 2821). A chunk the rectangle
     * writer consumed never reached it, so without this replay the next chunk ConEmuHk renders - a
     * declined one, a command line, a prompt - would be painted with that stale colour. Only the
     * escape sequences are replayed: they carry no text and move no cursor.
     */
    private void syncSgr(String sgr) {
        if (sgr == null || sgr.isEmpty() || !rendererAvailable) {
            return;
        }
        try {
            char[] b = sgr.toCharArray();
            WriteProcessed3(b, b.length, charsWritten, Pointer.createConstant(console));
        } catch (Throwable ignored) {
            //the writer's own attribute handling still applies
        }
    }

    /**
     * JNA copies the whole array, and JLine hands over its shared 1024 char write buffer even for a
     * three char write, so marshal exactly the characters that are being written.
     */
    private char[] marshall(char[] text, int len) {
        if (text.length == len) {
            return text;
        }
        if (scratch.length < len) {
            scratch = new char[len];
        }
        System.arraycopy(text, 0, scratch, 0, len);
        return scratch;
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

    /** Prints the optional bulk-path statistics; deliberately does not unload ConEmuHk. */
    @Override
    public void close() {
        if (bulkWriter != null) {
            bulkWriter.report();
        }
        super.close();
    }
}

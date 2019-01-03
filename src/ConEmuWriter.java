package org.jline.terminal.impl.jansi.win;

import com.sun.jna.Native;
import com.sun.jna.NativeLibrary;
import com.sun.jna.win32.W32APIOptions;
import org.jline.terminal.impl.AbstractWindowsConsoleWriter;


import java.io.IOException;
import java.nio.CharBuffer;

import static org.fusesource.jansi.internal.Kernel32.GetStdHandle;
import static org.fusesource.jansi.internal.Kernel32.STD_OUTPUT_HANDLE;

public class ConEmuWriter extends AbstractWindowsConsoleWriter {
    static {
        NativeLibrary nativeLibrary = NativeLibrary.getInstance("ConEmuHk" + (System.getProperty("os.arch").equals("x86") ? "" : "64"), W32APIOptions.UNICODE_OPTIONS);
        Native.register(ConEmuWriter.class, nativeLibrary);
    }

    static final native boolean WriteProcessed(String in_lpBuffer, int in_nLength, int out_lpNumberOfCharsWritten);

    static final native boolean WriteProcessed3(String in_lpBuffer, int in_nLength, int out_lpNumberOfCharsWritten, long in_hConsoleOutput);

    private final long console;
    private CharBuffer buff = CharBuffer.allocate(8196);
    private int charsWritten = 0;

    public ConEmuWriter() {
        this(GetStdHandle(STD_OUTPUT_HANDLE));
    }

    @Override
    protected void writeConsole(char[] text, int len) throws IOException {

    }

    public ConEmuWriter(long console) {
        super();
        this.console = console;
    }

    @Override
    public final synchronized void write(final int b) throws IOException {
        if (buff.position() >= buff.limit()) flush();
        buff.put((char)b);
    }

    @Override
    public final synchronized void write(final char b[], final int off, final int len) throws IOException {
        if (buff.remaining() <= len) flush();
        if (buff.remaining() >= len) buff.put(b, off, len);
        else if (off == 0 && len == b.length) writeStdOut(new String(b));
        else {
            char[] b1 = new char[len];
            System.arraycopy(b, off, b1, 0, len);
            writeStdOut(new String(b1));
        }
    }

    @Override
    public final void write(final char b[]) throws IOException {
        write(b, 0, b.length);
    }

    @Override
    public final synchronized void flush() {
        final int len = buff.position();
        if (len > 0) {
            buff.flip();
            char[] b = new char[len];
            buff.get(b);
            buff.clear();
            writeStdOut(new String(b));
        }
    }

    private final void writeStdOut(final String str) {
        WriteProcessed3(str, str.length(), charsWritten, console);
    }
}
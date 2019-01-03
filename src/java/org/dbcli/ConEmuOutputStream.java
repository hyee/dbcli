package org.dbcli;

import com.sun.jna.Native;
import com.sun.jna.NativeLibrary;
import com.sun.jna.Pointer;
import com.sun.jna.ptr.IntByReference;
import com.sun.jna.win32.W32APIOptions;

import java.io.IOException;
import java.io.OutputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;

public class ConEmuOutputStream extends OutputStream {
    static {
        NativeLibrary nativeLibrary = NativeLibrary.getInstance("ConEmuHk" + (System.getProperty("os.arch").equals("x86") ? "" : "64"), W32APIOptions.UNICODE_OPTIONS);
        Native.register(ConEmuOutputStream.class, nativeLibrary);
    }

    private final Pointer console;
    private ByteBuffer buff = ByteBuffer.allocateDirect(8196);
    private IntByReference charsWritten = new IntByReference();

    public ConEmuOutputStream() {
        this(Kernel32.INSTANCE.GetStdHandle(Kernel32.STD_OUTPUT_HANDLE));
    }

    public ConEmuOutputStream(Pointer console) {
        super();
        this.console = console;
        this.buff.order(ByteOrder.nativeOrder());
    }

    static final native boolean WriteProcessed(String in_lpBuffer, int in_nLength, IntByReference out_lpNumberOfCharsWritten);

    static final native boolean WriteProcessed3(String in_lpBuffer, int in_nLength, IntByReference out_lpNumberOfCharsWritten, Pointer in_hConsoleOutput);

    @Override
    public final synchronized void write(final int b) throws IOException {
        if (buff.position() >= buff.limit()) flush();
        buff.put((byte) b);
    }

    @Override
    public final synchronized void write(final byte b[], final int off, final int len) throws IOException {
        if (buff.remaining() <= len) flush();
        if (buff.remaining() >= len) buff.put(b, off, len);
        else if (off == 0 && len == b.length) writeStdOut(new String(b));
        else {
            byte[] b1 = new byte[len];
            System.arraycopy(b, off, b1, 0, len);
            writeStdOut(new String(b1));
        }
    }

    @Override
    public final void write(final byte b[]) throws IOException {
        write(b, 0, b.length);
    }

    @Override
    public final synchronized void flush() throws IOException {
        final int len = buff.position();
        if (len > 0) {
            buff.flip();
            byte[] b = new byte[len];
            buff.get(b);
            buff.clear();
            writeStdOut(new String(b));
        }
    }

    private final void writeStdOut(final String str) {
        WriteProcessed3(str, str.length(), charsWritten, console);
    }
}
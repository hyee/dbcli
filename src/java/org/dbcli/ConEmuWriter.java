package org.dbcli;

import com.sun.jna.Native;
import com.sun.jna.NativeLibrary;
import com.sun.jna.ptr.IntByReference;
import com.sun.jna.win32.W32APIOptions;
import org.jline.terminal.impl.AbstractWindowsConsoleWriter;

public final class ConEmuWriter extends AbstractWindowsConsoleWriter {
    private NativeLibrary INSTANCE;
    private IntByReference charsWritten = new IntByReference();

    public ConEmuWriter() {
        super();
    }

    static final native boolean WriteProcessed(String in_lpBuffer, int in_nLength, IntByReference out_lpNumberOfCharsWritten);

    @Override
    protected final void writeConsole(char[] chars, int i) {
        try {
            WriteProcessed(String.valueOf(chars), i, charsWritten);
        } catch (Throwable e) {
            e.printStackTrace();
        }
    }

    void register(boolean active) {
        if (!active) close();
        else if (INSTANCE == null) {
            INSTANCE = NativeLibrary.getInstance("ConEmuHk" + (System.getProperty("os.arch").equals("x86") ? "" : "64"), W32APIOptions.UNICODE_OPTIONS);
            Native.register(ConEmuWriter.class, INSTANCE);
        }
    }

    @Override
    public void close() {
        if (INSTANCE != null) {
            INSTANCE.dispose();
            INSTANCE = null;
        }
    }
}
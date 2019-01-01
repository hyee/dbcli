package org.dbcli;

import com.sun.jna.Native;
import com.sun.jna.NativeLibrary;
import com.sun.jna.Pointer;
import com.sun.jna.ptr.IntByReference;
import com.sun.jna.win32.W32APIOptions;
import org.jline.terminal.impl.AbstractWindowsConsoleWriter;

import java.io.IOException;

public class ConEmuWriter extends AbstractWindowsConsoleWriter {
    static {
        NativeLibrary nativeLibrary = NativeLibrary.getInstance("ConEmuHk" + (System.getProperty("os.arch").equals("x86") ? "" : "64"), W32APIOptions.UNICODE_OPTIONS);
        Native.register(ConEmuWriter.class, nativeLibrary);
    }

    private final Pointer console;
    private IntByReference charsWritten = new IntByReference();

    public ConEmuWriter() {
        this(Kernel32.INSTANCE.GetStdHandle(Kernel32.STD_OUTPUT_HANDLE));
    }


    public ConEmuWriter(Pointer console) {
        super();
        this.console = console;
    }

    static final native boolean WriteProcessed(String in_lpBuffer, int in_nLength, IntByReference out_lpNumberOfCharsWritten);

    static final native boolean WriteProcessed3(String in_lpBuffer, int in_nLength, IntByReference out_lpNumberOfCharsWritten, Pointer in_hConsoleOutput);

    @Override
    protected void writeConsole(char[] chars, int i) throws IOException {
        WriteProcessed3(String.valueOf(chars), i, charsWritten, console);
    }

}
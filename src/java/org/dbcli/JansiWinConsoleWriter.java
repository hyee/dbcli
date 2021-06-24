package org.dbcli;

import org.fusesource.jansi.WindowsSupport;
import org.jline.terminal.impl.AbstractWindowsConsoleWriter;

import java.io.IOException;

import static org.fusesource.jansi.internal.Kernel32.*;

public final class JansiWinConsoleWriter extends AbstractWindowsConsoleWriter {

    private static final long console = GetStdHandle(STD_OUTPUT_HANDLE);
    private final int[] writtenChars = new int[1];

    @Override
    protected void writeConsole(char[] text, int len) throws IOException {
        if (WriteConsoleW(console, text, len, writtenChars, 0) == 0) {
            throw new IOException("Failed to write to console: " + WindowsSupport.getLastErrorMessage());
        }
    }

}
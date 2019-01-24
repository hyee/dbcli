package org.dbcli;

import org.fusesource.jansi.internal.WindowsSupport;
import org.jline.terminal.impl.AbstractWindowsConsoleWriter;

import java.io.IOException;

import static org.fusesource.jansi.internal.Kernel32.*;

class JansiWinConsoleWriter extends AbstractWindowsConsoleWriter {

    private static final long console = GetStdHandle(STD_OUTPUT_HANDLE);
    private final int[] writtenChars = new int[1];
    StringBuffer sb = new StringBuffer();
    volatile boolean flushOnDemand;

    public void setFlushOnDemand(boolean enabled) throws IOException {
        if (enabled == flushOnDemand) return;
        flushOnDemand = enabled;
        if (!enabled && sb.length() > 0) {
            char[] text = sb.toString().toCharArray();
            sb.setLength(0);
            writeConsole(text, text.length);
        }
    }

    @Override
    protected void writeConsole(char[] text, int len) throws IOException {
        if (flushOnDemand) {
            sb.append(text);
            return;
        }

        if (WriteConsoleW(console, text, len, writtenChars, 0) == 0) {
            throw new IOException("Failed to write to console: " + WindowsSupport.getLastErrorMessage());
        }
    }

}
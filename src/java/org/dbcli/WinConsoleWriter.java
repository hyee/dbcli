package org.dbcli;

import org.jline.terminal.impl.AbstractWindowsConsoleWriter;

import static org.jline.nativ.Kernel32.WriteConsoleW;

/**
 * Writes JLine's finished text straight to the console handle, so the console itself has to render
 * the escapes: the writer for a VTP console and for Windows Terminal. A console that cannot render
 * them gets {@link ConEmuWriter}, which hands the text to ConEmuHk instead.
 */
public final class WinConsoleWriter extends AbstractWindowsConsoleWriter {
    private final long console;
    private final int[] writtenChars = new int[1];

    public WinConsoleWriter(long console) {
        super();
        this.console = console;
    }

    @Override
    protected void writeConsole(char[] text, int len) {
        WriteConsoleW(console, text, len, writtenChars, 0);
    }
}

package org.dbcli;

import org.jline.terminal.impl.AbstractWindowsConsoleWriter;

import static org.jline.nativ.Kernel32.*;

public final class WinConsoleWriter extends AbstractWindowsConsoleWriter {
    /** index asking for the in-process ANSI renderer, see ConEmuWriter */
    private static final int CONEMU = 1;
    private final ConEmuWriter conEmuWriter;
    private final long console;
    private final int[] writtenChars = new int[1];

    public WinConsoleWriter(long console, int index) {
        super();
        this.console = console;
        //Index 1 renders ANSI in-process through ConEmuHk; every other index writes the text
        //through WriteConsoleW (the console then is a VTP one, or Windows Terminal's).
        this.conEmuWriter = index == CONEMU ? new ConEmuWriter(console) : null;
    }

    public WinConsoleWriter(long console) {
        this(console, 2);
    }

    @Override
    protected final void writeConsole(char[] text, int len) {
        if (conEmuWriter != null) {
            conEmuWriter.writeConsole(text, len);
        } else {
            WriteConsoleW(console, text, len, writtenChars, 0);
        }
    }

    @Override
    public void close() {
        if (conEmuWriter != null) {
            //prints the optional bulk-writer statistics; it never unloads ConEmuHk
            conEmuWriter.close();
        }
        super.close();
    }
}

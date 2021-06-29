package org.dbcli;

import org.fusesource.jansi.WindowsSupport;
import org.jline.terminal.impl.AbstractWindowsConsoleWriter;
import java.io.IOException;
import static org.fusesource.jansi.internal.Kernel32.*;
public final class JansiWinConsoleWriter extends AbstractWindowsConsoleWriter {
    private final ConEmuWriter conEmuWriter;

    public JansiWinConsoleWriter(boolean isAttachConEmu) {
        super();
        conEmuWriter = isAttachConEmu ? new ConEmuWriter() : null;
    }

    public JansiWinConsoleWriter() {
        this(false);
    }

    private static final long console = GetStdHandle(STD_OUTPUT_HANDLE);
    private final int[] writtenChars = new int[1];
    private int index = 0;

    void setWriter(int index) {
        if (conEmuWriter == null) return;
        conEmuWriter.register(index == 1);
        this.index = index;
    }

    public int currentWriter() {
        return index;
    }

    @Override
    protected final void writeConsole(char[] text, int len) throws IOException {
        if (index == 0 || conEmuWriter == null) {
            if (WriteConsoleW(console, text, len, writtenChars, 0) == 0) {
                throw new IOException("Failed to write to console: " + WindowsSupport.getLastErrorMessage());
            }
        } else {
            conEmuWriter.writeConsole(text, len);
        }
    }


    @Override
    public void close() {
        super.close();
        if (conEmuWriter != null) {
            conEmuWriter.close();
        }
    }
}
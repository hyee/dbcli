package org.dbcli;

import org.jline.terminal.impl.ExecPty;
import org.jline.terminal.impl.PosixSysTerminal;
import org.jline.terminal.impl.jna.JnaNativePty;
import org.jline.terminal.spi.Pty;
import org.jline.utils.OSUtils;

import java.io.IOException;
import java.io.PrintWriter;
import java.nio.charset.Charset;

public class PosixTerminal extends PosixSysTerminal implements MyTerminal {
    public PosixTerminal(String name, String type, Pty pty, String encoding, boolean nativeSignals, SignalHandler signalHandler) throws IOException {
        super(name, type, pty, encoding, nativeSignals, signalHandler);
    }

    public PosixTerminal(String name) throws IOException {
        this(name, (OSUtils.IS_CYGWIN || OSUtils.IS_MINGW) ? "xterm-256color" : System.getenv("TERM"), (OSUtils.IS_CYGWIN || OSUtils.IS_MINGW) ? ExecPty.current() : JnaNativePty.current(), Charset.defaultCharset().name(), true, SignalHandler.SIG_IGN);
    }

    @Override
    public PrintWriter printer() {
        return this.writer();
    }

    public int getBufferWidth() {
        return this.getWidth();
    }
}
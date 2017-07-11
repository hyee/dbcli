package org.dbcli;

import org.jline.terminal.impl.PosixSysTerminal;
import org.jline.terminal.impl.jna.JnaNativePty;
import org.jline.terminal.spi.Pty;

import java.io.IOException;
import java.io.PrintWriter;
import java.nio.charset.Charset;

/**
 * Created by VULCAN on 7/11/2017.
 */
public class PosixTerminal extends PosixSysTerminal implements MyTerminal {
    public PosixTerminal(String name, String type, Pty pty, String encoding, boolean nativeSignals, SignalHandler signalHandler) throws IOException {
        super(name, type, pty, encoding, nativeSignals, signalHandler);
    }

    public PosixTerminal(String name) throws IOException {
        this(name, System.getenv("TERM"), JnaNativePty.current(), Charset.defaultCharset().name(), true, SignalHandler.SIG_IGN);
    }

    @Override
    public PrintWriter printer() {
        return this.writer();
    }
}

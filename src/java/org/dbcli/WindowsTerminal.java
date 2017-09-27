package org.dbcli;

import com.sun.jna.Pointer;
import org.jline.terminal.Size;
import org.jline.terminal.impl.jansi.win.JansiWinSysTerminal;
import org.jline.terminal.impl.jna.win.JnaWinSysTerminal;

import java.io.*;
import java.nio.charset.Charset;
import java.util.concurrent.CountDownLatch;

public class WindowsTerminal extends JansiWinSysTerminal implements MyTerminal {
    private static final Pointer consoleIn = Kernel32.INSTANCE.GetStdHandle(Kernel32.STD_INPUT_HANDLE);
    private static final Pointer consoleOut = Kernel32.INSTANCE.GetStdHandle(Kernel32.STD_OUTPUT_HANDLE);
    private OutputStream output;
    private PrintWriter writer;
    private PrintWriter printer;
    private int bufferWidth = 1000;
    private CountDownLatch locker = null;

    public WindowsTerminal(String name, int codePage) throws IOException {
        this(name, codePage,true, SignalHandler.SIG_IGN);
    }

    public WindowsTerminal(String name, int codePage, boolean nativeSignals, SignalHandler signalHandler) throws IOException {
        super(name, codePage, nativeSignals, signalHandler);
        this.output = super.output();
        this.writer = super.writer();
        this.printer = this.writer;
        Charset charset = Charset.forName(System.getProperty("file.encoding"));
        Charset nativeCharset = charset;
        final int cp = getConsoleOutputCP();
        if (cp != 65001) try {
            nativeCharset = Charset.forName("ms" + cp);
        } catch (Exception e) {
            try {
                nativeCharset = Charset.forName("cp" + cp);
            } catch (Exception e1) {
            }
        }
        String ansicon = System.getenv("ANSICON");
        if (ansicon != null && ansicon.split("\\d+").length >= 3) name = "native";
        if (!"jline".equals(name)) {
            if ("ansicon".equals(name)) {
                this.output = new ConEmuOutputStream();
                this.writer = new PrintWriter(new OutputStreamWriter(super.output(), nativeCharset));
                this.printer = new PrintWriter(new OutputStreamWriter(output, charset));
            } else {
                this.output = new BufferedOutputStream(new FileOutputStream(FileDescriptor.out));
                this.printer = new PrintWriter(new OutputStreamWriter(this.output, nativeCharset));
                this.writer = this.printer;
            }
        }
    }


    final public void lockReader(boolean enabled) {
        try {
            if (enabled)
                locker = new CountDownLatch(1);
            else if (locker != null) {
                locker.countDown();
                locker = null;
            }
        } catch (Exception e) {
        }
    }

    private long prev = 0;

    @Override
    protected void setConsoleOutputCP(int code) {
        if ("jline".equals(this.name)) super.setConsoleOutputCP(code);
    } //ignore

    @Override
    protected String readConsoleInput() throws IOException {
        if (locker != null) try {
            locker.await();
        } catch (InterruptedException e) {

        }
        final String input = super.readConsoleInput();
        final long timer = System.currentTimeMillis();
        try {
            return ("\t".equals(input) && timer - prev <= 50) ? "    " : input;
        } finally {
            if (input != null && !input.equals("")) prev = timer;
        }
    }

    @Override
    public final PrintWriter writer() {
        return this.writer;
    }

    @Override
    public final OutputStream output() {
        return this.output;
    }

    public final PrintWriter printer() {
        return this.printer;
    }

    @Override
    protected void setConsoleMode(int mode) {
        Kernel32.INSTANCE.SetConsoleMode(consoleIn, mode);
    }

    @Override
    public final Size getSize() {
        Kernel32.CONSOLE_SCREEN_BUFFER_INFO info = new Kernel32.CONSOLE_SCREEN_BUFFER_INFO();
        Kernel32.INSTANCE.GetConsoleScreenBufferInfo(consoleOut, info);
        bufferWidth = info.dwSize.X;
        return new Size(info.windowWidth(), info.windowHeight());
    }

    public int getBufferWidth() {
        return bufferWidth;
    }
}

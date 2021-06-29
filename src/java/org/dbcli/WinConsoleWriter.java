package org.dbcli;

import org.jline.terminal.impl.AbstractWindowsConsoleWriter;

import static org.fusesource.jansi.internal.Kernel32.*;

public final class WinConsoleWriter extends AbstractWindowsConsoleWriter {
    private final ConEmuWriter conEmuWriter;
    final int mode;
    /*
    volatile short clock = 0;
    volatile CountDownLatch latch = null;
    final StringBuffer sb = new StringBuffer(1024 * 1024);
    Thread t = new Thread(new Runnable() {
        @Override
        public void run() {
            while (true) {
                try {
                    Thread.sleep(10L);
                    if (sb.length()==0||++clock < 8) continue;
                    char[] text;
                    synchronized (WinConsoleWriter.this.lock) {
                        text = sb.toString().toCharArray();
                        sb.setLength(0);
                        latch = new CountDownLatch(1);
                    }
                    if (index != 1) {
                        WriteConsoleW(console, text, text.length, writtenChars, 0);
                    } else {
                        conEmuWriter.writeConsole(text, text.length);
                    }
                    latch.await();
                } catch (Exception e) {
                    e.printStackTrace();
                }
            }
        }
    });*/

    public WinConsoleWriter(int index) {
        super();
        this.index = index;
        this.mode = index;
        conEmuWriter = mode <= 1 ? new ConEmuWriter() : null;
        if (mode <= 1) conEmuWriter.register(true);
        //t.setDaemon(true);
        //t.start();
    }

    public WinConsoleWriter() {
        this(2);
    }

    private static final long console = GetStdHandle(STD_OUTPUT_HANDLE);
    private final int[] writtenChars = new int[1];
    private int index = 0;

    void setWriter(int index) {
        if (mode != 0) return;
        conEmuWriter.register(index == 1);
        this.index = index;
    }

    public int currentWriter() {
        return index;
    }

    @Override
    protected final void writeConsole(char[] text, int len) {
        if (index != 1) {
            WriteConsoleW(console, text, len, writtenChars, 0);
        } else {
            conEmuWriter.writeConsole(text, len);
        }
    }

    @Override
    public void close() {
        super.close();
        if (mode == 0) {
            conEmuWriter.close();
        }
    }
}
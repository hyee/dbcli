package org.dbcli;

import org.jline.reader.impl.LineReaderImpl;
import org.jline.utils.Status;

import java.nio.charset.Charset;
import java.nio.charset.CharsetEncoder;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.TimeZone;
import java.util.concurrent.CountDownLatch;

class Timer {
    private volatile long clock = 0;
    private volatile CountDownLatch latch;

    private Console console;
    // Dots a-f only: the two extra dots of the 8-dot families hang below the baseline, and the
    // status row has the input box line directly underneath it. One dot moves per frame.
    private static final String[] DOTS = new String[]{"\u283E", "\u283D", "\u283B", "\u2837", "\u282F", "\u281F"};
    private static final String[] BAR  = new String[]{"|", "/", "-", "\\"};
    // The status text is encoded with the terminal charset -- Console.java pins that to
    // Charset.forName("file.encoding") -- and no legacy code page encodes braille: measured,
    // GBK/cp1252/ISO-8859-1/CP437/Shift_JIS/EUC-KR all answer "no" across U+2800..U+28FF and the
    // encoder substitutes 0x3F. Ask that encoder rather than guess from the property name.
    private final String[] icons = encodable(DOTS) ? DOTS : BAR;
    private final String format = "[%s] %d:%02d:%02d.%02d |";
    private volatile String time = String.format(format, "*", 0, 0, 0, 0);

    private static boolean encodable(String[] frames) {
        try {
            CharsetEncoder enc = Charset.forName(System.getProperty("file.encoding")).newEncoder();
            for (String f : frames) if (!enc.canEncode(f)) return false;
            return true;
        } catch (RuntimeException unsupportedCharset) { return false; }
    }
    private void flushTime(String icon) {
        Status status = console.status;
        if (status != null) {
            long secs = clock == 0 ? 0 : (System.currentTimeMillis() - clock) / 10;
            time = String.format(format, icon != null ? icon : icons[(int) (secs / 100) % icons.length], secs / 360000, (secs % 360000) / 6000, (secs % 6000) / 100, (secs % 100));
            console.setStatus("flush", "");
        }
    }

    private final Thread t = new Thread(() -> {
        while (clock >= 0) {
            try {
                if (latch == null) {
                    clock = 0;
                    latch = new CountDownLatch(1);
                    latch.await();
                    clock = System.currentTimeMillis();
                    Thread.sleep(1005L);
                    continue;
                }
                flushTime(null);
                Thread.sleep(1000);
            } catch (Exception e) {
            }
        }
    });

    protected String getTime() {
        return time;
    }

    protected void start() {
        if (latch != null && clock == 0) {
            flushTime(icons[0]);
            latch.countDown();
        }
    }

    protected void stop() {
        if (latch != null && clock > 0) {
            latch.countDown();
            latch = null;
            flushTime("*");
        }
    }

    protected void close() {
        clock = -1;
    }

    public Timer(Console console) {
        this.console = console;
        t.setDaemon(true);
        t.start();
    }
}

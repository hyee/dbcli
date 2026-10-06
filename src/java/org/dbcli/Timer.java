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
    // Two different risks reach the spinner, and the encoder below only sees one of them.
    //
    // (a) Encoding. Console pins the terminal charset to Charset.forName(file.encoding), and on the paths that
    //     actually encode text to bytes -- a dumb terminal, redirected output, ANSI_RENDER=off -- that charset
    //     is real: canEncode says NO for U+2800..U+28FF on GBK / windows-1252 / ISO-8859-1 / CP437 / Shift_JIS
    //     / EUC-KR, and the substitution character is '?'. Measured; see the 2026-09-28 round.
    // (b) Glyphs. The console path does NOT encode: AbstractWindowsTerminal.java:156-157 hands that charset to
    //     `output` only, while Status/Display write through terminal.writer() -- a PrintWriter into
    //     WriteConsoleW / render.dll as UTF-16. Nothing substitutes there; what can fail is the font, and
    //     neither this class nor the renderer probes glyph coverage.
    //
    // So this line is the guard for (a) and a proxy for (b) at best. It is kept because (a) is the failure
    // that produces a wrong *character* rather than a wrong *picture*, and BAR is drawable everywhere. The leg
    // that would settle (b) is three arms -- cp936 + raster font, cp936 + a braille-bearing font, chcp 65001
    // -- reading back the cells the bar actually got. Until that runs, do not describe this as proof.
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

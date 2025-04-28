package org.dbcli;

import org.jline.reader.impl.LineReaderImpl;
import org.jline.utils.Status;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.TimeZone;
import java.util.concurrent.CountDownLatch;

class Timer {
    private volatile long clock = 0;
    private volatile CountDownLatch latch;

    private Console console;
    private final String[] icons = new String[]{"|", "/", "-", "\\"};
    private final String format = "[%s] %d:%02d:%02d.%02d |";
    private volatile String time = String.format(format, "*", 0, 0, 0, 0);

    private void flushTime(String icon) {
        Status status;
        status = console.status;
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

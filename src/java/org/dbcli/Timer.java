package org.dbcli;

import org.jline.reader.impl.LineReaderImpl;
import org.jline.utils.Status;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.TimeZone;
import java.util.concurrent.CountDownLatch;

public class Timer {
    private volatile long clock;
    private volatile CountDownLatch latch;
    private volatile String time = "";
    private Console console;
    private final String format = " %d:%02d:%02d | ";
    private final Thread t = new Thread(() -> {
        Status status;
        while (true) {
            try {
                if (latch == null) {
                    time = "";
                    status = console.status;
                    if (status != null) console.setStatus("flush", "");
                    latch = new CountDownLatch(1);
                    latch.await();
                    clock = System.currentTimeMillis();
                    Thread.sleep(100L);
                    continue;
                }
                Thread.sleep(1000);
                status = console.status;
                if (status != null) {
                    long secs = (System.currentTimeMillis() - clock) / 1000;
                    time = String.format(format, secs / 3600, (secs % 3600) / 60, (secs % 60));
                    console.setStatus("flush", "");
                }
            } catch (Exception e) {
            }
        }
    });

    protected String getTime() {
        return time;
    }

    protected void start() {
        if (latch != null)
            latch.countDown();
    }

    protected void stop() {
        if (latch != null) {
            latch.countDown();
            latch = null;
        }
    }

    public Timer(Console console) {
        this.console = console;
        t.setDaemon(true);
        t.start();
    }


}

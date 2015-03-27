package org.dbcli;

import jline.console.ConsoleReader;
import jline.console.completer.Completer;
import jline.console.history.History;
import jline.internal.NonBlockingInputStream;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.IOException;
import java.util.Iterator;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;

public class Console extends ConsoleReader {
    private History his;
    private ScheduledFuture task;
    private EventReader monitor = new EventReader();
    private ScheduledExecutorService executor = Executors.newScheduledThreadPool(1);
    private NonBlockingInputStream in;
    private ActionListener event;
    private char[] keys;

    public Console() throws IOException {
        super(System.in, System.out);
        his = getHistory();
        setExpandEvents(false);
        setHandleUserInterrupt(true);
        setBellEnabled(false);
        in = (NonBlockingInputStream) this.getInput();
        Iterator<Completer> iterator = getCompleters().iterator();
        while (iterator.hasNext()) removeCompleter(iterator.next());
    }

    public String readLine() throws IOException {
        if (isRunning()) setEvents(null, null);
        synchronized (in) {
            String line = super.readLine();
            return line;
        }
    }

    public Boolean isRunning() {return this.task!=null;}

    public synchronized void setEvents(ActionListener event, char[] keys) {
        this.event = event;
        this.keys = keys;
        if (this.task != null) {
            this.task.cancel(true);
            this.task = null;
        }
        if (this.event != null && this.keys!=null) {
            this.monitor.counter=0;
            this.task = this.executor.scheduleWithFixedDelay(this.monitor, 1000, 200, TimeUnit.MILLISECONDS);
        }
    }

    public void setMultiplePrompt(String Content) {
        if (Content == null) {
            try {
                setHistoryEnabled(false);
                his.removeLast();
            } catch (Exception e) {
            }
        } else {
            setHistoryEnabled(true);
            this.his.add(Content);
            this.his.moveToEnd();
        }
    }

    class EventReader implements Runnable {
        public int counter=0;
        public void run() {
            try {
                int ch = in.read(1L);
                if (ch <= 0) return;
                for (int i = 0; i < keys.length; i++) {
                    if (ch != keys[i]) continue;
                    event.actionPerformed(new ActionEvent(this, ActionEvent.ACTION_PERFORMED, String.valueOf(ch)));
                    break;
                }
            } catch (Exception e) {
                //e.printStackTrace();
            }
        }
    }
}

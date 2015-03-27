package org.dbcli;

import jline.console.ConsoleReader;
import jline.console.completer.Completer;
import jline.console.history.History;
import jline.internal.NonBlockingInputStream;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.IOException;
import java.util.Iterator;

public class Console extends ConsoleReader {
    protected History his;
    protected boolean isPending = false;
    protected EventReader waiter;
    protected Long clock;
    NonBlockingInputStream in;
    ActionListener event;
    char[] keys;

    public Console() throws IOException {
        super(System.in, System.out);
        his = getHistory();
        setExpandEvents(false);
        waiter = new EventReader();
        waiter.setDaemon(true);
        waiter.start();
        waiter.setPriority(Thread.MAX_PRIORITY);
        setHandleUserInterrupt(true);
        in = (NonBlockingInputStream) this.getInput();
        Iterator<Completer> iterator = getCompleters().iterator();
        while (iterator.hasNext()) removeCompleter(iterator.next());
    }

    protected boolean isRun() {
        if (clock > 0L && System.currentTimeMillis() - clock > 300) clock = 0L;
        return isPending && clock == 0L && keys != null && event != null;
    }


    public String readLine() throws IOException {
        if (isPending) setEvents(null, null);
        synchronized (in) {
            String line = super.readLine();
            return line;
        }
    }


    public synchronized void setEvents(ActionListener event, char[] keys) {
        clock = event != null ? System.currentTimeMillis() : 0L;
        isPending = event != null ? true : false;
        this.event = event;
        this.keys = keys;
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

    class EventReader extends Thread {
        public void run() {
            while (true) {
                try {
                    if (isRun()) synchronized (in) {
                        int ch = in.read(100);
                        if (ch <= 0) continue;
                        for (int i = 0; i < keys.length; i++) {
                            if (ch != keys[i]) continue;
                            event.actionPerformed(new ActionEvent(this, ActionEvent.ACTION_PERFORMED, String.valueOf(ch)));
                            break;
                        }
                    }
                    else Thread.currentThread().sleep(300);
                } catch (Exception e) {
                    //e.printStackTrace();
                }
            }
        }
    }
}

package org.dbcli;

import jline.console.ConsoleReader;
import jline.console.completer.Completer;
import jline.console.history.History;
import jline.internal.NonBlockingInputStream;

import java.awt.event.ActionListener;
import java.io.IOException;
import java.util.Iterator;

public class Console extends ConsoleReader {
    protected History his;
    protected boolean isPending = false;
    protected EventReader waiter;
    protected Long clock;

    public Console() throws IOException {
        super(System.in, System.out);
        his = getHistory();
        setExpandEvents(false);
        waiter = new EventReader();
        waiter.setDaemon(true);
        waiter.start();
        waiter.setPriority(Thread.MAX_PRIORITY);
        setHandleUserInterrupt(true);

        Iterator<Completer> iterator = getCompleters().iterator();
        while (iterator.hasNext()) removeCompleter(iterator.next());
    }

    protected synchronized boolean isRun() {
        if (clock > 0L && System.currentTimeMillis() - clock > 300) clock = 0L;
        return isPending && clock == 0L;
    }

    protected synchronized NonBlockingInputStream getReader() {
        return (NonBlockingInputStream) this.getInput();
    }

    public String readLine() throws IOException {
        setRunning(false);
        String line = super.readLine();
        return line;
    }

    public synchronized void setRunning(Boolean status) {
        clock = status ? System.currentTimeMillis() : 0L;
        isPending = status;
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
            StringBuilder sb = new StringBuilder();
            while (true) {
                try {
                    if (isRun()) {
                        int ch = getReader().read(100);
                        if(ch>=0) {
                            //System.out.println(ch);
                            sb.appendCodePoint(ch);
                            Object o = getKeys().getBound(sb);
                            if(o!=null) sb.setLength(0);
                            if (o instanceof ActionListener) {
                                ((ActionListener) o).actionPerformed(null);
                            }
                        }
                    } else Thread.currentThread().sleep(300);
                } catch (Exception e) {
                    //e.printStackTrace();
                }
            }
        }
    }
}

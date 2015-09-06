package org.dbcli;

import jline.AnsiWindowsTerminal;
import jline.Terminal;
import jline.TerminalFactory;
import jline.WindowsTerminal;
import jline.console.ConsoleReader;
import jline.console.completer.Completer;
import jline.console.history.History;
import jline.internal.Configuration;
import jline.internal.NonBlockingInputStream;
import org.fusesource.jansi.WindowsAnsiOutputStream;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.IOException;
import java.io.Writer;
import java.util.Collection;
import java.util.Iterator;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;

public class Console extends ConsoleReader {
    public static Writer writer;
    public static ConsoleReader reader;
    public static NonBlockingInputStream in;
    public static Terminal terminal;
    protected static ScheduledExecutorService threadPool = Executors.newScheduledThreadPool(5);
    private History his;
    private ScheduledFuture task;
    private EventReader monitor = new EventReader();
    private ActionListener event;
    private char[] keys;


    public Console(Terminal t) throws IOException {
        super(null,System.in, System.out,t);
        his = getHistory();
        setExpandEvents(false);
        setHandleUserInterrupt(true);
        setBellEnabled(false);
        in = (NonBlockingInputStream) this.getInput();
        writer = this.getOutput();
        Iterator<Completer> iterator = getCompleters().iterator();
        while (iterator.hasNext()) removeCompleter(iterator.next());
        reader = this;
    }

    public String readLine(String prompt) throws IOException {
        if (isRunning()) setEvents(null, null);
        synchronized (in) {
            return super.readLine(prompt);
        }
    }

    public String readLine() throws IOException {
        return readLine((String) null);
    }

    public Boolean isRunning() {
        return this.task != null;
    }

    public synchronized void setEvents(ActionListener event, char[] keys) {
        this.event = event;
        this.keys = keys;
        if (this.task != null) {
            this.task.cancel(true);
            this.task = null;
        }
        if (this.event != null && this.keys != null) {
            this.monitor.counter = 0;
            this.task = this.threadPool.scheduleWithFixedDelay(this.monitor, 1000, 200, TimeUnit.MILLISECONDS);
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
            if (!Content.equals("")) this.his.add(Content);
            this.his.moveToEnd();
        }
    }

    class EventReader implements Runnable {
        public int counter = 0;

        public void run() {
            try {
                int ch = in.read(1L);
                if (ch <= 0) return;
                //System.out.println(ch);
                for (int i = 0; i < keys.length; i++) {
                    if (ch != keys[i] && keys[i] != '*') continue;
                    event.actionPerformed(new ActionEvent(this, ActionEvent.ACTION_PERFORMED, Character.toChars(ch).toString()));
                    break;
                }
            } catch (Exception e) {
                //e.printStackTrace();
            }
        }
    }
}
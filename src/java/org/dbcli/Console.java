package org.dbcli;

import com.naef.jnlua.LuaState;
import jline.Terminal;
import jline.console.ConsoleReader;
import jline.console.Operation;
import jline.console.completer.Completer;
import jline.console.history.History;
import jline.internal.Configuration;
import jline.internal.NonBlockingInputStream;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.IOException;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.Iterator;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;

public class Console extends ConsoleReader {
    public static PrintWriter writer;
    //public static NonBlockingInputStream in;
    public static WindowsInputReader in;
    public static Terminal terminal;
    public static String charset;
    protected static ScheduledExecutorService threadPool = Executors.newScheduledThreadPool(5);
    public LuaState lua;
    private History his;
    private ScheduledFuture task;
    private EventReader monitor = new EventReader();
    private ActionListener event;
    private char[] keys;
    private long threadID;
    private boolean isBlocking = false;
    private HashMap<String, Method> methods = new HashMap();
    private Method t_puts;

    public Console() throws Exception {
        super();
        his = getHistory();
        setExpandEvents(false);
        setHandleUserInterrupt(false);
        setBellEnabled(false);
        getKeys().bind("\u001bOn", Operation.DELETE_CHAR); //The delete key
        in = new WindowsInputReader();
        ((NonBlockingInputStream) this.getInput()).shutdown();
        Field field = ConsoleReader.class.getDeclaredField("in");
        field.setAccessible(true);
        field.set(this, in);
        field.setAccessible(false);
        field = ConsoleReader.class.getDeclaredField("reader");
        field.setAccessible(true);
        charset = this.getTerminal().getOutputEncoding() == null ? Configuration.getEncoding() : this.getTerminal().getOutputEncoding();
        field.set(this, new InputStreamReader(in, charset));
        field.setAccessible(false);
        t_puts = ConsoleReader.class.getDeclaredMethod("tputs", String.class, Object[].class);
        t_puts.setAccessible(true);
        writer = new PrintWriter(System.getenv("ANSICON_DEF") != null ? new OutputStreamWriter(System.out, Console.charset) : getOutput());

        //in=(NonBlockingInputStream)this.getInput();
        Iterator<Completer> iterator = getCompleters().iterator();
        threadID = Thread.currentThread().getId();
        while (iterator.hasNext()) removeCompleter(iterator.next());
        in.listen(this, new EventCallback() {
            @Override
            public void interrupt(Object... c) throws Exception {
                if (!isRunning() && lua != null && threadID == Thread.currentThread().getId()) {
                    lua.getGlobal("TRIGGER_EVENT");
                    lua.pushJavaObject(c[0]);
                    lua.pushString((String) c[1]);
                    lua.call(2, 1);
                    int r = lua.toInteger(lua.getTop());
                    //System.out.println(r);
                    if (r == 2) ((long[]) c[0])[0] = 2;
                }
            }
        });
    }

    public void doTPuts(String s, Object... o) throws Exception {
        t_puts.invoke(this, s, o);
    }

    public void write(String msg) throws Exception {
        print(msg);
        flush();
    }

    public Object invokeMethod(String method, Object... o) throws Exception {
        Method m = null;
        if (!methods.containsKey(method)) {
            Class<?>[] cls = new Class[o.length];
            for (int i = 0; i < o.length; i++) cls[i] = o[i] instanceof Class<?> ? (Class<?>) o[i] : o[i].getClass();
            m = ConsoleReader.class.getDeclaredMethod(method, cls);
            m.setAccessible(true);
            methods.put(method, m);
        } else m = methods.get(method);
        Object r = m.invoke(this, o);
        flush();
        return r;
    }

    public String readLine(String prompt) throws IOException {
        isBlocking = false;
        if (isRunning()) setEvents(null, null);
        String line = super.readLine(prompt);
        return line;
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
        this.isBlocking = false;
        if (this.task != null) {
            this.task.cancel(true);
            this.task = null;
        }
        if (this.event != null && this.keys != null) {
            this.monitor.counter = 0;
            //this.task = this.threadPool.schedule(this.monitor, 1000, TimeUnit.MILLISECONDS);
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
                if (isBlocking) return;
                int ch = in.peek(-1);
                if (ch < 1) return;
                for (int i = 0; i < keys.length; i++) {
                    if (ch != keys[i] && keys[i] != '*') continue;
                    in.read(-1);
                    event.actionPerformed(new ActionEvent(this, ActionEvent.ACTION_PERFORMED, Character.toChars(ch).toString()));
                    return;
                }
                if (ch > 32) isBlocking = true;
                else in.read(-1);
            } catch (Exception e) {
                //Loader.getRootCause(e).printStackTrace();
            }
        }
    }
}
package org.dbcli;

import com.esotericsoftware.reflectasm.ClassAccess;
import com.naef.jnlua.LuaState;
import org.jline.builtins.Commands;
import org.jline.builtins.Less;
import org.jline.builtins.Source;
import org.jline.keymap.KeyMap;
import org.jline.reader.EOFError;
import org.jline.reader.History;
import org.jline.reader.LineReader;
import org.jline.reader.ParsedLine;
import org.jline.reader.impl.DefaultHighlighter;
import org.jline.reader.impl.DefaultParser;
import org.jline.reader.impl.LineReaderImpl;
import org.jline.terminal.Terminal;
import org.jline.terminal.TerminalBuilder;
import org.jline.utils.*;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.*;
import java.lang.reflect.Method;
import java.util.HashMap;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;

import static org.jline.reader.LineReader.*;

public class Console {
    public static PrintWriter writer;
    //public static NonBlockingInputStream in;
    public static NonBlockingReader in;
    public static String charset = "utf-8";
    public static Terminal terminal;
    LineReaderImpl reader;
    public static ClassAccess<LineReaderImpl> accessor = ClassAccess.access(LineReaderImpl.class);

    static {
        try {
            terminal = TerminalBuilder.builder().encoding(charset).system(true).nativeSignals(true).signalHandler(Terminal.SignalHandler.SIG_IGN).exec(true).jansi(true).build();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    protected static ScheduledExecutorService threadPool = Executors.newScheduledThreadPool(5);
    private LuaState lua;
    private History his;
    volatile private ScheduledFuture task;
    private EventReader monitor = new EventReader();
    private ActionListener event;
    private char[] keys;
    private long threadID;
    private HashMap<String, Method> methods = new HashMap();
    private EventCallback callback;
    private ParserCallback parserCallback;
    private Parser parser;
    private Highlighter highlighter;

    public void setLua(LuaState lua) {
        this.lua = lua;
        parserCallback = null;
    }

    public Console(LineReader reader) throws Exception {
        this.reader = (LineReaderImpl) reader;
        parser = new Parser();
        highlighter=new Highlighter();
        this.reader.setParser(parser);
        this.reader.setHighlighter(highlighter);
        //this.reader.setHighlighter(new org.apache.felix.gogo.jline.Highlighter());
        this.his = this.reader.getHistory();
        //reader.getKeys().bind("\u001bOn", DELETE_CHAR); //The delete key
        in = terminal.reader();

        //map.bind(new Reference(BACKWARD_KILL_WORD),KeyMap.ctrl((char)KeyEvent.VK_BACK_SPACE));
        //map.bind(new Reference(BACKWARD_WORD),KeyMap.ctrl((char)KeyEvent.VK_LEFT));

        String colorPlan = System.getenv("ANSICON_DEF");
        writer = colorPlan != null && !("jline").equals(colorPlan) ? new PrintWriter(new OutputStreamWriter(System.out,charset)) : terminal.writer();
        threadID = Thread.currentThread().getId();
        Interrupter.handler = terminal.handle(Terminal.Signal.INT, new Interrupter());
        callback = new EventCallback() {
            @Override
            public void call(Object... c) {
                if (!isRunning() && lua != null && threadID == Thread.currentThread().getId()) {
                    lua.getGlobal("TRIGGER_EVENT");
                    Integer r = (Integer) (lua.call(c)[0]);
                    if (r == 2) ((long[]) c[0])[0] = 2;
                } else if (event != null) {
                    if (c[1] instanceof ActionEvent) event.actionPerformed((ActionEvent) c[0]);
                    else event.actionPerformed(new ActionEvent(this, ActionEvent.ACTION_PERFORMED, "\3"));
                }
            }
        };
        Interrupter.listen(this, callback);
    }

    public void doTPuts(String s, Object... o) {
        try {
            Curses.tputs(new StringWriter(), terminal.getStringCapability(InfoCmp.Capability.carriage_return), o);
        } catch (IOException e) {

        }
    }

    public void less(String output) throws Exception {
        ByteArrayOutputStream stream = new ByteArrayOutputStream();
        Source source=new Source() {
            @Override
            public String getName() {
                return "-MORE-";
            }
            @Override
            public InputStream read() throws IOException {
                return new ByteArrayInputStream(output.getBytes());
            }
        };
        Less less=new Less(terminal);
        less.veryQuiet=true;
        less.chopLongLines=false;
        less.ignoreCaseAlways=true;
        less.run(source);
    }

    public PrintWriter getOutput() {
        return writer;
    }

    public void write(String msg) {
        if (writer == null) return;
        writer.write(msg);
        writer.flush();
    }

    public Object invokeMethod(String method, Object... o) {
        return accessor.invoke(reader, method, o);
    }

    public String readLine(String prompt,String mask) {
        try {
            if (isRunning()) setEvents(null, null);
            if(mask.startsWith("\033")) {
                highlighter.ansi=mask;
                mask=null;
            }
            String line = reader.readLine(prompt, null, mask);
            return line;
        } catch (Exception e) {
            callback.call(null, "CTRL+C");
            return "";
        }
    }

    public String readLine(String prompt) {
        return readLine(prompt);
    }

    public String readLine() {
        return readLine(null);
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
            //this.task = this.threadPool.scheduleWithFixedDelay(this.monitor, 1000, 200, TimeUnit.MILLISECONDS);
        }
    }

    public void setEvents() {
        setEvents(null, null);
    }

    public String getKeyMap(String[] options) {
        ByteArrayOutputStream stream = new ByteArrayOutputStream();
        Commands.keymap(reader, new PrintStream(stream), new PrintStream(new ByteArrayOutputStream()), options);
        return stream.toString();
    }

    class EventReader implements Runnable {
        public int counter = 0;

        public void run() {
            try {
                int ch = in.peek(1L);
                if (ch < -1) return;
                for (int i = 0; i < keys.length; i++) {
                    if (ch != keys[i] && keys[i] != '*') continue;
                    in.read(1L);
                    event.actionPerformed(new ActionEvent(this, ActionEvent.ACTION_PERFORMED, Character.toChars(ch).toString()));
                    return;
                }
                setEvents(null, null);
            } catch (Exception e) {
                //Loader.getRootCause(e).printStackTrace();
            }
        }
    }

    interface ParserCallback {
        Object[] call(Object... e);
    }

    class Parser extends DefaultParser {
        String secondPrompt = "    ";
        final EOFError err = new EOFError(-1, -1, "Request new line", "");
        int i=0;
        public Parser() {
            super();
            super.setEofOnEscapedNewLine(true);
            reader.setVariable(SECONDARY_PROMPT_PATTERN,secondPrompt);
            reader.setOpt(LineReader.Option.AUTO_FRESH_LINE);
        }

        public ParsedLine parse(final String line, final int cursor, ParseContext context) {
            //if (context == ParseContext.SECONDARY_PROMPT) throw err;
            if (context != ParseContext.ACCEPT_LINE) return null;
            if (parserCallback == null) {
                lua.load("return {call=env.parse_line}", "proxy");
                lua.call(0, 1);
                parserCallback = lua.getProxy(-1, ParserCallback.class);
                lua.pop(1);
            }
            String[] lines= line.split("\r?\n");
            Object[] result = parserCallback.call(lines[lines.length-1]);
            if ((Boolean) result[0]) {
                if (result.length > 1 && !secondPrompt.equals(result[1])) {
                    secondPrompt = (String) result[1];
                    reader.setVariable(SECONDARY_PROMPT_PATTERN,secondPrompt);
                }
                throw err;
            }

            try {
                return super.parse(line, cursor,context);
            } catch (EOFError e) {
                throw err;
            }
        }
    }

    class Highlighter extends DefaultHighlighter{
        public String ansi="\033[0m";
        @Override
        public AttributedString highlight(LineReader reader, String buffer) {
            AttributedStringBuilder sb = new AttributedStringBuilder();
            sb.appendAnsi(ansi);
            sb.append(buffer);
            return  sb.toAttributedString();
        }
    }
}
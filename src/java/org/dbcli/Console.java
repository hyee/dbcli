package org.dbcli;

import com.esotericsoftware.reflectasm.ClassAccess;
import com.naef.jnlua.LuaState;
import org.apache.felix.gogo.runtime.EOFError;
import org.apache.felix.gogo.runtime.SyntaxError;
import org.apache.felix.gogo.runtime.Token;
import org.jline.builtins.Commands;
import org.jline.builtins.Less;
import org.jline.builtins.Source;
import org.jline.reader.History;
import org.jline.reader.LineReader;
import org.jline.reader.ParsedLine;
import org.jline.reader.impl.LineReaderImpl;
import org.jline.terminal.Terminal;
import org.jline.terminal.TerminalBuilder;
import org.jline.utils.NonBlockingReader;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.*;
import java.lang.reflect.Method;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.regex.Pattern;

import static org.jline.reader.LineReader.SECONDARY_PROMPT_PATTERN;

public class Console {
    public static PrintWriter writer;
    //public static NonBlockingInputStream in;
    public static NonBlockingReader in;
    //public static String charset = "utf-8";
    public static Terminal terminal;
    LineReaderImpl reader;
    public static ClassAccess<LineReaderImpl> accessor = ClassAccess.access(LineReaderImpl.class);
    public static Pattern ansiPattern = Pattern.compile("\33\\[[\\d\\;]*[mK]");

    static {
        try {
            terminal = TerminalBuilder.builder().system(true).nativeSignals(true).signalHandler(Terminal.SignalHandler.SIG_IGN).exec(true).jna(true).build();
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

    public void setKeywords(Map<String,Integer>  keywords) {
        highlighter.keywords=keywords;
    }

    public Console(LineReader reader) throws Exception {
        this.reader = (LineReaderImpl) reader;
        parser = new Parser();
        highlighter = new Highlighter();
        this.reader.setParser(parser);
        this.reader.setHighlighter(highlighter);
        this.his = this.reader.getHistory();
        //reader.getKeys().bind("\u001bOn", DELETE_CHAR); //The delete key
        in = terminal.reader();
        System.setIn(terminal.input());


        String colorPlan = System.getenv("ANSICON_DEF");
        writer = colorPlan != null && !("jline").equals(colorPlan) ? new PrintWriter(new OutputStreamWriter(System.out)) : terminal.writer();
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


    public void less(String output) throws Exception {
        ByteArrayOutputStream stream = new ByteArrayOutputStream();
        Source source = new Source() {
            @Override
            public String getName() {
                return "-MORE-";
            }

            @Override
            public InputStream read() throws IOException {
                return new ByteArrayInputStream(output.getBytes());
            }
        };
        Less less = new Less(terminal);
        less.veryQuiet = true;
        less.chopLongLines = false;
        less.ignoreCaseAlways = true;
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

    public String readLine(String prompt, String mask) {
        try {
            if (isRunning()) setEvents(null, null);
            if (mask.startsWith("\033")) {
                highlighter.ansi = mask;
                mask = null;
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

    class Parser implements org.jline.reader.Parser {
        String secondPrompt = "    ";
        final org.jline.reader.EOFError err = new org.jline.reader.EOFError(-1, -1, "Request new line", "");
        int i = 0;
        boolean isMulti=false;
        Pattern p=Pattern.compile("(\r?\n|\r)");
        public Parser() {
            super();
            //super.setEofOnEscapedNewLine(true);
            reader.setVariable(SECONDARY_PROMPT_PATTERN, secondPrompt);
            reader.setOpt(LineReader.Option.AUTO_FRESH_LINE);
        }

        public ParsedLine parse(String line, int cursor, ParseContext context){
            if (context != ParseContext.ACCEPT_LINE) return null;
            String[] lines=null;
            /*
            if(!isMulti)
            try {
                ParsedLineImpl parsedLine=null;
                org.apache.felix.gogo.runtime.Parser parser = new org.apache.felix.gogo.runtime.Parser(line);
                org.apache.felix.gogo.runtime.Parser.Program program = parser.program();
                List<org.apache.felix.gogo.runtime.Parser.Statement> statements = parser.statements();
                // Find corresponding statement
                org.apache.felix.gogo.runtime.Parser.Statement statement = null;
                for (int i = statements.size() - 1; i >= 0; i--) {
                    org.apache.felix.gogo.runtime.Parser.Statement s = statements.get(i);
                    if (s.start() <= cursor) {
                        boolean isOk = true;
                        // check if there are only spaces after the previous statement
                        if (s.start() + s.length() < cursor) {
                            for (int j = s.start() + s.length(); isOk && j < cursor; j++) {
                                isOk = Character.isWhitespace(line.charAt(j));
                            }
                        }
                        statement = s;
                        break;
                    }
                }
                if (statement != null) {
                    parsedLine=new ParsedLineImpl(program, statement, cursor, statement.tokens());
                } else {
                    // TODO:
                    parsedLine= new ParsedLineImpl(program, program, cursor, Collections.<Token>singletonList(program));
                }
                lines=new String[]{p.matcher(parsedLine.line()).replaceAll(" ")};
                System.out.println(lines[0]);
            } catch (EOFError e) {
                throw err;
            } catch (SyntaxError e) {
                throw new org.jline.reader.SyntaxError(e.line(), e.column(), e.getMessage());
            }
            */
            if (parserCallback == null) {
                lua.load("return {call=env.parse_line}", "proxy");
                lua.call(0, 1);
                parserCallback = lua.getProxy(-1, Console.ParserCallback.class);
                lua.pop(1);
            }

            if(lines==null) lines = p.split(line);
            Object[] result=null;
            for(int i=isMulti?lines.length-1:0;i<lines.length;i++)
                result=parserCallback.call(lines[i]);
            if ((Boolean) result[0]) {
                if (result.length > 1 && !secondPrompt.equals(result[1])) {
                    secondPrompt = (String) result[1];
                    reader.setVariable(SECONDARY_PROMPT_PATTERN, secondPrompt);
                }
                isMulti=true;
                throw err;
            }
            isMulti=false;
            return null;
        }
    }
}
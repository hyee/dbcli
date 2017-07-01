package org.dbcli;

import com.esotericsoftware.reflectasm.ClassAccess;
import com.naef.jnlua.LuaState;
import org.jline.builtins.Commands;
import org.jline.builtins.Less;
import org.jline.builtins.Source;
import org.jline.keymap.BindingReader;
import org.jline.keymap.KeyMap;
import org.jline.reader.Candidate;
import org.jline.reader.LineReader;
import org.jline.reader.ParsedLine;
import org.jline.reader.Reference;
import org.jline.reader.impl.DefaultParser;
import org.jline.reader.impl.LineReaderImpl;
import org.jline.terminal.Terminal;
import org.jline.terminal.TerminalBuilder;
import org.jline.terminal.impl.AbstractWindowsTerminal;
import org.jline.utils.NonBlockingReader;

import javax.swing.text.Keymap;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.*;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.regex.Pattern;

import static org.jline.reader.LineReader.DISABLE_HISTORY;
import static org.jline.reader.LineReader.SECONDARY_PROMPT_PATTERN;

public class Console {
    public static PrintWriter writer;
    public static NonBlockingReader in;
    public static String charset = "utf-8";
    public static AbstractWindowsTerminal terminal;
    LineReaderImpl reader;
    public static ClassAccess<LineReaderImpl> accessor = ClassAccess.access(LineReaderImpl.class);
    public final static Pattern ansiPattern = Pattern.compile("^\33\\[[\\d\\;]*[mK]$");

    static {
        try {
            terminal = (AbstractWindowsTerminal) TerminalBuilder.builder().system(true).nativeSignals(true).signalHandler(Terminal.SignalHandler.SIG_IGN).exec(true).jna(true).build();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    protected static ScheduledExecutorService threadPool = Executors.newScheduledThreadPool(5);
    private LuaState lua;
    volatile private ScheduledFuture task;
    private EventReader monitor = new EventReader();
    private ActionListener event;
    private char[] keys;
    long threadID;
    private EventCallback callback;
    private ParserCallback parserCallback;
    private Parser parser;
    private Highlighter highlighter = new Highlighter();
    HashMap<String, Candidate[]> candidates = new HashMap<>(1024);
    Completer completer = new Completer();

    public void setLua(LuaState lua) {
        this.lua = lua;
        parserCallback = null;
    }

    private Candidate candidate(String key, String desc) {
        if (desc != null && (desc.equals("") || desc.equals("\0"))) desc = null;
        return new Candidate(key, key, null, null, null, null, true);
    }

    public void addCompleters(Map<String, ?> keys, boolean isCommand) {
        Candidate c = isCommand ? candidate("", null) : null;
        for (Map.Entry<String, ?> entry : keys.entrySet()) {
            String key = entry.getKey().trim().toUpperCase();
            Object value = entry.getValue();
            String desc = value instanceof Map ? "\0" : value instanceof String ? (String) value : "";
            Candidate[] cs = candidates.get(key);
            if (cs == null || isCommand && (cs[2] == null || cs[2].descr() == null)) {
                candidates.put(key, new Candidate[]{candidate(key, desc), candidate(key.toLowerCase(), desc), c});
                int index = key.lastIndexOf(".");
                if (index > 0) {
                    key = key.substring(index + 1);
                    candidates.put(key, new Candidate[]{candidate(key, desc), candidate(key.toLowerCase(), desc), c});
                }
            }
            if ("\0".equals(desc)) {
                for (Map.Entry<String, String> e : ((Map<String, String>) entry.getValue()).entrySet()) {
                    String k = e.getKey().trim().toUpperCase();
                    desc = e.getValue();
                    candidates.put(key + " " + k, new Candidate[]{candidate(k, desc), candidate(k.toLowerCase(), desc), c});
                }
            }
        }
        completer.candidates.clear();
        completer.candidates.putAll(candidates);
    }

    public void setKeywords(Map<String, ?> keywords) {
        highlighter.keywords = keywords;
        addCompleters(keywords, false);
    }

    public void setCommands(Map<String, Object> commands) {
        highlighter.commands = commands;
        addCompleters(commands, true);
    }

    public void setSubCommands(Map<String, Object> commands) {
        addCompleters(commands, true);
        highlighter.commands.putAll(commands);
    }

    public Console(LineReader reader) throws Exception {
        this.reader = (LineReaderImpl) reader;
        this.parser = new Parser();
        this.reader.setParser(parser);
        this.reader.setHighlighter(highlighter);
        this.reader.setCompleter(completer);
        this.reader.setOpt(LineReader.Option.CASE_INSENSITIVE);
        this.reader.setOpt(LineReader.Option.MOUSE);
        this.reader.setOpt(LineReader.Option.AUTO_FRESH_LINE);
        this.reader.setOpt(LineReader.Option.BRACKETED_PASTE);
        /*
        reader.getKeyMaps().get(LineReader.EMACS).unbind("\t");
        reader.getKeyMaps().get(LineReader.EMACS).bind(new Reference(LineReader.EXPAND_OR_COMPLETE), "\t\t");
        */
        setKeyCode("redo","^Y");
        setKeyCode("undo","^Z");


        in = terminal.reader();
        System.setIn(terminal.input());

        String colorPlan = System.getenv("ANSICON_DEF");
        writer = colorPlan != null && !("jline").equals(colorPlan) ? new PrintWriter(new OutputStreamWriter(System.out, charset)) : terminal.writer();

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

    public void writeInput(String msg) {
        try {
            for (char c : msg.toCharArray())
                terminal.processInputByte((int) c);
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    boolean isPrompt=true;
    public String readLine(String prompt, String buffer) {
        try {
            if (isRunning()) setEvents(null, null);
            isPrompt = buffer != null && ansiPattern.matcher(buffer).find();
            if (isPrompt) {
                highlighter.setAnsi(buffer);
                buffer = null;
            } else {
                reader.setOpt(LineReader.Option.DISABLE_HIGHLIGHTER);
                reader.setOpt(LineReader.Option.DISABLE_EVENT_EXPANSION);
                reader.setVariable(DISABLE_HISTORY, true);
            }
            String line = reader.readLine(prompt, null, buffer);
            //writeInput(reader.BRACKETED_PASTE_END);
            return line;
        } catch (Exception e) {
            callback.call(null, "CTRL+C");
            return "";
        } finally {
            if (isPrompt) {
                reader.unsetOpt(LineReader.Option.DISABLE_HIGHLIGHTER);
                reader.unsetOpt(LineReader.Option.DISABLE_EVENT_EXPANSION);
                reader.setVariable(DISABLE_HISTORY, false);
            }
        }
    }

    public String readLine(String prompt) {
        return readLine(prompt, null);
    }

    public String readLine() {
        return readLine(null, null);
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

    public void setEvents() {
        setEvents(null, null);
    }

    public String getKeyMap(String[] options) {
        ByteArrayOutputStream stream = new ByteArrayOutputStream();
        Commands.keymap(reader, new PrintStream(stream), new PrintStream(new ByteArrayOutputStream()), options);
        return stream.toString();
    }

    public String setKeyCode(String keyEvent,String keyCode) {
        String keySeq;
        if(keyCode==null) {
            write("Input key code for '" + keyEvent + "'(hit Enter to complete): ");
            BindingReader binder = accessor.get(reader, "bindingReader");
            int c;
            StringBuilder sb = new StringBuilder();
            while (true) {
                c = binder.readCharacter();
                if (c == 10 || c == 13) break;
                String buff = new String(Character.toChars(c));
                sb.append(buff);
            }
            keySeq=sb.toString();
            keyCode=KeyMap.display(keySeq);
            write(keyCode+"\n");
        } else keySeq=KeyMap.translate(keyCode);
        if(keyCode.equals("")) return keyCode;
        reader.getKeyMaps().get(LineReader.EMACS).unbind(keySeq);
        reader.getKeyMaps().get(LineReader.EMACS).bind(new Reference(keyEvent),keySeq);
        return keyCode;
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
        final org.jline.reader.EOFError err = new org.jline.reader.EOFError(-1, -1, "Request new line", "");
        boolean isMulti = false;
        Pattern p = Pattern.compile("(\r?\n|\r)");

        public Parser() {
            super();
            super.setEofOnEscapedNewLine(true);
            reader.setVariable(SECONDARY_PROMPT_PATTERN, secondPrompt);
            reader.setOpt(LineReader.Option.AUTO_FRESH_LINE);
        }

        public ParsedLine parse(String line, int cursor, ParseContext context) {
            if (!isPrompt) return null;
            if (context == ParseContext.COMPLETE) return super.parse(line, cursor, context);
            if (context != ParseContext.ACCEPT_LINE) return null;
            String[] lines = null;

            if (parserCallback == null) {
                lua.load("return {call=env.parse_line}", "proxy");
                lua.call(0, 1);
                parserCallback = lua.getProxy(-1, Console.ParserCallback.class);
                lua.pop(1);
            }

            if (lines == null) lines = p.split(line);
            Object[] result = parserCallback.call(line);
            if ((Boolean) result[0]) {
                if (result.length > 1 && !secondPrompt.equals(result[1])) {
                    secondPrompt = (String) result[1];
                    reader.setVariable(SECONDARY_PROMPT_PATTERN, secondPrompt);
                }
                isMulti = true;
                throw err;
            }
            reader.setVariable(DISABLE_HISTORY, lines.length > Math.min(25, terminal.getHeight() - 5));
            isMulti = false;
            return null;
        }
    }
}
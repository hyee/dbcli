package org.dbcli;

import com.esotericsoftware.reflectasm.ClassAccess;
import com.naef.jnlua.LuaState;
import com.sun.jna.Library;
import com.sun.jna.Native;
import com.sun.jna.Platform;
import org.jline.builtins.Commands;
import org.jline.builtins.Less;
import org.jline.builtins.Source;
import org.jline.keymap.KeyMap;
import org.jline.reader.*;
import org.jline.reader.impl.DefaultParser;
import org.jline.reader.impl.LineReaderImpl;
import org.jline.terminal.Terminal;
import org.jline.utils.NonBlockingReader;
import org.jline.utils.OSUtils;
import org.jline.utils.WCWidth;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.*;
import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.security.Permission;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.logging.Level;
import java.util.logging.Logger;
import java.util.regex.Pattern;

import static org.jline.reader.LineReader.DISABLE_HISTORY;
import static org.jline.reader.LineReader.SECONDARY_PROMPT_PATTERN;

public class Console {
    public static PrintWriter writer;
    public static NonBlockingReader input;
    public static String charset = System.getProperty("sun.stdout.encoding");
    public Terminal terminal;
    LineReaderImpl reader;
    public static ClassAccess<LineReaderImpl> accessor = ClassAccess.access(LineReaderImpl.class);
    public final static Pattern ansiPattern = Pattern.compile("^\33\\[[\\d\\;]*[mK]$");

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
    private volatile boolean pause = false;
    private Highlighter highlighter = new Highlighter(this);
    HashMap<String, Candidate[]> candidates = new HashMap<>(1024);
    Completer completer = new Completer();
    public boolean isSubSystem = false;

    public interface CLibrary extends Library {
        Console.CLibrary INSTANCE = (Console.CLibrary)
                Native.loadLibrary((Platform.isWindows() ? "kernel32" : "c"),
                        Console.CLibrary.class);

        boolean SetConsoleTitleA(String title);
    }

    public void setTitle(String title) {
        CLibrary.INSTANCE.SetConsoleTitleA(title);
    }

    public void setLua(LuaState lua) {
        this.lua = lua;
        parserCallback = null;
    }

    private Candidate candidate(String key, String desc) {
        if (desc != null && (desc.equals("") || desc.equals("\0"))) desc = null;
        return new Candidate(key, key, null, null, null, null, true);
    }

    public static String ulen(final String s) {
        if (s == null) return "0:0";
        int len = 0;
        for (int i = 0, n = s.length(); i < n; i++) len += WCWidth.wcwidth(Character.codePointAt(s, i));
        return s.length() + ":" + len;
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

    public String getPlatform() {
        if (OSUtils.IS_CYGWIN) return "cygwin";
        if (OSUtils.IS_MINGW) return "mingw";
        if (OSUtils.IS_OSX) return "mac";
        if (OSUtils.IS_WINDOWS) return "windows";
        return "linux";
    }

    public int getBufferWidth() {
        if ("terminator".equals(System.getenv("TERM"))) return 2000;
        return ((MyTerminal) terminal).getBufferWidth();
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

    public Console(String historyLog) throws Exception {
        String colorPlan = System.getenv("ANSICON_DEF");
        if (colorPlan == null) colorPlan = "jline";
        if (OSUtils.IS_WINDOWS && !(OSUtils.IS_CYGWIN || OSUtils.IS_MINGW)) {
            terminal = new WindowsTerminal(colorPlan, Kernel32.INSTANCE.GetConsoleOutputCP());
        } else terminal = new PosixTerminal(colorPlan);
        this.reader = (LineReaderImpl) LineReaderBuilder.builder().terminal(terminal).build();
        this.parser = new Parser();
        this.reader.setParser(parser);
        this.reader.setHighlighter(highlighter);
        this.reader.setCompleter(completer);
        this.reader.setOpt(LineReader.Option.CASE_INSENSITIVE);
        //this.reader.setOpt(LineReader.Option.MOUSE);
        this.reader.setOpt(LineReader.Option.AUTO_FRESH_LINE);
        this.reader.setOpt(LineReader.Option.BRACKETED_PASTE);
        this.reader.setVariable(LineReader.HISTORY_FILE, historyLog);
        this.reader.setVariable(LineReader.HISTORY_FILE_SIZE, 2000);
        /*
        reader.getKeyMaps().get(LineReader.EMACS).unbind("\t");
        reader.getKeyMaps().get(LineReader.EMACS).bind(new Reference(LineReader.EXPAND_OR_COMPLETE), "\t\t");
        */
        setKeyCode("redo", "^Y");
        setKeyCode("undo", "^Z");
        setKeyCode("backward-word", "^[[1;3D");
        setKeyCode("forward-word", "^[[1;3C");

        input = terminal.reader();

        writer = ((MyTerminal) terminal).printer();
        threadID = Thread.currentThread().getId();
        Interrupter.handler = terminal.handle(Terminal.Signal.INT, new Interrupter());
        callback = new EventCallback() {
            @Override
            public void call(Object... c) {
                if (!pause && lua != null && threadID == Thread.currentThread().getId()) {
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

    Thread subThread = null;

    public void startSqlCL(final String[] args) throws Exception {
        if (subThread != null) throw new IOException("SQLCL instance is running!");
        Class clz;

        try {
            clz = Class.forName("oracle.dbtools.raptor.scriptrunner.cmdline.SqlCli");
        } catch (ClassNotFoundException e) {
            throw new IOException("Cannot find SqlCL libraries under folder 'lib/ext'!");
        }

        Method main = clz.getDeclaredMethod("main", String[].class);
        subThread = new Thread(() -> {
            try {
                main.invoke(null, new Object[]{args});
            } catch (IllegalAccessException e) {
                e.printStackTrace();
            } catch (InvocationTargetException e) {
                e.printStackTrace();
            } catch (Exception e) {
            }
        });


        //System.setSecurityManager(new NoExitSecurityManager(subThread));
        Logger.getLogger("OracleRestJDBCDriverLogger").setLevel(Level.OFF);
        try {
            subThread.setDaemon(true);
            subThread.start();
            subThread.join();
        } catch (Exception e1) {
        } finally {
            //System.setSecurityManager(null);
            subThread = null;
        }
    }

    private static class NoExitSecurityManager extends SecurityManager {
        Thread running;

        public NoExitSecurityManager(Thread running) {
            this.running = running;
        }

        @Override
        public void checkPermission(Permission perm) {
            // allow anything.
        }

        @Override
        public void checkPermission(Permission perm, Object context) {
            // allow anything.
        }

        @Override
        public void checkExit(int status) {
            super.checkExit(status);
            if (Thread.currentThread() == running) throw new SecurityException("Exited");
        }
    }

    public void less(String output) throws Exception {
        ByteArrayOutputStream stream = new ByteArrayOutputStream();
        Source source = new Source() {
            @Override
            public String getName() {
                return "";
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

    public void println(String msg) {
        if (writer == null) return;
        writer.println(msg);
        writer.flush();
    }

    public void clearScreen() {
        reader.clearScreen();
    }

    public Object invokeMethod(String method, Object... o) {
        return accessor.invoke(reader, method, o);
    }


    boolean isPrompt = true;

    public String readLine(String prompt, String buffer) {
        try {
            setEvents(null, null);
            ((MyTerminal) terminal).lockReader(false);
            isPrompt = buffer != null && ansiPattern.matcher(buffer).find();
            if (isPrompt) {
                highlighter.setAnsi(buffer);
                buffer = null;
            } else {
                reader.setOpt(LineReader.Option.DISABLE_HIGHLIGHTER);
                reader.setOpt(LineReader.Option.DISABLE_EVENT_EXPANSION);
                reader.setVariable(DISABLE_HISTORY, true);
            }
            pause = false;
            String line = reader.readLine(prompt, null, buffer);
            pause = true;
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
        return pause;
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

    public String setKeyCode(String keyEvent, String keyCode) {
        String keySeq;
        if (keyCode == null) {
            write("Input key code for '" + keyEvent + "'(hit Enter to complete): ");
            int c;
            StringBuilder sb = new StringBuilder();
            while (true) {
                c = reader.readCharacter();
                if (c == 10 || c == 13) break;
                sb.append(new String(Character.toChars(c)));
            }
            keySeq = sb.toString();
            keyCode = KeyMap.display(keySeq);
            write(keyCode + "\n");
        } else keySeq = KeyMap.translate(keyCode);
        if (keyCode.equals("")) return keyCode;
        reader.getKeyMaps().get(LineReader.EMACS).unbind(keySeq);
        reader.getKeyMaps().get(LineReader.EMACS).bind(new Reference(keyEvent), keySeq);
        return keyCode;
    }

    class EventReader implements Runnable {
        public int counter = 0;

        public void run() {
            try {
                if (pause) {
                    int ch = input.peek(1L);
                    if (ch < -1) return;
                    for (int i = 0; i < keys.length; i++) {
                        if (ch != keys[i] && keys[i] != '*') continue;
                        input.read(1L);
                        event.actionPerformed(new ActionEvent(this, ActionEvent.ACTION_PERFORMED, Character.toChars(ch).toString()));
                        return;
                    }
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
            if ((Boolean) result[2]) ((MyTerminal) terminal).lockReader(true);
            reader.setVariable(DISABLE_HISTORY, lines.length > Math.min(25, terminal.getHeight() - 5));
            isMulti = false;
            return null;
        }
    }
}
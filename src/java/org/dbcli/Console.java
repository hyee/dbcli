package org.dbcli;

import com.esotericsoftware.reflectasm.ClassAccess;
import com.naef.jnlua.LuaState;
import com.naef.jnlua.util.AbstractTableMap;
import org.jline.builtins.Commands;
import org.jline.builtins.Source;
import org.jline.keymap.KeyMap;
import org.jline.reader.*;
import org.jline.reader.impl.DefaultParser;
import org.jline.reader.impl.LineReaderImpl;
import org.jline.terminal.Attributes;
import org.jline.terminal.Size;
import org.jline.terminal.Terminal;
import org.jline.terminal.TerminalBuilder;
import org.jline.terminal.impl.AbstractTerminal;
import org.jline.terminal.impl.AbstractWindowsTerminal;
import org.jline.utils.*;
import org.jline.widget.AutosuggestionWidgets;

import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.io.*;
import java.nio.charset.Charset;
import java.security.Provider;
import java.security.Security;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

import static org.jline.reader.LineReader.DISABLE_HISTORY;
import static org.jline.reader.LineReader.SECONDARY_PROMPT_PATTERN;
import static org.jline.reader.impl.LineReaderImpl.BRACKETED_PASTE_OFF;
import static org.jline.reader.impl.LineReaderImpl.BRACKETED_PASTE_ON;


public final class Console {
    public final static Pattern ansiPattern = Pattern.compile("^\33\\[[\\d\\;]*[mK]$");
    public final static PrintStream stdout = System.out;
    public static Output writer;
    public static NonBlockingReader input;
    public static String charset = System.getProperty("sun.stdout.encoding");
    public static ClassAccess<LineReaderImpl> accessor = ClassAccess.access(LineReaderImpl.class);
    public static ClassAccess<AbstractWindowsTerminal> terminalAccess = ClassAccess.access(Terminal.class);
    protected static ScheduledExecutorService threadPool = Executors.newScheduledThreadPool(6);
    public AbstractTerminal terminal;
    public boolean isSubSystem = false;
    LineReaderImpl reader;
    Display display;
    long threadID;

    MyCompleter completer = new MyCompleter(this);
    boolean isPrompt = true;
    boolean isJNIConsole = false;
    ArrayList<AttributedString> titles = new ArrayList<>(2);
    private LuaState lua;
    volatile private ScheduledFuture task;
    private ActionListener event;
    private char[] keys;
    private final EventCallback callback;
    private ParserCallback parserCallback;
    MyParser parser;
    private volatile boolean pause = false;
    private final MyHistory history = new MyHistory();

    private String colorPlan;
    private final KeyMap keyMap;
    protected volatile Status status;
    public Timer timer = new Timer(this);
    private Size prevSize = null;

    public Console(String historyLog) throws Exception {
        colorPlan = "dbcli";
        Charset encoding = null;
        try {
            encoding = Charset.forName(System.getProperty("file.encoding"));
        } catch (Exception e) {
            encoding = Charset.defaultCharset();
            System.out.println("Unsupported encoding: " + System.getProperty("file.encoding") + ", DBCLI will use the default encoding(" + encoding.name() + ") instead.");

        }
        String mode = System.getenv("ANSICON_DEF");
        if (mode == null || mode.equals("")) mode = "default";
        mode = mode.toLowerCase();
        if (!mode.equals("default")
                && !mode.equals("jni")
                && !mode.equals("jna")
                && !mode.equals("ffm")
                && !mode.equals("ansicon")
                && !mode.equals("conemu")) {
            mode = "default";
        }
        if (OSUtils.IS_WINDOWS
                && !(OSUtils.IS_CYGWIN || OSUtils.IS_MSYSTEM || OSUtils.IS_CONEMU)
                && !"jna".equals(mode)
                && !"ffm".equals(mode)) {
            this.terminal = WinSysTerminal.createTerminal(colorPlan,
                    null,
                    "ansicon".equals(mode) || "conemu".equals(mode),
                    encoding, true,
                    Terminal.SignalHandler.SIG_IGN,
                    false);
        } else {
            this.terminal = (AbstractTerminal) TerminalBuilder
                    .builder()
                    .system(true)
                    .name(colorPlan)
                    .encoding(encoding)
                    .jansi(false)
                    .jna("jna".equals(mode))
                    .jni("jni".equals(mode) || "ansicon".equals(mode) || "conemu".equals(mode) || "default".equals(mode))
                    .ffm("ffm".equals(mode)) // || "default".equals(mode) default to disable due to possible warning
                    .nativeSignals(true)
                    .signalHandler(Terminal.SignalHandler.SIG_IGN)
                    .build();
        }
        Interrupter interrupter = new Interrupter();
        Interrupter.reset();
        Interrupter.handler = terminal.handle(Terminal.Signal.INT, interrupter);
        terminal.handle(Terminal.Signal.TSTP, interrupter);
        terminal.handle(Terminal.Signal.QUIT, interrupter);
        this.reader = (LineReaderImpl) LineReaderBuilder.builder().terminal(terminal).appName("dbcli").build();
        this.parser = new MyParser();
        this.reader.setParser(parser);
        this.reader.setHighlighter(parser);
        this.reader.setCompleter(completer);
        this.reader.setHistory(history);
        this.reader.unsetOpt(LineReader.Option.MOUSE);
        this.reader.unsetOpt(LineReader.Option.HISTORY_IGNORE_SPACE);
        this.reader.setOpt(LineReader.Option.DELAY_LINE_WRAP);
        this.reader.setOpt(LineReader.Option.DISABLE_EVENT_EXPANSION);
        this.reader.setOpt(LineReader.Option.CASE_INSENSITIVE);
        this.reader.setOpt(LineReader.Option.CASE_INSENSITIVE_SEARCH);
        this.reader.setOpt(LineReader.Option.AUTO_FRESH_LINE);
        this.reader.setOpt(LineReader.Option.LIST_ROWS_FIRST);
        this.reader.setOpt(LineReader.Option.INSERT_TAB);
        this.reader.setVariable(DISABLE_HISTORY, true);
        this.reader.setVariable(LineReader.HISTORY_FILE, historyLog);
        this.reader.setVariable(LineReader.HISTORY_FILE_SIZE, 2000);
        this.isJNIConsole = this.terminal instanceof WinSysTerminal;
        AutosuggestionWidgets autosuggestionWidgets = new AutosuggestionWidgets(reader);
        autosuggestionWidgets.enable();
        //terminal.echo(false); //fix paste issue of iTerm2 when past is off
        enableBracketedPaste("on");
        keyMap = reader.getKeyMaps().get(LineReader.MAIN);
        setKeyCode(LineReader.BACKWARD_DELETE_CHAR, Character.toString('\177'));
        for (String s : new String[]{"^_", "^[^H"}) setKeyCode(LineReader.BACKWARD_KILL_WORD, s);
        //deal with keys ctrl+arrow and alt+Arrow
        for (String s : new String[]{"^[[", "[1;2", "[1;3", "[1;5", "O", "["}) {
            s = "^[" + s;
            if (keyMap.getBound(KeyMap.translate(s + "A")) == null) {
                setKeyCode(LineReader.UP_HISTORY, s + "A");
                setKeyCode(LineReader.DOWN_HISTORY, s + "B");
                setKeyCode(LineReader.FORWARD_WORD, s + "C");
                setKeyCode(LineReader.BACKWARD_WORD, s + "D");
            }
        }

        //alt+y and alt+z
        setKeyCode("redo", "^[y");
        setKeyCode("undo", "^[z");

        if (!OSUtils.IS_OSX) {
            setKeyCode(LineReader.BEGINNING_OF_LINE, "^[[1~");
            setKeyCode(LineReader.END_OF_LINE, "^[[4~");
        }

        input = terminal.reader();
        writer = new Output(terminal.writer());
        colorPlan = terminal.getType();

        threadID = Thread.currentThread().getId();
        callback = new EventCallback() {
            @Override
            public void call(Object... c) {
                increaseCancelSeq();
                if (!pause && lua != null && threadID == Thread.currentThread().getId()) {
                    lua.getGlobal("TRIGGER_EVENT");
                    Integer r = (Integer) (lua.call(c)[0]);
                    if (r == 2) ((long[]) c[0])[0] = 2;
                } else if (event != null) {
                    if (c[1] instanceof ActionEvent) event.actionPerformed((ActionEvent) c[0]);
                    else event.actionPerformed(new ActionEvent(this, ActionEvent.ACTION_PERFORMED, "\3"));
                }
                if (titles.size() > 0)
                    new Thread(() -> {
                        try {
                            Thread.sleep(1000);
                        } catch (InterruptedException e) {
                        }
                        reader.redrawLine();
                        if (status != null) setStatus("flush", null);
                    }).start();
            }
        };
        Interrupter.listen(this, callback);
        display = new Display(terminal, false);
        prevSize = new Size(getScreenHeight(), getBufferWidth());
        terminal.handle(Terminal.Signal.WINCH, this::handleResize);
    }

    public void initDisplay() {
        display = new Display(terminal, false);
        if (status != null) {
            status.close();
            status.suspend();
        }
        display.setNoWrap(true);
        prevDisplay = null;
    }

    public void exitDisplay() {
        if (display == null) return;
        //display.exit();
        display.setNoWrap(false);
        prevDisplay = null;
        if (status != null) {
            status.restore();
        }
        display.reset();
    }

    private volatile String[] prevDisplay = null;

    public void display(String[] args) {
        int width = getBufferWidth();
        display.clear();
        display.resize(getScreenHeight(), width);
        Attributes attrs = terminal.enterRawMode();
        display.update(Arrays.stream(args)
                .map(s -> AttributedString.fromAnsi(s + (s.endsWith("\n") ? "" : "\n"))
                        .columnSubSequence(0, width)).collect(Collectors.toList()), -1);
        terminal.setAttributes(attrs);
        prevDisplay = args;
    }

    public void handleResize(Terminal.Signal signal) {
        Size size = terminal.getBufferSize();
        if (size.getRows() > 1
                && prevSize != null
                && prevSize.getColumns() == size.getColumns()
                && prevSize.getRows() == size.getRows()) {
            return;
        }

        prevSize.copy(size);

        if (status != null && !status.isHided() && !status.isSuspended()) {
            status.close();
            status.resize();
            terminal.puts(InfoCmp.Capability.carriage_return);
            terminal.puts(InfoCmp.Capability.clr_eos);
        }

        if (prevDisplay != null) {
            display.moveVisualCursorTo(0);
            terminal.puts(InfoCmp.Capability.clr_eos);
            display.empty();
            display(prevDisplay);
        }
    }

    public void enableMouse(String val) {
        if ("off".equals(val)) reader.unsetOpt(LineReader.Option.MOUSE);
        else reader.setOpt(LineReader.Option.MOUSE);
    }

    public void enableBracketedPaste(String val) {
        if ("off".equals(val)) {
            reader.unsetOpt(LineReader.Option.BRACKETED_PASTE);
            terminal.writer().write(BRACKETED_PASTE_OFF);
        } else {
            reader.setOpt(LineReader.Option.BRACKETED_PASTE);
            terminal.writer().write(BRACKETED_PASTE_ON);
        }
        terminal.writer().flush();
        if (isJNIConsole) ((WinSysTerminal) terminal).enablePaste(!"off".equals(val));
    }

    public void setLua(LuaState lua) {
        this.lua = lua;
        completer.reset();
        parserCallback = null;
    }

    public String ulen(String s, final int maxLength) {

        //WCWidth.java: (ucs >= 0x8140 && ucs <= 0xfefe && ucs%0x0100 !=0x7f) ||
        if (s == null) return "0:0";
        AttributedString buff = AttributedString.fromAnsi(s);
        int size = buff.columnLength();
        if (maxLength > 0 && maxLength < size) {
            buff = buff.columnSubSequence(0, maxLength);
            s = buff.toAnsi(terminal);
            size = maxLength;
        }
        return s.getBytes().length + ":" + size + ":" + (maxLength > 0 ? s : "");
    }


    public void setKeywords(AbstractTableMap<String, ?> keywords) {
        HashMap<String, ?> map = (HashMap) keywords.toJavaObject();
        completer.loadKeyWords(map, 700);
        //addCompleters(keywords, false);
    }

    public void setCommands(AbstractTableMap<String, Object> commands) {
        HashMap<String, Object> map = (HashMap) commands.toJavaObject();
        Object o = new Object();
        map.forEach((k, v) -> parser.commands.put(k, o));
        completer.setCommands(map);
        commands.unRef();
    }

    public void setSubCommands(AbstractTableMap<String, Object> commands) {
        HashMap<String, Object> map = (HashMap) commands.toJavaObject();
        Object o = new Object();
        map.forEach((k, v) -> parser.commands.put(k, o));
        commands.unRef();
        completer.loadCommands(map, 300);
        //map.forEach((k, v) ->parser.commands.put(k, v));
    }

    public void renameCommand(String[] oldNames, String[] newNames) {
        for (String name : oldNames) parser.commands.remove(name);
        Object o = new Object();
        for (String name : newNames) parser.commands.put(name, o);
        completer.renameCommands(oldNames, newNames);
    }

    public String getPlatform() {
        if (OSUtils.IS_CYGWIN) return "cygwin";
        if (OSUtils.IS_MSYSTEM) return "mingw";
        if (OSUtils.IS_CONEMU) return "conemu";
        if (OSUtils.IS_OSX) return "mac";
        if (OSUtils.IS_WINDOWS) return "windows";
        return "linux";
    }

    private volatile String prevTitle = "";
    private volatile String prevTime = "";
    private volatile String prevColor = "";

    public boolean setStatus(String title, String color) {
        try {
            final int width = getScreenWidth() - 1;
            this.status = terminal.getStatus(title != null && !title.equals("") && !title.equals("flush"));
            if (this.status == null || width <= 0)
                return false;
            if (title == null || title.equals("")) {
                this.status.close();
                this.status.suspend();
                this.status = null;
                return false;
            }
            if (terminal.paused()) return false;
            //must be width -1 to avoid cursor position issue, don't know why
            final String chars = new String(new char[width]);
            String time = timer.getTime();
            this.status.resize();
            if ("flush".equals(title) && prevTime.equals(time)) {
                this.status.update(titles);
            } else {
                if ("flush".equals(title)) {
                    title = prevTitle;
                } else {
                    prevTitle = title;
                }
                prevTime = time;
                if (color != null && !color.equals("") && !color.equals(prevColor)) {
                    prevColor = color;
                }
                titles.clear();
                titles.add(AttributedString.fromAnsi(prevColor + chars.replace('\0', '-') + '\n'));
                AttributedStringBuilder asb = new AttributedStringBuilder();
                asb.append(time).ansiAppend(title);
                titles.add(asb.toAttributedString());
                this.status.update(titles);
            }
            //manually flush or cursor position is incorrect
            terminal.flush();
            return true;
        } catch (Throwable e) {
            e.printStackTrace();
            return false;
        }
    }

    public Map getSecurityProviders() {
        Provider[] providerList = Security.getProviders();
        Map names = new HashMap<String, String>();
        for (Provider provider : providerList) {
            names.put(provider.getName(), provider.getInfo());
        }
        return names;
    }

    public int getBufferWidth() {
        return terminal.getBufferSize().getColumns();
    }

    public int getScreenWidth() {
        return terminal.getWidth();
    }

    public int getScreenHeight() {
        if (OSUtils.IS_WINDOWS && !(OSUtils.IS_CYGWIN || OSUtils.IS_MSYSTEM)) {
            return terminal.getHeight();
        }
        return terminal.getHeight() - titles.size();
    }


    public int wcwidth(String str) {
        if (str == null || str.equals("")) return 0;
        return display.wcwidth(str);
    }

    public void less(String output, int titleLines, int spaces, int lines) {
        More less = new More(terminal, null);
        //Less less=new Less(terminal, null);
        less.noInit = true;
        less.veryQuiet = true;
        less.numWidth = (int) Math.max(3, Math.ceil(Math.log10(lines < 10 ? 10 : lines)));
        less.padding = spaces;
        less.setTitleLines(titleLines);
        less.chopLongLines = true;
        less.quitIfOneScreen = true;
        less.ignoreCaseAlways = true;
        try {
            less.run(new Source.InputStreamSource(new ByteArrayInputStream(output.getBytes()), true, ""));
        } catch (Exception e) {
            e.printStackTrace();
        }
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

    public Object invokeMethod(String method, Object... o) {
        return accessor.invoke(reader, method, o);
    }


    private String currentBuffer;
    private String firstPrompt = "SQL> ";
    private int promptWidth = 5;
    private int cancelSeq = 0;

    public synchronized void increaseCancelSeq() {
        if (cancelSeq == 0) ++cancelSeq;
    }

    public String readLine(String prompt, String buffer) {
        try {
            setEvents(null, null);
            terminal.echo(false);
            terminal.resume();
            terminal.puts(InfoCmp.Capability.cursor_visible);
            terminal.flush();
            isPrompt = buffer != null && ansiPattern.matcher(buffer).find();
            if (isPrompt) {
                parser.setAnsi(buffer);
                buffer = null;
            }
            pause = false;
            currentBuffer = buffer;
            if (prompt != null && !prompt.equals(parser.secondPrompt)) {
                firstPrompt = prompt;
                promptWidth = wcwidth(firstPrompt);
            }
            prevDisplay = null;
            String line = reader.readLine(prompt, null, buffer);

            if (line != null) {
                line = parser.getLines();
                if (line == null) return readLine(parser.secondPrompt, null);
            }
            cancelSeq *= 0;
            if (pause) {
                terminal.echo(true);
                terminal.pause();
            } else {
                pause = true;
            }
            return line;
        } catch (Throwable e) {
            timer.stop();
            ++cancelSeq;
            try {
                if (cancelSeq >= 5) {
                    System.out.println("Detected 5 readLine errors, terminating the console to avoid blocking in backgound.");
                    System.out.flush();
                    if (status != null) {
                        this.status.close();
                        this.status.suspend();
                    }
                    return null;
                } else {
                    terminal.puts(InfoCmp.Capability.cursor_up);
                    terminal.puts(InfoCmp.Capability.delete_line);
                    terminal.raise(Terminal.Signal.INT);
                }
            } catch (Throwable e1) {
            }
            return "";
        } finally {
            try {
                if (cancelSeq >= 5) {
                    System.exit(0);
                } else {
                    if (status != null) status.redraw(true);
                }
            } catch (Throwable e2) {
                ++cancelSeq;
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

    public Boolean isBroken() {
        return cancelSeq >= 5;
    }

    public int setLastHistory() {
        return history.setIndex();
    }

    public void updateLastHistory(String line) {
        history.updateLast(line);
    }

    public void suspend(boolean enable) {
        if (terminal.paused() == enable && pause == enable) return;
        if (enable) {
            if (status != null) {
                status.hide();
                status.suspend();
            }
            terminal.echo(true);
            terminal.pause();
        } else {
            if (isBroken()) {
                System.exit(0);
                return;
            }
            terminal.resume();
            terminal.echo(false);
            if (status != null) {
                status.restore();
                setStatus("flush", "");
            }
        }
        pause = enable;
    }

    public synchronized void setEvents(ActionListener event, char[] keys) {
        this.event = event;
        this.keys = keys;
        if (this.task != null) {
            this.task.cancel(true);
            this.task = null;
        }
        if (this.event != null && this.keys != null) {
            //this.task = this.threadPool.scheduleWithFixedDelay(this.monitor, 1000, 200, TimeUnit.MILLISECONDS);
        }
    }

    public void setEvents() {
        setEvents(null, null);
    }

    public String getKeyMap(String[] options) throws Exception {
        ByteArrayOutputStream stream = new ByteArrayOutputStream();
        Commands.keymap(reader, new PrintStream(stream), System.err, options);
        return stream.toString();
    }

    public String setKeyCode(String keyEvent, String keyCode) throws IOException {
        String keySeq;
        if (keyCode == null) {
            write("Input key code for '" + keyEvent + "'(hit Enter to complete): ");
            int c;
            StringBuilder sb = new StringBuilder();
            boolean isPause = terminal.paused();
            if (isPause) terminal.resume();
            while (true) {
                c = terminal.reader().read();
                if (c > 0) {
                    if (c == 10 || c == 13) break;
                    sb.appendCodePoint(c);
                }
            }
            if (isPause) terminal.pause();
            keySeq = sb.toString();
            keyCode = KeyMap.display(keySeq);
            if (keyCode.equals("\"\"") && !keySeq.equals("")) {
                keyCode = "\"";
                c = Character.codePointCount(keySeq, 0, keySeq.length());
                for (int i = 0; i < c; i++) {
                    keyCode += "\\" + Integer.toOctalString(Character.codePointAt(keySeq, i));
                }
                keyCode += "\"";
            }
            write(keyCode + "\n");
        } else keySeq = KeyMap.translate(keyCode);
        if (keyCode.equals("")) return keyCode;
        keyMap.unbind(keySeq);
        keyMap.bind(new Reference(keyEvent), keySeq);
        return keyCode;
    }

    interface ParserCallback {
        Object[] call(Object... e);
    }

    class MyParser extends DefaultParser implements Highlighter {
        public static final String DEFAULT_HIGHLIGHTER_COLORS = "rs=1:st=2:nu=3:co=4:va=5:vn=6:fu=7:bf=8:re=9";
        public final Pattern numPattern = Pattern.compile("([0-9]+)");
        final String NOR = "\033[0m";
        public String buffer = null;
        public Map<String, String> colors = Arrays.stream(DEFAULT_HIGHLIGHTER_COLORS.split(":"))
                .collect(Collectors.toMap(s -> s.substring(0, s.indexOf('=')),
                        s -> s.substring(s.indexOf('=') + 1)));
        public Map<String, Object> commands = new HashMap();
        volatile String secondPrompt = "    ";
        volatile int lines = 0;
        StringBuffer sb = new StringBuffer(32767);
        boolean enabled = true;
        Pattern p1 = Pattern.compile("^(\\s*\\.?)([^\\s\\w]+|\\w[^\\s\\|;/]*)(.*)$", Pattern.DOTALL);
        AttributedStringBuilder asb = new AttributedStringBuilder();
        final AttributedString empty = asb.toAttributedString();
        private String ansi = null;
        private String errorAnsi = null;
        private volatile String prev = null;
        private volatile int sub = 0;

        public MyParser() {
            super();
            setAnsi(NOR);
            super.setEofOnEscapedNewLine(true);
            reader.setVariable(SECONDARY_PROMPT_PATTERN, secondPrompt);
            quoteChars(new char[]{'\'', '"', '`'}).escapeChars(new char[]{});
            Interrupter.listen(MyParser.this, c -> {
                lines = 0;
                sb.setLength(0);
            });
        }

        @Override
        public boolean isDelimiterChar(CharSequence buffer, int pos) {
            final char c = buffer.charAt(pos);
            return Character.isWhitespace(c) || (c != '.' && c != '_' && c != '$' && c != '#' && !(c >= '0' && c <= '9') && !(c >= 'A' && c <= 'Z') && !(c >= 'a' && c <= 'z'));
        }

        public final String getLines() {
            if (lines < 0) ++lines;
            return lines > 0 ? null : sb.toString();
        }

        public final ParsedLine parse(final String line, final int cursor, final ParseContext context) {
            if (!isPrompt && line == null) return null;
            if (Thread.currentThread().isInterrupted()) return super.parse("", 0, context);
            if (context == ParseContext.COMPLETE) return super.parse(line, cursor, context);
            if (context != ParseContext.ACCEPT_LINE) return null;

            if (lines <= 0) sb.setLength(0);
            else sb.append('\n');
            sb.append(line);

            if (parserCallback == null) {
                lua.load("return {call=env.parse_line}", "proxy");
                lua.call(0, 1);
                parserCallback = lua.getProxy(-1, ParserCallback.class);
                lua.pop(1);
            }
            Object[] result = parserCallback.call(line);
            lines += (int) result[3];
            if ((Boolean) result[0]) {
                if (result.length > 1 && !secondPrompt.equals(result[1])) {
                    String prompt = (String) result[1];
                    if (prompt == null || prompt.length() != promptWidth && prompt.trim().equals("")) {
                        prompt = String.format("%" + promptWidth + "s", " ");
                    }
                    if (!prompt.equals(secondPrompt)) {
                        secondPrompt = prompt;
                        reader.setVariable(SECONDARY_PROMPT_PATTERN, secondPrompt);
                    }
                }
                return null;
            }
            if (lines <= terminal.getHeight() - 10 && currentBuffer == null) {
                reader.setVariable(DISABLE_HISTORY, false);
                history.add(sb.toString());
                reader.setVariable(DISABLE_HISTORY, true);
            }
            lines = 0;
            if ((Boolean) result[2]) {
                pause = true;
            }
            return null;
        }


        public final void setAnsi(final String ansi) {
            if (ansi.equals(this.ansi)) return;
            this.ansi = ansi;
            Matcher m = numPattern.matcher(ansi);
            m.find();
            this.errorAnsi = Integer.valueOf(m.group(1)) > 50 ? "\33[91m" : "\33[31m";
            enabled = !ansi.equals(NOR);
            for (String key : colors.keySet()) {
                String value;
                switch (key) {
                    case "bf":
                        value = "\33[91m";
                        break;
                    case "fu":
                        value = ansi;
                        break;
                    case "rs":
                        value = "\33[95m";
                        break;
                    default:
                        value = ansi;
                        break;
                }
                colors.put(key, value);
            }
        }

        private final AttributedStringBuilder process(final String buffer, final int index) {
            char c;
            boolean found;
            if (!enabled) asb.append(buffer);
            else {
                final int n = buffer.length();
                if (n > 2048) {
                    asb.append(buffer);
                    return asb;
                }
                for (int i = index; i < n; i++) {
                    c = buffer.charAt(i);
                    found = c == '(' || c == ')' || c == '{' || c == '}' || c == ',';
                    if (found) asb.ansiAppend(NOR);
                    asb.append(c);
                    if (found) asb.ansiAppend(ansi);
                }
            }
            return asb;
        }

        public final AttributedString highlight(final LineReader reader, final String buffer) {
            try {
                final int len = buffer.length();
                if (sub > 0 && len >= sub && buffer.startsWith(prev)) {
                    if (len > sub) {
                        process(buffer, sub);
                        sub = len;
                        prev = buffer;
                    }
                    return asb.toAttributedString();
                }
                sub *= 0;
                prev = null;
                asb.setLength(0);

                if (len == 0) {
                    return empty;
                } else if (buffer.charAt(0) == '\33') {
                    asb.ansiAppend(buffer);
                } else if (!enabled) {
                    asb.ansiAppend(ansi).append(buffer);
                } else {
                    if (Console.this.isSubSystem || lines != 0) {
                        asb.ansiAppend(ansi);
                        process(buffer, 0);
                        sub = len;
                        prev = buffer;
                    } else {
                        //Handling command name
                        final Matcher m = p1.matcher(buffer);
                        if (m.find()) {
                            asb.ansiAppend(NOR);
                            if (!commands.containsKey(m.group(2).toUpperCase())) {
                                asb.ansiAppend(m.group(1)).ansiAppend(errorAnsi).append(m.group(2)).ansiAppend(ansi);
                                process(m.group(3), 0);
                            } else {
                                asb.ansiAppend(ansi);
                                process(buffer, 0);
                            }
                            if (!m.group(3).equals("")) {
                                prev = buffer;
                                sub = len;
                            }
                        } else process(buffer, 0);
                    }
                }
                return asb.toAttributedString();
            } catch (Exception e) {
                e.printStackTrace();
                throw e;
            } finally {

            }
        }

        @Override
        public void setErrorPattern(Pattern errorPattern) {

        }

        @Override
        public void setErrorIndex(int errorIndex) {

        }
    }
}
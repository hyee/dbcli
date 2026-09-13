package org.dbcli;

import com.esotericsoftware.reflectasm.ClassAccess;
import com.sun.jna.WString;
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
import org.jline.terminal.impl.DumbTerminal;
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
import java.util.List;
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
    private volatile LuaState lua;
    volatile private ScheduledFuture task;
    //read on the signal/event thread (callback) and written on the Lua thread (setEvents/setLua)
    private volatile ActionListener event;
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
    private Attributes originalAttributes = null;
    private Attributes savedAttributes = null;

    private static int envInt(String name, int def) {
        String value = System.getenv(name);
        if (value != null) {
            try {
                int i = Integer.parseInt(value.trim());
                if (i > 0) return i;
            } catch (NumberFormatException ignored) {
            }
        }
        return def;
    }

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
            try {
                this.terminal = WinSysTerminal.createTerminal(colorPlan,
                        null,
                        "ansicon".equals(mode) || "conemu".equals(mode),
                        encoding, true,
                        Terminal.SignalHandler.SIG_IGN,
                        false);
            } catch (IOException e) {
                //No console attached (redirected stdio / harness / background): fall through to the generic
                //builder, which yields a dumb terminal instead of aborting before anything can be printed.
                this.terminal = null;
            }
        }
        if (this.terminal == null) {
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
        //A dumb terminal carries no size, which degenerates every width-dependent layout (grid/colwrap/line
        //trimming). Defaults are unchanged; DBCLI_BUFFER_COLS/DBCLI_BUFFER_ROWS (or COLUMNS/LINES) opt into a fixed size.
        if (this.terminal instanceof DumbTerminal) {
            int cols = envInt("DBCLI_BUFFER_COLS", envInt("COLUMNS", 0));
            int rows = envInt("DBCLI_BUFFER_ROWS", envInt("LINES", 0));
            if (cols > 0 && rows > 0) terminal.setSize(new Size(cols, rows));
        }
        //Capture the pristine (cooked) terminal state before dbcli ever enters raw mode; restored when handing the console to a native child.
        this.originalAttributes = terminal.getAttributes();
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
        initTerminalKeys();

        input = terminal.reader();
        writer = new Output(terminal.writer());
        colorPlan = terminal.getType();

        threadID = Thread.currentThread().getId();
        callback = new EventCallback() {
            @Override
            public void call(Object... c) {
                increaseCancelSeq();
                if (c.length > 0) {
                    if (!pause && lua != null && threadID == Thread.currentThread().getId()) {
                        long[] keyData = new long[8];
                        final boolean isKeyArray = c[0] instanceof long[];
                        if (isKeyArray) {
                            System.arraycopy((long[]) c[0], 0, keyData, 0, keyData.length);
                        } else {
                            keyData[2] = '\3';
                        }
                        lua.getGlobal("TRIGGER_EVENT");
                        Object r = lua.call(keyData, c.length > 1 ? String.valueOf(c[1]) : "CTRL+C")[0];
                        //2 means "the key was consumed": write it back into the caller's key array, which only
                        //exists when the event arrived as one (a CTRL+C ActionEvent carries no key array).
                        if (isKeyArray && r instanceof Number && ((Number) r).intValue() == 2) {
                            ((long[]) c[0])[0] = 2;
                        }
                    } else if (event != null) {
                        //The event itself is c[0]; c[1] only carries the key name for the TRIGGER_EVENT call.
                        if (c[0] instanceof ActionEvent) event.actionPerformed((ActionEvent) c[0]);
                        else event.actionPerformed(new ActionEvent(this, ActionEvent.ACTION_PERFORMED, "\3"));
                    }
                }

                if (titles.size() > 0) {
                    new Thread(() -> {
                        try {
                            Thread.sleep(1000);
                        } catch (InterruptedException e) {
                        }
                        reader.redrawLine();
                        if (status != null) setStatus("flush", null);
                    }).start();
                }
            }
        };
        Interrupter.listen(this, callback);
        display = new Display(terminal, false);
        prevSize = new Size(getScreenHeight(), getBufferWidth());
        terminal.handle(Terminal.Signal.WINCH, this::handleResize);
    }

    //Widgets to use for A/B/C/D (up/down/right/left), and the modifier numbers of the two CSI forms:
    //CSI 1;<n><final> and CSI <n><final>, where n-1 is SHIFT|ALT|CTRL (2=Shift 3=Alt 5=Ctrl 6=Ctrl+Shift ...).
    private static final String[] ARROW_WIDGETS = {
            LineReader.UP_HISTORY, LineReader.DOWN_HISTORY, LineReader.FORWARD_WORD, LineReader.BACKWARD_WORD};
    private static final char[] ARROW_FINALS = {'A', 'B', 'C', 'D'};
    private static final String[] ARROW_MODS =
            {"1;2", "1;3", "1;4", "1;5", "1;6", "1;7", "1;8", "2", "3", "4", "5", "6", "7", "8"};
    private static final String SENTINEL_INSERT = "dbcli-sentinel-insert";

    //Terminals disagree on how a modified arrow key is encoded, and the terminfo Linux/mac provides makes JLine
    //pre-bind the forms it knows (Shift+arrows end up on `beep`), so the encodings are bound here explicitly.
    private void initTerminalKeys() throws IOException {
        //Backspace: DEL, plus the "no character" sentinel U+FFFF ((char)-1) that MSYS/ConPTY terminals report for
        //the backspace key. A code point >= KeyMap.KEYMAP_LENGTH cannot live in a keymap, so the sentinel is only
        //reachable through the keymap's unicode fallback.
        setKeyCode(LineReader.BACKWARD_DELETE_CHAR, Character.toString('\177'));
        reader.getWidgets().put(SENTINEL_INSERT, this::insertOrDelete);
        keyMap.setUnicode(new Reference(SENTINEL_INSERT));
        //Delete a word: Ctrl+_, Ctrl+W, Alt+Backspace (ESC BS on the Windows console, ESC DEL elsewhere).
        for (String s : new String[]{"^_", "\027"}) setKeyCode(LineReader.BACKWARD_KILL_WORD, s);
        for (String s : new String[]{"^[^H", "^[\177"}) setKeyCode(LineReader.BACKWARD_KILL_WORD, s);
        //Word motion and history: the xterm CSI 1;<n><final> form (what JLine synthesises for the Windows console,
        //and what xterm/gnome-terminal/iTerm2/Windows Terminal send), the legacy CSI <n><final> form (rxvt, PuTTY,
        //Xshell's "CSI 5" mode, TERM=linux), rxvt's CSI a-d / SS3 a-d forms, and the ESC-prefixed forms of
        //terminals that pass Alt through as a leading ESC.
        for (String m : ARROW_MODS)
            for (int i = 0; i < ARROW_FINALS.length; i++) setKeyCode(ARROW_WIDGETS[i], "^[[" + m + ARROW_FINALS[i]);
        for (String p : new String[]{"^[[", "^[O"})
            for (int i = 0; i < ARROW_FINALS.length; i++) {
                setKeyCode(ARROW_WIDGETS[i], p + (char) ('a' + i));
                setKeyCode(ARROW_WIDGETS[i], "^[" + p + ARROW_FINALS[i]);
            }
        //A plain arrow keeps whatever the terminal capability bound (char motion, up-line-or-search); whose CSI/SS3
        //form is still free is worth binding, since that is then the only encoding the terminal can send.
        for (String p : new String[]{"^[[", "^[O"})
            for (int i = 0; i < ARROW_FINALS.length; i++)
                if (keyMap.getBound(KeyMap.translate(p + ARROW_FINALS[i])) == null)
                    setKeyCode(ARROW_WIDGETS[i], p + ARROW_FINALS[i]);
        //Home / End: xterm-style ^[[1~/^[[4~, plus the CSI form used by macOS Terminal.app and VT consoles.
        if (!OSUtils.IS_OSX) {
            setKeyCode(LineReader.BEGINNING_OF_LINE, "^[[1~");
            setKeyCode(LineReader.END_OF_LINE, "^[[4~");
        }
        for (String s : new String[]{"^[[H", "^[OH"}) setKeyCode(LineReader.BEGINNING_OF_LINE, s);
        for (String s : new String[]{"^[[F", "^[OF"}) setKeyCode(LineReader.END_OF_LINE, s);
        //alt+y / alt+z for redo / undo. The shifted (ESC Y / ESC Z) and the ^X^R / ^X^U chords are bound too:
        //a terminal that uppercases the Alt+letter would otherwise land on JLine's `do-lowercase-version` and
        //corrupt the line, and JLine's own ^X^R/^X^U only exist on its emacs keymap. On macOS Option+z/y types a
        //special character instead of ESC+z/y (profile setting), so the ^X^R / ^X^U pair is the reliable one there.
        for (String s : new String[]{"^[y", "^[Y", "^X^R"}) setKeyCode("redo", s);
        for (String s : new String[]{"^[z", "^[Z", "^X^U"}) setKeyCode("undo", s);
    }

    //The keymap's unicode fallback: every unbound character lands here. U+FFFF is the backspace sentinel of the
    //console/ConPTY terminals, anything else is normal text.
    private boolean insertOrDelete() {
        if ("\uffff".equals(reader.getLastBinding())) reader.callWidget(LineReader.BACKWARD_DELETE_CHAR);
        else reader.callWidget(LineReader.SELF_INSERT);
        return true;
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
        //A dashboard repaint does not need the line editor's diff: with the rectangle writer on, the
        //whole screen goes out as one block (home, rows, erase to end of line). The writer then paints
        //it with a single WriteConsoleOutputW instead of one cursor addressed write per row, which is
        //the difference between "the screen appears" and "the screen paints itself line by line".
        if (bulkDisplay()) {
            int height = getScreenHeight();
            List<AttributedString> lines = Arrays.stream(args)
                    .map(s -> s == null ? null : AttributedString.fromAnsi(s))
                    .collect(Collectors.toList());
            Attributes attrs = terminal.enterRawMode();
            terminal.writer().print(screenBlock(lines, height, width));
            terminal.writer().flush();
            terminal.setAttributes(attrs);
            prevDisplay = args;
            return;
        }
        display.clear();
        display.resize(getScreenHeight(), width);
        Attributes attrs = terminal.enterRawMode();
        display.update(Arrays.stream(args)
                .map(s -> AttributedString.fromAnsi(s + (s.endsWith("\n") ? "" : "\n"))
                        .columnSubSequence(0, width)).collect(Collectors.toList()), -1);
        terminal.setAttributes(attrs);
        prevDisplay = args;
    }

    /**
     * One screenful as a single sequential write: home, every row, erase to end of line. The rectangle
     * writer turns that into one WriteConsoleOutputW; anything it declines still gets the whole screen
     * in one chunk for ConEmuHk instead of one cursor addressed write per row.
     */
    static String screenBlock(List<AttributedString> lines, int rows, int columns) {
        StringBuilder sb = new StringBuilder(16 + (columns + 8) * (rows + 1));
        sb.append("\u001b[H");
        for (int i = 0; i < rows; i++) {
            if (i > 0) {
                sb.append("\r\n");
            }
            if (i < lines.size() && lines.get(i) != null) {
                sb.append(lines.get(i).columnSubSequence(0, columns).toAnsi());
            }
            sb.append("\u001b[K");
        }
        return sb.toString();
    }


    /** the ConEmu console (no ENABLE_VIRTUAL_TERMINAL_PROCESSING) with the rectangle writer enabled */
    static boolean isBulkBlockEnabled(Terminal terminal) {
        return BulkCellWriter.isEnabled()
                && !BulkCellWriter.isSafe()
                && AbstractWindowsTerminal.TYPE_WINDOWS_CONEMU.equals(terminal.getType());
    }

    private boolean bulkDisplay() {
        // The screen block is plain ANSI, so it needs no rectangle writer - only a terminal that can
        // take ANSI as-is. Inside a real ConEmu window dbcli gets JLine's native Windows terminal
        // (Console.java:118 skips dbcli's own WinSysTerminal there), whose type is still windows-conemu
        // (NativeWinSysTerminal.java:74 picks it when TERM is unset and ConEmuPID is set) - so this is
        // true there as well. That matters: the repaint this replaces goes through Display.clear(),
        // which makes Display.update emit clear_screen (\e[H\E[J for windows-conemu) and wipes the
        // screen - it is why leaving the pager used to clear everything in a real ConEmu window.
        return isBulkBlockEnabled(terminal);
    }

    public void handleResize(Terminal.Signal signal) {
        Size size = terminal.getBufferSize();
        if (prevSize != null && size.getRows() > 1
                && prevSize.getColumns() == size.getColumns()
                && prevSize.getRows() == size.getRows()) {
            return;
        }

        if (prevSize == null) prevSize = new Size(size.getColumns(), size.getRows());   //a WINCH before the ctor
        else prevSize.copy(size);

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
        // The grid formats its rows to this width. On a console it is the screen buffer width, which on
        // this user's terminals is deliberately much wider than the window (2000 columns) so that output
        // stays readable in the scrollback. A pty has no such thing: Terminal.getBufferSize() defaults to
        // getSize(), i.e. the window, and nothing inside the pty can see the console's buffer either, so
        // DBCLI_BUFFER_COLS (or COLUMNS) is how that width is stated - dbcli.sh carries a commented out export
        // for the 2000 column case.
        int cols = envInt("DBCLI_BUFFER_COLS", envInt("COLUMNS", 0));
        return cols > 0 ? cols : terminal.getBufferSize().getColumns();
    }

    public int getScreenWidth() {
        return terminal.getWidth();
    }

    public int getScreenHeight() {
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
        //Digits of the largest line number, not ceil(log10(n)): that came out one short for 1000,
        //10000, ... and then every numbered row was one column wider than the budget.
        less.numWidth = Math.max(3, String.valueOf(lines < 10 ? 10 : lines).length());
        less.padding = spaces;
        less.setTitleLines(titleLines);
        less.chopLongLines = true;
        less.quitIfOneScreen = true;
        less.ignoreCaseAlways = true;
        try {
            //The text is already a String: runText() avoids output.getBytes() (a second full copy and
            //a silent '?' for anything the platform charset cannot encode).
            less.runText("", output);
        } catch (Throwable e) {
            //Must catch Throwable: an Error (the OOM the pager raises on a huge result set) is not an
            //Exception, so it is the case the old code could not report. Note that an escaping
            //Throwable *was* already reported by printer.lua's pcall(console.less, ...) - what
            //vanished was a caught Nothing: the old body printed the stack trace to stderr only, and
            //a database session has no visible stderr. Report on the terminal as well.
            try {
                println("");
                println("[more failed: " + e + "]");
            } catch (Throwable ignored) {
                //nothing else we can do while reporting a failure
            }
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
        //PrintWriter.println() is two writes (the text, then newLine()): JLine hands each write to the
        //console writer separately, so every line arrived as two chunks - and on a console without VT
        //processing each chunk costs its own console round trip in ConEmuWriter. One write instead.
        writer.print(msg + System.lineSeparator());
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
        } catch (EndOfFileException eof) {
            //Ctrl+D on a console, or the end of a redirected/piped stdin: not an error. Still counts towards
            //the limit so a prompt loop that keeps re-reading (env.ask) cannot spin forever, but reports
            //"no more input" instead of "" -- input.lua then runs env.exit() and the session closes cleanly.
            ++cancelSeq;
            return null;
        } catch (Throwable e) {
            timer.stop();
            ++cancelSeq;
            try {
                if (cancelSeq >= 5) {
                    System.out.println("Detected 5 readLine errors, terminating the console to avoid blocking in background.");
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
            terminal.pause();
            //Save the current console mode before restoring to original mode for native child
            if (terminal instanceof WinSysTerminal) {
                ((WinSysTerminal) terminal).saveConsoleMode();
                ((WinSysTerminal) terminal).restoreOrgConsoleMode();
            } else {
                savedAttributes = terminal.getAttributes();
                terminal.setAttributes(originalAttributes);
            }
        } else {
            if (isBroken()) {
                System.exit(0);
                return;
            }
            if (savedAttributes != null) {
                terminal.setAttributes(savedAttributes);
            }
            //Restore the console mode that was active before pause
            if (terminal instanceof WinSysTerminal) {
                ((WinSysTerminal) terminal).resumeConsoleMode();
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
            //A colour sequence needs no parameter ("\33[m" is a plain reset), and ansiPattern accepts that,
            //so fall back to the default red instead of letting group(1) throw out of highlight setup.
            int severity = m.find() ? Integer.parseInt(m.group(1)) : 0;
            this.errorAnsi = severity > 50 ? "\33[91m" : "\33[31m";
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
            if (!enabled) asb.append(index > 0 ? buffer.substring(index) : buffer);
            else {
                final int n = buffer.length();
                if (n > 2048) {
                    asb.append(index > 0 ? buffer.substring(index) : buffer);
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

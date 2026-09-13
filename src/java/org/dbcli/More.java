/*
 * Copyright (c) 2002-2018, the original author or authors.
 *
 * This software is distributable under the BSD license. See the terms of the
 * BSD license in the documentation provided with this software.
 *
 * https://opensource.org/licenses/BSD-3-Clause
 */
package org.dbcli;
/*
 * Copyright (c) 2002-2020, the original author or authors.
 *
 * This software is distributable under the BSD license. See the terms of the
 * BSD license in the documentation provided with this software.
 *
 * https://opensource.org/licenses/BSD-3-Clause
 */

import org.jline.builtins.*;
import org.jline.builtins.Nano.PatternHistory;
import org.jline.builtins.Source.ResourceSource;
import org.jline.builtins.Source.URLSource;
import org.jline.keymap.BindingReader;
import org.jline.keymap.KeyMap;
import org.jline.terminal.Attributes;
import org.jline.terminal.Size;
import org.jline.terminal.Terminal;
import org.jline.terminal.Terminal.Signal;
import org.jline.terminal.Terminal.SignalHandler;
import org.jline.utils.*;
import org.jline.utils.InfoCmp.Capability;

import java.io.*;
import java.io.InputStreamReader;
import java.nio.file.*;
import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.regex.PatternSyntaxException;
import java.util.stream.Stream;

import static org.jline.keymap.KeyMap.*;

/* Change following class/methods as public：
   Nano.PatternHistory
   Nano.Parser
   Nano.Parser.split
   Commands.findFiles
* */
final public class More {

    private static final int ESCAPE = 27;
    private static final String MESSAGE_FILE_INFO = "FILE_INFO";

    public boolean quitAtSecondEof;
    public boolean quitAtFirstEof;
    public boolean quitIfOneScreen;
    public boolean printLineNumbers;
    public boolean quiet;
    public boolean veryQuiet;
    public boolean chopLongLines;
    public boolean ignoreCaseCond;
    public boolean ignoreCaseAlways;
    public boolean noKeypad;
    public boolean noInit;
    protected List<Integer> tabs = Collections.singletonList(4);
    protected String syntaxName;
    private String historyLog = null;

    protected final Terminal terminal;
    protected final Play display;
    protected final BindingReader bindingReader;
    protected final Path currentDir;

    protected List<Source> sources;
    protected int sourceIdx;
    protected BufferedReader reader;
    protected KeyMap<Operation> keys;

    protected int firstLineInMemory = 0;
    //Raw line text, already trimmed. An AttributedString costs 10 bytes per char (char[] and
    //long[] of the same length) against 2 for a String, and the pager used to keep every line it
    //had ever read, so a 32k line result set needed ~800MB and died with OutOfMemoryError on the
    //shipped 32bit JVM. Lines are therefore kept as text and materialised on demand, cached with
    //an LRU bound so that repeated repaints of the same screen stay allocation free.
    //firstLineInMemory is the absolute number of the oldest line held in lines (titleLines when
    //nothing has been pruned), i.e. lines.get(k) is line firstLineInMemory + k. Older lines are
    //re-read from the source when the user scrolls back above the window (rewindable sources only).
    //Title lines are never pruned: they live in titles[] and are only a handful.
    protected List<String> lines = new ArrayList<>();
    protected static final int MATERIALIZED_CACHE = 512;
    protected static final int WINDOW_LINES = 4096;
    //Extra lines kept above WINDOW_LINES before a batch drop; see pruneWindow().
    protected static final int WINDOW_SLACK = 1024;
    protected static final int WINDOW_CHARS = 4 << 20;
    //How many leading lines decide whether the grid's left padding is real (see checkPadding).
    private static final int PADDING_PROBE_LINES = 30;
    protected int windowChars = 0;
    protected boolean rewindable = false;
    //Highest totalLines reached since the source was opened: a rewind restarts the read cursor, but
    //the file info message must not report a shrinking line count.
    protected int highWaterLines = 0;
    private final Map<Integer, AttributedString> materialized =
            new LinkedHashMap<>(128, 0.75f, true);

    protected int firstLineToDisplay = 0;
    protected int firstColumnToDisplay = 0;
    protected int offsetInLine = 0;

    protected String message;
    protected String errorMessage;
    protected final StringBuilder buffer = new StringBuilder();

    protected final Map<String, Operation> options = new TreeMap<>();

    protected int window;
    protected int halfWindow;

    protected int nbEof;

    protected PatternHistory patternHistory = new PatternHistory(null);
    protected String pattern;
    protected String displayPattern;

    protected final Size size = new Size();
    protected final ArrayList<Integer> matchedLines = new ArrayList<>();
    protected int matchedIndex = -1;
    protected boolean matchedAsc = true;

    SyntaxHighlighter syntaxHighlighter;
    private final List<Path> syntaxFiles = new ArrayList<>();
    private boolean highlight = true;
    private boolean nanorcIgnoreErrors;
    protected static String clrBol = null;

    public static String[] usage() {
        return new String[]{
                "less -  file pager",
                "Usage: less [OPTIONS] [FILES]",
                "  -? --help                    Show help",
                "  -e --quit-at-eof             Exit on second EOF",
                "  -E --QUIT-AT-EOF             Exit on EOF",
                "  -F --quit-if-one-screen      Exit if entire file fits on first screen",
                "  -q --quiet --silent          Silent mode",
                "  -Q --QUIET --SILENT          Completely silent",
                "  -S --chop-long-lines         Do not fold long lines",
                "  -i --ignore-case             Search ignores lowercase case",
                "  -I --IGNORE-CASE             Search ignores all case",
                "  -x --tabs=N[,...]            Set tab stops",
                "  -N --LINE-NUMBERS            Display line number for each line",
                "  -Y --syntax=name             The name of the syntax highlighting to use.",
                "     --no-init                 Disable terminal initialization",
                "     --no-keypad               Disable keypad handling",
                "     --ignorercfiles           Don't look at the system's lessrc nor at the user's lessrc.",
                "  -H --historylog=name         Log search strings to file, so they can be retrieved in later sessions"
        };
    }

    public More(Terminal terminal, Path currentDir) {
        this(terminal, currentDir, null);
    }

    public More(Terminal terminal, Path currentDir, Options opts) {
        this(terminal, currentDir, opts, null);
    }

    public More(Terminal terminal, Path currentDir, Options opts, ConfigurationPath configPath) {
        this.terminal = terminal;
        this.display = new Play(terminal);
        this.bindingReader = new BindingReader(terminal.reader());
        this.currentDir = currentDir;
        this.clrBol = terminal.getStringCapability(InfoCmp.Capability.clr_bol);
        Path lessrc = configPath != null ? configPath.getConfig("jlessrc") : null;
        boolean ignorercfiles = opts != null && opts.isSet("ignorercfiles");
        if (lessrc != null && !ignorercfiles) {
            try {
                parseConfig(lessrc);
            } catch (IOException e) {
                errorMessage = "Encountered error while reading config file: " + lessrc;
            }
        } else if (new File("/usr/share/nano").exists() && !ignorercfiles) {
            PathMatcher pathMatcher = FileSystems.getDefault().getPathMatcher("glob:/usr/share/nano/*.nanorc");
            try (Stream<Path> pathStream = Files.walk(Paths.get("/usr/share/nano"))) {
                pathStream.filter(pathMatcher::matches).forEach(syntaxFiles::add);
                nanorcIgnoreErrors = true;
            } catch (IOException e) {
                errorMessage = "Encountered error while reading nanorc files";
            }
        }
        if (opts != null) {
            for (String flag : FLAG_OPTIONS) {
                if (opts.isSet(flag)) {
                    applyFlag(flag, true);
                }
            }
            if (opts.isSet("tabs")) {
                doTabs(opts.get("tabs"));
            }
            if (opts.isSet("syntax")) {
                syntaxName = opts.get("syntax");
                nanorcIgnoreErrors = false;
            }
            if (opts.isSet("no-init")) {
                noInit = true;
            }
            if (opts.isSet("no-keypad")) {
                noKeypad = true;
            }
            if (opts.isSet("historylog")) {
                historyLog = opts.get("historylog");
            }
        }
        if (configPath != null && historyLog != null) {
            try {
                patternHistory = new PatternHistory(configPath.getUserConfig(historyLog, true));
            } catch (IOException e) {
                errorMessage = "Encountered error while reading pattern-history file: " + historyLog;
            }
        }
    }

    private void parseConfig(Path file) throws IOException {
        try (BufferedReader reader = Files.newBufferedReader(file)) {
            String line = reader.readLine();
            while (line != null) {
                line = line.trim();
                if (!line.isEmpty() && !line.startsWith("#")) {
                    List<String> parts = SyntaxHighlighter.RuleSplitter.split(line);
                    if (parts.get(0).equals("include")) {
                        SyntaxHighlighter.nanorcInclude(parts.get(1), syntaxFiles);
                    } else if (parts.get(0).equals("theme")) {
                        SyntaxHighlighter.nanorcTheme(parts.get(1), syntaxFiles);
                    } else if (parts.size() == 2
                            && (parts.get(0).equals("set") || parts.get(0).equals("unset"))) {
                        String option = parts.get(1);
                        if (!applyFlag(option, parts.get(0).equals("set"))) {
                            errorMessage = "Less config: Unknown or unsupported configuration option " + option;
                        }
                    } else if (parts.size() == 3 && parts.get(0).equals("set")) {
                        String option = parts.get(1);
                        String val = parts.get(2);
                        if (option.equals("tabs")) {
                            doTabs(val);
                        } else if (option.equals("historylog")) {
                            historyLog = val;
                        } else {
                            errorMessage = "Less config: Unknown or unsupported configuration option " + option;
                        }
                    } else if (parts.get(0).equals("bind") || parts.get(0).equals("unbind")) {
                        errorMessage = "Less config: Key bindings can not be changed!";
                    } else {
                        errorMessage = "Less config: Bad configuration '" + line + "'";
                    }
                }
                line = reader.readLine();
            }
        }
    }

    //Keys offered by the interactive "-" option editor, in the order they are listed here.
    private static final Map<String, Operation> OPTION_KEYS = new LinkedHashMap<>();

    static {
        OPTION_KEYS.put("-e", Operation.OPT_QUIT_AT_SECOND_EOF);
        OPTION_KEYS.put("--quit-at-eof", Operation.OPT_QUIT_AT_SECOND_EOF);
        OPTION_KEYS.put("-E", Operation.OPT_QUIT_AT_FIRST_EOF);
        OPTION_KEYS.put("-QUIT-AT-EOF", Operation.OPT_QUIT_AT_FIRST_EOF);
        OPTION_KEYS.put("-N", Operation.OPT_PRINT_LINES);
        OPTION_KEYS.put("--LINE-NUMBERS", Operation.OPT_PRINT_LINES);
        OPTION_KEYS.put("-q", Operation.OPT_QUIET);
        OPTION_KEYS.put("--quiet", Operation.OPT_QUIET);
        OPTION_KEYS.put("--silent", Operation.OPT_QUIET);
        OPTION_KEYS.put("-Q", Operation.OPT_VERY_QUIET);
        OPTION_KEYS.put("--QUIET", Operation.OPT_VERY_QUIET);
        OPTION_KEYS.put("--SILENT", Operation.OPT_VERY_QUIET);
        OPTION_KEYS.put("-S", Operation.OPT_CHOP_LONG_LINES);
        OPTION_KEYS.put("--chop-long-lines", Operation.OPT_CHOP_LONG_LINES);
        OPTION_KEYS.put("-i", Operation.OPT_IGNORE_CASE_COND);
        OPTION_KEYS.put("--ignore-case", Operation.OPT_IGNORE_CASE_COND);
        OPTION_KEYS.put("-I", Operation.OPT_IGNORE_CASE_ALWAYS);
        OPTION_KEYS.put("--IGNORE-CASE", Operation.OPT_IGNORE_CASE_ALWAYS);
        OPTION_KEYS.put("-Y", Operation.OPT_SYNTAX_HIGHLIGHT);
        OPTION_KEYS.put("--syntax", Operation.OPT_SYNTAX_HIGHLIGHT);
    }

    //Names the constructor asks the caller's Options object about. It must list exactly the names in
    //that spec: Options.isSet() throws for anything the spec does not define. The aliases ("silent",
    //"SILENT") only exist in the lessrc syntax, and applyFlag() accepts them for that path.
    private static final String[] FLAG_OPTIONS = {
            "QUIT-AT-EOF", "quit-at-eof", "quit-if-one-screen", "quiet", "QUIET",
            "chop-long-lines", "IGNORE-CASE", "ignore-case", "LINE-NUMBERS"
    };

    /** Apply one boolean option; false when the name is unknown. */
    private boolean applyFlag(String option, boolean value) {
        switch (option) {
            case "QUIT-AT-EOF": quitAtFirstEof = value; return true;
            case "quit-at-eof": quitAtSecondEof = value; return true;
            case "quit-if-one-screen": quitIfOneScreen = value; return true;
            case "quiet":
            case "silent": quiet = value; return true;
            case "QUIET":
            case "SILENT": veryQuiet = value; return true;
            case "chop-long-lines": chopLongLines = value; return true;
            case "IGNORE-CASE": ignoreCaseAlways = value; return true;
            case "ignore-case": ignoreCaseCond = value; return true;
            case "LINE-NUMBERS": printLineNumbers = value; return true;
            default: return false;
        }
    }

    private void doTabs(String val) {
        tabs = new ArrayList<>();
        for (String s : val.split(",")) {
            try {
                tabs.add(Integer.parseInt(s));
            } catch (Exception ex) {
                errorMessage = "Less config: tabs option error parsing number: " + s;
            }
        }
    }

    // to be removed
    public More tabs(List<Integer> tabs) {
        this.tabs = tabs;
        return this;
    }

    public void handle(Signal signal) {
        size.copy(terminal.getSize());
        try {
            display.clear();
            display(false);
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    public void run(Source src) throws IOException, InterruptedException {
        ArrayList<Source> list = new ArrayList<>();
        list.add(src);
        run(list);
    }

    /**
     * Run the pager over text that is already in memory. Console.less() used to hand the pager
     * {@code output.getBytes()}, which copied the whole payload a second time (up to ~88MB, exactly
     * when memory is tightest) and silently replaced every character the platform charset cannot
     * encode with '?'. This path reads the characters directly.
     */
    public void runText(String name, String text) throws IOException, InterruptedException {
        run(new TextSource(name, text));
    }

    public void run(Source... sources) throws IOException, InterruptedException {
        run(new ArrayList<>(Arrays.asList(sources)));
    }

    public void run(List<Source> sources) throws IOException, InterruptedException {
        if (sources == null || sources.isEmpty()) {
            throw new IllegalArgumentException("No sources");
        }
        //Work on a copy: the caller's list must not be modified (it may even be immutable).
        List<Source> list = new ArrayList<>(sources);
        list.add(0, new ResourceSource("less-help.txt", "HELP -- Press SPACE for more, or q when done"));
        this.sources = list;

        sourceIdx = 1;
        openSource();
        if (errorMessage != null) {
            message = errorMessage;
            errorMessage = null;
        }

        try {
            size.copy(terminal.getSize());
            if (quitIfOneScreen && sources.size() == 2) {
                if (display(true)) {
                    return;
                }
            }

            SignalHandler prevHandler = terminal.handle(Signal.WINCH, this::handle);
            Attributes attr = terminal.enterRawMode();
            try {
                keys = new KeyMap<>();
                bindKeys(keys);

                display.init(!noInit);
                if (!noKeypad) {
                    terminal.puts(Capability.keypad_xmit);
                }

                options.putAll(OPTION_KEYS);

                Operation op;
                boolean forward = true;
                terminal.writer().flush();
                display(false);
                do {
                    checkInterrupted();
                    size.copy(terminal.getSize());
                    window = size.getRows() - 1;
                    halfWindow = window / 2;
                    op = null;
                    //
                    // Option edition
                    //
                    if (buffer.length() > 0 && buffer.charAt(0) == '-') {
                        int c = terminal.reader().read();
                        message = null;
                        if (buffer.length() == 1) {
                            buffer.append((char) c);
                            if (c != '-') {
                                op = options.get(buffer.toString());
                                if (op == null) {
                                    message = "There is no " + printable(buffer.toString()) + " option";
                                    buffer.setLength(0);
                                }
                            }
                        } else if (c == '\r') {
                            op = options.get(buffer.toString());
                            if (op == null) {
                                message = "There is no " + printable(buffer.toString()) + " option";
                                buffer.setLength(0);
                            }
                        } else {
                            buffer.append((char) c);
                            Map<String, Operation> matching = new HashMap<>();
                            for (Map.Entry<String, Operation> entry : options.entrySet()) {
                                if (entry.getKey().startsWith(buffer.toString())) {
                                    matching.put(entry.getKey(), entry.getValue());
                                }
                            }
                            switch (matching.size()) {
                                case 0:
                                    buffer.setLength(0);
                                    break;
                                case 1:
                                    buffer.setLength(0);
                                    buffer.append(matching.keySet().iterator().next());
                                    break;
                            }
                        }
                    }
                    //
                    // Pattern edition
                    //
                    else if (buffer.length() > 0 && (buffer.charAt(0) == '/' || buffer.charAt(0) == '?' || buffer.charAt(0) == '&')) {
                        forward = search();
                    }
                    //
                    // Command reading
                    //
                    else {
                        Operation obj = bindingReader.readBinding(keys, null, false);
                        if (obj == null && bindingReader.getCurrentBuffer().isEmpty() && inputAtEof()) {
                            //No input device left; there is nothing to page through any more.
                            op = Operation.EXIT;
                            continue;
                        }
                        if (obj == Operation.CHAR) {
                            char c = bindingReader.getLastBinding().charAt(0);
                            // Enter option mode or pattern edit mode
                            if (c == '-' || c == '/' || c == '?' || c == '&') {
                                buffer.setLength(0);
                            }
                            buffer.append(c);
                        } else if (obj == Operation.BACKSPACE) {
                            if (buffer.length() > 0) {
                                buffer.deleteCharAt(buffer.length() - 1);
                            }
                        } else {
                            op = obj;
                        }
                    }
                    if (op != null) {
                        String prevMeesage = message;
                        message = null;
                        switch (op) {
                            case FORWARD_ONE_LINE:
                                if (prevMeesage == null) moveForward(getStrictPositiveNumberInBuffer(1));
                                break;
                            case BACKWARD_ONE_LINE:
                                moveBackward(getStrictPositiveNumberInBuffer(1));
                                break;
                            case FORWARD_ONE_WINDOW_OR_LINES:
                                moveForward(getStrictPositiveNumberInBuffer(window));
                                break;
                            case FORWARD_ONE_WINDOW_AND_SET:
                                window = getStrictPositiveNumberInBuffer(window);
                                moveForward(window);
                                break;
                            case FORWARD_ONE_WINDOW_NO_STOP:
                                moveForward(window);
                                // TODO: handle no stop
                                break;
                            case FORWARD_HALF_WINDOW_AND_SET:
                                halfWindow = getStrictPositiveNumberInBuffer(halfWindow);
                                moveForward(halfWindow);
                                break;
                            case BACKWARD_ONE_WINDOW_AND_SET:
                                window = getStrictPositiveNumberInBuffer(window);
                                moveBackward(window);
                                break;
                            case BACKWARD_ONE_WINDOW_OR_LINES:
                                moveBackward(getStrictPositiveNumberInBuffer(window));
                                break;
                            case BACKWARD_HALF_WINDOW_AND_SET:
                                halfWindow = getStrictPositiveNumberInBuffer(halfWindow);
                                moveBackward(halfWindow);
                                break;
                            case GO_TO_FIRST_LINE_OR_N:
                                moveTo(getStrictPositiveNumberInBuffer(1) - 1);
                                break;
                            case GO_TO_LAST_LINE_OR_N:
                                int lineNum = getStrictPositiveNumberInBuffer(0) - 1;
                                if (lineNum < 0) {
                                    moveForward(Integer.MAX_VALUE);
                                } else {
                                    moveTo(lineNum);
                                }
                                break;
                            case HOME:
                                moveTo(0);
                                break;
                            case END:
                                moveForward(Integer.MAX_VALUE);
                                break;
                            case LEFT_ONE_HALF_SCREEN:
                                firstColumnToDisplay = Math.max(0, firstColumnToDisplay - size.getColumns() / 2);
                                break;
                            case RIGHT_ONE_HALF_SCREEN:
                                firstColumnToDisplay += size.getColumns() / 2;
                                break;
                            case RIGHT_FRIST_COLUMN:
                                firstColumnToDisplay += Integer.MAX_VALUE;
                                break;
                            case LEFT_FRIST_COLUMN:
                                firstColumnToDisplay = 0;
                                break;
                            case REPEAT_SEARCH_BACKWARD_SPAN_FILES:
                                moveToMatch(!forward, true);
                                break;
                            case REPEAT_SEARCH_BACKWARD:
                                moveToMatch(!forward, false);
                                break;
                            case REPEAT_SEARCH_FORWARD_SPAN_FILES:
                                moveToMatch(forward, true);
                                break;
                            case REPEAT_SEARCH_FORWARD:
                                moveToMatch(forward, false);
                                break;
                            case UNDO_SEARCH:
                                pattern = null;
                                break;
                            case OPT_PRINT_LINES:
                                buffer.setLength(0);
                                printLineNumbers = !printLineNumbers;
                                //message = printLineNumbers ? "Constantly display line numbers" : "Don't use line numbers";
                                break;
                            case OPT_QUIET:
                                buffer.setLength(0);
                                quiet = !quiet;
                                veryQuiet = false;
                                message = quiet ? "Ring the bell for errors but not at eof/bof" : "Ring the bell for errors AND at eof/bof";
                                break;
                            case OPT_VERY_QUIET:
                                buffer.setLength(0);
                                veryQuiet = !veryQuiet;
                                quiet = false;
                                message = veryQuiet ? "Never ring the bell" : "Ring the bell for errors AND at eof/bof";
                                break;
                            case OPT_CHOP_LONG_LINES:
                                buffer.setLength(0);
                                offsetInLine = 0;
                                chopLongLines = !chopLongLines;
                                message = chopLongLines ? "Chop long lines" : "Fold long lines";
                                display.clear();
                                break;
                            case OPT_IGNORE_CASE_COND:
                                ignoreCaseCond = !ignoreCaseCond;
                                ignoreCaseAlways = false;
                                message = ignoreCaseCond ? "Ignore case in searches" : "Case is significant in searches";
                                break;
                            case OPT_IGNORE_CASE_ALWAYS:
                                ignoreCaseAlways = !ignoreCaseAlways;
                                ignoreCaseCond = false;
                                message = ignoreCaseAlways ? "Ignore case in searches and in patterns" : "Case is significant in searches";
                                break;
                            case OPT_SYNTAX_HIGHLIGHT:
                                highlight = !highlight;
                                message = "Highlight " + (highlight ? "enabled" : "disabled");
                                break;
                            case ADD_FILE:
                                addFile();
                                break;
                            case NEXT_FILE:
                                int next = getStrictPositiveNumberInBuffer(1);
                                if (sourceIdx < sources.size() - next) {
                                    SavedSourcePositions ssp = new SavedSourcePositions();
                                    sourceIdx += next;
                                    String newSource = sources.get(sourceIdx).getName();
                                    try {
                                        openSource();
                                    } catch (FileNotFoundException exp) {
                                        ssp.restore(newSource);
                                    }
                                } else {
                                    message = "No next file";
                                }
                                break;
                            case PREV_FILE:
                                int prev = getStrictPositiveNumberInBuffer(1);
                                if (sourceIdx > prev) {
                                    SavedSourcePositions ssp = new SavedSourcePositions(-1);
                                    sourceIdx -= prev;
                                    String newSource = sources.get(sourceIdx).getName();
                                    try {
                                        openSource();
                                    } catch (FileNotFoundException exp) {
                                        ssp.restore(newSource);
                                    }
                                } else {
                                    message = "No previous file";
                                }
                                break;
                            case GOTO_FILE:
                                int tofile = getStrictPositiveNumberInBuffer(1);
                                if (tofile < sources.size()) {
                                    SavedSourcePositions ssp = new SavedSourcePositions(tofile < sourceIdx ? -1 : 0);
                                    sourceIdx = tofile;
                                    String newSource = sources.get(sourceIdx).getName();
                                    try {
                                        openSource();
                                    } catch (FileNotFoundException exp) {
                                        ssp.restore(newSource);
                                    }
                                } else {
                                    message = "No such file";
                                }
                                break;
                            case INFO_FILE:
                                message = MESSAGE_FILE_INFO;
                                break;
                            case DELETE_FILE:
                                if (sources.size() > 2) {
                                    sources.remove(sourceIdx);
                                    if (sourceIdx >= sources.size()) {
                                        sourceIdx = sources.size() - 1;
                                    }
                                    openSource();
                                }
                                break;
                            case REPAINT:
                                size.copy(terminal.getSize());
                                display(false);
                                break;
                            case REPAINT_AND_DISCARD:
                                message = null;
                                size.copy(terminal.getSize());
                                display(false);
                                break;
                            case HELP:
                                help();
                                break;
                            case EXIT:
                                continue;
                        }
                        buffer.setLength(0);
                    }
                    if (quitAtFirstEof && nbEof > 0 || quitAtSecondEof && nbEof > 1) {
                        if (sourceIdx < sources.size() - 1) {
                            sourceIdx++;
                            openSource();
                        } else {
                            op = Operation.EXIT;
                            continue;
                        }
                    }
                    display(false);
                } while (op != Operation.EXIT);
            } catch (InterruptedException ie) {
                // Do nothing
            } finally {
                terminal.setAttributes(attr);
                if (prevHandler != null) {
                    terminal.handle(Terminal.Signal.WINCH, prevHandler);
                }
                display.exit();
                if (!noKeypad) {
                    terminal.puts(Capability.keypad_local);
                }
                terminal.writer().flush();
            }
        } finally {
            releaseBuffer();
            titleLines = 0;
            titles = null;
            if (reader != null) {
                reader.close();
            }
            patternHistory.persist();
        }
    }

    private class LineEditor {
        private final int begPos;

        public LineEditor(int begPos) {
            this.begPos = begPos;
        }

        public int editBuffer(Operation op, int curPos) {
            switch (op) {
                case INSERT:
                    buffer.insert(curPos++, bindingReader.getLastBinding());
                    break;
                case BACKSPACE:
                    if (curPos > begPos - 1) {
                        buffer.deleteCharAt(--curPos);
                    }
                    break;
                case NEXT_WORD:
                    int newPos = buffer.length();
                    for (int i = curPos; i < buffer.length(); i++) {
                        if (buffer.charAt(i) == ' ') {
                            newPos = i + 1;
                            break;
                        }
                    }
                    curPos = newPos;
                    break;
                case PREV_WORD:
                    newPos = begPos;
                    for (int i = curPos - 2; i > begPos; i--) {
                        if (buffer.charAt(i) == ' ') {
                            newPos = i + 1;
                            break;
                        }
                    }
                    curPos = newPos;
                    break;
                case HOME:
                    curPos = begPos;
                    break;
                case END:
                    curPos = buffer.length();
                    break;
                case DELETE:
                    if (curPos >= begPos && curPos < buffer.length()) {
                        buffer.deleteCharAt(curPos);
                    }
                    break;
                case DELETE_WORD:
                    while (true) {
                        if (curPos < buffer.length() && buffer.charAt(curPos) != ' ') {
                            buffer.deleteCharAt(curPos);
                        } else {
                            break;
                        }
                    }
                    while (true) {
                        if (curPos - 1 >= begPos) {
                            if (buffer.charAt(curPos - 1) != ' ') {
                                buffer.deleteCharAt(--curPos);
                            } else {
                                buffer.deleteCharAt(--curPos);
                                break;
                            }
                        } else {
                            break;
                        }
                    }
                    break;
                case DELETE_LINE:
                    buffer.setLength(begPos);
                    curPos = 1;
                    break;
                case LEFT:
                    if (curPos > begPos) {
                        curPos--;
                    }
                    break;
                case RIGHT:
                    if (curPos < buffer.length()) {
                        curPos++;
                    }
                    break;
            }
            return curPos;
        }
    }

    private class SavedSourcePositions {
        int saveSourceIdx;
        int saveFirstLineToDisplay;
        int saveFirstColumnToDisplay;
        int saveOffsetInLine;
        List<String> savelines = new ArrayList<>();
        int saveTotalLines = 0;
        int saveTitleLines = 0;
        int saveFirstLineInMemory = 0;
        int saveHighWaterLines = 0;
        AttributedString[] saveTitles = null;
        boolean saveMatchedAsc;
        int saveMatchedIndex;
        String savePattern;
        ArrayList<Integer> saveMatchedLines = new ArrayList<>();

        boolean savePrintLineNumbers;

        public SavedSourcePositions() {
            this(0);
        }

        public SavedSourcePositions(int dec) {
            saveSourceIdx = sourceIdx + dec;
            saveFirstLineToDisplay = firstLineToDisplay;
            saveFirstColumnToDisplay = firstColumnToDisplay;
            saveOffsetInLine = offsetInLine;
            saveFirstLineInMemory = firstLineInMemory;
            saveHighWaterLines = highWaterLines;
            savePrintLineNumbers = printLineNumbers;
            saveTitles = titles;
            saveTotalLines = totalLines;
            saveTitleLines = titleLines;
            savePattern = pattern;
            saveMatchedAsc = matchedAsc;
            saveMatchedIndex = matchedIndex;
            saveMatchedLines.clear();
            saveMatchedLines.addAll(matchedLines);
            savelines.clear();
            savelines.addAll(lines);
            clearBuffer();
            resetView();
            printLineNumbers = false;
            titleLines = 0;
            titles = new AttributedString[0];
            resetMatches();
        }

        public void restore(String failingSource) throws IOException {
            sourceIdx = saveSourceIdx;
            openSource();
            firstLineToDisplay = saveFirstLineToDisplay;
            firstColumnToDisplay = saveFirstColumnToDisplay;
            offsetInLine = saveOffsetInLine;
            printLineNumbers = savePrintLineNumbers;
            titles = saveTitles;
            totalLines = saveTotalLines;
            titleLines = saveTitleLines;
            pattern = savePattern;
            matchedAsc = saveMatchedAsc;
            matchedIndex = saveMatchedIndex;
            matchedLines.clear();
            matchedLines.addAll(saveMatchedLines);
            setBuffer(savelines, saveFirstLineInMemory);
            highWaterLines = saveHighWaterLines;
            if (failingSource != null) {
                message = failingSource + " not found!";
            }
        }
    }

    private void addSource(String file) throws IOException {
        if (file.contains("*") || file.contains("?")) {
            for (Path p : Commands.findFiles(currentDir, file)) {
                sources.add(new URLSource(p.toUri().toURL(), p.toString()));
            }
        } else {
            sources.add(new URLSource(currentDir.resolve(file).toUri().toURL(), file));
        }
        sourceIdx = sources.size() - 1;
    }

    private void addFile() throws IOException, InterruptedException {
        KeyMap<Operation> fileKeyMap = new KeyMap<>();
        fileKeyMap.setUnicode(Operation.INSERT);
        for (char i = 32; i < 256; i++) {
            fileKeyMap.bind(Operation.INSERT, Character.toString(i));
        }
        fileKeyMap.bind(Operation.RIGHT, key(terminal, Capability.key_right), alt('l'));
        fileKeyMap.bind(Operation.LEFT, key(terminal, Capability.key_left), alt('h'));
        fileKeyMap.bind(Operation.HOME, key(terminal, Capability.key_home), alt('0'));
        fileKeyMap.bind(Operation.END, key(terminal, Capability.key_end), alt('$'));
        fileKeyMap.bind(Operation.BACKSPACE, del());
        fileKeyMap.bind(Operation.DELETE, alt('x'));
        fileKeyMap.bind(Operation.DELETE_WORD, alt('X'));
        fileKeyMap.bind(Operation.DELETE_LINE, ctrl('U'));
        fileKeyMap.bind(Operation.ACCEPT, "\r");

        SavedSourcePositions ssp = new SavedSourcePositions();
        message = null;
        buffer.append("Examine: ");
        int curPos = buffer.length();
        final int begPos = curPos;
        display(false, curPos);
        LineEditor lineEditor = new LineEditor(begPos);
        while (true) {
            checkInterrupted();
            Operation op = bindingReader.readBinding(fileKeyMap);
            if (op == null) {
                //End of input while editing the file name: cancel the prompt.
                buffer.setLength(0);
                return;
            }
            if (op == Operation.ACCEPT) {
                String name = buffer.substring(begPos);
                addSource(name);
                try {
                    openSource();
                } catch (Exception exp) {
                    ssp.restore(name);
                }
                return;
            } else if (op != null) {
                curPos = lineEditor.editBuffer(op, curPos);
            }
            if (curPos > begPos) {
                display(false, curPos);
            } else {
                buffer.setLength(0);
                return;
            }
        }
    }

    private boolean search() throws IOException, InterruptedException {
        KeyMap<Operation> searchKeyMap = new KeyMap<>();
        searchKeyMap.setUnicode(Operation.INSERT);
        for (char i = 32; i < 256; i++) {
            searchKeyMap.bind(Operation.INSERT, Character.toString(i));
        }
        searchKeyMap.bind(Operation.RIGHT, key(terminal, Capability.key_right), alt('l'));
        searchKeyMap.bind(Operation.LEFT, key(terminal, Capability.key_left), alt('h'));
        searchKeyMap.bind(Operation.NEXT_WORD, alt('w'));
        searchKeyMap.bind(Operation.PREV_WORD, alt('b'));
        searchKeyMap.bind(Operation.HOME, key(terminal, Capability.key_home), alt('0'));
        searchKeyMap.bind(Operation.END, key(terminal, Capability.key_end), alt('$'));
        searchKeyMap.bind(Operation.BACKSPACE, del(), "\b");
        searchKeyMap.bind(Operation.DELETE, alt('x'));
        searchKeyMap.bind(Operation.DELETE_WORD, alt('X'));
        searchKeyMap.bind(Operation.DELETE_LINE, ctrl('U'));
        searchKeyMap.bind(Operation.UP, key(terminal, Capability.key_up), alt('k'));
        searchKeyMap.bind(Operation.DOWN, key(terminal, Capability.key_down), alt('j'));
        searchKeyMap.bind(Operation.ACCEPT, "\r");


        boolean forward = true;
        message = null;
        int curPos = buffer.length();
        final int begPos = curPos;
        final char type = buffer.charAt(0);
        String currentBuffer = buffer.toString();
        LineEditor lineEditor = new LineEditor(begPos);
        while (true) {
            checkInterrupted();
            Operation op = bindingReader.readBinding(searchKeyMap);
            if (op == null) {
                //End of input while editing the pattern.
                buffer.setLength(0);
                return forward;
            }
            switch (op) {
                case UP:
                    buffer.setLength(0);
                    buffer.append(type);
                    buffer.append(patternHistory.up(currentBuffer.substring(1)));
                    curPos = buffer.length();
                    break;
                case DOWN:
                    buffer.setLength(0);
                    buffer.append(type);
                    buffer.append(patternHistory.down(currentBuffer.substring(1)));
                    curPos = buffer.length();
                    break;
                case ACCEPT:
                    try {
                        String _pattern = buffer.length() == 0 ? "" : buffer.substring(1);
                        if (type == '&') {
                            displayPattern = _pattern.length() > 0 ? _pattern : null;
                            getPattern(true);
                        } else {
                            matchedLines.clear();
                            matchedIndex = -1;
                            pattern = _pattern;
                            getPattern();
                            if (type == '/') {
                                matchedAsc = true;
                                moveToNextMatch();
                            } else {
                                matchedAsc = false;
                                //The backward scan starts from the very end of the source, so remember
                                //the old view: a failed '?' used to leave the pager parked past EOF,
                                //showing nothing but ~ rows until the next command (less keeps the
                                //original position).
                                int savedTop = firstLineToDisplay;
                                int savedOffset = offsetInLine;
                                int savedMatches = matchedIndex;
                                if (totalLines - viewTop() <= size.getRows()) {
                                    showLineAtTop(totalLines);
                                } else {
                                    moveForward(size.getRows() - 1);
                                }
                                moveToPreviousMatch();
                                if (matchedIndex == savedMatches) {
                                    firstLineToDisplay = savedTop;
                                    offsetInLine = savedOffset;
                                }
                                forward = false;
                            }
                        }
                        patternHistory.add(_pattern);
                        buffer.setLength(0);
                    } catch (PatternSyntaxException e) {
                        String str = e.getMessage();
                        if (str.indexOf('\n') > 0) {
                            str = str.substring(0, str.indexOf('\n'));
                        }
                        if (type == '&') {
                            displayPattern = null;
                        } else {
                            pattern = null;
                        }
                        buffer.setLength(0);
                        message = "Invalid pattern: " + str + " (Press a key)";
                        display(false);
                        terminal.reader().read();
                        message = null;
                    }
                    return forward;
                default:
                    curPos = lineEditor.editBuffer(op, curPos);
                    currentBuffer = buffer.toString();
            }

            display.updateBuff(buffer.toString(), curPos);

            if (curPos < begPos) {
                buffer.setLength(0);
                return forward;
            }
        }
    }

    private void help() throws IOException {
        SavedSourcePositions ssp = new SavedSourcePositions();
        printLineNumbers = false;
        sourceIdx = 0;
        try {
            openSource();
            display(false);
            Operation op;
            do {
                checkInterrupted();
                op = bindingReader.readBinding(keys, null, false);
                if (op == null && bindingReader.getCurrentBuffer().isEmpty() && inputAtEof()) {
                    break;      // no input device left
                }
                if (op != null) {
                    switch (op) {
                        case FORWARD_ONE_WINDOW_OR_LINES:
                            moveForward(getStrictPositiveNumberInBuffer(window));
                            break;
                        case BACKWARD_ONE_WINDOW_OR_LINES:
                            moveBackward(getStrictPositiveNumberInBuffer(window));
                            break;
                    }
                }
                display(false);
            } while (op != Operation.EXIT);
        } catch (IOException | InterruptedException exp) {
            // Do nothing
        } finally {
            ssp.restore(null);
        }
    }

    protected void openSource() throws IOException {
        boolean wasOpen = false;
        if (reader != null) {
            reader.close();
            wasOpen = true;
        }
        boolean open;
        boolean displayMessage = false;
        do {
            Source source = sources.get(sourceIdx);
            try {
                boolean isText = source instanceof TextSource;
                InputStream in = isText ? null : source.read();
                //A fresh stream per read() (URL/Path/Resource sources) can always be re-read, while
                //an InputStreamSource rewinds its stream only when it supports marks (a
                //ByteArrayInputStream does, a pipe does not); a TextSource always can. Window pruning
                //is enabled only when re-reading is possible.
                rewindable = isText || !(source instanceof Source.InputStreamSource) || in.markSupported();
                if (sources.size() == 2 || sourceIdx == 0) {
                    message = source.getName();
                } else {
                    message = source.getName() + " (file " + sourceIdx + " of "
                            + (sources.size() - 1) + ")";
                }
                reader = isText
                        ? new BufferedReader(new StringReader(((TextSource) source).text))
                        : new BufferedReader(new InputStreamReader(new InterruptibleInputStream(in)));
                //Reset the buffer to the new source. These resets live here rather than only in
                //SavedSourcePositions: :d and the quit-at-eof file switch call openSource()
                //directly and used to keep displaying the previous file's cached lines.
                clearBuffer();
                resetView();
                //Per-source state: the eof counter and the widest-line clamp must not carry over.
                nbEof = 0;
                globalLineWidth = 0;
                display.clear();
                if (sourceIdx == 0) {
                    syntaxHighlighter = SyntaxHighlighter.build(syntaxFiles, null, "none");
                } else {
                    syntaxHighlighter = SyntaxHighlighter.build(syntaxFiles, source.getName(), syntaxName, nanorcIgnoreErrors);
                }
                open = true;
                if (displayMessage) {
                    AttributedStringBuilder asb = new AttributedStringBuilder();
                    asb.style(AttributedStyle.INVERSE);
                    asb.append(source.getName() + " (press RETURN)");
                    asb.toAttributedString().println(terminal);
                    terminal.writer().flush();
                    terminal.reader().read();
                }
            } catch (FileNotFoundException exp) {
                sources.remove(sourceIdx);
                if (sourceIdx > sources.size() - 1) {
                    sourceIdx = sources.size() - 1;
                }
                if (wasOpen) {
                    throw exp;
                } else {
                    AttributedStringBuilder asb = new AttributedStringBuilder();
                    asb.append(source.getName() + " not found!");
                    asb.toAttributedString().println(terminal);
                    terminal.writer().flush();
                    open = false;
                    displayMessage = true;
                }
            }
        } while (!open && sourceIdx > 0);
        if (!open) {
            throw new FileNotFoundException();
        }
    }

    void moveTo(int lineNum) throws IOException {
        AttributedString line = getScanLine(lineNum);
        if (line != null) {
            display.clear();
            //No openSource() here: getLine() already re-reads the source when the target is above
            //the retained window, and resetting the buffer at this point would drop every line
            //between the target and the current position.
            showLineAtTop(lineNum);
            offsetInLine = 0;
        } else {
            message = "Cannot seek to line number " + (lineNum + 1);
        }
    }

    private void moveToNextMatch() throws IOException {
        moveToMatch(true, false);
    }

    private void moveToPreviousMatch() throws IOException {
        moveToMatch(false, false);
    }

    /**
     * Repeat the current search in one direction. Cached matches are replayed first, then the buffer
     * is scanned; in span-files mode an exhausted source moves on to the next (or previous) file and
     * continues there. Both directions share this body - they only differ by the step sign, which way
     * the match list is walked, and how a backward scan crosses the retained window.
     */
    private void moveToMatch(boolean forward, boolean spanFiles) throws IOException {
        Pattern compiled = getPattern();
        Pattern dpCompiled = getPattern(true);
        if (compiled != null) {
            if (replayMatch(forward)) return;
            if (forward ? scanForward(compiled, dpCompiled) : scanBackward(compiled, dpCompiled)) return;
        }
        if (!spanFiles) {
            message = "Pattern not found";
            return;
        }
        boolean hasNeighbour = forward ? sourceIdx < sources.size() - 1 : sourceIdx > 1;
        if (!hasNeighbour) {
            message = "Pattern not found";
            return;
        }
        SavedSourcePositions ssp = new SavedSourcePositions(forward ? 0 : -1);
        sourceIdx += forward ? 1 : -1;
        String newSource = sources.get(sourceIdx).getName();
        try {
            openSource();
            if (!forward) {
                //Enter the new file from its end: a seek to Integer.MAX_VALUE cannot do it (no such
                //line, so it would leave the view at the top and scan the wrong way).
                readToEnd();
                showLineAtTop(totalLines);
            }
            moveToMatch(forward, true);
        } catch (FileNotFoundException exp) {
            ssp.restore(newSource);
        }
    }

    /** Replay an already known match; false when the cached list has nothing left in this direction. */
    private boolean replayMatch(boolean forward) {
        if (matchedAsc != forward) {
            if (matchedIndex <= 0) return false;
            display.clear();
            --matchedIndex;
        } else {
            if (matchedLines.size() <= matchedIndex + 1) return false;
            ++matchedIndex;
        }
        setViewTop(matchedLines.get(matchedIndex));
        return true;
    }

    /** Scan towards the end of the source; true when a match was found and shown. */
    private boolean scanForward(Pattern compiled, Pattern dpCompiled) throws IOException {
        for (int lineNumber = viewTop() + 1; ; lineNumber++) {
            AttributedString line = getScanLine(lineNumber);
            if (line == null) return false;
            if (!toBeDisplayed(line, dpCompiled)) continue;
            if (matcher.find(compiled, line)) {
                showMatch(lineNumber);
                return true;
            }
        }
    }

    /**
     * Scan towards the start of the source; true when a match was found and shown. The retained
     * window is scanned downwards first (cheap); if it holds no match, the source is re-read once,
     * forwards, and the last match at or above the old window start wins. Walking the lines above
     * the window downwards instead cost one full re-read per window: measured 1.6s for a 32767 line
     * source, because every step dropped the window again and rewound the source.
     */
    private boolean scanBackward(Pattern compiled, Pattern dpCompiled) throws IOException {
        int from = viewTop() - 1;
        int floor = Math.max(firstLineInMemory, titleLines);
        for (int lineNumber = from; lineNumber >= floor; lineNumber--) {
            AttributedString line = getScanLine(lineNumber);
            if (line == null) break;
            if (!toBeDisplayed(line, dpCompiled)) continue;
            if (matcher.find(compiled, line)) {
                showMatch(lineNumber);
                return true;
            }
        }
        if (floor <= titleLines || !rewindable) return false;
        rewind();
        int found = -1;
        for (int lineNumber = titleLines; lineNumber <= from; lineNumber++) {
            AttributedString line = getScanLine(lineNumber);
            if (line == null) break;
            if (!toBeDisplayed(line, dpCompiled)) continue;
            if (matcher.find(compiled, line)) found = lineNumber;
        }
        if (found < 0) return false;
        showMatch(found);
        return true;
    }

    /** Show a found line at the first content row and remember it for the next repeat. */
    private void showMatch(int lineNumber) {
        display.clear();
        showLineAtTop(lineNumber);
        ++matchedIndex;
        matchedLines.add(firstLineToDisplay);
    }

    private String printable(String s) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (c == ESCAPE) {
                sb.append("ESC");
            } else if (c < 32) {
                sb.append('^').append((char) (c + '@'));
            } else if (c < 128) {
                sb.append(c);
            } else {
                sb.append('\\').append(String.format("%03o", (int) c));
            }
        }
        return sb.toString();
    }

    private int titleLines = 0;
    private AttributedString[] titles = new AttributedString[titleLines];

    public void setTitleLines(int titleLines) {
        this.titleLines = titleLines;
        titles = new AttributedString[titleLines];
    }

    void moveForward(int lines) throws IOException {
        Pattern dpCompiled = getPattern(true);
        int width = size.getColumns() - (printLineNumbers ? numWidth + 1 : 0);
        if (width < 1) width = 1;
        int height = size.getRows();
        boolean doOffsets = firstColumnToDisplay == 0 && !chopLongLines;
        if (lines == Integer.MAX_VALUE) {
            //Seek to the last screen. moveTo(Integer.MAX_VALUE) cannot do it: there is no such line,
            //so getLine() fails and the position is left untouched; the old code then reset the
            //position to height-1 (near the top) and let the loop below walk forward one line per
            //iteration until the screen bottom passed EOF (~0.45s over 20k lines, measured on a real
            //console). Read to the end of the source first, then back up one screen.
            //NB: do not loop on getLine(totalLines) here - with title lines it can keep returning a
            //title line instead of null and never terminate.
            readToEnd();
            firstLineToDisplay = Math.max(0, totalLines - 1);
            for (int l = 0; l < height - 1; l++) {
                firstLineToDisplay =
                        prevLine2display(firstLineToDisplay, dpCompiled).getU();
            }
        }
        if (titleLines > 0 && lines > titleLines && lines != Integer.MAX_VALUE) lines -= titleLines;
        if (lines >= size.getRows() - 1) {
            display.clear();
        }
        while (--lines >= 0) {
            int lastLineToDisplay = firstLineToDisplay;
            if (!doOffsets) {
                for (int l = 0; l < height - 1; l++) {
                    lastLineToDisplay = nextLine2display(lastLineToDisplay, dpCompiled).getU();
                }
            } else {
                int off = offsetInLine;
                for (int l = 0; l < height - 1; l++) {
                    Pair<Integer, AttributedString> nextLine = nextLine2display(lastLineToDisplay, dpCompiled);
                    AttributedString line = nextLine.getV();
                    if (line == null) {
                        lastLineToDisplay = nextLine.getU();
                        break;
                    }
                    if (line.columnLength() > off + width) {
                        off += width;
                    } else {
                        off = 0;
                        lastLineToDisplay = nextLine.getU();
                    }
                }
            }
            if (getLine(lastLineToDisplay) == null) {
                eof();
                return;
            }
            Pair<Integer, AttributedString> nextLine = nextLine2display(firstLineToDisplay, dpCompiled);
            AttributedString line = nextLine.getV();
            if (doOffsets && line.columnLength() > width + offsetInLine) {
                offsetInLine += width;
            } else {
                offsetInLine = 0;
                firstLineToDisplay = nextLine.getU();
            }
        }
    }

    void moveBackward(int lines) throws IOException {
        Pattern dpCompiled = getPattern(true);
        int width = size.getColumns() - (printLineNumbers ? numWidth + 1 : 0);
        if (width < 1) width = 1;       //same guard as display(): length % width below must not divide by zero
        //if (titleLines > 0 && lines > titleLines) lines -= titleLines;
        if (lines >= size.getRows() - 1) {
            display.clear();
        }
        while (--lines >= 0) {
            if (offsetInLine > 0) {
                offsetInLine = Math.max(0, offsetInLine - width);
            //There are always lines above the top of the screen until it is the first line itself
            //(title lines are kept in titles[] even after the window has been pruned).
            } else if (firstLineToDisplay > 0) {
                Pair<Integer, AttributedString> prevLine = prevLine2display(firstLineToDisplay, dpCompiled);
                firstLineToDisplay = prevLine.getU();
                AttributedString line = prevLine.getV();
                if (line != null && firstColumnToDisplay == 0 && !chopLongLines) {
                    int length = line.columnLength();
                    offsetInLine = length - length % width;
                }
            } else {
                bof();
                return;
            }
        }
    }

    private void eof() {
        nbEof++;
        if (sourceIdx > 0 && sourceIdx < sources.size() - 1) {
            message = "(END) - Next: " + sources.get(sourceIdx + 1).getName();
        } else {
            message = "(END)";
        }
        if (!quiet && !veryQuiet && !quitAtFirstEof && !quitAtSecondEof) {
            terminal.puts(Capability.bell);
            terminal.writer().flush();
        }
    }

    private void bof() {
        if (!quiet && !veryQuiet) {
            terminal.puts(Capability.bell);
            terminal.writer().flush();
        }
    }

    int getStrictPositiveNumberInBuffer(int def) {
        try {
            int n = Integer.parseInt(buffer.toString());
            return (n > 0) ? n : def;
        } catch (NumberFormatException e) {
            return def;
        } finally {
            buffer.setLength(0);
        }
    }

    private Pair<Integer, AttributedString> nextLine2display(int line, Pattern dpCompiled) throws IOException {
        AttributedString curLine;
        do {
            curLine = getLine(line++);
        } while (!toBeDisplayed(curLine, dpCompiled));
        return new Pair<>(line, curLine);
    }

    private Pair<Integer, AttributedString> prevLine2display(int line, Pattern dpCompiled) throws IOException {
        AttributedString curLine;
        do {
            curLine = getLine(line--);
        } while (line > 0 && !toBeDisplayed(curLine, dpCompiled));
        if (line == 0 && !toBeDisplayed(curLine, dpCompiled)) {
            curLine = null;
        }
        return new Pair<>(line, curLine);
    }

    private boolean toBeDisplayed(AttributedString curLine, Pattern dpCompiled) {
        return curLine == null || dpCompiled == null || sourceIdx == 0 || displayMatcher.find(dpCompiled, curLine);
    }

    synchronized boolean display(boolean oneScreen) throws IOException {
        return display(oneScreen, null);
    }

    //True when no further input can arrive at all (input closed or exhausted). readBinding() with
    //block=false cannot tell that apart from "a partial key sequence is buffered" on its own, and
    //without this check the main loop spins: it keeps getting null back while there is nothing
    //left to block on. The probe uses a 1ms budget, never 0: peek(0) waits forever (see display()).
    boolean inputAtEof() {
        try {
            //jline's NonBlockingReader contract: -1 is end of input, READ_EXPIRED (-2) is "nothing yet".
            //At real EOF the character is already latched, so this returns -1 without waiting.
            return terminal.reader().peek(1) == -1;
        } catch (Exception e) {
            //A closed reader throws here. The MSYS/WSL/Cygwin paths deliberately avoid peek()
            //elsewhere in this class, so stay conservative there instead of leaving the pager early.
            return System.getenv("IS_WSL") == null && !OSUtils.IS_MSYSTEM && !OSUtils.IS_CYGWIN;
        }
    }

    public int numWidth = 4;
    public int padding = 0;
    private String paddingSpaces = "";
    private int globalLineWidth = 0;
    private int rows = 0;
    private int cols = 0;
    final AttributedString sep = new AttributedString("|", AttributedStyle.DEFAULT.foreground(AttributedStyle.YELLOW));
    final AttributedStringBuilder msg = new AttributedStringBuilder(2048);

    synchronized boolean display(boolean oneScreen, Integer curPos) throws IOException {
        if (!oneScreen) {
            if (curPos == null && display.getPos() > 0 && buffer.length() > 0 && rows == size.getRows() && cols == size.getColumns()) {
                display.updateBuff(buffer.toString(), -1);
                return false;
            }
            //The repaint used to sit behind a blocking peek, which delayed every keystroke by the
            //whole 128ms timeout (measured: 141ms per repaint, of which only 4.5ms was painting).
            //Display diffs the screen, so repainting an unchanged state writes nothing and the
            //batching is not worth the latency.
            //Do not try to test for pending input with peek(0): jline's Timeout(0).elapsed() stays
            //false, so its wait loop calls wait(0) and never returns (verified on an idle reader).
        }
        rows = size.getRows();
        cols = size.getColumns();
        // Boundary check: ensure minimum size to prevent calculation errors
        if (rows < 1) rows = 1;
        if (cols < 1) cols = 1;
        int width = cols - (printLineNumbers ? numWidth + 1 : 0) - 1;
        if (width < 1) width = 1;
        int maxWidth = 0;
        AttributedStringBuilder asb = new AttributedStringBuilder();
        if (globalLineWidth > 0 && firstColumnToDisplay > globalLineWidth - width / 2) {
            firstColumnToDisplay = Math.max(0, globalLineWidth - width / 2);
        }
        List<AttributedString> newLines = new ArrayList<>();
        int inputLine = firstLineToDisplay;
        AttributedString curLine = null;
        Pattern compiled = getPattern();
        Pattern dpCompiled = getPattern(true);
        boolean fitOnOneScreen = false;
        boolean eof = false;
        if (highlight) {
            syntaxHighlighter.reset();
            for (int i = Math.max(0, inputLine - rows); i < inputLine; i++) {
                final AttributedString line = getLine(i);
                if (line != null) syntaxHighlighter.highlight(line);
                else break;
            }
        }
        int off = 0;
        if (padding > 0 && paddingSpaces.length() != padding) {
            paddingSpaces = String.join("", Collections.nCopies(padding, " "));
        }
        final String numberPad = numWidth > 0 ? String.join("", Collections.nCopies(numWidth, " ")) : "";

        for (int terminalLine = 0; terminalLine < rows - 1; terminalLine++) {
            if (curLine == null) {
                Pair<Integer, AttributedString> nextLine = nextLine2display(inputLine, dpCompiled);
                inputLine = nextLine.getU();
                curLine = nextLine.getV();
                if (curLine == null) {
                    if (oneScreen) {
                        fitOnOneScreen = true;
                        break;
                    }
                    eof = true;
                    curLine = new AttributedString("~");
                } else if (highlight) {
                    curLine = syntaxHighlighter.highlight(curLine);
                }
                if (compiled != null) {
                    curLine = curLine.styleMatches(compiled, AttributedStyle.DEFAULT.inverse());
                }
                if (printLineNumbers && padding > 0) {
                    curLine = curLine.columnSubSequence(padding, Integer.MAX_VALUE);
                }
                maxWidth = Math.max(maxWidth, curLine.columnLength());
            }
            AttributedString toDisplay;
            if (firstColumnToDisplay > 0 || chopLongLines) {
                off = firstColumnToDisplay;
                if (terminalLine == 0 && offsetInLine > 0) {
                    off = Math.max(offsetInLine, off);
                }
                if (padding > 0 && off > padding && !printLineNumbers) {
                    asb.setLength(0);
                    asb.append(paddingSpaces);
                    asb.append(curLine.columnSubSequence(off, off + width - padding));
                    toDisplay = asb.toAttributedString();
                } else {
                    toDisplay = curLine.columnSubSequence(off, off + width);
                }
                curLine = null;
            } else {
                if (terminalLine == 0 && offsetInLine > 0) {
                    curLine = curLine.columnSubSequence(offsetInLine, Integer.MAX_VALUE);
                }
                toDisplay = curLine.columnSubSequence(0, width);
                curLine = curLine.columnSubSequence(width, Integer.MAX_VALUE);
                if (curLine.length() == 0 && !chopLongLines && firstColumnToDisplay == 0) {
                    curLine = null;
                }
            }
            if (printLineNumbers && !eof) {
                asb.setLength(0);
                if (lineIndex == -1) {
                    asb.append(numberPad);
                } else {
                    //Same output as String.format("%<numWidth>d"), without the Formatter cost per row.
                    String num = Integer.toString(lineIndex);
                    for (int i = num.length(); i < numWidth; i++) asb.append(' ');
                    asb.append(num);
                }
                asb.append(sep).append(toDisplay);
                newLines.add(asb.toAttributedString());
            } else {
                newLines.add(toDisplay);
            }
        }
        if (oneScreen) {
            if (fitOnOneScreen && maxWidth <= width) {
                newLines.forEach(l -> l.println(terminal));
                terminal.writer().flush();
                return true;
            }
            return false;
        }
        globalLineWidth = Math.max(maxWidth, globalLineWidth);

        msg.setLength(0);
        if (MESSAGE_FILE_INFO.equals(message)) {
            Source source = sources.get(sourceIdx);
            Long allLines = source.lines();
            message = source.getName()
                    + (sources.size() > 2 ? " (file " + sourceIdx + " of " + (sources.size() - 1) + ")" : "")
                    + " lines " + (firstLineToDisplay + 1) + "-" + lineIndex + "/"
                    + (allLines != null ? allLines : Math.max(highWaterLines, totalLines))
                    + (eof ? " (END)" : "");
        }
        if (buffer.length() > 0) {
            msg.append(" ").append(buffer);
        } else if (bindingReader.getCurrentBuffer().length() > 0
                && terminal.reader().available() == 0) {
            msg.append(" ").append(printable(bindingReader.getCurrentBuffer()));
        } else if (message != null) {
            msg.style(AttributedStyle.INVERSE);
            msg.append(message);
            msg.style(AttributedStyle.INVERSE.inverseOff());
        } else if (displayPattern != null) {
            msg.append("&");
        } else {
            msg.append(":");
        }
        newLines.add(msg.toAttributedString());
        //NB: no display.clear() here. Clearing on every frame marks the display for a full
        //clear_screen + repaint (Display.clear only sets `reset`; the next update then repaints every
        //row), which measured ~4000 bytes per keystroke on a 100x40 screen even when one status line
        //changed, and it made every repaint a full one. The movements that really need a fresh screen
        //call display.clear() themselves (openSource, moveTo, showMatch, moveForward, moveBackward),
        //and in between, Display diffs against the screen it already painted.
        if (curPos == null) {
            display.update(newLines, -1);
        } else {
            display.update(newLines, size.cursorPos(size.getRows() - 1, curPos + 1));
        }
        return false;
    }

    private final PatternMatcher matcher = new PatternMatcher();
    private final PatternMatcher displayMatcher = new PatternMatcher();
    private final PatternCache searchPatterns = new PatternCache();
    private final PatternCache displayPatterns = new PatternCache();

    private Pattern getPattern() {
        return searchPatterns.get(pattern, ignoreCaseAlways, ignoreCaseCond);
    }

    private Pattern getPattern(boolean doDisplayPattern) {
        return doDisplayPattern
                ? displayPatterns.get(displayPattern, ignoreCaseAlways, ignoreCaseCond)
                : searchPatterns.get(pattern, ignoreCaseAlways, ignoreCaseCond);
    }

    /**
     * One compiled pattern kept per pattern string: display() and the move* methods ask for the same
     * regex on every call, and recompiling it per keystroke is pure waste. The ignore-case options are
     * part of the key because they can be toggled at runtime.
     */
    private static final class PatternCache {
        private String key;
        private Pattern compiled;

        //Synchronized: display() runs on the WINCH signal thread as well, and it asks this same cache
        //for the search pattern while a scan on the main thread may be updating it. Two plain fields
        //updated by two threads could hand back the wrong pattern for one frame.
        synchronized Pattern get(String source, boolean ignoreCaseAlways, boolean ignoreCaseCond) {
            if (source == null) return null;
            boolean insensitive = ignoreCaseAlways || ignoreCaseCond && source.toLowerCase().equals(source);
            String k = (insensitive ? "i" : "-") + source;
            if (!k.equals(key)) {
                key = k;
                compiled = Pattern.compile("(" + source + ")",
                        insensitive ? Pattern.CASE_INSENSITIVE | Pattern.UNICODE_CASE : 0);
            }
            return compiled;
        }
    }

    /** A pattern together with the Matcher reused for it: a scan used to allocate one per line. */
    private static final class PatternMatcher {
        private Pattern pattern;
        private Matcher matcher;

        boolean find(Pattern p, CharSequence text) {
            if (matcher == null || pattern != p) {
                pattern = p;
                matcher = p.matcher(text);
            } else {
                matcher.reset(text);
            }
            return matcher.find();
        }
    }

    int lineIndex;

    //Cut trailing whitespace without the regex, exactly as RTRIM.matcher(s).replaceAll("") did.
    //The class is \s = space, \t, \n, vertical tab, form feed and \r: testing `c <= ' '` instead also
    //cut the C0 controls the regex kept (ESC among them, i.e. a truncated escape at the end of a line).
    //Java's $ additionally matches before a final line terminator, and \u0085 (NEL), \u2028 and \u2029
    //count as terminators although \s does not match them - so the run trimmed is the one in front of
    //such a character, which itself stays.
    static String rtrim(String s) {
        int end = s.length();
        int stop = end;
        if (end > 0) {
            char last = s.charAt(end - 1);
            if (last == '\u0085' || last == '\u2028' || last == '\u2029') {
                stop = end - 1;
            }
        }
        int i = stop;
        while (i > 0) {
            char c = s.charAt(i - 1);
            if (c == ' ' || c == '\t' || c == '\n' || c == '\u000B' || c == '\f' || c == '\r') {
                --i;
            } else {
                break;
            }
        }
        if (i == end) return s;                              // nothing to trim
        if (stop == end) return s.substring(0, i);            // the plain case
        return i == stop ? s : s.substring(0, i) + s.substring(stop);
    }

    //Read one more line from the source into the buffer (title line, text line and the padding
    //probe). Returns false at end of input. Shared by getLine()'s read-ahead and the jump-to-end
    //path in moveForward(), which must not loop on getLine(): with title lines that can keep
    //returning a non-null title instead of null.
    private boolean readNextLine() throws IOException {
        String str = reader.readLine();
        if (str == null) return false;
        //RTRIM.matcher(str).replaceAll("") runs a backtracking regex over the whole line;
        //a dbcli grid line is mostly right-padding, so the tail scan below is both faster
        //and allocation-free.
        str = rtrim(str);
        if (totalLines < titleLines) {
            //Title lines stay materialised: there are only a handful of them and every repaint
            //needs them.
            AttributedString buff = toAttributedString(str);
            titles[totalLines] = buff;
            if (padding > 0 && paddingCounter < PADDING_PROBE_LINES) checkPadding(buff);
        } else {
            lines.add(str);
            windowChars += str.length();
            if (padding > 0 && paddingCounter < PADDING_PROBE_LINES) checkPadding(materialize(totalLines));
        }
        ++totalLines;
        if (totalLines > highWaterLines) highWaterLines = totalLines;
        //Bound the peak of a long read-ahead. Pruning only at the end of the loop let a seek or a
        //search that rewinds keep the whole prefix in memory (measured: 32765 lines / 19MB of text
        //for a 32k line source, on a 32bit JVM with a 247MB heap). The line just read is always the
        //newest one, so trimming to the newest window can never drop what the caller is after.
        if ((totalLines & 1023) == 0) pruneWindow();
        return true;
    }

    int paddingCounter = 0;
    int totalLines = 0;

    //Synchronized because the WINCH handler repaints from the signal thread while the main loop may
    //be reading: both end up here, and the BufferedReader underneath is not thread safe.
    synchronized AttributedString getLine(int line) throws IOException {
        if (line < 0) line = 0;
        if (line >= titleLines && line < firstLineInMemory) {
            //Scrolled back above the retained window: re-read the source from the start.
            rewind();
        }
        while (line >= totalLines) {
            if (!readNextLine()) break;
        }
        pruneWindow();
        lineIndex = -1;
        final int line1 = line - firstLineToDisplay;
        if (line1 < titleLines && titleLines > 0) {
            return line1 >= 0 ? titles[line1] : null;
        }
        if (line >= titleLines) {
            final int content = line - firstLineInMemory;
            if (content >= 0 && content < lines.size()) {
                lineIndex = line - titleLines + 1;
                return materialize(line);
            }
        }
        return null;
    }

    //Absolute line shown at the FIRST CONTENT ROW: title lines are pinned at the top of every screen,
    //so the content region starts titleLines rows below firstLineToDisplay. Pattern scans must start
    //there, and a line that should appear at that row needs firstLineToDisplay = line - titleLines -
    //which is also how moveForward/moveBackward already treat the field (they scroll it by one row
    //per displayed line). Treating it as an absolute line instead made every search and seek land
    //titleLines rows past the target, so the found line sat just above the visible area.
    int viewTop() {
        return firstLineToDisplay + titleLines;
    }

    /** Scroll offset: the content row shown first, with the horizontal offset reset. */
    private void setViewTop(int top) {
        firstLineToDisplay = top;
        offsetInLine = 0;
    }

    /** Show an absolute line at the first content row (clamped for lines inside the title block). */
    private void showLineAtTop(int line) {
        setViewTop(Math.max(0, line - titleLines));
    }

    //Line accessor for the pattern scans (moveToNextMatch/moveToPreviousMatch). getLine() resolves a
    //position through the pinned title rows: a row above the top of the screen maps to a title, and
    //one above *that* to null. That is what renders the header on every screen, but it also meant a
    //backward search stopped on its very first step whenever title lines were configured - the scan
    //asked for firstLineToDisplay-1, got null and broke out, so ?pattern/N never found anything.
    //Scanning by absolute line number ignores that mapping (real title rows are still scannable).
    synchronized AttributedString getScanLine(int line) throws IOException {
        if (line < 0) line = 0;
        if (line >= titleLines && line < firstLineInMemory) {
            rewind();
        }
        while (line >= totalLines) {
            if (!readNextLine()) break;
        }
        pruneWindow();
        if (line < titleLines) {
            //The real title row by absolute index. Delegating to getLine() here would return null for
            //any row above the current screen, which is what made `g` (seek to the first line) fail
            //whenever title lines were configured.
            return line < titles.length ? titles[line] : null;
        }
        final int content = line - firstLineInMemory;
        return content >= 0 && content < lines.size() ? materialize(line) : null;
    }

    //Read the rest of the source into the buffer; the jump-to-end paths use it. Synchronized for the
    //same reason as getLine(): the WINCH handler repaints from the signal thread and would otherwise
    //walk the buffer while this loop is appending to it.
    private synchronized void readToEnd() throws IOException {
        while (readNextLine()) {
            //reading to the end
        }
    }

    /** Forget every buffered line and rewind the read cursor to the source's first line. */
    private void clearBuffer() {
        lines = new ArrayList<>();
        windowChars = 0;
        materialized.clear();
        totalLines = 0;
        highWaterLines = 0;
        firstLineInMemory = titleLines;
    }

    /** Replace the buffered text (a restored position) and move the window start with it. */
    private void setBuffer(List<String> text, int windowStart) {
        lines = new ArrayList<>(text);
        windowChars = 0;
        for (String line : text) {
            windowChars += line.length();
        }
        materialized.clear();
        firstLineInMemory = windowStart;
    }

    /** Drop the buffer for good; only the teardown path does this. */
    private void releaseBuffer() {
        lines = null;
        materialized.clear();
        windowChars = 0;
        totalLines = 0;
        highWaterLines = 0;
    }

    /** Put the view back at the top of the current source. */
    private void resetView() {
        firstLineToDisplay = 0;
        firstColumnToDisplay = 0;
        offsetInLine = 0;
    }

    /** Forget cached matches: a new pattern, or a different source. */
    private void resetMatches() {
        matchedLines.clear();
        matchedIndex = -1;
        matchedAsc = true;
    }

    //Re-open the source and drop the buffer; the reads that follow refill it from line 0, so
    //absolute line numbers (and with them firstLineToDisplay, the match list and the screen) stay
    //valid. Only used for sources that can be read twice, see rewindable.
    private synchronized void rewind() throws IOException {
        if (reader != null) {
            reader.close();
        }
        Source source = sources.get(sourceIdx);
        if (source instanceof TextSource) {
            reader = new BufferedReader(new StringReader(((TextSource) source).text));
        } else {
            InputStream in = source.read();
            //An InputStreamSource hands back the very same stream (marked at construction time when
            //it supports it), so without the reset the "rewind" would start reading at its current,
            //already consumed position and produce nothing at all.
            if (source instanceof Source.InputStreamSource && in.markSupported()) {
                in.reset();
            }
            reader = new BufferedReader(new InputStreamReader(new InterruptibleInputStream(in)));
        }
        clearBuffer();
    }

    //Drop the oldest buffered lines once the window overflows, keeping the newest WINDOW_LINES lines
    //(or WINDOW_CHARS of text, whichever is tighter). The floor used to be "one window behind the
    //view", which retained the whole prefix whenever the reader ran ahead of the view - reading to
    //the end of a 32k line source held 32765 lines / 19MB of text at the peak, on a 32bit JVM whose
    //heap is 247MB. Every caller that reads far ahead (jump to end, rewind) moves the view right
    //afterwards, and a line dropped here is re-read through rewind() when the view really needs it.
    //Trimming happens in WINDOW_SLACK sized batches: clearing a sublist shifts every retained
    //reference, and doing that once per line cost ~10us on every line a scan walked over.
    private void pruneWindow() {
        if (!rewindable || (lines.size() <= WINDOW_LINES + WINDOW_SLACK && windowChars <= WINDOW_CHARS)) {
            return;
        }
        int floor = totalLines - WINDOW_LINES;
        int drop = 0;
        while (drop < lines.size()
                && firstLineInMemory + drop < floor
                && (lines.size() - drop > WINDOW_LINES || windowChars > WINDOW_CHARS)) {
            windowChars -= lines.get(drop).length();
            ++drop;
        }
        if (drop > 0) {
            lines.subList(0, drop).clear();
            firstLineInMemory += drop;
        }
    }

    //fromAnsi is only worth its per-cell parse when the line actually carries escape sequences;
    //a plain dbcli grid row is a straight copy either way.
    private AttributedString toAttributedString(String str) {
        return str.indexOf('\u001b') >= 0 ? AttributedString.fromAnsi(str, tabs) : new AttributedString(str);
    }

    //Materialise one buffered line and remember it, keeping the cache bounded: a repaint of the
    //same screen (and the pre-highlight pass that walks back over it) then costs no allocation,
    //while a full-file search scan cannot grow the heap without limit. Keys are absolute line
    //numbers, so entries stay valid while the window slides.
    private AttributedString materialize(int line) {
        AttributedString buff = materialized.get(line);
        if (buff != null) return buff;
        buff = toAttributedString(lines.get(line - firstLineInMemory));
        materialized.put(line, buff);
        if (materialized.size() > MATERIALIZED_CACHE) {
            Iterator<Integer> lru = materialized.keySet().iterator();
            lru.next();
            lru.remove();
        }
        return buff;
    }

    //Same test the reader used to run on the AttributedString it built eagerly: does the line
    //start with at least `padding` blank columns?
    private void checkPadding(AttributedString buff) {
        for (int i = 0, l = Math.min(padding, buff.columnLength()); i < l; i++) {
            if (buff.charAt(i) != ' ') {
                padding = 0;
                break;
            }
        }
        ++paddingCounter;
    }

    /**
     * This is for long running commands to be interrupted by ctrl-c
     *
     * @throws InterruptedException if the thread has been interruped
     */
    public static void checkInterrupted() throws InterruptedException {
        Thread.yield();
        if (Thread.currentThread().isInterrupted()) {
            throw new InterruptedException();
        }
    }

    private void bindKeys(KeyMap<Operation> map) {
        map.bind(Operation.HELP, "h", "H");
        map.bind(Operation.EXIT, "q", ":q", "Q", ":Q", "ZZ");
        map.bind(Operation.FORWARD_ONE_LINE, "e", ctrl('E'), "j", ctrl('N'), "\r", key(terminal, Capability.key_down));
        map.bind(Operation.BACKWARD_ONE_LINE, "y", ctrl('Y'), "k", ctrl('K'), ctrl('P'), key(terminal, Capability.key_up));
        map.bind(Operation.FORWARD_ONE_WINDOW_OR_LINES, "f", ctrl('F'), ctrl('V'), " ", key(terminal, Capability.key_npage));
        map.bind(Operation.BACKWARD_ONE_WINDOW_OR_LINES, "b", ctrl('B'), alt('v'), key(terminal, Capability.key_ppage));
        map.bind(Operation.FORWARD_ONE_WINDOW_AND_SET, "z");
        map.bind(Operation.BACKWARD_ONE_WINDOW_AND_SET, "w");
        map.bind(Operation.FORWARD_ONE_WINDOW_NO_STOP, alt(' '));
        map.bind(Operation.FORWARD_HALF_WINDOW_AND_SET, "d", ctrl('D'));
        map.bind(Operation.BACKWARD_HALF_WINDOW_AND_SET, "u", ctrl('U'));
        map.bind(Operation.RIGHT_ONE_HALF_SCREEN, alt(')'), key(terminal, Capability.key_right));
        map.bind(Operation.LEFT_ONE_HALF_SCREEN, alt('('), key(terminal, Capability.key_left));
        //Home/End are bound to HOME/END further down; binding them here as well is silently
        //overwritten (KeyMap.bind replaces), so the column moves keep their own keys.
        map.bind(Operation.RIGHT_FRIST_COLUMN, "]");
        map.bind(Operation.LEFT_FRIST_COLUMN, "[");
        map.bind(Operation.REPAINT, "r", ctrl('R'), ctrl('L'));
        map.bind(Operation.REPAINT_AND_DISCARD, "R");
        map.bind(Operation.REPEAT_SEARCH_FORWARD, "n");
        map.bind(Operation.REPEAT_SEARCH_BACKWARD, "N");
        map.bind(Operation.REPEAT_SEARCH_FORWARD_SPAN_FILES, alt('n'));
        map.bind(Operation.REPEAT_SEARCH_BACKWARD_SPAN_FILES, alt('N'));
        map.bind(Operation.UNDO_SEARCH, alt('u'));
        map.bind(Operation.GO_TO_FIRST_LINE_OR_N, "g", "<", alt('<'));
        map.bind(Operation.GO_TO_LAST_LINE_OR_N, "G", ">", alt('>'));
        map.bind(Operation.HOME, key(terminal, Capability.key_home));
        map.bind(Operation.END, key(terminal, Capability.key_end));
        map.bind(Operation.ADD_FILE, ":e", ctrl('X') + ctrl('V'));
        map.bind(Operation.NEXT_FILE, ":n");
        map.bind(Operation.PREV_FILE, ":p");
        map.bind(Operation.GOTO_FILE, ":x");
        map.bind(Operation.INFO_FILE, "=", ":f", ctrl('G'));
        map.bind(Operation.DELETE_FILE, ":d");
        map.bind(Operation.BACKSPACE, del(), "\b");
        map.bind(Operation.OPT_PRINT_LINES, "l", "L");
        "-/0123456789?&".chars().forEach(c -> map.bind(Operation.CHAR, Character.toString((char) c)));
    }

    protected enum Operation {

        // General
        HELP,
        EXIT,

        // Moving
        FORWARD_ONE_LINE,
        BACKWARD_ONE_LINE,
        FORWARD_ONE_WINDOW_OR_LINES,
        BACKWARD_ONE_WINDOW_OR_LINES,
        FORWARD_ONE_WINDOW_AND_SET,
        BACKWARD_ONE_WINDOW_AND_SET,
        FORWARD_ONE_WINDOW_NO_STOP,
        FORWARD_HALF_WINDOW_AND_SET,
        BACKWARD_HALF_WINDOW_AND_SET,
        LEFT_ONE_HALF_SCREEN,
        RIGHT_ONE_HALF_SCREEN,
        LEFT_FRIST_COLUMN,
        RIGHT_FRIST_COLUMN,
        REPAINT,
        REPAINT_AND_DISCARD,

        // Searching
        REPEAT_SEARCH_FORWARD,
        REPEAT_SEARCH_BACKWARD,
        REPEAT_SEARCH_FORWARD_SPAN_FILES,
        REPEAT_SEARCH_BACKWARD_SPAN_FILES,
        UNDO_SEARCH,

        // Jumping
        GO_TO_FIRST_LINE_OR_N,
        GO_TO_LAST_LINE_OR_N,

        // Options
        OPT_PRINT_LINES,
        OPT_CHOP_LONG_LINES,
        OPT_QUIT_AT_FIRST_EOF,
        OPT_QUIT_AT_SECOND_EOF,
        OPT_QUIET,
        OPT_VERY_QUIET,
        OPT_IGNORE_CASE_COND,
        OPT_IGNORE_CASE_ALWAYS,
        OPT_SYNTAX_HIGHLIGHT,

        // Files
        ADD_FILE,
        NEXT_FILE,
        PREV_FILE,
        GOTO_FILE,
        INFO_FILE,
        DELETE_FILE,

        //
        CHAR,

        // Edit pattern
        INSERT,
        RIGHT,
        LEFT,
        NEXT_WORD,
        PREV_WORD,
        HOME,
        END,
        BACKSPACE,
        DELETE,
        DELETE_WORD,
        DELETE_LINE,
        ACCEPT,
        UP,
        DOWN
    }

    /** In-memory source: the pager reads the characters directly, no byte copy and no charset round trip. */
    public static class TextSource implements Source {
        private final String name;
        final String text;

        public TextSource(String name, String text) {
            this.name = name;
            this.text = text;
        }

        @Override
        public InputStream read() throws IOException {
            //Never used: openSource()/rewind() take the characters straight from `text`.
            return new ByteArrayInputStream(new byte[0]);
        }

        @Override
        public String getName() {
            return name;
        }

        @Override
        public Long lines() {
            return null;
        }
    }

    static class InterruptibleInputStream extends FilterInputStream {
        InterruptibleInputStream(InputStream in) {
            super(in);
        }

        @Override
        public int read(byte[] b, int off, int len) throws IOException {
            if (Thread.currentThread().isInterrupted()) {
                throw new InterruptedIOException();
            }
            return super.read(b, off, len);
        }
    }

    static class Pair<U, V> {
        final U u;
        final V v;

        public Pair(U u, V v) {
            this.u = u;
            this.v = v;
        }

        public U getU() {
            return u;
        }

        public V getV() {
            return v;
        }
    }

    static class Play extends Display {
        public Play(Terminal terminal) {
            this(terminal, true);
        }

        public Play(Terminal terminal, boolean fullScreen) {
            super(terminal, fullScreen && terminal.getStringCapability(Capability.enter_ca_mode) != null);
        }

        boolean isStarted;
        boolean isEnterCA;
        Status status = null;

        public void init(boolean isEnterCA) {
            if (isStarted) return;
            reset();
            prevBuff = null;
            isStarted = false;
            // Inside a real ConEmu window the alternate screen is not something dbcli can use: leaving it
            // (rmcup, \e[?1049l) does not bring the previous screen back, so the pager's exit left the
            // screen empty with just the prompt - and the scrollback dbcli relies on for reading output
            // is what the wide console buffer is there for. Paint on the normal screen instead, which is
            // also what the pager already does on a console without an alternate screen.
            this.isEnterCA = isEnterCA
                    && terminal.getStringCapability(Capability.exit_ca_mode) != null
                    && !OSUtils.IS_CONEMU;
            status = Status.getStatus(terminal, false);
            if (status != null) {
                status.close();
                status.suspend();
            }
            // Enter fullscreen mode only if isEnterCA flag is set and terminal supports enter_ca_mode
            if (this.isEnterCA && fullScreen && terminal.getStringCapability(Capability.enter_ca_mode) != null) {
                terminal.puts(Capability.enter_ca_mode);
            }
        }

        public void exit() {
            isStarted = false;
            if (this.isEnterCA) {
                terminal.puts(Capability.exit_ca_mode);
                this.isEnterCA = false;
            }
            status = Status.getStatus(terminal, false);
            if (status != null) {
                status.restore();
            }
        }

        @Override
        public void clear() {
            if (!isStarted) return;
            super.clear();
            reset = true;
        }

        @Override
        public void resize(int rows, int columns) {
            if (this.rows != rows || this.columns != columns) {
                super.resize(rows, columns);
                clear();
            }
        }

        @Override
        public synchronized void update(List<AttributedString> newLines, int targetCursorPos) {
            Size size = terminal.getSize();
            resize(size.getRows(), size.getColumns());
            isStarted = true;
            if (!isEnterCA && fullScreen && !OSUtils.IS_CONEMU) {
                // Check if terminal supports enter_ca_mode
                if (terminal.getStringCapability(Capability.enter_ca_mode) != null) {
                    terminal.puts(Capability.enter_ca_mode);
                    clear();
                    isEnterCA = true;
                }
            }
            if (cursorPos > 0 && prevBuff != null && prevOffset > 0) {
                updateBuff("", 0);
            }
            prevBuff = null;
            prevOffset = 0;
            //An unchanged screen is a common repaint: any key that moves nothing, the repaint after a
            //command, a resize that did not change the size. Display still walks every row through
            //DiffHelper.diff() to end up writing nothing - measured 0.38ms per repaint at 40x100 -
            //and its per-row right-margin handling can even emit a space plus a cursor-left per row
            //when the cursor sits in the last column. oldLines is the screen the terminal already
            //shows, so an equal list means the terminal is up to date and only the cursor may need
            //moving. reset (set by clear()/resize()) must still go through the full path.
            if (!reset && newLines.equals(oldLines)) {
                if (targetCursorPos >= 0) {
                    moveVisualCursorTo(targetCursorPos, newLines);
                }
                terminal.writer().flush();
                return;
            }
            //Only the status/command line changed, which is what a search prompt, a message or a
            //toast looks like: paint that one row instead of letting Display walk all of them.
            if (paintLastRow(newLines, targetCursorPos)) {
                return;
            }
            //Everything else is a screen worth of changes (a page, a scroll, a jump): one block.
            if (paintWholeScreen(newLines, targetCursorPos)) {
                return;
            }
            super.update(newLines, targetCursorPos, false);
            terminal.writer().flush();
        }

        /**
         * Paint the whole screen as one sequential block (home, every row, erase to end of line).
         * Display.update addresses every changed row absolutely, and a chunk with more than one cursor
         * address is exactly what the rectangle writer has to decline - so on this terminal the pager
         * would be painted row by row by ConEmuHk's renderer, which is what made `more` slow to appear.
         * As one block it is a single WriteConsoleOutputW rectangle instead.
         *
         * Display's model has to be kept in step with the screen afterwards, otherwise the next
         * incremental repaint would draw against a screen that does not exist: oldLines becomes the
         * list that is now on screen, and cursorPos becomes where the block left the cursor (the end of
         * the last row it wrote, Display counting one virtual newline per row).
         */
        private boolean paintWholeScreen(List<AttributedString> newLines, int targetCursorPos) {
            // isEnterCA (smcup, \e[?1049h) needs no guard: inside a real ConEmu window Console.java
            // does not use WinSysTerminal at all, so a session that reaches this code has no ConEmu GUI
            // to switch screen buffers - and the console handle this writer holds stays the visible one.
            if (!Console.isBulkBlockEnabled(terminal)) {
                return false;
            }
            terminal.writer().print(Console.screenBlock(newLines, rows, columns));
            terminal.writer().flush();
            int last = Math.min(rows, newLines.size()) - 1;
            int lastLength = 0;
            if (last >= 0 && newLines.get(last) != null) {
                lastLength = Math.min(newLines.get(last).columnLength(), columns);
            }
            oldLines = newLines;
            reset = false;
            cursorPos = last <= 0 ? lastLength : last * columns1 + lastLength;
            if (targetCursorPos >= 0) {
                moveVisualCursorTo(targetCursorPos, newLines);
            }
            return true;
        }

        /**
         * Paint the last row only, for the repaints where it is the only one that changed. The pager
         * rewrites that row (status line, search prompt, message) on nearly every keystroke while the
         * view stays put, and Display would still run DiffHelper.diff() over every row - measured
         * ~0.3ms of the ~0.35ms such a repaint costs at 40x100 - just to patch this one row.
         *
         * Only the narrow case is taken, everything else falls back to the full update:
         * every other row is equal, the screen fills the terminal exactly, both the old and the new
         * last row are narrower than the terminal (so no delayed-wrap state can be pending) and the
         * cursor is not parked in the last column. The row itself is written exactly the way Display
         * would write it: the new tail when the row only grew, otherwise the whole row plus a clear
         * to end of line.
         */
        private boolean paintLastRow(List<AttributedString> newLines, int targetCursorPos) {
            final int n = newLines.size();
            if (reset || n < 2 || n != oldLines.size() || n != rows) return false;
            if ((cursorPos % columns1) == columns) return false;
            AttributedString last = newLines.get(n - 1);
            AttributedString prev = oldLines.get(n - 1);
            if (last.equals(prev)) return false;
            if (last.columnLength() >= columns || prev.columnLength() >= columns) return false;
            if (!newLines.subList(0, n - 1).equals(oldLines.subList(0, n - 1))) return false;

            final int rowStart = (n - 1) * columns1;
            final int prevCols = prev.columnLength();
            if (last.columnSubSequence(0, prevCols).equals(prev)) {
                AttributedString tail = last.columnSubSequence(prevCols, last.columnLength());
                moveVisualCursorTo(rowStart + prevCols);
                tail.print(terminal);
            } else {
                //Same order as Display's diff: position, clear to end of line, then the new row.
                moveVisualCursorTo(rowStart);
                if (!terminal.puts(Capability.clr_eol)) {
                    //No clear-to-eol: blank out whatever the previous, longer row left behind.
                    int extra = prevCols - last.columnLength();
                    if (extra > 0) {
                        if (blankLine.length < extra) {
                            blankLine = new char[Math.max(extra, columns)];
                            Arrays.fill(blankLine, ' ');
                        }
                        terminal.writer().write(blankLine, 0, extra);
                    }
                }
                last.print(terminal);
            }
            cursorPos = rowStart + last.columnLength();
            oldLines = newLines;
            if (targetCursorPos >= 0) {
                moveVisualCursorTo(targetCursorPos, newLines);
            }
            terminal.writer().flush();
            return true;
        }

        public int getPos() {
            return cursorPos;
        }

        String prevBuff = null;
        int prevOffset;
        //Display already resolves exactly this in its constructor (terminal column_address != null),
        //so the shadowing field and its lazy lookup are redundant.
        private char[] blankLine = new char[0];

        /**
         * Move cursor to specified column using column_address or fallback method
         */
        private void moveCursorToColumn(int col) {
            if (hasColumnAddress) {
                terminal.puts(Capability.column_address, col);
            } else {
                // Fallback: carriage return, then move right. perform() picks the counted capability
                //(one escape sequence) and only loops the single-width one when the terminal has no
                //counted form - the hand written loop sent `col` separate sequences per call.
                terminal.puts(Capability.carriage_return);
                if (col > 0) {
                    perform(Capability.cursor_right, Capability.parm_right_cursor, col);
                }
            }
        }

        public boolean updateBuff(final String currBuff, int offset) {
            if (offset > -1) prevOffset = offset;
            if (currBuff.equals(prevBuff)) {
                if (offset > -1) moveCursorToColumn(offset);
                return true;
            }
            if (prevBuff != null && currBuff.startsWith(prevBuff)) {
                terminal.writer().write(currBuff.substring(prevBuff.length()));
                terminal.writer().flush();
            } else {
                // Check if terminal supports clr_bol before using it
                if (clrBol != null) {
                    // clr_bol clears from line start to cursor; cursor stays at current column.
                    terminal.puts(InfoCmp.Capability.clr_bol);
                    moveCursorToColumn(0);
                } else {
                    // Fallback: overwrite the line with spaces then return to column 0.
                    // Use the cached column count to avoid a live getSize() call that could
                    // return a stale value after a resize and cause a spurious line wrap.
                    terminal.puts(Capability.carriage_return);
                    if (blankLine.length < columns) {
                        blankLine = new char[columns];
                        Arrays.fill(blankLine, ' ');
                    }
                    terminal.writer().write(blankLine, 0, columns);
                    terminal.puts(Capability.carriage_return);
                }
                terminal.writer().print(currBuff);
                terminal.flush();
            }

            if (prevOffset != currBuff.length() && prevOffset > 0) moveCursorToColumn(prevOffset);
            cursorPos += currBuff.length() - (prevBuff == null ? 0 : prevBuff.length());
            prevBuff = currBuff;
            return false;
        }
    }
}
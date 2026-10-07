package org.dbcli;


import java.io.IOError;
import java.io.IOException;
import java.io.Writer;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.function.IntConsumer;

import com.hyee.ansirender.NativeRenderer;
import org.jline.keymap.KeyMap;
import org.jline.nativ.Kernel32;
import org.jline.nativ.Kernel32.CONSOLE_SCREEN_BUFFER_INFO;
import org.jline.nativ.Kernel32.INPUT_RECORD;
import org.jline.nativ.Kernel32.KEY_EVENT_RECORD;
import org.jline.reader.impl.LineReaderImpl;
import org.jline.terminal.Cursor;
import org.jline.terminal.Size;
import org.jline.terminal.TerminalBuilder;
import org.jline.terminal.impl.AbstractWindowsTerminal;
import org.jline.terminal.impl.jni.JniTerminalProvider;
import org.jline.terminal.spi.SystemStream;
import org.jline.terminal.spi.TerminalProvider;
import org.jline.utils.InfoCmp;
import org.jline.utils.OSUtils;
import org.jline.utils.Status;

import static org.jline.nativ.Kernel32.FORMAT_MESSAGE_FROM_SYSTEM;
import static org.jline.nativ.Kernel32.FormatMessageW;
import static org.jline.nativ.Kernel32.GetConsoleScreenBufferInfo;
import static org.jline.nativ.Kernel32.GetLastError;
import static org.jline.nativ.Kernel32.GetStdHandle;
import static org.jline.nativ.Kernel32.INVALID_HANDLE_VALUE;
import static org.jline.nativ.Kernel32.STD_ERROR_HANDLE;
import static org.jline.nativ.Kernel32.STD_INPUT_HANDLE;
import static org.jline.nativ.Kernel32.STD_OUTPUT_HANDLE;
import static org.jline.nativ.Kernel32.WaitForSingleObject;
import static org.jline.nativ.Kernel32.readConsoleInputHelper;

public class WinSysTerminal extends AbstractWindowsTerminal<Long> {

    private static final long consoleIn = GetStdHandle(STD_INPUT_HANDLE);
    private static final long consoleOut = GetStdHandle(STD_OUTPUT_HANDLE);
    private static final long consoleErr = GetStdHandle(STD_ERROR_HANDLE);

    /*
    public SystemStream getSystemStream(List<TerminalProvider> providers) {
        SystemOutput systemOutput = computeSystemOutput();
        Map<SystemStream, Boolean> system = Stream.of(SystemStream.values())
                .collect(Collectors.toMap(
                        stream -> stream, stream -> providers.stream().anyMatch(p -> p.isSystemStream(stream))));
        return select(system, systemOutput);
    }
    * */

    public static WinSysTerminal createTerminal(
            String name,
            String type,
            boolean ansiPassThrough,
            Charset encoding,
            boolean nativeSignals,
            SignalHandler signalHandler,
            boolean paused)
            throws IOException {
        // Get input console mode
        int[] inMode = new int[1];
        if (Kernel32.GetConsoleMode(consoleIn, inMode) == 0) {
            throw new IOException("Failed to get console mode: " + getLastErrorMessage());
        }
        JniTerminalProvider provider = new JniTerminalProvider();
        ArrayList<TerminalProvider> providers = new ArrayList<>();
        providers.add(provider);
        // Get output console and mode
        SystemStream systemStream = TerminalBuilder
                .builder().getSystemStream(providers);

        long console = getConsole(systemStream);
        int[] outMode = new int[1];
        if (Kernel32.GetConsoleMode(console, outMode) == 0) {
            throw new IOException("Failed to get console mode: " + getLastErrorMessage());
        }
        // Create writer
        Writer writer;

        /* A ConPTY console is not a grid to be painted, whatever ANSICON_DEF says. The terminal above it
           parses the escapes itself, and the headless conhost in between turns this process's cell writes
           back into VT for that terminal -- VtIo.cpp:771-830 -- so a paint is applied twice, once by a model
           and once by a serializer that knows nothing about it. What an adopt repaints makes that concrete:
           it writes back cells it merely read, cmd's own listing among them, and re-emitting text the
           terminal has already shown puts it in a scrollback that is not ours to write. Full-width glyphs are
           where the round trip loses: a run that begins or ends between the two cells of one glyph is
           replaced by a space on the way out (VtIo.cpp:786-806).
           The test is read off the console's window, not from WT_SESSION. That variable is inherited by a
           plain conhost window started from inside a WT session -- a window that parses nothing, and the one
           the variable gets wrong -- whereas the window class is VtIo mode as conhost itself reports it
           (getset.cpp:1262-1275). Where the library cannot answer, the old weaker test stands in, and it is
           only ever reached on a session that has no painter to begin with. */
        /* #99: an explicit ANSICON_DEF=conemu now outranks the pseudo-console test, by the owner's
           decision on 2026-09-27. Before this, a Windows Terminal session with ANSICON_DEF=conemu in its
           environment took the ConPTY branch at the line below and never reached the ConEmuWriter branch,
           so the painter was skipped for the whole session and nothing said so -- ConEmuWriter is the
           only caller that reports unavailableReason().
         
           WARNING, current as of build -48: two costs were measured on this branch and one has been paid.
           PAID (#104): the host's own escape parser is now switched off by render.dll for as long as it is
           painting, so a chunk the renderer declines looks the same on Windows 7 and on 1809+ -- that was the
           owner's actual requirement, and it is enforced in the library, not here.
           STILL OWED (#103, reproduced on screen 2026-09-27): under a pseudo-console a write of cells is
           turned back into escape sequences by a serializer that knows nothing about this model, so the rows
           an adopt merely re-read reach the terminal as NEW OUTPUT and land in a scrollback that is not ours.
           A screenshot of `help` followed by a resize showed it plainly -- two status bars, the listing
           interleaved in two columns, two prompts. Clearing ENABLE_VIRTUAL_TERMINAL_PROCESSING does not help
           with that one: headless conhost serialises buffer changes to the pty whatever this buffer's mode
           says. The fix is in align_grid's `rc_mark_all_dirty` (ANSI_TODO #103 has the line).
           ANSI_RENDER=off remains the way out of both: ConEmuWriter then holds no renderer and every write
           goes out raw, which is always correct and only slower.
           See DESIGN.md rows #37, #38 and #99, ANSI_TODO #103/#104, and JLINE_CHANGES.md. */
        final String claim = System.getenv("ANSICON_DEF");
        final String term = System.getenv("TERM");
        /* TERM=windows-render is the same claim through the channel dbcli.bat uses: it selects the
           renderer (ConEmuWriter/render.dll) AND its own caps. */
        final boolean rendererClaimed = "conemu".equals(claim) || "render".equals(claim)
                || "windows-render".equals(term) || "render".equals(term);
        /* The hosting terminal's declared dialect outranks our Windows defaults when it set one and no
           explicit claim says otherwise. wezterm and ghostty export TERM=xterm-256color even on Windows,
           and on the branches below where the escapes flow out to that terminal (a pseudo-console
           pass-through, a VTP-capable console) its dialect is the one worth encoding for. Only names with
           built-in caps qualify: the lookup is InfoCmp's pure in-memory registry, never the infocmp
           shell-out -- the Windows gate in InfoCmp.getInfoCmp stands untouched, by the owner's 2026-10-05
           ruling -- and an unknown TERM keeps the Windows default instead of degrading the session.
           MSYS/Cygwin are excluded on purpose (their consoles are ptys with their own terminfo chain, and
           dbcli.bat already corrects ANSICON_DEF there), and `dumb` because honouring a TERM set for
           redirected stdio would switch a live console session to dumb caps. The renderer branches below
           still force their own type: a session painting through render.dll speaks the renderer's dialect,
           whatever the host terminal would have said. */
        if (type == null && !OSUtils.IS_MSYSTEM && !OSUtils.IS_CYGWIN && !rendererClaimed) {
            if (term != null && !term.isEmpty() && !"dumb".equals(term) && !"dumb-color".equals(term)
                    && InfoCmp.getDefaultInfoCmp(term) != null) {
                type = term;
            }
        }
        /* A real ConEmu window parses the stream itself, so its dialect is windows-conemu even when its
           conhost advertises VTP -- the vtp caps describe conhost's parser, and the consumer of these
           bytes is ConEmu. Measured 2026-10-07: the enableVtp branch below won over the IS_CONEMU branch
           on a real ConEmu (type=windows-vtp, the same on the pre-TERM jars), which is the wrong dialect
           for the thing actually reading the escapes. A TERM the host set still wins over this; it only
           fills the default. The writer is untouched -- the stream still goes out as-is for ConEmu to
           parse. */
        if (type == null && OSUtils.IS_CONEMU) {
            type = TYPE_WINDOWS_CONEMU;
        }
        Boolean pty = NativeRenderer.pseudoConsole();
        /* 2026-09-29, owner's ruling: the claim wins. ANSICON_DEF=conemu is the owner saying "this session
           renders through the native renderer", and a pseudo-console test may not silently override it --
           the 2026-09-28 ordering (pty first, claim ignored with a startup warning) routed every ConPTY-hosted
           session to the plain writer instead, which the owner called the bypass itself: the session prints
           escapes to the terminal above and render.dll never runs. So the claim is tested first again
           (the #99 order of 2026-09-27), with no warning: the claim is honoured, not apologised for.
           2026-10-07: ANSICON_DEF=render joins it with the renderer's own caps entry -- same dialect as
           conemu at the fork, free to diverge -- so the two renderers' contracts can be told apart.
           What painting under a pseudo-console has to get right is then render.dll's business -- the
           re-serialization hazard is real (MSFT VtIo.cpp:771-830 turns a cell write back into escapes) and
           is tracked as ANSI_TODO #103/#104; it is a defect to fix in the renderer, not a licence to skip
           the renderer. */
        if (rendererClaimed) {
            // ANSICON_DEF=conemu keeps the conemu name (the session's own declaration); the render forms
            // -- TERM=windows-render as dbcli.bat exports, ANSICON_DEF=render -- take the renderer's own.
            type = "conemu".equals(claim) ? TYPE_WINDOWS_CONEMU : TYPE_WINDOWS_RENDER;
            writer = new ConEmuWriter(console);
        } else if (pty != null ? pty.booleanValue()
                : System.getenv("WT_SESSION") != null && enableVtp(console, outMode[0])) {
            /* No enableVtp call here: a ConPTY console already has it on -- measured 2026-09-25 in Windows
               Terminal, mode 0x7 with the VTP bit both set and settable -- and this branch is taken on the
               fact that the *terminal* parses, which does not depend on this buffer's mode. */
            type = type != null ? type : TYPE_WINDOWS_VTP;
            writer = newConsoleWriter(console);
        } else if (ansiPassThrough) {
            if (("ansicon").equals(System.getenv("ANSICON_DEF"))) {
                if (enableVtp(console, outMode[0])) {
                    type = type != null ? type : TYPE_WINDOWS_VTP;
                    writer = newConsoleWriter(console);
                } else {
                    type = TYPE_WINDOWS_CONEMU;
                    writer = new ConEmuWriter(console);
                }
            } else {
                type = type != null ? type : OSUtils.IS_CONEMU ? TYPE_WINDOWS_CONEMU : TYPE_WINDOWS;
                writer = newConsoleWriter(console);
            }
        } else {
            if (enableVtp(console, outMode[0])) {
                type = type != null ? type : TYPE_WINDOWS_VTP;
                writer = newConsoleWriter(console);
            } else if (OSUtils.IS_CONEMU) {
                type = type != null ? type : TYPE_WINDOWS_CONEMU;
                writer = newConsoleWriter(console);
            } else {
                // The console cannot parse the escapes itself and is not ConEmu, so somebody has to
                // render them: the native renderer in ConEmuWriter does the parsing and paints the
                // cells. The alternative here was JLine's WindowsAnsiWriter, which issues one console
                // call per character and costs seconds on a large result set.
                type = TYPE_WINDOWS_CONEMU;
                writer = new ConEmuWriter(console);
            }
        }
        // Create terminal
        WinSysTerminal terminal = new WinSysTerminal(
                provider,
                systemStream,
                writer,
                name,
                type,
                encoding,
                nativeSignals,
                signalHandler,
                consoleIn,
                inMode[0],
                console,
                outMode[0]);
        // Start input pump thread
        if (!paused) {
            terminal.resume();
        }
        return terminal;
    }


    public static long getConsole(SystemStream systemStream) {
        long console;
        switch (systemStream) {
            case Output:
                console = consoleOut;
                break;
            case Error:
                console = consoleErr;
                break;
            default:
                throw new IllegalArgumentException("Unsupported stream for console: " + systemStream);
        }
        return console;
    }

    private static boolean enableVtp(long console, int outMode) {
        return Kernel32.SetConsoleMode(console, outMode | AbstractWindowsTerminal.ENABLE_VIRTUAL_TERMINAL_PROCESSING)
                != 0;
    }

    private static Writer newConsoleWriter(long console) {
        return new WinConsoleWriter(console);
    }

    WinSysTerminal(
            TerminalProvider provider,
            SystemStream systemStream,
            Writer writer,
            String name,
            String type,
            Charset encoding,
            boolean nativeSignals,
            SignalHandler signalHandler,
            long inConsole,
            int inMode,
            long outConsole,
            int outMode)
            throws IOException {
        super(
                provider,
                systemStream,
                writer,
                name,
                type,
                encoding,
                nativeSignals,
                signalHandler,
                inConsole,
                inMode,
                outConsole,
                outMode);
        if (status != null && type.equals(TYPE_WINDOWS)) {
            status.hide();
            status.suspend();
            status = null;
        }
        /* Held because the input pump is the only thing in the process that learns a key was pressed, and a
           console rendering its own escapes -- or nobody rendering them -- has nothing to be told. Taken from
           the constructor's argument rather than from getOutput(): whatever the base terminal does to the
           writer afterwards, this is the object that owns the renderer. */
        this.consoleWriter = writer instanceof ConEmuWriter ? (ConEmuWriter) writer : null;
        t.setDaemon(true);
        t.start();
    }

    private ConEmuWriter consoleWriter;

    @Override
    public Status getStatus(boolean create) {
        super.getStatus(create);
        if (status != null && status.toString().contains("false")) {
            status.close();
            status.suspend();
            status = null;
        }
        return status;
    }

    final private static int[] mode = new int[1];

    public static boolean isWindowsSystemStream(SystemStream stream) {
        long console;
        switch (stream) {
            case Input:
                console = consoleIn;
                break;
            case Output:
                console = consoleOut;
                break;
            case Error:
                console = consoleErr;
                break;
            default:
                return false;
        }
        return Kernel32.GetConsoleMode(console, mode) != 0;
    }

    @Override
    protected int getConsoleMode(Long console) {
        if (Kernel32.GetConsoleMode(console, mode) == 0) {
            return -1;
        }
        return mode[0];
    }

    @Override
    protected void setConsoleMode(Long console, int mode) {
        Kernel32.SetConsoleMode(console, mode);
    }

    //Restore the exact console mode captured at startup, so a native child given the real console (e.g. sqlplus) gets cooked line-input and command history.
    public void restoreOrgConsoleMode() {
        setConsoleMode(inConsole, originalInConsoleMode);
        //Also clear VT processing on output: Windows 11 enables it by default, and sqlplus 21c
        //switches to its own VT line editor on a VT console, losing conhost's cooked up/down
        //command history and F7. Handing over a plain cooked console keeps them working.
        setConsoleMode(outConsole, originalOutConsoleMode & ~AbstractWindowsTerminal.ENABLE_VIRTUAL_TERMINAL_PROCESSING);
    }

    //Save the current console mode before pausing, so we can restore it when resuming
    private int savedConsoleMode = -1;
    private int savedOutConsoleMode = -1;

    public void saveConsoleMode() {
        savedConsoleMode = getConsoleMode(inConsole);
        savedOutConsoleMode = getConsoleMode(outConsole);
    }

    public void resumeConsoleMode() {
        if (savedConsoleMode >= 0) {
            setConsoleMode(inConsole, savedConsoleMode);
        }
        if (savedOutConsoleMode >= 0) {
            setConsoleMode(outConsole, savedOutConsoleMode);
        }
    }

    /* Two rules, both learned from what they cost.
     *
     * The caller keeps what it is handed. One shared, mutated Size used to serve both questions, so a
     * caller that held getSize() across a getBufferSize() call woke up with 2000x9001 in a variable it
     * had read as a window (measured: the two calls returned the same object identity). The contract in
     * this codebase is a copy -- LineDisciplineTerminal.getSize() does exactly that, and jline's own
     * NativeWinSysTerminal returns distinct objects.
     *
     * A failed query is not a size. GetConsoleScreenBufferInfo writes nothing when it fails, so the
     * struct kept whatever was last in it -- zeros on the first call -- and windowWidth() turned 0-0+1
     * into a plausible 1x1 while the buffer answer came out a flat 0x0. Display.resize() then reads a
     * 0 as "one row, two billion columns" and the status bar quietly draws a line the width of an
     * integer; the width check in Console.setStatus() reads the same zero as "no status bar". Both were
     * silent. The convention for a failed console call here is getCursorPosition(): throw. */
    public Size getSize() {
        CONSOLE_SCREEN_BUFFER_INFO info = new CONSOLE_SCREEN_BUFFER_INFO();
        if (GetConsoleScreenBufferInfo(outConsole, info) == 0) {
            throw new IOError(new IOException("Could not get the window size: " + getLastErrorMessage()));
        }
        return new Size(info.windowWidth(), info.windowHeight());
    }

    @Override
    public Size getBufferSize() {
        CONSOLE_SCREEN_BUFFER_INFO info = new CONSOLE_SCREEN_BUFFER_INFO();
        if (GetConsoleScreenBufferInfo(outConsole, info) == 0) {
            throw new IOError(new IOException("Could not get the buffer size: " + getLastErrorMessage()));
        }
        return new Size(info.size.x, info.size.y);
    }

    private volatile long prevTime = 0;
    private volatile int pasteCount = 0;
    private volatile char lastChar;
    private volatile boolean enablePaste = true;
    volatile CountDownLatch latch = null;
    final char[] bp = KeyMap.translate(LineReaderImpl.BRACKETED_PASTE_BEGIN).toCharArray();
    final char[] ep = KeyMap.translate(LineReaderImpl.BRACKETED_PASTE_END).toCharArray();
    final short bpl = (short) (bp.length - 1);
    final short epl = (short) (ep.length - 1);
    final short START_POS = 1;
    final String tab = "    ";
    short beginIdx = START_POS;
    short endIdx = START_POS;

    public void enablePaste(boolean enabled) {
        enablePaste = enabled;
    }

    Thread t = new Thread(() -> {
        while (true) {
            try {
                if (!paused() && latch == null) {
                    latch = new CountDownLatch(1);
                    latch.await();
                } else Thread.sleep(32);
                if (prevTime == 0 || pasteCount == 0 || paused()) continue;
                //If no more input after 128+ ms, leave the paste mode (Assume that consuming a input char costs 300us)
                if (System.currentTimeMillis() - prevTime >= 128 + pasteCount * 0.3) {
                    pasteCount = 0;
                    if (endIdx != epl) {
                        slaveInputPipe.write(LineReaderImpl.BRACKETED_PASTE_END);
                        if (lastChar == '\r' || lastChar == '\n') processChar('\n');
                        prevTime = 0;
                    }
                    latch = null;
                }
            } catch (Exception e) {
            }
        }
    });

    final void processChar(char c) throws IOException {
        super.processInputChar(c);
    }

    @Override
    public int getDefaultForegroundColor() {
        CONSOLE_SCREEN_BUFFER_INFO info = new CONSOLE_SCREEN_BUFFER_INFO();
        if (GetConsoleScreenBufferInfo(outConsole, info) == 0) {
            return -1;
        }
        return convertAttributeToRgb(info.attributes & 0x0F, true);
    }

    @Override
    public int getDefaultBackgroundColor() {
        CONSOLE_SCREEN_BUFFER_INFO info = new CONSOLE_SCREEN_BUFFER_INFO();
        if (GetConsoleScreenBufferInfo(outConsole, info) == 0) {
            return -1;
        }
        return convertAttributeToRgb((info.attributes & 0xF0) >> 4, false);
    }

    @Override
    public void processInputChar(char c) throws IOException {
        lastChar = c;
        //check if the console natively supports Bracketed Paste
        if (pasteCount == 0 && c == bp[beginIdx]) beginIdx += beginIdx >= bpl ? 0 : 1;
        else if (pasteCount == 0 && beginIdx > START_POS && beginIdx < bpl) beginIdx = START_POS;
        else if (pasteCount > 0 && c == ep[endIdx]) endIdx += endIdx >= epl ? 0 : 1;
        else if (pasteCount > 0 && endIdx > START_POS && endIdx < epl) endIdx = START_POS;
        //Check remaining input chars and determine if enter paste mode
        if (enablePaste && beginIdx != bpl && pasteCount == 0 && Character.isWhitespace(c) && reader.available() >= 3) {
            this.slaveInputPipe.write(LineReaderImpl.BRACKETED_PASTE_BEGIN);
            prevTime = System.currentTimeMillis();
            pasteCount = 1;
            if (latch != null) latch.countDown();
            //insert one more space to bypass the completor's detection if the first pasted char is tab
            if (c == '\t') {
                this.slaveInputPipe.write(' ');
                return;
            }
        } else if (pasteCount > 0) {
            if (latch != null) latch.countDown();
            pasteCount = pasteCount + 1;
            //reduce the frequency of getting timer to avoid performance issue
            //the timer is used to determine whether to leave the paste mode
            if (pasteCount > 100) {
                prevTime = System.currentTimeMillis();
                pasteCount = 1;
            }
        } else if (c == '\t') {
            //deal with tab, if there are remaining input chars, then replace as 4 spaces to bypass the completor's detection
            if (reader.available() == 0) {
                try {
                    Thread.sleep(16L);
                } catch (InterruptedException e) {
                }
            }
            if (reader.available() > 0) {
                this.slaveInputPipe.write(tab);
                return;
            }
        }
        processChar(c);
    }

    final protected boolean processConsoleInput() throws IOException {
        INPUT_RECORD[] events;
        if (inConsole != INVALID_HANDLE_VALUE && WaitForSingleObject(inConsole, 100) == 0) {
            events = readConsoleInputHelper(inConsole, 1, false);
        } else {
            return false;
        }

        boolean flush = false;
        for (INPUT_RECORD event : events) {
            if (event.eventType == INPUT_RECORD.KEY_EVENT) {
                KEY_EVENT_RECORD keyEvent = event.keyEvent;
                processKeyEvent(keyEvent.keyDown, keyEvent.keyCode, keyEvent.uchar, keyEvent.controlKeyState);
                if (keyEvent.keyDown && isInputKey(keyEvent.keyCode)) {
                    snapOnInput();
                }
                flush = true;
            } else if (event.eventType == INPUT_RECORD.WINDOW_BUFFER_SIZE_EVENT) {
                raise(Signal.WINCH);
            } else if (event.eventType == INPUT_RECORD.MOUSE_EVENT) {
                processMouseEvent(event.mouseEvent);
                flush = true;
            } else if (event.eventType == INPUT_RECORD.FOCUS_EVENT) {
                processFocusEvent(event.focusEvent.setFocus);
            }
        }

        return flush;
    }

    /**
     * The keys a user presses *at* a screen, as opposed to the modifiers they hold on the way to one of them
     * -- conhost's own list ({@code IsInputKey}, screenInfo.cpp:1668-1680), taken whole because the defect it
     * prevents is a real one: pressing Shift to type a capital letter must not yank a view the user moved
     * deliberately, and only the key they meant says "I am typing where I cannot see".
     */
    private static boolean isInputKey(int vkey) {
        switch (vkey) {
            case 0x11: case 0xA2: case 0xA3:      /* CONTROL, LCONTROL, RCONTROL */
            case 0x12: case 0xA4: case 0xA5:      /* MENU, LMENU, RMENU */
            case 0x10: case 0xA0: case 0xA1:      /* SHIFT, LSHIFT, RSHIFT */
            case 0x5B: case 0x5C:                 /* LWIN, RWIN */
            case 0x2C:                            /* SNAPSHOT */
                return false;
            default:
                return true;
        }
    }

    /** Asks the renderer, if this terminal has one, to put the prompt back where the user is about to type. */
    private void snapOnInput() {
        if (consoleWriter != null) {
            consoleWriter.snapOnInput();
        }
    }

    private final char[] focus = new char[]{'\033', '[', ' '};

    private void processFocusEvent(boolean hasFocus) throws IOException {
        /* A1: under the ConEmu writer the DECSET stream was parsed by render.dll, not by this class, so
           the model is the one that knows whether `?1004` is armed. Its verdict -- including "nothing
           is due" -- outranks the jline-side flag; only a library that cannot be asked falls back. */
        if (consoleWriter != null && consoleWriter.writeFocusReport(hasFocus, slaveInputPipe)) {
            return;
        }
        if (focusTracking) {
            focus[2] = hasFocus ? 'I' : 'O';
            slaveInputPipe.write(focus);
        }
    }

    private final char[] mouse = new char[]{'\033', '[', 'M', ' ', ' ', ' '};

    private void processMouseEvent(Kernel32.MOUSE_EVENT_RECORD mouseEvent) throws IOException {
        int dwEventFlags = mouseEvent.eventFlags;
        int dwButtonState = mouseEvent.buttonState;
        /* A1: same seam as focus above. The model parsed `?1006h` when the stream asked for SGR, so its
           encoder answers in the armed format; the hand-rolled X10 below is the fallback for a console
           this process does not render (the vtp path) or a dll older than the seam. The jline-side
           `tracking` gate is deliberately not consulted first on this path: a program that armed the
           mouse through the stream is owed its reports even when jline's own notion says Off. */
        if (consoleWriter != null
                && consoleWriter.writeMouseReport(dwButtonState, dwEventFlags, mouseEvent.controlKeyState,
                        mouseEvent.mousePosition.x, mouseEvent.mousePosition.y, slaveInputPipe)) {
            return;
        }
        if (tracking == MouseTracking.Off
                || tracking == MouseTracking.Normal && dwEventFlags == Kernel32.MOUSE_EVENT_RECORD.MOUSE_MOVED
                || tracking == MouseTracking.Button
                && dwEventFlags == Kernel32.MOUSE_EVENT_RECORD.MOUSE_MOVED
                && dwButtonState == 0) {
            return;
        }
        int cb = 0;
        dwEventFlags &= ~Kernel32.MOUSE_EVENT_RECORD.DOUBLE_CLICK; // Treat double-clicks as normal
        if (dwEventFlags == Kernel32.MOUSE_EVENT_RECORD.MOUSE_WHEELED) {
            cb |= 64;
            if ((dwButtonState >> 16) < 0) {
                cb |= 1;
            }
        } else if (dwEventFlags == Kernel32.MOUSE_EVENT_RECORD.MOUSE_HWHEELED) {
            return;
        } else if ((dwButtonState & Kernel32.MOUSE_EVENT_RECORD.FROM_LEFT_1ST_BUTTON_PRESSED) != 0) {
            cb |= 0x00;
        } else if ((dwButtonState & Kernel32.MOUSE_EVENT_RECORD.RIGHTMOST_BUTTON_PRESSED) != 0) {
            cb |= 0x01;
        } else if ((dwButtonState & Kernel32.MOUSE_EVENT_RECORD.FROM_LEFT_2ND_BUTTON_PRESSED) != 0) {
            cb |= 0x02;
        } else {
            cb |= 0x03;
        }
        int cx = mouseEvent.mousePosition.x;
        int cy = mouseEvent.mousePosition.y;
        mouse[3] = (char) (' ' + cb);
        mouse[4] = (char) (' ' + cx + 1);
        mouse[5] = (char) (' ' + cy + 1);
        slaveInputPipe.write(mouse);
    }

    @Override
    public Cursor getCursorPosition(IntConsumer discarded) {
        CONSOLE_SCREEN_BUFFER_INFO info = new CONSOLE_SCREEN_BUFFER_INFO();
        if (GetConsoleScreenBufferInfo(outConsole, info) == 0) {
            throw new IOError(new IOException("Could not get the cursor position: " + getLastErrorMessage()));
        }
        return new Cursor(info.cursorPosition.x, info.cursorPosition.y);
    }

    /* The cursor that cursor_address reaches is window-relative (its rows count from the window's top),
       but getCursorPosition() above hands out the buffer-absolute answer of the same query. The two
       differ by srWindow.top whenever the buffer is taller than the window, and the
       buffer-height-minus-window-height guess is wrong exactly when it matters: a scrollback console
       whose window is not parked at the buffer's end while a prompt sits on the window's own bottom
       row. Callers comparing a readback against window coordinates want this one: {x, y}. */
    public int[] getRelativeCursorPosition() {
        CONSOLE_SCREEN_BUFFER_INFO info = new CONSOLE_SCREEN_BUFFER_INFO();
        if (GetConsoleScreenBufferInfo(outConsole, info) == 0) {
            throw new IOError(new IOException("Could not get the cursor position: " + getLastErrorMessage()));
        }
        return new int[] { info.cursorPosition.x - info.window.left,
                           info.cursorPosition.y - info.window.top };
    }

    public void disableScrolling() {
        strings.remove(InfoCmp.Capability.insert_line);
        strings.remove(InfoCmp.Capability.parm_insert_line);
        strings.remove(InfoCmp.Capability.delete_line);
        strings.remove(InfoCmp.Capability.parm_delete_line);
    }

    static String getLastErrorMessage() {
        int errorCode = GetLastError();
        return getErrorMessage(errorCode);
    }

    static String getErrorMessage(int errorCode) {
        int bufferSize = 160;
        byte[] data = new byte[bufferSize];
        FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM, 0, errorCode, 0, data, bufferSize, null);
        return new String(data, StandardCharsets.UTF_16LE).trim();
    }


}

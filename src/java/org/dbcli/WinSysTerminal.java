package org.dbcli;


import java.io.BufferedWriter;
import java.io.IOError;
import java.io.IOException;
import java.io.Writer;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.concurrent.CountDownLatch;
import java.util.function.IntConsumer;

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
import org.jline.terminal.impl.jni.win.WindowsAnsiWriter;
import org.jline.terminal.spi.SystemStream;
import org.jline.terminal.spi.TerminalProvider;
import org.jline.utils.InfoCmp;
import org.jline.utils.OSUtils;

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

        if (ansiPassThrough) {
            if (("ansicon").equals(System.getenv("ANSICON_DEF"))) {
                if (enableVtp(console, outMode[0])) {
                    type = type != null ? type : TYPE_WINDOWS_VTP;
                    writer = newConsoleWriter(console);
                } else {
                    type = TYPE_WINDOWS_CONEMU;
                    writer = new WinConsoleWriter(console, 1);
                }
            } else if (("conemu").equals(System.getenv("ANSICON_DEF"))) {
                type = TYPE_WINDOWS_CONEMU;
                writer = new WinConsoleWriter(console, 1);
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
                type = type != null ? type : TYPE_WINDOWS;
                writer = new WindowsAnsiWriter(new BufferedWriter(newConsoleWriter(console)));
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
        if (status != null) {
            status.close();
            status = null;
        }
        t.setDaemon(true);
        t.start();
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

    final Size size = new Size();
    final CONSOLE_SCREEN_BUFFER_INFO info = new CONSOLE_SCREEN_BUFFER_INFO();

    public Size getSize() {
        Kernel32.GetConsoleScreenBufferInfo(outConsole, info);
        size.setColumns(info.windowWidth());
        size.setRows(info.windowHeight());
        return size;

    }

    @Override
    public Size getBufferSize() {
        Kernel32.GetConsoleScreenBufferInfo(outConsole, info);
        size.setColumns(info.size.x);
        size.setRows(info.size.y);
        return size;
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

    private final char[] focus = new char[]{'\033', '[', ' '};

    private void processFocusEvent(boolean hasFocus) throws IOException {
        if (focusTracking) {
            focus[2] = hasFocus ? 'I' : 'O';
            slaveInputPipe.write(focus);
        }
    }

    private final char[] mouse = new char[]{'\033', '[', 'M', ' ', ' ', ' '};

    private void processMouseEvent(Kernel32.MOUSE_EVENT_RECORD mouseEvent) throws IOException {
        int dwEventFlags = mouseEvent.eventFlags;
        int dwButtonState = mouseEvent.buttonState;
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

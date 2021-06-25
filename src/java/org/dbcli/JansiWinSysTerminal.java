package org.dbcli;


import org.fusesource.jansi.internal.Kernel32;
import org.fusesource.jansi.internal.Kernel32.*;
import org.jline.keymap.KeyMap;
import org.jline.reader.impl.LineReaderImpl;
import org.jline.terminal.Cursor;
import org.jline.terminal.Size;
import org.jline.terminal.impl.AbstractWindowsTerminal;
import org.jline.terminal.impl.jansi.win.WindowsAnsiWriter;
import org.jline.utils.InfoCmp;
import org.jline.utils.OSUtils;
import org.jline.utils.Status;

import java.io.BufferedWriter;
import java.io.IOError;
import java.io.IOException;
import java.io.Writer;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;
import java.util.function.IntConsumer;

import static org.fusesource.jansi.internal.Kernel32.*;

public final class JansiWinSysTerminal extends AbstractWindowsTerminal {
    private static final long consoleOut = GetStdHandle(STD_OUTPUT_HANDLE);
    private static final long consoleIn = GetStdHandle(STD_INPUT_HANDLE);

    public static JansiWinSysTerminal createTerminal(String name, String type, boolean ansiPassThrough, Charset encoding, int codepage, boolean nativeSignals, SignalHandler signalHandler, boolean paused) throws IOException {
        Writer writer;
        int[] mode = new int[1];
        if (Kernel32.GetConsoleMode(consoleOut, mode) == 0) {
            throw new IOException("Failed to get console mode: " + getLastErrorMessage());
        }
        if (type == null) {
            if (Kernel32.SetConsoleMode(consoleOut, mode[0] | AbstractWindowsTerminal.ENABLE_VIRTUAL_TERMINAL_PROCESSING) != 0)
                type = TYPE_WINDOWS_VTP;
            else if (OSUtils.IS_CONEMU)
                type = TYPE_WINDOWS_CONEMU;
            else
                type = TYPE_WINDOWS;
        }
        if (ansiPassThrough) {
            type = TYPE_WINDOWS;
            if (("ansicon").equals(System.getenv("ANSICON_DEF")))
                writer = new BufferedWriter(OSUtils.IS_CONEMU ? new JansiWinConsoleWriter() : new ConEmuWriter(), 65536);
            else
                writer = new JansiWinConsoleWriter();
        } else {
            if (type.equals(TYPE_WINDOWS_VTP) || OSUtils.IS_CONEMU) {
                writer = new JansiWinConsoleWriter();
            } else if (("ansicon").equals(System.getenv("ANSICON_DEF"))) {
                type = TYPE_WINDOWS;
                writer = new BufferedWriter(OSUtils.IS_CONEMU ? new JansiWinConsoleWriter() : new ConEmuWriter(), 65536);
            } else {
                writer = new WindowsAnsiWriter(new BufferedWriter(new JansiWinConsoleWriter()));
            }
        }
        if (Kernel32.GetConsoleMode(consoleIn, mode) == 0) {
            throw new IOException("Failed to get console mode: " + getLastErrorMessage());
        }
        JansiWinSysTerminal terminal = new JansiWinSysTerminal(writer, name, type, encoding, codepage, nativeSignals, signalHandler);
        // Start input pump thread
        if (!paused) {
            terminal.resume();
        }
        return terminal;
    }

    @Override
    public Status getStatus() {
        return null;
    }


    public static boolean isWindowsConsole() {
        int[] mode = new int[1];
        return Kernel32.GetConsoleMode(consoleOut, mode) != 0 && Kernel32.GetConsoleMode(consoleIn, mode) != 0;
    }

    public static boolean isConsoleOutput() {
        int[] mode = new int[1];
        return Kernel32.GetConsoleMode(consoleOut, mode) != 0;
    }

    public static boolean isConsoleInput() {
        int[] mode = new int[1];
        return Kernel32.GetConsoleMode(consoleIn, mode) != 0;
    }

    JansiWinSysTerminal(Writer writer, String name, String type, Charset encoding, int codepage, boolean nativeSignals, SignalHandler signalHandler) throws IOException {
        super(writer, name, type, encoding, codepage, nativeSignals, signalHandler);
        this.status = null;
        t.setDaemon(true);
        t.start();
    }

    @Override
    protected int getConsoleMode() {
        int[] mode = new int[1];
        if (Kernel32.GetConsoleMode(consoleIn, mode) == 0) {
            return -1;
        }
        return mode[0];
    }

    @Override
    protected void setConsoleMode(int mode) {
        Kernel32.SetConsoleMode(consoleIn, mode);
    }

    final CONSOLE_SCREEN_BUFFER_INFO info = new CONSOLE_SCREEN_BUFFER_INFO();
    final Size size = new Size();
    final Cursor cursor = new Cursor(0, 0);

    public Size getSize() {
        Kernel32.GetConsoleScreenBufferInfo(consoleOut, info);
        size.setColumns(info.windowWidth());
        size.setRows(info.windowHeight());
        return size;
    }

    @Override
    public Size getBufferSize() {
        Kernel32.GetConsoleScreenBufferInfo(consoleOut, info);
        size.setColumns(info.size.x);
        size.setRows(info.size.y);
        return size;
    }

    private volatile long prevTime = 0;
    private volatile int pasteCount = 0;
    private volatile char lastChar;
    private volatile boolean enablePaste = true;
    final char[] bp = KeyMap.translate(LineReaderImpl.BRACKETED_PASTE_BEGIN).toCharArray();
    final char[] ep = KeyMap.translate(LineReaderImpl.BRACKETED_PASTE_END).toCharArray();
    final short bpl = (short) (bp.length - 1);
    final short epl = (short) (ep.length - 1);
    final short START_POS = 1;
    final String tab = "    ";
    short beginIdx = START_POS;
    short endIdx = START_POS;

    final void processChar(char c) throws IOException {
        super.processInputChar(c);
    }

    public void enablePaste(boolean enabled) {
        enablePaste = enabled;
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
            //insert one more space to bypass the completor's detection if the first pasted char is tab
            if (c == '\t') {
                this.slaveInputPipe.write(' ');
                return;
            }
        } else if (pasteCount > 0) {
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

    Thread t = new Thread(() -> {
        while (true) {
            try {
                Thread.sleep(32);
                if (prevTime == 0 || pasteCount == 0 || paused()) continue;
                //If no more input after 128+ ms, leave the paste mode (Assume that consuming a input char costs 300us)
                if (System.currentTimeMillis() - prevTime >= 128 + pasteCount * 0.3) {
                    if (endIdx != epl) {
                        slaveInputPipe.write(LineReaderImpl.BRACKETED_PASTE_END);
                        if (lastChar == '\r' || lastChar == '\n') processChar('\n');
                        prevTime = 0;
                    }
                    pasteCount = 0;
                }
            } catch (Exception e) {
            }
        }
    });


    protected boolean processConsoleInput() throws IOException {
        INPUT_RECORD[] events;
        if (consoleIn != INVALID_HANDLE_VALUE
                && WaitForSingleObject(consoleIn, 100) == 0) {
            events = readConsoleInputHelper(consoleIn, 1, false);
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

    private char[] focus = new char[]{'\033', '[', ' '};

    private void processFocusEvent(boolean hasFocus) throws IOException {
        if (focusTracking) {
            focus[2] = hasFocus ? 'I' : 'O';
            slaveInputPipe.write(focus);
        }
    }

    private char[] mouse = new char[]{'\033', '[', 'M', ' ', ' ', ' '};

    private void processMouseEvent(Kernel32.MOUSE_EVENT_RECORD mouseEvent) throws IOException {
        int dwEventFlags = mouseEvent.eventFlags;
        int dwButtonState = mouseEvent.buttonState;
        if (tracking == MouseTracking.Off
                || tracking == MouseTracking.Normal && dwEventFlags == Kernel32.MOUSE_EVENT_RECORD.MOUSE_MOVED
                || tracking == MouseTracking.Button && dwEventFlags == Kernel32.MOUSE_EVENT_RECORD.MOUSE_MOVED && dwButtonState == 0) {
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
        if (GetConsoleScreenBufferInfo(consoleOut, info) == 0) {
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

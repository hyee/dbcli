package org.dbcli;

import jline.internal.NonBlockingInputStream;
import org.fusesource.jansi.internal.Kernel32.INPUT_RECORD;
import org.fusesource.jansi.internal.Kernel32.KEY_EVENT_RECORD;
import org.fusesource.jansi.internal.WindowsSupport;

import java.awt.event.KeyEvent;
import java.io.IOException;
import java.io.InputStream;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.HashMap;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.TimeUnit;


public class WindowsInputReader extends NonBlockingInputStream {
    private static HashMap<Integer, byte[]> keyEvents = new HashMap();
    // support some C1 control sequences: ALT + [@-_] (and [a-z]?) => ESC <ascii>
    // http://en.wikipedia.org/wiki/C0_and_C1_control_codes#C1_set
    final int altState = KEY_EVENT_RECORD.LEFT_ALT_PRESSED | KEY_EVENT_RECORD.RIGHT_ALT_PRESSED;
    // Pressing "Alt Gr" is translated to Alt-Ctrl, hence it has to be checked that Ctrl is _not_ pressed,
    // otherwise inserting of "Alt Gr" codes on non-US keyboards would yield errors
    final int ctrlState = KEY_EVENT_RECORD.LEFT_CTRL_PRESSED | KEY_EVENT_RECORD.RIGHT_CTRL_PRESSED;

    final int shiftState = KEY_EVENT_RECORD.SHIFT_PRESSED;

    final int funcState = 64;
    byte[] buf = null;
    int bufIdx = 0;

    //Escape information: https://www.novell.com/documentation/extend5/Docs/help/Composer/books/TelnetAppendixB.html
    static {
        keyEvents.put(KeyEvent.VK_ESCAPE, "\u001b".getBytes());
        keyEvents.put(KeyEvent.VK_F1, "\u001bOP".getBytes());
        keyEvents.put(KeyEvent.VK_F2, "\u001bOQ".getBytes());
        keyEvents.put(KeyEvent.VK_F3, "\u001bOR".getBytes());
        keyEvents.put(KeyEvent.VK_F4, "\u001bOS".getBytes());
        keyEvents.put(KeyEvent.VK_F5, "\u001b[15~".getBytes());
        keyEvents.put(KeyEvent.VK_F6, "\u001b[17~".getBytes());
        keyEvents.put(KeyEvent.VK_F7, "\u001b[18~".getBytes());
        keyEvents.put(KeyEvent.VK_F8, "\u001b[19~".getBytes());
        keyEvents.put(KeyEvent.VK_F9, "\u001b[20~".getBytes());
        keyEvents.put(KeyEvent.VK_F10, "\u001b[21~".getBytes());
        keyEvents.put(KeyEvent.VK_F11, "\u001b[23~".getBytes());
        keyEvents.put(KeyEvent.VK_F12, "\u001b[24~".getBytes());
        keyEvents.put(KeyEvent.VK_HOME, "\u001B[1~".getBytes());
        keyEvents.put(KeyEvent.VK_INSERT, "\u001b[2~".getBytes());
        keyEvents.put(KeyEvent.VK_DELETE, "\u001B[3~".getBytes());
        keyEvents.put(KeyEvent.VK_END, "\u001B[4~".getBytes());
        keyEvents.put(KeyEvent.VK_PAGE_UP, "\u001B[5~".getBytes());
        keyEvents.put(KeyEvent.VK_PAGE_DOWN, "\u001B[6~".getBytes());
        keyEvents.put(KeyEvent.VK_UP, "\u001b[A".getBytes());
        keyEvents.put(KeyEvent.VK_DOWN, "\u001b[B".getBytes());
        keyEvents.put(KeyEvent.VK_RIGHT, "\u001b[C".getBytes());
        keyEvents.put(KeyEvent.VK_LEFT, "\u001b[D".getBytes());
        keyEvents.put(KeyEvent.VK_BACK_SPACE, "\u0008".getBytes());
        keyEvents.put(KeyEvent.VK_TAB, "\u0009".getBytes());
    }

    private int ch = -2;             // Recently read character
    private volatile boolean isShutdown = false;
    private IOException exception = null;
    private ArrayBlockingQueue<INPUT_RECORD[]> inputQueue;
    private volatile INPUT_RECORD[] peeker;
    private ByteBuffer inputBuff = ByteBuffer.allocateDirect(255);
    private boolean nonBlockingEnabled;
    private int ctrlFlags;
    private InputStream in;


    public WindowsInputReader() {
        super(System.in, false);
        this.nonBlockingEnabled = true;
        inputQueue = new ArrayBlockingQueue(32767);
        inputBuff.order(ByteOrder.nativeOrder());
        Thread t = new Thread(this);
        t.setName("NonBlockingInputStreamThread");
        t.setDaemon(true);
        t.start();
    }

    public boolean isNonBlockingEnabled() {
        return nonBlockingEnabled;
    }

    public void clear() {
        inputQueue.clear();
    }

    /**
     * Shuts down the thread that is handling blocking I/O. Note that if the
     * thread is currently blocked waiting for I/O it will not actually
     * shut down until the I/O is received.  Shutting down the I/O thread
     * does not prevent this class from being used, but causes the
     * non-blocking methods to fail if called and causes }
     * to return false.
     */
    public synchronized void shutdown() {
        if (!isShutdown) {
            isShutdown = true;
            notify();
        }
    }


    @Override
    public void close() throws IOException {
        /*
         * The underlying input stream is closed first. This means that if the
         * I/O thread was blocked waiting on input, it will be woken for us.
         */
        inputQueue = null;
        shutdown();
    }

    @Override
    public int read() throws IOException {
        int c = read(0L, false);
        //System.out.println(c);
        return c;
    }

    /**
     * Peeks to see if there is a byte waiting in the input stream without
     * actually consuming the byte.
     *
     * @param timeout The amount of time to wait, 0 == forever
     * @return -1 on eof, -2 if the timeout expired with no available input
     * or the character that was read (without consuming it).
     */
    public int peek(long timeout) throws IOException {
        return read(timeout, true);
    }

    /**
     * Attempts to read a character from the input stream for a specific
     * period of time.
     *
     * @param timeout The amount of time to wait for the character
     * @return The character read, -1 if EOF is reached, or -2 if the
     * read timed out.
     */
    public int read(long timeout) throws IOException {
        return read(timeout, false);
    }

    @Override
    public int read(byte[] b, int off, int len) throws IOException {
        if (b == null) {
            throw new NullPointerException();
        } else if (off < 0 || len < 0 || len > b.length - off) {
            throw new IndexOutOfBoundsException();
        } else if (len == 0) {
            return 0;
        }
        int c = read();

        if (c == -1) {
            return -1;
        }
        b[off] = (byte) c;
        return 1;
    }


    /**
     * Attempts to read a character from the input stream for a specific
     * period of time.
     *
     * @param timeout The amount of time to wait for the character(<0: without wait, 0: always wait, >0: wait within <timeout> milliseconds)
     * @return The character read, -1 if EOF is reached, or -2 if the read timed out.
     */
    public synchronized int read(long timeout, boolean isPeek) throws IOException {
        //System.out.println(1);
        if (buf != null && bufIdx < buf.length - 1) return (isPeek ? buf[bufIdx + 1] : buf[++bufIdx]) & 0xff;
        String c = readChar(timeout, isPeek);
        if (c == null) return -2;
        if (c == "\0") return -1;
        if (c == "\t" && readChar(-1, true) != null) buf = "    ".getBytes();
        else buf = c.getBytes();
        bufIdx = 0;
        return buf[0] & 0xff;
    }

    public int getCtrlFlags() {
        return ctrlFlags;
    }

    public String readChar(long timeout, boolean isPeek) throws IOException {
        INPUT_RECORD[] events = readRaw(timeout, isPeek);
        ctrlFlags = 0;
        if (events == null) {
            return null;
        }
        if (events.length == 0) {
            return "\0".intern();
        }
        inputBuff.clear();
        for (INPUT_RECORD event : events) {
            KEY_EVENT_RECORD keyEvent = event.keyEvent;
            // Compute the overall alt state
            ctrlFlags = ctrlFlags | keyEvent.controlKeyState;
            boolean isAlt = ((keyEvent.controlKeyState & altState) != 0) && ((keyEvent.controlKeyState & ctrlState) == 0);
            //Log.trace(keyEvent.keyDown? "KEY_DOWN" : "KEY_UP", "key code:", keyEvent.keyCode, "char:", (long)keyEvent.uchar);
            if (keyEvent.keyDown) {
                if (keyEvent.uchar > 0) {
                    if (isAlt && ((keyEvent.uchar >= '@' && keyEvent.uchar <= '_') || (keyEvent.uchar >= 'a' && keyEvent.uchar <= 'z'))) {
                        inputBuff.put((byte) '\u001B');
                    }
                    inputBuff.put((byte) keyEvent.uchar);
                } else if (keyEvents.containsKey(Integer.valueOf(keyEvent.keyCode))) {
                    ctrlFlags = ctrlFlags | funcState;
                    for (int k = 0; k < keyEvent.repeatCount; k++) {
                        if (isAlt) {
                            inputBuff.put((byte) '\u001B');
                        }
                        inputBuff.put(keyEvents.get(Integer.valueOf(keyEvent.keyCode)));
                    }
                }

            } else {
                // key up event
                // support ALT+NumPad input method
                if (keyEvent.keyCode == 0x12/*VK_MENU ALT key*/ && keyEvent.uchar > 0) {
                    inputBuff.put((byte) keyEvent.uchar);
                }
            }
        }
        if (inputBuff.position() > 0) {
            inputBuff.flip();
            //System.out.println(inputBuff.remaining()+","+inputBuff.position());
            buf = new byte[inputBuff.remaining()];
            inputBuff.get(buf);
            bufIdx = 0;
            //System.out.println(new String(buf)+","+buf[buf.length-1]+","+buf[0]);
            return new String(buf).intern();
        }
        return readChar(timeout, isPeek);
    }


    public synchronized INPUT_RECORD[] readRaw(long timeout, boolean isPeek) throws IOException {
        INPUT_RECORD[] c = peeker;
        if (c != null) {
            peeker = null;
            return c;
        }
        if (exception != null) throw exception;
        try {
            c = timeout < 0 ? inputQueue.poll() : (timeout == 0 ? inputQueue.take() : inputQueue.poll(timeout, TimeUnit.MILLISECONDS));
            if (c != null && c.length == 1 && c[0] != null && c[0].keyEvent.keyDown) {
                INPUT_RECORD[] c1 = inputQueue.poll();
                if (c1 != null && c1.length > 0) c = new INPUT_RECORD[]{c[0], c1[0]};
            }
            if (isPeek) peeker = c;
            return c;
        } catch (InterruptedException e) {
            return new INPUT_RECORD[0];
        }
    }

    //@Override
    public void run() {
        exception = null;
        try {
            while (!isShutdown) {
                inputQueue.put(WindowsSupport.readConsoleInput(1));
            }
        } catch (IOException e) {
            exception = e;
        } catch (Exception e1) {
            exception = new IOException(e1.getMessage());
        }
    }

    public synchronized void writeInput(INPUT_RECORD[] input) throws Exception {
        inputQueue.put(input);
    }

    public void writeInput(String input) throws Exception {
        int prev = 0;
        for (byte b : input.getBytes()) {
            if ((b == 10 && prev == 13) || (b == 13 && prev == 10)) continue;
            INPUT_RECORD c0 = new INPUT_RECORD();
            INPUT_RECORD c1 = new INPUT_RECORD();
            c0.keyEvent.uchar = b == 13 ? '\n' : (char) b;
            prev = b;
            c0.keyEvent.keyDown = true;
            c0.keyEvent.repeatCount = 1;
            c0.keyEvent.scanCode = 38;
            c0.keyEvent.controlKeyState = 0;
            c0.eventType = 0;
            c1.keyEvent.keyDown = false;
            c1.keyEvent.uchar = c0.keyEvent.uchar;
            c1.keyEvent.repeatCount = c0.keyEvent.repeatCount;
            c1.keyEvent.controlKeyState = c0.keyEvent.controlKeyState;
            c1.keyEvent.scanCode = c0.keyEvent.scanCode;
            inputQueue.put(new INPUT_RECORD[]{c0, c1});
        }
    }
}

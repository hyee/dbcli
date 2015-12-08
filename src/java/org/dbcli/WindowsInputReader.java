package org.dbcli;

import jline.internal.NonBlockingInputStream;
import org.fusesource.jansi.internal.Kernel32.INPUT_RECORD;
import org.fusesource.jansi.internal.Kernel32.KEY_EVENT_RECORD;
import org.fusesource.jansi.internal.WindowsSupport;

import java.awt.event.KeyEvent;
import java.io.IOException;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.Arrays;
import java.util.HashMap;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.TimeUnit;


public class WindowsInputReader extends NonBlockingInputStream {
    public static final int altState = KEY_EVENT_RECORD.LEFT_ALT_PRESSED | KEY_EVENT_RECORD.RIGHT_ALT_PRESSED;
    public static final int ctrlState = KEY_EVENT_RECORD.LEFT_CTRL_PRESSED | KEY_EVENT_RECORD.RIGHT_CTRL_PRESSED;
    public static final int shiftState = KEY_EVENT_RECORD.SHIFT_PRESSED;
    public static final int anyCtrl = altState | ctrlState | shiftState;
    public static final int funcState = 64;
    public static final int KEY_DOWN = 0;
    public static final int KEY_CODE = 1;
    public static final int KEY_CHAR = 2;
    public static final int KEY_CTRL = 3;
    public static final int KEY_REPE = 4;
    static HashMap<Object, EventCallback> eventMap = new HashMap<>();
    private static HashMap<Integer, byte[]> keyEvents = new HashMap();

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

    byte[] buf = null;
    int bufIdx = 0;
    private volatile boolean isShutdown = false;
    private IOException exception = null;
    private final static ArrayBlockingQueue<long[]> inputQueue=new ArrayBlockingQueue(32767);
    private volatile long[][] peeker;
    private ByteBuffer inputBuff = ByteBuffer.allocateDirect(255);
    private boolean nonBlockingEnabled;
    private int ctrlFlags;

    public WindowsInputReader() {
        super(System.in, false);
        inputBuff.order(ByteOrder.nativeOrder());
        this.nonBlockingEnabled = true;
        Thread t = new Thread(this);
        t.setName("NonBlockingInputStreamThread");
        t.setDaemon(true);
        t.start();
    }

    public static void listen(Object name, EventCallback c) {
        //System.out.println(name.toString()+(c==null?"null":c.toString()));
        if (eventMap.containsKey(name)) eventMap.remove(name);
        if (c != null) eventMap.put(name, c);
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
        if (buf != null && bufIdx < buf.length - 1) return (isPeek ? buf[bufIdx + 1] : buf[++bufIdx]) & 0xff;
        String c = readChar(timeout, isPeek);
        if (c == null) return -2;
        if (c.equals("\0")) return -1;
        buf = ((c.equals("\t") && readChar(10, true) != null) ? "    " : c).getBytes();
        bufIdx = 0;
        return buf[0] & 0xff;
    }

    public int getCtrlFlags() {
        return ctrlFlags;
    }

    public synchronized String readChar(long timeout, boolean isPeek) throws IOException {
        long[][] events = readRaw(timeout, isPeek);
        ctrlFlags = 0;
        if (events == null || events[0] == null) {
            return null;
        }

        if (events.length == 0) {
            return "\0".intern();
        }
        inputBuff.clear();
        for (long[] event : events) {
            // Compute the overall alt state
            ctrlFlags |= event[KEY_CTRL];
            boolean isAlt = ((event[KEY_CTRL] & altState) != 0) && ((event[KEY_CTRL] & ctrlState) == 0);
            //Log.trace(keyEvent.keyDown? "KEY_DOWN" : "KEY_UP", "key code:", keyEvent.keyCode, "char:", (long)keyEvent.uchar);
            if (event[KEY_DOWN] == 1) {
                if (event[KEY_CHAR] > 0) {
                    if (isAlt && ((event[KEY_CHAR] >= '@' && event[KEY_CHAR] <= '_') || (event[KEY_CHAR] >= 'a' && event[KEY_CHAR] <= 'z')))
                        inputBuff.put((byte) '\u001B');
                    inputBuff.put((byte) event[KEY_CHAR]);
                } else if (keyEvents.containsKey(Integer.valueOf((int) event[KEY_CODE]))) {
                    ctrlFlags |= funcState;
                    for (int k = 0; k < event[KEY_REPE]; k++) {
                        if (isAlt) inputBuff.put((byte) '\u001B');
                        inputBuff.put(keyEvents.get(Integer.valueOf((int) event[KEY_CODE])));
                    }
                }
            } else {
                // key up event
                // support ALT+NumPad input method
                if (event[KEY_CODE] == KeyEvent.VK_ALT && event[KEY_CHAR] > 0) {
                    inputBuff.put((byte) event[KEY_CHAR]);
                }
            }
        }
        if (inputBuff.position() > 0) {
            inputBuff.flip();
            //System.out.println(inputBuff.remaining()+","+inputBuff.position());
            byte[] buf = new byte[inputBuff.remaining()];
            inputBuff.get(buf);
            return new String(buf).intern();
        }
        return readChar(timeout, isPeek);
    }

    public synchronized long[][] readRaw(long timeout, boolean isPeek) throws IOException {
        long[][] c = peeker;
        if (c != null) {
            peeker = null;
            return c;
        }
        if (exception != null) throw exception;
        try {
            c = new long[][]{timeout < 0 ? inputQueue.poll() : (timeout == 0 ? inputQueue.take() : inputQueue.poll(timeout, TimeUnit.MILLISECONDS))};
            if (c[0] != null && c[0][KEY_DOWN] == 1) {
                long[] c1 = inputQueue.poll(200, TimeUnit.MILLISECONDS);
                if (c1 != null) c = new long[][]{c[0], c1};
            }
            for (long[] c0 : c) {
                //System.out.println(Arrays.toString(c0));
                if (!isPeek && c0 != null && c0[KEY_DOWN] == 1 && (//
                        (c0[KEY_CTRL] > 0 && c0[KEY_CHAR] > 0) || //
                                (c0[KEY_CODE] >= KeyEvent.VK_F1 && c0[KEY_CODE] <= KeyEvent.VK_F12 && c0[KEY_CHAR] == 0))) {
                    for (EventCallback callback : eventMap.values()) callback.interrupt(c0);
                }
            }
            if (isPeek) peeker = c;
            return c;
        } catch (InterruptedException e) {
            return new long[0][0];
        } catch (Exception e1) {
            throw new IOException(e1.getMessage());
        }
    }

    //@Override
    public void run() {
        exception = null;
        try {
            while (!isShutdown) {
                INPUT_RECORD[] input = WindowsSupport.readConsoleInput(1);
                if (input == null || input.length == 0) continue;

                for (INPUT_RECORD rec : input) {
                    //System.out.println(rec.keyEvent.toString());
                    inputQueue.put(new long[]{rec.keyEvent.keyDown ? 1 : 0, rec.keyEvent.keyCode, (long) rec.keyEvent.uchar, rec.keyEvent.controlKeyState & anyCtrl, rec.keyEvent.repeatCount});
                }
            }
        } catch (IOException e) {
            exception = e;
        } catch (Exception e1) {
            exception = new IOException(e1.getMessage());
        }
    }

    public synchronized static void writeInput(INPUT_RECORD rec) throws Exception {
        inputQueue.put(new long[]{rec.keyEvent.keyDown ? 1 : 0, rec.keyEvent.keyCode, (long) rec.keyEvent.uchar, rec.keyEvent.controlKeyState & anyCtrl, rec.keyEvent.repeatCount});
    }

    public synchronized static void writeInput(String input) throws Exception {
        int prev = 0;
        for (byte b : input.getBytes()) {
            if ((b == 10 && prev == 13) || (b == 13 && prev == 10)) continue;
            inputQueue.put(new long[]{1, 0, b == 13 ? 10 : b,b<27?ctrlState:0, 0, 1});
            inputQueue.put(new long[]{0, 0, b == 13 ? 10 : b, b<27?ctrlState:0, 1});
        }
    }
}

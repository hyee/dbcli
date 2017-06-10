package org.dbcli;

import jline.internal.NonBlockingInputStream;
import org.fusesource.jansi.internal.Kernel32.INPUT_RECORD;
import org.fusesource.jansi.internal.Kernel32.KEY_EVENT_RECORD;
import org.fusesource.jansi.internal.WindowsSupport;

import java.awt.event.KeyEvent;
import java.io.Closeable;
import java.io.IOException;
import java.lang.reflect.Field;
import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.HashMap;
import java.util.concurrent.ArrayBlockingQueue;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.CyclicBarrier;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.locks.ReentrantLock;

public class WindowsInputReader extends NonBlockingInputStream {
    public static final int altState = KEY_EVENT_RECORD.LEFT_ALT_PRESSED | KEY_EVENT_RECORD.RIGHT_ALT_PRESSED;
    public static final int ctrlState = KEY_EVENT_RECORD.LEFT_CTRL_PRESSED | KEY_EVENT_RECORD.RIGHT_CTRL_PRESSED;
    public static final int shiftState = KEY_EVENT_RECORD.SHIFT_PRESSED;
    public static final int anyCtrl = altState | ctrlState;
    public static final int funcState = 64;
    public static final int KEY_DOWN = 0;
    public static final int KEY_CODE = 1;
    public static final int KEY_CHAR = 2;
    public static final int KEY_CTRL = 3;
    public static final int KEY_REPE = 4;
    public static final int KEY_ALT = 5;
    public static final int KEY_CTL = 6;
    public static final int KEY_SFT = 7;
    private final static ArrayBlockingQueue<long[]> inputQueue = new ArrayBlockingQueue(32767);
    public static HashMap<Integer, byte[]> keyEvents = new HashMap();
    public static HashMap<Integer, String> keyCodes = new HashMap<>();

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
        keyEvents.put(KeyEvent.VK_PERIOD, "\u001bOn".getBytes());
        Field[] fields = KeyEvent.class.getDeclaredFields();
        try {
            for (Field field : fields) {
                if (field.getName().startsWith("VK_") && field.getType().getName().equals("int"))
                    keyCodes.put(field.getInt(null), field.getName().substring(3));
            }
        } catch (Exception e) {
        }
    }

    static HashMap<Object, EventCallback> eventMap = new HashMap<>();
    byte[] buf = null;
    int bufIdx = 0;
    private volatile boolean isShutdown = false;
    private IOException exception = null;
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

    public synchronized static void writeInput(INPUT_RECORD rec) throws Exception {
        inputQueue.put(new long[]{rec.keyEvent.keyDown ? 1 : 0, rec.keyEvent.keyCode, (long) rec.keyEvent.uchar, rec.keyEvent.controlKeyState & anyCtrl, rec.keyEvent.repeatCount});
    }

    public synchronized static void writeInput(String input) throws Exception {
        int prev = 0;
        for (byte b : input.getBytes()) {
            if ((b == 10 && prev == 13) || (b == 13 && prev == 10)) continue;
            inputQueue.put(new long[]{1, 0, b == 13 ? 10 : b, b < 27 ? ctrlState : 0, 0, 1});
            inputQueue.put(new long[]{0, 0, b == 13 ? 10 : b, b < 27 ? ctrlState : 0, 1});
        }
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
        int ch = read(timeout, false);
        return ch;
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
    public int read(long timeout, boolean isPeek) throws IOException {
        int ch = _read(timeout, isPeek);
        return ch;
    }

    int _read(long timeout, boolean isPeek) throws IOException {
        if (buf != null && bufIdx < buf.length - 1) return (isPeek ? buf[bufIdx + 1] : buf[++bufIdx]) & 0xff;
        String c = readChar(timeout, isPeek);
        if (c == null) return -2;
        if (c == "\0") return -1;
        buf = (c == "\t" && readChar(10, true) != null ? "    " : c).getBytes();
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
            if (event == null) continue;
            // Compute the overall alt state
            ctrlFlags |= event[KEY_CTRL];
            boolean isAlt = ((event[KEY_CTRL] & altState) != 0) && ((event[KEY_CTRL] & ctrlState) == 0);
            Integer code = Integer.valueOf((int) event[KEY_CODE]);
            //Log.trace(keyEvent.keyDown? "KEY_DOWN" : "KEY_UP", "key code:", keyEvent.keyCode, "char:", (long)keyEvent.uchar);
            if (event[KEY_DOWN] == 1) {
                //System.out.println(Arrays.toString(event)+","+KEY_CHAR+","+event[KEY_CHAR]);
                if (event[KEY_CHAR] > 0) {
                    if (isAlt && ((event[KEY_CHAR] >= '@' && event[KEY_CHAR] <= '_') || (event[KEY_CHAR] >= 'a' && event[KEY_CHAR] <= 'z')))
                        inputBuff.put((byte) '\u001B');
                    inputBuff.put((byte) event[KEY_CHAR]);
                } else if (keyEvents.containsKey(code)) {
                    ctrlFlags |= funcState;
                    for (int k = 0; k < event[KEY_REPE]; k++) {
                        if (isAlt) inputBuff.put((byte) '\u001B');
                        inputBuff.put(keyEvents.get(code));
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

    CountDownLatch lock = new CountDownLatch(1);
    ReentrantLock lock1 = new ReentrantLock();

    private void pause(boolean pause) {
        try {
            try (Closeable c = lock1::unlock) {
                lock1.lock();
                if (pause) {
                    if(inputQueue.isEmpty()) return;
                    lock = new CountDownLatch(1);
                } else {
                    lock.countDown();
                    return;
                }
            }
            lock.await();
        } catch (Exception e) {e.printStackTrace();}
    }

    public synchronized long[][] readRaw(long timeout, boolean isPeek) throws IOException {
        long[][] c = peeker;
        if (c != null && c[0] != null) {
            if (!isPeek) peeker = null;
            return c;
        }
        if (exception != null) throw exception;
        try {
            c = new long[][]{inputQueue.poll(), null};
            if (c[0] == null) {
                pause(false);
                if (timeout >= 0)
                    c[0] = timeout == 0 ? inputQueue.take() : inputQueue.poll(timeout, TimeUnit.MILLISECONDS);
                else
                    c[0] = inputQueue.poll();
            }
            if (c[0] != null && c[0][KEY_DOWN] == 1) c[1] = inputQueue.poll(100, TimeUnit.MILLISECONDS);
            if (isPeek) {
                peeker = c;
            } else {
                for (long[] c0 : c) {
                    if (c0 == null) continue;
                    //System.out.println(Arrays.toString(c0));
                    if ((c0[KEY_DOWN] == 1 || c0[KEY_CHAR] == 3) && (//
                            (c0[KEY_CTRL] > 0 && (c0[KEY_CHAR] > 0 || keyEvents.containsKey(Integer.valueOf((int) c0[KEY_CODE])))) || //
                                    (c0[KEY_SFT] > 0 && keyEvents.containsKey(Integer.valueOf((int) c0[KEY_CODE]))) ||//
                                    (c0[KEY_CODE] >= KeyEvent.VK_F1 && c0[KEY_CODE] <= KeyEvent.VK_F12 && c0[KEY_CHAR] == 0))) {
                        StringBuilder sb = new StringBuilder(32);
                        if (c0[KEY_CTL] > 0) sb.append("CTRL+");
                        if (c0[KEY_ALT] > 0) sb.append("ALT+");
                        if (c0[KEY_SFT] > 0) sb.append("SHIFT+");
                        sb.append(keyCodes.get(Integer.valueOf((int) c0[KEY_CODE])));
                        for (EventCallback callback : eventMap.values()) callback.interrupt(c0, sb.toString());
                        if (c0[0] == 2) return readRaw(timeout, isPeek);
                    }
                }
            }
            return c;
        } catch (InterruptedException e) {
            return new long[0][0];
        } catch (Exception e1) {
            e1.printStackTrace();
            throw new IOException(e1.getMessage());
        }
    }

    //@Override
    public void run() {
        exception = null;
        INPUT_RECORD[] input;
        long[] c;
        try {
            while (!isShutdown) {
                input = WindowsSupport.readConsoleInput(1);
                if ((input == null || input.length == 0)) continue;
                for (INPUT_RECORD rec : input) {
                    long uchar = rec.keyEvent.uchar;
                    if (uchar >= 65281 && uchar <= 65374) {
                        uchar -= 65248;
                    } else if (uchar == 12288) {
                        uchar = 32;
                    }
                    c = new long[]{rec.keyEvent.keyDown ? 1 : 0, rec.keyEvent.keyCode, uchar, rec.keyEvent.controlKeyState & anyCtrl, rec.keyEvent.repeatCount,//
                            (rec.keyEvent.controlKeyState & altState) > 0 ? 1 : 0, (rec.keyEvent.controlKeyState & ctrlState) > 0 ? 1 : 0, (rec.keyEvent.controlKeyState & shiftState) > 0 ? 1 : 0,};
                    inputQueue.put(c);
                    if ((c[KEY_CHAR] == 10 || c[KEY_CHAR] == 13) && c[KEY_DOWN] == 0 && c[KEY_CTRL] == 0)
                        pause(true);
                }
            }
        } catch (IOException e) {
            exception = e;
        } catch (Exception e1) {
            exception = new IOException(e1.getMessage());
        }
    }
}
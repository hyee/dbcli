package org.dbcli;

import com.sun.jna.Library;
import com.sun.jna.Memory;
import com.sun.jna.Native;
import com.sun.jna.Pointer;
import com.sun.jna.Structure;
import com.sun.jna.win32.W32APIOptions;
import org.jline.nativ.Kernel32;

import java.util.Arrays;
import java.util.List;

/**
 * One Windows console screen buffer: the handle, the value types the console API takes, and the calls
 * this package makes on it. Everything here is a mechanism - a rectangle of cells in or out, a scroll,
 * a cursor, a window position - and every method reports what the console said without deciding what
 * the writer should do about it. That is BulkCellWriter's job.
 *
 * The structure arguments are fields rather than locals. Constructing one costs ~1.3us (JNA works out
 * the native layout and allocates its memory on every construction) and a painted chunk needs four of
 * them - ~5us of pure Java-side work on a path whose whole point is to stop paying per-line overhead.
 * autoWrite/autoRead are switched off so the explicit write() at each call site is the only sync that
 * happens; nothing here is ever read back from native memory, so no read() is needed. Sharing these
 * instances is safe because every entry point is reached only from ConEmuWriter.writeConsole, which is
 * synchronized.
 */
public final class ScreenBuffer {

    // ---- the value types -------------------------------------------------------------------

    public static class COORDV extends Structure implements Structure.ByValue {
        public short X, Y;

        public COORDV() {}

        public COORDV(short x, short y) {
            X = x;
            Y = y;
        }

        @Override
        protected List<String> getFieldOrder() {
            return Arrays.asList("X", "Y");
        }
    }

    public static class RECTV extends Structure {
        public short Left, Top, Right, Bottom;

        public RECTV() {}

        public RECTV(short l, short t, short r, short b) {
            Left = l;
            Top = t;
            Right = r;
            Bottom = b;
        }

        @Override
        protected List<String> getFieldOrder() {
            return Arrays.asList("Left", "Top", "Right", "Bottom");
        }
    }

    public static class CHARINFO extends Structure {
        public char UnicodeChar;
        public short Attributes;

        public CHARINFO() {}

        @Override
        protected List<String> getFieldOrder() {
            return Arrays.asList("UnicodeChar", "Attributes");
        }
    }

    /** CONSOLE_CURSOR_INFO: a DWORD size and a BOOL visibility */
    public static class CURSORINFO extends Structure {
        public int dwSize;
        public int bVisible;

        public CURSORINFO() {}

        @Override
        protected List<String> getFieldOrder() {
            return Arrays.asList("dwSize", "bVisible");
        }
    }

    public interface K32 extends Library {
        K32 I = Native.load("kernel32", K32.class, W32APIOptions.DEFAULT_OPTIONS);

        boolean WriteConsoleOutputW(Pointer h, Pointer cells, COORDV bufferSize, COORDV bufferCoord, RECTV region);

        boolean ReadConsoleOutputW(Pointer h, Pointer cells, COORDV bufferSize, COORDV bufferCoord, RECTV region);

        boolean ScrollConsoleScreenBufferW(Pointer h, RECTV scrollRect, RECTV clipRect, COORDV destOrigin, CHARINFO fill);

        boolean SetConsoleTextAttribute(Pointer h, short attribute);

        boolean GetConsoleCursorInfo(Pointer h, CURSORINFO info);

        boolean SetConsoleCursorInfo(Pointer h, CURSORINFO info);

        boolean SetConsoleWindowInfo(Pointer h, boolean absolute, RECTV window);

        boolean SetConsoleCursorPosition(Pointer h, COORDV position);
    }

    // ---- the console -----------------------------------------------------------------------

    private final long console;
    private final Pointer h;
    /** the cursor size as the console had it when this handle was opened, -1 when unknown */
    private final short cursorSize;

    private final COORDV bufSize = noSync(new COORDV());
    private final COORDV bufCoord = noSync(new COORDV());
    private final COORDV coord = noSync(new COORDV());
    private final RECTV region = noSync(new RECTV());
    private final RECTV window = noSync(new RECTV());
    private final RECTV full = noSync(new RECTV());
    private final CHARINFO fill = noSync(new CHARINFO());
    private final CURSORINFO cursorInfo = noSync(new CURSORINFO());

    private static <T extends Structure> T noSync(T s) {
        s.setAutoWrite(false);
        s.setAutoRead(false);
        return s;
    }

    public ScreenBuffer(long console) {
        this.console = console;
        this.h = Pointer.createConstant(console);
        CURSORINFO ci = new CURSORINFO();
        cursorSize = K32.I.GetConsoleCursorInfo(h, ci) ? (short) ci.dwSize : (short) -1;
    }

    /** the handle as a number, for the trace; this is the buffer every call below addresses */
    long handle() {
        return console;
    }

    /** the console's own geometry and state, or null when the handle is not a screen buffer */
    Kernel32.CONSOLE_SCREEN_BUFFER_INFO info() {
        Kernel32.CONSOLE_SCREEN_BUFFER_INFO csbi = new Kernel32.CONSOLE_SCREEN_BUFFER_INFO();
        if (Kernel32.GetConsoleScreenBufferInfo(console, csbi) == 0) {
            return null;
        }
        return csbi;
    }

    /**
     * Lays out the rectangle the two cell transfers share: {@code columns} by {@code rows} cells read
     * from the start of {@code cells}, going to absolute buffer rows {@code top}..{@code bottom} from
     * column 0.
     */
    private void prepareRect(Memory cells, int columns, int rows, int top, int bottom) {
        region.Left = 0;
        region.Top = (short) top;
        region.Right = (short) (columns - 1);
        region.Bottom = (short) bottom;
        region.write();
        bufSize.X = (short) columns;
        bufSize.Y = (short) rows;
        bufSize.write();
        bufCoord.X = 0;
        bufCoord.Y = 0;
        bufCoord.write();
    }

    /** WriteConsoleOutputW: one rectangle of cells, no scrolling, no cursor movement */
    boolean writeRect(Memory cells, int columns, int rows, int top, int bottom) {
        prepareRect(cells, columns, rows, top, bottom);
        return K32.I.WriteConsoleOutputW(h, cells, bufSize, bufCoord, region);
    }

    /** ReadConsoleOutputW: the same rectangle, read back out of the console */
    boolean readRect(Memory cells, int columns, int rows, int top, int bottom) {
        prepareRect(cells, columns, rows, top, bottom);
        return K32.I.ReadConsoleOutputW(h, cells, bufSize, bufCoord, region);
    }

    /**
     * Moves the whole buffer up by {@code by} rows, which is what the console does itself when a
     * newline arrives on its last row; {@code fillAttr} is the attribute it uses for the rows that
     * appear at the bottom.
     */
    boolean scrollUp(int by, int bufferWidth, int bufferHeight, short fillAttr) {
        if (by <= 0) {
            return true;
        }
        fill.UnicodeChar = ' ';
        // what the console itself uses when it scrolls on a newline at the last buffer row
        fill.Attributes = fillAttr;
        fill.write();
        full.Left = 0;
        full.Top = 0;
        full.Right = (short) (bufferWidth - 1);
        full.Bottom = (short) (bufferHeight - 1);
        full.write();
        coord.X = 0;
        coord.Y = (short) (-by);
        coord.write();
        return K32.I.ScrollConsoleScreenBufferW(h, full, full, coord, fill);
    }

    /** SetConsoleWindowInfo in absolute coordinates: where the viewport sits in the buffer */
    boolean setWindow(int left, int top, int right, int bottom) {
        window.Left = (short) left;
        window.Top = (short) top;
        window.Right = (short) right;
        window.Bottom = (short) bottom;
        window.write();
        return K32.I.SetConsoleWindowInfo(h, true, window);
    }

    boolean setCursorPosition(int row, int col) {
        coord.X = (short) col;
        coord.Y = (short) row;
        coord.write();
        return K32.I.SetConsoleCursorPosition(h, coord);
    }

    /** the console's "current attribute", which the ANSI renderer reads back (ExtGetAttributes) */
    boolean setTextAttribute(short attribute) {
        return K32.I.SetConsoleTextAttribute(h, attribute);
    }

    /**
     * DECTCEM (SGR ?25h/?25l). ConEmuHk applies it with SetConsoleCursorInfo (Ansi.cpp:3308), so a
     * chunk that carries it must not simply be dropped: the pager and the dashboard hide the cursor
     * around their repaints. Only the visibility is touched - the size stays as it was found.
     */
    boolean setCursorVisible(boolean visible) {
        if (cursorSize < 0) {
            return true; // no cursor info: leave it to whatever is there
        }
        cursorInfo.dwSize = cursorSize;
        cursorInfo.bVisible = visible ? 1 : 0;
        cursorInfo.write();
        return K32.I.SetConsoleCursorInfo(h, cursorInfo);
    }
}

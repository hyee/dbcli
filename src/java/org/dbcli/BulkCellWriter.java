package org.dbcli;

import com.sun.jna.Memory;
import org.jline.nativ.Kernel32;

import java.util.Arrays;

/**
 * Writes a chunk of console text as one CHAR_INFO rectangle with a single WriteConsoleOutputW,
 * instead of handing every line to ConEmuHk's ANSI renderer (WriteProcessed3 -> ExtWriteText),
 * which costs roughly 0.21ms per line and 0.32ms per SGR - the "a big result set or a full screen
 * dashboard is slow to paint" problem on a console without ENABLE_VIRTUAL_TERMINAL_PROCESSING
 * (Windows 7 and older).
 *
 * The scope is deliberately narrow so that no ANSI state machine is reimplemented: whatever is not
 * implemented here is declined and handed to ConEmuHk's own (complete) parser.
 *   handled  : printable text, CRLF/LF/CR, wide (CJK) characters, SGR colour attributes, a leading
 *              cursor address (CUP/HVP), erase-to-end-of-line (EL), and the cursor visibility
 *              private modes. Wide characters use the COMMON_LVB_LEADING_BYTE / TRAILING_BYTE
 *              convention ConEmu's renderer leaves in the console buffer.
 *   declined : everything else - a second cursor jump in the same chunk, erase display, scrolling,
 *              OSC, tabs, true colour, a line wider than the console, surrogate pairs - write()
 *              then returns false without having touched the console.
 *
 * The rectangle is written at absolute coordinates, so scrolling and the cursor are managed here:
 * overflow scrolls the buffer once, and the cursor is left where the ANSI path would have left it.
 *
 * Off by default; DBCLI_BULK_WRITE=on enables it.
 */
public final class BulkCellWriter {

    // ConEmu's own ANSI index -> console colour bits map (Ansi.cpp: ClrMap). It is an involution,
    // so the same table converts back; using it is what makes both renderers produce equal cells.
    private static final short[] ANSI2CON = {0, 4, 2, 6, 1, 5, 3, 7};

    /**
     * ClrMap applied to a colour index: the low three bits through the table, the bright bit kept
     * where it is. Because the table is an involution this one call serves both directions, which is
     * also its trap - see ansiFrom256 for a colour index that must not be converted twice.
     */
    private static int clrMap(int colourIndex) {
        return ANSI2CON[colourIndex & 0x07] | (((colourIndex & 0x08) != 0) ? 0x08 : 0);
    }

    private static final char ESC = 27;
    private static final char BEL = 7;
    private static final short LVB_UNDERSCORE = (short) 0x8000;
    private static final short LVB_REVERSE = (short) 0x4000;
    private static final short LVB_LEADING = (short) 0x0100;
    private static final short LVB_TRAILING = (short) 0x0200;
    private static final int MAX_ARGS = 16;
    private static final int MAX_PENDING_ESCAPE = 512; // CEAnsi_MaxPrevPart in ConEmu

    /**
     * The DBCLI_BULK_* environment, read once when this class is first touched. Two of the tests run
     * on the hot path - the safe-mode test per carriage return, the trace test per chunk - so none of
     * them may look a variable up per chunk.
     */
    static final class Config {
        /** DBCLI_BULK_WRITE=on|1|true|yes|trace switches the rectangle writer on (default: off) */
        final boolean enabled;
        /**
         * DBCLI_BULK_SAFE=1 holds the writer to text, SGR, LF and CRLF: no cursor addressing, no erase
         * line, no bare CR, no full window block. Diagnostics only, to tell the two feature sets apart.
         */
        final boolean safe;
        /**
         * DBCLI_BULK_TRACE=<file>|1 logs every chunk, its decision and the console geometry; null when
         * tracing is off, so a call site tests one field.
         */
        final String traceFile;

        Config() {
            String v = System.getenv("DBCLI_BULK_WRITE");
            enabled = v != null
                    && (v.equalsIgnoreCase("on")
                            || v.equals("1")
                            || v.equalsIgnoreCase("true")
                            || v.equalsIgnoreCase("yes")
                            || v.equalsIgnoreCase("trace"));
            safe = truthy(System.getenv("DBCLI_BULK_SAFE"));
            v = System.getenv("DBCLI_BULK_TRACE");
            traceFile = !truthy(v) ? null
                    : (v.equals("1") || v.equalsIgnoreCase("on"))
                            ? System.getProperty("java.io.tmpdir", ".") + java.io.File.separator
                                    + "dbcli-bulk-trace.log"
                            : v;
        }

        /** DBCLI_BULK_SAFE and DBCLI_BULK_TRACE are on for any value but an empty one, 0 and off */
        private static boolean truthy(String v) {
            return v != null && !v.isEmpty() && !v.equals("0") && !v.equalsIgnoreCase("off");
        }
    }

    static final Config CONFIG = new Config();

    private static java.io.Writer traceOut;
    private static int traceLines;
    private static long traceSeq;

    private final ScreenBuffer screen;

    // console geometry of the current chunk
    private int width, height;
    // The base an SGR reset returns to. ConEmuHk freezes it: CEAnsi::GetDefaultTextAttr() caches the
    // console attribute statically and DisplayParm::Reset (SGR 0, Ansi.cpp:562) plus SGR 39/49
    // (Ansi.cpp:3583, 3612) read that constant. Using the *live* attribute here instead picks up
    // whatever colour the previous chunk left behind - and because the console attribute is written
    // back below, that colour then leaks into every write ConEmuHk renders itself (prompt, command
    // line, declined chunks), which shows up as a fully black screen.
    private final short defAttr;
    // the live console attribute, used where the console itself would use it (scroll fill)
    private short chunkAttr = 0x07;
    // per absolute screen row: the highest column this chunk touches in it, and the lowest one
    private int[] rowFill = new int[64];
    private int[] rowStart = new int[64];

    // the single rectangle the chunk is rendered into
    private int boxTop, boxBottom, boxWidth;
    private int cursorRow, cursorCol;

    // cursor/attribute state while walking a chunk
    private int row, col;
    private boolean hasOrigin;
    private int originRow, originCol;
    private boolean paintedSomething;

    private byte[] raw = new byte[0];
    private Memory cells;
    private final int[] args = new int[MAX_ARGS];

    private int fg, bg;
    private boolean bold, underline, reverse;
    // an SGR colour that only a 256 colour or a true colour sequence can produce: ConEmu then keeps
    // the bright bit out of the bold flag (Bold becomes an annotation only, Ansi.cpp:792)
    private boolean fg256, bg256;
    // SGR 100-107: the only thing that stops \e[1m from brightening the foreground (Ansi.cpp:789)
    private boolean brightBack;
    // ConEmu's SGR state is process wide and it re-applies it to the console whenever it renders a
    // chunk itself (Ansi.cpp:2780, 2821), so the sequences this writer consumes are replayed to it
    private final StringBuilder sgrSeen = new StringBuilder();

    private long handled, declined, rowsWritten, cellsWritten;
    private int escState;
    private int escPending;

    public BulkCellWriter(long console) {
        this.screen = new ScreenBuffer(console);
        Arrays.fill(rowStart, Integer.MAX_VALUE); // no row covered yet
        // Freeze the reset base as early as ConEmuHk does: this runs right after the DLL is loaded
        // and before a single character has been written, so both sides read the same clean attribute.
        Kernel32.CONSOLE_SCREEN_BUFFER_INFO csbi = screen.info();
        short captured = csbi == null ? 0x07 : csbi.attributes;
        // A default whose foreground and background are the same colour would make every SGR reset
        // paint invisible text, and because the console attribute is written back below, it would do
        // that to everything ConEmuHk renders afterwards too. That is never a displayable default, so
        // fall back to the ordinary light grey on black the console starts with.
        defAttr = ((captured & 0x0F) == ((captured >> 4) & 0x0F)) ? (short) 0x07 : captured;
        chunkAttr = defAttr;
    }

    // ---- public API ------------------------------------------------------------------------

    /** renders the chunk; returns false when it declined, in which case nothing was written */
    public boolean write(char[] buf, int len) {
        lastReason = null;
        lastRows = 0;
        lastRectW = 0;
        sgrSeen.setLength(0); // only the paint pass of a chunk that is actually taken fills this
        paintedCells = 0;
        measuredCells = 0;
        pendingCursorVisible = -1;
        rowBase = 0;
        painted = false;
        if (pendingEscape(buf, len)) {
            declined++;
            trace(buf, len, "declined: pending-escape", 0, 0, 0, 0);
            return false; // the previous chunk left a sequence open: ConEmu must get the rest
        }
        if (writeRect(buf, len)) {
            handled++;
            trace(buf, len, "handled", lastRows, lastRectW, boxTop, boxBottom);
            return true;
        }
        declined++;
        sgrSeen.setLength(0); // a declined chunk goes to ConEmu whole, it reads the sequences itself
        trace(
                buf,
                len,
                "declined: " + (lastReason == null ? "?" : lastReason),
                lastRows,
                lastRectW,
                boxTop,
                boxBottom);
        return false;
    }

    /**
     * The SGR sequences of the chunk that was just rendered, for ConEmuHk to replay so that its own
     * display parameters stay in step with the console attribute this writer maintains. Returns null
     * when the chunk carried none.
     */
    public String takeSgrSync() {
        if (sgrSeen.length() == 0) {
            return null;
        }
        String s = sgrSeen.toString();
        sgrSeen.setLength(0);
        return s;
    }

    private long paintedCells;
    // cells the chunk would write, counted by the measure pass: a chunk that measures zero
    // (the "\r\n" JLine sends as its own chunk after every line) only has to move the cursor
    private long measuredCells;

    private String lastReason;
    private int lastRows, lastRectW;

    private static final String BUILD = "bulk-2026-09-22-13";

    /** what the standard output handle points at, for the trace's one-time header */
    private String describeStdHandle() {
        try {
            long out = Kernel32.GetStdHandle(-11);
            Kernel32.CONSOLE_SCREEN_BUFFER_INFO csbi = new Kernel32.CONSOLE_SCREEN_BUFFER_INFO();
            if (Kernel32.GetConsoleScreenBufferInfo(out, csbi) == 0) {
                return "0x" + Long.toHexString(out) + "(no info)";
            }
            return "0x" + Long.toHexString(out) + " buffer=" + csbi.size.x + "x" + csbi.size.y
                    + " cursor=(" + csbi.cursorPosition.x + "," + csbi.cursorPosition.y + ")";
        } catch (Throwable e) {
            return "error " + e;
        }
    }

    /**
     * True when the handle this writer was handed looks like the same screen buffer the process
     * writes to normally: same size, cursor and attribute. A false here means every rectangle this
     * writer paints goes into a buffer nobody can see.
     */
    private boolean sameBufferAsStdOut() {
        try {
            long out = Kernel32.GetStdHandle(-11);
            Kernel32.CONSOLE_SCREEN_BUFFER_INFO a = screen.info();
            Kernel32.CONSOLE_SCREEN_BUFFER_INFO b = new Kernel32.CONSOLE_SCREEN_BUFFER_INFO();
            if (a == null || Kernel32.GetConsoleScreenBufferInfo(out, b) == 0) {
                return false;
            }
            return a.size.x == b.size.x && a.size.y == b.size.y
                    && a.cursorPosition.x == b.cursorPosition.x && a.cursorPosition.y == b.cursorPosition.y
                    && a.attributes == b.attributes;
        } catch (Throwable e) {
            return false;
        }
    }

    private boolean no(String why) {
        lastReason = why;
        return false;
    }

    /** one line per chunk: what it was, what was decided, and the console geometry around it */
    private void trace(char[] buf, int len, String decision, int rows, int rectW, int boxTop, int boxBottom) {
        if (CONFIG.traceFile == null || traceLines > 4000) {
            return;
        }
        try {
            if (traceOut == null) {
                traceOut = new java.io.BufferedWriter(new java.io.FileWriter(CONFIG.traceFile, false));
                traceLines = 0;
                Kernel32.CONSOLE_SCREEN_BUFFER_INFO csbi = screen.info();
                traceOut.write("== dbcli bulk writer trace " + BUILD + ", enabled="
                        + CONFIG.enabled + " safe=" + CONFIG.safe
                        + "\n   geometry: buffer="
                        + (csbi == null ? "?" : csbi.size.x + "x" + csbi.size.y)
                        + " window=" + (csbi == null ? "?" : csbi.window.left + ".." + csbi.window.right
                                + "," + csbi.window.top + ".." + csbi.window.bottom)
                        + " attr=0x" + (csbi == null ? "?" : Integer.toHexString(csbi.attributes))
                        + " defaultAttr=0x" + Integer.toHexString(defAttr)
                        + " cursor=(" + (csbi == null ? "?" : csbi.cursorPosition.x + "," + csbi.cursorPosition.y) + ")\n"
                        // Writing into the right screen buffer is the whole ball game: if the handle the
                        // writer was handed is not the buffer that is on screen, every rectangle lands
                        // somewhere invisible and no call ever reports an error.
                        + "   handles: this=0x" + Long.toHexString(screen.handle())
                        + " stdout=" + describeStdHandle()
                        + " sameBuffer=" + sameBufferAsStdOut() + "\n");
            }
            Kernel32.CONSOLE_SCREEN_BUFFER_INFO csbi = screen.info();
            StringBuilder sb = new StringBuilder(160);
            sb.append(++traceSeq).append(" len=").append(len).append(' ').append(decision);
            sb.append(" rows=").append(rows).append(" w=").append(rectW)
                    .append(" box=").append(boxTop).append("..").append(boxBottom)
                    .append(" top=").append(rectTop).append(" shift=").append(rowShift)
                    .append(" attr=0x").append(Integer.toHexString(chunkAttr))
                    .append(" painted=").append(paintedCells);
            if (csbi != null) {
                sb.append(" win=").append(csbi.window.left).append("..").append(csbi.window.right)
                        .append(',').append(csbi.window.top).append("..").append(csbi.window.bottom)
                        .append(" cur=(").append(csbi.cursorPosition.x).append(',').append(csbi.cursorPosition.y).append(')');
            }
            sb.append(" head=");
            for (int i = 0; i < len && i < 56; i++) {
                char c = buf[i];
                if (c == 27) {
                    sb.append("\\e");
                } else if (c < 0x20 || c > 0x7E) {
                    sb.append(String.format("\\x%04X", (int) c));
                } else {
                    sb.append(c);
                }
            }
            sb.append('\n');
            traceOut.write(sb.toString());
            traceLines++;
            traceOut.flush();
        } catch (Throwable ignored) {
            traceLines = 5000; // stop trying after a failure
        }
    }

    /** one bounded line of statistics, printed when the terminal closes */
    public void report() {
        if (handled == 0 && declined == 0) {
            return;
        }
        System.err.printf(
                "dbcli: bulk cell writer: %d chunk(s), %d row(s), %d cell(s) in rectangle writes; %d chunk(s) fell back to the ANSI renderer%n",
                handled, rowsWritten, cellsWritten, declined);
    }

    // ---- the writer ------------------------------------------------------------------------

    private boolean writeRect(char[] buf, int len) {
        if (len <= 0) {
            return true;
        }
        Kernel32.CONSOLE_SCREEN_BUFFER_INFO csbi = screen.info();
        if (csbi == null) {
            return no("no-console");
        }
        if (!measure(buf, len, csbi)) {
            return false;
        }
        Plan p = plan(new Geom(cursorRow, boxTop, boxBottom, boxWidth, height, winTop, winBottom,
                hasOrigin ? originRow : -1));
        rowShift = 0;
        rowBase = p.rowBase;
        cursorRow = p.anchoredCursor;
        if (p.oversize) {
            return no("oversize");
        }
        if (p.scrollBy > 0) {
            if (!screen.scrollUp(p.scrollBy, width, height, chunkAttr)) {
                return no("scroll-failed");
            }
            boxTop = p.boxTop;
            boxBottom = p.boxBottom;
            cursorRow = p.cursorRow;
            rowShift = p.scrollBy;
        }
        rectTop = p.rectTop;
        int rows = p.rows;
        int rectW = p.rectW;

        if (rows > 0 && boxWidth > 0 && measuredCells > 0) {
            long need = (long) rows * rectW * 4;
            if (raw.length < need) {
                raw = new byte[(int) need];
            }
            if (cells == null || cells.size() < need) {
                cells = new Memory(need);
            }
            // A chunk only fills the rectangle when every one of its rows is covered from column 0 to
            // boxWidth. Otherwise (a short row, an erased tail, a write that starts mid row) the base
            // has to be read back: cells the text does not cover must stay exactly as they are, which
            // is what the ANSI path leaves behind. Without the base the padding would paint the rest of
            // the row with the current colour - a visible band after a coloured line.
            boolean ragged = false;
            for (int r = Math.max(boxTop, 0); r <= boxBottom; r++) {
                if (rowStart[r] != 0 || rowFill[r] != boxWidth) {
                    ragged = true;
                    break;
                }
            }
            int paintedTop = rectTop + rowBase;
            int paintedBottom = Math.max(boxBottom, 0) + rowBase;
            boolean base = false;
            if (ragged) {
                base = screen.readRect(cells, rectW, rows, paintedTop, paintedBottom);
                if (!base) {
                    // Without the base the cells the text does not cover would keep the prefill (spaces in
                    // the current colour) and paint over live content. Hand the chunk to ConEmuHk instead.
                    return no("read-base-failed");
                }
                cells.read(0, raw, 0, (int) need);
            }
            // second walk: paint the cells (the first one validated and measured)
            if (!walk(buf, len, true, rows, rectW, base)) {
                return false;
            }
            cells.write(0, raw, 0, (int) need);
            boolean ok = screen.writeRect(cells, rectW, rows, paintedTop, paintedBottom);
            if (!ok) {
                return no("write-failed");
            }
            // Past this point the rectangle is on screen: the chunk must not be declined any more, or
            // ConEmuHk would be handed the same text a second time and paint it twice.
            painted = true;
            lastRows = rows;
            lastRectW = rectW;
            rowsWritten += rows;
            cellsWritten += (long) rows * rectW;
            // WriteConsoleOutputW sets cell attributes but not the console's "current attribute",
            // which the ANSI renderer reads back (ExtGetAttributes): keep them in sync.
            if (sgrSeen.length() > 0) {
                // the attribute only needs writing back when this chunk changed it; without SGR the
                // console already holds exactly this state, and the call is ~50us on every line
                short want = attrOf();
                // chunkAttr was read from this same console at the start of this same chunk (measure()),
                // so equal means the call below would set the value it already has. A chunk that colours
                // a column and resets it at the end of the line is that case, which is most of them.
                // attrOf() is not an exact inverse of the state seeding for the grid index bits
                // (0x100-0x200), but those never reach here as a starting attribute, and a mismatch only
                // means the call is made as before.
                if (want != chunkAttr) {
                    screen.setTextAttribute(want);
                }
            }
        }
        if (pendingCursorVisible >= 0) {
            screen.setCursorVisible(pendingCursorVisible == 1);
        }

        // place the cursor exactly where the ANSI path would have left it
        if (cursorRow >= height) {
            int by = Math.min(cursorRow - height + 1, height);
            if (screen.scrollUp(by, width, height, chunkAttr)) {
                cursorRow = height - 1;
            } else if (!painted) {
                return no("scroll-failed-2");
            }
        }
        if (cursorCol < 0 || cursorCol >= width) {
            cursorCol = 0;
        }
        boolean placed = screen.setCursorPosition(Math.max(0, cursorRow), Math.max(0, cursorCol));
        if (placed) {
            followCursor(rectTop + rowBase, rows);
        } else if (!painted) {
            return false;
        }
        return true;
    }

    // ---- the geometry decision (pure: no console call, so it can be enumerated) --------------

    /** Console shape and the rectangle the measuring walk found, as one chunk sees them. */
    static final class Geom {
        final int cursorRow;                // where the chunk leaves the cursor, before any scroll
        final int boxTop, boxBottom, boxWidth;
        final int height;                   // buffer rows
        final int winTop, winBottom;        // visible window as of the start of the chunk
        final int originRow;                // row a leading CUP addressed, -1 when the chunk had none

        Geom(int cursorRow, int boxTop, int boxBottom, int boxWidth, int height,
             int winTop, int winBottom, int originRow) {
            this.cursorRow = cursorRow;
            this.boxTop = boxTop;
            this.boxBottom = boxBottom;
            this.boxWidth = boxWidth;
            this.height = height;
            this.winTop = winTop;
            this.winBottom = winBottom;
            this.originRow = originRow;
        }
    }

    /** What {@link #plan} decides about a chunk: see the fields for the terms writeRect() uses. */
    static final class Plan {
        final int rowBase, scrollBy, anchoredCursor;
        final boolean oversize;
        final int boxTop, boxBottom, cursorRow, rectTop, rows, rectW;

        Plan(int rowBase, int scrollBy, int anchoredCursor, boolean oversize,
             int boxTop, int boxBottom, int cursorRow, int rectTop, int rows, int rectW) {
            this.rowBase = rowBase;
            this.scrollBy = scrollBy;
            this.anchoredCursor = anchoredCursor;
            this.oversize = oversize;
            this.boxTop = boxTop;
            this.boxBottom = boxBottom;
            this.cursorRow = cursorRow;
            this.rectTop = rectTop;
            this.rows = rows;
            this.rectW = rectW;
        }
    }

    /**
     * Decides where a chunk's rectangle lands, without touching the console.
     *
     * A screen row maps into the rectangle as (row - rowShift - rectTop): the rectangle already
     * carries rowBase in its top (below), rowShift is how far the scroll above moved the content
     * up and rectTop is its unshifted first row. Getting this wrong paints a chunk that
     * starts below the top of the screen into the wrong rows (or, when the rectangle is one row
     * tall, nowhere at all).
     *
     * A chunk that addresses the cursor first and then fills at least a whole screen is a screen
     * repaint: the dashboard block, a pager page. On a terminal with an alternate screen "\e[H"
     * is the visible top, but this console has no alternate screen and ConEmuHk reads it as row 0
     * of a scrollback buffer that is thousands of rows tall - not where the application means to
     * draw, and drawing there leaves the user's screen untouched. Anchor those blocks at the
     * window's top row instead.
     *
     * One scroll moves at most a whole screen, so it can only fit a chunk whose tail reaches at
     * most one screen past the buffer end. Past that the rectangle stays taller than the buffer
     * and the paint addresses rows that no longer exist; ConEmuHk scrolls that case line by line
     * and gets it right, so it has to be handed over *before* scrolling: a console this writer
     * already moved would be scrolled twice. A long result set that does fit after the one scroll
     * stays here, where this writer pays most.
     */
    static Plan plan(Geom g) {
        int rowBase = (g.originRow == 0 && g.winTop > 0 && g.boxBottom - g.boxTop + 1 >= g.winBottom - g.winTop)
                ? g.winTop
                : 0;
        int anchored = g.cursorRow + rowBase;
        int overflow = anchored + 1 - g.height; // the cursor may need a row past the buffer end
        int by = overflow > 0 ? Math.min(overflow, g.height) : 0;
        boolean oversize = by > 0 && g.boxBottom - by - Math.max(g.boxTop - by, 0) + 1 > g.height;
        int boxTop = g.boxTop - by;
        int boxBottom = g.boxBottom - by;
        int cursorRow = anchored - by;
        int rectTop = Math.max(boxTop, 0);
        return new Plan(rowBase, by, anchored, oversize, boxTop, boxBottom, cursorRow,
                rectTop, boxBottom - rectTop + 1, Math.max(g.boxWidth, 1));
    }

    // ---- measuring and painting ------------------------------------------------------------

    /**
     * Validates the chunk and measures the rectangle it needs.
     *
     * @return false when the chunk must go to the ANSI renderer
     */
    private boolean measure(char[] buf, int len, Kernel32.CONSOLE_SCREEN_BUFFER_INFO csbi) {
        width = csbi.size.x;
        height = csbi.size.y;
        chunkAttr = csbi.attributes;
        winLeft = csbi.window.left;
        winRight = csbi.window.right;
        winTop = csbi.window.top;
        winBottom = csbi.window.bottom;
        resetChunk(csbi.cursorPosition.y, csbi.cursorPosition.x, true);
        if (!walk(buf, len, false, 0, 0, false)) {
            return false;
        }
        finishChunk();
        return true;
    }

    /**
     * Walks the chunk once, either measuring it or painting it. Both passes share this code so they
     * cannot drift apart.
     *
     * @return false when the chunk contains something this writer cannot express
     */
    private boolean walk(char[] buf, int len, boolean paint, int rows, int rectW, boolean base) {
        if (paint) {
            if (!base) {
                for (int cell = 0; cell < rows * rectW; cell++) {
                    int o = cell * 4;
                    raw[o] = ' ';
                    raw[o + 1] = 0;
                    raw[o + 2] = (byte) (chunkAttr & 0xFF);
                    raw[o + 3] = (byte) ((chunkAttr >> 8) & 0xFF);
                }
            }
            resetSgrState();
            // restore the measured start
            row = hasOrigin ? originRow : startRow;
            col = hasOrigin ? originCol : startCol;
            paintedSomething = false;
        } else {
            resetSgrState();
        }
        int i = 0;
        while (i < len) {
            char c = buf[i];
            if (c == ESC) {
                int end = scanEscape(buf, i, len, paint, rows, rectW);
                if (end < 0) {
                    return no("escape");
                }
                i = end;
                continue;
            }
            if (c == '\n') {
                row++;
                col = 0;
                i++;
                continue;
            }
            if (c == '\r') {
                if (CONFIG.safe && (i + 1 >= len || buf[i + 1] != '\n')) {
                    return no("bare-cr"); // safe mode keeps to CRLF
                }
                col = 0; // a bare CR rewrites the current row, which the rectangle handles
                i++;
                continue;
            }
            if (c == BEL) {
                return no("bel"); // a bell (or an OSC terminator that lost its OSC) is not ours
            }
            if (c < 0x20 || Character.isSurrogate(c)) {
                return no("control-or-surrogate"); // tab, other control char, or a supplementary plane character
            }
            int w = charWidth(c);
            if (col + w > width) {
                return no("wide-glyph-wrap"); // the ANSI path would wrap this glyph
            }
            paintCell(row, col, c, w, paint, rows, rectW);
            col += w;
            ensureRow(row);
            if (row < boxTop) {
                boxTop = row;
            }
            if (row > boxBottom) {
                boxBottom = row;
            }
            if (col > rowFill[row]) {
                rowFill[row] = col;
            }
            int cellStart = col - w;
            if (cellStart < rowStart[row]) {
                rowStart[row] = cellStart;
            }
            if (col > boxWidth) {
                boxWidth = col;
            }
            paintedSomething = true;
            if (col >= width) {
                row++;
                col = 0;
            }
            i++;
        }
        return true;
    }

    private void paintCell(int r, int c, char ch, int w, boolean paint, int rows, int rectW) {
        if (!paint) {
            measuredCells += w; // does this chunk write any cell at all?
            return;
        }
        int rr = r - rowShift - rectTop;
        if (rr < 0 || rr >= rows) {
            return; // scrolled off the top of the rectangle
        }
        paintedCells += w;
        short attr = attrOf();
        if (w == 2) {
            // conhost stores a wide glyph in two cells: the character itself in both, the first
            // marked COMMON_LVB_LEADING_BYTE and the second COMMON_LVB_TRAILING_BYTE, which is what
            // ConEmuHk's renderer leaves in the buffer (verified cell by cell).
            putCell(rr, c, rectW, ch, (short) (attr | LVB_LEADING));
            putCell(rr, c + 1, rectW, ch, (short) (attr | LVB_TRAILING));
        } else {
            putCell(rr, c, rectW, ch, attr);
        }
    }

    /** starts a chunk: cursor at (r,c) unless the chunk addresses the cursor itself */
    private void resetChunk(int r, int c, boolean allowOrigin) {
        row = r;
        col = c;
        originRow = r;
        originCol = c;
        hasOrigin = false;
        paintedSomething = false;
        boxTop = r;
        boxBottom = r;
        boxWidth = c;
        ensureRow(r);
        // only the rows the previous chunk could have touched need clearing
        int clear = Math.min(rowFill.length, Math.max(dirtyTo, r) + 1);
        Arrays.fill(rowFill, 0, clear, 0);
        Arrays.fill(rowStart, 0, clear, Integer.MAX_VALUE);
        dirtyTo = 0;
        startRow = r;
        startCol = c;
    }

    private int startRow, startCol;
    // where the current chunk rows land inside the rectangle, see writeRect
    private int rectTop, rowShift;
    // how far a screen repaint is moved down to land on the visible window (see writeRect)
    private int rowBase;
    // set once the rectangle is on screen: from then on the chunk must not be declined
    private boolean painted;
    // the visible window as of the start of the chunk, so followCursor needs no extra call
    private int winLeft, winRight, winTop, winBottom;
    // 25h/25l seen in the chunk being written: -1 none, 1 show, 0 hide
    private int pendingCursorVisible = -1;
    private int dirtyTo;

    /** rowFill is indexed by absolute screen row, so it has to cover rows past the buffer end too */
    private void ensureRow(int r) {
        if (r >= rowFill.length) {
            int old = rowFill.length;
            int cap = old;
            while (cap <= r) {
                cap *= 2;
            }
            rowFill = Arrays.copyOf(rowFill, cap);
            rowStart = Arrays.copyOf(rowStart, cap);
            Arrays.fill(rowStart, old, cap, Integer.MAX_VALUE);
        }
        if (r > dirtyTo) {
            dirtyTo = r;
        }
    }

    private void finishChunk() {
        cursorRow = row;
        cursorCol = col;
        if (row > dirtyTo) {
            dirtyTo = row;
        }
    }

    // ---- escape sequences ------------------------------------------------------------------

    /**
     * Scans one escape sequence.
     *
     * @param paint false: only measure; true: also paint its effect
     * @return index just past the sequence, or -1 when it is something this writer cannot express
     */
    private int scanEscape(char[] buf, int at, int len, boolean paint, int rows, int rectW) {
        int i = at + 1;
        if (i >= len || buf[i] != '[') {
            return -1; // OSC, charset selection, two character escapes: not ours
        }
        i++;
        if (i < len && buf[i] == '?') {
            // private modes: the cursor visibility ones touch no cell but do change console state
            // (CEAnsi 25 -> SetConsoleCursorInfo, Ansi.cpp:3308), so they are applied rather than
            // dropped. 12 (cursor blink) has no legacy console equivalent and is ignored.
            int j = i + 1;
            int value = -1;
            while (j < len && buf[j] >= '0' && buf[j] <= '9') {
                value = (value < 0 ? 0 : value) * 10 + (buf[j] - '0');
                j++;
            }
            if (j < len && (buf[j] == 'h' || buf[j] == 'l')) {
                if (value == 25) {
                    // Remembered and applied once the chunk is actually taken: a chunk carrying nothing
                    // but this sequence paints no cell at all, so it never reaches the paint pass.
                    pendingCursorVisible = buf[j] == 'h' ? 1 : 0;
                    return j + 1;
                }
                if (value == 12) {
                    return j + 1;
                }
            }
            return -1;
        }
        int n = 0;
        int value = -1;
        boolean any = false;
        while (i < len) {
            char c = buf[i];
            if (c >= '0' && c <= '9') {
                value = (value < 0 ? 0 : value) * 10 + (c - '0');
                any = true;
                i++;
                continue;
            }
            if (c == ';') {
                if (n >= MAX_ARGS) {
                    return -1;
                }
                args[n++] = any ? value : 0;
                value = -1;
                any = false;
                i++;
                continue;
            }
            if (c == 'm') {
                if (n >= MAX_ARGS) {
                    return -1;
                }
                args[n++] = any ? value : 0;
                if (!checkArgs(n, paint)) {
                    return -1;
                }
                if (paint && sgrSeen.length() < 4096) {
                    // ConEmuHk keeps its own copy of the SGR state and re-applies it to the console
                    // whenever it renders a chunk; replaying what was consumed here keeps the two
                    // renderers from disagreeing about the colour of everything that follows
                    sgrSeen.append(buf, at, i + 1 - at);
                }
                return i + 1;
            }
            if (c == 'H' || c == 'f') {
                if (CONFIG.safe) {
                    return -1; // safe mode: cursor addressing goes to ConEmuHk
                }
                if (n >= MAX_ARGS) {
                    return -1;
                }
                args[n++] = any ? value : 0;
                return seekCursor(n) ? i + 1 : -1;
            }
            if (c == 'K') {
                if (CONFIG.safe) {
                    return -1; // safe mode: erase line goes to ConEmuHk
                }
                if (n >= MAX_ARGS) {
                    return -1;
                }
                args[n++] = any ? value : 0;
                return eraseLine(n, paint, rows, rectW) ? i + 1 : -1;
            }
            return -1; // cursor moves, erase display, scroll, OSC, ... : leave them to ConEmuHk
        }
        return -1;
    }

    /** CUP/HVP: only allowed before the chunk writes anything, so it stays one rectangle */
    private boolean seekCursor(int n) {
        if (paintedSomething) {
            return no("second-cup"); // a second rectangle would be needed; decline instead
        }
        // a missing or zero parameter means 1 (ANSI: "\e[H" is the home position)
        int r = n > 0 && args[0] > 0 ? args[0] : 1;
        int c = n > 1 && args[1] > 0 ? args[1] : 1;
        if (r > height || c > width) {
            return no("cup-range");
        }
        hasOrigin = true;
        originRow = r - 1;
        originCol = c - 1;
        row = originRow;
        col = originCol;
        if (row < boxTop) {
            boxTop = row;
        }
        if (row > boxBottom) {
            boxBottom = row;
        }
        return true;
    }

    /** EL: blank from the cursor to the end of the row (0), from the start to the cursor (1) or all (2) */
    private boolean eraseLine(int n, boolean paint, int rows, int rectW) {
        int mode = n > 0 ? args[0] : 0;
        if (mode < 0 || mode > 2) {
            return no("el-mode");
        }
        int from;
        int to;
        if (mode == 0) {
            from = col;
            to = width; // cursors own cell included, like ConEmu's nChars = size.X - cursor.X
        } else if (mode == 1) {
            from = 0;
            to = Math.min(width, col + 1); // ConEmu uses nChars = cursor.X + 1
        } else {
            from = 0;
            to = width;
        }
        short attr = attrOf();
        ensureRow(row);
        if (row < boxTop) {
            boxTop = row;
        }
        if (row > boxBottom) {
            boxBottom = row;
        }
        for (int c = from; c < to; c++) {
            if (paint) {
                int rr = row - rowShift - rectTop;
                if (rr >= 0 && rr < rows) {
                    putCell(rr, c, rectW, ' ', attr);
                    paintedCells++;
                }
            } else {
                measuredCells++;
            }
        }
        if (to > rowFill[row]) {
            rowFill[row] = to;
        }
        if (from < rowStart[row]) {
            rowStart[row] = from;
        }
        if (to > boxWidth) {
            boxWidth = to;
        }
        return true;
    }

    /** validates the SGR argument list; when {@code apply} is set the state is updated as well */
    private boolean checkArgs(int n, boolean apply) {
        for (int k = 0; k < n; k++) {
            int v = args[k];
            if (v == 38 || v == 48) {
                // 256 colour (38;5;n) and true colour (38;2;r;g;b) fold onto a 16 colour console
                // exactly like CEAnsi::DisplayParm::Apply does it; underline colour (58) declines
                if (k + 2 < n && args[k + 1] == 5 && args[k + 2] <= 255) {
                    if (apply) {
                        setColor(v == 38, ansiFrom256(args[k + 2]));
                    }
                    k += 2;
                    continue;
                }
                if (k + 4 < n && args[k + 1] == 2 && args[k + 2] <= 255 && args[k + 3] <= 255 && args[k + 4] <= 255) {
                    if (apply) {
                        setColor(v == 38, ansiFromRgb(args[k + 2], args[k + 3], args[k + 4]));
                    }
                    k += 4;
                    continue;
                }
                return false;
            }
            if (v > 107) {
                return false;
            }
            if (apply) {
                applyArg(v);
            }
        }
        return true;
    }

    private void setColor(boolean foreground, int ansi) {
        if (foreground) {
            fg = ansi;
            fg256 = true;
        } else {
            bg = ansi;
            bg256 = true;
        }
    }

    private void applyArg(int v) {
        if (v == 0) {
            // DisplayParm::Reset: colours go back to the *default* one, never to the colour the
            // previous chunk left behind (Ansi.cpp:562)
            fg = clrMap(defAttr);
            bg = clrMap(defAttr >> 4);
            bold = false;
            underline = (defAttr & LVB_UNDERSCORE) != 0;
            reverse = false;
            fg256 = false;
            bg256 = false;
            brightBack = false;
        } else if (v == 1) {
            bold = true;
        } else if (v == 2 || v == 22) {
            bold = false; // ConEmu treats faint/normal as "not bold"
        } else if (v == 4) {
            underline = true;
        } else if (v == 24) {
            underline = false;
        } else if (v == 7) {
            reverse = true;
        } else if (v == 27) {
            reverse = false;
        } else if (v >= 30 && v <= 37) {
            fg = v - 30;
            fg256 = false;
        } else if (v == 39) {
            fg = clrMap(defAttr);
            fg256 = false;
        } else if (v >= 40 && v <= 47) {
            bg = v - 40;
            bg256 = false;
            brightBack = false;
        } else if (v == 49) {
            bg = clrMap(defAttr >> 4);
            bg256 = false;
            brightBack = false;
        } else if (v >= 90 && v <= 97) {
            fg = (v - 90) | 8;
            fg256 = false;
        } else if (v >= 100 && v <= 107) {
            bg = (v - 100) | 8;
            bg256 = false;
            brightBack = true;
        }
        // 3/5/6/9/23/25/29/... have no legacy console attribute: ignored, which is what ConEmu
        // does on a console without true colour support.
    }

    /**
     * xterm 256 colour index -> console colour, exactly as CEAnsi::DisplayParm::Apply does it:
     * indices up to 15 are console colours already, the rest go through RgbMap and Far3Color.
     */
    private static int ansiFrom256(int index) {
        if (index < 16) {
            // RgbMap[0..15] is ClrMap[n & 7] | (n >= 8 ? 8 : 0), which already *is* the console colour
            // for that index, and attrOf() converts the stored index on the way out - so it has to go
            // through unchanged here, or it is converted twice: 38;5;3 -> ClrMap[3] = 6 -> ANSI2CON -> 3,
            // which paints a yellow prompt cyan.
            return index;
        }
        int color;
        if (index < 232) {
            int c = index - 16;
            color = (LEVELS[c % 6] << 16) | (LEVELS[(c / 6) % 6] << 8) | LEVELS[c / 36]; // 0x00BBGGRR
        } else {
            int v = 8 + 10 * (index - 232);
            color = (v << 16) | (v << 8) | v;
        }
        // the result is a console colour index: convert it back to the ANSI index this writer tracks
        return clrMap(conIndexFromRgb(color));
    }

    /** true colour SGR: the same conversion, with the colour given directly */
    private static int ansiFromRgb(int r, int g, int b) {
        return clrMap(conIndexFromRgb((b << 16) | (g << 8) | r));
    }

    private static final int[] LEVELS = {0x00, 0x5F, 0x87, 0xAF, 0xD7, 0xFF};
    /** Far3Color::GetStdPalette, in console colour order (0x00BBGGRR) */
    private static final int[] STD_PALETTE = {
        0x000000, 0x800000, 0x008000, 0x808000, 0x000080, 0x800080, 0x008080, 0xC0C0C0,
        0x808080, 0xFF0000, 0x00FF00, 0xFFFF00, 0x0000FF, 0xFF00FF, 0x00FFFF, 0xFFFFFF
    };

    /** Far3Color::Color2FgIndex / Color2BgIndex (ConEmuColors3.h:61, they share one body) */
    private static int conIndexFromRgb(int color) {
        for (int i = 0; i < 16; i++) {
            if (color == STD_PALETTE[i]) {
                return i;
            }
        }
        int b = (color >> 16) & 0xFF;
        int g = (color >> 8) & 0xFF;
        int r = color & 0xFF;
        int max = Math.max(b, Math.max(r, g));
        int index = ((b + 32 > max) ? 1 : 0) | ((g + 32 > max) ? 2 : 0) | ((r + 32 > max) ? 4 : 0);
        if (index == 7) {
            if (max < 32) {
                index = 0;
            } else if (max < 160) {
                index = 8;
            } else if (max > 200) {
                index = 15;
            }
        } else if (max > 220) {
            index |= 8;
        }
        return index;
    }

    /** the state an SGR reset returns to, and the state a chunk starts from */
    private void resetSgrState() {
        fg = clrMap(chunkAttr);
        bg = clrMap(chunkAttr >> 4);
        bold = false;
        underline = (chunkAttr & LVB_UNDERSCORE) != 0;
        reverse = (chunkAttr & LVB_REVERSE) != 0;
        fg256 = false;
        bg256 = false;
        brightBack = false;
    }

    private short attrOf() {
        // ConEmu derives the bright foreground bit from SGR 90-97, from \e[1m ("bold") when the
        // background is not itself bright, or from the colour index itself; a 256 colour or true
        // colour keeps its own bit and treats bold as an annotation (Ansi.cpp:780-793)
        int f = clrMap(fg) | ((bold && !fg256 && !brightBack) ? 0x08 : 0);
        int b = clrMap(bg);
        int a = f | (b << 4);
        if (underline) {
            a |= LVB_UNDERSCORE;
        }
        if (reverse) {
            // ConEmu expresses SGR 7 as COMMON_LVB_REVERSE_VIDEO, it does not swap the colour
            // nibbles (verified against the ANSI path's readback: 0x4007 for "\e[7m" on default).
            a |= LVB_REVERSE;
        }
        return (short) a;
    }

    // ---- helpers ---------------------------------------------------------------------------

    private void putCell(int r, int c, int rectW, char ch, short attr) {
        int o = (r * rectW + c) * 4;
        if (o < 0 || o + 4 > raw.length) {
            return;
        }
        raw[o] = (byte) (ch & 0xFF);
        raw[o + 1] = (byte) ((ch >> 8) & 0xFF);
        raw[o + 2] = (byte) (attr & 0xFF);
        raw[o + 3] = (byte) ((attr >> 8) & 0xFF);
    }

    /**
     * Display width of one UTF-16 unit: 2 for the East Asian Wide/Fullwidth ranges (Markus Kuhn's
     * table, as every wcwidth implementation uses), 1 otherwise.
     */
    static int charWidth(char c) {
        if (c < 0x1100) {
            return 1;
        }
        if ((c >= 0x1100 && c <= 0x115F) // Hangul Jamo
                || c == 0x2329 || c == 0x232A
                || (c >= 0x2E80 && c <= 0x303E) // CJK radicals, Kangxi
                || (c >= 0x3041 && c <= 0x33FF) // Hiragana .. CJK compatibility
                || (c >= 0x3400 && c <= 0x4DBF) // CJK ext A
                || (c >= 0x4E00 && c <= 0x9FFF) // CJK unified
                || (c >= 0xA000 && c <= 0xA4CF) // Yi
                || (c >= 0xA960 && c <= 0xA97F)
                || (c >= 0xAC00 && c <= 0xD7A3) // Hangul syllables
                || (c >= 0xF900 && c <= 0xFAFF) // CJK compatibility ideographs
                || (c >= 0xFE10 && c <= 0xFE19)
                || (c >= 0xFE30 && c <= 0xFE6F)
                || (c >= 0xFF00 && c <= 0xFF60) // fullwidth forms
                || (c >= 0xFFE0 && c <= 0xFFE6)) {
            return 2;
        }
        return 1;
    }

    /**
     * Writing cells through WriteConsoleOutputW never scrolls the console the way a real newline
     * does, so the viewport sometimes has to be moved by hand - ConEmuHk does the same for its own
     * line feeds (Ansi.cpp:2065-2072). Working from the geometry cached at the start of the chunk
     * keeps this free: the common cases need no call at all.
     */
    private void followCursor(int paintedTop, int paintedRows) {
        int newTop = viewportTop(hasOrigin, paintedTop, paintedRows, cursorRow, winTop, winBottom, height);
        if (newTop < 0) {
            return;
        }
        int windowRows = winBottom - winTop;
        if (screen.setWindow(winLeft, newTop, winRight, newTop + windowRows)) {
            winTop = newTop;
            winBottom = newTop + windowRows;
        }
    }

    /**
     * Where the viewport top has to move so the chunk just painted is readable, or -1 to leave the
     * window alone.
     *
     *   - the chunk painted at least a whole screen and addressed the cursor first: it is a screen
     *     repaint (the dashboard block, a pager screen, "snap" output), so show it from its top row.
     *     conhost follows a cursor that moves *down* but never back up, so without this the viewport
     *     stays where the last longer output left it and the repaint's first rows are never seen;
     *   - the cursor ended above the window: follow it up.
     *
     * Window height is preserved, only Top/Bottom move, and vertical only: a buffer much wider than
     * its window must not be scrolled sideways by a long line.
     */
    static int viewportTop(boolean hasOrigin, int paintedTop, int paintedRows,
                           int cursorRow, int winTop, int winBottom, int height) {
        int windowRows = winBottom - winTop;
        int newTop;
        if (hasOrigin && paintedRows >= windowRows && paintedTop < winTop) {
            newTop = paintedTop;
        } else if (cursorRow < winTop) {
            newTop = cursorRow;
        } else {
            return -1;
        }
        newTop = Math.max(0, Math.min(newTop, height - 1 - windowRows));
        return newTop == winTop ? -1 : newTop;
    }

    /**
     * Tracks escape sequences across chunk boundaries (the renderer's own parser state).
     *
     * @return true when the previous chunk left a sequence open, i.e. this chunk must go to ConEmu
     */
    private boolean pendingEscape(char[] buf, int len) {
        boolean wasPending = escState != 0;
        for (int i = 0; i < len; i++) {
            char c = buf[i];
            switch (escState) {
                case 0:
                    if (c == ESC) {
                        escState = 1;
                    }
                    break;
                case 1: // just saw ESC
                    if (c == '[') {
                        escState = 2;
                    } else if (c == ']') {
                        escState = 3;
                    } else if (c == '(' || c == ')' || c == '*' || c == '+' || c == '#' || c == ' ') {
                        escState = 5; // one more character belongs to the sequence
                    } else {
                        escState = 0;
                    }
                    break;
                case 2: // CSI: terminated by a byte in 0x40..0x7E
                    if (c >= 0x40 && c <= 0x7E) {
                        escState = 0;
                    }
                    break;
                case 3: // OSC: terminated by BEL or ST (ESC \)
                    if (c == BEL) {
                        escState = 0;
                    } else if (c == ESC) {
                        escState = 4;
                    }
                    break;
                case 4:
                    escState = (c == '\\') ? 0 : 3;
                    break;
                default:
                    escState = 0;
                    break;
            }
            if (escState == 0) {
                escPending = 0;
            } else if (++escPending > MAX_PENDING_ESCAPE) {
                escState = 0; // ConEmu drops an over-long partial sequence as well
                escPending = 0;
            }
        }
        return wasPending;
    }
}

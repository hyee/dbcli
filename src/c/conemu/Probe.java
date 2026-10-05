public class Probe {

    static { System.loadLibrary("probe"); }

    static native String build();
    static native long[] prepareConsole();
    static native boolean setCursor(int x, int y);
    static native boolean setGeometry(int bufW, int bufH, int winW, int winH);
    static native long[] writeText(char[] text, int len, int attr);
    static native long[] readCells(int x, int y, int w, int h, int convention);

    private static int failures = 0;
    private static int goodConvention = 0;

    private static void gate(String what, boolean ok, String detail) {
        System.out.println((ok ? "  ok   " : "  FAIL ") + what + (detail == null ? "" : "  " + detail));
        if (!ok) {
            failures++;
        }
    }

    private static void observe(String what) {
        System.out.println("  OBSERVE " + what);
    }

    private static String hex(long v) {
        return "0x" + Long.toHexString(v).toUpperCase();
    }

    private static String errName(long e) {
        switch ((int) e) {
            case 0:    return "ERROR_SUCCESS";
            case 1:    return "ERROR_INVALID_FUNCTION";
            case 6:    return "ERROR_INVALID_HANDLE";
            case 87:   return "ERROR_INVALID_PARAMETER";
            case 1241: return "ERROR_INCORRECT_ADDRESS";
            case 1440: return "ERROR_SCREEN_ALREADY_LOCKED";
            default:   return "code " + e;
        }
    }

    private static String cellText(long[] r, int n) {
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < n && i < r.length - 3; i++) {
            long cell = r[3 + i];
            if (i > 0) {
                sb.append(" | ");
            }
            sb.append("U+").append(String.format("%04X", cell & 0xFFFF)).append('/')
              .append(String.format("%04X", (cell >> 16) & 0xFFFF));
        }
        return sb.toString();
    }

    private static boolean cellsAre(long[] r, int count, char[] want, int attr) {
        if (r == null || r.length < 3 + count) {
            return false;
        }
        for (int i = 0; i < count; i++) {
            long cell = r[3 + i];
            if ((int) (cell & 0xFFFF) != want[i] || (int) ((cell >> 16) & 0xFFFF) != attr) {
                return false;
            }
        }
        return true;
    }

    private static long[] tryConventions(String label, int x, int y, int w, int h,
                                         char[] want, int attr) {
        long[] readable = null;
        long[] exact = null;
        for (int conv = 1; conv <= 3 && exact == null; conv++) {
            long[] r = readCells(x, y, w, h, conv);
            if (r == null) {
                observe(label + " convention " + conv + ": request refused by the probe");
                continue;
            }
            boolean holds = cellsAre(r, want.length, want, attr);
            observe(label + " convention " + conv + ": rc=" + r[0] + " err=" + errName(r[1])
                    + (r[0] == 1 ? (" cells=" + cellText(r, w)) : "")
                    + (want.length > 0 ? (" holdsExpected=" + holds) : ""));
            if (r[0] == 1) {
                if (readable == null) {
                    readable = r;
                }
                if (holds) {
                    exact = r;
                }
                if (goodConvention == 0) {
                    goodConvention = conv;
                }
            }
        }
        return exact != null ? exact : readable;
    }

    public static void main(String[] args) {
        System.out.println("vm=" + System.getProperty("java.vm.name")
                + " arch=" + System.getProperty("os.arch")
                + " dataModel=" + System.getProperty("sun.arch.data.model")
                + " version=" + System.getProperty("java.version"));
        System.out.println("native build: " + build());

        long[] c = prepareConsole();
        if (c == null) {
            System.out.println("  FAIL prepareConsole returned null");
            System.out.println("RESULT: failed");
            System.exit(1);
        }
        System.out.println("  stdout fileType=" + c[0] + " freeConsole=" + c[1]
                + " allocConsole=" + c[2] + " conoutType=" + c[3] + " (GetFileType: 0=? 1=disk 2=char 3=pipe)");
        gate("console buffer info readable", c[4] == 1,
                "buffer=" + c[5] + "x" + c[6] + " window=" + c[7] + ".." + c[8] + "," + c[9] + ".." + c[10]
                        + " attr=" + hex(c[11]) + " cursor=(" + c[12] + "," + c[13] + ")");
        System.out.println("  SetConsoleScreenBufferSize(120x2000)=" + c[14]);

        gate("SetConsoleCursorPosition accepted", setCursor(0, 20), "at (0,20)");

        char[] ascii = "Ab9".toCharArray();
        long[] wr = writeText(ascii, ascii.length, 0x1E);
        gate("WriteConsoleW of a UTF-16 char[] succeeds",
                wr != null && wr[0] == 1 && wr[1] == ascii.length,
                wr == null ? "null"
                        : ("written=" + wr[1] + " err=" + errName(wr[2]) + " buffer=" + wr[3] + "x" + wr[4]
                                + " cursorAfter=(" + wr[5] + "," + wr[6] + ") attrAfter=" + hex(wr[11])));
        long bufW = (wr != null && wr[3] > 0) ? wr[3] : c[5];
        if (wr != null && wr[0] == 1) {
            tryConventions("ascii", 0, 20, ascii.length, 1, ascii, 0x1E);
        }
        gate("at least one ReadConsoleOutputW convention works", goodConvention != 0,
                "convention=" + goodConvention);

        if (goodConvention != 0) {
            int w = (int) Math.min(120, Math.max(1, bufW));
            long[] big = readCells(0, 20, w, 5, goodConvention);
            int nonEmpty = 0;
            if (big != null && big[0] == 1) {
                for (int i = 3; i < big.length; i++) {
                    if ((big[i] & 0xFFFF) != 0) {
                        nonEmpty++;
                    }
                }
            }
            gate("block read of " + w + "x5 cells", big != null && big[0] == 1,
                    big == null ? "null" : ("err=" + errName(big[1]) + " nonEmpty=" + nonEmpty));
        }

        setCursor(0, 22);
        char[] cjk = new char[] {0x4E2D, 'A', 0x4E2D};
        writeText(cjk, cjk.length, 0x0B);
        long[] rc = tryConventions("cjk", 0, 22, 6, 1, new char[0], 0);
        if (rc != null && rc.length >= 7) {
            int c0 = (int) (rc[3] & 0xFFFF), c1 = (int) (rc[4] & 0xFFFF);
            int c2 = (int) (rc[5] & 0xFFFF), c3 = (int) (rc[6] & 0xFFFF);
            observe("leading/trailing: both cells hold U+4E2D? " + (c0 == 0x4E2D && c1 == 0x4E2D)
                    + " attrs=" + hex((rc[3] >> 16) & 0xFFFF) + "," + hex((rc[4] >> 16) & 0xFFFF)
                    + " (LVB 0x0100/0x0200 expected)"
                    + " ; then U+" + Integer.toHexString(c2).toUpperCase()
                    + ", U+" + Integer.toHexString(c3).toUpperCase());
        }

        setCursor(0, 24);
        char[] nul = new char[] {'x', 0, 'y'};
        long[] rn = writeText(nul, nul.length, 0x07);
        observe("NUL inside a write: rc=" + (rn == null ? "null" : rn[0])
                + " written=" + (rn == null ? -1 : rn[1])
                + " err=" + (rn == null ? "-" : errName(rn[2])));
        if (rn != null && rn[0] == 1) {
            tryConventions("nul", 0, 24, nul.length, 1, new char[0], 0);
        }

        setCursor(0, 26);
        char[] nl = "ab\ncd".toCharArray();
        long[] rn2 = writeText(nl, nl.length, 0x07);
        observe("bare LF in a write: rc=" + (rn2 == null ? "null" : rn2[0])
                + " written=" + (rn2 == null ? -1 : rn2[1])
                + (rn2 == null ? "" : " cursorAfter=(" + rn2[5] + "," + rn2[6] + ")"));
        if (rn2 != null && rn2[0] == 1 && goodConvention != 0) {
            long[] two = readCells(0, 26, 8, 2, goodConvention);
            if (two != null && two[0] == 1) {
                StringBuilder sb = new StringBuilder("where a bare LF puts the text: \"");
                for (int i = 0; i < 16; i++) {
                    if (i == 8) sb.append("\" \"");
                    long cell = two[3 + i] & 0xFFFF;
                    sb.append(cell == 0 ? ' ' : (char) cell);
                }
                observe(sb.append("\" (rows 26,27)").toString());
            }
        }

        if (setGeometry(200, 400, 100, 30)) {
            setCursor(0, 10);
            StringBuilder lb = new StringBuilder();
            for (int i = 0; i < 150; i++) lb.append((char) ('0' + i % 10));
            char[] longLine = lb.toString().toCharArray();
            long[] rl = writeText(longLine, longLine.length, 0x1E);
            observe("150 columns into a 100-wide window (buffer 200): rc="
                    + (rl == null ? "null" : rl[0]) + " written=" + (rl == null ? -1 : rl[1])
                    + " buffer=" + (rl == null ? -1 : rl[3]) + "x" + (rl == null ? -1 : rl[4])
                    + " cursorAfter=(" + (rl == null ? -1 : rl[5]) + "," + (rl == null ? -1 : rl[6]) + ")"
                    + " window=" + (rl == null ? -1 : rl[7]) + ".." + (rl == null ? -1 : rl[8]) + ","
                    + (rl == null ? -1 : rl[9]) + ".." + (rl == null ? -1 : rl[10]));
            if (rl != null && rl[0] == 1 && goodConvention != 0) {
                long[] rr = readCells(0, 10, 200, 3, goodConvention);
                if (rr != null && rr[0] == 1) {
                    for (int row = 0; row < 3; row++) {
                        StringBuilder line = new StringBuilder();
                        int first = -1, last = -1;
                        for (int col = 0; col < 200; col++) {
                            long ch = rr[3 + row * 200 + col] & 0xFFFF;
                            boolean filled = ch != 0 && ch != ' ';
                            if (filled) {
                                if (first < 0) first = col;
                                last = col;
                            }
                            if (col >= 96 && col <= 103) line.append(filled ? (char) ch : '.');
                        }
                        observe("row " + (10 + row) + ": cols 96..103 = \"" + line + "\" span "
                                + first + ".." + last);
                    }
                } else {
                    observe("row read failed: err=" + (rr == null ? "null" : errName(rr[1])));
                }
            }

            setCursor(0, 20);
            char[] multi = (lb.toString() + "\r\nshort").toCharArray();
            long[] rm = writeText(multi, multi.length, 0x07);
            if (rm != null && rm[0] == 1 && goodConvention != 0) {
                long[] mr = readCells(0, 20, 200, 3, goodConvention);
                if (mr != null && mr[0] == 1) {
                    for (int row = 0; row < 3; row++) {
                        int first = -1, last = -1;
                        for (int col = 0; col < 200; col++) {
                            long ch = mr[3 + row * 200 + col] & 0xFFFF;
                            if (ch != 0 && ch != ' ') {
                                if (first < 0) first = col;
                                last = col;
                            }
                        }
                        observe("multi-row write, row " + (20 + row) + ": span " + first + ".." + last);
                    }
                }
            }
            setGeometry(200, 400, 100, 30);
        } else {
            observe("cannot shape a wide buffer with a narrow window: nothing to measure");
        }

        if (setGeometry(200, 400, 100, 30) && goodConvention != 0) {
            final char wide = (char) 0x3042;
            final char bs = 8;
            char[][] bsCases = {
                { wide, bs, 'X' },
                { wide, bs, bs, 'X' },
                { wide, 'a', bs, 'X' },
                { wide, 'a', bs, bs, 'X' },
                { 'a', wide, bs, 'X' },
                { wide, bs, bs, bs, 'X' },
            };
            String[] bsNames = { "wide BS X", "wide BS BS X", "wide a BS X",
                                 "wide a BS BS X", "a wide BS X", "wide BS BS BS X" };
            observe("geometry for the backspace block: buffer 200x400, window 100x30");
            for (int i = 0; i < bsCases.length; i++) {
                final int row = 2 + i;
                setCursor(0, row);
                StringBuilder steps = new StringBuilder();
                for (int k = 0; k < bsCases[i].length; k++) {
                    char[] one = { bsCases[i][k] };
                    long[] r = writeText(one, 1, 0x07);
                    long[] cells = readCells(0, row, 8, 1, goodConvention);
                    steps.append("\n        unit ").append(k).append(" -> ").append(name(bsCases[i][k]))
                         .append(": rc=").append(r == null ? "null" : String.valueOf(r[0]))
                         .append(" written=").append(r == null ? "-" : String.valueOf(r[1]))
                         .append(" cursor=").append(r == null ? "-" : "(" + r[5] + "," + r[6] + ")")
                         .append(" cells=").append(cells == null || cells[0] != 1 ? "read failed"
                                 : cellText(cells, 8));
                }
                observe("row " + row + " [" + bsNames[i] + "], unit by unit:" + steps);
                setCursor(0, row + 20);
                long[] r = writeText(bsCases[i], bsCases[i].length, 0x07);
                long[] cells = readCells(0, row + 20, 8, 1, goodConvention);
                observe("row " + (row + 20) + " [" + bsNames[i] + "], one write:"
                        + " rc=" + (r == null ? "null" : String.valueOf(r[0]))
                        + " written=" + (r == null ? "-" : String.valueOf(r[1]))
                        + " cursor=" + (r == null ? "-" : "(" + r[5] + "," + r[6] + ")")
                        + " cells=" + (cells == null || cells[0] != 1 ? "read failed" : cellText(cells, 8)));
            }

            setCursor(0, 12);
            char[] pair = { wide };
            writeText(pair, pair.length, 0x07);
            setCursor(1, 12);
            char[] over = { 'X' };
            long[] rw = writeText(over, over.length, 0x07);
            long[] cells = (rw != null && rw[0] == 1) ? readCells(0, 12, 8, 1, goodConvention) : null;
            observe("row 12 [wide, cursor forced to col 1, X]"
                    + (rw == null ? " write null" : " written=" + rw[1] + " cursorAfter=(" + rw[5] + "," + rw[6] + ")")
                    + "  cells=" + ((cells != null && cells[0] == 1) ? cellText(cells, 8) : "read failed"));

            setCursor(0, 14);
            char[] astral = new char[] { (char) 0xD83D, (char) 0xDE00 };
            long[] ra = writeText(astral, astral.length, 0x07);
            long[] ac = (ra != null && ra[0] == 1) ? readCells(0, 14, 4, 1, goodConvention) : null;
            observe("row 14 [U+1F600 written as a surrogate pair]"
                    + (ra == null ? " write null" : " written=" + ra[1] + " cursorAfter=(" + ra[5] + "," + ra[6] + ")")
                    + "  cells=" + ((ac != null && ac[0] == 1) ? cellText(ac, 4) : "read failed")
                    + "  (a surviving pair reads D83D then DE00; the lossy read repeats the first unit)");
            observe("(a trailing cell is 0x0200, a leading one 0x0100; a lone glyph is neither)");
        }

        System.out.println(failures == 0 ? "RESULT: ok" : "RESULT: failed (" + failures + ")");
        System.exit(failures == 0 ? 0 : 1);
    }

    private static String name(char c) {
        if (c == 8) {
            return "BS";
        }
        if (c == 0x3042) {
            return "wide";
        }
        return "'" + c + "'";
    }
}
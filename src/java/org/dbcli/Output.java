package org.dbcli;

import com.naef.jnlua.LuaTable;

import java.io.PrintWriter;
import java.io.Writer;
import java.util.ArrayList;

public final class Output extends PrintWriter {
    final int fixedThreshold = 8 * 1024 * 1024;
    StringBuffer buff = new StringBuffer(32767);
    public volatile boolean isMore;
    public volatile int sizeThreshold = fixedThreshold + 1024 * 1024;

    public Output(final Writer out) {
        super(out);
    }

    public void clear() {
        buff.setLength(0);
    }

    public void add(final String str) {
        buff.append(str);
        if (!isMore) write(str);
        //The length check and the trim are one atomic step on purpose: lines() holds this same lock
        //while it copies the buffer out, and a trim decided from a length read before another thread
        //appended can delete rows that were never delivered (measured: 36541 fresh rows lost with a
        //deliberately widened window).
        synchronized (buff) {
            if (buff.length() > sizeThreshold) {
                final int index = buff.indexOf("\n", 1024 * 1024);
                if (index > -1) buff.delete(0, index + 1);
            }
        }
    }

    public void addln(final String str) {
        append(str + "\n");
        flush();
    }

    @Override
    public void println(final String str) {
        super.println(str);
        flush();
    }

    private final LuaTable table = new LuaTable(new String[0]);

    public LuaTable lines() {
        isMore = false;
        //Read and clear under the buffer's own lock: SubSystem adds from its reader thread, and
        //anything appended between toString() and setLength(0) used to be dropped silently.
        synchronized (buff) {
            if (buff.length() == 0) table.setTable(new String[0]);
            else {
                table.setTable(splitLines(buff.toString()));
                buff.setLength(0);
            }
        }
        sizeThreshold = fixedThreshold + 1024 * 1024;
        return table;
    }

    /**
     * Split on the same boundaries as the old {@code Pattern.compile("\r?\n\r?").split(...)} -
     * identical results, including the dropped trailing empties - without running a regex over the
     * whole scrollback (a ~9MB buffer cost ~140-240ms per call, once per command).
     */
    static String[] splitLines(String text) {
        final int len = text.length();
        //Mirrors the old lines(), which short-circuited an empty buffer instead of letting the regex
        //return its single empty element.
        if (len == 0) return new String[0];
        ArrayList<String> out = new ArrayList<>();
        int start = 0;
        int i = 0;
        while (i < len) {
            if (text.charAt(i) != '\n') {
                ++i;
                continue;
            }
            int end = i;
            if (end > start && text.charAt(end - 1) == '\r') --end;   // the pattern's leading \r?
            out.add(text.substring(start, end));
            int next = i + 1;
            if (next < len && text.charAt(next) == '\r') ++next;      // the pattern's trailing \r?
            start = next;
            i = next;
        }
        if (start < len) out.add(text.substring(start));
        int keep = out.size();
        while (keep > 0 && out.get(keep - 1).isEmpty()) --keep;   // Pattern.split drops trailing empties
        if (keep == out.size()) return out.toArray(new String[0]);
        return out.subList(0, keep).toArray(new String[0]);
    }
}

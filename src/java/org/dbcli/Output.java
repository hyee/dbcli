package org.dbcli;

import java.io.PrintWriter;
import java.io.Writer;
import java.util.regex.Pattern;

public final class Output extends PrintWriter {
    final Pattern p = Pattern.compile("\r?\n\r?");
    StringBuffer buff = new StringBuffer(32767);
    volatile boolean isMore;

    public Output(final Writer out) {
        super(out);
    }

    public void clear() {
        buff.setLength(0);
    }

    public void add(final String str) {
        buff.append(str);
        if (!isMore) write(str);
    }

    public void addln(final String str) {
        buff.append(str + "\n");
        flush();
    }

    @Override
    public void println(final String str) {
        super.println(str);
        flush();
    }

    public String[] lines() {
        isMore = false;
        if (buff.length() == 0) return new String[0];
        String[] array = p.split(buff.toString());
        return array;
    }
}

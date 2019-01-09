package org.dbcli;

import com.naef.jnlua.LuaTable;

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
        append(str + "\n");
        flush();
    }

    @Override
    public void println(final String str) {
        super.println(str);
        flush();
    }

    private LuaTable table= new LuaTable(new String[0]);
    public LuaTable lines() {
        isMore = false;
        if (buff.length() == 0) table.setTable(new String[0]);
        else {
            table.setTable(p.split(buff.toString()));
        }
        return table;
    }
}

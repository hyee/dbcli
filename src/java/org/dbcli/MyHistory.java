package org.dbcli;

import com.esotericsoftware.reflectasm.ClassAccess;
import org.jline.reader.impl.history.DefaultHistory;

import java.util.LinkedList;

public class MyHistory extends DefaultHistory {
    private ClassAccess<DefaultHistory> accessor = ClassAccess.access(DefaultHistory.class);
    private LinkedList<EntryImpl> list = null;
    private int lasIndex;
    private int unescapeIndex;
    private EntryImpl lastEntry = null;

    public MyHistory() {
        super();
        list = accessor.get(this, "items");
        unescapeIndex = accessor.indexOfMethod("unescape");
    }

    public int setIndex() {
        lasIndex = list.size() - 1;
        lastEntry = list.get(lasIndex);
        return lasIndex;
    }

    public void update(int index, String line) {
        EntryImpl entry = list.get(index);
        list.set(index, new EntryImpl(entry.index(), entry.time(), accessor.invokeWithIndex(this, unescapeIndex, line)));
    }

    public void updateLast(String line) {
        if (lastEntry == null) return;
        for (int i = lasIndex; i >= 0; i--) {
            if (list.get(i) == lastEntry) {
                lasIndex = i;
                update(lasIndex, line);
                break;
            }
        }
    }
}

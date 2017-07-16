package org.dbcli;

import java.io.PrintWriter;

public interface MyTerminal {
    default void lockReader(boolean enabled) {
    }

    PrintWriter printer();

    int getBufferWidth();
}

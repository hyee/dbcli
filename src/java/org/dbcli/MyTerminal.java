package org.dbcli;

import java.io.PrintWriter;

/**
 * Created by VULCAN on 7/11/2017.
 */
public interface MyTerminal {
    default void lockReader(boolean enabled) {
    }

    PrintWriter printer();
}

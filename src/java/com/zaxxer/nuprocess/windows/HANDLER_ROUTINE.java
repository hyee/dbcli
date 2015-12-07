package com.zaxxer.nuprocess.windows;

import com.sun.jna.win32.StdCallLibrary;

public interface HANDLER_ROUTINE extends StdCallLibrary.StdCallCallback {
    public static final int CTRL_C_EVENT = 0;
    public static final int CTRL_BREAK_EVENT = 1;
    public static final int CTRL_CLOSE_EVENT = 2;
    public static final int CTRL_LOGOFF_EVENT = 5;
    public static final int CTRL_SHUTDOWN_EVENT = 6;

    long callback(long dwCtrlType);
}
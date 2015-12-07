package com.zaxxer.nuprocess.windows;

import com.sun.jna.Native;
import com.sun.jna.NativeLibrary;
import com.sun.jna.win32.W32APIOptions;

public class NuUser32 {
    static {
        NativeLibrary nativeLibrary = NativeLibrary.getInstance("user32", W32APIOptions.UNICODE_OPTIONS);
        Native.register(nativeLibrary);
    }

    public static native NuWinNT.DWORD WaitForInputIdle(NuWinNT.HANDLE hThread, NuWinNT.DWORD dwMilliseconds);
}

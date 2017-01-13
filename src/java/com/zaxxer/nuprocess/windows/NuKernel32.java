/*
 * Copyright (C) 2013 Brett Wooldridge
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package com.zaxxer.nuprocess.windows;

import com.sun.jna.*;
import com.sun.jna.ptr.IntByReference;
import com.sun.jna.ptr.PointerByReference;
import com.sun.jna.win32.W32APIOptions;
import com.zaxxer.nuprocess.windows.NuWinNT.*;

import java.nio.ByteBuffer;
import java.util.Arrays;
import java.util.List;

public class NuKernel32 {
    static {
        NativeLibrary nativeLibrary = NativeLibrary.getInstance("kernel32", W32APIOptions.UNICODE_OPTIONS);
        Native.register(NuKernel32.class, nativeLibrary);
    }

    public static final int PIPE_ACCESS_DUPLEX = 0x00000003;
    public static final int PIPE_ACCESS_INBOUND = 0x00000002;
    public static final int PIPE_ACCESS_OUTBOUND = 0x00000001;
    public static final int FILE_FLAG_OVERLAPPED = 0x40000000;
    public static final int ENABLE_PROCESSED_INPUT = 0x0001;
    public static final int ENABLE_LINE_INPUT = 0x0002;
    public static final int ENABLE_ECHO_INPUT = 0x0004;
    public static final int ENABLE_WINDOW_INPUT = 0x0008;
    public static final int ENABLE_MOUSE_INPUT = 0x0010;
    public static final int ENABLE_INSERT_MODE = 0x0020;
    public static final int ENABLE_QUICK_EDIT_MODE = 0x0040;
    public static final int ENABLE_EXTENDED_FLAGS = 0x0080;
    public static final int HANDLE_FLAG_INHERIT = 0x00000001;
    public static final int STD_INPUT_HANDLE = -10;
    public static final int STD_OUTPUT_HANDLE = -11;
    public static final int STD_ERROR_HANDLE = -12;

    public static native boolean CloseHandle(HANDLE hObject);

    public static native HANDLE CreateIoCompletionPort(HANDLE fileHandle, HANDLE existingCompletionPort, ULONG_PTR completionKey, int numberOfThreads);

    public static native boolean CreateProcessW(WString lpApplicationName, char[] lpCommandLine, SECURITY_ATTRIBUTES lpProcessAttributes, SECURITY_ATTRIBUTES lpThreadAttributes, boolean bInheritHandles, DWORD dwCreationFlags, Pointer lpEnvironment, char[] lpCurrentDirectory, STARTUPINFO lpStartupInfo, PROCESS_INFORMATION lpProcessInformation);

    public static native boolean TerminateProcess(HANDLE hProcess, int exitCode);

    public static native HANDLE CreateFile(WString lpFileName, int dwDesiredAccess, int dwShareMode, SECURITY_ATTRIBUTES lpSecurityAttributes, int dwCreationDisposition, int dwFlagsAndAttributes, HANDLE hTemplateFile);

    public static native HANDLE CreateEvent(SECURITY_ATTRIBUTES lpEventAttributes, boolean bManualReset, boolean bInitialState, String lpName);

    public static native int GetQueuedCompletionStatus(HANDLE completionPort, IntByReference numberOfBytes, ULONG_PTRByReference completionKey, PointerByReference lpOverlapped, int dwMilliseconds);

    public static native boolean PostQueuedCompletionStatus(HANDLE completionPort, int dwNumberOfBytesTransferred, ULONG_PTR dwCompletionKey, OVERLAPPED lpOverlapped);

    public static native HANDLE CreateNamedPipeW(WString name, int dwOpenMode, int dwPipeMode, int nMaxInstances, int nOutBufferSize, int nInBufferSize, int nDefaultTimeOut, SECURITY_ATTRIBUTES securityAttributes);

    public static native int ConnectNamedPipe(HANDLE hNamedPipe, OVERLAPPED lpo);

    public static native boolean DisconnectNamedPipe(HANDLE hNamedPipe);

    public static native boolean CreatePipe(HANDLEByReference hReadPipe, HANDLEByReference hWritePipe, SECURITY_ATTRIBUTES securityAttributes, int size);

    public static native boolean SetHandleInformation(HANDLE hObject, int dwMask, int dwFlags);

    public static native DWORD ResumeThread(HANDLE hThread);

    public static native boolean GetExitCodeProcess(HANDLE hProcess, IntByReference exitCode);

    public static native int ReadFile(HANDLE hFile, ByteBuffer lpBuffer, int nNumberOfBytesToRead, IntByReference lpNumberOfBytesRead, NuKernel32.OVERLAPPED lpOverlapped);

    public static native int WriteFile(HANDLE hFile, ByteBuffer lpBuffer, int nNumberOfBytesToWrite, IntByReference lpNumberOfBytesWritten, NuKernel32.OVERLAPPED lpOverlapped);

    public static native int WaitForSingleObject(HANDLE hHandle, int dwMilliseconds);

    public static native boolean GenerateConsoleCtrlEvent(int dwCtrlEvent, DWORD dwProcessGroupId);

    public static native boolean SetConsoleCtrlHandler(HANDLER_ROUTINE HandlerRoutine, boolean Add);

    public static native boolean SetEnvironmentVariable(String lpName, String lpValue);

    public static native String GetEnvironmentVariable(String lpName);

    public static native int FormatMessage(int dwFlags, Pointer lpSource, int dwMessageId, int dwLanguageId, PointerByReference lpBuffer, int nSize, Pointer va_list);

    public static native Pointer LocalFree(Pointer hLocal);

    public static native boolean AttachConsole(DWORD dwProcessId);

    public static native boolean FreeConsole();

    public static native boolean AllocConsole();

    public static native boolean SetConsoleMode(HANDLE hProcess, int mode);

    public static native int GetConsoleMode(HANDLE hProcess);

    public static native HANDLE GetStdHandle(int nStdHandle);

    public static native boolean SetStdHandle(int nStdHandle, HANDLE hHandle);
    //public static native boolean WriteConsoleInput(HANDLE hProcess, INPUT_RECORD[] input,int length,IntByReference lpNumberOfEventsWritten);

    public static native boolean WriteProcessMemory(HANDLE hProcess, Pointer lpBaseAddress, Pointer lpBuffer, int nSize, IntByReference lpNumberOfBytesWritten);

    /**
     * The OVERLAPPED structure contains information used in
     * asynchronous (or overlapped) input and output (I/O).
     */
    public static class OVERLAPPED extends Structure {
        public ULONG_PTR Internal;
        public ULONG_PTR InternalHigh;
        public int Offset;
        public int OffsetHigh;
        public HANDLE hEvent;

        public OVERLAPPED() {
            super();
        }

        public OVERLAPPED(Pointer p) {
            super(p);
        }

        @Override
        @SuppressWarnings("rawtypes")
        protected List getFieldOrder() {
            return Arrays.asList(new String[]{"Internal", "InternalHigh", "Offset", "OffsetHigh", "hEvent"});
        }
    }
}

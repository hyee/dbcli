/*
 * Copyright (C) 2015 Ben Hamilton
 *
 * Originally from JNA com.sun.jna.platform.win32 package (Apache
 * License, Version 2.0)
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
import com.sun.jna.ptr.ByReference;
import com.sun.jna.ptr.ByteByReference;
import com.sun.jna.win32.StdCallLibrary;

import java.util.Arrays;
import java.util.List;

/**
 * Constants and structures for Windows APIs, borrowed from com.sun.jna.platform.win32
 * to avoid pulling in a dependency on that package.
 */
@SuppressWarnings("serial")
public interface NuWinNT {
    int DEBUG_PROCESS = 0x00000001;
    int DEBUG_ONLY_THIS_PROCESS = 0x00000002;
    int CREATE_SUSPENDED = 0x00000004;
    int DETACHED_PROCESS = 0x00000008;
    int CREATE_NEW_CONSOLE = 0x00000010;
    int CREATE_NEW_PROCESS_GROUP = 0x00000200;
    int CREATE_UNICODE_ENVIRONMENT = 0x00000400;
    int CREATE_SEPARATE_WOW_VDM = 0x00000800;
    int CREATE_SHARED_WOW_VDM = 0x00001000;
    int CREATE_FORCEDOS = 0x00002000;
    int INHERIT_PARENT_AFFINITY = 0x00010000;
    int CREATE_PROTECTED_PROCESS = 0x00040000;
    int EXTENDED_STARTUPINFO_PRESENT = 0x00080000;
    int CREATE_BREAKAWAY_FROM_JOB = 0x01000000;
    int CREATE_PRESERVE_CODE_AUTHZ_LEVEL = 0x02000000;
    int CREATE_DEFAULT_ERROR_MODE = 0x04000000;
    int CREATE_NO_WINDOW = 0x08000000;

    int ERROR_SUCCESS = 0;
    int ERROR_BROKEN_PIPE = 109;
    int ERROR_PIPE_NOT_CONNECTED = 233;
    int ERROR_PIPE_CONNECTED = 535;
    int ERROR_IO_PENDING = 997;

    int FILE_ATTRIBUTE_NORMAL = 0x00000080;
    int FILE_FLAG_OVERLAPPED = 0x40000000;
    int FILE_SHARE_READ = 0x00000001;
    int FILE_SHARE_WRITE = 0x00000002;

    int GENERIC_READ = 0x80000000;
    int GENERIC_WRITE = 0x40000000;

    int OPEN_EXISTING = 3;

    int STATUS_PENDING = 0x00000103;
    int STILL_ACTIVE = STATUS_PENDING;

    int STARTF_USESTDHANDLES = 0x100;

    HANDLE INVALID_HANDLE_VALUE = new HANDLE(Pointer.createConstant(Pointer.SIZE == 8 ? -1 : 0xFFFFFFFFL));

    public interface HANDLER_ROUTINE extends StdCallLibrary.StdCallCallback {
        public static final int CTRL_C_EVENT = 0;
        public static final int CTRL_BREAK_EVENT = 1;
        public static final int CTRL_CLOSE_EVENT = 2;
        public static final int CTRL_LOGOFF_EVENT = 5;
        public static final int CTRL_SHUTDOWN_EVENT = 6;

        long callback(long dwCtrlType);
    }

    class HANDLE extends PointerType {
        public HANDLE() {
        }

        public HANDLE(Pointer p) {
            setPointer(p);
        }

        @Override
        public Object fromNative(Object nativeValue, FromNativeContext context) {
            Object o = super.fromNative(nativeValue, context);
            if (INVALID_HANDLE_VALUE.equals(o)) {
                return INVALID_HANDLE_VALUE;
            }
            return o;
        }
    }

    public static class HANDLEByReference extends ByReference {
        public HANDLEByReference() {
            this(null);
        }

        public HANDLEByReference(HANDLE h) {
            super(Pointer.SIZE);
            setValue(h);
        }

        public HANDLE getValue() {
            Pointer p = getPointer().getPointer(0);
            if (p == null) {
                return null;
            }
            if (INVALID_HANDLE_VALUE.getPointer().equals(p)) {
                return INVALID_HANDLE_VALUE;
            }
            HANDLE h = new HANDLE();
            h.setPointer(p);
            return h;
        }

        public void setValue(HANDLE h) {
            getPointer().setPointer(0, h != null ? h.getPointer() : null);
        }
    }

    static class WORD extends IntegerType {
        public static final int SIZE = 2;

        public WORD() {
            this(0);
        }

        public WORD(long value) {
            super(SIZE, value, true);
        }
    }

    static class DWORD extends IntegerType {
        public static final int SIZE = 4;

        public DWORD() {
            this(0);
        }

        public DWORD(long value) {
            super(SIZE, value, true);
        }
    }

    static class ULONG_PTR extends IntegerType {
        public ULONG_PTR() {
            this(0);
        }

        public ULONG_PTR(long value) {
            super(Pointer.SIZE, value, true);
        }

        public Pointer toPointer() {
            return Pointer.createConstant(longValue());
        }
    }

    static class ULONG_PTRByReference extends ByReference {
        public ULONG_PTRByReference() {
            this(new ULONG_PTR(0));
        }

        public ULONG_PTRByReference(ULONG_PTR value) {
            super(Pointer.SIZE);
            setValue(value);
        }

        public ULONG_PTR getValue() {
            return new ULONG_PTR(Pointer.SIZE == 4 ? getPointer().getInt(0) : getPointer().getLong(0));
        }

        public void setValue(ULONG_PTR value) {
            if (Pointer.SIZE == 4) {
                getPointer().setInt(0, value.intValue());
            } else {
                getPointer().setLong(0, value.longValue());
            }
        }
    }

    class SECURITY_ATTRIBUTES extends Structure {
        public DWORD dwLength;
        public Pointer lpSecurityDescriptor;
        public boolean bInheritHandle;

        @Override
        @SuppressWarnings("rawtypes")
        protected List getFieldOrder() {
            return Arrays.asList(new String[]{"dwLength", "lpSecurityDescriptor", "bInheritHandle"});
        }
    }

    class STARTUPINFO extends Structure {
        public DWORD cb;
        public String lpReserved;
        public String lpDesktop;
        public String lpTitle;
        public DWORD dwX;
        public DWORD dwY;
        public DWORD dwXSize;
        public DWORD dwYSize;
        public DWORD dwXCountChars;
        public DWORD dwYCountChars;
        public DWORD dwFillAttribute;
        public int dwFlags;
        public WORD wShowWindow;
        public WORD cbReserved2;
        public ByteByReference lpReserved2;
        public HANDLE hStdInput;
        public HANDLE hStdOutput;
        public HANDLE hStdError;

        public STARTUPINFO() {
            cb = new DWORD(size());
        }

        @Override
        @SuppressWarnings("rawtypes")
        protected List getFieldOrder() {
            return Arrays.asList(new String[]{"cb", "lpReserved", "lpDesktop", "lpTitle", "dwX", "dwY", "dwXSize", "dwYSize", "dwXCountChars", "dwYCountChars", "dwFillAttribute", "dwFlags", "wShowWindow", "cbReserved2", "lpReserved2", "hStdInput", "hStdOutput", "hStdError"});
        }
    }

    class PROCESS_INFORMATION extends Structure {
        public HANDLE hProcess;
        public HANDLE hThread;
        public DWORD dwProcessId;
        public DWORD dwThreadId;

        @Override
        @SuppressWarnings("rawtypes")
        protected List getFieldOrder() {
            return Arrays.asList(new String[]{"hProcess", "hThread", "dwProcessId", "dwThreadId"});
        }
    }

    // typedef struct _COORD {
//    SHORT X;
//    SHORT Y;
//  } COORD, *PCOORD;
    public class COORD extends Structure implements Structure.ByValue {
        private static String[] fieldOrder = {"X", "Y"};
        public short X;
        public short Y;

        public COORD() {
        }

        public COORD(short X, short Y) {
            this.X = X;
            this.Y = Y;
        }

        @Override
        protected java.util.List<String> getFieldOrder() {
            return java.util.Arrays.asList(fieldOrder);
        }
    }

    public class UnionChar extends Union {
        public char UnicodeChar;
        public byte AsciiChar;

        public UnionChar() {
        }

        public UnionChar(char c) {
            setType(char.class);
            UnicodeChar = c;
        }

        public UnionChar(byte c) {
            setType(byte.class);
            AsciiChar = c;
        }

        public void set(char c) {
            setType(char.class);
            UnicodeChar = c;
        }

        public void set(byte c) {
            setType(byte.class);
            AsciiChar = c;
        }
    }

    // typedef struct _KEY_EVENT_RECORD {
//   BOOL  bKeyDown;
//   WORD  wRepeatCount;
//   WORD  wVirtualKeyCode;
//   WORD  wVirtualScanCode;
//   union {
//     WCHAR UnicodeChar;
//     CHAR  AsciiChar;
//   } uChar;
//   DWORD dwControlKeyState;
// } KEY_EVENT_RECORD;
    public class KEY_EVENT_RECORD extends Structure {
        private static String[] fieldOrder = {"bKeyDown", "wRepeatCount", "wVirtualKeyCode", "wVirtualScanCode", "uChar", "dwControlKeyState"};
        public boolean bKeyDown;
        public short wRepeatCount;
        public short wVirtualKeyCode;
        public short wVirtualScanCode;
        public UnionChar uChar;
        public int dwControlKeyState;

        @Override
        protected java.util.List<String> getFieldOrder() {
            return java.util.Arrays.asList(fieldOrder);
        }
    }

    // typedef struct _MOUSE_EVENT_RECORD {
//   COORD dwMousePosition;
//   DWORD dwButtonState;
//   DWORD dwControlKeyState;
//   DWORD dwEventFlags;
// } MOUSE_EVENT_RECORD;
    public class MOUSE_EVENT_RECORD extends Structure {
        public static final short MOUSE_MOVED = 0x0001;
        public static final short DOUBLE_CLICK = 0x0002;
        public static final short MOUSE_WHEELED = 0x0004;
        public static final short MOUSE_HWHEELED = 0x0008;

        public static final short FROM_LEFT_1ST_BUTTON_PRESSED = 0x0001;
        public static final short RIGHTMOST_BUTTON_PRESSED = 0x0002;
        public static final short FROM_LEFT_2ND_BUTTON_PRESSED = 0x0004;
        public static final short FROM_LEFT_3RD_BUTTON_PRESSED = 0x0008;
        public static final short FROM_LEFT_4TH_BUTTON_PRESSED = 0x0010;
        private static String[] fieldOrder = {"dwMousePosition", "dwButtonState", "dwControlKeyState", "dwEventFlags"};
        public COORD dwMousePosition;
        public int dwButtonState;
        public int dwControlKeyState;
        public int dwEventFlags;

        @Override
        protected java.util.List<String> getFieldOrder() {
            return java.util.Arrays.asList(fieldOrder);
        }
    }

    // typedef struct _INPUT_RECORD {
//   WORD  EventType;
//   union {
//     KEY_EVENT_RECORD          KeyEvent;
//     MOUSE_EVENT_RECORD        MouseEvent;
//     WINDOW_BUFFER_SIZE_RECORD WindowBufferSizeEvent;
//     MENU_EVENT_RECORD         MenuEvent;
//     FOCUS_EVENT_RECORD        FocusEvent;
//   } Event;
// } INPUT_RECORD;
    public class INPUT_RECORD extends Structure {
        public static final short FOCUS_EVENT = 0x0010;
        public static final short KEY_EVENT = 0x0001;
        public static final short MENU_EVENT = 0x0008;
        public static final short MOUSE_EVENT = 0x0002;
        public static final short WINDOW_BUFFER_SIZE_EVENT = 0x0004;
        private static String[] fieldOrder = {"EventType", "Event"};
        public short EventType;
        public EventUnion Event;

        @Override
        public void read() {
            readField("EventType");
            switch (EventType) {
                case KEY_EVENT:
                    Event.setType(KEY_EVENT_RECORD.class);
                    break;
                case MOUSE_EVENT:
                    Event.setType(MOUSE_EVENT_RECORD.class);
                    break;
            }
            super.read();
        }

        @Override
        public void write() {
            readField("EventType");
            switch (EventType) {
                case KEY_EVENT:
                    Event.setType(KEY_EVENT_RECORD.class);
                    break;
                case MOUSE_EVENT:
                    Event.setType(MOUSE_EVENT_RECORD.class);
                    break;
            }
            super.write();
        }

        @Override
        protected java.util.List<String> getFieldOrder() {
            return java.util.Arrays.asList(fieldOrder);
        }

        public static class EventUnion extends Union {
            public KEY_EVENT_RECORD KeyEvent;
            public MOUSE_EVENT_RECORD MouseEvent;
            // WINDOW_BUFFER_SIZE_RECORD WindowBufferSizeEvent;
            // MENU_EVENT_RECORD MenuEvent;
            // FOCUS_EVENT_RECORD FocusEvent;
        }
    }
}

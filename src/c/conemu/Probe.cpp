// Stage-0 probe for a JNI-rendered console writer (see .dsh/memory/project/project-conemu-writer-perf.md).
//
// Proves four things before any real component is built:
//   1. a MinGW-w64 cross DLL from WSL loads in JDK 8 (x86 and x64) through System.loadLibrary;
//   2. the native side can drive the console API and read cells back (the oracle the real writer
//      needs, same recipe as ProdBulkBench: FreeConsole + AllocConsole + CONOUT$ + hide);
//   3. UTF-16 gets to WriteConsoleW without a copy or a transcode (GetPrimitiveArrayCritical on a
//      Java char[] is already the console's encoding);
//   4. which source-rectangle convention ReadConsoleOutputW actually accepts here - the one
//      capability the Java rectangle writer (BulkCellWriter, retired 2026-09-23) depended on, and the
//      one this probe exists to settle.
//
// Nothing here is production code; it exists to be deleted once the seams it tests are settled.
//
// Two toolchain traps this file already paid for: JNIEnv is a *reference* in C++ (env->Method(),
// not (*env)->Method(env, ...)), and mingw-w64 calls the CHAR_INFO union member UnicodeChar.
//
// The native side deliberately reports instead of asserting: it hands back return codes and
// GetLastError values and lets Probe.java decide what is a gate failure, so a change of opinion
// about the expectations does not need a rebuild.

#include <jni.h>
#include <windows.h>
#include <stdio.h>
#include <string.h>

#define PROBE_BUILD "probe-2026-09-22-3"

// ReadConsoleOutputW/WriteConsoleOutputW cell rectangles, as reported to the gate.
#define READ_MAX_CELLS 4096

#ifdef __MINGW32__
#define CH_UNICODE(ci) ((ci).Char.UnicodeChar)
#else
#define CH_UNICODE(ci) ((ci).Char.Unicode)
#endif

static HANDLE g_con = INVALID_HANDLE_VALUE;

/** A jlongArray of n values, or NULL when the JVM cannot allocate it. */
static jlongArray newLongs(JNIEnv *env, const jlong *vals, int n)
{
  jlongArray arr = env->NewLongArray(n);
  if (arr) env->SetLongArrayRegion(arr, 0, n, vals);
  return arr;
}

extern "C" {

JNIEXPORT jstring JNICALL Java_Probe_build(JNIEnv *env, jclass cls)
{
  char b[256];
  sprintf(b, "%s gcc=[%s] arch=%s sizeof_ptr=%u _WIN32_WINNT=0x%04x sizeof_CHAR_INFO=%u",
          PROBE_BUILD,
          __VERSION__,
          (sizeof(void *) == 4) ? "x86" : "x64",
          (unsigned)sizeof(void *),
          (unsigned)_WIN32_WINNT,
          (unsigned)sizeof(CHAR_INFO));
  return env->NewStringUTF(b);
}

/**
 * Opens a console we can read back from.
 *
 * Only frees the inherited console when this process' stdout is a pipe, because otherwise
 * FreeConsole would silence our own reporting. Returns:
 *   [0] stdout file type  [1] FreeConsole rc  [2] AllocConsole rc  [3] conout file type
 *   [4] csbi ok           [5..6] buffer X,Y   [7..10] window L,R,T,B
 *   [11] attributes       [12..13] cursor X,Y [14] SetConsoleScreenBufferSize(120x2000) rc
 */
JNIEXPORT jlongArray JNICALL Java_Probe_prepareConsole(JNIEnv *env, jclass cls)
{
  jlong out[15];
  memset(out, 0, sizeof(out));

  HANDLE std_out = GetStdHandle(STD_OUTPUT_HANDLE);
  DWORD std_type = std_out ? GetFileType(std_out) : 0;
  out[0] = std_type;

  if (std_type == FILE_TYPE_PIPE)
  {
    out[1] = FreeConsole() ? 1 : 0;
    out[2] = AllocConsole() ? 1 : 0;
    HWND hwnd = GetConsoleWindow();
    if (hwnd) ShowWindow(hwnd, SW_HIDE);
  }

  g_con = CreateFileW(L"CONOUT$", GENERIC_READ | GENERIC_WRITE,
                      FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
  out[3] = (g_con == INVALID_HANDLE_VALUE) ? 0 : GetFileType(g_con);

  CONSOLE_SCREEN_BUFFER_INFO csbi;
  memset(&csbi, 0, sizeof(csbi));
  out[4] = GetConsoleScreenBufferInfo(g_con, &csbi) ? 1 : 0;
  out[5] = csbi.dwSize.X;
  out[6] = csbi.dwSize.Y;
  out[7] = csbi.srWindow.Left;
  out[8] = csbi.srWindow.Right;
  out[9] = csbi.srWindow.Top;
  out[10] = csbi.srWindow.Bottom;
  out[11] = csbi.wAttributes;
  out[12] = csbi.dwCursorPosition.X;
  out[13] = csbi.dwCursorPosition.Y;

  COORD want;
  want.X = 120;
  want.Y = 2000;
  out[14] = SetConsoleScreenBufferSize(g_con, want) ? 1 : 0;

  return newLongs(env, out, 15);
}

/**
 * Put the console into a shape the gate chooses: buffer bufW x bufH, window winW x winH at its top-left.
 * Buffer first, window second (the reverse fails while the window hangs below the buffer it is being
 * shrunk into). Returns the window call's result.
 *
 * This exists so one question can be asked of conhost directly, with no renderer in the way: what does
 * it do with a line longer than the window when the buffer is wider still. Stage 0 never shaped the
 * console that way, so the shipped writer's wrap assumption was never compared against it.
 */
JNIEXPORT jboolean JNICALL Java_Probe_setGeometry(JNIEnv *env, jclass cls,
                                                  jint bufW, jint bufH, jint winW, jint winH)
{
  (void)env; (void)cls;
  if (g_con == INVALID_HANDLE_VALUE) return JNI_FALSE;
  COORD size;
  size.X = (SHORT)bufW;
  size.Y = (SHORT)bufH;
  SetConsoleScreenBufferSize(g_con, size);
  SMALL_RECT wr;
  wr.Left = 0;
  wr.Top = 0;
  wr.Right = (SHORT)(winW - 1);
  wr.Bottom = (SHORT)(winH - 1);
  return SetConsoleWindowInfo(g_con, TRUE, &wr) ? JNI_TRUE : JNI_FALSE;
}

/** Moves the cursor; proves the API the real writer will use for its geometry. */
JNIEXPORT jboolean JNICALL Java_Probe_setCursor(JNIEnv *env, jclass cls, jint x, jint y)
{
  if (g_con == INVALID_HANDLE_VALUE) return JNI_FALSE;
  COORD c;
  c.X = (SHORT)x;
  c.Y = (SHORT)y;
  return SetConsoleCursorPosition(g_con, c) ? JNI_TRUE : JNI_FALSE;
}

/**
 * Writes len UTF-16 units at the cursor with the given attribute.
 *
 * Returns the write result plus the geometry the gate needs to name the cells it expects:
 *   [0] rc  [1] chars written  [2] GetLastError   [3..4] buffer X,Y
 *   [5..6] cursor X,Y after    [7..10] window L,R,T,B   [11] console attribute after
 */
JNIEXPORT jlongArray JNICALL Java_Probe_writeText(JNIEnv *env, jclass cls,
                                                  jcharArray text, jint len, jint attr)
{
  jlong out[12];
  memset(out, 0, sizeof(out));
  if (g_con == INVALID_HANDLE_VALUE || len <= 0)
  {
    out[2] = (LONG)ERROR_INVALID_HANDLE;
    return newLongs(env, out, 12);
  }
  if (!text) return NULL;

  jchar *chars = (jchar *)env->GetPrimitiveArrayCritical(text, NULL);
  if (!chars) return NULL;

  SetLastError(0);
  SetConsoleTextAttribute(g_con, (WORD)attr);
  DWORD written = 0;
  BOOL ok = WriteConsoleW(g_con, chars, (DWORD)len, &written, NULL);
  LONG err = (LONG)GetLastError();
  env->ReleasePrimitiveArrayCritical(text, chars, 0);

  CONSOLE_SCREEN_BUFFER_INFO csbi;
  memset(&csbi, 0, sizeof(csbi));
  if (!GetConsoleScreenBufferInfo(g_con, &csbi))
    return NULL;

  out[0] = ok ? 1 : 0;
  out[1] = written;
  out[2] = err;
  out[3] = csbi.dwSize.X;
  out[4] = csbi.dwSize.Y;
  out[5] = csbi.dwCursorPosition.X;
  out[6] = csbi.dwCursorPosition.Y;
  out[7] = csbi.srWindow.Left;
  out[8] = csbi.srWindow.Right;
  out[9] = csbi.srWindow.Top;
  out[10] = csbi.srWindow.Bottom;
  out[11] = csbi.wAttributes;

  return newLongs(env, out, 12);
}

/**
 * Reads a w-by-h block of cells starting at buffer cell (x,y), in one of the three rectangle
 * conventions the API documentation and practice disagree about.
 *
 * The shipped Java writer (ScreenBuffer.readRect) uses convention 1 and works, so this is about
 * confirming that the same shape is available to native code and about getting an error code when
 * it is not - not about picking a winner by guesswork.
 *
 *   convention 1  absolute:  lpBufferCoordinates=(0,0),  lpWindow=(x,y)-(x+w-1,y+h-1)
 *   convention 2  relative:  lpBufferCoordinates=(x,y),  lpWindow=(0,0)-(w-1,h-1)
 *   convention 3  both:      lpBufferCoordinates=(x,y),  lpWindow=(x,y)-(x+w-1,y+h-1)
 *
 * Returns NULL when the request itself is impossible (no console, empty or oversized block);
 * otherwise [0] rc  [1] GetLastError  [2] convention  [3..] w*h cells as (Unicode | Attr << 16).
 */
JNIEXPORT jlongArray JNICALL Java_Probe_readCells(JNIEnv *env, jclass cls,
                                                  jint x, jint y, jint w, jint h, jint convention)
{
  if (g_con == INVALID_HANDLE_VALUE || w <= 0 || h <= 0)
    return NULL;
  const int cells = w * h;
  if (cells > READ_MAX_CELLS)
    return NULL;

  CHAR_INFO buf[READ_MAX_CELLS];
  memset(buf, 0, (size_t)cells * sizeof(buf[0]));

  COORD buf_size, buf_coord;
  buf_size.X = (SHORT)w;
  buf_size.Y = (SHORT)h;
  SMALL_RECT window;

  SetLastError(0);
  if (convention == 2)
  {
    buf_coord.X = (SHORT)x;
    buf_coord.Y = (SHORT)y;
    window.Left = 0;
    window.Top = 0;
    window.Right = (SHORT)(w - 1);
    window.Bottom = (SHORT)(h - 1);
  }
  else
  {
    buf_coord.X = (convention == 3) ? (SHORT)x : 0;
    buf_coord.Y = (convention == 3) ? (SHORT)y : 0;
    window.Left = (SHORT)x;
    window.Top = (SHORT)y;
    window.Right = (SHORT)(x + w - 1);
    window.Bottom = (SHORT)(y + h - 1);
  }

  BOOL ok = ReadConsoleOutputW(g_con, buf, buf_size, buf_coord, &window);
  LONG err = (LONG)GetLastError();

  jlongArray out = env->NewLongArray(3 + cells);
  if (!out) return NULL;
  jlong *vals = (jlong *)env->GetPrimitiveArrayCritical(out, NULL);
  if (!vals)
  {
    env->DeleteLocalRef(out);
    return NULL;
  }
  vals[0] = ok ? 1 : 0;
  vals[1] = err;
  vals[2] = convention;
  for (int i = 0; i < cells; i++)
    vals[3 + i] = (jlong)((unsigned)CH_UNICODE(buf[i]) | ((unsigned)buf[i].Attributes << 16));
  env->ReleasePrimitiveArrayCritical(out, vals, 0);
  return out;
}

}  // extern "C"

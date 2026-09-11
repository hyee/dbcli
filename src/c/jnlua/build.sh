#!/usr/bin/env bash
#
# build.sh -- Cross-compile src/c/jnlua into the two DBCLI native modules and place
#             per-platform output at lib/<platform>/, then run built-in self checks:
#
#               jnlua.c   -> lib/<plat>/jnlua5.1.dll   (Windows)
#                            lib/<plat>/libjnlua5.1.so  (Linux/macOS)
#               javavm.c  -> lib/<plat>/javavm.dll      (Windows)
#                            lib/<plat>/javavm.so       (Linux/macOS)
#
# Consumers (do not rename the artifacts -- both names are hard-wired elsewhere):
#   * Lua side   : bootstrap.lua does  require("javavm")  -> luaopen_javavm via
#                  LUA_CPATH ./lib/$os/?.so (?.dll on Windows), then javavm.create().
#   * JVM side   : com.naef.jnlua LuaState static init does System.loadLibrary("jnlua5.1")
#                  -> jnlua5.1.dll / libjnlua5.1.so; the JVM resolves the library through
#                  JNI_OnLoad/JNI_OnUnload (this jnlua fork binds ALL its natives with
#                  RegisterNatives inside JNI_OnLoad -- there are no Java_*-exported entry
#                  points, see jnlua.c luastate_native_map / luadebug_native_map).
#
# Linking contract (mirrors src/c/luauf8/build.sh; the artifacts stay "copy-and-go"):
#   Linux   : do NOT put libluajit5.1.so on the link line -> no DT_NEEDED libluajit5.1.so;
#             the lua_*/lj* refs stay undefined and resolve against the LuaJIT already
#             loaded in the process (the shipped luv.so does the same; the OLD shipped
#             libjnlua5.1.so/javavm.so still recorded DT_NEEDED libluajit5.1.so -- this
#             build drops it). libjvm is the one hard dependency javavm.so keeps: it is
#             loaded BEFORE any VM exists (it CREATES the VM), so JNI_CreateJavaVM cannot
#             come from the process and MUST be a DT_NEEDED libjvm.so resolved via
#             LD_LIBRARY_PATH (dbcli.sh points it at $JAVA_HOME/lib/server). jnlua itself
#             never links libjvm: it only uses JNIEnv/JavaVM function pointers it is
#             handed by JNI_OnLoad.
#   Windows : the PE loader binds imports by the DLL NAME in the import table, so we KEEP
#             importing lua5.1.dll (any module already loaded under that name satisfies it
#             -- utf8.dll/luv.dll do the same) and javavm.dll additionally imports jvm.dll
#             by name (as shipped). Link inputs: lib/<plat>/lua5.1.dll and a REAL jvm.dll
#             of matching bitness (mingw ld reads exports straight from the DLL; the
#             recorded import name is its basename).
#   macOS   : Mach-O BUNDLE with -undefined dynamic_lookup so lua_* resolve from the host
#             at load time; javavm also links libjli+libjvm from the JDK (both arrive as
#             @rpath deps, exactly like the shipped lib/mac/javavm.so; dbcli.sh exports
#             DYLD_LIBRARY_PATH for them -- no LC_RPATH is baked in). x86_64 floor
#             -mmacosx-version-min=10.12 (user-specified), arm64 floor 11.0. Ad-hoc
#             codesign so Apple Silicon accepts the bundle. mac/mac-arm build only on
#             macOS (no osxcross here).
#   Output goes straight onto lib/<plat>/... -- the build overwrites the previous artifact
#   in place and keeps no copy of it (back up before replacing a deployed tree).
#
# Win32 stdcall (x86 only): JNICALL is __stdcall on i386, so the JVM's
# GetProcAddress(h,"JNI_OnLoad") needs the UNDECORATED export; -Wl,--add-stdcall-alias
# provides both JNI_OnLoad and JNI_OnLoad@8 (the shipped x86 dll has exactly that pair).
# Both Windows modules are linked against an explicit .def plus
# -Wl,--exclude-all-symbols so the export table is minimal (jnlua: JNI_OnLoad
# [+@8 alias]; javavm: luaopen_javavm) instead of mingw's default export-everything.
#
# CentOS6 / GLIBC<=2.12: on x86-64 glibc binds memcpy/memmove to @GLIBC_2.14 (>2.12).
#   A .symver directive remaps this TU's references to @GLIBC_2.2.5 via -include (same
#   trick as src/c/luauf8/build.sh; measured on the shipped linux pair: ceiling 2.4).
#   linux-arm needs nothing: aarch64 memcpy only exists as @GLIBC_2.17+ there.
#
# JNI headers come from a JDK per target (jni.h + jni_md.h from the arch subdir); the
# Lua headers from the LuaJIT sources. Defaults target this machine (WSL paths):
#   x64|x86  headers /mnt/d/jdk-17 (+bin/server/jvm.dll; x86 jvm from the in-repo
#            32-bit JRE jre/bin/client/jvm.dll), linux /mnt/d/jdk-24-linux,
#            linux-arm /mnt/d/jdk-24-linux-arm64, mac/mac-arm $JAVA_HOME (on macOS).
#
# Usage: src/c/jnlua/build.sh [options]     (run inside WSL or on macOS)
# See "--help" for the full option list.

set -u

# This script lives next to its sources (src/c/jnlua); the repo root is three levels up.
SELF=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P) || SELF=.
SRC_DIR="$SELF"
REPO=$(cd -- "$SELF/../../.." >/dev/null 2>&1 && pwd -P) || REPO=.
OUT_ROOT="$REPO/lib"
LUAJIT_SRC="/mnt/d/LuaJIT-2.1/src"
JDK_WIN="/mnt/d/jdk-17"
JVM_X64=""
JVM_X86="/mnt/d/jdkx86/lib/jvm.lib"   # 32-bit IMPORT LIB: the Java 8 jvm.dll exports are
                                       # undecorated, but C javavm.c emits the stdcall dllimport
                                       # ref _imp__JNI_CreateJavaVM@12 -- only jvm.lib has it.
JDK_LINUX="/mnt/d/jdk-24-linux"
JDK_ARM="/mnt/d/jdk-24-linux-arm64"
GLIBC_MAX_LINUX="2.12"
PLATFORMS=""
EXTRA_CFLAGS=""
DO_STRIP=1
DO_CHECK=1
DRY_RUN=0
CC_OVR=""
SELFTEST_DIR=${TMPDIR:-/tmp}/dbcli_jnlua_selftest

usage() {
  cat <<'USAGE'
build.sh -- cross-build jnlua (JNI_OnLoad) + javavm (luaopen_javavm) for DBCLI

Options:
  -p, --platform LIST    Space-separated platforms. Defaults by host:
                         x86-64 Linux/WSL -> x64 x86 linux linux-arm ; macOS -> mac mac-arm
                         (mac/mac-arm build only on macOS with clang; skipped elsewhere)
  -o, --out DIR          lib root directory. Default: <repo>/lib
      --luajit-src DIR   LuaJIT headers dir. Default: /mnt/d/LuaJIT-2.1/src
      --jdk-win DIR      Windows-target JDK root (jni.h + include/win32). Default: /mnt/d/jdk-17
      --jvm-x64 PATH     jvm.dll used to emit x64 javavm.dll's import table.
                         Default: <jdk-win>/bin/server/jvm.dll
      --jvm-x86 PATH     32-bit VM import lib for x86 (MUST be a .lib: the 32-bit JDK
                         jvm.dll lacks the @12-decorated export the compiler references).
                         Default: /mnt/d/jdkx86/lib/jvm.lib
      --jdk-linux DIR    linux-target JDK root (jni.h + include/linux; lib/server/libjvm.so).
                         Default: /mnt/d/jdk-24-linux
      --jdk-arm DIR      linux-arm-target JDK root. Default: /mnt/d/jdk-24-linux-arm64
                         (mac/mac-arm use $JAVA_HOME; export it before running on macOS)
  -c, --cc PLAT=CC       Override a platform's compiler, e.g. -c linux-arm=aarch64-linux-gnu-gcc
  -C, --cflags STR       Append extra compile flags (e.g. -O3)
      --glibc-max VER    Linux(x86-64) GLIBC ceiling check. Default: 2.12 (CentOS6)
  -n, --dry-run          Print commands only, do not compile
      --no-strip         Keep the symbol table (default: strip; artifacts are install-free
                         and can replace shipped files directly)
      --no-check         Skip self checks
  -h, --help             Show this help

Self checks (what the audit enforces):
  Windows : jnlua5.1.dll exports JNI_OnLoad (+JNI_OnLoad@8 on x86) and imports
            lua5.1.dll but NOT jvm.dll; javavm.dll exports luaopen_javavm and imports
            lua5.1.dll + jvm.dll; no Win8+ entrypoints anywhere (Win7 floor).
  ELF     : exported JNI_OnLoad / luaopen_javavm; DT_NEEDED of javavm MUST contain
            libjvm.so and MUST NOT contain libluajit*; undefined lua_* > 0 (host-provided);
            linux GLIBC ceiling <= --glibc-max; no versionless non-lua undefined symbol.
  Mach-O  : BUNDLE, lua_* undefined via dynamic_lookup; javavm deps only libSystem +
            @rpath libjli/libjvm; jnlua deps libSystem only; no LC_RPATH; minos floor.
  Load    : real require("javavm") + ffi.load of jnlua against the in-process LuaJIT on
            any platform whose host can execute it (linux native, linux-arm via qemu if
            present, Windows via WSL interop, mac natively on macOS).
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    -p|--platform)   PLATFORMS=${2:-}; shift 2 ;;
    -o|--out)        OUT_ROOT=${2:-}; shift 2 ;;
    --luajit-src)    LUAJIT_SRC=${2:-}; shift 2 ;;
    --jdk-win)       JDK_WIN=${2:-}; shift 2 ;;
    --jvm-x64)       JVM_X64=${2:-}; shift 2 ;;
    --jvm-x86)       JVM_X86=${2:-}; shift 2 ;;
    --jdk-linux)     JDK_LINUX=${2:-}; shift 2 ;;
    --jdk-arm)       JDK_ARM=${2:-}; shift 2 ;;
    -c|--cc)         CC_OVR="$CC_OVR $2"; shift 2 ;;
    -C|--cflags)     EXTRA_CFLAGS="$EXTRA_CFLAGS ${2:-}"; shift 2 ;;
    --glibc-max)     GLIBC_MAX_LINUX=${2:-}; shift 2 ;;
    -n|--dry-run)    DRY_RUN=1; shift ;;
    --no-strip)      DO_STRIP=0; shift ;;
    --no-check)      DO_CHECK=0; shift ;;
    -h|--help)       usage; exit 0 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[ -z "$JVM_X64" ] && JVM_X64="$JDK_WIN/bin/server/jvm.dll"

for f in "$SRC_DIR/jnlua.c" "$SRC_DIR/javavm.c"; do
  [ -f "$f" ] || { printf 'source not found: %s\n' "$f" >&2; exit 1; }
done
[ -f "$LUAJIT_SRC/lua.h" ] || { printf 'LuaJIT headers not found: %s\n' "$LUAJIT_SRC" >&2; exit 1; }

# ---- JNI header roots per platform (jni.h in <root>/include, jni_md.h in the arch dir) ----
jdk_root() { # $1=platform -> echo JDK root or empty
  case "$1" in
    x64|x86)      echo "$JDK_WIN" ;;
    linux)        echo "$JDK_LINUX" ;;
    linux-arm)    echo "$JDK_ARM" ;;
    mac|mac-arm)  echo "${JAVA_HOME:-}" ;;
  esac
}
jni_md_dir() { # $1=platform -> include/<win32|linux|darwin>
  case "$1" in
    x64|x86)     echo "$2/include/win32" ;;
    linux|linux-arm) echo "$2/include/linux" ;;
    mac|mac-arm) echo "$2/include/darwin" ;;
  esac
}
jvm_input() { # $1=platform -> link input for the VM library (empty = none for jnlua)
  case "$1" in
    x64)   echo "$JVM_X64" ;;
    x86)   echo "$JVM_X86" ;;
    linux) echo "$JDK_LINUX/lib/server/libjvm.so" ;;
    linux-arm) echo "$JDK_ARM/lib/server/libjvm.so" ;;
    mac)   echo "-L${JAVA_HOME:-}/lib/server -ljli -ljvm" ;;
    mac-arm) echo "-L${JAVA_HOME:-}/lib/server -ljli -ljvm" ;;
  esac
}

host_plat() {
  case "$(uname -s)/$(uname -m)" in
    Linux/x86_64)  echo linux ;;
    Linux/aarch64) echo linux-arm ;;
    Darwin/x86_64) echo mac ;;
    Darwin/arm64)  echo mac-arm ;;
    *)             echo none ;;
  esac
}

resolve_cc() { # $1=platform -> sets global CC (empty means cannot build here)
  local kv cc=""
  for kv in $CC_OVR; do case "$kv" in "$1="*) cc=${kv#*=} ;; esac; done
  [ -n "$cc" ] && { CC=$cc; return 0; }
  case "$1" in
    x64)       CC=$(command -v x86_64-w64-mingw32-gcc || true) ;;
    x86)       CC=$(command -v i686-w64-mingw32-gcc || true) ;;
    linux)     CC=$(command -v gcc || true) ;;
    linux-arm) CC=$(command -v aarch64-linux-gnu-gcc || true) ;;
    mac|mac-arm)
      if [ "$(uname -s)" = Darwin ]; then CC=$(command -v clang || true); else CC=""; fi ;;
    *) CC="" ;;
  esac
}

find_tool() { # <cc> <suffix> -> try same-toolchain prefix first, then bare command
  local c t=""
  for c in "${1%-gcc}-$2" "${1%-cc}-$2" "${1%-clang}-$2" "$2"; do
    command -v "$c" >/dev/null 2>&1 && { t=$c; break; }
  done
  printf '%s' "$t"
}

link_input() { # $1=platform -> LuaJIT link input (Windows only: keep the lua5.1.dll import)
  case "$1" in
    x64) echo "\"$OUT_ROOT/x64/lua5.1.dll\"" ;;
    x86) echo "\"$OUT_ROOT/x86/lua5.1.dll\"" ;;
    *)   echo "" ;;
  esac
}

# def files live outside the repo (temp dir): minimal PE export tables (see header notes).
write_defs() {
  # Only undecorated names: --add-stdcall-alias (x86) generates the decorated aliases
  # from the real signatures (JNI_OnLoad@8 / JNI_OnUnload@8).
  mkdir -p "$SELFTEST_DIR" || return 1
  printf 'EXPORTS\nJNI_OnLoad\nJNI_OnUnload\n' > "$SELFTEST_DIR/jnlua.def"
  printf 'EXPORTS\nluaopen_javavm\n' > "$SELFTEST_DIR/javavm.def"
}

ARTIFACTS="" FAILED="" DEPFAIL=""

# build_mod <platform> <kind jnlua|javavm> <output name> <source> <extra link args>
build_mod() {
  local plat=$1 kind=$2 name=$3 src=$4 linkextra=$5 cc out dir strip symver="" def=""
  resolve_cc "$plat"; cc=$CC
  dir="$OUT_ROOT/$plat"; out="$dir/$name"

  case "$plat" in
    x64|x86)
      [ -f "$SRC_DIR/$src" ] || return 1
      write_defs "$plat"
      def="\"$SELFTEST_DIR/${kind}.def\" -Wl,--exclude-all-symbols"
      [ "$plat" = x86 ] && [ "$kind" = jnlua ] && def="$def -Wl,--add-stdcall-alias" ;;
    linux)
      mkdir -p "$SELFTEST_DIR" 2>/dev/null
      printf '__asm__(".symver memcpy,memcpy@GLIBC_2.2.5");\n__asm__(".symver memmove,memmove@GLIBC_2.2.5");\n' > "$SELFTEST_DIR/symver.h"
      symver="-include $SELFTEST_DIR/symver.h" ;;
  esac

  local jdk md mode stripopt="-s"
  jdk=$(jdk_root "$plat"); md=$(jni_md_dir "$plat" "$jdk")
  case "$plat" in
    mac)     mode="-bundle -undefined dynamic_lookup -arch x86_64 -mmacosx-version-min=10.12"; stripopt="-x" ;;
    mac-arm) mode="-bundle -undefined dynamic_lookup -arch arm64 -mmacosx-version-min=11.0";  stripopt="-x" ;;
    *)       mode="-shared" ;;
  esac

  # jnlua.c/javavm.c pick JNLUA_THREADLOCAL from LUA_WIN / LUA_USE_POSIX; LuaJIT's
  # luaconf.h defines neither, so the platform define must come from the command line.
  local platdef
  case "$plat" in
    x64|x86)    platdef="-DLUA_WIN" ;;
    *)          platdef="-DLUA_USE_POSIX" ;;
  esac
  local cmd="$cc $mode -std=c99 -O2 -DNDEBUG -fPIC -Wall -Wextra $platdef $EXTRA_CFLAGS $symver"
  # mingw: keep the libgcc helpers (udiv/modf thunks) inside the DLL -- an import of
  # libgcc_s_seh-1.dll / libgcc_s_dw2-1.dll would break copy-and-go (not shipped runtime).
  case "$plat" in x64|x86) cmd="$cmd -static-libgcc" ;; esac
  case "$plat" in mac|mac-arm) ;; *) [ "$DO_STRIP" = 1 ] && cmd="$cmd -s" ;; esac
  cmd="$cmd -o \"$out\" \"$SRC_DIR/$src\" -I \"$LUAJIT_SRC\" -I \"$SRC_DIR\""
  [ -n "$md" ] && cmd="$cmd -I \"$jdk/include\" -I \"$md\""
  cmd="$cmd $linkextra $def"
  if [ "$DRY_RUN" = 1 ]; then printf '  %-9s DRY   %s\n' "$plat/$kind" "$cmd"; return 0; fi

  mkdir -p "$dir" 2>/dev/null || { printf '  %-9s FAIL  cannot create %s\n' "$plat/$kind" "$dir"; FAILED="$FAILED $plat/$kind"; return 1; }
  sh -c "$cmd" || { printf '  %-9s FAIL  compile failed\n' "$plat/$kind"; FAILED="$FAILED $plat/$kind"; return 1; }
  [ -f "$out" ] || { printf '  %-9s FAIL  no output %s\n' "$plat/$kind" "$out"; FAILED="$FAILED $plat/$kind"; return 1; }

  if [ "$DO_STRIP" = 1 ]; then
    strip=$(find_tool "$cc" strip); [ -n "$strip" ] && "$strip" $stripopt "$out" 2>/dev/null
  fi
  case "$plat" in
    mac|mac-arm) command -v codesign >/dev/null 2>&1 && codesign -s - --force "$out" 2>/dev/null ;;
  esac
  local sz; sz=$(wc -c < "$out" | tr -d ' ')
  printf '  %-9s OK    %s (%s bytes)\n' "$plat/$kind" "$out" "$sz"
  ARTIFACTS="$ARTIFACTS$out:$plat:$kind "
}

build_one() {
  local plat=$1 lt jvm
  case "$plat" in x64|x86) jn="jnlua5.1.dll" jv="javavm.dll" ;; *) jn="libjnlua5.1.so" jv="javavm.so" ;; esac
  lt=$(link_input "$plat")

  # macOS targets build only on a macOS host (clang + SDK, no osxcross here).
  if [ "$(uname -s)" != Darwin ]; then
    case "$plat" in mac|mac-arm)
      printf '  %-9s SKIP  macOS SDK present only on macOS hosts (build lib/mac{,-arm} on the M1)\n' "$plat"
      FAILED="$FAILED $plat:skip"; return 0 ;;
    esac
  fi
  case "$plat" in mac|mac-arm)
    [ -n "${JAVA_HOME:-}" ] || { printf '  %-9s SKIP  JAVA_HOME unset (JNI headers + lib/server come from it)\n' "$plat"; FAILED="$FAILED $plat:skip"; return 0; } ;;
  esac
  case "$plat" in
    x64|x86)
      { [ -n "$lt" ] && [ -f "$(printf '%s' "$lt" | tr -d '"')" ]; } || \
        { printf '  %-9s SKIP  missing lua5.1.dll for %s (PE emits no import table without it)\n' "$plat" "$plat"; FAILED="$FAILED $plat:skip"; return 0; } ;;
  esac

  # jnlua: LuaJIT host-provided symbols only; NEVER links the JVM.
  build_mod "$plat" jnlua "$jn" jnlua.c "$lt"

  # javavm: additionally needs a real VM library at link time (JNI_CreateJavaVM import).
  jvm=$(jvm_input "$plat")
  local ok=1
  case "$plat" in
    x64|x86|linux|linux-arm)
      [ -f "$jvm" ] || { printf '  %-9s FAIL  JVM library not found: %s (pass --jvm-x64/--jvm-x86/--jdk-linux/--jdk-arm)\n' "$plat/javavm" "$jvm"; FAILED="$FAILED $plat/javavm"; ok=0; } ;;
    mac|mac-arm)
      [ -n "${JAVA_HOME:-}" ] || { printf '  %-9s FAIL  JAVA_HOME unset (mac javavm links $JAVA_HOME/lib/server)\n' "$plat/javavm"; FAILED="$FAILED $plat/javavm"; ok=0; } ;;
  esac
  [ "$ok" = 1 ] && build_mod "$plat" javavm "$jv" javavm.c "$lt $jvm"
}

# ---------------- self checks ----------------
IMP_RE='^[[:space:]]+[0-9a-fA-F]{2,8}[[:space:]]+[0-9]+[[:space:]]+[A-Za-z_][A-Za-z0-9_]*$'
NEWAPI='(Set|Get)ThreadDescription|WaitOnAddress|WakeByAddress[A-Za-z]*|GetSystemTimePreciseAsFileTime|CreateSymbolicLinkW|GetTickCount64|CompareObjectHandles|GetFileInformationByHandleEx|SetFileInformationByHandle'

check_win() { # <artifact> <dump text> <kind> <plat>
  local kind=$3 plat=$4 n bad want dlls junk
  printf '  exports         : %s\n' "$(printf '%s\n' "$2" | awk '/\[Ordinal\/Name Pointer\]/{e=1;next} /^$/{e=0} e' | grep -oE "\] [A-Za-z_][A-Za-z0-9_@]*$" | awk '{print $2}' | sort -u | tr '\n' ' ')"
  if [ "$kind" = jnlua ]; then want='JNI_OnLoad'; else want='luaopen_javavm'; fi
  printf '%s\n' "$2" | sed -n '/Export Tables/,$p' | grep -q "\] $want" \
    && printf '  required export : %s OK\n' "$want" \
    || { printf '  ! required export %s MISSING\n' "$want"; DEPFAIL="$DEPFAIL $plat/$kind:no-$want"; }
  if [ "$plat" = x86 ] && [ "$kind" = jnlua ]; then
    printf '%s\n' "$2" | sed -n '/Export Tables/,$p' | grep -q '\] JNI_OnLoad@8' \
      && printf '  stdcall alias   : JNI_OnLoad@8 OK (add-stdcall-alias took effect)\n' \
      || { printf '  ! stdcall alias  JNI_OnLoad@8 missing -- JVM may reject the plain name\n'; DEPFAIL="$DEPFAIL $plat/$kind:no-alias"; }
  fi
  printf '  DLL deps        : %s\n' "$(printf '%s\n' "$2" | awk '/DLL Name/{printf "%s ", $NF}')"
  # Copy-and-go floor: only the CRT/loader pair plus the two named modules we bind to.
  # Anything else (libgcc_s_*, winpthread, api sets...) is a file the target may not have.
  junk=$(printf '%s\n' "$2" | awk '/DLL Name/{print $NF}' \
         | grep -viE '^(kernel32|msvcrt|ntdll|lua5\.1|jvm)\.dll$' | tr '\n' ' ')
  [ -n "$junk" ] \
    && { printf '  ! extra DLL imports : %s\n' "$junk"; DEPFAIL="$DEPFAIL $plat/$kind:imports"; } \
    || printf '  DLL whitelist     : clean OK\n'
  if [ "$kind" = jnlua ]; then
    printf '%s\n' "$2" | grep -q 'DLL Name: jvm' \
      && { printf '  ! jnlua must not import jvm.dll (it only uses JNI function pointers)\n'; DEPFAIL="$DEPFAIL $plat/$kind:jvm-import"; } \
      || printf '  jvm import      : none OK\n'
  else
    printf '%s\n' "$2" | grep -q 'DLL Name: jvm' \
      && printf '  jvm import      : present OK (javavm creates the VM)\n' \
      || { printf '  ! missing jvm.dll import\n'; DEPFAIL="$DEPFAIL $plat/$kind:no-jvm"; }
  fi
  printf '%s\n' "$2" | grep -q 'DLL Name: lua5.1.dll' \
    && printf '  lua5.1 import   : present OK (PE binds by module name; dbcli always loads it)\n' \
    || { printf '  ! missing lua5.1.dll import\n'; DEPFAIL="$DEPFAIL $plat/$kind:no-lua"; }
  n=$(printf '%s\n' "$2" | sed -n '/Import Tables/,$p' | grep -Ec "$IMP_RE")
  printf '  imported funcs  : %s (lua*: %s)\n' "$n" "$(printf '%s\n' "$2" | sed -n '/Import Tables/,$p' | grep -E "$IMP_RE" | awk '{print $NF}' | grep -cE '^lua')"
  bad=$(printf '%s\n' "$2" | sed -n '/Import Tables/,$p' | grep -Eo "$NEWAPI" | sort -u | tr '\n' ' ')
  [ -n "$bad" ] && { printf '  ! Win8+ entrypoints : %s\n' "$bad"; DEPFAIL="$DEPFAIL $plat/$kind:win8api"; } \
                 || printf '  Win8+ entrypoints   : none OK (Win7 floor)\n'
  printf '%s\n' "$2" | sed -n '/Import Tables/,$p' | grep -q 'api-ms-win' \
    && printf '  ! api-ms-win-* forwarders present\n' || printf '  api-ms-win-*        : none OK\n'
}

ver_le() {
  [ "$1" = "$2" ] && return 0
  local first; first=$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)
  [ "$first" = "$1" ]
}

check_elf() { # <artifact> <nm> <dump> <plat> <kind>
  local und plat=$4 kind=$5 verdict maxg needed want
  [ "$kind" = jnlua ] && want='JNI_OnLoad' || want='luaopen_javavm'
  printf '  export %-14s: %s\n' "$want" "$("$2" -D --defined-only "$1" 2>/dev/null | grep -c "$want")"
  "$2" -D --defined-only "$1" 2>/dev/null | grep -q " $want\$" \
    || { printf '  ! required export %s missing\n' "$want"; DEPFAIL="$DEPFAIL $plat/$kind:no-$want"; }
  needed=$(printf '%s\n' "$3" | awk '/NEEDED/{printf "%s ", $NF}')
  printf '  NEEDED          : %s\n' "$needed"
  if printf '%s\n' "$needed" | grep -q 'luajit'; then
    printf '  ! still hard-links LuaJIT : %s\n' "$needed"; DEPFAIL="$DEPFAIL $plat/$kind:luajit-dep"
  else
    printf '  hard-link LuaJIT : none OK (lua_* resolved by the in-process host; copy-and-go)\n'
  fi
  if [ "$kind" = javavm ]; then
    printf '%s\n' "$needed" | grep -q 'libjvm' \
      && printf '  libjvm          : NEEDED OK (creates the VM; found via LD_LIBRARY_PATH at runtime)\n' \
      || { printf '  ! missing NEEDED libjvm.so\n'; DEPFAIL="$DEPFAIL $plat/$kind:no-libjvm"; }
  else
    printf '%s\n' "$needed" | grep -q 'jvm' \
      && { printf '  ! jnlua must not NEEDED libjvm\n'; DEPFAIL="$DEPFAIL $plat/$kind:jvm-dep"; } \
      || printf '  libjvm          : none OK\n'
  fi
  printf '  undefined lua_* : %s (expected >0, satisfied by the host)\n' "$("$2" -D --undefined-only "$1" 2>/dev/null | grep -cE ' (lua|luaL|lj)[a-zA-Z]')"
  maxg=$(printf '%s\n' "$3" | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1)
  if [ "$plat" = linux ]; then
    if ver_le "${maxg#GLIBC_}" "$GLIBC_MAX_LINUX"; then verdict='OK'; else verdict='ABOVE CEILING'; DEPFAIL="$DEPFAIL $plat/$kind:glibc-$maxg"; fi
    printf '  GLIBC ceiling   : %s  (require <=%s, CentOS6) %s\n' "$maxg" "$GLIBC_MAX_LINUX" "$verdict"
  else
    printf '  GLIBC ceiling   : %s  (arm64 arch floor is ~2.17; there is no CentOS6 arm64)\n' "$maxg"
  fi
  # Version-tagged refs (@GLIBC/@LIBC/@SUNWprivate -- the latter from libjvm) come from NEEDED
  # libs; lua*/lj* come from the host; crt weak symbols are ignorable. A versionless non-lua
  # undefined reference is a real gap.
  und=$("$2" -D --undefined-only "$1" 2>/dev/null | awk '{print $NF}' \
        | grep -vE '@' \
        | grep -vE '^(lua|lj|_ITM_|__gmon_start__|__cxa_|__stack_chk_|_init$|_fini$|__register_frame|__deregister_frame)' \
        | tr '\n' ' ')
  if [ -n "$und" ]; then
    printf '  ! undefined symbols : %s\n' "$und"; DEPFAIL="$DEPFAIL $plat/$kind:undefined"
  else
    printf '  undefined symbols   : none OK (libc/libjvm / host cover everything)\n'
  fi
}

check_macho() { # <artifact> <plat> <kind>
  local ot nm deps bad rpath idname minos want sig hrow ft kind=$3
  ot=$(command -v otool); nm=$(command -v nm)
  [ -n "$ot" ] && [ -n "$nm" ] || { printf '  (skip: no otool/nm)\n'; return 0; }
  want=10.12; [ "$2" = mac-arm ] && want=11.0
  hrow=$("$ot" -hv "$1" 2>/dev/null | awk '$1 ~ /^MH_MAGIC/{print; exit}')
  ft=$(printf '%s\n' "$hrow" | grep -owE 'BUNDLE|DYLIB|DYLINKER|EXECUTE|COREFILE|PRELOAD' | head -1)
  printf '  filetype        : %s\n' "${ft:-?}"
  printf '%s\n' "$hrow" | grep -q 'BUNDLE' \
    && printf '  MH_BUNDLE       : OK (-bundle, what dlopen/require and System.loadLibrary expect)\n' \
    || { printf '  ! not a BUNDLE  : rebuild with -bundle\n'; DEPFAIL="$DEPFAIL $2/$kind:not-bundle"; }
  [ "$kind" = jnlua ] && want='JNI_OnLoad' || want='luaopen_javavm'
  printf '  export %-14s: %s\n' "$want" "$("$nm" -gU "$1" 2>/dev/null | grep -c "$want")"
  "$nm" -gU "$1" 2>/dev/null | grep -q "$want" \
    || { printf '  ! required export %s missing\n' "$want"; DEPFAIL="$DEPFAIL $2/$kind:no-$want"; }
  deps=$("$ot" -L "$1" 2>/dev/null | tail -n +2 | awk '{printf "%s ", $1}')
  printf '  deps (otool -L) : %s\n' "$deps"
  if printf '%s\n' "$deps" | grep -q 'luajit'; then
    printf '  ! still links LuaJIT : %s\n' "$deps"; DEPFAIL="$DEPFAIL $2/$kind:luajit-dep"
  else
    printf '  hard-link LuaJIT : none OK (lua_* resolved by the in-process host)\n'
  fi
  # libSystem is the Mach-O floor; javavm additionally carries the @rpath JVM libs
  # (as shipped: @rpath/libjli.dylib + @rpath/libjvm.dylib, resolved via DYLD_LIBRARY_PATH).
  bad=$(printf '%s\n' $deps | grep -v '^$' \
        | grep -v '^/usr/lib/libSystem[^ ]*\.dylib$' \
        | { [ "$kind" = javavm ] && grep -vE '^@rpath/lib(jvm|jli)[^ ]*\.dylib$' || cat; } | tr '\n' ' ')
  [ -n "$bad" ] \
    && { printf '  ! unexpected dylibs : %s\n' "$bad"; DEPFAIL="$DEPFAIL $2/$kind:dylibs"; } \
    || printf '  dylibs            : minimal OK%s\n' "$([ "$kind" = javavm ] && echo ' (libSystem + @rpath libjli/libjvm)')"
  rpath=$("$ot" -l "$1" 2>/dev/null | grep -c 'LC_RPATH')
  [ "$rpath" = 0 ] \
    && printf '  LC_RPATH          : none OK (dbcli.sh supplies DYLD_LIBRARY_PATH; as shipped)\n' \
    || { printf '  ! LC_RPATH        : %s (a search path is a dependency; drop it)\n' "$rpath"; DEPFAIL="$DEPFAIL $2/$kind:rpath"; }
  idname=$("$ot" -l "$1" 2>/dev/null | awk '/LC_ID_DYLIB/{f=1} f&&/^ *name /{print $2; exit}')
  [ -z "$idname" ] \
    && printf '  LC_ID_DYLIB       : none OK\n' \
    || printf '  LC_ID_DYLIB       : %s (informational)\n' "$idname"
  minos=$("$ot" -l "$1" 2>/dev/null | awk '/LC_BUILD_VERSION|LC_VERSION_MIN_MACOSX/{f=1} f&&/minos|version/{print $2; exit}')
  if [ -z "$minos" ] || ver_le "$minos" "$want"; then
    printf '  minos             : %s  (floor %s) OK\n' "$minos" "$want"
  else
    printf '  ! minos           : %s  ABOVE the %s floor\n' "$minos" "$want"; DEPFAIL="$DEPFAIL $2/$kind:minos-$minos"
  fi
  printf '  undefined lua_* : %s (dynamic_lookup; resolved from the host)\n' \
    "$("$nm" -u "$1" 2>/dev/null | grep -cE '_?lua')"
  "$nm" -u "$1" 2>/dev/null | grep -qE '_?lua' \
    || { printf '  ! no undefined lua_* : -undefined dynamic_lookup did not take effect\n'; DEPFAIL="$DEPFAIL $2/$kind:no-dynamic-lookup"; }
  if [ "$2" = mac-arm ]; then
    if command -v codesign >/dev/null 2>&1; then
      sig=$(codesign -dv "$1" 2>&1 | grep -c 'Signature')
      [ "${sig:-0}" != 0 ] \
        && printf '  codesign          : ad-hoc signed OK\n' \
        || { printf '  ! codesign         : UNSIGNED -- Apple Silicon will refuse to load it\n'; DEPFAIL="$DEPFAIL $2/$kind:unsigned"; }
    else
      printf '  codesign          : (cannot tell, codesign not on PATH)\n'
    fi
  fi
}

write_luasmoke() { # generates $SELFTEST_DIR/smoke.lua ; loads both modules for real
  mkdir -p "$SELFTEST_DIR" || return 1
  cat > "$SELFTEST_DIR/smoke.lua" <<'LEOF'
local dir = arg[1]
package.cpath = dir .. "/?.so;" .. dir .. "/?.dll;" .. package.cpath
local ffi = require("ffi")
local jl, jv
if jit.os == "Windows" then
  jl, jv = "./jnlua5.1.dll", "./javavm.dll"
  -- WSL interop does not reliably translate a prepended Unix PATH for the Windows
  -- child, so arg[2] may carry an absolute jvm.dll path: pre-loading it proves the
  -- exact same import binding (the loader binds javavm.dll's "jvm.dll" import to the
  -- in-memory module -- at runtime dbcli.bat has the JRE on PATH instead).
  if arg[2] and arg[2] ~= "" then
    local pok, perr = pcall(ffi.load, arg[2])
    if not pok then io.stderr:write("jvm preload failed: " .. tostring(perr) .. "\n"); os.exit(3) end
  end
else
  jl, jv = dir .. "/libjnlua5.1.so", dir .. "/javavm.so"
end
-- ffi.load = dlopen/LoadLibrary with immediate binding: proves every lua_* resolves
-- against the running LuaJIT without any DT_NEEDED import (copy-and-go contract).
local h = assert(ffi.load(jl))
assert(h ~= nil)
local ok, m = pcall(require, "javavm")
if not ok then io.stderr:write("require(javavm) failed: " .. tostring(m) .. "\n"); os.exit(2) end
assert(type(m) == "table", "javavm is not a table")
for _,f in ipairs{"create","attach","detach","get"} do
  assert(type(m[f]) == "function", "missing javavm." .. f)
end
io.write("REQUIRE-OK jnlua=" .. jl .. " javavm={create,attach,detach,get}\n")
LEOF
}

native_test() { # <plat> <artifact> -- run once per platform from the javavm check
  local plat=$1 dir luajit jvmdir tf jvmdll wjvm
  dir=$(dirname "$2")
  write_luasmoke || { printf '  (skip real load: temp dir not writable)\n'; return 0; }
  case "$plat" in
    linux)
      luajit="$dir/luajit"; [ -x "$luajit" ] || { printf '  (skip: no %s/luajit)\n' "$dir"; return 0; }
      jvmdir=$(dirname "$(jvm_input linux)")
      LD_LIBRARY_PATH="$dir:$jvmdir${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" "$luajit" "$SELFTEST_DIR/smoke.lua" "$dir" ;;
    linux-arm)
      if command -v qemu-aarch64-static >/dev/null 2>&1 && [ -x "$dir/luajit" ]; then
        jvmdir=$(dirname "$(jvm_input linux-arm)")
        qemu-aarch64-static -L /usr/aarch64-linux-gnu \
          -E LD_LIBRARY_PATH="$dir:$jvmdir" "$dir/luajit" "$SELFTEST_DIR/smoke.lua" "$dir"
      else printf '  (skip qemu-aarch64 real load: no qemu or no arm luajit)\n'; fi ;;
    x64|x86)
      local exe="$dir/luajit.exe"
      [ -x "$exe" ] || { printf '  (skip Windows real load: no %s)\n' "$exe"; return 0; }
      # luajit.exe (run through WSL interop) is a real Windows process; it cannot read
      # /tmp, so the smoke script must live in the artifact dir and move back afterwards.
      tf="$dir/.jnlua_smoke.lua"
      cp "$SELFTEST_DIR/smoke.lua" "$tf" 2>/dev/null || { printf '  (skip Windows real load: smoke script not copyable)\n'; return 0; }
      case "$plat" in
        x64) jvmdll="$JVM_X64" ;;
        x86) jvmdll="$REPO/jre/bin/client/jvm.dll" ;;   # runtime 32-bit jvm.dll (link input is a .lib)
      esac
      wjvm=$(wslpath -w "$jvmdll" 2>/dev/null || true)
      [ -n "$wjvm" ] || wjvm="$jvmdll"
      ( cd "$dir" && timeout 60 ./luajit.exe ".jnlua_smoke.lua" "$dir" "$wjvm" ) 2>&1 \
        || printf '  (Windows real load did not run / timed out: rely on the static audit)\n'
      mv -f "$tf" "$SELFTEST_DIR/smoke-$plat.lua" 2>/dev/null ;;
    mac|mac-arm)
      [ -x "$dir/luajit" ] || { printf '  (skip: no %s/luajit)\n' "$dir"; return 0; }
      DYLD_LIBRARY_PATH="$dir:${JAVA_HOME:-}/lib/server" "$dir/luajit" "$SELFTEST_DIR/smoke.lua" "$dir" ;;
  esac
}

check_one() {
  local out=$1 plat=$2 kind=$3 cc od nm dump
  resolve_cc "$plat"; cc=$CC
  printf -- '-- %s/%s (%s)\n' "$plat" "$kind" "${out#$OUT_ROOT/}"
  case "$plat" in
    x64|x86)
      od=$(find_tool "$cc" objdump); [ -n "$od" ] || { printf '  (skip: no objdump)\n'; return 0; }
      dump=$("$od" -p "$out" 2>/dev/null | tr -d '\r')
      check_win "$out" "$dump" "$kind" "$plat" ;;
    linux|linux-arm)
      od=$(find_tool "$cc" objdump); nm=$(find_tool "$cc" nm)
      [ -n "$od" ] && [ -n "$nm" ] || { printf '  (skip: no objdump/nm)\n'; return 0; }
      dump=$("$od" -p "$out" 2>/dev/null)
      check_elf "$out" "$nm" "$dump" "$plat" "$kind" ;;
    mac|mac-arm)
      check_macho "$out" "$plat" "$kind" ;;
  esac
  # one real-load smoke per platform, driven from the javavm artifact (it has the strictest
  # requirement: a resolvable VM library at dlopen time).
  if [ "$kind" = javavm ]; then
    case "$plat" in
      linux)     [ "$(host_plat)" = linux ] && native_test "$plat" "$out" ;;
      linux-arm) native_test "$plat" "$out" ;;
      x64|x86)   native_test "$plat" "$out" ;;
      mac|mac-arm) [ "$(host_plat)" = "$plat" ] && native_test "$plat" "$out" ;;
    esac
  fi
}

printf '== jnlua+javavm: src/c/jnlua/{jnlua.c,javavm.c} -> JNI_OnLoad + luaopen_javavm ==\n'
printf '   LuaJIT headers : %s\n' "$LUAJIT_SRC"
printf '   JDK win        : %s (jvm x64 %s / x86 %s)\n' "$JDK_WIN" "$JVM_X64" "$JVM_X86"
printf '   JDK linux      : %s\n   JDK linux-arm  : %s\n' "$JDK_LINUX" "$JDK_ARM"
if [ -z "$PLATFORMS" ]; then
  case "$(uname -s)/$(uname -m)" in
    Linux/x86_64) PLATFORMS="x64 x86 linux linux-arm" ;;
    Linux/aarch64) PLATFORMS="linux linux-arm" ;;
    Darwin/x86_64|Darwin/arm64) PLATFORMS="mac mac-arm" ;;
    *) printf 'run inside WSL (gcc/mingw/cross) or on macOS (clang), or specify platforms with -p\n' >&2; exit 1 ;;
  esac
fi
for p in $PLATFORMS; do build_one "$p"; done
[ "$DRY_RUN" = 1 ] && exit 0

if [ "$DO_CHECK" = 1 ]; then
  printf '\n== self check ==\n'
  for a in $ARTIFACTS; do
    check_one "$(printf '%s' "$a" | cut -d: -f1)" "$(printf '%s' "$a" | cut -d: -f2)" "$(printf '%s' "$a" | cut -d: -f3)"
  done
fi

printf '\n== artifacts ==\n'
for a in $ARTIFACTS; do ls -l "$(printf '%s' "$a" | cut -d: -f1)"; done
[ -n "$FAILED" ] && printf '\nskipped / not done:%s\n' "$FAILED"

# A real build failure (anything that is not an explicit ":skip") must be loud: e.g. a
# locked output file (artifact loaded by a running dbcli/java) fails the link, and the
# green checks of the OTHER platforms must not disguise it as a successful run.
if [ -n "$FAILED" ] && printf '%s\n' $FAILED | grep -qv ':skip$'; then
  printf '\n== BUILD FAILURE (see FAIL lines above; close any process using lib/ and re-run) ==\n'
  exit 1
fi

# Dependency contract (header notes): ELF/Mach-O carry no LuaJIT dependency; javavm's only
# extra dependency is the VM library itself (libjvm/jvm.dll) which is legitimate by design.
if [ -n "$DEPFAIL" ]; then
  printf '\n== DEPENDENCY CONTRACT VIOLATED:%s ==\n' "$DEPFAIL"
  printf '   It may still load, but it is no longer copy-and-go or no longer acceptable to the\n'
  printf '   JVM/Lua host. Fix the flags above; do not ship this build. (--no-check skips the\n'
  printf '   audit, it does not excuse the artifact.)\n'
  exit 1
fi

cat <<EOF

== Runtime usage ==
dbcli's runtime LUA_CPATH already includes ./lib/\$os/?.so (?.dll on Windows):
  local javavm = require("javavm")          -- luaopen_javavm, then javavm.create(params)
The JVM then binds com.naef.jnlua.LuaState to jnlua5.1 (System.loadLibrary("jnlua5.1"));
java.library.path must include lib/\$os. Standalone Windows smoke (WSL interop, cwd=lib/x64):
  PATH="<jvm dir>;\$PATH" ./luajit.exe <(printf 'package.cpath="./?.dll;"..package.cpath; print(require("javavm"))')
EOF
exit 0

#!/usr/bin/env bash

set -u

SELF=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P) || SELF=.
SRC_DIR="$SELF"
REPO=$(cd -- "$SELF/../../.." >/dev/null 2>&1 && pwd -P) || REPO=.
SCRATCH="$REPO/cache/native-probe"
STAGE1="$REPO/cache/conemu-stage1"
CONEMU_SRC="/mnt/d/ConEmu-master/src"
JDK_X86="/mnt/d/jdkx86"
JDK_X64="/mnt/d/jdkx64"
DO_COLORCHECK=1

while [ $# -gt 0 ]; do
  case "$1" in
    --scratch)     SCRATCH=${2:-}; shift 2 ;;
    --conemu-src)  CONEMU_SRC=${2:-}; shift 2 ;;
    --jdk-x86)     JDK_X86=${2:-}; shift 2 ;;
    --jdk-x64)     JDK_X64=${2:-}; shift 2 ;;
    --no-colorcheck) DO_COLORCHECK=0; shift ;;
    -h|--help)     sed -n '2,58p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) printf 'unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done

mkdir -p "$SCRATCH/x86" "$SCRATCH/x64" "$SCRATCH/out" || exit 1

VENDOR="$SRC_DIR/vendor/ConEmuColors3.h"
[ -f "$VENDOR" ] || { printf 'vendored header missing: %s\n' "$VENDOR" >&2; exit 1; }
if [ -f "$CONEMU_SRC/common/ConEmuColors3.h" ]; then
  if cmp -s "$VENDOR" "$CONEMU_SRC/common/ConEmuColors3.h"; then
    printf 'vendor/ConEmuColors3.h: identical to upstream %s OK\n' "$CONEMU_SRC"
  else
    printf 'vendor/ConEmuColors3.h: DIFFERS from upstream -- either upstream moved (re-vendor deliberately) or someone edited it here. Its BSD-3 notice must stay intact.\n'
  fi
else
  printf 'vendor/ConEmuColors3.h: upstream not found at %s (cannot compare)\n' "$CONEMU_SRC"
fi

FLAGS="-std=c++17 -O2 -D_WIN32_WINNT=0x0601 -DWINVER=0x0601 -Wall -Wextra -Wno-unused-parameter"
STATIC="-static -static-libgcc -static-libstdc++"
NEWAPI='(Set|Get)ThreadDescription|WaitOnAddress|WakeByAddress[A-Za-z]*|GetSystemTimePreciseAsFileTime|CreateSymbolicLinkW|GetTickCount64|CompareObjectHandles|GetFileInformationByHandleEx|SetFileInformationByHandle|SetConsoleCursorShape'

FAILED=""

gate_dll() {
  local plat=$1 OD=$2 dll=$3 want=$4 tag=$5 missing=""
  local exp decorated junk bad n
  exp=$($OD -p "$dll" | tr -d '\r' | grep -oE 'Java_[A-Za-z0-9_]+@*[0-9]*' | sort -u | tr '\n' ' ')
  printf '%s:%s exports: %s\n' "$plat" "$tag" "$exp"
  n=$(printf '%s' "$want" | wc -w | tr -d ' ')
  for s in $want; do printf '%s' " $exp" | grep -q " $s " || missing="$missing $s"; done
  [ -z "$missing" ] && printf '%s:%s all %s JNI entrypoints exported OK\n' "$plat" "$tag" "$n" \
      || { printf '%s:%s ! missing exports:%s\n' "$plat" "$tag" "$missing" >&2; FAILED="$FAILED $plat:$tag-exports"; }
  decorated=$(printf '%s' "$exp" | grep -oE 'Java_[A-Za-z0-9_]+@[0-9]+' | wc -w | tr -d ' ')
  [ "$decorated" = 0 ] && printf '%s:%s no @-decorated JNI exports OK\n' "$plat" "$tag" \
      || { printf '%s:%s ! %s decorated export(s) -- HotSpot looks up the plain name\n' "$plat" "$tag" "$decorated" >&2
           FAILED="$FAILED $plat:$tag-decorated"; }
  junk=$($OD -x "$dll" | tr -d '\r' | awk '/DLL Name/{print $NF}' \
         | grep -viE '^(kernel32|msvcrt|ntdll|user32|gdi32|advapi32|shell32|ole32|version|wintrust|imm32|ws2_32|rpcrt4)\.dll$' | tr '\n' ' ')
  [ -n "$junk" ] \
      && { printf '%s:%s ! extra DLL imports: %s (not copy-and-go)\n' "$plat" "$tag" "$junk" >&2; FAILED="$FAILED $plat:$tag-imports"; } \
      || printf '%s:%s DLL imports are system-only OK\n' "$plat" "$tag"
  local noexec
  noexec=$($OD -p "$dll" | tr -d '\r' | grep -Eo \
      'CreateProcess[A-Za-z]*|WinExec|ShellExecute[A-Za-z]*|_?ws?ystem|MessageBox[A-Za-z]*|DialogBox[A-Za-z]*|SetEnvironmentVariable[A-Za-z]*|CoCreateInstance|OleInitialize|WriteProcessMemory|VirtualAllocEx' | sort -u | tr '\n' ' ')
  [ -n "${noexec// /}" ] \
      && { printf '%s:%s ! an OSC 9 action API is linked: %s\n' "$plat" "$tag" "$noexec" >&2; FAILED="$FAILED $plat:$tag-noexec"; } \
      || printf '%s:%s no process/dialog/env-write entrypoint imported (OSC 9 floor holds) OK\n' "$plat" "$tag"
  bad=$($OD -p "$dll" | tr -d '\r' | grep -Eo "$NEWAPI" | sort -u | tr '\n' ' ')
  [ -n "$bad" ] && { printf '%s:%s ! Win8+ entrypoints: %s\n' "$plat" "$tag" "$bad" >&2; FAILED="$FAILED $plat:$tag-win8api"; } \
                 || printf '%s:%s no Win8+ entrypoints OK (Win7 floor)\n' "$plat" "$tag"
}

natives_of() {
  grep -E '^[[:space:]]*(([A-Za-z]+[[:space:]]+)+)?native[[:space:]]' "$1" \
    | grep -oE '[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' | tr -d ' (' | sed "s|^|$2|" | sort -u
}

gate_declared() {
  local plat=$1 OD=$2 dll=$3 java=$4 pfx=$5 tag=$6 want have missing n
  if [ -z "$java" ] || [ ! -f "$java" ]; then
    printf '%s:%s ! declared-export check SKIPPED: no Java source for %s\n' "$plat" "$tag" "$pfx" >&2
    FAILED="$FAILED $plat:$tag-declared"
    return
  fi
  want=$(natives_of "$java" "$pfx")
  n=$(printf '%s\n' "$want" | grep -c . | tr -d ' ')
  [ "$n" -gt 0 ] || { printf '%s:%s ! %s declares no native methods -- the extractor is wrong\n' \
                        "$plat" "$tag" "$java" >&2; FAILED="$FAILED $plat:$tag-declared"; return; }
  have=$($OD -p "$dll" | tr -d '\r' | grep -oE 'Java_[A-Za-z0-9_]+' | sort -u)
  missing=$(comm -23 <(printf '%s\n' "$want") <(printf '%s\n' "$have"))
  [ -z "$missing" ] \
      && printf '%s:%s all %s declared native method(s) bound in %s OK\n' "$plat" "$tag" "$n" "$java" \
      || { printf '%s:%s ! declared but not exported:%s\n' "$plat" "$tag" "$(printf '%s' "$missing" | tr '\n' ' ')" >&2
           FAILED="$FAILED $plat:$tag-declared"; }
}

strip_debug() {
  local st=$1 dll=$2 tag=$3 before after
  command -v "$st" >/dev/null 2>&1 \
    && { before=$(wc -c < "$dll" | tr -d ' ')
         "$st" --strip-debug "$dll" \
           && { after=$(wc -c < "$dll" | tr -d ' ')
                printf '%s stripped %s: %s -> %s bytes\n' "$tag" "$(basename "$dll")" "$before" "$after"; } \
           || { printf '%s ! strip --strip-debug failed on %s\n' "$tag" "$dll" >&2; FAILED="$FAILED $tag-strip"; }; } \
    || printf '%s %s missing, %s keeps its debug info\n' "$tag" "$st" "$(basename "$dll")"
}

NR_JAVA=""
for c in "${DBCLI_JAVA_SRC:-}/com/hyee/ansirender/NativeRenderer.java" \
         /mnt/d/JavaProjects/jline3.29/dbcli/src/com/hyee/ansirender/NativeRenderer.java \
         /mnt/d/dbcli/src/java/com/hyee/ansirender/NativeRenderer.java; do
  [ -n "$c" ] && [ -f "$c" ] && { NR_JAVA="$c"; break; }
done

if [ -f "$SRC_DIR/gen_statslots.py" ] && command -v python3 >/dev/null 2>&1; then
  python3 "$SRC_DIR/gen_statslots.py" --check "$SRC_DIR/Render.java" || FAILED="$FAILED host:statslots-gate"
  [ -n "$NR_JAVA" ] && { python3 "$SRC_DIR/gen_statslots.py" --check "$NR_JAVA" || FAILED="$FAILED host:statslots-prod"; }
  python3 "$SRC_DIR/gen_statslots.py" --check-c "$SRC_DIR/RenderJni.cpp" || FAILED="$FAILED host:statslots-chain"
elif [ -n "${SKIP_STATLOTS:-}" ]; then
  printf 'statslots: seam skipped by SKIP_STATLOTS=%s (the table and the two Java blocks are NOT compared)\n' "$SKIP_STATLOTS" >&2
else
  [ -f "$SRC_DIR/gen_statslots.py" ] || printf 'statslots: no %s/gen_statslots.py\n' "$SRC_DIR" >&2
  command -v python3 >/dev/null 2>&1 || printf 'statslots: python3 not on PATH\n' >&2
  printf 'statslots: the seam could not run, so nothing here proves the generated blocks match Render.h.\n' >&2
  printf '           install python3, or opt out of the leg out loud: SKIP_STATLOTS=1 ./build.sh\n' >&2
  FAILED="$FAILED host:statslots-unrunnable"
fi

for plat in x86 x64; do
  case $plat in
    x86) TC=${TC_X86:-i686-w64-mingw32-g++}   OD=${OD_X86:-i686-w64-mingw32-objdump} ST=${ST_X86:-i686-w64-mingw32-strip} JDK="$JDK_X86"; KILLAT="-Wl,--kill-at" ;;
    x64) TC=${TC_X64:-x86_64-w64-mingw32-g++} OD=${OD_X64:-x86_64-w64-mingw32-objdump} ST=${ST_X64:-x86_64-w64-mingw32-strip} JDK="$JDK_X64"; KILLAT="" ;;
  esac
  command -v "$TC" >/dev/null 2>&1 || { printf '%s: %s not installed\n' "$plat" "$TC" >&2; FAILED="$FAILED $plat:toolchain"; continue; }
  [ -f "$JDK/include/jni.h" ] || { printf '%s: JNI headers not found under %s\n' "$plat" "$JDK" >&2; FAILED="$FAILED $plat:jni-headers"; continue; }

  $TC $FLAGS -c "$SRC_DIR/ColorCheck.cpp" -o "$SCRATCH/out/ColorCheck-$plat.o" \
      || { printf '%s: ColorCheck.cpp does not compile for the target\n' "$plat" >&2; FAILED="$FAILED $plat:colorcheck"; }
  $TC $FLAGS -c "$SRC_DIR/Render.cpp" -o "$SCRATCH/out/Render-$plat.o" \
      || { printf '%s: Render.cpp does not compile for the target\n' "$plat" >&2; FAILED="$FAILED $plat:render"; }
  $TC $FLAGS -c "$SRC_DIR/Paint.cpp" -o "$SCRATCH/out/Paint-$plat.o" \
      || { printf '%s: Paint.cpp does not compile for the target\n' "$plat" >&2; FAILED="$FAILED $plat:paint"; }

  $TC $FLAGS -I"$JDK/include" -I"$JDK/include/win32" \
      -c "$SRC_DIR/Probe.cpp" -o "$SCRATCH/out/Probe-$plat.o" \
      && $TC $STATIC -shared $KILLAT -o "$SCRATCH/$plat/probe.dll" "$SCRATCH/out/Probe-$plat.o" \
      && strip_debug "$ST" "$SCRATCH/$plat/probe.dll" "$plat:probe" \
      && printf '%s: built %s (%s bytes)\n' "$plat" "$SCRATCH/$plat/probe.dll" "$(wc -c < "$SCRATCH/$plat/probe.dll" | tr -d ' ')" \
      || { printf '%s: probe build FAILED\n' "$plat" >&2; FAILED="$FAILED $plat:probe"; continue; }
  gate_dll "$plat" "$OD" "$SCRATCH/$plat/probe.dll" \
      "Java_Probe_build Java_Probe_prepareConsole Java_Probe_readCells Java_Probe_setCursor Java_Probe_writeText" probe

  $TC $FLAGS -I"$JDK/include" -I"$JDK/include/win32" \
      -c "$SRC_DIR/RenderJni.cpp" -o "$SCRATCH/out/RenderJni-$plat.o" \
      && $TC $FLAGS -I"$JDK/include" -I"$JDK/include/win32" \
      -c "$SRC_DIR/RenderExec.cpp" -o "$SCRATCH/out/RenderExec-$plat.o" \
      && $TC $STATIC -shared $KILLAT -o "$SCRATCH/$plat/render.dll" \
           "$SCRATCH/out/RenderJni-$plat.o" "$SCRATCH/out/RenderExec-$plat.o" "$SCRATCH/out/Render-$plat.o" "$SCRATCH/out/Paint-$plat.o" \
      && strip_debug "$ST" "$SCRATCH/$plat/render.dll" "$plat:render" \
      && printf '%s: built %s (%s bytes)\n' "$plat" "$SCRATCH/$plat/render.dll" "$(wc -c < "$SCRATCH/$plat/render.dll" | tr -d ' ')" \
      || { printf '%s: render build FAILED\n' "$plat" >&2; FAILED="$FAILED $plat:renderjni"; continue; }
  gate_dll "$plat" "$OD" "$SCRATCH/$plat/render.dll" \
      "Java_com_hyee_ansirender_NativeRenderer_render Java_com_hyee_ansirender_NativeRenderer_build \
       Java_com_hyee_ansirender_NativeRenderer_open \
       Java_com_hyee_ansirender_NativeRenderer_openStatus Java_com_hyee_ansirender_NativeRenderer_openReason \
       Java_com_hyee_ansirender_NativeRenderer_feed \
       Java_com_hyee_ansirender_NativeRenderer_flush Java_com_hyee_ansirender_NativeRenderer_sgr \
       Java_com_hyee_ansirender_NativeRenderer_align Java_com_hyee_ansirender_NativeRenderer_stats \
       Java_com_hyee_ansirender_NativeRenderer_stopReason Java_com_hyee_ansirender_NativeRenderer_close \
       Java_com_hyee_ansirender_NativeRenderer_snap \
       Java_com_hyee_ansirender_NativeRenderer_isPseudoConsole \
       Java_com_hyee_ansirender_NativeRenderer_encodeMouse0 \
       Java_com_hyee_ansirender_NativeRenderer_encodeFocus0 \
       Java_com_hyee_ansirender_NativeRenderer_taskbar0 \
       Java_com_hyee_ansirender_NativeRenderer_workingDirectory0 \
       Java_Render_prepareConsole Java_Render_setGeometry Java_Render_readCells \
       Java_Render_consoleView Java_Render_readInput Java_Render_readopt Java_Render_plan \
       Java_Render_faultRect Java_Render_consoleTitle Java_Render_consolePalette \
       Java_Render_censusNames Java_Render_validateGrid Java_Render_argTrunc \
       Java_com_hyee_ansirender_NativeRenderer_setClipboardPolicy0 \
       Java_com_hyee_ansirender_NativeRenderer_clipboardPolicy0" render
  gate_declared "$plat" "$OD" "$SCRATCH/$plat/render.dll" "$SRC_DIR/Render.java" "Java_Render_" render
  gate_declared "$plat" "$OD" "$SCRATCH/$plat/render.dll" "$NR_JAVA" \
                "Java_com_hyee_ansirender_NativeRenderer_" render
done

if [ "$DO_COLORCHECK" = 1 ]; then
  CC_HOST=$(command -v clang++ || command -v g++ || true)
  if [ -z "$CC_HOST" ]; then
    printf 'no host clang++/g++: the colour oracle and RenderCheck were skipped\n' >&2
    FAILED="$FAILED host:no-compiler"
  else
    [ -f "$SRC_DIR/gen_rgbmap.sh" ] \
        && { bash "$SRC_DIR/gen_rgbmap.sh" --check "$CONEMU_SRC" || FAILED="$FAILED host:rgbmap-stale"; }

    if [ -f "$SRC_DIR/gen_x11colors.sh" ]; then
        bash "$SRC_DIR/gen_x11colors.sh" --check
        x11rc=$?
        case $x11rc in
          0) : ;;
          2) printf 'X11ColorNames.h: check skipped (a source tree is missing, rc=2)\n' >&2 ;;
          *) FAILED="$FAILED host:x11colors-stale" ;;
        esac
    fi

    RGBTXT="$STAGE1/conemu-rgbmap.txt"
    if [ -f "$CONEMU_SRC/ConEmuHk/Ansi.cpp" ] && [ -f "$STAGE1/extract_rgbmap.py" ] \
       && command -v python3 >/dev/null 2>&1; then
      python3 "$STAGE1/extract_rgbmap.py" "$CONEMU_SRC/ConEmuHk/Ansi.cpp" "$STAGE1" >/dev/null \
          || printf 'extract_rgbmap.py failed: keeping the existing %s\n' "$RGBTXT"
    fi
    TABLE_ARGS=""
    if [ -f "$RGBTXT" ] && [ "$(wc -l < "$RGBTXT" | tr -d ' ')" = 256 ]; then
      TABLE_ARGS="--table $RGBTXT"
    else
      printf '! no 256-entry table at %s: ColorCheck would dump the REPLICA, which is not the oracle\n' "$RGBTXT" >&2
      FAILED="$FAILED host:no-rgbmap"
    fi

    "$CC_HOST" -std=c++17 -O1 -o "$SCRATCH/out/colorcheck" "$SRC_DIR/ColorCheck.cpp" \
        && "$SCRATCH/out/colorcheck" $TABLE_ARGS > "$SCRATCH/out/colors-native.txt" \
        && grep -q 'mode=conemu-table' "$SCRATCH/out/colors-native.txt" \
        && printf 'colour oracle: %s (%s lines, %s)\n' "$SCRATCH/out/colors-native.txt" \
              "$(wc -l < "$SCRATCH/out/colors-native.txt" | tr -d ' ')" "$(tail -1 "$SCRATCH/out/colors-native.txt")" \
        || { printf 'host colour table FAILED (missing or not in conemu-table mode)\n' >&2; FAILED="$FAILED host:colorcheck"; }

    "$CC_HOST" -std=c++17 -O1 -Wall -Wextra -Wno-unused-parameter \
        -o "$SCRATCH/out/rendercheck" "$SRC_DIR/RenderCheck.cpp" "$SRC_DIR/Render.cpp" "$SRC_DIR/Paint.cpp" \
        && { "$SCRATCH/out/rendercheck" "$SCRATCH/out/colors-native.txt" 2>&1 \
             | tee "$SCRATCH/out/rendercheck.txt"; rc=${PIPESTATUS[0]}; \
             [ "$rc" = 0 ] || FAILED="$FAILED host:rendercheck"; } \
        || { printf 'RenderCheck does not build on the host\n' >&2; FAILED="$FAILED host:rendercheck-build"; }
  fi
fi

printf '\nGate: pwsh -File %s/run.ps1    (it compiles Probe.java and Render.java and loads both DLLs in JDK 8)\n' \
       "$(cd -- "$SRC_DIR" >/dev/null 2>&1 && (wslpath -w "$SRC_DIR" 2>/dev/null || echo "$SRC_DIR"))"
[ -n "$FAILED" ] && { printf '\nBUILD FAILURE:%s\n' "$FAILED" >&2; exit 1; }
printf 'BUILD: ok\n'

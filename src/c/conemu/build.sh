#!/usr/bin/env bash
#
# build.sh -- cross-build the ConEmu-tier native console component from src/c/conemu with the
#             WSL MinGW-w64 toolchain, for BOTH bitnesses the JVM runs on.
#
# What is here and why:
#   Probe.cpp     -> cache/native-probe/{x86,x64}/probe.dll
#                     stage-0 capability probe: does a MinGW cross DLL load in JDK 8, can native
#                     code write and read back console cells (the oracle the writer needs), and
#                     which ReadConsoleOutputW rectangle convention conhost accepts here.
#                     Driven by run.ps1 -> Probe.java on D:\jdkx86 and D:\jdkx64.
#   ColorCheck.cpp-> cache/native-probe/out/colors-native.txt
#                     runs vendor/ConEmuColors3.h's 256-colour/truecolour -> 16-colour folding and
#                     dumps the whole table, so stage 1 can diff it against the folding that
#                     shipped in the Java rectangle writer, BulkCellWriter (the §12.4 / §14.1 colour
#                     fixes; that class was retired on 2026-09-23) over the full
#                     domain instead of the 32 samples those rounds used.
#                     MUST be dumped in --table mode (see the colour oracle note below): the replica
#                     formula disagrees with ConEmu's own RgbMap on 15 entries.
#   Render.cpp    -> cache/native-probe/out/Render-{x86,x64}.o, linked into render.dll
#                     the console-free parser + grid model (Render.h states its parity targets).
#   Paint.cpp     -> .../Paint-{x86,x64}.o, linked into render.dll, and compiled on the HOST too
#                     the console-free geometry: rc_plan_paint turns damage + a viewport scroll into an
#                     operation list (slide the window / scroll the buffer / these row runs / cursor).
#                     This is where the shipped Java writer's §13, §14.1 and §21 bugs lived, and it
#                     needs no console to enumerate, so RenderCheck section 6 pins it.
#   RenderJni.cpp -> cache/native-probe/{x86,x64}/render.dll
#                     the JNI seam: open/feed/flush/align/stats/close, and nothing else. It executes
#                     the plan and reads the console's shape; it decides no geometry. Driven by
#                     run.ps1 -> Render.java, whose gate asserts on cells read back out of conhost.
#   RenderCheck.cpp -> cache/native-probe/out/rendercheck, run as part of the build
#                     the host gate for Render.cpp + Paint.cpp: replays colors-native.txt through rc_feed,
#                     cross checks rc_width against the generated width tables, then asserts the escape
#                     grammar, the grid geometry and the paint plan, and finally re-feeds every corpus
#                     string one UTF-16 unit at a time. A failure is a build failure -- these are the
#                     rules that do NOT need a Windows console, so nothing about them should ever be
#                     settled by looking at a terminal.
#
# The colour oracle: colors-native.txt is produced from cache/conemu-stage1/conemu-rgbmap.txt, which
# extract_rgbmap.py pulls out of upstream's Ansi.cpp. Two independent extractions (that Python regex,
# and gen_rgbmap.sh's awk -> vendor/ConEmuRgbMap.h) reading one source is the point: RenderCheck's
# "RgbMap identity" assertion fails if either parser misreads the table, which is exactly the failure
# mode where the vendored numbers quietly stop being upstream's.
#
# Toolchain notes (each of these was paid for once, do not "simplify" them away):
#   * --kill-at is REQUIRED on x86: JNICALL is __stdcall there, so without it the export table
#     carries Java_Probe_build@8 and HotSpot's plain-name GetProcAddress fails. x64 needs nothing
#     because there JNICALL is the standard 64-bit convention.
#   * -static -static-libgcc -static-libstdc++ keeps the DLL copy-and-go: an import of
#     libgcc_s_dw2-1.dll / libstdc++-6.dll would mean shipping a runtime we do not ship.
#   -D_WIN32_WINNT=0x0601 is the Win7 floor this library supports; the API whitelist check below enforces
#     that nothing Win8+ crept in (same rule src/c/jnlua/build.sh applies).
#   * JNI headers come from the JDK of the matching bitness (jni.h + include/win32/jni_md.h).
#   * The runnable half of ColorCheck and all of RenderCheck are HOST builds (clang++ here): there is
#     no wine on this box, so a Windows binary could be built but not executed. Four typedefs are the
#     whole price for ColorCheck; Render.cpp needs none, which is why the model is console-free.
#   * Objects, DLLs and dumps all go under cache/ (scratch). This tree holds sources only.
#
# Usage: src/c/conemu/build.sh [--scratch DIR] [--no-colorcheck] [-h]

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

# ---- the vendored header must stay a byte-for-byte copy of upstream --------------------------
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
NEWAPI='(Set|Get)ThreadDescription|WaitOnAddress|WakeByAddress[A-Za-z]*|GetSystemTimePreciseAsFileTime|CreateSymbolicLinkW|GetTickCount64|CompareObjectHandles|GetFileInformationByHandleEx|SetFileInformationByHandle'

FAILED=""

# One gate applied to every DLL: the export table HotSpot's GetProcAddress reads, the import table that
# has to stay system-only, and the Win8+ whitelist. On x86 every JNI name must be UNDECORATED (no @8):
# that is exactly what --kill-at buys, and a decorated-only table loads but never binds.
gate_dll() {  # $1 plat  $2 objdump  $3 dll  $4 "space separated expected exports"  -> appends FAILED
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
  bad=$($OD -p "$dll" | tr -d '\r' | grep -Eo "$NEWAPI" | sort -u | tr '\n' ' ')
  [ -n "$bad" ] && { printf '%s:%s ! Win8+ entrypoints: %s\n' "$plat" "$tag" "$bad" >&2; FAILED="$FAILED $plat:$tag-win8api"; } \
                 || printf '%s:%s no Win8+ entrypoints OK (Win7 floor)\n' "$plat" "$tag"
}

# Drop the DWARF that the MinGW runtime objects carry. It is not ours: FLAGS has no -g, and each of
# our .o files has 0 bytes of .debug_*. The distro ships dllcrt2.o/crtbegin.o/libmingw32.a built with
# -g, and the linker drags them in whatever -static says -- dropping -static left the 340793 bytes of
# .debug_* exactly as large. They have no ALLOC flag, so they cost disk and repo churn, never RAM.
# --strip-debug on purpose: the COFF symbol table survives, so a native fault inside render.dll still
# resolves to a function name in a stack dump. Measured inert on the same file before/after -- .text
# and .rdata byte-identical, all 13 JNI exports intact. (Compare sections only within ONE file:
# two links of the same objects differ because GNU ld randomizes the PE ImageBase.)
strip_debug() {  # $1 strip tool  $2 dll  $3 "plat:tag"  -> appends FAILED
  local st=$1 dll=$2 tag=$3 before after
  command -v "$st" >/dev/null 2>&1 \
    && { before=$(wc -c < "$dll" | tr -d ' ')
         "$st" --strip-debug "$dll" \
           && { after=$(wc -c < "$dll" | tr -d ' ')
                printf '%s stripped %s: %s -> %s bytes\n' "$tag" "$(basename "$dll")" "$before" "$after"; } \
           || { printf '%s ! strip --strip-debug failed on %s\n' "$tag" "$dll" >&2; FAILED="$FAILED $tag-strip"; }; } \
    || printf '%s %s missing, %s keeps its debug info\n' "$tag" "$st" "$(basename "$dll")"
}

for plat in x86 x64; do
  case $plat in
    x86) TC=i686-w64-mingw32-g++  OD=i686-w64-mingw32-objdump  ST=i686-w64-mingw32-strip  JDK="$JDK_X86"; KILLAT="-Wl,--kill-at" ;;
    x64) TC=x86_64-w64-mingw32-g++ OD=x86_64-w64-mingw32-objdump ST=x86_64-w64-mingw32-strip JDK="$JDK_X64"; KILLAT="" ;;
  esac
  command -v "$TC" >/dev/null 2>&1 || { printf '%s: %s not installed\n' "$plat" "$TC" >&2; FAILED="$FAILED $plat:toolchain"; continue; }
  [ -f "$JDK/include/jni.h" ] || { printf '%s: JNI headers not found under %s\n' "$plat" "$JDK" >&2; FAILED="$FAILED $plat:jni-headers"; continue; }

  # ColorCheck and Paint are cross-compiled but never run here: those builds only prove the code
  # compiles for the real target against the real windows.h. (RenderCheck runs Paint.cpp on the host.)
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

  # The renderer itself: model + planner + JNI shell. the Java binding is the production
  # caller; the Java_Render_* exports are the gate's own scaffolding (see RenderJni.cpp).
  $TC $FLAGS -I"$JDK/include" -I"$JDK/include/win32" \
      -c "$SRC_DIR/RenderJni.cpp" -o "$SCRATCH/out/RenderJni-$plat.o" \
      && $TC $STATIC -shared $KILLAT -o "$SCRATCH/$plat/render.dll" \
           "$SCRATCH/out/RenderJni-$plat.o" "$SCRATCH/out/Render-$plat.o" "$SCRATCH/out/Paint-$plat.o" \
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
       Java_Render_prepareConsole Java_Render_setGeometry Java_Render_readCells \
       Java_Render_consoleView Java_Render_readInput Java_Render_readopt Java_Render_plan" render
done

# ---- host gates: the colour oracle, then the model -------------------------------------------
# Both run here rather than on Windows because neither needs a console, and the claim they protect --
# "ConEmu's own tables and its own folding, faithfully" -- is checkable without one. Anything that
# does need a terminal belongs to run.ps1 and the grid witness, not to this script.
if [ "$DO_COLORCHECK" = 1 ]; then
  CC_HOST=$(command -v clang++ || command -v g++ || true)
  if [ -z "$CC_HOST" ]; then
    printf 'no host clang++/g++: the colour oracle and RenderCheck were skipped\n' >&2
    FAILED="$FAILED host:no-compiler"
  else
    # vendor/ConEmuRgbMap.h is generated, not vendored, so a cmp against upstream cannot see an edit
    # inside ReSetDisplayParm's tables: re-derive it from Ansi.cpp and compare.
    [ -f "$SRC_DIR/gen_rgbmap.sh" ] \
        && { bash "$SRC_DIR/gen_rgbmap.sh" --check "$CONEMU_SRC" || FAILED="$FAILED host:rgbmap-stale"; }

    # The oracle has to be ConEmu's OWN table. ColorCheck's replica formula (xterm cube plus greyscale
    # ramp) disagrees with RgbMap on 15 entries, so a replica dump would quietly bless those 15.
    # extract_rgbmap.py pulls the table out of upstream with a different parser than gen_rgbmap.sh
    # uses, which is what makes RenderCheck's "RgbMap identity" assertion more than a tautology.
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

    # The model gate. Its own output is short and every line of it is a verdict, so it goes to the
    # console as well as to the log.
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

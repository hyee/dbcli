#!/usr/bin/env bash
#
# bench.sh -- build PaintBench.cpp into a Windows executable (DESIGN.md §8: what does a flush cost?).
#
# Deliberately separate from build.sh: that script is the gate, and it fails on any regression. A
# measurement tool has no pass condition, so it must not be able to break the gate -- and it must not
# be linked into render.dll, where every byte of it would ship.
#
#   src/c/conemu/bench.sh                  # both bitnesses into cache/native-probe
#   src/c/conemu/bench.sh x64
#
# Run the result on Windows, not under wine (there is none) and not from WSL's interop: the benchmark
# needs a real console because that is the thing being measured.
#   D:\dbcli\cache\native-probe\paintbench-x64.exe
# If stdout is a pipe it AllocConsoles a hidden one, so redirecting the output is fine.

set -u
SRC_DIR=$(cd "$(dirname "$0")" && pwd)
SCRATCH=${SCRATCH:-/mnt/d/dbcli/cache/native-probe}
FLAGS="-std=c++17 -O2 -D_WIN32_WINNT=0x0601 -DWINVER=0x0601 -Wall -Wextra -Wno-unused-parameter"
LINK="-static -static-libgcc -static-libstdc++"
rc=0

want=${1:-both}
case "$want" in
  x86|x64|both) : ;;
  -h|--help) sed -n '1,20p' "$0"; exit 0 ;;
  *) printf 'usage: bench.sh [x86|x64|both]\n' >&2; exit 2 ;;
esac

mkdir -p "$SCRATCH"
for plat in $( [ "$want" = both ] && echo "x86 x64" || echo "$want" ); do
  case $plat in
    x86) TC=i686-w64-mingw32-g++ ;;
    x64) TC=x86_64-w64-mingw32-g++ ;;
  esac
  command -v "$TC" >/dev/null || { printf '%s: no %s (build.sh needs it too)\n' "$plat" "$TC" >&2; rc=1; continue; }
  out="$SCRATCH/paintbench-$plat.exe"
  "$TC" $FLAGS $LINK "$SRC_DIR/PaintBench.cpp" -o "$out" || { rc=1; continue; }
  printf '%s: built %s (%s bytes)\n' "$plat" "$out" "$(stat -c %s "$out")"
done

[ $rc = 0 ] && printf 'BENCH: ok -- run it on Windows, e.g. D:\\dbcli\\cache\\native-probe\\paintbench-x64.exe\n'
exit $rc

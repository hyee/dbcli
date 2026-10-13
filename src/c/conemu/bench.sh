#!/usr/bin/env bash

set -u
SRC_DIR=$(cd "$(dirname "$0")" && pwd)
SCRATCH=${SCRATCH:-/mnt/d/dbcli/cache/native-probe}
FLAGS="-std=c++17 -O2 -D_WIN32_WINNT=0x0601 -DWINVER=0x0601 -Wall -Wextra -Wno-unused-parameter"
LINK="-static -static-libgcc -static-libstdc++"
rc=0

want=${1:-both}
if [ "$want" = --bench ]; then
  CC_HOST=$(command -v clang++ || command -v g++ || true)
  [ -n "$CC_HOST" ] || { printf 'no host C++ compiler (clang++ or g++) for --bench\n' >&2; exit 1; }
  "$CC_HOST" -std=c++17 -O2 -Wall -Wextra -Wno-unused-parameter -o "$SCRATCH/rowbench" \
      "$SRC_DIR/RowBench.cpp" "$SRC_DIR/Render.cpp" "$SRC_DIR/Paint.cpp" || exit 1
  exec "$SCRATCH/rowbench"
fi
case "$want" in
  x86|x64|both) : ;;
  -h|--help) sed -n '1,24p' "$0"; exit 0 ;;
  *) printf 'usage: bench.sh [x86|x64|both|--bench]\n' >&2; exit 2 ;;
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

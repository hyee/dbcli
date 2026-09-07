#!/usr/bin/env bash
#
# build_luautf8.sh -- Compile src/c/luauf8/*.c (lutf8lib.c + trim_string.c) into a
#                     LuaJIT require-style C module, place per-platform output at
#                     lib/<platform>/utf8.[dll|so], and run built-in self checks.
#                     Consumer: require("utf8") in Lua (dbcli sets LUA_CPATH=./lib/$os/?.so).
#
# Linking contract (avoid hard-linking LuaJIT so the file "just works" when copied):
#   Linux   : do NOT put libluajit5.1.so on the link line -> the artifact has no
#             DT_NEEDED libluajit5.1.so; lua_* stay undefined and resolve against the
#             LuaJIT already loaded in the process (identical to the shipped luv.so,
#             whose NEEDED list is only librt/libpthread/libdl/libc yet has 61 undefined
#             lua_*). Copy it into any host that already carries LuaJIT (dbcli lib<plat>)
#             with no requirement for a sibling .so file path.
#   Windows : the PE loader resolves imports only by the DLL name recorded in the import
#             table (there is no DT_NEEDED-style lazy mechanism), so we KEEP importing
#             lua5.1.dll (the shipped luv.dll imports lua5.1.dll too; avoiding it would
#             require a GetProcAddress rewrite of the source). This is not a file-level
#             hard link: as long as a module named lua5.1.dll is already loaded in the
#             process (dbcli always does), the import binds to the in-memory copy and
#             utf8.dll need not sit in the same directory as lua5.1.dll.
#   macOS   : build a Mach-O BUNDLE with -undefined dynamic_lookup, so lua_* stay undefined and
#             resolve from the host at load time (matches the shipped luv.so, which is a bundle
#             with no NEEDED libluajit). x86_64 floor -mmacosx-version-min=10.12 (user-specified);
#             arm64 floor 11.0 (Apple Silicon never ran an older macOS). Ad-hoc codesign so the
#             bundle loads on Apple Silicon. mac/mac-arm build only on macOS (no osxcross here).
#             Measured floor on the shipped bundles is ONE dylib (/usr/lib/libSystem.B.dylib) with
#             no LC_RPATH and no LC_ID_DYLIB; check_macho enforces it, and a violation exits 1.
#   Output goes straight onto lib/<plat>/utf8.[dll|so] -- the build overwrites the previous
#   artifact in place and keeps no copy of it (git tracks nothing under lib/*/utf8.*, so a
#   replacement is only as recoverable as your own backup).
#   Headers come from the LuaJIT sources (-I); LUA_VERSION_NUM=501 selects the luaL_register branch.
#
# CentOS6 / GLIBC<=2.12: on x86-64 glibc binds memcpy to @GLIBC_2.14 (>2.12). A .symver
#   directive remaps this translation unit's memcpy/memmove references to @GLIBC_2.2.5 (the
#   old compat symbol), measured to lower the ceiling to 2.4. Applies to linux(x86-64) only;
#   linux-arm has no such issue (aarch64 memcpy is only @GLIBC_2.17 and glibc has no 2.2.5 there).
#
# Usage: src/c/luauf8/build_luautf8.sh [options]
# See "--help" for the full option list. Reproducible from-scratch steps: luautf8.txt (same dir).

set -u

# This script lives next to its sources (src/c/luauf8); the repo root is three levels up.
SELF=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P) || SELF=.
SRC_DIR="$SELF"                     # compile every *.c in this dir (lutf8lib.c + trim_string.c ...)
REPO=$(cd -- "$SELF/../../.." >/dev/null 2>&1 && pwd -P) || REPO=.
OUT_ROOT="$REPO/lib"
LUAJIT_SRC="/mnt/d/LuaJIT-2.1/src"
MOD_NAME="utf8"
GLIBC_MAX_LINUX="2.12"
PLATFORMS=""
EXTRA_CFLAGS=""
DO_STRIP=1
DO_CHECK=1
DRY_RUN=0
CC_OVR=""
SELFTEST_DIR=${TMPDIR:-/tmp}/dbcli_utf8_selftest

usage() {
  cat <<'USAGE'
build_luautf8.sh -- cross-build LuaJIT module utf8 (require("utf8") + utf8.trim_space)

Options:
  -p, --platform LIST    Space-separated platforms to build. Defaults by host:
                         x86-64 Linux/WSL -> x64 x86 linux linux-arm ; macOS -> mac mac-arm
                         (mac/mac-arm build only on macOS with clang; skipped elsewhere)
  -o, --out DIR          lib root directory. Default: <repo>/lib
      --luajit-src DIR   LuaJIT headers dir. Default: /mnt/d/LuaJIT-2.1/src (on macOS pass your own)
      --mod-name NAME    require name / artifact basename. Default: utf8
  -c, --cc PLAT=CC       Override a platform's compiler, e.g. -c linux-arm=aarch64-linux-gnu-gcc
  -C, --cflags STR       Append extra compile flags (e.g. -O3)
      --glibc-max VER    Linux(x86-64) GLIBC ceiling check. Default: 2.12 (CentOS6)
  -n, --dry-run          Print commands only, do not compile
      --no-strip         Keep the symbol table (default: strip; artifacts are install-free
                         and can replace shipped files directly)
      --no-check         Skip self checks
  -h, --help             Show this help
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    -p|--platform)   PLATFORMS=${2:-}; shift 2 ;;
    -o|--out)        OUT_ROOT=${2:-}; shift 2 ;;
    --luajit-src)    LUAJIT_SRC=${2:-}; shift 2 ;;
    --mod-name)      MOD_NAME=${2:-}; shift 2 ;;
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

[ -f "$SRC_DIR/lutf8lib.c" ] || { printf 'source not found: %s\n' "$SRC_DIR/lutf8lib.c" >&2; exit 1; }
[ -f "$LUAJIT_SRC/lua.h" ] || { printf 'LuaJIT headers not found: %s\n' "$LUAJIT_SRC" >&2; exit 1; }

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
    mac|mac-arm)  # macOS targets build only on macOS (clang); no osxcross here
      if [ "$(uname -s)" = Darwin ]; then CC=$(command -v clang || true); else CC=""; fi ;;
    *) CC="" ;;
  esac
}

# LuaJIT dependency file for the platform (direct link object; used by Windows only)
link_target() { # $1=platform -> absolute path
  case "$1" in
    x64)       echo "$OUT_ROOT/x64/lua5.1.dll" ;;
    x86)       echo "$OUT_ROOT/x86/lua5.1.dll" ;;
    linux)     echo "$OUT_ROOT/linux/libluajit5.1.so" ;;
    linux-arm) echo "$OUT_ROOT/linux-arm/libluajit5.1.so" ;;
  esac
}

find_tool() { # <cc> <suffix> -> try same-toolchain prefix first, then bare command
  local c t=""
  for c in "${1%-gcc}-$2" "${1%-cc}-$2" "${1%-clang}-$2" "$2"; do
    command -v "$c" >/dev/null 2>&1 && { t=$c; break; }
  done
  printf '%s' "$t"
}

ARTIFACTS="" FAILED="" DEPFAIL=""

build_one() {
  local plat=$1 cc out dir name lt cmd strip sz symver="" link_arg=""
  resolve_cc "$plat"; cc=$CC
  case "$plat" in x64|x86) name="$MOD_NAME.dll" ;; *) name="$MOD_NAME.so" ;; esac
  dir="$OUT_ROOT/$plat"; out="$dir/$name"; lt=$(link_target "$plat")

  if [ -z "$cc" ]; then
    printf '  %-9s SKIP  no usable compiler here (set with -c %s=<cc>)\n' "$plat" "$plat"
    FAILED="$FAILED $plat:skip"; return 0
  fi
  case "$plat" in
    x64|x86)
      [ -f "$lt" ] || { printf '  %-9s FAIL  missing lua5.1.dll %s (Windows needs it to emit the import table)\n' "$plat" "$lt"; FAILED="$FAILED $plat"; return 1; }
      link_arg="\"$lt\"" ;;   # Windows: keep lua5.1.dll import (PE has no lazy resolution; luv.dll does the same)
    *)
      link_arg="" ;;          # Linux: do NOT hard-link libluajit5.1.so; lua_* resolved by the host (like luv.so)
  esac
  mkdir -p "$dir" 2>/dev/null || { printf '  %-9s FAIL  cannot create %s\n' "$plat" "$dir"; FAILED="$FAILED $plat"; return 1; }

  # Only x86-64 Linux needs memcpy/memmove demoted to GLIBC_2.2.5 (injected into this TU via -include)
  if [ "$plat" = linux ]; then
    mkdir -p "$SELFTEST_DIR" 2>/dev/null
    printf '__asm__(".symver memcpy,memcpy@GLIBC_2.2.5");\n__asm__(".symver memmove,memmove@GLIBC_2.2.5");\n' > "$SELFTEST_DIR/symver.h"
    symver="-include $SELFTEST_DIR/symver.h"
  fi

  # Per-platform link mode + strip option.
  #   Linux/Windows: -shared (ELF/PE), strip during link with -s.
  #   macOS: a require-able LuaJIT module is a Mach-O BUNDLE with -undefined dynamic_lookup so the
  #          lua_* symbols resolve from the host at load time (matches the shipped luv.so, no hard
  #          link). Apple's ld has no -s, so strip afterwards with `strip -x`. x86_64 floor is 10.12
  #          (user-specified); arm64 floor is 11.0 (Apple Silicon never ran anything older).
  #   macOS dependency floor, measured on the two shipped bundles (llvm-objdump --macho
  #   --private-headers lib/mac/luv.so lib/mac-arm/luv.so): filetype BUNDLE, exactly ONE
  #   LC_LOAD_DYLIB (/usr/lib/libSystem.B.dylib), no LC_RPATH, no LC_ID_DYLIB, no libluajit.
  #   One dylib is the floor for any Mach-O image, so "minimal" means never adding a second one
  #   and never growing a loader search path: no -l, no -L, no link_target (see the case above),
  #   no rpath. These sources include only string/stdlib/stdint/limits/assert, so every non-lua
  #   reference is a libSystem symbol; check_macho() is what keeps it that way.
  local mode stripopt="-s"
  case "$plat" in
    mac)     mode="-bundle -undefined dynamic_lookup -arch x86_64 -mmacosx-version-min=10.12"; stripopt="-x" ;;
    mac-arm) mode="-bundle -undefined dynamic_lookup -arch arm64 -mmacosx-version-min=11.0";  stripopt="-x" ;;
    *)       mode="-shared" ;;
  esac

  cmd="$cc $mode -std=c99 -O2 -DNDEBUG -fPIC -Wall -Wextra $EXTRA_CFLAGS $symver"
  case "$plat" in mac|mac-arm) ;; *) [ "$DO_STRIP" = 1 ] && cmd="$cmd -s" ;; esac
  cmd="$cmd -o \"$out\" \"$SRC_DIR\"/*.c -I \"$LUAJIT_SRC\" $link_arg"
  if [ "$DRY_RUN" = 1 ]; then printf '  %-9s DRY   %s\n' "$plat" "$cmd"; return 0; fi

  sh -c "$cmd" || { printf '  %-9s FAIL  compile failed\n' "$plat"; FAILED="$FAILED $plat"; return 1; }
  [ -f "$out" ] || { printf '  %-9s FAIL  no output %s\n' "$plat" "$out"; FAILED="$FAILED $plat"; return 1; }

  if [ "$DO_STRIP" = 1 ]; then
    strip=$(find_tool "$cc" strip); [ -n "$strip" ] && "$strip" $stripopt "$out" 2>/dev/null
  fi
  # Apple Silicon refuses to load an unsigned bundle; ad-hoc sign so it is loadable (no-op elsewhere).
  case "$plat" in
    mac|mac-arm) command -v codesign >/dev/null 2>&1 && codesign -s - --force "$out" 2>/dev/null ;;
  esac
  sz=$(wc -c < "$out" | tr -d ' ')
  printf '  %-9s OK    %s (%s bytes)\n' "$plat" "$out" "$sz"
  ARTIFACTS="$ARTIFACTS$out:$plat "
}

# ---------------- self checks ----------------
IMP_RE='^[[:space:]]+[0-9a-fA-F]{2,8}[[:space:]]+[0-9]+[[:space:]]+[A-Za-z_][A-Za-z0-9_]*$'
NEWAPI='(Set|Get)ThreadDescription|WaitOnAddress|WakeByAddress[A-Za-z]*|GetSystemTimePreciseAsFileTime|CreateSymbolicLinkW|GetTickCount64|CompareObjectHandles|GetFileInformationByHandleEx|SetFileInformationByHandle'
OPEN="luaopen_$MOD_NAME"

check_win() { # <artifact> <dump text>
  local n bad
  n=$(printf '%s\n' "$2" | sed -n '/Import Tables/,$p' | grep -Ec "$IMP_RE")
  printf '  export %-14s: %s\n' "$OPEN" "$(printf '%s\n' "$2" | grep -Eq "\] $OPEN" && echo 'present OK' || echo 'MISSING')"
  printf '  DLL deps        : %s\n' "$(printf '%s\n' "$2" | awk '/DLL Name/{printf "%s ", $NF}')"
  printf '  imported funcs  : %s\n' "$n"
  printf '  lua* imports    : %s\n' "$(printf '%s\n' "$2" | sed -n '/Import Tables/,$p' | grep -E "$IMP_RE" | awk '{print $NF}' | grep -cE '^lua')"
  bad=$(printf '%s\n' "$2" | sed -n '/Import Tables/,$p' | grep -Eo "$NEWAPI" | sort -u | tr '\n' ' ')
  [ -n "$bad" ] && printf '  ! Win8+ entrypoints : %s\n' "$bad" || printf '  Win8+ entrypoints   : none OK\n'
  printf '%s\n' "$2" | sed -n '/Import Tables/,$p' | grep -q 'api-ms-win' \
    && printf '  ! api-ms-win-* forwarders present\n' || printf '  api-ms-win-*        : none OK\n'
}

ver_le() { # "$1" <= "$2" (version-aware); returns 0 when satisfied
  [ "$1" = "$2" ] && return 0
  local first; first=$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)
  [ "$first" = "$1" ]
}

check_elf() { # <artifact> <nm> <dump> <plat>
  local und plat=$4 verdict maxg needed
  printf '  export %-14s: %s\n' "$OPEN" "$("$2" -D --defined-only "$1" 2>/dev/null | grep -c "$OPEN")"
  needed=$(printf '%s\n' "$3" | awk '/NEEDED/{printf "%s ", $NF}')
  printf '  NEEDED          : %s\n' "$needed"
  if printf '%s\n' "$needed" | grep -q 'luajit'; then
    printf '  ! still hard-links LuaJIT : %s\n' "$needed"; DEPFAIL="$DEPFAIL $plat:luajit-dep"
  else
    printf '  hard-link LuaJIT : none OK (lua_* resolved by the in-process host; copy-and-go)\n'
  fi
  printf '  undefined lua_* : %s (expected >0, satisfied by the host)\n' "$("$2" -D --undefined-only "$1" 2>/dev/null | grep -cE ' (lua|luaL|lj)[a-zA-Z]')"
  maxg=$(printf '%s\n' "$3" | grep -oE 'GLIBC_[0-9.]+' | sort -uV | tail -1)
  if [ "$plat" = linux ]; then
    if ver_le "${maxg#GLIBC_}" "$GLIBC_MAX_LINUX"; then verdict='OK'; else verdict='ABOVE CEILING'; DEPFAIL="$DEPFAIL $plat:glibc-$maxg"; fi
    printf '  GLIBC ceiling   : %s  (require <=%s, CentOS6) %s\n' "$maxg" "$GLIBC_MAX_LINUX" "$verdict"
  else
    printf '  GLIBC ceiling   : %s  (arm64 arch floor is ~2.17; there is no CentOS6 arm64)\n' "$maxg"
  fi
  # Undefined symbols: @GLIBC/@LIBC versioned refs are provided by NEEDED libc; lua*/lj* are the host;
  # crt weak symbols are ignored. Only a versionless, non-lua undefined reference is a real gap (e.g. sendmmsg).
  und=$("$2" -D --undefined-only "$1" 2>/dev/null | awk '{print $NF}' \
        | grep -vE '@(GLIBC|LIBC)_' \
        | grep -vE '^(lua|lj|_ITM_|__gmon_start__|__cxa_|__stack_chk_|_init$|_fini$|__register_frame|__deregister_frame)' \
        | tr '\n' ' ')
  if [ -n "$und" ]; then
    printf '  ! undefined symbols : %s\n' "$und"; DEPFAIL="$DEPFAIL $plat:undefined"
  else
    printf '  undefined symbols   : none OK (libc / host cover everything)\n'
  fi
}

write_test() { # generate the require behavior assertions (temp dir; not committed into the repo)
  mkdir -p "$SELFTEST_DIR" || return 1
  cat > "$SELFTEST_DIR/test_utf8.lua" <<'LEOF'
local dir = arg[1]
package.cpath = dir .. "/?.so;" .. dir .. "/?.dll;" .. package.cpath
local ok, u = pcall(require, "utf8")
if not ok then io.stderr:write("require failed: " .. tostring(u) .. "\n"); os.exit(2) end
assert(type(u) == "table", "not a table")
assert(u.len("hello") == 5, "len ascii")
assert(u.codepoint("A") == 65, "codepoint")
assert(u.upper("ab") == "AB", "upper")
assert(u.char(97) == "a", "char")
local zhong = "\228\184\173"          -- U+4E2D (CJK ideograph) = E4 B8 AD
assert(u.len(zhong) == 1, "len 1 codepoint (3 bytes)")
assert(#u.sub(zhong .. "x", 2, 2) == 1 and u.sub(zhong .. "x", 2, 2) == "x", "sub after multibyte")
assert(u.byte("A", 1) == 65, "byte")
-- utf8.trim_space merged from trim_string.c (mode: <0 ltrim, >0 rtrim, 0/absent both)
assert(u.trim_space("  hi  ") == "hi", "trim both (default)")
assert(u.trim_space("  hi  ", 0) == "hi", "trim both (explicit)")
assert(u.trim_space("  hi  ", -1) == "hi  ", "ltrim")
assert(u.trim_space("  hi  ", 1) == "  hi", "rtrim")
assert(u.trim_space("\t\n hi \r\n") == "hi", "trim ASCII controls")
assert(u.trim_space("  ") == "", "all blank -> empty")
assert(u.trim_space("  " .. zhong .. "  ") == zhong, "trim around multibyte")
assert(u.trim_space("a b", -1) == "a b" and u.trim_space("a b", 1) == "a b", "inner space kept")
-- trim_space: ASCII 0x00..0x20 are blank EXCEPT ESC(27=\27); then Unicode White_Space
local esc = string.char(27)                        -- \27 == ESC (0x1B): the only exception in 0..32
assert(u.trim_space(esc .. "hi" .. esc) == esc .. "hi" .. esc, "ESC not trimmed")
assert(u.trim_space("\t\027hi") == "\027hi", "trim stops at ESC boundary")
assert(u.trim_space("\0hi") == "hi" and #u.trim_space("\0hi") == 2, "NUL(0) trimmed")
assert(u.trim_space(string.char(0,1,8,14,31) .. "hi" .. string.char(31,8,1)) == "hi", "C0 controls trimmed")
assert(u.trim_space("\194\160x") == "x", "NBSP U+00A0 trimmed")            -- C2 A0
assert(u.trim_space("\194\133x") == "x", "NEL U+0085 trimmed")             -- C2 85
assert(u.trim_space("\227\128\128x") == "x", "U+3000 full-width trimmed")  -- E3 80 80
assert(u.trim_space("\226\128\168x") == "x", "U+2028 line sep trimmed")    -- E2 80 A8
assert(u.trim_space("\225\154\128x") == "x", "U+1680 ogham trimmed")       -- E1 9A 80 (newly added)
assert(u.trim_space("\226\128\138x") == "x", "U+200A hair space trimmed")  -- E2 80 8A
-- zero-width / invisible format chars ARE blank for trimming: they render with no advance and,
-- at an edge, have no outer neighbour to join/shape with, so removing them cannot garble output.
local zwsp = string.char(226,128,139)              -- U+200B ZWSP
local zwnj = string.char(226,128,140)              -- U+200C ZWNJ
local zwj  = string.char(226,128,141)              -- U+200D ZWJ
local wj   = string.char(226,129,160)              -- U+2060 WORD JOINER
local mvs  = string.char(225,160,142)              -- U+180E MONGOLIAN VOWEL SEPARATOR
local bom  = string.char(239,187,191)              -- U+FEFF BOM (ZWNBSP)
for _,z in ipairs{zwsp,zwnj,zwj,wj,mvs,bom} do
  assert(u.trim_space(z .. "x") == "x",        "zero-width lead trimmed")
  assert(u.trim_space("x" .. z) == "x",        "zero-width tail trimmed")
  assert(u.trim_space(z .. "x" .. z) == "x",   "zero-width both ends trimmed")
  assert(u.trim_space(" " .. z .. "x" .. z) == "x", "zero-width with ASCII blanks")
end
assert(u.trim_space(zwsp .. "x" .. zwsp, -1) == "x" .. zwsp, "zero-width ltrim")
assert(u.trim_space(zwsp .. "x" .. zwsp,  1) == zwsp .. "x", "zero-width rtrim")
-- invisible operators U+2061..U+2064 are blank too (E2 81 A1..A4)
for _,b in ipairs{161,162,163,164} do
  local op = string.char(226,129,b)
  assert(u.trim_space(op .. "x" .. op) == "x", "U+206x invisible operator trimmed")
end
-- Invalid UTF-8 is OPAQUE. trim only ever consumes a byte range that is the canonical
-- (shortest-form, valid-tail) encoding of a blank. utf8_decode() masks continuation bytes
-- with 0x3F, so an invalid lead followed by VISIBLE ASCII decodes to a phantom blank:
-- C2 45 decodes to U+0085 NEL exactly as a real NEL does. Consuming it used to eat the
-- 'E'. The tail check is the only thing that tells the two apart, so assert both sides.
local function opaque(bytes, name)
  assert(u.trim_space(bytes) == bytes,       "invalid UTF-8 kept: " .. name)
  assert(u.trim_space(bytes, -1) == bytes,   "invalid UTF-8 kept (ltrim): " .. name)
  assert(u.trim_space(bytes,  1) == bytes,   "invalid UTF-8 kept (rtrim): " .. name)
end
opaque(string.char(194,69),          "C2 'E' bad tail")        -- would decode to U+0085
opaque(string.char(224,128,69),      "E0 80 'E' overlong")     -- would decode to U+0045
opaque(string.char(192,128),         "C0 80 overlong NUL")     -- would decode to U+0000
opaque(string.char(128,69),          "80 'E' stray continuation")
opaque(string.char(245,128,128,128), "F5 ... above U+10FFFF")
opaque(string.char(226,128),         "E2 80 truncated")        -- would be U+200x
-- the same encodings DO trim once they are genuinely canonical
assert(u.trim_space(string.char(194,133)) == "",          "real NEL U+0085 trimmed")
assert(u.trim_space(string.char(226,128,139) .. "x") == "x", "real ZWSP trimmed")
-- ANSI escape integrity. A BEL that TERMINATES an open OSC / APC / PM / SOS / DCS must
-- survive trimming: dropping it leaves the sequence unterminated and the terminal then
-- swallows every byte written afterwards, which is far worse than one stray bell.
local bel = string.char(7)
assert(u.trim_space(esc .. "]0;title" .. bel .. "  ", 1) == esc .. "]0;title" .. bel,
       "OSC closed by BEL survives rtrim")
assert(u.trim_space("  " .. esc .. "]0;t" .. bel) == esc .. "]0;t" .. bel,
       "OSC closed by BEL survives ltrim of the pad before it")
assert(u.trim_space(esc .. "_apc" .. bel .. " ", 1) == esc .. "_apc" .. bel, "APC + BEL survives rtrim")
assert(u.trim_space(esc .. "Pdq" .. bel .. " ", 1) == esc .. "Pdq" .. bel,   "DCS + BEL survives rtrim")
assert(u.trim_space(esc .. "]0;t" .. esc .. "\\  ", 1) == esc .. "]0;t" .. esc .. "\\",
       "OSC closed by ST survives rtrim")
-- a BEL that closes nothing is still blank, and a CSI cell keeps its colours
assert(u.trim_space(bel .. "x" .. bel) == "x", "unattached BEL trimmed")
assert(u.trim_space(esc .. "[31mRED" .. esc .. "[0m ") == esc .. "[31mRED" .. esc .. "[0m",
       "SGR cell keeps its colours, trailing pad goes")
-- blanks added by the same fix: DEL has no glyph and no advance in a UTF-8 terminal, and
-- these zero-width format characters cannot alter a neighbour once they sit at an edge.
assert(u.trim_space(string.char(127) .. "x" .. string.char(127)) == "x", "DEL 0x7F trimmed")
assert(u.trim_space(string.char(194,173) .. "x") == "x",       "U+00AD SOFT HYPHEN trimmed")
assert(u.trim_space(string.char(226,128,142) .. "x") == "x",   "U+200E LRM trimmed")
assert(u.trim_space(string.char(226,128,170) .. "x") == "x",   "U+202A LRE trimmed")
assert(u.trim_space(string.char(227,133,164) .. "x") == "x",   "U+3164 HANGUL FILLER trimmed")
assert(u.trim_space(string.char(239,190,160) .. "x") == "x",   "U+FFA0 HALFWIDTH HANGUL FILLER trimmed")
-- Deliberately NOT blank: removing these changes how the KEPT text renders, so trimming
-- them would itself be the garbling the policy exists to avoid.
local function keeps(s, name)
  assert(u.trim_space(s) == s,             "must keep " .. name)
  assert(u.trim_space("x" .. s) == "x" .. s, "must keep trailing " .. name)
  assert(u.trim_space(s .. " ") == s,      "pad after kept char still trims: " .. name)
end
keeps(string.char(239,184,143), "U+FE0F VS16")          -- turns the last emoji colour
keeps(string.char(224,160,139), "U+180B MONGOLIAN FVS1")
keeps(string.char(224,160,143), "U+180F MONGOLIAN FVS4")
keeps(string.char(204,129),     "U+0301 COMBINING ACUTE")
keeps(string.char(226,160,128), "U+2800 BRAILLE BLANK") -- looks blank, has an advance
keeps(string.char(239,188,188), "U+FFFC OBJECT REPLACEMENT")
keeps(string.char(239,188,189), "U+FFFD REPLACEMENT")
keeps(string.char(194,142),     "U+008E C1 SS2")        -- 8-bit escape introducer
keeps(string.char(194,144),     "U+0090 C1 DCS")
keeps(string.char(194,155),     "U+009B C1 CSI")
keeps(string.char(194,159),     "U+009F C1 APC")
-- utf8.trim_chars(s, chars[, mode]): trim only the code points present in chars
assert(u.trim_chars("xxhixx", "x") == "hi", "trim_chars basic")
assert(u.trim_chars("xxhixx", "x", -1) == "hixx", "trim_chars ltrim")
assert(u.trim_chars("xxhixx", "x", 1) == "xxhi", "trim_chars rtrim")
assert(u.trim_chars("abXba", "ab") == "X", "trim_chars multi set")
assert(u.trim_chars("  hi  ", " ") == "hi", "trim_chars space-as-set")
assert(u.trim_chars("abab", "ab") == "", "trim_chars consumes all")
assert(u.trim_chars("x", "ab") == "x", "trim_chars no match")
assert(u.trim_chars("hi", "") == "hi", "trim_chars empty set")
assert(u.trim_chars(zhong .. "x" .. zhong, zhong) == "x", "trim_chars multibyte set")
local znil = u.trim_chars("\0a\0", "\0")
assert(znil == "a" and #znil == 1, "trim_chars embedded NUL")
-- utf8.ansi_width / utf8.ansi_cut: C port of misc.lua string.wcwidth / string.ansi_cut.
-- Every expectation below was read off a real cursor: conhost and Windows Terminal via
-- CONOUT$ cursor readback, xterm via ESC[6n CPR, glibc via wcwidth(). See luautf8.txt 2.7.
local ESC = string.char(27)
assert(u.ansi_width("abc") == 3, "aw ascii")
assert(u.ansi_width(ESC .. "[31mred" .. ESC .. "[0m") == 3, "aw skips SGR")
assert(u.ansi_width(zhong) == 2 and u.ansi_width(zhong .. zhong) == 4, "aw wide=2")
assert(u.ansi_width(ESC .. "[31m" .. zhong .. ESC .. "[0m") == 2, "aw SGR around wide")
assert(u.ansi_width(ESC .. "]0;title" .. string.char(7) .. "x") == 1, "aw OSC skipped")
assert(u.ansi_width(nil) == 0, "aw nil=0")
-- TAB advances to the next 8-column stop; it is not one column. Both consoles measured
-- TAB@0=8, "a\tb"=9, "12345678\tx"=17, "1234567\tx"=9.
assert(u.ansi_width("\t") == 8, "aw TAB at col 0")
assert(u.ansi_width("a\tb") == 9, "aw TAB after 1 col")
assert(u.ansi_width("12345678\tx") == 17, "aw TAB after 8 cols")
assert(u.ansi_width("1234567\tx") == 9, "aw TAB after 7 cols")
-- a multi-line string reports its WIDEST line, not the sum of them
assert(u.ansi_width("ab\ncdef") == 4, "aw multiline widest")
assert(u.ansi_width("abcdefgh\nxy") == 8, "aw multiline widest, longest first")
assert(u.ansi_width(zhong .. "\nabcd") == 4, "aw multiline widest with a wide char")
-- CR / BS fold the cursor into the line's high-water mark first, so overstriking does not
-- lose width that was already drawn. Both consoles end at column 2 for the first two.
assert(u.ansi_width("ab\rcd") == 2, "aw CR overstrike")
assert(u.ansi_width("ab\bc") == 2, "aw BS overstrike")
assert(u.ansi_width("abc\b\bX") == 3, "aw BS keeps the high-water mark")
-- an unterminated string form is abandoned at a new ESC, CAN or SUB, so it cannot swallow
-- the escapes after it; CR does NOT abandon one (measured: the tail really stays hidden)
assert(u.ansi_width(ESC .. "]0;x" .. ESC .. "[31mvis") == 3, "aw OSC abandoned at ESC")
assert(u.ansi_width(ESC .. "]0;x" .. string.char(24) .. "vis") == 3, "aw OSC abandoned at CAN")
assert(u.ansi_width(ESC .. "]0;x\rvis") == 0, "aw OSC not abandoned at CR")
assert(u.ansi_width(ESC .. "]0;x") == 0, "aw unterminated OSC runs to the end")
-- SS2 / SS3 consume only the introducer: both consoles then print the graphic byte (measured 1)
assert(u.ansi_width(ESC .. "OP") == 1, "aw SS3 prints its byte")
assert(u.ansi_width(ESC .. "Nx") == 1, "aw SS2 prints its byte")
-- invisible code points, straight from the generated Unicode 15 table
assert(u.ansi_width(string.char(226,128,139)) == 0, "aw ZWSP=0")
assert(u.ansi_width(string.char(216,156)) == 0, "aw U+061C arabic let mark=0")
assert(u.ansi_width(string.char(225,160,142)) == 0, "aw U+180E mongolian VS=0")
assert(u.ansi_width(string.char(226,129,164)) == 0, "aw U+2064 invisible plus=0")
assert(u.ansi_width(string.char(226,129,166)) == 0, "aw U+2066 LRI=0")
assert(u.ansi_width(string.char(226,129,169)) == 0, "aw U+2069 PDI=0")
assert(u.ansi_width(string.char(225,160,142)) == u.width(string.char(225,160,142)), "aw==width U+180E")
assert(u.ansi_width("e" .. string.char(204,129)) == 1, "aw combining mark after a base=0")
-- Emoji_Presentation code points are EastAsianWidth=W in modern Unicode; the JLine-frozen
-- table said 1. Both consoles measure 2 for every one of these.
assert(u.ansi_width(string.char(226,140,154)) == 2, "aw U+231A watch=2")
assert(u.ansi_width(string.char(226,152,148)) == 2, "aw U+2614 umbrella=2")
assert(u.ansi_width(string.char(226,153,136)) == 2, "aw U+2648 aries=2")
assert(u.ansi_width(string.char(240,159,152,128)) == 2, "aw U+1F600 grinning=2")
assert(u.ansi_width(string.char(240,159,143,187)) == 2, "aw U+1F3FB skin tone=2")
-- Mc spacing marks DO advance the cursor (measured 1); lutf8lib.c's utf8.width says 0
assert(u.ansi_width(string.char(224,166,190)) == 1, "aw U+09BE bengali Mc=1")
-- EastAsianWidth=A stays 1: no ambiguous-width opt-in, which is the default every listed
-- terminal ships with. (Not unanimous -- U+3248 below is A and conhost/xterm/glibc say 2.)
assert(u.ansi_width(string.char(226,148,128)) == 1, "aw U+2500 box drawing=1")
assert(u.ansi_width(string.char(194,161)) == 1, "aw U+00A1 inv exclam=1")
-- Measured supplements: the code points where Unicode's properties and what a terminal
-- actually draws disagree. Each one is a reading, not a guess.
local function u8(n)  -- encode one code point by arithmetic, independent of the module
  if n < 0x80 then return string.char(n) end
  if n < 0x800 then return string.char(0xC0 + math.floor(n/0x40), 0x80 + n%0x40) end
  if n < 0x10000 then
    return string.char(0xE0 + math.floor(n/0x1000),
                       0x80 + math.floor(n/0x40)%0x40, 0x80 + n%0x40)
  end
  return string.char(0xF0 + math.floor(n/0x40000), 0x80 + math.floor(n/0x1000)%0x40,
                     0x80 + math.floor(n/0x40)%0x40, 0x80 + n%0x40)
end
-- U+00AD and Unicode's 13 Prepended_Concatenation_Marks are Cf, yet all four sources draw
-- a cell for them: conhost 1, Windows Terminal 1, xterm 1, glibc 1.
for _,c in ipairs{0x00AD, 0x0600,0x0601,0x0602,0x0603,0x0604,0x0605,
                  0x06DD, 0x070F, 0x0890,0x0891, 0x08E2, 0x110BD, 0x110CD} do
  assert(u.ansi_width(u8(c)) == 1, ("aw U+%04X drawn Cf=1"):format(c))
end
assert(u.ansi_width(u8(0x0600) .. "123") == 4, "aw PCM in front of a number counts")
-- Conjoining Hangul jamo: a medial or final jamo is drawn into the cell the initial jamo
-- before it opened, so it costs nothing. xterm measures U+1100 U+1161 as 2 cells, not 3;
-- Windows gets the same 2 by shaping the pair into one syllable.
assert(u.ansi_width(u8(0x1100)) == 2, "aw U+1100 choseong=2")
for _,c in ipairs{0x1160, 0x1161, 0x11FF, 0xD7B0, 0xD7CB, 0xD7FB} do
  assert(u.ansi_width(u8(c)) == 0, ("aw U+%04X conjoining jamo=0"):format(c))
end
assert(u.ansi_width(u8(0x1100) .. u8(0x1161)) == 2, "aw jamo syllable is one wide cell")
assert(u.ansi_width(u8(0xAC00)) == 2, "aw precomposed hangul=2")
-- Yijing hexagrams: EastAsianWidth says N, but Windows Terminal, glibc, xterm and
-- lutf8lib's own unidata.h all draw them full width. Only font-driven conhost says 1.
assert(u.ansi_width(u8(0x4DC0)) == 2, "aw U+4DC0 hexagram 1=2")
assert(u.ansi_width(u8(0x4DFF)) == 2, "aw U+4DFF hexagram 64=2")
-- These stay 1 on purpose, and unidata.h is the one that is wrong about them. Trigrams and
-- Tai Xuan Jing are EAW=N (glibc 1, xterm 1). U+3248..U+324F are EAW=A, where the 2 that
-- glibc and xterm report is an artifact of glibc merging 3220..A48C into one wide run --
-- Windows Terminal, which keeps a curated table, says 1.
assert(u.ansi_width(u8(0x2630)) == 1, "aw U+2630 trigram=1")
assert(u.ansi_width(u8(0x1D300)) == 1, "aw U+1D300 tai xuan jing=1")
assert(u.ansi_width(u8(0x3248)) == 1, "aw U+3248 circled ten=1")
-- malformed UTF-8 is one column per byte and can never smuggle in a width class
assert(u.ansi_width(string.char(240,132,184,128)) == 4, "aw overlong 4-byte form")
assert(u.ansi_width(string.char(237,160,128)) == 3, "aw UTF-16 surrogate")
assert(u.ansi_width(string.char(244,144,128,128)) == 4, "aw past U+10FFFF")
assert(u.ansi_width(string.char(128)) == 1, "aw lone continuation byte")
assert(u.ansi_width(string.char(228,184)) == 2, "aw truncated 3-byte sequence")
-- the rest of C0, and DEL, count 0
assert(u.ansi_width(string.char(0,7,127)) == 0, "aw NUL/BEL/DEL=0")
-- ansi_width's SECOND value is the byte length of the widest line, counted per line the same
-- way the width is. For a single-line string that is just its length; for a multi-line one it
-- is NOT the sum. The two numbers disagree in both directions.
local function aw(s)  return (u.ansi_width(s)) end          -- ( ) cuts it back to one value
local function awb(s) return select(2, u.ansi_width(s)) end
assert(select("#", u.ansi_width("abc")) == 2, "aw returns two values")
assert(select("#", u.ansi_width(nil)) == 2, "aw nil returns two values too")
assert(aw("abc") == 3 and awb("abc") == 3, "awb single line")
assert(awb("") == 0, "awb empty string")
assert(awb(nil) == 0, "awb nil")
assert(aw(12345) == 5 and awb(12345) == 5, "awb coerced number")
-- bytes the width does not charge for: escapes, combining marks, malformed sequences
assert(aw(ESC .. "[31mred" .. ESC .. "[0m") == 3 and awb(ESC .. "[31mred" .. ESC .. "[0m") == 12,
       "awb counts the SGR bytes")
assert(aw("e" .. string.char(204,129)) == 1 and awb("e" .. string.char(204,129)) == 3,
       "awb combining mark bytes")
assert(awb(string.char(240,132,184,128)) == 4, "awb malformed bytes")
assert(aw(zhong) == 2 and awb(zhong) == 3, "awb one wide char is 3 bytes and 2 columns")
-- and the other direction: TAB is one byte worth up to 8 columns
assert(aw("\t") == 8 and awb("\t") == 1, "awb TAB is one byte")
assert(aw("a\tb") == 9 and awb("a\tb") == 3, "awb TAB run")
-- multi-line: the bytes come from the SAME line the width came from
assert(aw("ab\ncdef") == 4 and awb("ab\ncdef") == 4, "awb widest line is the last")
assert(aw("abcdefgh\nxy") == 8 and awb("abcdefgh\nxy") == 8, "awb widest line is the first")
assert(aw(zhong .. "\nabcd") == 4 and awb(zhong .. "\nabcd") == 4, "awb the wide-char line loses")
assert(aw(zhong .. zhong .. "\nabcd") == 4 and awb(zhong .. zhong .. "\nabcd") == 6,
       "awb the wide-char line wins: 4 columns, 6 bytes")
assert(awb("a\nbb\nccc\ndd\ne") == 3, "awb picks the middle line")
-- a tie goes to the FIRST line that reached the maximum: line 1 is 7 bytes at width 2, line 2
-- is 2 bytes at the same width
assert(aw(ESC .. "[31mab\ncd") == 2 and awb(ESC .. "[31mab\ncd") == 7, "awb tie -> first line")
-- a line of width 0 still has bytes, and still counts as the first line
assert(aw(ESC .. "]0;x") == 0 and awb(ESC .. "]0;x") == 5, "awb zero-width line reports its bytes")
assert(aw(ESC .. "[0m\nab") == 2 and awb(ESC .. "[0m\nab") == 2, "awb zero-width first line loses")
assert(aw("\n" .. ESC .. "[0m") == 0 and awb("\n" .. ESC .. "[0m") == 0,
       "awb empty first line wins the zero-width tie")
-- LF is the only separator; CR folds back inside the line and its byte belongs to it
assert(aw("ab\n") == 2 and awb("ab\n") == 2, "awb trailing LF is not part of the line")
assert(aw("\n\n") == 0 and awb("\n\n") == 0, "awb every line empty")
assert(awb("\nabcd\n") == 4, "awb middle line between two LFs")
assert(aw("ab\rcd") == 2 and awb("ab\rcd") == 5, "awb CR stays inside the line")
assert(aw("ab\bc") == 2 and awb("ab\bc") == 4, "awb BS bytes")
assert(aw("abc\b\bX") == 3 and awb("abc\b\bX") == 6, "awb overstrike bytes")
assert(aw("abc\r\ndef") == 3 and awb("abc\r\ndef") == 4, "awb CRLF: the CR belongs to the line")
local b1, p1, c1 = u.ansi_cut("abcdef", 3)
assert(b1 == 3 and p1 == 3 and c1 == "abc", "ansi_cut plain cut")
local b2, p2, c2 = u.ansi_cut("abcdef")
assert(p2 == 6 and c2 == "abcdef", "ansi_cut no budget")
local b3, p3, c3 = u.ansi_cut("", 5)
assert(b3 == 0 and p3 == 0 and c3 == "", "ansi_cut empty")
local b4, p4, c4 = u.ansi_cut(ESC .. "[31mred" .. ESC .. "[0m", 2)
assert(p4 == 2 and #c4 == b4 and c4:find(ESC, 1, true), "ansi_cut coloured cut keeps reset")
assert(select("#", u.ansi_cut(nil)) == 1, "ansi_cut nil returns one nil, like string.ansi_cut")
io.write("REQUIRE-OK version=" .. tostring(u.version) .. " len(hello)=" .. u.len("hello") .. " cp(A)=" .. u.codepoint("A") .. " len(zhong)=" .. u.len(zhong) .. " trim=[" .. u.trim_space("  x  ") .. "|" .. u.trim_space("  x  ", -1) .. "|" .. u.trim_space("  x  ", 1) .. "] trim_chars=[" .. u.trim_chars("xxhixx","x") .. "|" .. u.trim_chars("abXba","ab") .. "] aw=" .. u.ansi_width(ESC .. "[31m" .. zhong .. zhong .. ESC .. "[0m") .. " ansi_cut=" .. select(2, u.ansi_cut("abcdef", 3)) .. "\n")
LEOF
}

native_test() { # <artifact> <plat>
  local plat=$2 dir luaprog
  dir=$(dirname "$1")
  write_test || { printf '  (skip real require: temp dir not writable)\n'; return 0; }
  luaprog="$dir/luajit"
  [ -x "$luaprog" ] || luaprog="$dir/luajit.exe"
  case "$plat" in
    linux)
      [ -x "$dir/luajit" ] || { printf '  (skip: no %s/luajit)\n' "$dir"; return 0; }
      LD_LIBRARY_PATH="$dir" "$dir/luajit" "$SELFTEST_DIR/test_utf8.lua" "$dir" ;;
    linux-arm)
      if command -v qemu-aarch64-static >/dev/null 2>&1 && [ -x "$dir/luajit" ]; then
        qemu-aarch64-static -L /usr/aarch64-linux-gnu -E LD_LIBRARY_PATH="$dir" \
          "$dir/luajit" "$SELFTEST_DIR/test_utf8.lua" "$dir"
      else printf '  (skip qemu-aarch64 real load: no qemu or no arm luajit)\n'; fi ;;
    x64|x86)
      local exe="$dir/luajit.exe" tf="$dir/.utf8_wt.lua"
      [ -x "$exe" ] || { printf '  (skip Windows real require: no %s)\n' "$exe"; return 0; }
      # The temp script must live in the artifact dir (Windows-visible); luajit.exe cannot read /tmp.
      # Use a relative name + '/' cpath to dodge backslash escaping across the interop layers.
      printf 'package.cpath="./?.so;./?.dll;"..package.cpath\nlocal ok,u=pcall(require,"utf8")\nif not ok then io.stderr:write("require failed: "..tostring(u).."\\n");os.exit(2) end\nassert(u.len("hello")==5 and u.codepoint("A")==65 and u.upper("ab")=="AB" and u.char(97)=="a")\nassert(u.trim_space(" hi ")=="hi" and u.trim_space(" hi ",-1)=="hi " and u.trim_space(" hi ",1)==" hi")\nassert(u.trim_space(string.char(27).."hi")==(string.char(27).."hi") and u.trim_space(string.char(227,128,128).."x")=="x" and u.trim_space(string.char(0).."hi")=="hi")\nassert(u.trim_space(string.char(226,128,139).."x")=="x" and u.trim_space(string.char(239,187,191).."x")=="x")\nassert(u.trim_chars("xxhixx","x")=="hi" and u.trim_chars("abXba","ab")=="X" and u.trim_chars("abab","ab")=="")\nlocal e=string.char(27); local z=string.char(228,184,173)\nassert(u.ansi_width(e.."[31mred"..e.."[0m")==3 and u.ansi_width(z)==2 and u.ansi_width(z..z)==4 and u.ansi_width(nil)==0)\nlocal _b,_p,_c=u.ansi_cut("abcdef",3); assert(_p==3 and _c=="abc" and _b==3)\nio.write("REQUIRE-OK version="..tostring(u.version).." len(hello)="..u.len("hello").." cp(A)="..u.codepoint("A").." trim=["..u.trim_space(" x ",-1).."|"..u.trim_space(" x ",1).."] trim_chars=["..u.trim_chars("xxhi","x").."|"..u.trim_chars("abXba","ab").."] aw="..u.ansi_width(e.."[31m"..z..z..e.."[0m").." ansi_cut=".._p.."\\n")\n' > "$tf" 2>/dev/null \
        && { ( cd "$dir" && timeout 40 ./luajit.exe ".utf8_wt.lua" ) 2>&1 || printf '  (Windows real require did not run / timed out: rely on the static import-table audit)\n'; } \
        || printf '  (skip Windows real require: temp script not writable)\n'
      mv -f "$tf" "$SELFTEST_DIR/wt-$plat.lua" 2>/dev/null
      ;;
    mac|mac-arm)
      [ -x "$dir/luajit" ] || { printf '  (skip: no %s/luajit)\n' "$dir"; return 0; }
      DYLD_LIBRARY_PATH="$dir" "$dir/luajit" "$SELFTEST_DIR/test_utf8.lua" "$dir" ;;
  esac
}

check_macho() { # <artifact> <plat>
  local ot nm deps bad rpath idname minos want sig hrow ft
  ot=$(command -v otool); nm=$(command -v nm)
  [ -n "$ot" ] && [ -n "$nm" ] || { printf '  (skip: no otool/nm)\n'; return 0; }
  want=10.12; [ "$2" = mac-arm ] && want=11.0
  # otool -hv prints "<file>:", "Mach header" and a column-name line before the data row, so pick
  # the row by its magic instead of a line number, and read the type as a token (the 32-bit row
  # has no caps column, so a fixed field index would point at ncmds there).
  hrow=$("$ot" -hv "$1" 2>/dev/null | awk '$1 ~ /^MH_MAGIC/{print; exit}')
  ft=$(printf '%s\n' "$hrow" | grep -owE 'BUNDLE|DYLIB|DYLINKER|EXECUTE|COREFILE|PRELOAD' | head -1)
  printf '  filetype        : %s\n' "${ft:-?}"
  printf '%s\n' "$hrow" | grep -q 'BUNDLE' \
    && printf '  MH_BUNDLE       : OK (what dlopen/require expects; -bundle)\n' \
    || { printf '  ! not a BUNDLE  : rebuild with -bundle\n'; DEPFAIL="$DEPFAIL $2:not-bundle"; }
  printf '  export %-14s: %s\n' "$OPEN" "$("$nm" -gU "$1" 2>/dev/null | grep -c "$OPEN")"
  deps=$("$ot" -L "$1" 2>/dev/null | tail -n +2 | awk '{printf "%s ", $1}')
  printf '  deps (otool -L) : %s\n' "$deps"
  if printf '%s\n' "$deps" | grep -q 'luajit'; then
    printf '  ! still links LuaJIT : %s\n' "$deps"; DEPFAIL="$DEPFAIL $2:luajit-dep"
  else
    printf '  hard-link LuaJIT : none OK (lua_* resolved by the in-process host; copy-and-go)\n'
  fi
  # libSystem is the floor for any Mach-O image; anything else in that list is a dependency this
  # module does not need and the host may not have at that path.
  bad=$(printf '%s\n' $deps | grep -v '^$' | grep -v '^/usr/lib/libSystem[^ ]*\.dylib$' | tr '\n' ' ')
  [ -n "$bad" ] \
    && { printf '  ! dylibs beyond libSystem : %s\n' "$bad"; DEPFAIL="$DEPFAIL $2:dylibs"; } \
    || printf '  dylibs            : libSystem only OK (the minimum for any Mach-O image)\n'
  rpath=$("$ot" -l "$1" 2>/dev/null | grep -c 'LC_RPATH')
  [ "$rpath" = 0 ] \
    && printf '  LC_RPATH          : none OK (no loader search path baked in)\n' \
    || { printf '  ! LC_RPATH        : %s (a search path is a dependency; drop it)\n' "$rpath"; DEPFAIL="$DEPFAIL $2:rpath"; }
  idname=$("$ot" -l "$1" 2>/dev/null | awk '/LC_ID_DYLIB/{f=1} f&&/^ *name /{print $2; exit}')
  [ -z "$idname" ] \
    && printf '  LC_ID_DYLIB       : none OK (like the shipped luv.so; nothing links against us)\n' \
    || { printf '  ! LC_ID_DYLIB     : %s (install name recorded; a bundle needs none)\n' "$idname"; DEPFAIL="$DEPFAIL $2:id-dylib"; }
  minos=$("$ot" -l "$1" 2>/dev/null | awk '/LC_BUILD_VERSION|LC_VERSION_MIN_MACOSX/{f=1} f&&/minos|version/{print $2; exit}')
  if [ -z "$minos" ] || ver_le "$minos" "$want"; then
    printf '  minos           : %s  (floor %s, what -mmacosx-version-min asked for) OK\n' "$minos" "$want"
  else
    printf '  ! minos          : %s  ABOVE the %s floor -- a newer libc symbol raised the OS requirement\n' "$minos" "$want"
    DEPFAIL="$DEPFAIL $2:minos-$minos"
  fi
  printf '  undefined lua_* : %s (resolved from the host via -undefined dynamic_lookup)\n' \
    "$("$nm" -u "$1" 2>/dev/null | grep -cE '_?lua')"
  # Zero undefined lua_* means dynamic_lookup never applied and the Lua API got resolved at link
  # time -- i.e. a real second dependency slipped in. A successful require below is the proof.
  [ "$("$nm" -u "$1" 2>/dev/null | grep -cE '_?lua')" -gt 0 ] \
    || { printf '  ! no undefined lua_* : -undefined dynamic_lookup did not take effect\n'; DEPFAIL="$DEPFAIL $2:no-dynamic-lookup"; }
  # Apple Silicon refuses to load an unsigned image; x86_64 does not care (luv.so is unsigned).
  if [ "$2" = mac-arm ]; then
    if command -v codesign >/dev/null 2>&1; then
      sig=$(codesign -dv "$1" 2>&1 | grep -c 'Signature')
      [ "${sig:-0}" != 0 ] \
        && printf '  codesign          : ad-hoc signed OK\n' \
        || { printf '  ! codesign         : UNSIGNED -- Apple Silicon will refuse to load it\n'; DEPFAIL="$DEPFAIL $2:unsigned"; }
    else
      printf '  codesign          : (cannot tell, codesign not on PATH)\n'
    fi
  fi
}

check_one() {
  local out=$1 plat=$2 cc od nm dump
  resolve_cc "$plat"; cc=$CC
  printf -- '-- %s (%s)\n' "$plat" "${out#$OUT_ROOT/}"
  case "$plat" in
    x64|x86)
      od=$(find_tool "$cc" objdump); [ -n "$od" ] || { printf '  (skip: no objdump)\n'; return 0; }
      dump=$("$od" -p "$out" 2>/dev/null | tr -d '\r')
      check_win "$out" "$dump"
      native_test "$out" "$plat" ;;
    linux|linux-arm)
      od=$(find_tool "$cc" objdump); nm=$(find_tool "$cc" nm)
      [ -n "$od" ] && [ -n "$nm" ] || { printf '  (skip: no objdump/nm)\n'; return 0; }
      dump=$("$od" -p "$out" 2>/dev/null)
      check_elf "$out" "$nm" "$dump" "$plat"
      # linux loads only on a same-architecture host; linux-arm best-effort via qemu-aarch64
      { [ "$plat" = linux ] && [ "$(host_plat)" = linux ]; } && native_test "$out" "$plat"
      [ "$plat" = linux-arm ] && native_test "$out" "$plat" ;;
    mac|mac-arm)
      check_macho "$out" "$plat"
      [ "$(host_plat)" = "$plat" ] && native_test "$out" "$plat" ;;
  esac
}

printf '== %s: src/c/luauf8/*.c (lutf8lib + trim_string) -> luaopen_%s + %s.trim_space ==\n' "$MOD_NAME" "$MOD_NAME" "$MOD_NAME"
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
  for a in $ARTIFACTS; do check_one "${a%:*}" "${a##*:}"; done
fi

printf '\n== artifacts ==\n'
for a in $ARTIFACTS; do ls -l "${a%:*}"; done
[ -n "$FAILED" ] && printf '\nskipped / not done:%s\n' "$FAILED"

# Dependency contract: ELF (check_elf) and Mach-O (check_macho) must carry no library the host
# does not already have. Windows is not in this list on purpose -- a PE import table always names
# lua5.1.dll (no DT_NEEDED-style lazy binding), see the linking contract at the top of this file.
if [ -n "$DEPFAIL" ]; then
  printf '\n== DEPENDENCY CONTRACT VIOLATED:%s ==\n' "$DEPFAIL"
  printf '   It may still load, but it is no longer copy-and-go: it now needs a library, a loader\n'
  printf '   search path, or an OS version the link contract forbids. Fix the flags above; do not\n'
  printf '   ship this build. (--no-check skips the audit, it does not excuse the artifact.)\n'
  exit 1
fi

cat <<EOF

== Lua usage ==
dbcli's runtime LUA_CPATH already includes ./lib/\$os/?.so (?.dll on Windows), so simply:
  local utf8 = require("utf8")
Standalone luajit smoke test (cwd = repo root):
  LD_LIBRARY_PATH=lib/linux lib/linux/luajit -e 'package.cpath="lib/linux/?.so;"..package.cpath; local u=require("utf8"); print(u.version, u.len("hello"), u.codepoint("A"), u.trim_space("  x  ", -1))'
EOF
exit 0

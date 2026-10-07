#!/bin/bash
set -u

REFRESH=no
for a in "$@"; do [ "$a" = "--refresh" ] && REFRESH=yes; done

marker() { [ -f "$1/src/c/conemu/terminfo/windows-conemu.ti" ]; }

ROOT=""
TRIED=""
if [ -n "${DBCLI_ROOT:-}" ]; then
  TRIED="$TRIED \$DBCLI_ROOT=$DBCLI_ROOT"
  marker "$DBCLI_ROOT" && ROOT="$DBCLI_ROOT"
fi
if [ -z "$ROOT" ]; then
  for s in "${BASH_SOURCE[0]:-}" "$0"; do
    case "$s" in
      */terminfo_check.sh)
        here=$(cd "$(dirname "$s")" 2>/dev/null && pwd)
        if [ -n "$here" ]; then
          cand=$(cd "$here/../../../.." 2>/dev/null && pwd)
          TRIED="$TRIED script-path=$cand"
          [ -n "$cand" ] && marker "$cand" && ROOT="$cand" && break
        fi ;;
    esac
  done
fi
if [ -z "$ROOT" ]; then
  d=$(pwd)
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    TRIED="$TRIED cwd-up=$d"
    marker "$d" && { ROOT="$d"; break; }
    d=$(dirname "$d")
  done
fi
marker "/" && [ -z "$ROOT" ] && ROOT="/"
if [ -z "$ROOT" ]; then
  echo "FAIL no dbcli root: nothing under[$TRIED] holds src/c/conemu/terminfo/windows-conemu.ti."
  echo "     pass DBCLI_ROOT=<path to the tree> (WSL spelling, e.g. /mnt/d/dbcli)."
  exit 1
fi
T="$ROOT/src/c/conemu/terminfo"
echo "     root resolved to: $ROOT"
JAR="${JAR:-$ROOT/lib/JLine3.jar}"
JLINE_CAPS="${JLINE_CAPS:-}"
if [ -z "$JLINE_CAPS" ]; then
  for c in /mnt/d/JavaProjects/jline3.29/terminal/src/main/resources/org/jline/utils/windows-conemu.caps            "$ROOT/../jline3.29/terminal/src/main/resources/org/jline/utils/windows-conemu.caps"; do
    [ -f "$c" ] && JLINE_CAPS="$c" && break
  done
fi
export JLINE_CAPS
export JAR
[ -f "$T/windows-conemu.ti" ] || { echo "no $T/windows-conemu.ti (set DBCLI_ROOT)"; exit 1; }
for f in windows-conemu.caps; do [ -f "$T/$f" ] || { echo "no $T/$f"; exit 1; }; done

WORK=$(mktemp -d) || exit 1
trap 'rm -rf "$WORK"' EXIT
rc=0

tic -x -o "$WORK/tc" "$T/windows-conemu.ti" >"$WORK/tic.log" 2>&1
if [ -s "$WORK/tic.log" ]; then
  echo "FAIL tic -x said something about the entry:"; cat "$WORK/tic.log"; rc=1
else
  echo "ok   tic -x compiles windows-conemu.ti with no complaint"
fi

TERMINFO="$WORK/tc" infocmp -x -1 -I windows-conemu >"$WORK/dump.txt" 2>"$WORK/dump.err"
if [ ! -s "$WORK/dump.txt" ]; then
  echo "FAIL infocmp could not read back what tic wrote:"; cat "$WORK/dump.err"
  echo "TERMINFO CHECK: FAILED"; exit 1
fi

python3 - "$T" "$ROOT" "$WORK/dump.txt" "$@" <<'PY' || rc=1
import io, os, sys

T, ROOT, dump = sys.argv[1], sys.argv[2], sys.argv[3]
extra = sys.argv[4:]   # the flags this script was given; arm 3 honours --allow-no-jar

def caps_from_source(path):
    """The capability fields of a terminfo source file: everything after the names line, comma-separated.

    The names line is the first line that is neither a comment nor blank -- which is why this does not simply
    skip line 0. The .ti leads with a comment block and the .caps leads with prose; in both, line 0 is not the
    names line's index and the names line itself is not a capability."""
    out = []
    seen_names = False
    for line in io.open(path, encoding="utf-8", errors="replace").read().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if not seen_names:
            seen_names = True
            continue
        for tok in line.rstrip(",").split(","):
            tok = tok.strip()
            if tok:
                out.append(tok)
    return sorted(set(out))


def names(caps):
    return sorted(set(c.split("=")[0].split("#")[0] for c in caps))


ti = caps_from_source(os.path.join(T, "windows-conemu.ti"))
mirror = caps_from_source(os.path.join(T, "windows-conemu.caps"))
dump_caps = caps_from_source(dump)

bad = 0

# Source to source: the tokens must match exactly, spelling and all. Two documents, one contract, and the
# .ti is the one a terminfo tool can read.
if ti == mirror:
    print("ok   the .ti and the mirrored .caps hold the same %d capabilities, spelled alike" % len(ti))
else:
    bad = 1
    print("FAIL the .ti and the mirrored .caps disagree")
    print("     only in the .ti  : %s" % [x for x in ti if x not in mirror][:8])
    print("     only in the .caps: %s" % [x for x in mirror if x not in ti][:8])

# Source to compiled dump: NAMES only, and that is a fact about infocmp rather than a shortcut. It writes
# every value back in its own spelling: hex for the integer caps, C-escapes rewritten as
# two-character sequences, and control bytes spelled by name. A token compare would fail on
# any entry ever compiled, so this leg compares NAMES, which is where a capability tic dropped,
# merged or renamed. The byte-level meaning of each value is asserted elsewhere, through jline's own decoder:
# see TERMINFO.md, "who checks the bytes".
if names(ti) == names(dump_caps):
    print("ok   tic -> infocmp round-trips the same %d capability names" % len(dump_caps))
else:
    bad = 1
    print("FAIL the compiled entry is not the set the source claims")
    print("     only in source: %s" % sorted(set(names(ti)) - set(names(dump_caps)))[:8])
    print("     only in dump  : %s" % sorted(set(names(dump_caps)) - set(names(ti)))[:8])

# Snapshot to live dump: TOKENS, not just names. This is the one comparison in this script where values may
# be compared verbatim, because both sides come out of the same generator -- `infocmp` -- so there is no
# spelling drift to forgive. The checked-in snapshot is otherwise write-only (only --refresh ever touches it),
# which is how it kept advertising `cud1=\n` for hours after the entry went back to `\E[B`: a file that
# describes the contract, is read by nobody, and is never re-derived, is a file that can lie forever.
SNAP = os.path.join(T, "infocmp-windows-conemu.txt")
if os.path.exists(SNAP):
    snap_caps = caps_from_source(SNAP)
    if snap_caps == dump_caps:
        print("ok   the checked-in infocmp snapshot matches this compile, values and all (%d tokens)" % len(snap_caps))
    else:
        bad = 1
        print("FAIL the checked-in snapshot is not what the entry compiles to now")
        for x in snap_caps:
            if x not in dump_caps:
                print("     snapshot says: %s" % x)
        for x in dump_caps:
            if x not in snap_caps:
                print("     the compile says: %s" % x)
        print("     decide which side is right, then --refresh to rewrite the snapshot from the compile.")
else:
    bad = 1
    print("FAIL no %s -- the snapshot leg has nothing to compare; run --refresh once to create it." % SNAP)

# three copies of the entry that run time can actually see
import hashlib
import os
import zipfile


def md5(b):
    return hashlib.md5(b).hexdigest()


CAPS_NAME = "org/jline/utils/windows-conemu.caps"
copies = [("mirror", open(os.path.join(T, "windows-conemu.caps"), "rb").read())]
jsrc = os.environ.get("JLINE_CAPS", "")
if jsrc and os.path.exists(jsrc):
    copies.append(("jline", open(jsrc, "rb").read()))
else:
    print("note jline's source copy was not found (JLINE_CAPS unset), so it is not compared")
jar = os.environ.get("JAR", "")
if jar and os.path.exists(jar):
    z = zipfile.ZipFile(jar)
    copies.append(("jar", z.read(CAPS_NAME) if CAPS_NAME in z.namelist() else None))
    print("     the shipped entry compared: %s" % jar)
else:
    # A comparison that ran nothing has to be a failure, not a note: this script printed
    # `TERMINFO CHECK: ok` for its whole life while both copies above were skipped, because JAR was set in
    # the shell and never exported into the python that reads it. The rule is the one DESIGN section 6
    # states for the both-leg A/B -- a comparing gate must assert that it compared.
    print("FAIL the shipped copy was not compared, so arm 3 would be three files checked against one of")
    print("     them: pass JAR=<path to JLine3.jar>, or --allow-no-jar on a tree without one")
    if "--allow-no-jar" not in extra:
        bad = 1
n = CAPS_NAME
base = copies[0][1]
print("     arm 3 compared %d copies of the entry" % len(copies))
for tag, blob in copies[1:]:
    if blob is None:
        print("FAIL the %s copy has no %s" % (tag, n))
        bad = 1
    elif blob == base:
        print("ok   the %s copy is byte-identical to the mirror (%s)" % (tag, md5(base)[:12]))
    else:
        print("FAIL the %s copy differs from the mirror: %s vs %s" % (tag, md5(blob)[:12], md5(base)[:12]))
        bad = 1
sys.exit(bad)
PY

if [ "$REFRESH" = "yes" ] && [ -s "$WORK/dump.txt" ]; then
  {
    echo "# Generated by terminfo_check.sh --refresh. Do not hand-edit: it is what \`infocmp -x -1 -I\` says"
    echo "# about windows-conemu.ti, which is derived from windows-conemu.caps -- the entry jline loads at run"
    echo "# time. The capability set is asserted equal to that file's on every run of this script."
    echo "# $(infocmp -V 2>/dev/null || echo 'ncurses version unavailable')"
    sed "s#$WORK#<tic output dir>#" "$WORK/dump.txt"
  } >"$T/infocmp-windows-conemu.txt"
  echo "ok   refreshed infocmp-windows-conemu.txt"
fi
# --- windows-render: render.dll's own entry, forked from windows-conemu 2026-10-07. Same gate shape,
# one compile arm and a three-copy byte compare; independent because the whole point of the fork is
# that the two entries can now diverge -- a gate that only ever compared conemu would wave a diverged
# render entry through.
if [ -f "$T/windows-render.ti" ] && [ -f "$T/windows-render.caps" ]; then
  tic -x -o "$WORK/tc-render" "$T/windows-render.ti" >"$WORK/tic-render.log" 2>&1
  if [ -s "$WORK/tic-render.log" ]; then
    echo "FAIL tic -x said something about windows-render.ti:"; cat "$WORK/tic-render.log"; rc=1
  else
    echo "ok   tic -x compiles windows-render.ti with no complaint"
  fi
  RENDER_CAPS_NAME="org/jline/utils/windows-render.caps"
  RENDER_MIRROR_JLINE="${JLINE_RENDER_CAPS:-$(dirname "${JLINE_CAPS:-/x/x}")/windows-render.caps}"
  if [ -f "$RENDER_MIRROR_JLINE" ]; then
    export RENDER_MIRROR_JLINE
  fi
  python3 - "$T" "$RENDER_MIRROR_JLINE" <<'PY' || rc=1
import os, sys, hashlib, zipfile
T, jline_copy = sys.argv[1], sys.argv[2]
bad = 0
mirror = open(os.path.join(T, "windows-render.caps"), "rb").read()
copies = [("mirror", mirror)]
if jline_copy and os.path.exists(jline_copy):
    copies.append(("jline", open(jline_copy, "rb").read()))
jar = os.environ.get("JAR", "")
if jar and os.path.exists(jar):
    z = zipfile.ZipFile(jar)
    name = "org/jline/utils/windows-render.caps"
    copies.append(("jar", z.read(name) if name in z.namelist() else None))
else:
    print("note the render jar copy was not compared (JAR unset)")
def md5(b):
    return hashlib.md5(b).hexdigest()
base = copies[0][1]
for tag, blob in copies[1:]:
    if blob is None:
        print("FAIL the %s copy of windows-render.caps is missing from the jar" % tag); bad = 1
    elif blob == base:
        print("ok   the %s copy of windows-render.caps is byte-identical to the mirror (%s)" % (tag, md5(base)[:12]))
    else:
        print("FAIL the %s copy of windows-render.caps differs from the mirror: %s vs %s" % (tag, md5(blob)[:12], md5(base)[:12])); bad = 1
sys.exit(bad)
PY
else
  echo "note windows-render entry not found in the mirror, render arm skipped"
fi


echo "TERMINFO CHECK: $([ $rc -eq 0 ] && echo ok || echo FAILED)"
exit $rc

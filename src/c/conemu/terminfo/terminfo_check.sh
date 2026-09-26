#!/bin/bash
# The terminfo contract, checked rather than asserted.
#
# Four facts, none of them provable by reading one file:
#   1. `windows-conemu.ti` compiles under ncurses (`tic -x`). The jline spelling of the same entry does NOT:
#      its first line carries prose with commas, and terminfo reads those as field separators. So the .ti is
#      the only form a real terminfo tool can be pointed at, and two documents describing one contract drift
#      unless something checks. This is that something.
#   2. The .ti's capability set equals the set in `windows-conemu.caps`, the file jline actually loads.
#   3. Three copies of that .caps agree: the renderer's mirror here, jline's source tree, and the copy
#      inside the jar the application loads. A green audit against a stale jar copy is DESIGN §6 rule 10 in
#      another costume.
#   4. The compiled entry dumps back (`infocmp`) as the same set the source claims, which is what catches a
#      capability that tic silently dropped or renamed.
#
# Usage, from anywhere wsl.exe reaches:
#   MSYS_NO_PATHCONV=1 wsl.exe -e bash -lc 'bash /mnt/d/dbcli/src/c/conemu/terminfo/terminfo_check.sh'
# Pass --refresh to rewrite infocmp-windows-conemu.txt from the compile. Nothing else here rewrites a file.
# The dbcli root is never hardcoded:  $ROOT  >  $DBCLI_ROOT  >  derived from this script's own location.
set -u

REFRESH=no
for a in "$@"; do [ "$a" = "--refresh" ] && REFRESH=yes; done

ROOT="${DBCLI_ROOT:-}"
if [ -z "$ROOT" ]; then
  here=$(cd "$(dirname "$0")" && pwd)          # .../<root>/src/c/conemu/terminfo
  ROOT=$(cd "$here/../../../.." && pwd)
fi
T="$ROOT/src/c/conemu/terminfo"
JAR="${JAR:-$ROOT/lib/JLine3.jar}"
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
  echo "FAIL infocmp could not read back what tic wrote:"; cat "$WORK/dump.err"; rc=1
fi

python3 - "$T" "$ROOT" "$WORK/dump.txt" <<'PY' || rc=1
import io, os, sys

T, ROOT, dump = sys.argv[1], sys.argv[2], sys.argv[3]

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

# three copies of the entry that run time can actually see
import hashlib
import os
import zipfile


def md5(b):
    return hashlib.md5(b).hexdigest()


copies = [("mirror", open(os.path.join(T, "windows-conemu.caps"), "rb").read())]
jsrc = os.environ.get("JLINE_CAPS", "")
if jsrc and os.path.exists(jsrc):
    copies.append(("jline", open(jsrc, "rb").read()))
else:
    print("note JLINE_CAPS unset or missing, so jline's source copy was not compared")
jar = os.environ.get("JAR", "")
if jar and os.path.exists(jar):
    z = zipfile.ZipFile(jar)
    n = "org/jline/utils/windows-conemu.caps"
    copies.append(("jar", z.read(n) if n in z.namelist() else None))
else:
    print("note JAR unset or missing, so the shipped copy was not compared")
base = copies[0][1]
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
    cat "$WORK/dump.txt"
  } >"$T/infocmp-windows-conemu.txt"
  echo "ok   refreshed infocmp-windows-conemu.txt"
fi

echo "TERMINFO CHECK: $([ $rc -eq 0 ] && echo ok || echo FAILED)"
exit $rc

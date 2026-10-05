#!/usr/bin/env python3
"""Single-source the stats() slot seam.

Render.h owns two tables:
  RC_CENSUS_X   -- the census families (order == enum RcUnsupported == rc_census[] ==
                   the stats() run 17..16+RC_UN_MAX)
  RC_STATFAM_X  -- every named slot after the census (family base rows carry the C
                   family constant, '-' rows are members reached by +n in RenderJni.cpp)

This script renders the Java side from those tables (the S_* block in Render.java and
the SLOT_*/UNMODELLED block in NativeRenderer.java, both marker-delimited) and verifies
the C side (the STAT_* #define chain in RenderJni.cpp) against the same tables.

Modes:
  gen_statslots.py --write  [render.h dir]          rewrite both Java blocks in place
  gen_statslots.py --check  FILE                    exit 1 if FILE's block is stale
  gen_statslots.py --check-c FILE                   exit 1 if the STAT_ chain drifts
No mode: print the computed table (diagnostic)."""

import re
import sys

BEGIN = "// BEGIN SLOT TABLE (generated from Render.h by gen_statslots.py -- build.sh verifies)"
END = "// END SLOT TABLE (generated)"


def macro_body(text, name):
    m = re.search(r"#define\s+" + name + r"\(X\)", text)
    if not m:
        die("Render.h: no #define " + name)
    out = []
    for line in text[m.end():].splitlines():
        stripped = line.rstrip()
        if stripped.endswith("\\"):
            out.append(stripped[:-1])
        else:
            out.append(stripped)
            break
    return " ".join(out)


def split_args(s):
    out, depth, cur, instr = [], 0, "", False
    i = 0
    while i < len(s):
        c = s[i]
        if instr:
            cur += c
            if c == "\\":
                cur += s[i + 1]
                i += 2
                continue
            if c == '"':
                instr = False
        elif c == '"':
            instr = True
            cur += c
        elif c == "(":
            depth += 1
            cur += c
        elif c == ")":
            depth -= 1
            cur += c
        elif c == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += c
        i += 1
    if cur.strip():
        out.append(cur.strip())
    return out


def rows(text, name):
    body = macro_body(text, name)
    out = []
    for m in re.finditer(r"\bX\(", body):
        i = m.end()
        depth, instr, args, cur = 1, False, [], ""
        while i < len(body) and depth > 0:
            c = body[i]
            if instr:
                cur += c
                if c == '"':
                    instr = False
            elif c == '"':
                instr = True
                cur += c
            elif c == "(":
                depth += 1
                cur += c
            elif c == ")":
                depth -= 1
                if depth:
                    cur += c
            else:
                cur += c
            i += 1
        args = split_args(cur)
        out.append(args)
    return out


def unquote(arg):
    parts = re.findall(r'"((?:[^"\\]|\\.)*)"', arg)
    if not re.fullmatch(r'\s*"(?:[^"\\]|\\.)*"(?:\s*"(?:[^"\\]|\\.)*")*\s*', arg):
        die("expected string literal(s), got: " + arg)
    return "".join(parts)


def die(msg):
    sys.stderr.write("gen_statslots: " + msg + "\n")
    sys.exit(1)


def load_tables(render_h):
    text = open(render_h, encoding="utf-8").read()
    census = []
    for a in rows(text, "RC_CENSUS_X"):
        if len(a) != 5:
            die("RC_CENSUS_X row has %d fields: %r" % (len(a), a))
        tok, label, word, sentence, suspect = a
        census.append({
            "tok": tok, "label": unquote(label), "word": unquote(word),
            "sentence": unquote(sentence), "suspect": int(suspect),
        })
    fam = []
    for a in rows(text, "RC_STATFAM_X"):
        if len(a) != 4:
            die("RC_STATFAM_X row has %d fields: %r" % (len(a), a))
        fam.append({"fam": a[0], "stat": a[1], "gate": a[2], "prod": a[3]})
    names = [c["label"] for c in census]
    if len(names) != len(set(names)):
        die("RC_CENSUS_X: duplicate label")
    return census, fam


def slot_indices(census, fam):
    base = 17
    idx = {}
    for i, r in enumerate(fam):
        idx[id(r)] = base + len(census) + i
    return base, idx


def gate_block(census, fam):
    base, idx = slot_indices(census, fam)
    L = ["    " + BEGIN,
         "    private static final int S_UN = %d;" % base]
    for r in fam:
        if r["gate"] != "-":
            L.append("    private static final int %s = %d;" % (r["gate"], idx[id(r)]))
    L.append("    private static final int S_LEN = %d;" % (base + len(census) + len(fam)))
    L.append("    " + END)
    return "\n".join(L)


def prod_block(census, fam):
    base, idx = slot_indices(census, fam)
    words = ", ".join('"%s"' % c["word"] for c in census)
    L = ["    " + BEGIN,
         "    private static final int SLOT_UNSUPPORTED = %d;" % base]
    for r in fam:
        if r["prod"] != "-":
            L.append("    private static final int %s = %d;" % (r["prod"], idx[id(r)]))
    L.append("    private static final int SLOT_LAST = %d;" % (base + len(census) + len(fam)))
    L.append("    private static final String[] UNMODELLED = {%s};" % words)
    L.append("    " + END)
    return "\n".join(L)


def replace_block(text, block):
    m = re.search(re.escape(BEGIN) + r".*?" + re.escape(END), text, re.S)
    if not m:
        die("marker block not found (run --write once to install it)")
    return text[:m.start()] + block + text[m.end():]


def install_block(path, block):
    text = open(path, encoding="utf-8").read()
    open(path, "w", encoding="utf-8", newline="").write(replace_block(text, block))


def check_block(path, block, tag):
    text = open(path, encoding="utf-8").read()
    m = re.search(re.escape(BEGIN) + r".*?" + re.escape(END), text, re.S)
    if not m:
        die(tag + ": no marker block")
    a, b = m.group(0).splitlines(), block.splitlines()
    ok = len(a) == len(b) and all(x.strip() == y.strip() for x, y in zip(a, b))
    if not ok:
        sys.stderr.write("%s: SLOT table is stale -- edit Render.h, then run gen_statslots.py --write\n" % tag)
        for i in range(max(len(a), len(b))):
            x = a[i] if i < len(a) else "<none>"
            y = b[i] if i < len(b) else "<none>"
            if x.strip() != y.strip():
                sys.stderr.write("  have: %s\n  want: %s\n" % (x.strip(), y.strip()))
        sys.exit(1)


def eval_chain(defines, expr):
    expr = expr.strip().strip("()")
    for _ in range(10):
        m = re.search(r"\b(STAT_[A-Z]+|RC_UN_MAX)\b", expr)
        if not m:
            break
        name = m.group(1)
        if name not in defines:
            die("RenderJni.cpp: %s used before defined" % name)
        expr = expr.replace(name, "(%d)" % defines[name])
    return int(eval(expr, {"__builtins__": {}}, {}))


def check_c(path, census, fam):
    text = open(path, encoding="utf-8").read()
    defines = {"RC_UN_MAX": len(census), "STAT_UNSUPPORTED": 17}
    order = []
    for m in re.finditer(r"#define\s+(STAT_[A-Z]+)\s+([^\n]+)", text):
        name, expr = m.group(1), m.group(2)
        if name == "STAT_UNSUPPORTED":
            continue
        defines[name] = eval_chain(defines, expr)
        order.append(name)
    base, idx = slot_indices(census, fam)
    want = {"STAT_" + r["fam"] if r["stat"] != "-" else None: None for r in fam}
    fam_bases = {}
    for r in fam:
        if r["stat"] != "-":
            fam_bases[r["stat"]] = idx[id(r)]
    bad = []
    for stat_name, want_idx in fam_bases.items():
        if defines.get(stat_name) != want_idx:
            bad.append("%s: chain says %s, table says %d" % (stat_name, defines.get(stat_name), want_idx))
    last = base + len(census) + len(fam)
    if defines.get("STAT_LAST") != last:
        bad.append("STAT_LAST: chain says %s, table says %d" % (defines.get("STAT_LAST"), last))
    sizes = {}
    for r in fam:
        sizes[r["fam"]] = sizes.get(r["fam"], 0) + 1
    fam_order = []
    for r in fam:
        if r["fam"] not in fam_order:
            fam_order.append(r["fam"])
    for a, b in zip(fam_order, fam_order[1:]):
        ca, cb = defines["STAT_" + a.upper()], defines["STAT_" + b.upper()]
        if cb - ca != sizes[a]:
            bad.append("%s family: chain spans %d slots, table has %d" % (a, cb - ca, sizes[a]))
    if bad:
        sys.stderr.write("RenderJni.cpp STAT chain is stale -- table in Render.h moved:\n  " + "\n  ".join(bad) + "\n")
        sys.exit(1)


def main():
    here = sys.argv[0]
    args = [a for a in sys.argv[1:]]
    render_h = None
    mode = None
    target = None
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("--write", "--check", "--check-c", "--print"):
            mode = a
            if a in ("--check", "--check-c") and i + 1 < len(args):
                target = args[i + 1]
                i += 1
        elif a == "--render-h":
            render_h = args[i + 1]
            i += 1
        else:
            die("unknown arg: " + a)
        i += 1
    import os
    d = os.path.dirname(os.path.abspath(here))
    if render_h is None:
        render_h = os.path.join(d, "Render.h")
    census, fam = load_tables(render_h)
    if mode == "--check":
        if not target:
            die("--check needs a file")
        if "Render.java" in target:
            check_block(target, gate_block(census, fam), "Render.java")
        else:
            check_block(target, prod_block(census, fam), target)
        print("statslots: %s up to date" % target)
    elif mode == "--check-c":
        if not target:
            die("--check-c needs RenderJni.cpp")
        check_c(target, census, fam)
        print("statslots: STAT chain matches RC_STATFAM_X")
    elif mode == "--write":
        nr = os.environ.get("NR_JAVA")
        if not nr:
            die("--write needs NR_JAVA in the environment (the NativeRenderer.java to edit)")
        install_block(os.path.join(d, "Render.java"), gate_block(census, fam))
        install_block(nr, prod_block(census, fam))
        print("statslots: wrote both blocks")
    else:
        base, idx = slot_indices(census, fam)
        print("census=%d families=%d slots 17..%d" % (len(census), len(fam), base + len(census) + len(fam) - 1))
        for r in fam:
            print("  %3d  STAT %-12s gate %-16s prod %s" % (idx[id(r)], r["stat"], r["gate"], r["prod"]))


if __name__ == "__main__":
    main()

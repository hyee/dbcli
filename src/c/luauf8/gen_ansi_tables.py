#!/usr/bin/env python3
"""gen_ansi_tables.py -- regenerate ansi_width_tables from Unicode 15.0 (Python unicodedata).

Writes two files from one table, because the two width models in this project have to be the
same width model: the C header `ansi_width_tables.h` (src/c/luauf8/ansi_width.c, the Lua
utf8.ansi_width / utf8.ansi_cut engine) and the Java `AnsiWidthTables.java` (org/jline/utils,
behind JLine's WCWidth, so Display/Status/LineReader measure a cell the way the grid paints it).
`--java PATH...` writes the Java form; `--java-check PATH...` re-derives it and compares, so a
tree left behind by an edit to the rules below fails a gate instead of shipping quietly.

Width model, the one real terminals apply:
    Cc (C0, DEL, C1) + NUL  -> 0
    DRAWN_CF                -> 1   (Cf that terminals still draw: soft hyphen, the
                                    Prepended_Concatenation_Marks)
    JAMO_ZERO               -> 0   (conjoining Hangul jamo: drawn into the cell the
                                    initial jamo opened)
    Mn / Me / Cf            -> 0   (before EAW: U+3099, U+302A are Mn *and* EAW=W)
    EastAsianWidth W or F   -> 2
    WIDE                    -> 2   (UAX #11 default-wide for undesignated code points,
                                    plus the Yijing hexagrams)
    EastAsianWidth A        -> 2   (the ambiguous ruling), EXCEPT the code points measured
                                    1 cell in every console font -- AMBIGUOUS_NARROW below
    everything else         -> 1   (the narrow default every listed terminal uses)
Only runs whose width is not 1 are emitted, so cp_width() can default to 1.
The per-256-block map collapses every block whose 256 code points agree, so ASCII, CJK
and Hangul resolve with one table read and never scan an interval. (C header only -- the
Java table is a single binary search, which is the same answer and cannot drift from it.)
"""
import sys
import unicodedata as ud

# An older unicodedata silently produces a worse table: it does not know the code points
# added since, so they come out unassigned and width 1, splitting runs that should be
# uniform. The interval count this script prints is the tell -- Unicode 13 gave 1,036 where
# Unicode 15 gives a few hundred -- and it moves again with every width rule, so compare
# within a rule rather than against a number left in this comment.
UNIDATA_MIN = (15, 0, 0)
_unidata = tuple(int(x) for x in ud.unidata_version.split("."))
if _unidata < UNIDATA_MIN:
    sys.exit("gen_ansi_tables.py: this Python's unicodedata is Unicode %s, need >= %s. "
             "Run it with an interpreter whose unicodedata is new enough."
             % (ud.unidata_version, ".".join(str(x) for x in UNIDATA_MIN)))

NBLK = 4352
MAXCP = 0x10FFFF

# Invocation:
#   gen_ansi_tables.py [OUT.h]                      -- the C header (default name, as before)
#   gen_ansi_tables.py --java P [P...]              -- write the Java table to each path
#   gen_ansi_tables.py --java-check P [P...]         -- verify each path without touching it
# The Java form exists because two hand-written width tables are the bug this script was
# written to avoid: JLine's WCWidth carried its own Kuhn table while the Lua side consulted
# the generated one, and the grid measured a cell one way and the layout the other.
# Both files must come from ONE run of THIS script, so `--java` takes the list of trees to
# write and `--java-check` is the leg that fails when any of them has fallen behind.
JAVA_FLAG = "--java"
JAVA_CHECK_FLAG = "--java-check"

_argv = sys.argv[1:]
MODE = "c"
if _argv and _argv[0] == JAVA_FLAG:
    MODE, PATHS = "java", _argv[1:]
elif _argv and _argv[0] == JAVA_CHECK_FLAG:
    MODE, PATHS = "check", _argv[1:]
else:
    PATHS = _argv
if not PATHS:
    PATHS = ["ansi_width_tables.h"] if MODE == "c" else None
if MODE != "c" and not PATHS:
    sys.exit("gen_ansi_tables.py: %s needs at least one path" % MODE)
OUT = PATHS[0] if MODE == "c" else None

ZERO_CAT = ("Mn", "Me", "Cf")

# Code points whose width is not what Unicode's properties alone would give.
# The first five are UAX #11: undesignated code points inside these ranges default to
# East_Asian_Width=W, but unicodedata.east_asian_width() reports 'N' for anything
# unassigned. Without this the holes inside the CJK blocks come out as 1 -- wrong on a
# real terminal, and it also splits blocks that would otherwise be a single uniform width.
# The last is a measured override: EastAsianWidth says N for the Yijing hexagrams, but
# Windows Terminal, glibc, xterm and lutf8lib's own unidata.h all render them full width.
# Only conhost says 1, and conhost is font driven rather than cell driven.
WIDE = (
    (0x3400, 0x4DBF),     # CJK Unified Ideographs Extension A
    (0x4E00, 0x9FFF),     # CJK Unified Ideographs
    (0xF900, 0xFAFF),     # CJK Compatibility Ideographs
    (0x20000, 0x2FFFD),   # Plane 2, all undesignated code points
    (0x30000, 0x3FFFD),   # Plane 3, all undesignated code points
    (0x4DC0, 0x4DFF),     # Yijing hexagram symbols
)

# Cf (format) characters that a terminal nevertheless gives a cell to. U+00AD SOFT HYPHEN
# measures 1 in conhost, Windows Terminal, xterm and glibc alike -- all four of them. The
# rest are Unicode's Prepended_Concatenation_Marks: they sit in front of a number and are
# drawn there, which is why glibc, xterm and unidata.h all report 1 for them too.
DRAWN_CF = frozenset((0x00AD,
                      0x0600, 0x0601, 0x0602, 0x0603, 0x0604, 0x0605,
                      0x06DD, 0x070F, 0x0890, 0x0891, 0x08E2, 0x110BD, 0x110CD))

# Conjoining Hangul jamo. A medial (jungseong) or final (jongseong) jamo is drawn INTO the
# syllable cell that the initial jamo before it opened, so it advances the cursor by
# nothing. glibc zeroes exactly these three ranges and xterm follows it; the reading that
# settles it is a sequence, where U+1100 U+1161 measures 2 cells in xterm rather than 3.
# Windows agrees by shaping instead of by table: DirectWrite renders the pair as one
# two-cell syllable. A lone medial jamo is malformed text, so its own width is moot.
JAMO_ZERO = ((0x1160, 0x11FF), (0xD7B0, 0xD7C6), (0xD7CB, 0xD7FB))

# The ambiguous ruling: East_Asian_Width=A counts 2, because that is what the console does
# with the fonts a Chinese Windows console starts with.
#
# It is not, however, a property of the code point. D:\dbcli\cache\ambiguous\measure\
# ambmeasure.c wrote every ambiguous code point followed by a marker at a known column, and
# read the cursor back out of conhost -- 47,766 measurements over six faces the console itself
# confirmed (Consolas, Courier New, Lucida Console, MS Gothic, Terminal, and the CP-936 default
# 新宋体), each face verified with GetCurrentConsoleFontEx because SetCurrentConsoleFontEx
# returns TRUE even when it silently kept the previous face. The BMP sweep is exhaustive
# (7,292 code points) and reproduced byte for byte on a second run; the astral half samples
# 669 code points, because the first sweep dropped all 131,457 of them to a `> 0xFFFF` filter
# and a 138,164-code-point change came to rest on BMP evidence alone.
# The code page changes nothing: 437, 936 and 65001 give identical answers. The font changes
# everything, and it splits the ambiguous set three ways:
#
#   7,110 cps  every font gives 2 cells  (6,348 BMP private use, 667 astral: the assigned
#              U+1F100..U+1F1AC symbols, both astral PUA planes) -- the ruling is simply right
#     620 cps  some fonts give 2, some 1 (degree, plus-minus, Greek and Cyrillic capitals,
#              black square, arrows) -- these follow the ruling and count 2 here, which costs
#              a column of over-prediction on a Western console face and is correct on the
#              CJK default one. Recorded as the known cost; see DESIGN.md.
#     229 cps  every font gives 1 cell   -- the list below, minus the 17 that are Mn/Me/Cf
#              and reach the ambiguous branch never.
#
# Counting those 206 as 2 would break what this tool itself draws: every box-drawing border
# (U+2500..U+254B, U+2550..U+2573), every block element a progress bar is made of
# (U+2580..U+258F, U+2592..U+2595), and accented Latin text such as "Jose" with an e-acute.
# No font on this box gives any of them two cells, so the ruling cannot be about them.
# Regenerate this list from measure/sets.txt rather than editing it; the widths were measured,
# not derived, and a future Unicode update must not be allowed to look like a reason to.
#
# One thing the sweep does NOT settle, and a reader will ask: Mn/Me/Cf count 0 here while
# conhost gives them a cell of their own -- measure/Probe.java shows U+0041 U+0300 taking 2
# cells and U+4E2D U+0300 taking 3, so it is not the standalone case that differs. That is
# deliberate: xterm, Windows Terminal and glibc all absorb the mark, and one table has to
# serve every terminal this library is loaded into. See DESIGN.md's known costs.
AMBIGUOUS_NARROW = (
    (0x00A1, 0x00A1),      # INVERTED EXCLAMATION MARK
    (0x00AA, 0x00AA),      # FEMININE ORDINAL INDICATOR
    (0x00AE, 0x00AE),      # REGISTERED SIGN
    (0x00B2, 0x00B3),      # SUPERSCRIPT TWO .. SUPERSCRIPT THREE
    (0x00B8, 0x00BA),      # CEDILLA .. MASCULINE ORDINAL INDICATOR
    (0x00BC, 0x00BF),      # VULGAR FRACTION ONE QUARTER .. INVERTED QUESTION MARK
    (0x00C6, 0x00C6),      # LATIN CAPITAL LETTER AE
    (0x00D0, 0x00D0),      # LATIN CAPITAL LETTER ETH
    (0x00D8, 0x00D8),      # LATIN CAPITAL LETTER O WITH STROKE
    (0x00DE, 0x00E1),      # LATIN CAPITAL LETTER THORN .. LATIN SMALL LETTER A WITH ACUTE
    (0x00E6, 0x00E6),      # LATIN SMALL LETTER AE
    (0x00E8, 0x00EA),      # LATIN SMALL LETTER E WITH GRAVE .. E WITH CIRCUMFLEX
    (0x00EC, 0x00ED),      # LATIN SMALL LETTER I WITH GRAVE .. I WITH ACUTE
    (0x00F0, 0x00F0),      # LATIN SMALL LETTER ETH
    (0x00F2, 0x00F3),      # LATIN SMALL LETTER O WITH GRAVE .. O WITH ACUTE
    (0x00F8, 0x00FA),      # LATIN SMALL LETTER O WITH STROKE .. U WITH ACUTE
    (0x00FC, 0x00FC),      # LATIN SMALL LETTER U WITH DIAERESIS
    (0x00FE, 0x00FE),      # LATIN SMALL LETTER THORN
    (0x0101, 0x0101),      # LATIN SMALL LETTER A WITH MACRON
    (0x0113, 0x0113),      # LATIN SMALL LETTER E WITH MACRON
    (0x011B, 0x011B),      # LATIN SMALL LETTER E WITH CARON
    (0x012B, 0x012B),      # LATIN SMALL LETTER I WITH MACRON
    (0x0131, 0x0131),      # LATIN SMALL LETTER DOTLESS I
    (0x0133, 0x0133),      # LATIN SMALL LIGATURE IJ
    (0x0138, 0x0138),      # LATIN SMALL LETTER KRA
    (0x013F, 0x0142),      # LATIN CAPITAL L WITH MIDDLE DOT .. SMALL LETTER L WITH STROKE
    (0x0144, 0x0144),      # LATIN SMALL LETTER N WITH ACUTE
    (0x0148, 0x0148),      # LATIN SMALL LETTER N WITH CARON
    (0x014D, 0x014D),      # LATIN SMALL LETTER O WITH MACRON
    (0x0152, 0x0153),      # LATIN CAPITAL LIGATURE OE .. SMALL LIGATURE OE
    (0x0166, 0x0167),      # LATIN CAPITAL T WITH STROKE .. SMALL LETTER T WITH STROKE
    (0x016B, 0x016B),      # LATIN SMALL LETTER U WITH MACRON
    (0x0251, 0x0251),      # LATIN SMALL LETTER ALPHA
    (0x0261, 0x0261),      # LATIN SMALL LETTER SCRIPT G
    (0x02CD, 0x02CD),      # MODIFIER LETTER LOW MACRON
    (0x02D0, 0x02D0),      # MODIFIER LETTER TRIANGULAR COLON
    (0x02D8, 0x02D8),      # BREVE
    (0x02DA, 0x02DB),      # RING ABOVE .. OGONEK
    (0x02DD, 0x02DD),      # DOUBLE ACUTE ACCENT
    (0x2022, 0x2022),      # BULLET
    (0x2024, 0x2024),      # ONE DOT LEADER
    (0x2027, 0x2027),      # HYPHENATION POINT
    (0x203E, 0x203E),      # OVERLINE
    (0x2074, 0x2074),      # SUPERSCRIPT FOUR
    (0x207F, 0x207F),      # SUPERSCRIPT LATIN SMALL LETTER N
    (0x2081, 0x2084),      # SUBSCRIPT ONE .. SUBSCRIPT FOUR
    (0x2113, 0x2113),      # SCRIPT SMALL L
    (0x2122, 0x2122),      # TRADE MARK SIGN
    (0x2500, 0x254B),      # BOX DRAWINGS LIGHT HORIZONTAL .. HEAVY VERTICAL AND HORIZONTAL
    (0x2550, 0x2573),      # BOX DRAWINGS DOUBLE HORIZONTAL .. LIGHT DIAGONAL CROSS
    (0x2580, 0x258F),      # UPPER HALF BLOCK .. LEFT ONE EIGHTH BLOCK
    (0x2592, 0x2595),      # MEDIUM SHADE .. RIGHT ONE EIGHTH BLOCK
    (0xE7C7, 0xE7C8),      # unassigned: measured narrow in every face, unlike the PUA around it
)

_AMBIG_NARROW = frozenset(cp for lo, hi in AMBIGUOUS_NARROW for cp in range(lo, hi + 1))


def in_ranges(cp, ranges):
    for lo, hi in ranges:
        if lo <= cp <= hi:
            return True
    return False


def width(cp):
    if cp == 0 or cp < 0x20 or 0x7F <= cp <= 0x9F:
        return 0
    if cp in DRAWN_CF:
        return 1
    if in_ranges(cp, JAMO_ZERO):
        return 0
    ch = chr(cp)
    if ud.category(ch) in ZERO_CAT:
        return 0
    eaw = ud.east_asian_width(ch)
    if eaw == "A":
        return 1 if cp in _AMBIG_NARROW else 2
    if eaw in ("W", "F"):
        return 2
    if in_ranges(cp, WIDE):
        return 2
    return 1


w = [width(cp) for cp in range(MAXCP + 1)]

# collapse into runs of equal width, keep only the ones that are not the default 1
iv = []
cp = 0
while cp <= MAXCP:
    if w[cp] != 1:
        lo, val = cp, w[cp]
        while cp + 1 <= MAXCP and w[cp + 1] == val:
            cp += 1
        iv.append((lo, cp, val))
    cp += 1
niv = len(iv)

# per-block map: uniform width, or -1 when the block's 256 code points disagree
blk_w, blk_iv, mixed, maxscan = [], [], 0, 0
for b in range(NBLK):
    lo, hi = b * 256, b * 256 + 255
    vals = set(w[lo:hi + 1])
    if len(vals) == 1:
        blk_w.append(vals.pop())
        blk_iv.append(0)
    else:
        blk_w.append(-1)
        mixed += 1
        start = next((k for k, v in enumerate(iv) if v[1] >= lo and v[0] <= hi), niv)
        blk_iv.append(start)
        # longest linear scan cp_width() can perform inside this block
        span = next((k for k, v in enumerate(iv) if v[0] > hi), niv)
        maxscan = max(maxscan, span - start)

assert niv < 65536, "ansi_blk_iv is uint16_t"
assert all(0 <= v <= 2 for v in blk_w if v >= 0)

o = []
o.append("/* GENERATED by gen_ansi_tables.py from Unicode %s (Python unicodedata) -- DO NOT EDIT BY HAND.\n"
         % ud.unidata_version)
o.append(" * Width model: Mn/Me/Cf and Cc -> 0 (checked before EAW, since U+3099/U+302A are\n"
         " * both Mn and EAW=W); EastAsianWidth W/F -> 2; unassigned code points inside the\n"
         " * CJK ideograph blocks and Planes 2/3 -> 2 (UAX #11 default, which unicodedata\n"
         " * does not report); EastAsianWidth A -> 2 except for the code points measured 1\n"
         " * cell in every console font, which stay 1 (AMBIGUOUS_NARROW in the generator).\n"
         " * Measured overrides, see gen_ansi_tables.py: the soft hyphen and the 13\n"
         " * Prepended_Concatenation_Marks -> 1, conjoining Hangul jamo -> 0, Yijing -> 2.\n"
         " * Only runs that are not 1 are listed.\n")
o.append(" * Regenerate with:  python3 gen_ansi_tables.py <path>/ansi_width_tables.h\n")
o.append(" * The same run also writes the Java copy of this table -- see --java below. */\n")
o.append("#ifndef ANSI_WIDTH_TABLES_H\n#define ANSI_WIDTH_TABLES_H\n#include <stdint.h>\n\n")
o.append("#define ANSI_NBLK %d\n#define ANSI_NWIV %d\n\n" % (NBLK, niv))
o.append("typedef struct { uint32_t first, last; uint8_t w; } ansi_iv;\n\n")
o.append("static const ansi_iv ansi_wiv[ANSI_NWIV] = {\n")
for k, (a, b, v) in enumerate(iv):
    o.append("{0x%X,0x%X,%d}," % (a, b, v))
    o.append("\n" if (k + 1) % 6 == 0 else "")
o.append("\n};\n\n")
o.append("/* ansi_blk_w[b]: uniform width of block b (0/1/2), or -1 when the block is mixed\n"
        " * (then scan ansi_wiv from ansi_blk_iv[b]). ansi_blk_iv[b] is the 0-based index of\n"
        " * the first interval overlapping block b, so the scan never walks the whole table. */\n")
o.append("static const int8_t ansi_blk_w[ANSI_NBLK] = {\n")
for b in range(NBLK):
    o.append("%d," % blk_w[b])
    if (b + 1) % 32 == 0:
        o.append("\n")
o.append("\n};\n\n")
o.append("static const uint16_t ansi_blk_iv[ANSI_NBLK] = {\n")
for b in range(NBLK):
    o.append("%d," % blk_iv[b])
    if (b + 1) % 32 == 0:
        o.append("\n")
o.append("\n};\n\n#endif /* ANSI_WIDTH_TABLES_H */\n")
C_TEXT = "".join(o)


def java_rows(vals, per):
    """8 intervals or 16 widths per line -- wide enough to keep the file short, narrow enough
    that a stale copy shows up as a one-line diff instead of a wall of rewrapped numbers."""
    return ["        " + " ".join(v + "," for v in vals[k:k + per]) + "\n"
            for k in range(0, len(vals), per)]


# The Java table is the same 594 runs, in the same order, with the same widths -- only the
# shape of the array differs. No range is written down here twice: if the model changes, both
# halves change together or --java-check says so.
JAVA_BEGIN = ("    // ---- BEGIN GENERATED WIDTH TABLE (gen_ansi_tables.py --java) : DO NOT EDIT, "
              "DO NOT HAND-COPY ----")
JAVA_END = "    // ---- END GENERATED WIDTH TABLE ----\n"


def build_java():
    j = []
    j.append("/*\n"
             " * Copyright (c) 2002-2025, the original author(s).\n"
             " *\n"
             " * This software is distributable under the BSD license. See the terms of the\n"
             " * BSD license in the documentation provided with this software.\n"
             " *\n"
             " * https://opensource.org/licenses/BSD-3-Clause\n"
             " */\n")
    j.append("package org.jline.utils;\n\n")
    j.append("/**\n"
             " * The display width of every Unicode code point, as the terminals this library is\n"
             " * loaded into actually lay them out. <b>Generated file</b> -- dbcli's\n"
             " * {@code src/c/luauf8/gen_ansi_tables.py} (Unicode %s, Python unicodedata) writes it together\n"
             " * with {@code ansi_width_tables.h}, the table behind the Lua {@code utf8.ansi_width} engine.\n"
             " * One run of one script writes both, which is the whole reason this class exists: the\n"
             " * grid may not size a cell one way and the layout another.\n"
             " *\n"
             " * <p>The rules, and what each of them cost:\n"
             " * <ul>\n"
             " *   <li>Mn / Me / Cf and the C0/C1 controls count 0 -- checked before East_Asian_Width,\n"
             " *       because U+3099 and U+302A are both Mn <i>and</i> EAW=W.</li>\n"
             " *   <li>East_Asian_Width W and F count 2, and so do the undesignated code points inside\n"
             " *       the CJK ideograph blocks and Planes 2 and 3 (UAX #11's default, which\n"
             " *       unicodedata does not report for unassigned characters).</li>\n"
             " *   <li>East_Asian_Width A counts 2 -- the ruling a CJK console font applies -- except\n"
             " *       for the code points measured one cell in every console font on the box (box\n"
             " *       drawing, block elements, accented Latin). That carve-out is\n"
             " *       {@code AMBIGUOUS_NARROW} in the generator, and it is measured, not derived.</li>\n"
             " *   <li>Measured overrides: the soft hyphen and the 13 Prepended_Concatenation_Marks\n"
             " *       get a cell, conjoining Hangul jamo do not, the Yijing hexagrams count 2.</li>\n"
             " *   <li>Everything else is 1, which is why only runs that are <i>not</i> 1 are listed.</li>\n"
             " * </ul>\n"
             " *\n"
             " * <p>Control characters are listed here as 0, and {@link WCWidth#wcwidth(int)} answers\n"
             " * them with its own contract first: JLine returns -1 for C0/C1 and DEL, where the C table\n"
             " * says 0. That difference is JLine's, not a disagreement about the grid.\n"
             " *\n"
             " * <p>Regenerate with\n"
             " * {@code python3 gen_ansi_tables.py --java <tree>/org/jline/utils/AnsiWidthTables.java ...}\n"
             " * naming every jline tree that builds; {@code --java-check} with the same paths is the leg\n"
             " * that fails when one of them has fallen behind.\n"
             " */\n"
             % ud.unidata_version)
    j.append("public final class AnsiWidthTables {\n\n")
    j.append("    private AnsiWidthTables() {}\n\n")
    j.append(JAVA_BEGIN + "\n")
    j.append("    /** Start of each run whose width is not 1, ascending and non-overlapping. */\n")
    j.append("    static final int[] FIRST = {\n")
    j.extend(java_rows(["0x%X" % a for a, b, v in iv], 8))
    j.append("\n    };\n\n")
    j.append("    /** End of each run, inclusive, paired with {@link #FIRST}. */\n")
    j.append("    static final int[] LAST = {\n")
    j.extend(java_rows(["0x%X" % b for a, b, v in iv], 8))
    j.append("\n    };\n\n")
    j.append("    /** The width of each run: 0 or 2 -- a run of 1s is not a run worth listing. */\n")
    j.append("    static final byte[] WIDTH = {\n")
    j.extend(java_rows([str(v) for a, b, v in iv], 16))
    j.append("\n    };\n")
    j.append(JAVA_END + "\n")
    j.append("    /**\n"
             "     * The width of one code point: 0, 1 or 2 columns. Binary search over the listed runs,\n"
             "     * defaulting to 1; the answer is {@code cp_width()}'s in ansi_width.c for every code\n"
             "     * point the Lua decoder can produce.\n"
             "     */\n"
             "    static int width(int cp) {\n"
             "        if (cp < FIRST[0] || cp > LAST[LAST.length - 1]) {\n"
             "            return 1;\n"
             "        }\n"
             "        int lo = 0;\n"
             "        int hi = FIRST.length - 1;\n"
             "        while (lo <= hi) {\n"
             "            int mid = (lo + hi) >>> 1;\n"
             "            if (cp > LAST[mid]) {\n"
             "                lo = mid + 1;\n"
             "            } else if (cp < FIRST[mid]) {\n"
             "                hi = mid - 1;\n"
             "            } else {\n"
             "                return WIDTH[mid];\n"
             "            }\n"
             "        }\n"
             "        return 1;\n"
             "    }\n"
             "}\n")
    return "".join(j)


JAVA_TEXT = build_java() if MODE != "c" else None

if MODE == "c":
    with open(OUT, "w", newline="\n") as fh:
        fh.write(C_TEXT)
    print("unicode %s -> %s" % (ud.unidata_version, OUT))
else:
    for path in PATHS:
        if MODE == "check":
            try:
                raw = open(path, encoding="utf-8", newline="\n").read()
            except IOError as err:
                sys.exit("gen_ansi_tables.py --java-check: cannot read %s: %s" % (path, err))
            # CRLF-tolerant on purpose. Both jline repos are checked out with core.autocrlf=true, so the
            # same file is LF the moment the generator writes it and CRLF the moment git touches it --
            # and a drift check that reports "STALE" for a line ending teaches nobody anything. The
            # generator's own output stays LF; only the comparison folds.
            have = raw.replace("\r\n", "\n")
            if have == JAVA_TEXT:
                print("%s: table is current (%d runs%s)"
                      % (path, niv, ", CRLF" if raw != have else ""))
                continue
            a, b = have.splitlines(), JAVA_TEXT.splitlines()
            sys.stderr.write("%s: STALE -- regenerate with: python3 gen_ansi_tables.py --java %s\n"
                             % (path, path))
            for i in range(max(len(a), len(b))):
                x = a[i] if i < len(a) else "<none>"
                y = b[i] if i < len(b) else "<none>"
                if x != y:
                    sys.stderr.write("  line %d\n  have: %s\n  want: %s\n" % (i + 1, x, y))
                    break
            sys.stderr.write("  have %d lines / want %d lines\n" % (len(a), len(b)))
            sys.exit(1)
        with open(path, "w", newline="\n") as fh:
            fh.write(JAVA_TEXT)
        print("unicode %s -> %s (%d runs)" % (ud.unidata_version, path, niv))

print("intervals=%d  blocks uniform=%d mixed=%d  longest interval scan in one block=%d"
      % (niv, NBLK - mixed, mixed, maxscan))
if MODE != "check":
    for cp in (0x231A, 0x2614, 0x2648, 0x2764, 0x4E2D, 0xAC00, 0x09BE, 0x0616, 0x0487,
               0x3099, 0xFE0F, 0x1F3FB, 0x1F600, 0x2500, 0x00AD, 0x200B, 0x0009, 0x001B,
               0x0600, 0x110BD, 0x1100, 0x1160, 0x4DC0, 0x3248, 0x2630):
        print("  U+%04X cat=%-3s eaw=%-2s -> %d" % (cp, ud.category(chr(cp)),
                                                    ud.east_asian_width(chr(cp)), w[cp]))

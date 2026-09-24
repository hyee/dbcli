#!/usr/bin/env python3
"""gen_ansi_tables.py -- regenerate ansi_width_tables.h from Unicode 15.0 (Python unicodedata).

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
    everything else         -> 1   (EastAsianWidth A -> 1, the narrow default every
                                    listed terminal uses unless the user opts in)
Only runs whose width is not 1 are emitted, so cp_width() can default to 1.
The per-256-block map collapses every block whose 256 code points agree, so ASCII, CJK
and Hangul resolve with one table read and never scan an interval.
"""
import sys
import unicodedata as ud

# An older unicodedata silently produces a worse table: it does not know the code points
# added since, so they come out unassigned and width 1, splitting runs that should be
# uniform (Unicode 13 yields 1036 intervals where Unicode 15 yields 481).
UNIDATA_MIN = (15, 0, 0)
_unidata = tuple(int(x) for x in ud.unidata_version.split("."))
if _unidata < UNIDATA_MIN:
    sys.exit("gen_ansi_tables.py: this Python's unicodedata is Unicode %s, need >= %s. "
             "Run it with an interpreter whose unicodedata is new enough."
             % (ud.unidata_version, ".".join(str(x) for x in UNIDATA_MIN)))

NBLK = 4352
MAXCP = 0x10FFFF
OUT = sys.argv[1] if len(sys.argv) > 1 else "ansi_width_tables.h"

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


def width(cp):
    if cp == 0 or cp < 0x20 or 0x7F <= cp <= 0x9F:
        return 0
    if cp in DRAWN_CF:
        return 1
    for lo, hi in JAMO_ZERO:
        if lo <= cp <= hi:
            return 0
    ch = chr(cp)
    if ud.category(ch) in ZERO_CAT:
        return 0
    if ud.east_asian_width(ch) in ("W", "F"):
        return 2
    for lo, hi in WIDE:
        if lo <= cp <= hi:
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
         " * does not report); everything else, including EastAsianWidth A, -> 1.\n"
         " * Measured overrides, see gen_ansi_tables.py: the soft hyphen and the 13\n"
         " * Prepended_Concatenation_Marks -> 1, conjoining Hangul jamo -> 0, Yijing -> 2.\n"
         " * Only runs that are not 1 are listed.\n")
o.append(" * Regenerate with:  python3 gen_ansi_tables.py <path>/ansi_width_tables.h */\n")
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

with open(OUT, "w", newline="\n") as fh:
    fh.write("".join(o))

print("unicode %s -> %s" % (ud.unidata_version, OUT))
print("intervals=%d  blocks uniform=%d mixed=%d  longest interval scan in one block=%d"
      % (niv, NBLK - mixed, mixed, maxscan))
for cp in (0x231A, 0x2614, 0x2648, 0x2764, 0x4E2D, 0xAC00, 0x09BE, 0x0616, 0x0487,
           0x3099, 0xFE0F, 0x1F3FB, 0x1F600, 0x2500, 0x00AD, 0x200B, 0x0009, 0x001B,
           0x0600, 0x110BD, 0x1100, 0x1160, 0x4DC0, 0x3248, 0x2630):
    print("  U+%04X cat=%-3s eaw=%-2s -> %d" % (cp, ud.category(chr(cp)),
                                                ud.east_asian_width(chr(cp)), w[cp]))

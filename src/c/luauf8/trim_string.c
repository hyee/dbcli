/*
 * trim_string.c -- utf8.trim_space and utf8.trim_chars, merged into the LuaJIT "utf8" module.
 *
 * This translation unit is compiled together with lutf8lib.c into
 * lib/<plat>/utf8.[so|dll]. The open function (luaopen_utf8) and the
 * luaL_Reg table live in lutf8lib.c; here we expose two plain lua_CFunctions,
 * `luautf8_trim_space` and `luautf8_trim_chars`, which lutf8lib.c registers as
 *   { "trim_space", luautf8_trim_space }
 *   { "trim_chars", luautf8_trim_chars }
 * so both MUST keep external linkage and the exact lua_CFunction prototype.
 *
 *   utf8.trim_space(s [, mode])        -- drop leading/trailing WHITESPACE
 *   utf8.trim_chars(s, chars [, mode]) -- drop leading/trailing chars in `chars`
 *     mode: <0 ltrim (leading only) | >0 rtrim (trailing only) | 0/absent trim both
 *
 * WHAT COUNTS AS BLANK (the target is a terminal running UTF-8, so the rule is
 * "invisible, and removing it cannot garble what is left"):
 *
 *   1. ASCII 0x00..0x20 is blank, EXCEPT ESC 0x1B, which introduces every ANSI
 *      escape sequence. DEL 0x7F is blank too -- it has no glyph and no advance.
 *   2. BEL 0x07 is blank EXCEPT when it is the terminator of an open OSC / APC /
 *      PM / SOS / DCS sequence. Dropping it there leaves the escape unterminated
 *      and the terminal swallows every byte written afterwards, which is far worse
 *      than leaving one bell in the string. See bel_classify().
 *   3. The C1 block U+0080..U+009F is blank, EXCEPT the members that would act as
 *      8-bit escape introducers/terminators if any downstream consumer is not in
 *      UTF-8 mode: SS2/SS3/DCS (0x8E..0x90) and SOS..APC (0x98..0x9F). They are
 *      preserved for exactly the reason ESC is.
 *   4. The full Unicode White_Space property (all 25 code points), which covers
 *      NBSP, NEL, OGHAM SPACE MARK, U+2000..U+200A, the line/paragraph separators,
 *      NNBSP, MMSP and IDEOGRAPHIC SPACE.
 *   5. Zero-width invisibles that cannot alter a neighbouring glyph: SOFT HYPHEN,
 *      CGJ, ALM, the Hangul and halfwidth Hangul fillers, the Khmer inherent
 *      vowels, MVS, ZWSP/ZWNJ/ZWJ, LRM/RLM, the bidi embeddings and isolates, the
 *      word joiner and invisible operators, BOM, the interlinear annotation marks
 *      and the Tag block.
 *
 * DELIBERATELY NOT BLANK, because removing them changes how the KEPT text renders:
 *   - variation selectors U+FE00..U+FE0F and U+E0100..U+E01EF -- a trailing VS16
 *     is what turns the last emoji from text into colour presentation;
 *   - Mongolian free variation selectors U+180B..U+180D and U+180F -- same, they
 *     pick the glyph form of the preceding letter;
 *   - every other combining mark (Mn/Me), which is why U+0301 never matched;
 *   - U+2800 BRAILLE PATTERN BLANK and U+FFFC/U+FFFD, which look blank or special
 *     but are real characters with an advance;
 *   - U+070F SYRIAC ABBREVIATION MARK, a Cf that fonts do draw.
 *
 * INVARIANT: trim_space only ever consumes a byte range that is the canonical
 * (shortest) UTF-8 encoding of one of the code points above; anything else is
 * opaque and kept. utf8_decode() masks continuation bytes with 0x3F and cannot
 * distinguish "\xC2" 'E' (an invalid lead followed by a visible 'E') from a real
 * U+0085 NEL, and both scans used to consume the 'E'. The proof is now
 * utf8_canon(), applied only once the classifier has already decided to drop --
 * so CJK body text, the bulk of what this CLI trims, never reaches it.
 *
 * Trimming is codepoint aware (never splits a multibyte sequence), works on the
 * original buffer with no mutation and no extra malloc, and the input length comes
 * from luaL_checklstring so embedded '\0' bytes are handled. When nothing is trimmed,
 * the argument string is returned as-is (lua_pushvalue) to skip interning.
 *
 * PERFORMANCE: these are called per grid cell, so the byte ladder is ordered for
 * the real distribution, not for uniformity. A trailing run of plain SPACE -- what
 * a padded cell actually ends with -- is peeled by its own inner loop at two
 * predicted tests per byte, and the general ladder behind it never re-tests it.
 * Multibyte bytes are decoded and classified BEFORE their canonical form is
 * proved, because validation is only owed for bytes about to be dropped.
 *
 * Two inlining rules that are easy to break by accident, both found by measuring:
 *   * trim_bounds() must have NO address-taken local. One is enough for GCC's
 *     default -fstack-protector-strong to give it a stack canary and a 72-byte
 *     frame, which cost ~2.4 ns on every call -- including the no-op ones. That is
 *     why bel_classify() returns its cache by value.
 *   * utf8_is_space() must stay inlined into both scans, but only its hot part; the
 *     rare remainder is outlined into utf8_is_space_cold(). All-inline cost a real
 *     call per multibyte code point once GCC gave up on it (+6..12 ns); all-outlined
 *     grew trim_bounds() until GCC could no longer keep it in caller-saved
 *     registers (~9 cycles on every call). The ANSI/BEL machinery is outlined too:
 *     it is reached only when the byte about to be dropped is a BEL, which a space
 *     run never produces.
 */

#include <lua.h>
#include <lauxlib.h>
#include <stdint.h>
#include <string.h>

/*
 * The leaf classifiers below MUST stay inlined. Once utf8_is_space() grew past
 * GCC's voluntary inline budget it became two real calls inside trim_bounds(),
 * measured at +6..12 ns per multibyte code point -- more than the entire scan.
 * The double-underscore spelling keeps this legal under the ship build's -std=c99.
 */
#if defined(__GNUC__) || defined(__clang__)
#define UTF8_HOT static inline __attribute__((always_inline))
#define UTF8_COLD static __attribute__((noinline))
#else
#define UTF8_HOT static inline
#define UTF8_COLD static
#endif

/* Byte length of a UTF-8 sequence given its lead byte; invalid lead -> 1. */
UTF8_HOT int utf8_seq_len(unsigned char lead) {
    if (lead < 0x80)           return 1;
    if ((lead & 0xE0) == 0xC0) return 2;
    if ((lead & 0xF0) == 0xE0) return 3;
    if ((lead & 0xF8) == 0xF0) return 4;
    return 1;                 /* stray continuation / invalid lead: treat as one opaque byte */
}

/* Decode the sl bytes (1..4) at s to a code point. The 0x3F masks accept ANY byte,
 * so a cheap decode is not proof of validity: "\xC2" 'E' decodes to U+0085 just as
 * a real NEL does. Callers decode first, classify, and only then prove canonical
 * form with utf8_canon() -- and only if they are about to drop. */
UTF8_HOT uint32_t utf8_decode(const unsigned char *s, int sl) {
    switch (sl) {
        case 1:  return s[0];
        case 2:  return ((uint32_t)(s[0] & 0x1F) << 6) | (uint32_t)(s[1] & 0x3F);
        case 3:  return ((uint32_t)(s[0] & 0x0F) << 12) | ((uint32_t)(s[1] & 0x3F) << 6)
                        | (uint32_t)(s[2] & 0x3F);
        default: return ((uint32_t)(s[0] & 0x07) << 18) | ((uint32_t)(s[1] & 0x3F) << 12)
                        | ((uint32_t)(s[2] & 0x3F) << 6) | (uint32_t)(s[3] & 0x3F);
    }
}

/*
 * Is s[0..sl) the canonical (shortest-form, valid-tail) encoding of a code point?
 * Fuses two checks that used to re-branch on sl eight times per dropped code point:
 *
 *   tails    every byte after the lead is 10xxxxxx. utf8_decode() masks with 0x3F,
 *            so without this "\xC2" 'E' and a real U+0085 NEL are indistinguishable.
 *   shortest sl is the minimum length for the code point. Kills overlongs, and kills
 *            stray continuations and 0xF5..0xFF leads, which utf8_seq_len() reports
 *            as length 1 while decoding to >= 0x80.
 *
 * Both are decided from the bytes alone, so the decoded cp is not needed. sl comes
 * from utf8_seq_len(), which means the lead is already pinned to its range, and
 * within that range the lower bound on cp collapses to one compare:
 *
 *   sl==2  lead in C0..DF, cp < 0x800 always. cp >= 0x80  <=>  lead >= 0xC2.
 *   sl==3  lead in E0..EF, cp < 0x10000 always. cp >= 0x800  <=>  lead >= 0xE1, or
 *          lead == 0xE0 and the first continuation carries >= 6 bits' worth, i.e.
 *          s[1] >= 0xA0 (its low 6 bits are >= 0x20).
 *   sl==4  lead in F0..F7, cp < 0x200000 always. cp >= 0x10000  <=>  lead >= 0xF1,
 *          or lead == 0xF0 and s[1] >= 0x90 (low 6 bits >= 0x10).
 *   sl==1  only reachable for an invalid lead (0x80..0xBF, 0xF8..0xFF), since both
 *          scans get here from a byte >= 0x80 and sl==1 means utf8_seq_len() refused
 *          it. Such a byte is never canonical, so the answer is 0 without looking.
 *
 * Two-byte goes first: NBSP and the rest of Latin-1 Supplement are the multibyte
 * blanks real database output contains, and U+3000 pays one extra compare for it.
 *
 * Surrogates and values above U+10FFFF need no explicit range check: no
 * utf8_is_space() branch accepts them (0xD800..0xDFFF falls in the CJK hot reject,
 * and a non-canonical 4-byte form decodes to >= 0x110000, which is blank nowhere).
 */
UTF8_HOT int utf8_canon(const unsigned char *s, int sl) {
    if (sl == 2) return (s[1] & 0xC0) == 0x80 && s[0] >= 0xC2;
    if (sl == 3) return (s[1] & 0xC0) == 0x80 && (s[2] & 0xC0) == 0x80
                     && (s[0] >= 0xE1 || s[1] >= 0xA0);
    if (sl == 4) return (s[1] & 0xC0) == 0x80 && (s[2] & 0xC0) == 0x80
                     && (s[3] & 0xC0) == 0x80 && (s[0] >= 0xF1 || s[1] >= 0x90);
    return 0;                                    /* sl == 1: invalid lead, see above */
}

/*
 * ASCII edge classification: 0 = keep, 1 = drop, 2 = drop unless this BEL turns
 * out to terminate an open escape sequence.
 *
 * Ordered so the two outcomes that dominate a real workload are the cheapest. The
 * visible printable byte that ENDS every trim is first and costs a single compare:
 * (c - 0x21) <= 0x5D is exactly 0x21..0x7E under unsigned wraparound. That matters
 * because it is the only byte a no-op trim ever classifies -- a cell that needs no
 * trimming pays this test twice and nothing else, so it was worth trading one extra
 * compare on the rare SPACE and DEL outcomes for two fewer on the hot one.
 *
 * ESC is kept because it introduces every ANSI sequence. DEL is dropped: it has no
 * glyph and no advance in a UTF-8 terminal.
 */
UTF8_HOT int ascii_class(unsigned char c) {
    if ((unsigned)(c - 0x21) <= 0x5D) return 0;  /* 0x21..0x7E printable: the cell body */
    if (c == 0x20) return 1;                     /* SPACE (pre-peeled by the run loop) */
    if (c >  0x20) return c == 0x7F;             /* DEL drop; 0x80.. keep, callers pass < 0x80 */
    if (c == 0x1B) return 0;                     /* ESC: never trim */
    return c == 0x07 ? 2 : 1;                    /* BEL needs escape context */
}

/*
 * The tail of the classifier: everything that is neither ASCII, nor in the
 * CJK band, nor in the C1/NBSP block, nor IDEOGRAPHIC SPACE. Outlined on
 * purpose -- see utf8_is_space() below.
 *
 * Reached with cp in [0xA1, 0x3164] (minus 0x3000) or cp >= 0xFEFF.
 */
UTF8_COLD int utf8_is_space_cold(uint32_t cp) {
    if (cp >= 0x2000) {
        if (cp < 0xFEFF) {
            /* U+2000..U+3164: general punctuation, then nothing until CJK */
            if (cp <= 0x200F) return 1;          /* EN QUAD..HAIR SPACE, ZWSP/ZWNJ/ZWJ, LRM/RLM */
            if (cp <  0x2028) return 0;          /* dashes, quotes, bullets: visible */
            if (cp <= 0x202F) return 1;          /* LINE/PARA SEP, bidi embeddings, NNBSP */
            if (cp <  0x205F) return 0;          /* per-mille, primes, arrows: visible */
            if (cp <= 0x206F) return 1;          /* MMSP, WORD JOINER, invisible operators,
                                                    bidi isolates, deprecated format controls */
            return cp == 0x3164;                 /* HANGUL FILLER; U+3000 is settled inline */
        }
        /* U+FEFF and above */
        if (cp <= 0xFFFB) return cp == 0xFEFF || cp == 0xFFA0 || cp >= 0xFFF0;
        if (cp >= 0x1BCA0 && cp <= 0x1BCA3) return 1;   /* shorthand format controls */
        if (cp >= 0x1D173 && cp <= 0x1D17A) return 1;   /* musical phrase marks */
        return cp >= 0xE0000 && cp <= 0xE007F;          /* Tag block (NOT the selectors above it) */
    }
    /* U+00A1..U+1FFF */
    if (cp == 0xAD) return 1;                    /* SOFT HYPHEN: shows only at a line break */
    if (cp >= 0x1680) return cp == 0x1680 || cp == 0x180E
                          || (cp >= 0x17B4 && cp <= 0x17B5);
    return cp == 0x34F || cp == 0x61C || cp == 0x115F || cp == 0x1160;
}

/*
 * Whether a code point counts as whitespace/invisible for trimming. See the file
 * header for the full policy and for what is deliberately excluded.
 *
 * Split hot/cold because both halves are load-bearing and they pull in opposite
 * directions. Whole-function inline: the multibyte path gained a real call per
 * code point (+6..12 ns). Whole-function outlined: trim_bounds() grew until GCC
 * could no longer keep it in caller-saved registers, which taxed EVERY call
 * (~9 cycles) including the no-op ones. So the three outcomes that dominate a
 * real workload stay inline -- ASCII, the blank-free CJK band, the C1/NBSP block
 * -- plus IDEOGRAPHIC SPACE, and the rare remainder is one outlined call.
 */
UTF8_HOT int utf8_is_space(uint32_t cp) {
    if (cp < 0x80) return ascii_class((unsigned char)cp) != 0;   /* ASCII: the bulk of a cell */
    if (cp > 0x3164 && cp < 0xFEFF) return 0;   /* CJK / Hangul / Kana / fullwidth: no blanks */
    if (cp == 0xA0) return 1;                   /* NBSP: the one 2-byte blank DB output has */
    if (cp <  0xA0) return !((cp >= 0x8E && cp <= 0x90) || cp >= 0x98);  /* C1, minus the
                                                    8-bit escape introducers/terminators */
    if (cp == 0x3000) return 1;                 /* IDEOGRAPHIC SPACE: CJK padding */
    return utf8_is_space_cold(cp);
}

/* ---------------- ANSI escape integrity (cold path) ---------------- */

#define NO_ESC         ((size_t)-1)  /* no ESC at or below the cursor */
#define BEL_TERMINATES ((size_t)-2)  /* this BEL closes an open sequence: stop trimming */

/*
 * One past the terminator of the ECMA-48 escape sequence starting at s[esc], or 0
 * if the bytes there are not a well-formed sequence within [esc, limit).
 */
UTF8_COLD size_t esc_seq_end(const unsigned char *s, size_t esc, size_t limit) {
    size_t j = esc + 1;
    for (;;) {
        unsigned char k;
        if (j >= limit) return 0;                  /* ESC with no body */
        k = s[j];
        if (k == 0x1B) { j++; continue; }          /* ESC ESC...: the last one starts it */
        if (k == ']' || k == '_' || k == '^' || k == 'X' || k == 'P') {
            /* OSC / APC / PM / SOS / DCS: a string body.
             *
             * Measured on xterm, Windows Terminal and conhost: BEL terminates only
             * OSC. In the other four a BEL is just a byte and the sequence stays
             * open, swallowing everything written after it. Believing BEL is more
             * generous than ECMA-48 requires, and it is the safe direction -- it
             * only ever makes us KEEP a byte. Do not tighten this to OSC-only: a
             * stricter rule would let rtrim drop the BEL of a DCS the terminal
             * still had open, which is the exact defect this function exists for. */
            for (j = j + 1; j < limit; j++) {
                if (s[j] == 0x07) return j + 1;
                if (s[j] == 0x1B && j + 1 < limit && s[j + 1] == '\\') return j + 2;
            }
            return 0;                              /* unterminated */
        }
        if (k == '[') {
            /* CSI: parameters 0x30..0x3F, intermediates 0x20..0x2F, final 0x40..0x7E */
            for (j = j + 1; j < limit; j++) {
                unsigned char c = s[j];
                if (c >= 0x40 && c <= 0x7E) return j + 1;
                if (c < 0x20 || c > 0x3F) return 0;
            }
            return 0;
        }
        if (k >= 0x30 && k <= 0x7E) return j + 1;  /* two-character sequence */
        return 0;
    }
}

/*
 * Classify the BEL at s[bel] and return the ESC cache to carry on with.
 *
 * Returns BEL_TERMINATES when that BEL closes an escape sequence which is still
 * open -- the caller must stop trimming there. Otherwise it returns the updated
 * cache: the index of the nearest ESC below the cursor, or NO_ESC when there is
 * none.
 *
 * The cache is returned by value, not through a pointer, on purpose. An
 * address-taken local in trim_bounds() is enough for GCC's default
 * -fstack-protector-strong to emit a stack canary and a 72-byte frame there,
 * which taxed EVERY call by ~2.4 ns -- including the no-op ones, which never
 * reach this function at all. Nothing is lost by the change: on BEL_TERMINATES
 * the caller breaks out of the scan, so it never needs the cache again.
 *
 * Amortisation: the right scan moves strictly leftward, so a cached index stays
 * valid for every later BEL above it and NO_ESC stays valid for good. Each byte is
 * therefore stepped over at most once and a pathological run of trailing BELs stays
 * linear instead of quadratic. Initialise the cache to `len` ("not searched yet"),
 * never to NO_ESC.
 */
UTF8_COLD size_t bel_classify(const unsigned char *s, size_t start, size_t bel, size_t len,
                              size_t hint) {
    size_t esc = hint;
    if (hint == NO_ESC) return NO_ESC;
    if (hint >= bel) {
        size_t i = bel;
        int found = 0;
        while (i > start) { i--; if (s[i] == 0x1B) { found = 1; break; } }
        if (!found) return NO_ESC;
        esc = i;
    }
    return esc_seq_end(s, esc, len) == bel + 1 ? BEL_TERMINATES : esc;
}

/* Is `cp` one of the code points in the UTF-8 set [set, set+set_len)?
 * The set is decoded on the fly (no allocation, no cap on set size). */
static inline int cp_in_set(uint32_t cp, const unsigned char *set, size_t set_len) {
    size_t i = 0;
    while (i < set_len) {
        unsigned char lead = set[i];
        int sl = utf8_seq_len(lead);
        if (i + (size_t)sl > set_len) sl = 1;          /* truncated tail -> treat as one byte */
        if (utf8_decode(set + i, sl) == cp) return 1;
        i += sl;
    }
    return 0;
}

/* What a given code point should be trimmed (this drives both APIs). */
typedef struct {
    int by_space;                        /* 1: trim whitespace, 0: trim the set below */
    const unsigned char *set;            /* char set bytes (used when by_space == 0) */
    size_t set_len;
} trim_sel;

UTF8_HOT int trim_should_drop(uint32_t cp, const trim_sel *sel) {
    if (sel->by_space) return utf8_is_space(cp);
    return cp_in_set(cp, sel->set, sel->set_len);
}

/* The kept byte range, returned by value: SysV passes a 16-byte struct in RDX:RAX,
 * so this needs no out-pointers -- and out-pointers would make push_trimmed's locals
 * address-taken, which in turn gives the inlined entry point a stack canary. */
typedef struct { size_t start, len; } trim_span;

/*
 * Compute the kept byte range over s[0..len), honouring mode and `sel`.
 *   mode < 0: left only; mode > 0: right only; mode == 0: both.
 *
 * Robustness notes (the reason this is written with an exclusive cursor):
 *   * Every multibyte step is length-checked against the buffer before it is decoded,
 *     and is proved canonical (utf8_canon) before it is consumed, so
 *     truncated, overlong and outright invalid UTF-8 is left in place and nothing is
 *     ever read out of bounds.
 *   * Right-trim walks back to each trailing code point's lead byte -- at most three
 *     continuation bytes -- and requires the sequence to end exactly at the cursor, so
 *     it can never underflow a size_t or cross the left boundary.
 *   * Only the right scan needs the BEL guard. The left scan stops at the first ESC it
 *     meets, so by construction no ESC remains in [start, cursor) and no escape can
 *     still be open there.
 */
static trim_span trim_bounds(const unsigned char *s, size_t len, int mode, const trim_sel *sel) {
    size_t start = 0;
    size_t stop  = len;
    const int by_space = sel->by_space;

    if (len == 0) return (trim_span){ 0, 0 };

    /* Leading drop: applied for ltrim (mode < 0) and trim (mode == 0). */
    if (mode <= 0) {
        for (;;) {
            /* Hot path: a leading run of plain spaces, peeled without re-testing mode. */
            if (by_space) while (start < len && s[start] == 0x20) start++;
            if (start >= len) break;
            {
                unsigned char c = s[start];
                int sl;
                uint32_t cp;
                if (c < 0x80) {
                    if (by_space) { if (ascii_class(c) == 0) break; }
                    else if (!cp_in_set(c, sel->set, sel->set_len)) break;
                    start++;
                    continue;
                }
                sl = utf8_seq_len(c);
                if (start + (size_t)sl > len) break;    /* truncated by the buffer */
                cp = utf8_decode(s + start, sl);
                if (!trim_should_drop(cp, sel)) break;  /* CJK body text exits here, unvalidated */
                if (!utf8_canon(s + start, sl)) break;  /* overlong / invalid: opaque, keep it */
                start += (size_t)sl;
            }
        }
        if (start >= len) return (trim_span){ 0, 0 };   /* everything dropped */
    }

    /* Trailing drop: applied for rtrim (mode > 0) and trim (mode == 0). */
    if (mode >= 0) {
        size_t pos = stop;                         /* exclusive end of the kept region */
        size_t esc_hint = len;                     /* "not searched yet"; see bel_classify */
        for (;;) {
            /* Hot path: the trailing space run every padded grid cell ends with. */
            if (by_space) while (pos > start && s[pos - 1] == 0x20) pos--;
            if (pos <= start) break;
            {
                unsigned char c = s[pos - 1];
                size_t p;
                int sl, k, back = 0;
                uint32_t cp;
                if (c < 0x80) {
                    if (by_space) {
                        k = ascii_class(c);
                        if (k == 0) break;
                        if (k == 2) {                      /* BEL: only if it closes an open escape */
                            esc_hint = bel_classify(s, start, pos - 1, len, esc_hint);
                            if (esc_hint == BEL_TERMINATES) break;
                        }
                    } else if (!cp_in_set(c, sel->set, sel->set_len)) break;
                    pos--;
                    continue;
                }
                p = pos - 1;
                while (back < 3 && p > start && (s[p] & 0xC0) == 0x80) { p--; back++; }
                sl = utf8_seq_len(s[p]);
                if ((size_t)sl != pos - p) break;       /* not a clean sequence ending at pos */
                cp = utf8_decode(s + p, sl);
                if (!trim_should_drop(cp, sel)) break;  /* CJK body text exits here, unvalidated */
                if (!utf8_canon(s + p, sl)) break;  /* overlong / invalid: opaque, keep it */
                pos = p;                           /* drop the whole code point */
            }
        }
        stop = pos;
    }

    return (trim_span){ start, (stop > start) ? (stop - start) : 0 };
}

/*
 * Return the trimmed view as a Lua string.
 *
 * Fast path: when nothing is trimmed (start==0 and the whole input is kept), reuse
 * the argument via lua_pushvalue -- this skips the lua_pushlstring hash+intern, which
 * dominates the cost of a no-op trim (the common case for hot "trim then use" call
 * sites). The lua_type guard is belt-and-braces: luaL_checklstring on a number
 * converts slot 1 to its string form in place, so by this point slot 1 is a string
 * for both string and number arguments, and pushing it back is correct either way.
 * A non-string/non-number argument never gets here -- luaL_checklstring raises.
 */
static int push_trimmed(lua_State *L, const char *s, size_t len, int mode, const trim_sel *sel) {
    trim_span r = trim_bounds((const unsigned char *)s, len, mode, sel);
    if (r.start == 0 && r.len == len && lua_type(L, 1) == LUA_TSTRING) {
        lua_pushvalue(L, 1);                            /* already trimmed: same interned string, zero copy */
        return 1;
    }
    lua_pushlstring(L, s + r.start, r.len);             /* copied by Lua; no extra heap on our side */
    return 1;
}

/* Whitespace selector as a file-scope constant: a local `trim_sel` whose address is
 * taken would make GCC's default -fstack-protector-strong give this entry point a
 * stack canary and a frame, and trim_space is ~90% of the trim call sites. */
static const trim_sel SPACE_SEL = { 1, NULL, 0 };

/* utf8.trim_space(s [, mode]) -- trim whitespace. */
int luautf8_trim_space(lua_State *L) {
    size_t len;
    const char *s = luaL_checklstring(L, 1, &len);     /* accepts strings containing '\0' */
    int mode = (int)luaL_optinteger(L, 2, 0);         /* <0 ltrim, >0 rtrim, 0/absent both */
    return push_trimmed(L, s, len, mode, &SPACE_SEL);
}

/* utf8.trim_chars(s, chars [, mode]) -- trim code points that appear in `chars`. */
int luautf8_trim_chars(lua_State *L) {
    size_t len, clen;
    const char *s = luaL_checklstring(L, 1, &len);     /* subject, may contain '\0' */
    const char *chars = luaL_checklstring(L, 2, &clen);/* trim set (one or more code points) */
    int mode = (int)luaL_optinteger(L, 3, 0);         /* <0 ltrim, >0 rtrim, 0/absent both */
    trim_sel sel;
    sel.by_space = 0; sel.set = (const unsigned char *)chars; sel.set_len = clen;
    return push_trimmed(L, s, len, mode, &sel);
}

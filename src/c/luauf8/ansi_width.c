/*
 * ansi_width.c -- utf8.ansi_width and utf8.ansi_cut, the display-width engine behind
 * lib/misc.lua's string.wcwidth / string.ansi_cut. Compiled into the same LuaJIT "utf8"
 * module as lutf8lib.c, which owns luaopen_utf8 and the luaL_Reg table and registers
 *   { "ansi_width", luautf8_ansi_width }   { "ansi_cut", luautf8_ansi_cut }
 * so both keep external linkage and the exact lua_CFunction prototype.
 *
 * Width model. Every rule below was read off a real cursor: legacy conhost and Windows
 * Terminal via CONOUT$ cursor readback, xterm via ESC[6n (CPR) on a raw pty, and glibc via
 * wcwidth() over the whole code point space. Results, and the places where this code
 * deliberately does NOT follow a terminal, are recorded in luautf8.txt section 2.7.
 *
 *   - The string is replayed the way a cursor would replay it: `col` is the cursor
 *     column and `line_w` the widest column it reached on the current line. TAB advances
 *     to the next 8-column stop. CR and BS move `col` back without lowering `line_w`, so
 *     overstriking does not lose the width that was already drawn. LF closes the line and
 *     promotes it if it beat the best so far, which is what makes the result the widest
 *     LINE rather than the sum of the lines.
 *   - A VT/ANSI control sequence counts 0 and is skipped whole. The string forms
 *     (OSC/DCS/SOS/PM/APC) end at BEL or ST, and are abandoned at a new ESC, CAN or
 *     SUB -- measured, and it is what keeps an unterminated OSC from eating a string
 *     that goes on to contain more escapes. SS2/SS3 (ESC N, ESC O) consume only the
 *     introducer: both consoles then print the following graphic byte, so it counts 1.
 *   - TAB is the only C0 control that advances the cursor; the rest of C0, DEL and the
 *     C1 range count 0.
 *   - Malformed UTF-8 counts one column per byte (what a terminal shows as U+FFFD) and
 *     advances a single byte, so illegal bytes can never smuggle in a width class.
 *   - Code point widths come from ansi_width_tables.h, generated from Unicode 15:
 *     Mn/Me/Cf -> 0, EastAsianWidth W/F -> 2, everything else, including EAW=A, -> 1,
 *     plus three measured supplements the generator applies: the Cf characters terminals
 *     still draw (soft hyphen, the Prepended_Concatenation_Marks) at 1, conjoining Hangul
 *     jamo at 0, and the Yijing hexagrams at 2. Mc spacing marks such as U+09BE therefore
 *     count 1, which lutf8lib.c's utf8.width gets wrong.
 *   - There is no grapheme clustering: measured, conhost and xterm lay out one code point
 *     at a time, while Windows Terminal collapses an emoji ZWJ sequence and a
 *     regional-indicator pair into a single cell. Per-code-point matches the majority of
 *     the terminals in scope, and it is what a fixed grid of cells needs.
 *
 * utf8.ansi_width(s) returns (width, bytes): the display columns of the widest line, and
 * the byte length OF THAT SAME LINE, counted per line exactly the way the width is -- so
 * for a single-line string bytes is simply its length, and for a multi-line one it is not
 * the sum. A tie goes to the first line that reached the maximum. The two disagree in
 * both directions: an escape sequence or a combining mark adds bytes and no columns, a
 * TAB adds up to 8 columns for one byte. LF is the only line separator; CR folds the
 * cursor back inside the line, so its byte still belongs to it. Never allocates.
 *
 * utf8.ansi_cut(s[,maxlen]) returns (byte_len, print_len, cut) and is only ever called on a
 * single-line string.
 *
 * The width tables are GENERATED (gen_ansi_tables.py); do not edit them by hand.
 */

#include <lua.h>
#include <lauxlib.h>
#include <stdint.h>
#include <string.h>
#include "ansi_width_tables.h"

/* Width of one code point. utf8_decode guarantees cp <= 0x10FFFF, so hi <= 0x10FF and
 * both block tables are in range with no bounds test. A block whose 256 code points all
 * agree -- ASCII, CJK, Hangul, the whole of most scripts -- costs one load; only a mixed
 * block scans intervals, and it starts at the first one that can overlap it. */
static inline unsigned cp_width(uint32_t cp) {
    uint32_t hi = cp >> 8;
    int8_t bw = ansi_blk_w[hi];
    if (bw >= 0) return (unsigned)bw;
    unsigned cw = 1;                               /* not listed -> width 1 */
    uint32_t k;
    for (k = ansi_blk_iv[hi]; k < ANSI_NWIV; k++) {
        if (ansi_wiv[k].first > cp) break;         /* passed cp -> not present */
        if (cp <= ansi_wiv[k].last) { cw = ansi_wiv[k].w; break; }
    }
    return cw;
}

/* Decode the UTF-8 sequence at s (rem = bytes available). Returns its length, or 0 when
 * the bytes are not well formed. The 2-byte form is fenced by its lead range C2..DF, which
 * excludes continuations and the C0/C1 overlong leads at once; the 3- and 4-byte forms are
 * decoded first and then rejected by code point range -- overlong, surrogate, past
 * U+10FFFF -- which is Unicode's Table 3-12 rule and keeps those paths in registers, with
 * no lookup table in the dependency chain. Rejecting is what lets cp_width() skip its
 * bounds check. */
static inline size_t utf8_decode(const unsigned char *s, size_t rem, uint32_t *cp) {
    unsigned c = *s, b1, b2, v;
    if (c < 0xE0) {                                  /* 2 bytes: C2..DF */
        if (c < 0xC2 || rem < 2 || ((b1 = s[1]) & 0xC0) != 0x80) return 0;
        *cp = ((c & 0x1Fu) << 6) | (b1 & 0x3Fu);     /* >= 0x80 by construction: never overlong */
        return 2;
    }
    if (c < 0xF0) {                                  /* 3 bytes: E0..EF, the CJK workhorse */
        if (rem < 3 || ((b1 = s[1]) & 0xC0) != 0x80 || ((b2 = s[2]) & 0xC0) != 0x80) return 0;
        v = ((c & 0x0Fu) << 12) | ((b1 & 0x3Fu) << 6) | (b2 & 0x3Fu);
        if (v < 0x800u || v - 0xD800u < 0x800u) return 0;   /* overlong, or a surrogate */
        *cp = v; return 3;
    }
    if (c <= 0xF4) {                                 /* 4 bytes: F0..F4 */
        if (rem < 4 || ((b1 = s[1]) & 0xC0) != 0x80 || ((b2 = s[2]) & 0xC0) != 0x80
                  || (s[3] & 0xC0) != 0x80) return 0;
        v = ((c & 0x07u) << 18) | ((b1 & 0x3Fu) << 12) | ((b2 & 0x3Fu) << 6) | (s[3] & 0x3Fu);
        if (v < 0x10000u || v > 0x10FFFFu) return 0; /* overlong, or past the last code point */
        *cp = v; return 4;
    }
    return 0;                                        /* 0x80..0xBF continuations, 0xF5..0xFF */
}

/* Byte index just past the control sequence whose ESC sits at s[i] (0-based), clamped to n. */
static size_t esc_end(const unsigned char *s, size_t n, size_t i) {
    if (i + 1 >= n) return i + 1;                  /* lone ESC at end of string */
    unsigned char c = s[i + 1];
    size_t j = i + 2;                              /* first byte after the introducer */
    if (c == 0x5B) {                               /* CSI: ESC [ <params 0x30-0x3F> <inter 0x20-0x2F> <final 0x40-0x7E> */
        while (j < n && s[j] >= 0x30 && s[j] <= 0x3F) j++;
        while (j < n && s[j] >= 0x20 && s[j] <= 0x2F) j++;
        if (j < n && s[j] >= 0x40 && s[j] <= 0x7E) j++;
        return j;
    }
    if (c == 0x5D || c == 0x50 || c == 0x58 || c == 0x5E || c == 0x5F) {  /* OSC DCS SOS PM APC */
        while (j < n) {
            unsigned char d = s[j];
            if (d == 0x07) return j + 1;           /* BEL terminates, inclusive */
            if (d == 0x1B)                         /* ST terminates; a different ESC abandons */
                return (j + 1 < n && s[j + 1] == 0x5C) ? j + 2 : j;
            if (d == 0x18 || d == 0x1A) return j;  /* CAN / SUB abort back to ground */
            j++;
        }
        return j;                                  /* unterminated: runs to the end */
    }
    if (c >= 0x20 && c <= 0x2F) {                  /* nF: intermediates then a final byte */
        while (j < n && s[j] >= 0x20 && s[j] <= 0x2F) j++;
        if (j < n && s[j] >= 0x30 && s[j] <= 0x7E) j++;
        return j;
    }
    if (c >= 0x30 && c <= 0x7E) return i + 2;      /* Fe, and SS2/SS3: introducer only */
    return i + 1;                                  /* ESC + anything else: only the ESC */
}

/*
 * Replay s[0..n) as a cursor and return the widest line it touches.
 *   check_lim: stop before `col` would pass the column budget `lim`.
 *   trunc:     also stop at a newline (ansi_cut measures one line at a time).
 * Both are passed as literals (0,0) at the ansi_width call site, so the compiler folds
 * them away and emits a lean measure-everything loop with no budget or newline test;
 * ansi_cut passes them at run time. Printable-ASCII runs -- the dominant case in terminal
 * text -- are swallowed by a tight inner loop instead of one full iteration per byte.
 *
 * The width is kept per line, in `line_w`, and promoted at each LF and at loop exit, so
 * the byte span of the promoted line (`i - line_start`) is the byte length of the very
 * line the width came from. Taking the maximum per line and then over lines is the same
 * maximum as taking it over every position, so the returned width is unchanged; the
 * per-line form is what makes the byte count attributable to a line at all.
 *
 * *out_i (optional) receives the 0-based stop index, == n when everything was consumed.
 * *out_bytes (optional) receives that line's byte length. When the walk stops early -- a
 * budget, or trunc at a newline -- the line in progress is promoted with the bytes it did
 * consume, which is the only answer available for a line that was never finished.
 */
static inline size_t walk(const unsigned char *s, size_t n, size_t lim,
                          const int check_lim, const int trunc,
                          size_t *out_i, size_t *out_bytes) {
    size_t col = 0, maxw = 0, i = 0;
    size_t line_start = 0, line_w = 0, maxb = 0;
    int best = 0;                                    /* has any line been promoted yet? */
    while (i < n) {
        unsigned c = s[i];
        size_t cw, ni;
        if (c < 0x80) {
            if (c >= 0x20 && c != 0x7F) {              /* printable ASCII: the dominant case */
                if (!check_lim) {                      /* no budget -> take the whole run */
                    size_t j = i + 1;
                    while (j < n && (unsigned char)s[j] >= 0x20 && s[j] < 0x7F) j++;
                    col += j - i; i = j;
                    if (col > line_w) line_w = col;
                    continue;
                }
                cw = 1; ni = i + 1;                    /* budget -> one column at a time */
            }
            else if (c == 0x1B) { cw = 0; ni = esc_end(s, n, i); }   /* escape: skip it whole */
            else if (c == 0x09) { cw = 8 - (col & 7); ni = i + 1; }  /* TAB: next 8-column stop */
            else if (c == 0x0A || c == 0x0D || c == 0x08) {          /* LF / CR / BS */
                /* col folds back but line_w keeps what was already drawn, so overstriking
                 * costs nothing here */
                if (c == 0x0A) {
                    if (trunc) break;
                    /* the first line always wins its own promotion: a line of width 0 -- all
                     * escapes, all invisible -- would otherwise never beat the initial maxw and
                     * would report 0 bytes for a line that does have them */
                    if (!best || line_w > maxw) { best = 1; maxw = line_w; maxb = i - line_start; }
                    line_start = i + 1; line_w = 0; col = 0;   /* close the line, open the next */
                }
                else col = (c == 0x08 && col) ? col - 1 : 0;
                i++; continue;
            }
            else { cw = 0; ni = i + 1; }               /* the rest of C0, and DEL */
        } else {
            uint32_t cp;
            size_t L = utf8_decode(s + i, n - i, &cp);
            if (L == 0) { cw = 1; ni = i + 1; }        /* malformed byte: one replacement column */
            else        { cw = cp_width(cp); ni = i + L; }
        }
        if (check_lim && col + cw > lim) break;        /* budget exceeded: stop before adding */
        col += cw; i = ni;
        if (col > line_w) line_w = col;
    }
    if (!best || line_w > maxw) { maxw = line_w; maxb = i - line_start; }  /* line in progress */
    if (out_i) *out_i = i;
    if (out_bytes) *out_bytes = maxb;
    return maxw;
}

/* Coerce argument 1 to a string exactly like string.wcwidth: numbers take their string
 * form (luaL_checklstring), anything else goes through tostring(x). */
static const char *coerce_str(lua_State *L, size_t *len) {
    int t = lua_type(L, 1);
    if (t != LUA_TSTRING && t != LUA_TNUMBER) {
        lua_getglobal(L, "tostring");
        lua_pushvalue(L, 1);
        lua_call(L, 1, 1);
        lua_replace(L, 1);
    }
    return luaL_checklstring(L, 1, len);
}

/* Return the whole argument string with NO copy/intern when it is already a Lua string
 * (the interned object is reused, matching string.ansi_cut which returns `s` itself);
 * otherwise materialise it (e.g. a coerced number, whose slot is not a string). */
static void push_whole(lua_State *L, const char *s, size_t len) {
    if (lua_type(L, 1) == LUA_TSTRING) lua_pushvalue(L, 1);
    else lua_pushlstring(L, s, len);
}

/* utf8.ansi_width(s) -> display columns of the widest line, and that line's byte length. */
int luautf8_ansi_width(lua_State *L) {
    size_t len, bytes;
    const char *s;
    int t = lua_type(L, 1);
    if (t == LUA_TSTRING) {                         /* hot path: already a string, no coercion */
        s = lua_tolstring(L, 1, &len);
    } else if (t == LUA_TNIL || t == LUA_TNONE) {   /* nil/absent -> 0, 0, like string.wcwidth */
        lua_pushinteger(L, 0); lua_pushinteger(L, 0); return 2;
    } else {
        s = coerce_str(L, &len);                    /* number -> its string form; else tostring(x) */
    }
    lua_pushinteger(L, (lua_Integer)walk((const unsigned char *)s, len, 0, 0, 0, NULL, &bytes));
    lua_pushinteger(L, (lua_Integer)bytes);
    return 2;
}

/* utf8.ansi_cut(s[, maxlen]) -> byte_len, print_len, cut  (drop-in for string.ansi_cut). */
int luautf8_ansi_cut(lua_State *L) {
    size_t len, i, cutlen;
    const char *s;
    lua_Integer maxlen;
    int trunc, has_esc;
    size_t w;

    if (lua_isnoneornil(L, 1)) { lua_pushnil(L); return 1; }   /* string.ansi_cut(nil) returns one nil */
    s = luaL_checklstring(L, 1, &len);             /* numbers coerce; matches string.ansi_cut for strings */
    maxlen = luaL_optinteger(L, 2, -1);            /* absent -> no truncation */

    if (len == 0) {                                /* s == "" -> 0, 0, s */
        lua_pushinteger(L, 0); lua_pushinteger(L, 0); push_whole(L, s, 0); return 3;
    }
    if (maxlen == 0) {                             /* -> 0, 0, '' */
        lua_pushinteger(L, 0); lua_pushinteger(L, 0); lua_pushliteral(L, ""); return 3;
    }

    trunc = (maxlen > 0);
    w = walk((const unsigned char *)s, len, trunc ? (size_t)maxlen : 0, trunc, trunc, &i, NULL);

    if (i >= len) {                                /* consumed the whole string */
        lua_pushinteger(L, (lua_Integer)len); lua_pushinteger(L, (lua_Integer)w);
        push_whole(L, s, len); return 3;
    }
    if ((unsigned char)s[i] == 0x0A) {             /* stopped at a newline with room to spare */
        size_t full = walk((const unsigned char *)s, len, 0, 0, 0, NULL, NULL);
        if ((lua_Integer)full <= maxlen) {
            lua_pushinteger(L, (lua_Integer)len); lua_pushinteger(L, (lua_Integer)full);
            push_whole(L, s, len); return 3;
        }
    }

    cutlen = i;                                    /* bytes kept = stop index (i>0 <=> Lua i>1) */
    has_esc = (memchr(s, 0x1B, cutlen) != NULL);
    lua_pushinteger(L, (lua_Integer)(cutlen + (has_esc ? 4 : 0)));   /* byte_len of the final cut */
    lua_pushinteger(L, (lua_Integer)w);                              /* print_len */
    if (has_esc) {                                 /* re-append a reset, as jline's toAnsi() does */
        luaL_Buffer b;
        luaL_buffinit(L, &b);
        luaL_addlstring(&b, s, cutlen);
        luaL_addlstring(&b, "\033[0m", 4);
        luaL_pushresult(&b);
    } else {
        lua_pushlstring(L, s, cutlen);
    }
    return 3;
}

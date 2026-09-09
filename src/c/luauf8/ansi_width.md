# ansi_width.c — terminal display width model and measured width tables

> This document describes the width model in `src/c/luauf8/ansi_width.c`, the `(columns, bytes)`
> two-value contract, and the width tables for every class of character a terminal can be handed.
>
> Every table is **measured** straight out of the shipped artifact `lib/x64/utf8.dll` — not a width
> table from anyone's memory (including whoever wrote the code). Where a reading and a prose
> explanation conflict, trust the code and the measurements here, and fix the prose.
>
> The design decisions below carry the reading that produced them, because the verdicts came off real
> cursors rather than out of a table: §1.1 lists the witnesses.


## 1. The width model: a cursor replay

`walk()` (`ansi_width.c:157-208`) replays the string the way a terminal cursor replays it:

- `col` is the cursor column; `line_w` is the widest column the cursor reached **on the current line**;
- an LF settles the line: if it beats what is recorded, `line_w` is promoted to `maxw` and the line's
  byte span to `maxb`; then both counters reset and the next line opens;
- the loop exit settles "the line still in progress" (`ansi_width.c:204`);
- the return value is `(maxw, maxb)`.

Because the maximum over lines of each line's own maximum IS the global maximum, switching to
per-line accounting left the width **bit-identical to the single high-water-mark counter it
replaced** — all that changed is that the byte count can now be attributed to a specific line.

### 1.1 The order in which a code point is decided

`cp_width()` (`ansi_width.c:63-74`) reads the generated `ansi_width_tables.h` (478 intervals plus a
4352-entry per-256-code-point block map, Unicode 15.0.0). The order matters:

| Step | Test | Result |
|---|---|---|
| 1 | `Mn` / `Me` / `Cf` | 0 (must come before EAW: U+3099 and U+302A are Mn **and** W) |
| 2 | `Cc`, DEL, NUL | 0 |
| 3 | EastAsianWidth `W` or `F` | 2 |
| 4 | undesignated code points inside the CJK ideograph blocks and Planes 2/3 | 2 (the UAX #11 default) |
| 5 | everything else, including EAW=`A` | 1 (ambiguous width gets no opt-in; narrow is the shipping default of every terminal in scope) |

Three **measured supplements** cover the code points where Unicode's properties and what a terminal
actually draws disagree: `DRAWN_CF`→1 (SOFT HYPHEN plus the 13 Prepended_Concatenation_Marks),
`JAMO_ZERO`→0 (conjoining Hangul jamo), `Yijing`→2 (U+4DC0..U+4DFF).

Each is a reading off a real cursor, taken from four witnesses: **conhost** and **Windows Terminal**
(`CreateFileW("CONOUT$")` + `WriteConsoleW`, then `GetConsoleScreenBufferInfo` to read the cursor
column back), **xterm** (raw bytes to `/dev/tty` in termios raw mode, position reported back with
`ESC[6n`), **glibc** (`wcwidth()` over all code points, C.UTF-8), and **`unidata.h`** (this module's
own second width table). Two caveats shaped the verdicts: `WriteConsoleW` takes UTF-16, so the Windows
probes cannot test raw malformed bytes at all — only the xterm pty is valid at byte level; and xterm
mirrors glibc's `wcwidth()` for every assigned code point, so the two are **one** witness, not two.

### 1.2 Escapes, control characters and malformed UTF-8

- A VT/ANSI control sequence is skipped whole and counts 0: CSI (params 0x30-0x3F, intermediates
  0x20-0x2F, final 0x40-0x7E), the string forms OSC/DCS/SOS/PM/APC, nF, the Fe two-byte forms, SS2/SS3.
- **SS2/SS3 (`ESC N` / `ESC O`) consume only their introducer**: both consoles print the graphic byte
  that follows, so it counts 1.
- A string form is terminated only by **BEL or ST**, and abandoned by a **new ESC, CAN (0x18) or
  SUB (0x1A)**; **neither CR nor LF terminates one** — the newline is swallowed as sequence content
  (§4.5 has the measured rows).
- TAB advances to the **next 8-column stop**, it is not one column (§4.4).
- Every other C0 control, DEL and the whole of C1 count 0; a lone ESC counts 0.
- CR / BS fold `col` back **without lowering `line_w`**, so overstriking does not lose width that was
  already drawn.
- UTF-8 is **validated**, not merely decoded: overlong forms, surrogates, anything past U+10FFFF, lone
  continuation bytes and truncated sequences are all rejected; a rejected byte costs exactly
  **1 column and advances 1 byte**, which is Unicode's maximal-subpart rule (what the terminal shows as
  U+FFFD). A malformed byte therefore cannot smuggle in a width class.

## 2. The `(columns, bytes)` contract

`utf8.ansi_width(s)` returns two numbers:

1. the **display columns of the widest line**;
2. the **byte length of that SAME line** — not of the whole string, and not the sum over lines. The
   byte count obeys exactly the same widest-line rule as the width, and **a tie goes to the first line
   that reached the maximum**.

- LF is the only line separator. CR only folds the cursor back, its byte still belongs to the line:
  `"abc\r\n"` is one line of 4 bytes and 3 columns.
- Neither number bounds the other, and they disagree in both directions: escapes, combining marks and
  every other zero-width byte **add bytes and no columns**, while a single TAB byte is **worth up to 8
  columns**.
- The **first line is promoted unconditionally** (the `best` flag, `ansi_width.c:187`). A line of width
  0 — all escapes, all invisible — can never pass a `line_w > maxw` test against an initial `maxw`
  of 0, so without the flag it would report 0 columns (right) and 0 bytes (wrong): `ESC ] 0 ; x` is
  0 columns **5** bytes.
- nil/absent → `ansi_width` returns `0, 0`; `ansi_cut` returns `nil` (the original Lua semantics).
- At the Lua layer `lib/misc.lua` exposes both functions as `string.wcwidth` and `string.ansi_cut`;
  the wrapper is a plain `return ansi_width(s)`, so both returns are visible there as well, and
  `ansi_width(s) == 3` or `local w = ansi_width(s)` still read the columns only — Lua expands a
  multi-value call into several values only in trailing position.

### 2.1 Width distribution over the full sweep

| width | code points | runs | what lands in this class |
|---|---|---|---|
| 0 | 2450 | 358 | Mn/Me/Cf combining and format characters, C0 (TAB excepted), DEL, C1, conjoining Hangul jamo |
| 1 | 929088 | 471 | the default: everything else, including EastAsianWidth=A |
| 2 | 182573 | 121 | EastAsianWidth W/F, undesignated code points inside the CJK ideograph blocks, Yijing U+4DC0..4DFF |
| 8 | 1 | 1 | the reading of a lone TAB in the single-code-point sweep -- see the note below, TAB is not a fixed width |

> The TAB row is an artifact of the **single-code-point** sweep: `ansi_width` starts at col=0, so a lone TAB reads 8. In a real string the width of a TAB depends on which stop it hits -- anything from `1..8` is possible (§4.4).

An earlier sweep reported 953 run-length lines and `other=2049` where this section says 951. It **fed
the 2048 surrogate code points in as their 3-byte CESU form**; all of them are rejected and each reads 3,
which adds one `w3=2048` run. This document skips the surrogate range. Both policies, measured:

| policy | code points | runs | histogram |
|---|---|---|---|
| skip U+D800..DFFF (this document, §4) | 1,112,064 | 951 | 0=2450 / 1=927040 / 2=182573 / 8=1 |
| feed the surrogate range as its 3-byte CESU form | 1,114,112 | 953 | 0=2450 / 1=927040 / 2=182573 / 3=2048 / 8=1 |

The two agree on everything except the surrogate run, and the `0/1/2` histogram counts match to the digit.

## 3. How this relates to `utf8.width` (`unidata.h`)

The module ships two width tables: `utf8.ansi_width` (documented here, measured) and `utf8.width`
(`lutf8lib.c` plus a frozen `unidata.h`). They disagree on 4518 of 1,112,059 code points, in four
buckets, and **every bucket is `unidata.h`'s error**: 3905 Mc spacing marks judged 0 (measured 1), 311
C0/C1 controls and conjoining jamo judged 1, 296 trigram/Tai-Xuan-Jing and coarse-range holes judged 2,
and 6 code points judged 0 where EAW says W. On top of that `utf8.width` takes a **code point integer**,
so passing it a string silently yields garbage (`Lutf8_width` reads `lua_tointeger`).
The buckets above are the whole disagreement set; new code should use `ansi_width`.

## 4. Character width tables (all measured)

### 4.1 Code point intervals of width 0 (358 runs, complete)

Width 1 is the default, so only the **non-1** intervals are listed; the table below is every run that
resolves to 0.

| code points | from | to | width |
|---|---|---|---|
| 9 | `U+0000` | `U+0008` | 0 |
| 22 | `U+000A` | `U+001F` | 0 |
| 33 | `U+007F` | `U+009F` | 0 |
| 112 | `U+0300` | `U+036F` | 0 |
| 7 | `U+0483` | `U+0489` | 0 |
| 45 | `U+0591` | `U+05BD` | 0 |
| 1 | `U+05BF` | `U+05BF` | 0 |
| 2 | `U+05C1` | `U+05C2` | 0 |
| 2 | `U+05C4` | `U+05C5` | 0 |
| 1 | `U+05C7` | `U+05C7` | 0 |
| 11 | `U+0610` | `U+061A` | 0 |
| 1 | `U+061C` | `U+061C` | 0 |
| 21 | `U+064B` | `U+065F` | 0 |
| 1 | `U+0670` | `U+0670` | 0 |
| 7 | `U+06D6` | `U+06DC` | 0 |
| 6 | `U+06DF` | `U+06E4` | 0 |
| 2 | `U+06E7` | `U+06E8` | 0 |
| 4 | `U+06EA` | `U+06ED` | 0 |
| 1 | `U+0711` | `U+0711` | 0 |
| 27 | `U+0730` | `U+074A` | 0 |
| 11 | `U+07A6` | `U+07B0` | 0 |
| 9 | `U+07EB` | `U+07F3` | 0 |
| 1 | `U+07FD` | `U+07FD` | 0 |
| 4 | `U+0816` | `U+0819` | 0 |
| 9 | `U+081B` | `U+0823` | 0 |
| 3 | `U+0825` | `U+0827` | 0 |
| 5 | `U+0829` | `U+082D` | 0 |
| 3 | `U+0859` | `U+085B` | 0 |
| 8 | `U+0898` | `U+089F` | 0 |
| 24 | `U+08CA` | `U+08E1` | 0 |
| 32 | `U+08E3` | `U+0902` | 0 |
| 1 | `U+093A` | `U+093A` | 0 |
| 1 | `U+093C` | `U+093C` | 0 |
| 8 | `U+0941` | `U+0948` | 0 |
| 1 | `U+094D` | `U+094D` | 0 |
| 7 | `U+0951` | `U+0957` | 0 |
| 2 | `U+0962` | `U+0963` | 0 |
| 1 | `U+0981` | `U+0981` | 0 |
| 1 | `U+09BC` | `U+09BC` | 0 |
| 4 | `U+09C1` | `U+09C4` | 0 |
| 1 | `U+09CD` | `U+09CD` | 0 |
| 2 | `U+09E2` | `U+09E3` | 0 |
| 1 | `U+09FE` | `U+09FE` | 0 |
| 2 | `U+0A01` | `U+0A02` | 0 |
| 1 | `U+0A3C` | `U+0A3C` | 0 |
| 2 | `U+0A41` | `U+0A42` | 0 |
| 2 | `U+0A47` | `U+0A48` | 0 |
| 3 | `U+0A4B` | `U+0A4D` | 0 |
| 1 | `U+0A51` | `U+0A51` | 0 |
| 2 | `U+0A70` | `U+0A71` | 0 |
| 1 | `U+0A75` | `U+0A75` | 0 |
| 2 | `U+0A81` | `U+0A82` | 0 |
| 1 | `U+0ABC` | `U+0ABC` | 0 |
| 5 | `U+0AC1` | `U+0AC5` | 0 |
| 2 | `U+0AC7` | `U+0AC8` | 0 |
| 1 | `U+0ACD` | `U+0ACD` | 0 |
| 2 | `U+0AE2` | `U+0AE3` | 0 |
| 6 | `U+0AFA` | `U+0AFF` | 0 |
| 1 | `U+0B01` | `U+0B01` | 0 |
| 1 | `U+0B3C` | `U+0B3C` | 0 |
| 1 | `U+0B3F` | `U+0B3F` | 0 |
| 4 | `U+0B41` | `U+0B44` | 0 |
| 1 | `U+0B4D` | `U+0B4D` | 0 |
| 2 | `U+0B55` | `U+0B56` | 0 |
| 2 | `U+0B62` | `U+0B63` | 0 |
| 1 | `U+0B82` | `U+0B82` | 0 |
| 1 | `U+0BC0` | `U+0BC0` | 0 |
| 1 | `U+0BCD` | `U+0BCD` | 0 |
| 1 | `U+0C00` | `U+0C00` | 0 |
| 1 | `U+0C04` | `U+0C04` | 0 |
| 1 | `U+0C3C` | `U+0C3C` | 0 |
| 3 | `U+0C3E` | `U+0C40` | 0 |
| 3 | `U+0C46` | `U+0C48` | 0 |
| 4 | `U+0C4A` | `U+0C4D` | 0 |
| 2 | `U+0C55` | `U+0C56` | 0 |
| 2 | `U+0C62` | `U+0C63` | 0 |
| 1 | `U+0C81` | `U+0C81` | 0 |
| 1 | `U+0CBC` | `U+0CBC` | 0 |
| 1 | `U+0CBF` | `U+0CBF` | 0 |
| 1 | `U+0CC6` | `U+0CC6` | 0 |
| 2 | `U+0CCC` | `U+0CCD` | 0 |
| 2 | `U+0CE2` | `U+0CE3` | 0 |
| 2 | `U+0D00` | `U+0D01` | 0 |
| 2 | `U+0D3B` | `U+0D3C` | 0 |
| 4 | `U+0D41` | `U+0D44` | 0 |
| 1 | `U+0D4D` | `U+0D4D` | 0 |
| 2 | `U+0D62` | `U+0D63` | 0 |
| 1 | `U+0D81` | `U+0D81` | 0 |
| 1 | `U+0DCA` | `U+0DCA` | 0 |
| 3 | `U+0DD2` | `U+0DD4` | 0 |
| 1 | `U+0DD6` | `U+0DD6` | 0 |
| 1 | `U+0E31` | `U+0E31` | 0 |
| 7 | `U+0E34` | `U+0E3A` | 0 |
| 8 | `U+0E47` | `U+0E4E` | 0 |
| 1 | `U+0EB1` | `U+0EB1` | 0 |
| 9 | `U+0EB4` | `U+0EBC` | 0 |
| 7 | `U+0EC8` | `U+0ECE` | 0 |
| 2 | `U+0F18` | `U+0F19` | 0 |
| 1 | `U+0F35` | `U+0F35` | 0 |
| 1 | `U+0F37` | `U+0F37` | 0 |
| 1 | `U+0F39` | `U+0F39` | 0 |
| 14 | `U+0F71` | `U+0F7E` | 0 |
| 5 | `U+0F80` | `U+0F84` | 0 |
| 2 | `U+0F86` | `U+0F87` | 0 |
| 11 | `U+0F8D` | `U+0F97` | 0 |
| 36 | `U+0F99` | `U+0FBC` | 0 |
| 1 | `U+0FC6` | `U+0FC6` | 0 |
| 4 | `U+102D` | `U+1030` | 0 |
| 6 | `U+1032` | `U+1037` | 0 |
| 2 | `U+1039` | `U+103A` | 0 |
| 2 | `U+103D` | `U+103E` | 0 |
| 2 | `U+1058` | `U+1059` | 0 |
| 3 | `U+105E` | `U+1060` | 0 |
| 4 | `U+1071` | `U+1074` | 0 |
| 1 | `U+1082` | `U+1082` | 0 |
| 2 | `U+1085` | `U+1086` | 0 |
| 1 | `U+108D` | `U+108D` | 0 |
| 1 | `U+109D` | `U+109D` | 0 |
| 160 | `U+1160` | `U+11FF` | 0 |
| 3 | `U+135D` | `U+135F` | 0 |
| 3 | `U+1712` | `U+1714` | 0 |
| 2 | `U+1732` | `U+1733` | 0 |
| 2 | `U+1752` | `U+1753` | 0 |
| 2 | `U+1772` | `U+1773` | 0 |
| 2 | `U+17B4` | `U+17B5` | 0 |
| 7 | `U+17B7` | `U+17BD` | 0 |
| 1 | `U+17C6` | `U+17C6` | 0 |
| 11 | `U+17C9` | `U+17D3` | 0 |
| 1 | `U+17DD` | `U+17DD` | 0 |
| 5 | `U+180B` | `U+180F` | 0 |
| 2 | `U+1885` | `U+1886` | 0 |
| 1 | `U+18A9` | `U+18A9` | 0 |
| 3 | `U+1920` | `U+1922` | 0 |
| 2 | `U+1927` | `U+1928` | 0 |
| 1 | `U+1932` | `U+1932` | 0 |
| 3 | `U+1939` | `U+193B` | 0 |
| 2 | `U+1A17` | `U+1A18` | 0 |
| 1 | `U+1A1B` | `U+1A1B` | 0 |
| 1 | `U+1A56` | `U+1A56` | 0 |
| 7 | `U+1A58` | `U+1A5E` | 0 |
| 1 | `U+1A60` | `U+1A60` | 0 |
| 1 | `U+1A62` | `U+1A62` | 0 |
| 8 | `U+1A65` | `U+1A6C` | 0 |
| 10 | `U+1A73` | `U+1A7C` | 0 |
| 1 | `U+1A7F` | `U+1A7F` | 0 |
| 31 | `U+1AB0` | `U+1ACE` | 0 |
| 4 | `U+1B00` | `U+1B03` | 0 |
| 1 | `U+1B34` | `U+1B34` | 0 |
| 5 | `U+1B36` | `U+1B3A` | 0 |
| 1 | `U+1B3C` | `U+1B3C` | 0 |
| 1 | `U+1B42` | `U+1B42` | 0 |
| 9 | `U+1B6B` | `U+1B73` | 0 |
| 2 | `U+1B80` | `U+1B81` | 0 |
| 4 | `U+1BA2` | `U+1BA5` | 0 |
| 2 | `U+1BA8` | `U+1BA9` | 0 |
| 3 | `U+1BAB` | `U+1BAD` | 0 |
| 1 | `U+1BE6` | `U+1BE6` | 0 |
| 2 | `U+1BE8` | `U+1BE9` | 0 |
| 1 | `U+1BED` | `U+1BED` | 0 |
| 3 | `U+1BEF` | `U+1BF1` | 0 |
| 8 | `U+1C2C` | `U+1C33` | 0 |
| 2 | `U+1C36` | `U+1C37` | 0 |
| 3 | `U+1CD0` | `U+1CD2` | 0 |
| 13 | `U+1CD4` | `U+1CE0` | 0 |
| 7 | `U+1CE2` | `U+1CE8` | 0 |
| 1 | `U+1CED` | `U+1CED` | 0 |
| 1 | `U+1CF4` | `U+1CF4` | 0 |
| 2 | `U+1CF8` | `U+1CF9` | 0 |
| 64 | `U+1DC0` | `U+1DFF` | 0 |
| 5 | `U+200B` | `U+200F` | 0 |
| 5 | `U+202A` | `U+202E` | 0 |
| 5 | `U+2060` | `U+2064` | 0 |
| 10 | `U+2066` | `U+206F` | 0 |
| 33 | `U+20D0` | `U+20F0` | 0 |
| 3 | `U+2CEF` | `U+2CF1` | 0 |
| 1 | `U+2D7F` | `U+2D7F` | 0 |
| 32 | `U+2DE0` | `U+2DFF` | 0 |
| 4 | `U+302A` | `U+302D` | 0 |
| 2 | `U+3099` | `U+309A` | 0 |
| 4 | `U+A66F` | `U+A672` | 0 |
| 10 | `U+A674` | `U+A67D` | 0 |
| 2 | `U+A69E` | `U+A69F` | 0 |
| 2 | `U+A6F0` | `U+A6F1` | 0 |
| 1 | `U+A802` | `U+A802` | 0 |
| 1 | `U+A806` | `U+A806` | 0 |
| 1 | `U+A80B` | `U+A80B` | 0 |
| 2 | `U+A825` | `U+A826` | 0 |
| 1 | `U+A82C` | `U+A82C` | 0 |
| 2 | `U+A8C4` | `U+A8C5` | 0 |
| 18 | `U+A8E0` | `U+A8F1` | 0 |
| 1 | `U+A8FF` | `U+A8FF` | 0 |
| 8 | `U+A926` | `U+A92D` | 0 |
| 11 | `U+A947` | `U+A951` | 0 |
| 3 | `U+A980` | `U+A982` | 0 |
| 1 | `U+A9B3` | `U+A9B3` | 0 |
| 4 | `U+A9B6` | `U+A9B9` | 0 |
| 2 | `U+A9BC` | `U+A9BD` | 0 |
| 1 | `U+A9E5` | `U+A9E5` | 0 |
| 6 | `U+AA29` | `U+AA2E` | 0 |
| 2 | `U+AA31` | `U+AA32` | 0 |
| 2 | `U+AA35` | `U+AA36` | 0 |
| 1 | `U+AA43` | `U+AA43` | 0 |
| 1 | `U+AA4C` | `U+AA4C` | 0 |
| 1 | `U+AA7C` | `U+AA7C` | 0 |
| 1 | `U+AAB0` | `U+AAB0` | 0 |
| 3 | `U+AAB2` | `U+AAB4` | 0 |
| 2 | `U+AAB7` | `U+AAB8` | 0 |
| 2 | `U+AABE` | `U+AABF` | 0 |
| 1 | `U+AAC1` | `U+AAC1` | 0 |
| 2 | `U+AAEC` | `U+AAED` | 0 |
| 1 | `U+AAF6` | `U+AAF6` | 0 |
| 1 | `U+ABE5` | `U+ABE5` | 0 |
| 1 | `U+ABE8` | `U+ABE8` | 0 |
| 1 | `U+ABED` | `U+ABED` | 0 |
| 23 | `U+D7B0` | `U+D7C6` | 0 |
| 49 | `U+D7CB` | `U+D7FB` | 0 |
| 1 | `U+FB1E` | `U+FB1E` | 0 |
| 16 | `U+FE00` | `U+FE0F` | 0 |
| 16 | `U+FE20` | `U+FE2F` | 0 |
| 1 | `U+FEFF` | `U+FEFF` | 0 |
| 3 | `U+FFF9` | `U+FFFB` | 0 |
| 1 | `U+101FD` | `U+101FD` | 0 |
| 1 | `U+102E0` | `U+102E0` | 0 |
| 5 | `U+10376` | `U+1037A` | 0 |
| 3 | `U+10A01` | `U+10A03` | 0 |
| 2 | `U+10A05` | `U+10A06` | 0 |
| 4 | `U+10A0C` | `U+10A0F` | 0 |
| 3 | `U+10A38` | `U+10A3A` | 0 |
| 1 | `U+10A3F` | `U+10A3F` | 0 |
| 2 | `U+10AE5` | `U+10AE6` | 0 |
| 4 | `U+10D24` | `U+10D27` | 0 |
| 2 | `U+10EAB` | `U+10EAC` | 0 |
| 3 | `U+10EFD` | `U+10EFF` | 0 |
| 11 | `U+10F46` | `U+10F50` | 0 |
| 4 | `U+10F82` | `U+10F85` | 0 |
| 1 | `U+11001` | `U+11001` | 0 |
| 15 | `U+11038` | `U+11046` | 0 |
| 1 | `U+11070` | `U+11070` | 0 |
| 2 | `U+11073` | `U+11074` | 0 |
| 3 | `U+1107F` | `U+11081` | 0 |
| 4 | `U+110B3` | `U+110B6` | 0 |
| 2 | `U+110B9` | `U+110BA` | 0 |
| 1 | `U+110C2` | `U+110C2` | 0 |
| 3 | `U+11100` | `U+11102` | 0 |
| 5 | `U+11127` | `U+1112B` | 0 |
| 8 | `U+1112D` | `U+11134` | 0 |
| 1 | `U+11173` | `U+11173` | 0 |
| 2 | `U+11180` | `U+11181` | 0 |
| 9 | `U+111B6` | `U+111BE` | 0 |
| 4 | `U+111C9` | `U+111CC` | 0 |
| 1 | `U+111CF` | `U+111CF` | 0 |
| 3 | `U+1122F` | `U+11231` | 0 |
| 1 | `U+11234` | `U+11234` | 0 |
| 2 | `U+11236` | `U+11237` | 0 |
| 1 | `U+1123E` | `U+1123E` | 0 |
| 1 | `U+11241` | `U+11241` | 0 |
| 1 | `U+112DF` | `U+112DF` | 0 |
| 8 | `U+112E3` | `U+112EA` | 0 |
| 2 | `U+11300` | `U+11301` | 0 |
| 2 | `U+1133B` | `U+1133C` | 0 |
| 1 | `U+11340` | `U+11340` | 0 |
| 7 | `U+11366` | `U+1136C` | 0 |
| 5 | `U+11370` | `U+11374` | 0 |
| 8 | `U+11438` | `U+1143F` | 0 |
| 3 | `U+11442` | `U+11444` | 0 |
| 1 | `U+11446` | `U+11446` | 0 |
| 1 | `U+1145E` | `U+1145E` | 0 |
| 6 | `U+114B3` | `U+114B8` | 0 |
| 1 | `U+114BA` | `U+114BA` | 0 |
| 2 | `U+114BF` | `U+114C0` | 0 |
| 2 | `U+114C2` | `U+114C3` | 0 |
| 4 | `U+115B2` | `U+115B5` | 0 |
| 2 | `U+115BC` | `U+115BD` | 0 |
| 2 | `U+115BF` | `U+115C0` | 0 |
| 2 | `U+115DC` | `U+115DD` | 0 |
| 8 | `U+11633` | `U+1163A` | 0 |
| 1 | `U+1163D` | `U+1163D` | 0 |
| 2 | `U+1163F` | `U+11640` | 0 |
| 1 | `U+116AB` | `U+116AB` | 0 |
| 1 | `U+116AD` | `U+116AD` | 0 |
| 6 | `U+116B0` | `U+116B5` | 0 |
| 1 | `U+116B7` | `U+116B7` | 0 |
| 3 | `U+1171D` | `U+1171F` | 0 |
| 4 | `U+11722` | `U+11725` | 0 |
| 5 | `U+11727` | `U+1172B` | 0 |
| 9 | `U+1182F` | `U+11837` | 0 |
| 2 | `U+11839` | `U+1183A` | 0 |
| 2 | `U+1193B` | `U+1193C` | 0 |
| 1 | `U+1193E` | `U+1193E` | 0 |
| 1 | `U+11943` | `U+11943` | 0 |
| 4 | `U+119D4` | `U+119D7` | 0 |
| 2 | `U+119DA` | `U+119DB` | 0 |
| 1 | `U+119E0` | `U+119E0` | 0 |
| 10 | `U+11A01` | `U+11A0A` | 0 |
| 6 | `U+11A33` | `U+11A38` | 0 |
| 4 | `U+11A3B` | `U+11A3E` | 0 |
| 1 | `U+11A47` | `U+11A47` | 0 |
| 6 | `U+11A51` | `U+11A56` | 0 |
| 3 | `U+11A59` | `U+11A5B` | 0 |
| 13 | `U+11A8A` | `U+11A96` | 0 |
| 2 | `U+11A98` | `U+11A99` | 0 |
| 7 | `U+11C30` | `U+11C36` | 0 |
| 6 | `U+11C38` | `U+11C3D` | 0 |
| 1 | `U+11C3F` | `U+11C3F` | 0 |
| 22 | `U+11C92` | `U+11CA7` | 0 |
| 7 | `U+11CAA` | `U+11CB0` | 0 |
| 2 | `U+11CB2` | `U+11CB3` | 0 |
| 2 | `U+11CB5` | `U+11CB6` | 0 |
| 6 | `U+11D31` | `U+11D36` | 0 |
| 1 | `U+11D3A` | `U+11D3A` | 0 |
| 2 | `U+11D3C` | `U+11D3D` | 0 |
| 7 | `U+11D3F` | `U+11D45` | 0 |
| 1 | `U+11D47` | `U+11D47` | 0 |
| 2 | `U+11D90` | `U+11D91` | 0 |
| 1 | `U+11D95` | `U+11D95` | 0 |
| 1 | `U+11D97` | `U+11D97` | 0 |
| 2 | `U+11EF3` | `U+11EF4` | 0 |
| 2 | `U+11F00` | `U+11F01` | 0 |
| 5 | `U+11F36` | `U+11F3A` | 0 |
| 1 | `U+11F40` | `U+11F40` | 0 |
| 1 | `U+11F42` | `U+11F42` | 0 |
| 17 | `U+13430` | `U+13440` | 0 |
| 15 | `U+13447` | `U+13455` | 0 |
| 5 | `U+16AF0` | `U+16AF4` | 0 |
| 7 | `U+16B30` | `U+16B36` | 0 |
| 1 | `U+16F4F` | `U+16F4F` | 0 |
| 4 | `U+16F8F` | `U+16F92` | 0 |
| 1 | `U+16FE4` | `U+16FE4` | 0 |
| 2 | `U+1BC9D` | `U+1BC9E` | 0 |
| 4 | `U+1BCA0` | `U+1BCA3` | 0 |
| 46 | `U+1CF00` | `U+1CF2D` | 0 |
| 23 | `U+1CF30` | `U+1CF46` | 0 |
| 3 | `U+1D167` | `U+1D169` | 0 |
| 16 | `U+1D173` | `U+1D182` | 0 |
| 7 | `U+1D185` | `U+1D18B` | 0 |
| 4 | `U+1D1AA` | `U+1D1AD` | 0 |
| 3 | `U+1D242` | `U+1D244` | 0 |
| 55 | `U+1DA00` | `U+1DA36` | 0 |
| 50 | `U+1DA3B` | `U+1DA6C` | 0 |
| 1 | `U+1DA75` | `U+1DA75` | 0 |
| 1 | `U+1DA84` | `U+1DA84` | 0 |
| 5 | `U+1DA9B` | `U+1DA9F` | 0 |
| 15 | `U+1DAA1` | `U+1DAAF` | 0 |
| 7 | `U+1E000` | `U+1E006` | 0 |
| 17 | `U+1E008` | `U+1E018` | 0 |
| 7 | `U+1E01B` | `U+1E021` | 0 |
| 2 | `U+1E023` | `U+1E024` | 0 |
| 5 | `U+1E026` | `U+1E02A` | 0 |
| 1 | `U+1E08F` | `U+1E08F` | 0 |
| 7 | `U+1E130` | `U+1E136` | 0 |
| 1 | `U+1E2AE` | `U+1E2AE` | 0 |
| 4 | `U+1E2EC` | `U+1E2EF` | 0 |
| 4 | `U+1E4EC` | `U+1E4EF` | 0 |
| 7 | `U+1E8D0` | `U+1E8D6` | 0 |
| 7 | `U+1E944` | `U+1E94A` | 0 |
| 1 | `U+E0001` | `U+E0001` | 0 |
| 96 | `U+E0020` | `U+E007F` | 0 |
| 240 | `U+E0100` | `U+E01EF` | 0 |

### 4.2 Code point intervals of width 2 (121 runs, complete)

| code points | from | to | width |
|---|---|---|---|
| 96 | `U+1100` | `U+115F` | 2 |
| 2 | `U+231A` | `U+231B` | 2 |
| 2 | `U+2329` | `U+232A` | 2 |
| 4 | `U+23E9` | `U+23EC` | 2 |
| 1 | `U+23F0` | `U+23F0` | 2 |
| 1 | `U+23F3` | `U+23F3` | 2 |
| 2 | `U+25FD` | `U+25FE` | 2 |
| 2 | `U+2614` | `U+2615` | 2 |
| 12 | `U+2648` | `U+2653` | 2 |
| 1 | `U+267F` | `U+267F` | 2 |
| 1 | `U+2693` | `U+2693` | 2 |
| 1 | `U+26A1` | `U+26A1` | 2 |
| 2 | `U+26AA` | `U+26AB` | 2 |
| 2 | `U+26BD` | `U+26BE` | 2 |
| 2 | `U+26C4` | `U+26C5` | 2 |
| 1 | `U+26CE` | `U+26CE` | 2 |
| 1 | `U+26D4` | `U+26D4` | 2 |
| 1 | `U+26EA` | `U+26EA` | 2 |
| 2 | `U+26F2` | `U+26F3` | 2 |
| 1 | `U+26F5` | `U+26F5` | 2 |
| 1 | `U+26FA` | `U+26FA` | 2 |
| 1 | `U+26FD` | `U+26FD` | 2 |
| 1 | `U+2705` | `U+2705` | 2 |
| 2 | `U+270A` | `U+270B` | 2 |
| 1 | `U+2728` | `U+2728` | 2 |
| 1 | `U+274C` | `U+274C` | 2 |
| 1 | `U+274E` | `U+274E` | 2 |
| 3 | `U+2753` | `U+2755` | 2 |
| 1 | `U+2757` | `U+2757` | 2 |
| 3 | `U+2795` | `U+2797` | 2 |
| 1 | `U+27B0` | `U+27B0` | 2 |
| 1 | `U+27BF` | `U+27BF` | 2 |
| 2 | `U+2B1B` | `U+2B1C` | 2 |
| 1 | `U+2B50` | `U+2B50` | 2 |
| 1 | `U+2B55` | `U+2B55` | 2 |
| 26 | `U+2E80` | `U+2E99` | 2 |
| 89 | `U+2E9B` | `U+2EF3` | 2 |
| 214 | `U+2F00` | `U+2FD5` | 2 |
| 12 | `U+2FF0` | `U+2FFB` | 2 |
| 42 | `U+3000` | `U+3029` | 2 |
| 17 | `U+302E` | `U+303E` | 2 |
| 86 | `U+3041` | `U+3096` | 2 |
| 101 | `U+309B` | `U+30FF` | 2 |
| 43 | `U+3105` | `U+312F` | 2 |
| 94 | `U+3131` | `U+318E` | 2 |
| 84 | `U+3190` | `U+31E3` | 2 |
| 47 | `U+31F0` | `U+321E` | 2 |
| 40 | `U+3220` | `U+3247` | 2 |
| 29245 | `U+3250` | `U+A48C` | 2 |
| 55 | `U+A490` | `U+A4C6` | 2 |
| 29 | `U+A960` | `U+A97C` | 2 |
| 11172 | `U+AC00` | `U+D7A3` | 2 |
| 512 | `U+F900` | `U+FAFF` | 2 |
| 10 | `U+FE10` | `U+FE19` | 2 |
| 35 | `U+FE30` | `U+FE52` | 2 |
| 19 | `U+FE54` | `U+FE66` | 2 |
| 4 | `U+FE68` | `U+FE6B` | 2 |
| 96 | `U+FF01` | `U+FF60` | 2 |
| 7 | `U+FFE0` | `U+FFE6` | 2 |
| 4 | `U+16FE0` | `U+16FE3` | 2 |
| 2 | `U+16FF0` | `U+16FF1` | 2 |
| 6136 | `U+17000` | `U+187F7` | 2 |
| 1238 | `U+18800` | `U+18CD5` | 2 |
| 9 | `U+18D00` | `U+18D08` | 2 |
| 4 | `U+1AFF0` | `U+1AFF3` | 2 |
| 7 | `U+1AFF5` | `U+1AFFB` | 2 |
| 2 | `U+1AFFD` | `U+1AFFE` | 2 |
| 291 | `U+1B000` | `U+1B122` | 2 |
| 1 | `U+1B132` | `U+1B132` | 2 |
| 3 | `U+1B150` | `U+1B152` | 2 |
| 1 | `U+1B155` | `U+1B155` | 2 |
| 4 | `U+1B164` | `U+1B167` | 2 |
| 396 | `U+1B170` | `U+1B2FB` | 2 |
| 1 | `U+1F004` | `U+1F004` | 2 |
| 1 | `U+1F0CF` | `U+1F0CF` | 2 |
| 1 | `U+1F18E` | `U+1F18E` | 2 |
| 10 | `U+1F191` | `U+1F19A` | 2 |
| 3 | `U+1F200` | `U+1F202` | 2 |
| 44 | `U+1F210` | `U+1F23B` | 2 |
| 9 | `U+1F240` | `U+1F248` | 2 |
| 2 | `U+1F250` | `U+1F251` | 2 |
| 6 | `U+1F260` | `U+1F265` | 2 |
| 33 | `U+1F300` | `U+1F320` | 2 |
| 9 | `U+1F32D` | `U+1F335` | 2 |
| 70 | `U+1F337` | `U+1F37C` | 2 |
| 22 | `U+1F37E` | `U+1F393` | 2 |
| 43 | `U+1F3A0` | `U+1F3CA` | 2 |
| 5 | `U+1F3CF` | `U+1F3D3` | 2 |
| 17 | `U+1F3E0` | `U+1F3F0` | 2 |
| 1 | `U+1F3F4` | `U+1F3F4` | 2 |
| 71 | `U+1F3F8` | `U+1F43E` | 2 |
| 1 | `U+1F440` | `U+1F440` | 2 |
| 187 | `U+1F442` | `U+1F4FC` | 2 |
| 63 | `U+1F4FF` | `U+1F53D` | 2 |
| 4 | `U+1F54B` | `U+1F54E` | 2 |
| 24 | `U+1F550` | `U+1F567` | 2 |
| 1 | `U+1F57A` | `U+1F57A` | 2 |
| 2 | `U+1F595` | `U+1F596` | 2 |
| 1 | `U+1F5A4` | `U+1F5A4` | 2 |
| 85 | `U+1F5FB` | `U+1F64F` | 2 |
| 70 | `U+1F680` | `U+1F6C5` | 2 |
| 1 | `U+1F6CC` | `U+1F6CC` | 2 |
| 3 | `U+1F6D0` | `U+1F6D2` | 2 |
| 3 | `U+1F6D5` | `U+1F6D7` | 2 |
| 4 | `U+1F6DC` | `U+1F6DF` | 2 |
| 2 | `U+1F6EB` | `U+1F6EC` | 2 |
| 9 | `U+1F6F4` | `U+1F6FC` | 2 |
| 12 | `U+1F7E0` | `U+1F7EB` | 2 |
| 1 | `U+1F7F0` | `U+1F7F0` | 2 |
| 47 | `U+1F90C` | `U+1F93A` | 2 |
| 10 | `U+1F93C` | `U+1F945` | 2 |
| 185 | `U+1F947` | `U+1F9FF` | 2 |
| 13 | `U+1FA70` | `U+1FA7C` | 2 |
| 9 | `U+1FA80` | `U+1FA88` | 2 |
| 46 | `U+1FA90` | `U+1FABD` | 2 |
| 7 | `U+1FABF` | `U+1FAC5` | 2 |
| 14 | `U+1FACE` | `U+1FADB` | 2 |
| 9 | `U+1FAE0` | `U+1FAE8` | 2 |
| 9 | `U+1FAF0` | `U+1FAF8` | 2 |
| 65534 | `U+20000` | `U+2FFFD` | 2 |
| 65534 | `U+30000` | `U+3FFFD` | 2 |

### 4.3 Raw single-byte readings (0x00..0xFF, run-length compressed)

The code point table and the byte table are two different things: a lone 0x80..0xFF byte is not valid
UTF-8 and reads as 1 replacement glyph. The table below is run-length compressed from a full 256-measurement
sweep of 0..255.

| byte range | width | meaning |
|---|---|---|
| 0x00..0x08 | 0 | C0 controls (NUL..BS), count 0 |
| 0x09 | 8 | TAB: walks to the next 8-column stop, a lone TAB reads 8 |
| 0x0A..0x1F | 0 | the rest of C0 (LF..SI), count 0 |
| 0x20..0x7E | 1 | printable ASCII plus space, count 1 |
| 0x7F | 0 | DEL, count 0 |
| 0x80..0xFF | 1 | lone byte: not valid UTF-8, one replacement glyph per byte (this includes the C1 range 0x80..0x9F -- those read 0 only when encoded as C2 80..C2 9F) |

### 4.4 TAB stops

`cw = 8 - (col & 7)`, where `col` is the column **before** the TAB. Left column = `"x"*col .. TAB`,
right column = `TAB .. "x"*col`.

| columns before TAB | width of `x..x<TAB>` | width of `<TAB>x..x` |
|---|---|---|
| 0 | 8 | 8 |
| 1 | 8 | 9 |
| 2 | 8 | 10 |
| 3 | 8 | 11 |
| 4 | 8 | 12 |
| 5 | 8 | 13 |
| 6 | 8 | 14 |
| 7 | 8 | 15 |
| 8 | 16 | 16 |
| 9 | 16 | 17 |
| 10 | 16 | 18 |
| 11 | 16 | 19 |
| 12 | 16 | 20 |
| 13 | 16 | 21 |
| 14 | 16 | 22 |
| 15 | 16 | 23 |
| 16 | 24 | 24 |
| 17 | 24 | 25 |

### 4.5 Escapes and control sequences

The `check` column compares a hand-written expectation in the generator against the measured value;
all 28 rows are `OK`.

| sequence | bytes | width | check | as bytes |
|---|---|---|---|---|
| CSI SGR on | 5 | 0 | OK | `<1B>[31m` |
| CSI SGR off | 4 | 0 | OK | `<1B>[0m` |
| CSI 256-colour | 11 | 0 | OK | `<1B>[38;5;196m` |
| CSI truecolour | 16 | 0 | OK | `<1B>[38;2;12;34;56m` |
| CSI private > | 6 | 0 | OK | `<1B>[?25l` |
| CSI intermediate | 7 | 0 | OK | `<1B>[>1;2u` |
| OSC + BEL | 10 | 0 | OK | `<1B>]0;title<07>` |
| OSC + ST | 11 | 0 | OK | `<1B>]0;title<1B>\` |
| DCS | 9 | 0 | OK | `<1B>Pq;abc<1B>\` |
| SOS | 7 | 0 | OK | `<1B>Xabc<1B>\` |
| PM | 7 | 0 | OK | `<1B>^abc<1B>\` |
| APC | 7 | 0 | OK | `<1B>_abc<1B>\` |
| nF  ESC ( B | 3 | 0 | OK | `<1B>(B` |
| Fe  ESC 7 | 2 | 0 | OK | `<1B>7` |
| SS2 ESC N + 'a' | 3 | 1 | OK | `<1B>Na` |
| SS3 ESC O + 'a' | 3 | 1 | OK | `<1B>Oa` |
| bare ESC | 1 | 0 | OK | `<1B>` |
| ESC + NUL | 2 | 0 | OK | `<1B><00>` |
| unterm OSC abandon | 13 | 3 | OK | `<1B>]0;x<1B>[31mvis` |
| unterm OSC + CR | 9 | 0 | OK | `<1B>]0;x<0D>vis` |
| unterm OSC + CAN | 9 | 3 | OK | `<1B>]0;x<18>vis` |
| unterm OSC + LF | 9 | 0 | OK | `<1B>]0;x<0A>vis` |
| OSC eof-unterm | 12 | 0 | OK | `<1B>]0;untitled` |
| OSC BEL then LF | 10 | 3 | OK | `<1B>]0;x<07><0A>vis` |
| CAN then LF | 10 | 3 | OK | `<1B>]0;x<18><0A>vis` |
| unterm CSI | 3 | 0 | OK | `<1B>[3` |
| SGR on text off | 13 | 4 | OK | `<1B>[31mab<1B>[0mcd` |
| TAB after SGR | 6 | 9 | OK | `<1B>[1m<09>x` |

### 4.6 Code points that decide a policy

| code point | UTF-8 bytes | width | why it decides a policy |
|---|---|---|---|
| `U+0007` | 1 | **0** | BEL |
| `U+0009` | 1 | **8** | TAB |
| `U+000A` | 1 | **0** | LF |
| `U+000D` | 1 | **0** | CR |
| `U+0008` | 1 | **0** | BS |
| `U+007F` | 1 | **0** | DEL |
| `U+0080` | 2 | **0** | C1 PAD |
| `U+009B` | 2 | **0** | C1 CSI |
| `U+00A0` | 2 | **1** | NBSP |
| `U+00AD` | 2 | **1** | SOFT HYPHEN (DRAWN_CF) |
| `U+0301` | 2 | **0** | COMBINING ACUTE (Mn) |
| `U+09BE` | 3 | **1** | GURU VOWEL AA (Mc) |
| `U+0600` | 2 | **1** | ARABIC NUMBER SIGN (PCM) |
| `U+06DD` | 2 | **1** | ARABIC END OF AYAH (PCM) |
| `U+070F` | 2 | **1** | SYRIAC ABBREVIATION (PCM) |
| `U+08E2` | 3 | **1** | QURAN START (PCM) |
| `U+1100` | 3 | **2** | HANGUL CHOSEONG KIYEOK (initial) |
| `U+1161` | 3 | **0** | HANGUL JUNGSEONG A (medial) |
| `U+11A8` | 3 | **0** | HANGUL JONGSEONG KIYEOK (final) |
| `U+3164` | 3 | **2** | HANGUL FILLER |
| `U+200B` | 3 | **0** | ZERO WIDTH SPACE (Cf) |
| `U+200D` | 3 | **0** | ZERO WIDTH JOINER (Cf) |
| `U+2060` | 3 | **0** | WORD JOINER (Cf) |
| `U+FEFF` | 3 | **0** | BOM (Cf) |
| `U+180E` | 3 | **0** | MONGOLIAN VOWEL SEP |
| `U+2E80` | 3 | **2** | CJK RADICAL REPEAT (W) |
| `U+3000` | 3 | **2** | IDEOGRAPHIC SPACE (F) |
| `U+3099` | 3 | **0** | COMBINING KANA VOICED (Mn AND W) |
| `U+3248` | 3 | **1** | CIRCLED NUMBER FORTY-EIGHT (EAW=A) |
| `U+4DC0` | 3 | **2** | YI HEXAGRAM 1 (Yijing) |
| `U+4DFF` | 3 | **2** | YI HEXAGRAM 64 (Yijing) |
| `U+4E00` | 3 | **2** | CJK UNIFIED IDEOGRAPH-4E00 |
| `U+FF01` | 3 | **2** | FULLWIDTH EXCLAMATION (F) |
| `U+FF61` | 3 | **1** | HALFWIDTH IDEOGRAPHIC A |
| `U+1F600` | 4 | **2** | EMOJI GRINNING |
| `U+1F1E6` | 4 | **1** | REGIONAL INDICATOR A |
| `U+16FE0` | 4 | **2** | TANGUT ITERATION MARK (W) |
| `U+E0001` | 4 | **0** | LANGUAGE TAG |
| `U+F0000` | 4 | **1** | PLANE 15 PRIVATE |

### 4.7 Malformed UTF-8 and the validator

A `width` equal to the byte count means "each illegal byte took one column". Note that `9B` (a lone C1
byte) reads 1 while `C29B` (the legal encoding of U+009B) reads 0.

| case | bytes | width | hex |
|---|---|---|---|
| overlong 2  C0 AF | 2 | **2** | `C0AF` |
| overlong 2  C1 BF | 2 | **2** | `C1BF` |
| valid 2     C2 80 | 2 | **0** | `C280` |
| lone cont   80 | 1 | **1** | `80` |
| lone cont   BF | 1 | **1** | `BF` |
| trunc 2     C2 | 1 | **1** | `C2` |
| trunc 3     E4 B8 | 2 | **2** | `E4B8` |
| trunc 4     F0 9F 98 | 3 | **3** | `F09F98` |
| overlong 3  E0 80 80 | 3 | **3** | `E08080` |
| valid 3     E0 A0 80 | 3 | **1** | `E0A080` |
| surrogate   ED A0 80 | 3 | **3** | `EDA080` |
| surrogate   ED BF BF | 3 | **3** | `EDBFBF` |
| overlong 4  F0 80 80 80 | 4 | **4** | `F0808080` |
| valid 4     F0 90 80 80 | 4 | **1** | `F0908080` |
| valid 4     F4 8F BF BF | 4 | **1** | `F48FBFBF` |
| past max    F4 90 80 80 | 4 | **4** | `F4908080` |
| illegal lead F5 | 4 | **4** | `F5808080` |
| illegal lead F8 | 1 | **1** | `F8` |
| illegal lead FE FF | 2 | **2** | `FEFF` |
| C1 9B as 2b  C2 9B | 2 | **0** | `C29B` |
| C1 9B raw single 9B | 1 | **1** | `9B` |
| DEL 7F | 1 | **0** | `7F` |
| A + trunc 3 + B | 4 | **4** | `41E4B842` |
| zhong + lone cont | 4 | **3** | `E4B8AD80` |

### 4.8 Combining clusters: this model does not do grapheme clustering

One code point at a time, matching conhost, xterm and PuTTY, and what a fixed cell grid needs.
(Windows Terminal pairs an emoji ZWJ sequence and a regional-indicator pair into one cell — a
**deliberate divergence**: the ZWJ family below measures 6 cells here and the RI pair 2.)

| cluster | input bytes | columns | byte return |
|---|---|---|---|
| e + U+0301 | 3 | **1** | 3 |
| a + 5x U+0301 | 11 | **1** | 11 |
| RI pair 1F1E6 1F1E7 | 8 | **2** | 8 |
| emoji 1F600 | 4 | **2** | 4 |
| emoji + VS16 FE0F | 7 | **2** | 7 |
| 26A0 warning | 3 | **1** | 3 |
| 26A0 + VS16 | 6 | **1** | 6 |
| ZWJ family 1F468 200D 1F469 200D 1F467 | 18 | **6** | 18 |
| Hangul syll AC00 (precomposed) | 3 | **2** | 3 |
| Devanagari KA+VIRAMA+SSA | 9 | **2** | 9 |
| Devanagari KA + Mc AA | 6 | **2** | 6 |
| Thai KOKAI + MAIEK | 6 | **1** | 6 |
| Arabic PCM 0600 + 0661 | 4 | **2** | 4 |
| 3x SOFT HYPHEN | 6 | **3** | 6 |
| 10x ZWSP 200B | 30 | **0** | 30 |
| NBSP + space + NBSP | 5 | **3** | 5 |

### 4.9 Hangul jamo sequences (the reading behind `JAMO_ZERO`)

| sequence | bytes | width |
|---|---|---|
| initial alone | 3 | **2** |
| medial alone | 3 | **0** |
| initial + medial | 6 | **2** |
| initial + medial + final | 9 | **2** |
| medial + final, malformed | 6 | **0** |

### 4.10 Cursor folding and multi-line input: when the two returns diverge

Column 3 is `ansi_width`'s **byte** return — it belongs to the widest line, so it is not the length of
the whole string (compare column 2).

| input bytes | columns | widest-line bytes | content |
|---|---|---|---|
| 5 | **2** | 5 | `ab<0D>cd` |
| 4 | **2** | 4 | `ab<08>c` |
| 6 | **3** | 6 | `abc<08><08>X` |
| 3 | **10** | 3 | `<09>ab` |
| 3 | **9** | 3 | `a<09>b` |
| 10 | **17** | 10 | `12345678<09>x` |
| 9 | **9** | 9 | `1234567<09>x` |
| 7 | **4** | 4 | `ab<0A>cdef` |
| 9 | **6** | 6 | `abcdef<0A>ab` |
| 8 | **3** | 4 | `abc<0D><0A>def` |
| 2 | **0** | 0 | `<0A><0A>` |
| 5 | **4** | 4 | `abcd<0A>` |
| 6 | **4** | 4 | `<0A>abcd<0A>` |
| 10 | **2** | 7 | `<1B>[31mab<0A>cd` |
| 8 | **4** | 4 | `<E4><B8><AD><0A>abcd` |

## 5. `utf8.ansi_cut(s[, maxlen])`

`(byte_len, print_len, cut)`, **for strings that do not span lines**: it replays the same `walk` with a
column budget and stops before `col` would pass it, so it measures one line at a time.

- `byte_len` is the **raw byte count of the `cut` string that is returned, escape bytes included**. If
  an ESC appeared before the cut point, `cut` gets a trailing `ESC[0m` reset (4 bytes) and `byte_len`
  counts those 4 too (`ansi_width.c:283-284`). This is the same convention `ansi_width` uses for its
  byte return: both count raw bytes, never "visible" bytes.
- `print_len` is the columns `cut` **actually** occupies, not the requested `maxlen`: a wide character
  straddling the budget is dropped whole rather than drawn half a cell.
- With no budget (second argument omitted) `byte_len` is simply the length of the whole string.
- If the walk stops at a newline and budget remains, the whole input is returned when its total width
  fits `maxlen` (`ansi_width.c:274-280`).

Budget matrix, measured (`budget = -1` means the second argument was omitted; `cut` is printed as hex
bytes verbatim):

| case | budget | input bytes | byte_len | print_len | cut (hex) |
|---|---|---|---|---|---|
| plain | omitted | 6 | 6 | **6** | `616263646566` |
| plain | 0 | 6 | 0 | **0** | `(empty)` |
| plain | 1 | 6 | 1 | **1** | `61` |
| plain | 2 | 6 | 2 | **2** | `6162` |
| plain | 3 | 6 | 3 | **3** | `616263` |
| plain | 4 | 6 | 4 | **4** | `61626364` |
| plain | 6 | 6 | 6 | **6** | `616263646566` |
| plain | 12 | 6 | 6 | **6** | `616263646566` |
| zhong x2 | omitted | 6 | 6 | **4** | `E4B8ADE4B8AD` |
| zhong x2 | 0 | 6 | 0 | **0** | `(empty)` |
| zhong x2 | 1 | 6 | 0 | **0** | `(empty)` |
| zhong x2 | 2 | 6 | 3 | **2** | `E4B8AD` |
| zhong x2 | 3 | 6 | 3 | **2** | `E4B8AD` |
| zhong x2 | 4 | 6 | 6 | **4** | `E4B8ADE4B8AD` |
| zhong x2 | 6 | 6 | 6 | **4** | `E4B8ADE4B8AD` |
| zhong x2 | 12 | 6 | 6 | **4** | `E4B8ADE4B8AD` |
| SGR red | omitted | 12 | 12 | **3** | `1B5B33316D7265641B5B306D` |
| SGR red | 0 | 12 | 0 | **0** | `(empty)` |
| SGR red | 1 | 12 | 10 | **1** | `1B5B33316D721B5B306D` |
| SGR red | 2 | 12 | 11 | **2** | `1B5B33316D72651B5B306D` |
| SGR red | 3 | 12 | 12 | **3** | `1B5B33316D7265641B5B306D` |
| SGR red | 4 | 12 | 12 | **3** | `1B5B33316D7265641B5B306D` |
| SGR red | 6 | 12 | 12 | **3** | `1B5B33316D7265641B5B306D` |
| SGR red | 12 | 12 | 12 | **3** | `1B5B33316D7265641B5B306D` |
| SGR on only | omitted | 8 | 8 | **3** | `1B5B33316D726564` |
| SGR on only | 0 | 8 | 0 | **0** | `(empty)` |
| SGR on only | 1 | 8 | 10 | **1** | `1B5B33316D721B5B306D` |
| SGR on only | 2 | 8 | 11 | **2** | `1B5B33316D72651B5B306D` |
| SGR on only | 3 | 8 | 8 | **3** | `1B5B33316D726564` |
| SGR on only | 4 | 8 | 8 | **3** | `1B5B33316D726564` |
| SGR on only | 6 | 8 | 8 | **3** | `1B5B33316D726564` |
| SGR on only | 12 | 8 | 8 | **3** | `1B5B33316D726564` |
| OSC only | omitted | 5 | 5 | **0** | `1B5D303B78` |
| OSC only | 0 | 5 | 0 | **0** | `(empty)` |
| OSC only | 1 | 5 | 5 | **0** | `1B5D303B78` |
| OSC only | 2 | 5 | 5 | **0** | `1B5D303B78` |
| OSC only | 3 | 5 | 5 | **0** | `1B5D303B78` |
| OSC only | 4 | 5 | 5 | **0** | `1B5D303B78` |
| OSC only | 6 | 5 | 5 | **0** | `1B5D303B78` |
| OSC only | 12 | 5 | 5 | **0** | `1B5D303B78` |
| tab | omitted | 5 | 5 | **10** | `6162096364` |
| tab | 0 | 5 | 0 | **0** | `(empty)` |
| tab | 1 | 5 | 1 | **1** | `61` |
| tab | 2 | 5 | 2 | **2** | `6162` |
| tab | 3 | 5 | 2 | **2** | `6162` |
| tab | 4 | 5 | 2 | **2** | `6162` |
| tab | 6 | 5 | 2 | **2** | `6162` |
| tab | 12 | 5 | 5 | **10** | `6162096364` |
| CR fold | omitted | 9 | 9 | **6** | `6162636465660D7879` |
| CR fold | 0 | 9 | 0 | **0** | `(empty)` |
| CR fold | 1 | 9 | 1 | **1** | `61` |
| CR fold | 2 | 9 | 2 | **2** | `6162` |
| CR fold | 3 | 9 | 3 | **3** | `616263` |
| CR fold | 4 | 9 | 4 | **4** | `61626364` |
| CR fold | 6 | 9 | 9 | **6** | `6162636465660D7879` |
| CR fold | 12 | 9 | 9 | **6** | `6162636465660D7879` |
| LF two lines | omitted | 7 | 7 | **4** | `61620A63646566` |
| LF two lines | 0 | 7 | 0 | **0** | `(empty)` |
| LF two lines | 1 | 7 | 1 | **1** | `61` |
| LF two lines | 2 | 7 | 2 | **2** | `6162` |
| LF two lines | 3 | 7 | 2 | **2** | `6162` |
| LF two lines | 4 | 7 | 7 | **4** | `61620A63646566` |
| LF two lines | 6 | 7 | 7 | **4** | `61620A63646566` |
| LF two lines | 12 | 7 | 7 | **4** | `61620A63646566` |
| combining | omitted | 5 | 5 | **3** | `65CC816162` |
| combining | 0 | 5 | 0 | **0** | `(empty)` |
| combining | 1 | 5 | 3 | **1** | `65CC81` |
| combining | 2 | 5 | 4 | **2** | `65CC8161` |
| combining | 3 | 5 | 5 | **3** | `65CC816162` |
| combining | 4 | 5 | 5 | **3** | `65CC816162` |
| combining | 6 | 5 | 5 | **3** | `65CC816162` |
| combining | 12 | 5 | 5 | **3** | `65CC816162` |
| empty | omitted | 0 | 0 | **0** | `(empty)` |
| empty | 0 | 0 | 0 | **0** | `(empty)` |
| empty | 1 | 0 | 0 | **0** | `(empty)` |
| empty | 2 | 0 | 0 | **0** | `(empty)` |
| empty | 3 | 0 | 0 | **0** | `(empty)` |
| empty | 4 | 0 | 0 | **0** | `(empty)` |
| empty | 6 | 0 | 0 | **0** | `(empty)` |
| empty | 12 | 0 | 0 | **0** | `(empty)` |

## 6. Verification record

| Gate | Scope | Result |
|---|---|---|
| Build self-check | `build.sh` asserts the model inline on 4 targets (x64 / x86 / linux / linux-arm): SGR skip, wide=2, the four TAB stops, widest-line, the CR/BS high-water mark, the OSC abandon rules, SS2/SS3, the whole drawn Cf set, the jamo syllable, the Yijing block, malformed UTF-8, nil, the `ansi_cut` cuts, and the byte half (value count, per-line attribution, tie-goes-to-the-first-line, CR/CRLF/BS byte attribution, a zero-width line still reporting its own bytes) | all pass, no new compiler warnings |
| Independent model, differentially | `awref.lua`: a 1-based mirror of `esc_end` plus its own line splitter, over a 33851-string corpus (31 token classes crossed exhaustively at lengths 1, 2 and 3, plus 28 hand-built multi-line strings) | 0 width mismatches, 0 byte mismatches |
| Full sweep | every table in §4 of this document, x64 artifact | byte-identical to the linux artifact |
| Export-name contract | `namecheck.lua <libdir> [misc.lua]`: `utf8.ansi_cut` is a function, `utf8.ulen` is nil, the real definitions sliced out of `lib/misc.lua` `loadstring` cleanly with `string.ansi_cut` present and `string.ulen` nil, `string.wcwidth` returns exactly 2 values, 9 width assertions, and the `local reps,ansi_cut,wcwidth=...` binding line intact | x64 / x86 / linux / linux-arm (qemu) all PASS |
| Structural assertions | `lua -e loadfile` syntax check, line-ending byte counts (`grid.lua` 100% CRLF, `misc.lua` 100% LF) | not broken |
| Against glibc | `wcwidth()` over all code points | only U+3248..U+324F disagree (8), the deliberate EAW=A call listed in §4.6 |

> `namecheck.lua` first tried to `dofile("lib/misc.lua")` with stubs for `java` and `env`, and failed
> twice (`:129 String=java.require("java.lang.String")`, then a stub function used as a table index).
> The version that works **gives up on stubbing**: it slices the real definitions out of the tail of
> `misc.lua` by anchor line and `loadstring`s them. Cheaper, and more honest — it tests the text in
> the file rather than the file I assumed it was.

## 7. Measured performance: what the byte tracking and the second return cost

Three-way comparison, Windows x64, QueryPerformanceCounter, one configuration per process, equal call
depth, 5 interleaved repetitions, `min` per cell, ns/op:

- **A** = byte tracking deleted, 1 value pushed (`line_start/line_w/maxb/best` and `out_bytes` all gone)
- **B** = byte tracking kept, 1 value pushed (the result is written to `static size_t bench_bytes_sink`,
  otherwise GCC proves `bytes` is dead and deletes the tracking outright — the first version of this
  benchmark measured nothing for exactly that reason)
- **C** = the shipped source (tracking + 2 values pushed)

| case | A ns | B ns | C ns | walk(B-A) | push(C-B) | total(C-A) | vs A |
|---|---|---|---|---|---|---|---|
| ascii1 | 43.10 | 47.25 | 49.62 | +4.15 | +2.37 | +6.52 | +15% |
| ascii8 | 48.72 | 53.77 | 56.21 | +5.05 | +2.44 | +7.49 | +15% |
| ascii64 | 94.03 | 99.92 | 101.17 | +5.89 | +1.25 | +7.14 | +8% |
| ascii1024 | 685.18 | 689.14 | 691.17 | +3.96 | +2.03 | +5.99 | +1% |
| sgr20 | 65.18 | 70.67 | 73.89 | +5.49 | +3.22 | +8.71 | +13% |
| cjk4 | 59.77 | 64.34 | 66.06 | +4.57 | +1.72 | +6.29 | +11% |
| cjk64 | 355.25 | 366.70 | 369.61 | +11.45 | +2.91 | +14.36 | +4% |
| mixed | 111.99 | 123.36 | 127.74 | +11.37 | +4.38 | +15.75 | +14% |
| multiline | 274.52 | 275.30 | 277.73 | +0.78 | +2.43 | +3.21 | +1% |
| tab | 78.35 | 75.10 | 77.02 | -3.25 | +1.92 | -1.33 | -2% |

(aggregated from 150 measurements in `bench_abc3.tsv`, min per cell.)

Conclusion: the per-line bookkeeping inside `walk` is **not free** — `B−A` lands between 4.1 and
11.5 ns (`multiline` shows only +0.8 and `tab` even −3.3; those two cells are noise, not a negative
cost), and the second `lua_pushinteger` is worth a steady 1.3~4.4 ns (median about +2.2). The total
`C−A` is +3.2~+15.8 ns, i.e. 1% (long ASCII, multi-line) to 15% (the shortest strings) over the
pre-change artifact. This table was **re-measured against the currently shipped `lib/x64/utf8.dll`**
(min over 5 interleaved runs per cell) and matches the shape of the 2026-09-07 12:30 round. Given the
±10% run-to-run spread this machine shows, no single row proves anything on its own; what holds up is
that **9 of the 10 cases are positive in total**, the lone exception `tab` missing by 1.3 ns, inside
the noise. What that cost buys is a byte count attributable to a line, which is what the padding gate
in `lua/grid.lua:155-159` needs.

An optimisation that has NOT been tried: replace `int best` with the signed sentinel `ptrdiff_t maxw =
-1` so that `if ((ptrdiff_t)line_w > maxw)` promotes the first line unconditionally by itself, saving
one live local and one short-circuit branch. The scaffold is in `F:\tools\tmp\dsrc`; never compiled,
never measured.

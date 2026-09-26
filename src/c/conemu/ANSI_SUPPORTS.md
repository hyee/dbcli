# ANSI_SUPPORTS -- the ANSI escape support matrix of the C side (render.dll)

Snapshot 2026-09-26, build `render-2026-09-26-24`. The source of truth is **the code itself**:
`Render.cpp` (parsing + the grid model), `Render.h` (state and counters), `Paint.cpp` (turning the model into
console calls), `RenderJni.cpp` (the JNI pen, the title, the query replies). The upstream comparison is ConEmu's
`Ansi.cpp` (every rule carries its line number in the comments); OSC 133 was implemented against ghostty and the
MSFT terminal as references. An unsupported sequence is **never silent**: it is consumed, counted by family
(I19), and only "a final byte this switch has no case for" marks the frame `modelSuspect` and makes the painter
re-adopt the console once (self-healing).

The parse unit is a **UTF-16 code unit**; `rc_feed()` (Render.cpp:2483) is a resumable state machine, so a
sequence broken across chunks continues in the next one, and ConEmu's 512-byte `gsPrevAnsiPart` reparse window
simply does not exist here (deviation #2).

Every `file:line` below points into this directory and was correct as of the build named above. Code moves and
these numbers move with it, which makes them a liability as much as a citation: re-check them with
`cache/p57/citeview.py` (prints what every citation in the two contract documents currently points at) and
`cache/p57/citecheck2.py` (flags the ones whose symbol has walked away). A stale line number is a wrong fact
wearing a citation -- and this pass found twelve of them here, all from code added by other stamps.

---

## 1 Structural capability (the parsing framework)

| Capability | Behaviour |
|---|---|
| State machine | `RC_GROUND / RC_ESC / RC_ESC_INTERIM / RC_CSI / RC_OSC / RC_OSC_ESC` (Render.h:551) |
| CSI byte classes | parameters `0x30..0x3F` (including `;` and the private bytes `? > < = / :`), intermediates `0x20..0x2F` (DECSCUSR's space, DECSTR's `!`; accumulated into a set, see §2.6), final `0x40..0x7E` |
| Parameter count | capped at `RC_CSI_ARGS 16`; extra parameters are **dropped, not refused** (as upstream's ArgV) |
| Parameter values | digits accumulate and **saturate at 65535** (deviation #3: upstream overflows an int); an empty parameter between `;`s is 0; a **trailing** empty parameter is not sent as 0 |
| `arg()` semantics | a missing or zero parameter takes the default (so `CSI 0 A` = `CSI A`) |
| OSC/DCS payload | terminated by `BEL` or `ST(ESC \)`; abandoned by `ESC`/`CAN`/`SUB` it is **counted and never applied**; collection is capped at `RC_OSC_MAX 32768` units, and past that a **title is clipped to `RC_TITLE_MAX 256` and counted, while OSC 52 is refused whole** (half a base64 string is not a message) -- the sequence is consumed either way |
| OSC code reading | matched exactly against the leading digit run (`"0133"` does not match `"133"`), saturating out of range, so `]0133;A` and `]1334;A` cannot hit the wrong family |
| CAN/SUB | arriving inside a CSI or an OSC aborts the sequence back to ground, and the aborted half is charged to nothing |
| Unknown sequences | consumed and counted by family (see the §6 census); `RC_UN_SUP` arriving through the `default:` arm also sets `modelSuspect` |

---

## 2 Supported features

### 2.1 C0 control characters (`control()`, Render.cpp:1569)

| Code | Behaviour |
|---|---|
| `BEL 0x07` | takes no cell, rings nothing |
| `BS 0x08` | moves left without erasing; when it lands on the trailing half of a wide glyph it steps one further (`step_back_col`, Render.cpp:1028 -- upstream's `ROW::_adjustBackward`, and the correct side of the #852 family) |
| `HT 0x09` | fixed **8-column** tabulation, clamped to the end of the line; tab stops are not configurable (see §3) |
| `LF 0x0A` | moves down **and folds to column 0** (the conhost behaviour, measured WriteConsoleW semantics); `IND`/`RI` keep the column |
| `CR 0x0D` | to column 0 |
| other C0 and `DEL 0x7F` | ignored, and **never rendered as a glyph** (the answer to the #1900/#2158 family) |
| C1 `0x80..0x9F` | **not interpreted as control characters**: they go through the width table as ordinary code points (the Cf class measures 0, so they never reach the screen) |

### 2.2 ESC sequences (`esc_dispatch()`, Render.cpp:1500)

| Sequence | Name | Behaviour |
|---|---|---|
| `ESC 7` / `ESC 8` | DECSC/DECRC | saves and restores the cursor position only; **attributes are not saved** (as upstream, Ansi.cpp:2719) |
| `ESC c` | RIS | full reset (see `full_reset()`, Render.cpp:1001: leaves the alternate screen, resets SGR, clears the scroll region and the cursor shape, scrolls the viewport's content up into history, homes the cursor) |
| `ESC D` | IND | one row down, column untouched. This model makes it **region-aware** (upstream's ForwardLF deliberately is not -- a divergence kept for consistency's sake) |
| `ESC E` | NEL | CR + IND |
| `ESC M` | RI | reverse line feed; at the viewport top or the region top it **inserts a blank row** (upstream's LinesInsert semantics); a cursor outside the region only moves |
| `ESC ( 0` | SCACS | activates the G0 line-drawing substitution (the 31 `G0_DRAWING` entries, remapping `0x60..0x7E` only, width taken from the original letter, so a box border is still one cell per letter); `ESC ( B` and any other designator restore the default |
| `ESC N` / `ESC O` | SS2/SS3 | swallow the introducer only -- **the next byte prints as ordinary text** (no eaten glyph, no lost column) |
| `ESC g` / `ESC H` / `ESC =` / `ESC >` | visual bell / HTS / keypad | counted (`RC_UN_MODE`); no cell moves and the input side does not change |
| `ESC ) c`, `ESC % G` | G1 / UTF-8 selection | counted (`RC_UN_SUP`); G1 is unreachable and the UTF-8 flag is never set (the input is UTF-16 already) -- the same as upstream's default arm |

### 2.3 CSI cursor movement (`csi_dispatch()`, Render.cpp:1083)

| Sequence | Name | Behaviour |
|---|---|---|
| `CSI A` / `CSI B` | CUU/CUD | vertical movement; `move_row()` clamps to the **scroll region** (a cursor outside the region is handed to the viewport bounds) |
| `CSI C` / `CSI D` | CUF/CUB | horizontal movement; `D` landing on a wide glyph's trailing half steps one further (the same rule as BS) |
| `CSI E` / `CSI F` | CNL/CPL | vertical movement plus column 0 |
| `CSI G` | CHA | absolute column (1-based) |
| `CSI H` / `CSI f` | CUP | row and column, **viewport-relative** (never lands in the scrollback gutter), clamped both ways |
| `CSI d` | VPA | absolute row (viewport-relative) |
| `CSI a` | HPR | relative **column** movement, clamped to the **viewport** and not constrained by the region (MSFT `adaptDispatch.cpp:427`: "Unlike CUF/CUD, this is not constrained by margin settings"); a missing or zero parameter means 1 |
| `CSI e` | VPR | relative **row** movement, same rule: it takes `clxy` (viewport) rather than `move_row` (region), so it can walk out of a pinned region bottom; the column is preserved, which is its only behavioural difference from `CSI B` |
| `CSI s` / `CSI u` | save/restore cursor | `u` restores only **without a private byte** (`CSI ?u` is the kitty capability query; upstream has no private-byte guard, which is a defect: every round of capability probing teleports the cursor to the DECSC position) |
| `CSI ?1048 h/l` | save/restore cursor | the same slot as DECSC/DECRC |

### 2.4 CSI editing / erasing / scrolling

| Sequence | Name | Behaviour |
|---|---|---|
| `CSI J` 0/1/2 | ED | erases the screen, **stopping at the viewport** (scrollback is untouched); form 2 also homes the cursor to the viewport's top-left (upstream's 2J behaviour) |
| `CSI K` 0/1/2 | EL | erases the line; "the line" is the whole **buffer row** (cols is the buffer width, I7); erasing to end of line also clears that row's wrap claim |
| `CSI L` / `CSI M` | IL/DL | shift inside the region when there is one and are **refused** for a cursor outside it; with no region they shift inside the viewport; an `n` beyond the span is clamped (upstream writes past the region bottom -- a defect, not copied) |
| `CSI @` / `CSI P` | ICH/DCH | open and close slots inside the row, moving LEADING/TRAILING halves as one unit (as upstream does with the same pair); text pushed past the end of the row is gone |
| `CSI X` | ECH | erases n cells and **may run into the following rows** (ConEmu semantics), but the clamp is corrected to the real remaining cell count and stops at the viewport bottom (upstream's formula is one cell off -- a deviation); `CSI 0 X` erases nothing |
| `CSI b` | REP | replays `lastUnit` as text (so it can wrap, takes the current attribute and the charset remap, and a wide glyph costs 2 cells); what repeats is the code point **before** the remap (after `ESC ( 0` a repeat draws a box glyph rather than the letter); `CSI 0 b` repeats nothing; the private form is refused and counted |
| `CSI S` / `CSI T` | SU/SD | scroll the region up/down; with no region (or a region equal to the viewport) SU performs the whole-model scroll (carrying the gutter and the console scroll), and SD leaves the cursor alone |
| `CSI r` | DECSTBM | creates the scroll region. **Missing parameters take the viewport edges**: `CSI 3r` = 3..last row, `CSI ;4r` = 1..4 (both references agree: MSFT `adaptDispatch.cpp:2243-2257`, whose comment at :2239 spells out `[3;r -> 3,h`); **an inverted pair is ignored rather than clearing the region** (`3;2r` keeps the region; MSFT :2242 "an illegal combo ... is ignored") -- clearing and ignoring are different acts, and clearing hands the next line feed the whole viewport, which is exactly the #47/#48 class of failure with a new trigger. Both were changed on 2026-09-25 while re-examining "upstream does not do it either" as a reason: upstream's `Ansi.cpp:3142` demands `ArgC>=2` and otherwise calls `SetScrollRegion(false)`. What still matches upstream and deliberately differs from MSFT is the **clamping**: a bottom parameter past the viewport is pulled back to its last row rather than rejected (MSFT :2260 refuses), and `Pt==Pb` is accepted as a one-row region (`Status.reset()` arrives here as `CSI 1;1r`, and refusing it would leave the status bar's region stuck). Also: parameter 0 clamps to the viewport's first row; setting a region does **not** home the cursor; `CSI ?r` is accepted too; a region that is exactly the viewport normalises to "no region" (MSFT normalises the same way for `apt`, :2262-2270); parameters are viewport-relative and clamped once, never recomputed (a geometry change goes through a re-open, and a re-open has no region) |

### 2.5 DEC private modes (`CSI ? Pm h/l`)

Only `args[0]` is read (upstream looks at ArgV[0] alone, so `?1;2004h` acts on 1 only):

| Mode | Behaviour |
|---|---|
| `?25 h/l` | cursor visibility -> the painter's `SetConsoleCursorInfo`, called only on a real change |
| `?47` / `?1047` / `?1049` | the alternate screen, **one behaviour for all three** (matching MSFT's `ASB_AlternateScreenBuffer`): entering snapshots the main viewport's rows (wrap claims and FTCS marks included) and clears the viewport; leaving restores both; leaving without entering is safe; the alternate screen has no scrollback, so a row scrolled off the top is gone and scrolling costs no console scroll; the only refusal is a snapshot that failed to allocate (counted `RC_UN_ALTBUF`) |
| `?1048 h/l` | saves and restores the cursor only |
| `?2026 h/l` | **synchronized output** (BSU/ESU). While a region is open every on-screen plan is deferred: `flush()` still parses and still updates the model, but touches no console, damage stays marked until the region ends, and the closing flush paints **the whole union** (one rectangle per row, one frame). The first chunk that carries content is deferred too -- an application normally writes its BSU together with the top of the new screen. Three ways out: the ESU (the normal one), a **100 ms clock** (`RC_SYNC_TIMEOUT_MS`, the value MSFT also uses at `renderer.cpp:542`; when it expires the frame paints and the **mode is cleared**, because an application that leaked its BSU must not swallow a whole session one frame at a time), and a **full scrollback gutter** (`pendingScrolls` reaching `rc_scroll_room`: that frame must land or history is evicted, but the **region stays open**). An empty plan (state or cursor moves only) does not count as held; query replies are **sent either way** (a CPR or DA is a fact about the reader, and a program that asked and waits for the answer while we wait for its ESU hangs); `RIS`/`DECSTR` clear the bit. The counting family is in §6: engages/nested/held/timeout/overflow/declined |
| everything else | counted `RC_UN_MODE` (the mouse family 9/1000/1002..1015 and bracketed paste 2004 have **their own** counters, see §3/§6) |

The private `CSI ?7 h/l` (DECAWM) **is acted on** -- see the wrap model in §2.3 and I35 (#61, build -22); the
non-private `CSI 7 h/l` is GATM and is still counted `RC_UN_MODE`. The remaining two non-private modes each have
their own reason, and "upstream has no case" is not one of them (see the #60 re-examination): **LNM(20)** is print
**echo** -- what it changes is when a typed character reaches the screen, and this library owns no input handle
and has no echo to manage; **IRM(4)** only changes the meaning of a later `CSI @`/`CSI P`, and this model treats
ICH/DCH as **explicit sequences** forever, like both references do (insert and delete always happen as asked), so
there is no entity in the model whose behaviour IRM could alter. That is a missing capability -- a mode with an
owner -- not a missing willingness. DECAWM was once refused with that same sentence, arguing that "caps declares
`am`"; on review that conflated two things: **the caps `am` says whether the host terminal wraps, while this
model's right edge is drawn by us**, so `?7` can be implemented while `smam`/`rmam` stay out of the caps entry --
which also describes sessions where ConEmu's own parser reads the bytes and ignores `?7` (I26).

### 2.6 DECSCUSR and DECSTR

| Sequence | Behaviour |
|---|---|
| `CSI Ps SP q` | DECSCUSR: 1..6 stored in `cursorShape`; a missing or out-of-range parameter is 0 (upstream's "default", i.e. do not touch the height). The painter maps it (`Paint.cpp:55`): 1/2 -> block (height 100), 0 and 3..6 -> thin (height 15) -- the console APIs reachable from Win7 offer two shapes only, and folding a bar into an underline matches upstream; **a session that never sent `CSI q` does not touch the user's cursor height** (the -1 sentinel). The test is **the intermediate set being exactly that one byte**: `CSI ? SP q`, `CSI ! SP q`, and a run of spaces before the `q` are all *not* DECSCUSR and count as SUP |
| `CSI !p` (no parameters, no private byte) | DECSTR = `full_reset()` (upstream's FullReset is the same call, and it is a **hard** reset -- harsher than VT's soft one); `!p` with parameters, `?!p`, and every other spelling of `p` are counted |
| the intermediates themselves | accumulated into a set (`interims[RC_INTERIM_MAX]` + `nInterims`, overflow dropped), and consumers compare the **whole string exactly** (`interim_is()` requires length 1). Upstream does exactly this: `Ansi.cpp:1788` appends `0x20..0x2F` and `0x30..0x3F` into one `Pvt` buffer, and `:3645`/`:3657` both test `PvtLen == 1 && Pvt[0] == X`. A single slot lets the last byte win, which made `! SP q` impersonate a real DECSCUSR |

### 2.7 SGR (`sgr_apply()`, Render.cpp:713)

| Code | Behaviour |
|---|---|
| `0` | reset to the **frozen** default attribute (including the SGR 39/49 default colours) |
| `1` | bold: participates in `rc_attr()` as **brightening** only (the foreground nibble gains its bright bit when `bold && !brightBack`) -- the xterm family's bold->bright semantics, #1896 parity |
| `2` / `22` | bold off |
| `4` / `24` | underline on/off -> lands in `RC_LVB_UNDERSCORE` for real, and is drawn |
| `5` `6` / `25` | blink: **no state at all** (upstream is the same, Ansi.cpp:3530) |
| `7` / `27` | reverse video on/off -> lands in `RC_LVB_REVERSE` for real |
| `3` / `23`, `9` / `29` | italic and crossed out: **kept in the model** (`RcSgr.italic/crossed`) but the legacy console attribute has no bit for them, so `rc_attr()` emits nothing -- stored, not painted (the same shape as upstream's #677/#856 gap, see §3) |
| `39` / `49` | default foreground/background (in the 4-bit space, from the frozen default) |
| `30..37` / `40..47` | the standard 16 |
| `90..97` / `100..107` | the bright 16 |
| `38;5;n` / `48;5;n` | 256-colour, with an `n & 0xFF` mask and no range test (as upstream) |
| `38;2;r;g;b` / `48;2;r;g;b` | truecolour, in `0x00BBGGRR` COLORREF order |

Rules that go with them:

- **A bare `CSI m` is a reset** (recorded as an assumption from upstream's convention, not measured parity).
- **A private prefix drops the whole sequence** (`?31m` paints nothing and counts `RC_UN_MODE`) -- upstream's
  Ansi.cpp:3494 discards the whole SGR the same way.
- **An unknown parameter is skipped and the loop continues**: `\e[53;31m` still turns red; a truncated `38/48`
  (fewer parameters after the `5`/`2`) paints nothing and lets the remaining parameters read as ordinary SGR.
- Parameters cap at 16 and values saturate at 65535 (deviation #3).
- **The colour pipeline** (I15): `ReSetDisplayParm -> ExtPrepareColor -> the Far3Color fold`, with the folding
  table `vendor/ConEmuRgbMap.h` (RgbMap[256], ClrMap[8]) and `vendor/ConEmuColors3.h` extracted verbatim from
  upstream and counted at build time; the **fg==bg avoidance** rides on the result only when the background
  really went through the COLORREF fold (index > 15) -- the condition the 633-sample measurement produced.

### 2.8 OSC (`osc_finish()` consulting `rc_osc_families[]`, Render.cpp:2344)

Dispatch is a table rather than a chain of `if`s: each family is `{name, owns(code), apply(...)}`, table order is
precedence, and "no code is claimed twice" is now proved by `geo_osc_families` sweeping 0..4096. How far the
table may be edited is decided by whether a gate asks -- and that is exactly what the chain could never be
asked, because it could not state that no code has two handlers.

| Code | Behaviour |
|---|---|
| `0` / `1` / `2` | **the window title really lands**: upstream's guard copied verbatim (the digits must be followed by `;`, the payload must be non-empty, `]10;foo` is not a title); one pair of surrounding quotes is stripped (an empty string still *is* a title); the painter applies it with `SetConsoleTitleW`; longer than `RC_TITLE_MAX 256` it is clipped and counted and **the sequence is not lost**; an unterminated title counts and applies nothing |
| `133` (FTCS) | **a first-class citizen** (`ftcs_apply()`, Render.cpp:1744): `A`/`N` start a new prompt row (moving to one first when needed -- the only place in the family that moves the cursor); `P` sets the prompt without moving the row; `L` is a plain line feed and **may not carry options**; `B`/`I` mark where input begins (`I`'s input ends at the line's end); `C` marks the output start and reclaims a fish-style continuation mark; `D` carries the exit code (the second field; a non-number is an error rather than a success, following MSFT) and stamps SUCCESS/ERROR onto the nearest marked row above it. `k=c`/`k=s` options recognise a continuation (ghostty's rule); a line feed or a wrap itself promotes a non-output row to CONTINUATION. Row marks are **model-private**: they travel with every vertical move and are dropped after an adopt |
| `9` (ConEmu's private family; T7 split it) | **the safe subset is stored, never obeyed**: `9;4` stores `{state,progress}` (a state > 4 refuses the whole sequence and applies nothing, a progress > 100 clamps to 100 -- as MSFT does at `adaptDispatch.cpp:3596-3605`), `9;9` stores a path (one pair of quotes stripped, one illegal character refuses the whole thing, filtered like `til::is_legal_path`), and `9;12` calls `ftcs_apply("B")` directly -- the same code path as `133;B`, with no second copy of its semantics. Both are read **out** through `NativeRenderer.taskbar()/workingDirectory()`; this library paints no taskbar (it owns no window) and never `chdir`s (a directory from an output stream is data, not a command). **Every other subcommand counts `RC_UN_OSC_PRIV` and is never executed**: `9;1` sleep, `9;2` MessageBox, `9;3` set-environment, `9;6` GuiMacro, `9;7` DoProcess -- #687's RCE answer is unchanged. An unterminated payload counts **at the moment it is abandoned** (until then the parser is still inside it and nothing can be concluded) |
| `4` / `10` / `11` / `104` / `110` / `111` (the palette, I34) | **they really change the console's colours**: the grammar is MSFT's (`OutputStateMachineEngine.cpp:955-1000`/`:1062-1092`) -- `4` is `(index;spec)*`, `?` inquires in place, `10/11` walk one resource per field, `104` with no fields resets the whole table and **stops at the first index it cannot parse** (MSFT:846 notes that is xterm's choice over VTE's), and `110/111` reset only on an empty payload. Accepted specs are `#RGB`/`#RRGGBB`/`#RRRRGGGGBBBB` (three equal widths) and `rgb:r/g/b` (1-4 digits each, widths may differ), scaled to 8 bits by bit replication; **X11 colour names are not resolved** and join `RC_UN_OSC_OTHER` like any other unreadable spec. Indices 0..15 change the **console attribute colours** (written back through `SetConsoleScreenBufferInfoEx` -- see that trap in §5) and participate in the fold; 16..255 change only the fold's target. `10/11` can only land on an **index** (a 4-bit default attribute), so a query answers with the **effective** colour, not the requested one |
| `52` (the clipboard, I36) | **off by default, and only the host can turn it on**: `ANSI_CLIPBOARD=on\|1\|true\|yes` read once at class-init, or `NativeRenderer.setClipboardPolicy(true)`; nothing in the byte stream can reach either entry point, which is precisely why "off" means off (the census cannot tell a terminal the user configured from one a script configured, so a count is no substitute for a policy). There is no ASK setting: this library owns no window, so there is nowhere to ask. A **read** (`52;c;?`) is refused whether or not writing is enabled -- answering it would put what the user last copied into the console's **input** stream, i.e. into the next command line. The selection field accepts only `c` and empty: this machine has one clipboard, and ghostty can fold `p`/`s`/`q`/`0-7` only because X11 and macOS really do have those registers (`stream_terminal.zig:678-682`). base64 is strict RFC 4648: whole payload or nothing (never a partial decode), whitespace inside the payload refused rather than skipped, the unused bits of the final group required to be zero (so a tail like `QR==` -- "looks like an A, hides a character" -- is refused), a payload that decodes to a NUL refused whole (`CF_UNICODETEXT` is NUL-terminated, and storing the prefix hands the user half a paste), and the UTF-8 validated with `MB_ERR_INVALID_CHARS` before it becomes UTF-16. **An empty payload is the act of clearing**, not the absence of one. Refusals fall into four counted families (decode / selection / read / over-capacity), so `NativeRenderer`'s closing line can say which. `close()` does **not** restore the clipboard: snapshotting it at open would be the very read this half refuses. **ConEmu has no OSC 52 at all** (measured: its OSC switch is `switch (*Code.ArgSZ)` with cases 0/1/2/4/9… and no `case L'5'`). **But both reference terminals do, and both default to allowing it**: Windows Terminal has `OscActionCodes::SetClipboard = 52` (`OutputStateMachineEngine.hpp:222` -> `.cpp:821-827` -> `adaptDispatch.cpp:3302`), gated by `compatibility.allowOSC52` / `AllowVtClipboardWrite`, **default true** (`ControlProperties.h:59`, `MTSMSettings.h:119`, read at `Terminal.cpp:106`); ghostty's `clipboard-write` defaults to `.allow` (`Config.zig:2459`). So the default here is a **deliberate divergence from both references**, and the reason has to be our own: those two are terminals the user configures and answers for, and a setting exists because somebody turned it on, while a renderer living inside someone else's JVM has no such setting and no party who consented to the act -- silence can only be read as "not agreed", never as "agreed". Where the references agree, we agree: neither **answers** a read (WT parses the `?` and then drops it at `.cpp:825`; ghostty gates reads with `clipboard-read=.ask`), and this build refuses the read outright. One further deliberate split from MSFT: it ignores the selection field entirely (its own comment at `:1097` says "Currently the first parameter `Pc` is ignored"), so `52;p;…` writes the clipboard there, whereas this build follows ghostty's grammar and honours `c` and empty only -- folding answers a different question than the one that was asked, and MSFT's own comment calls that unfinished work |
| everything else (8/…) | counted `RC_UN_OSC_OTHER` -- and that tail is the invariant: it bills **a code no family owns**. A refused 133 spelling, an unterminated 133, and the unreadable colour specs above also land here. 52 has left this list to run its own family, and its refusals are counted in `RC_UN_OSC_CLIP` |

### 2.9 Queries and replies (I29)

| Query | Reply (`reply_text()`, RenderJni.cpp:653) |
|---|---|
| `CSI 5 n` | `ESC [ 0 n` (ready) |
| `CSI 6 n` | `ESC [ row ; col R`, 1-based, **counted from the window's top** (the same arithmetic the painter used); the answer is the cursor **as it stood when the query was read** (the queue entry is a snapshot -- `printf '\e[6n\e[2;3H'` reports row 1) |
| `CSI c` / `CSI 0 c` | `ESC [ ?61;4;6;7;14;21;22;23;24;28;32;42c` -- **conhost's identity string** (with the `;52` clipboard bit removed), not ConEmu's `?1;2c`: a declined chunk is handed to conhost, which answers that one itself, and one session must not present two identities |
| `CSI > c` / `CSI > 0 c` | `ESC [ >0;10;1c` (conhost's DA2) |
| `OSC 4;<i>;?` / `OSC 10;?` / `OSC 11;?` | `OSC 4;<i>;rgb:RRRR/GGGG/BBBB` (or `10;rgb:…` with no index), 16-bit components = the byte x0x0101, closed with ST -- the same shape as MSFT's `adaptDispatch.cpp:3338`/`:3417`. **The answer is the effective colour**: the defaults are 4-bit, so what comes back is the colour of the index the request folded to |
| `CSI ? <mode> $ p` | `ESC [ ? <mode> ; <status> $ y` (DECRPM), answering **only state the model really holds**: 25 -> `cursorVisible`, 47/1047/1049 -> `alt` (three spellings of one bit, so they cannot contradict each other or the DECSET that moved them), 2026 -> `sync`; and only the two statuses 1 (reset) and 2 (set). Snapshot semantics as for CPR (fixed when the question is read: `?2026h ?2026$p ?2026l` in one chunk still answers "it was on"). Upstream has no such reply (`Ansi.cpp:3650-3653` sends every `p` it does not know to DumpUnknownEscape); the reason to answer is jline4's probe batch, which looks replies up **by mode number** (`parseDecrpm`, AbstractTerminal.java:675-690) rather than reading them positionally |

Mechanism: a query is **queued** while parsing (FIFO, capped at `RC_REPORT_MAX 8`; a full queue refuses the new
query and counts it rather than evicting an older one); the painter writes the answers at the **end of a
successful flush**, one character at a time, as `KEY_EVENT` pairs into `CONIN$` (the same synthesis conhost's own
output leg uses), and even an empty flush writes them; a **declined** chunk answers nothing (its bytes were
handed back to conhost, and a second reply would be dirty input).

### 2.10 Width, glyphs and wrapping

| Item | Behaviour |
|---|---|
| The width oracle | `rc_width()` (Render.cpp:38) = the Unicode 15 tables in `src/c/luauf8/ansi_width` (the jansi/JLine WCWidth family is explicitly excluded); control characters 0, wide 2, ordinary 1 |
| The EAW ruling | **Ambiguous counts as wide**, minus the 206 exceptions measured at one cell across six fonts (`AMBIGUOUS_NARROW`: box glyphs, block elements, accented Latin); no VS16 promotion (`A\uFE0E` is as wide as `A`) |
| Zero width | Mn/Me/Cf produce no cell and take no column (as xterm/WT/glibc; conhost gives a combining mark its own cell, and we **do not** follow it) |
| Wide glyphs | 2 cells: a `LEADING` and a `TRAILING` half carrying the same code point; when they do not fit the **pair wraps whole** (`RC_WRAP_PAD`) and is never split |
| The supplementary planes | a surrogate pair is reassembled into the full code point before it is measured; what reaches the console is the original pair of units (never folded to U+FFFD); a high surrogate at a chunk boundary is held in `wantLow` and completed next time; a lone low surrogate writes one U+FFFD cell |
| Wrapping | **immediate** (no deferred wrap / pending-wrap): the four discriminators agreed on both legs when measured (CONEMU_ANSI_DEFECTS §2 end), so it stays undone |
| Soft vs hard break | one bit per row, `RC_WRAP_FORCED` (pushed to the right edge) or `RC_WRAP_PAD` (a wide pair wrapped whole), for copy and export to join rows correctly; it is not in `CHAR_INFO` and is dropped after an adopt |
| Erasing and attributes | an erase **overwrites whole cells** without merging, so a wide glyph's trailing half is destroyed when erased (I13, as conhost does) |

---

## 3 Not supported (all consumed and counted; see §6)

### SGR / colour

| Item | Behaviour | Note |
|---|---|---|
| blink `5/6/25` | no state | as upstream |
| **painting** italic `3/23` and crossed-out `9/29` | state kept, nothing drawn | the legacy attribute has no bit; drawing them means drawing ourselves (the same upstream gap as #677/#856) |
| `8` invisible, `53` overline, `21` double underline, `51/52` framed, `58/59` underline colour | fall under "unknown parameter, skipped" | no state in the model for them |
| **colon subparameters** `38:2::r:g:b`, `4:3`, … | **the whole sequence is dropped**, counted `RC_UN_COLON` | `:` is a Pvt byte in ConEmu; this is the I10 parity decision (the terminal that really parses them is Windows Terminal), and counting them is so a rollout has a number the day an application starts sending the colon form |
| 256-colour and 24-bit fidelity | supported, but **through ConEmu's palette fold** | differing from "true colour" is a feature, not a defect (#2516 reproduced); `48;2;…` does not degrade to colour number 8 |

### Positioning and tabs

| Item | Behaviour | Note |
|---|---|---|
| `CSI Z` CBT, `ESC H` HTS | dropped, counted `RC_UN_SUP` | there is **no tab-stop state at all**, so CBT has nowhere to back up to |
| tab stops | HT's fixed 8 columns only, not configurable | the terminfo entry correspondingly offers no `cbt/hts/tbc` |
| left/right margins (DECLRMM/DECSLRM), origin mode DECOM | counted `RC_UN_MODE` | not modelled |

### DEC/ANSI modes

| Item | Behaviour | Note |
|---|---|---|
| `?1` DECCKM (application cursor keys) | counted `RC_UN_MODE` | it changes the **input side** only, and this renderer does not touch input encoding |
| mouse `?9`, `?1000` `?1002` `?1003` `?1004` `?1005` `?1006` `?1015` | counted `RC_UN_MOUSE` | no mouse reports are produced |
| bracketed paste `?2004` | counted `RC_UN_DECBP`; there is no marker producer (a role mismatch: the paste is performed by conhost's QuickEdit, read by jline's pump, and the DLL is the output leg and **must not** read CONIN$ and steal input) | an optional upgrade: the DLL stores the bit + answers DECRPM + exposes it, and the host's input pump marks bursts -- see ANSI_TODO §6 |
| every other private/ANSI mode (including the query spellings other than `?6n`, `?3`, `?12`, the non-private `7` GATM, `4` IRM, `20` LNM) | counted `RC_UN_MODE` | each one checked against upstream: no case at all, or a case whose body is empty or commented out; the real replacement for IRM is that `CSI @` always inserts |
| `CSI ? 6 n` extended CPR | **deliberately unanswered**, counted | answering an extended question with the plain form reports a position nobody asked for; refusing is the option that cannot be wrong |
| `?2027$p` / `?2048$p` / `?1048$p` | **deliberately unanswered**, counted `RC_UN_MODE` | the permanent values 3/4 mean opposite things in DEC/xterm and in jline4's own documentation (`AbstractTerminal.java:663-667`), so whichever is sent one reader is lied to (2048 answered "permanently set" would claim resize arrives in the data stream); 1048 is a save/restore **event**, not reportable state. Silence is `NOT_SUPPORTED` for that asker, exactly as `?6n` set the precedent |

### Reports and windows

| Item | Behaviour | Note |
|---|---|---|
| `CSI t` window operations (including the pixel report `14t` and the character sizes `18t/19t`) | counted `RC_UN_REPORT`, not answered | a pixel size needs a window rectangle this library does not own; `18/19` could be answered but there is no consumer yet (the rule: model what a real writer sends) |
| DA with parameters (`CSI > 0 ; 1 c` and friends) | counted `RC_UN_REPORT` | upstream has no such reply spelling |
| OSC 8 (hyperlinks) | counted `RC_UN_OSC_OTHER` | **not supported** (#56, ruled out by the user on 2026-09-26): a link is a **range**, not a cell, so it would have to live beside `rowWrap[]` and inherit I20's never-readable-back debt; the sequence alone buys the user nothing visible. OSC 52 landed as I36 (§2.8) and does not belong to this row, and neither does the palette family 4/10/11/104/110/111, landed as I34 |
| the **dangerous half** of ConEmu's private OSC `9` (`9;1` sleep / `9;2` MessageBox / `9;3` set-environment / `9;6` GuiMacro / `9;7` **DoProcess**) | counted `RC_UN_OSC_PRIV`, **never executed** | #687's RCE: the only floor under executing the semantics is not implementing them. The safe half -- `9;4`/`9;9`/`9;12` -- is in §2.8: stored to be read is not the same as executed |

### Character sets and graphics

| Item | Behaviour | Note |
|---|---|---|
| `ESC ) c` G1, `ESC % G` UTF-8 selection | counted `RC_UN_SUP` | same as upstream's default arm; the input is UTF-16 already |
| `ESC P/X/^/_` (DCS/SOS/PM/APC) | the payload is consumed with OSC's framing and then **discarded whole**, counted `RC_UN_DCS` | no Sixel or kitty graphics, no XTGETTCAP |
| SS2/SS3 shifts | only the introducer is swallowed; the byte after it prints normally | not eating the glyph is deliberate (eating one costs a column) |

### The wrap model

| Item | Behaviour | Note |
|---|---|---|
| deferred wrap (pending wrap / postponing DECAWM) | **not implemented** | all four discriminators (CR+Y after a full row, BS+Y, EL, CUA+Y) agreed on both legs; switching to deferred would only create a new divergence (upstream's breeding ground for the #2404 family). Unrelated to `?7`: what that postpones is "the cursor stays on the last cell after it is filled", and this model moves on immediately, wrap mode or not |
| DECAWM `CSI ?7 h/l` (**implemented**, I35, #61) | on = wrap at the right edge (unchanged); **off = the last cell is overwritten repeatedly**: the cursor holds at the margin, the row takes **no** `RC_WRAP_FORCED` claim, no row below is started, and a glyph that cannot fit is dropped **whole** (and that cell cleared to blank) | wrapping is this model's behaviour rather than `ENABLE_WRAP_AT_EOL`'s, which is why it can be implemented at all. Dropping whole = MSFT `Row.cpp:474-494` ("Ignore the character. There's no correct alternative way to handle this situation") plus its anti-deadlock guard; clearing the orphaned back half when a narrow glyph overwrites a wide one's front half is conhost's cluster trim (I16's "the pair is one unit"); a cursor never rests inside a wide glyph (the `step_back_col` rule). `RIS`/`DECSTR` restore the mode; a resize rebuild **keeps** the current value (a resize is not a request to start wrapping again); DECRQM answers 1 or 2 for `?7`; `?7` no longer votes `RC_UN_MODE`. The caps entry **still** carries no `smam`/`rmam` -- see §2.5 for why |

---

## 4 Deliberate divergences from ConEmu (each of them on the record)

1. **An ESC inside an unfinished CSI/OSC abandons and restarts** (`\e[3\e[31m` turns red; ConEmu parks the ESC in
   Pvt and keeps swallowing, printing the text `31m`) -- Render.h deviation #1.
2. **A resumable state machine instead of the 512-byte reparse window** (upstream's reparse silently drops what
   does not fit) -- deviation #2.
3. **Parameter accumulation saturates at 65535** instead of reproducing upstream's int overflow -- deviation #3,
   differing only on absurd input.
4. **ECH's clamp is fixed**: the real remaining cell count (upstream's formula is one cell off per row, so the
   last column survives); crossing into further rows stops at the viewport bottom.
5. **IL/DL clamp to the region**: when n exceeds the region's height only the region is filled (upstream writes
   `dwSize.X * n` starting at the cursor's row, overrunning whatever sits below the region bottom).
6. **IND is region-aware**: upstream's ForwardLF ignores the scroll region; here LF/IND/NEL/RI all agree about
   which rows scroll.
7. **`move_row`'s region clamp uses model coordinates**: upstream compares absolute buffer rows against a
   window-relative cursor, off by exactly the window's position.
8. **Reply identities are conhost's strings** (DA1 `?61;…`, DA2 `>0;10;1`), not ConEmu's `?1;2c` / `>0;136;0`: a
   declined chunk is answered by conhost itself, and the two must not disagree.
9. **The supplementary planes keep their original units** (`put_pair`), while `REP` stores a full code point
   (upstream's WCHAR stores half a surrogate and replays the fragment twice).
10. **IL/DL's region guard**: they do nothing when the cursor is outside the region. That is not "they can, we
    cannot" -- it is us being **closer to VT**: xterm and MSFT both act inside the region only, and upstream
    ConEmu lets a cursor parked above the top pull rows over it, which is its own looseness.
11. **DECSTBM no longer mirrors upstream in two places** (the outcome of the 2026-09-25 review of "upstream does
    not do it either"): a one-parameter call takes the missing edge from the viewport, and an inverted pair is
    ignored rather than cleared -- both agree with MSFT/xterm and differ from `Ansi.cpp:3142-3150`. The clamping
    and the `Pt==Pb` tolerance still agree with upstream (the reasons are in that §2.4 row).
12. **`SetConsoleScreenBufferInfoEx` eats a window row on the round trip** (measured 2026-09-25): writing the
    struct straight back after reading it moves `srWindow.Bottom` from 29 to 28 (a 30-row window becomes 29), the
    next plan then reads NOGEOM and **declines the whole frame** -- setting a colour would shrink the user's
    viewport and never paint again; the palette restore in `close()` walked into the same thing (a 24-row leg read
    back 23). The countermeasure is to re-read the plain info after writing and, if the console disagrees, put the
    rect and size back with `SetConsoleScreenBufferSize` + `SetConsoleWindowInfo`; both paths share one
    `apply_palette`. **Any new feature that writes through InfoEx has to carry this fix.**

---

## 5 Bounds and limits

| Limit | Value | Behaviour past it |
|---|---|---|
| `RC_MAX_COLS` | 4096 | `open()` refuses (OPEN_WIDE) and the caller keeps using the old Java writer |
| `RC_MAX_ROWS` | 256 | refused at >= 256 rows (OPEN_NO_GUTTER); the gutter is a full screen at <= 128 rows and shrinks from 129 to 255 |
| `RC_CSI_ARGS` | 16 | extra parameters are dropped |
| `RC_TITLE_MAX` | 256 | the length of an **applied** title: clipped plus `nTitleTrunc` counted, the sequence still consumed |
| `RC_OSC_MAX` | 32768 | how many units of OSC/DCS payload are **collected** (`nOsc`). Past it a title is still clipped to `RC_TITLE_MAX` and counted, while OSC 52 is refused whole (`nClipBad`) -- truncated base64 is not a message |
| `RC_CLIP_ENC_MAX` | 16384 | the encoded-length cap on an OSC 52 payload; past it the request is refused whole |
| `RC_CLIP_MAX` | 12288 | the decoded byte cap, which is also `rc_clip_take`'s cap, so "it does not fit" is decided while parsing |
| `RC_REPORT_MAX` | 8 | a full queue **refuses** the new query and counts `nReportFull`; older entries are never evicted |
| `RC_SGR_ECHO_MAX / RC_SGR_CAP_MAX` | 1024 / 64 | the SGR echo exists only as a witness stub; overflow counts `nSgrDrop` and never disturbs parsing |

---

## 6 The counters (the census) (`RcUnsupported`, Render.h:87)

Slot numbers are a **positional contract** with the JNI side and are never renumbered.

| Counter | Trigger | sets `modelSuspect`? |
|---|---|---|
| `RC_UN_SUP` | a CSI/ESC final this switch has no case for (the `default:` arm) => **suspect**; and the known-inert `Z`, `q` with no interim, and the other spellings of `p` (through `ignored()`) => **not suspect** | the default arm only |
| `RC_UN_DECSTBM` | a dead slot (`CSI r` is modelled), kept only for the positional contract | no |
| `RC_UN_ALTBUF` | the alternate-screen snapshot failed to allocate | no (the sequence is consumed and the screen did not move) |
| `RC_UN_MOUSE` | the mouse mode family | no |
| `RC_UN_MODE` | private-prefixed SGR, unmodelled DEC/ANSI modes, `ESC g/H/=/>` and friends | no |
| `RC_UN_DECBP` | bracketed paste 2004 | no |
| `RC_UN_OSC_PRIV` | ConEmu's private OSC 9 (including unterminated) | no |
| `RC_UN_OSC_OTHER` | any other OSC code, an unterminated title, a refused or unterminated 133 | no |
| `RC_UN_DCS` | DCS/SOS/PM/APC | no |
| `RC_UN_REPORT` | queries that are not answered (`CSI t`, DA with parameters, `?6n`, DSR other than 5/6) | no |
| `RC_UN_COLON` | a CSI that carried `:` (one vote per sequence) | no |
| `RC_UN_OSC_CLIP` | one of OSC 52's refusals: policy off, a selection this platform has no place for, a payload that failed the strict decode, a request over the cap -- or a **read** | no |

What goes with them: once `modelSuspect` is set the painter **re-adopts the console once** and clears the bit
(self-healing); besides that there are the family-specific tallies `nTitleSet/nTitleTrunc`,
`nClipSet/nClipBad/nClipSel/nClipRead` (plus `g_clipCalls/g_clipFails` on the painter's side),
`nAltSwitch/nAltFail`, `nReportOk/nReportFail/nReportFull` and `nPromptMark`. The 12th slot arrived at -24, and
`STAT_TITLES = STAT_UNSUPPORTED + RC_UN_MAX` -- so **adding one slot shifts the offset of every family after
it**, and `Render.java`'s and `NativeRenderer`'s two hardcoded tables have to move by +1 in lockstep (the field
of zeroes the live gate printed on its first -24 run is the receipt for that).

The synchronized-output family (`RcGrid`, deliberately not in `RcUnsupported`: they record *how the mode was
used*, not *what is unmodelled*): `nSyncEngages` (how many regions opened -- the denominator for all the others),
`nSyncNested` (a second BSU inside a region), `nSyncHeld` (frames deferred), `nSyncTimeout` (the clock expired,
which also cleared the mode), `nSyncOverflow` (the gutter filled, the region kept open), `nSyncDeclined` (a chunk
was refused, so the region ended and the re-adopt path ran). With the live bit `sync` that is seven slots at the
tail of `stats()`, and the same positional contract: `Render.java`'s `S_SYNC*`, `NativeRenderer`'s `SLOT_SYNC*`
and `RenderJni.cpp`'s `STAT_SYNC` move together, and the live gate has an assertion holding the array length.

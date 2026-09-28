# ANSI_SUPPORTS — which ANSI escape sequences this renderer supports

Scope: the native renderer behind dbcli's terminal output (`render.dll`, loaded through
`com.hyee.ansirender.NativeRenderer`), for the terminal type it advertises, `windows-conemu`. This is the
user-facing matrix: what a program running under this renderer can use, what it cannot, and what the three
reference terminals do instead.

It deliberately carries **no file names and no line numbers**. The evidence for every row lives in the
maintainer documents — `DESIGN.md` (the invariants), `ANSI_TODO.md` (the per-item ledger, where each `#NN`
below is a ticket), `terminfo/TERMINFO.md` (the capability entry), and the gate suites in
`RenderCheck.cpp`/`Render.java` — and those documents are the place to look when a row has to be re-argued.

**How to read the "why not" column.** Four reasons are accepted as arguments, and one label is not:

| Tag | Meaning |
|---|---|
| **no carrier** | there is no place in the model to hold the thing, and it is not merely unwritten |
| **would lie** | advertising or answering it would state something the model does not hold, or would describe a session that another parser is reading |
| **conflicts with #NN** | taking it collides with a named feature, and the row says what that costs |
| **floor** / **owner decision #NN** | refused on purpose for safety, or ruled out by a named decision |
| **GAP** | none of the above applies. This is missing work, not an argument, and it is listed in §6 |

"Nobody in this stack reads it", "no application sends it" and "the upstream we replaced does not do it either"
are **not** reasons on this page.

---

## 1 Structure

| Property | Behaviour |
|---|---|
| Feed | UTF-16 code units, resumable: a sequence split across writes continues in the next one |
| Parameters | up to 16 per sequence, values saturate at 65535, surplus parameters are dropped **and counted**; an omitted or zero parameter takes the default |
| Unknown sequences | never silently swallowed: consumed, counted by family (§8), and a final byte with no case at all marks the model suspect, which makes the next paint re-read the console once and re-sync |
| Interruptions | `CAN`/`SUB`/`ESC` inside a partially-read sequence abandon it (counted, nothing applied) and restart cleanly |
| Terminals compared | microsoft/terminal, wezterm, ghostty. "All three do it" is evidence about what is possible, never about what is owed |

---

## 2 Supported

### 2.1 C0 controls

| Code | Behaviour |
|---|---|
| `BEL` | takes no cell, rings nothing |
| `BS` | moves left, never erases; steps off the trailing half of a wide glyph |
| `HT` | walks the tab-stop table (§2.11) forward; at the end of the line it stops rather than wrapping |
| `LF` | down one line **and to column 0** — the console's own behaviour, measured |
| `CR` | column 0 |
| `SO` / `SI` | select the drawing set / the default set for subsequent text (§2.2) |
| other C0, `DEL` | ignored, and never drawn as a glyph |
| C1 (`0x80`–`0x9F`) | treated as ordinary code points, not as controls; they are zero-width and never reach the screen |

### 2.2 ESC sequences

| Sequence | Name | Behaviour |
|---|---|---|
| `ESC 7` / `ESC 8` | save / restore cursor | position only — attributes are not saved; the origin mode travels with it |
| `ESC c` | RIS | full reset: leaves the alternate screen, resets the pen, drops the scroll region and the cursor-shape claim, clears the tab table to defaults, un-designates all four character sets and un-shifts, scrolls the viewport's content into history, homes the cursor |
| `ESC D` / `ESC E` / `ESC M` | IND / NEL / RI | down a line, CR+down, up a line — all three honour the scroll region; `RI` at the top of the region inserts a blank line |
| `ESC ( 0` | designate drawing set | box drawing for `` ` ``–`~`, one cell per character, width inherited from the letter it replaces; `ESC ( B` restores |
| `ESC ) * + ~ c` | designate G1–G3 | all four slots are stored and each holds one bit; only the drawing set and ASCII can be named. **Designating is invisible until something shifts it in** — `SO`/`SI` choose what the screen shows |
| `ESC H` | HTS | claims the cursor's column as a tab stop (§2.11) |
| `ESC N` / `ESC O` | SS2 / SS3 | the introducer is consumed and the next byte prints as ordinary text — nothing is eaten, no column is lost |
| `ESC g`, `ESC =`, `ESC >` | visual bell, keypad | counted, nothing happens: this library owns no window to flash and no input encoding to switch |
| `ESC ) c`, `ESC % G` | G1 designation with a foreign set, UTF-8 selection | counted. The input is already UTF-16, so there is no encoding to select |

### 2.3 Cursor movement

| Sequence | Name | Behaviour |
|---|---|---|
| `CSI A/B/C/D` | CUU/CUD/CUF/CUB | movement, clamped to the scroll region when one is set (a cursor outside the region is clamped to the viewport instead); leftward movement steps off a wide glyph's trailing half |
| `CSI E/F` | CNL/CPL | up/down plus column 0 |
| `CSI G` / `` CSI ` `` | CHA/HPA | absolute column |
| `CSI H` / `CSI f` | CUP | absolute position, viewport-relative — it can never land in the scrollback gutter, and it is clamped inside the margins when margins exist |
| `CSI d` | VPA | absolute row |
| `CSI a` / `CSI e` | HPR/VPR | relative column / row; like CUP these honour origin mode and margins |
| `CSI s` / `CSI u` | save / restore | `u` restores **only** without a private byte — `CSI ?u` is somebody else's protocol and is refused, not misread as a cursor jump |
| `CSI ?1048 h/l` | save / restore | the same slot as `ESC 7`/`ESC 8` |

### 2.4 Editing, inserting, deleting, scrolling

| Sequence | Name | Behaviour |
|---|---|---|
| `CSI J` 0/1/2 | ED | erases to/before/after the cursor, **stopping at the viewport** — the user's scrollback is never destroyed; form 2 also homes the cursor |
| `CSI K` 0/1/2 | EL | erases the line; forms 0/1 stop at the margins, form 2 takes the whole row; erasing to the end also clears that row's wrap claim |
| `CSI L` / `CSI M` | IL/DL | insert/delete lines inside the region, refused for a cursor outside it, clamped to the rows that exist; after a shift that happened the cursor is at column 0 of its own row (a redrawn table would otherwise shift by the cell count), a refused one keeps its column |
| `CSI @` / `CSI P` | ICH/DCH | open and close cells within the row, moving a wide glyph's two halves as one unit and healing a pair the shift split; text pushed off the row is gone |
| `CSI X` | ECH | erases cells **on the cursor's row only** — it never runs into the following rows |
| `CSI b` | REP | repeats the last written glyph as text: it wraps, takes the current attributes and the drawing-set remap, and a wide glyph still costs two cells; a combining mark alone is never stored as "the last thing" |
| `CSI S` / `CSI T` | SU/SD | scroll the region; with no region this is the whole-model scroll, carrying history with it |
| `CSI r` | DECSTBM | set the scroll region. A missing parameter takes the viewport's own edge (`CSI 3r` is "3 to the last row"); an inverted pair is **ignored** rather than clearing the region; an over-deep bottom is clamped rather than rejected; a one-row region is accepted (a status bar's reset arrives as exactly that); a region equal to the viewport is stored as "no region"; setting a region does not home the cursor; `CSI ?r` is accepted too |
| `CSI Pl;Pr s` / `CSI ?69 h/l` | DECSLRM / DECLRMM | left and right margins, with the gate: with `?69` off those same bytes are save-cursor, and with it on they set margins and home the cursor. A pair covering the whole page clears rather than stores |
| `CSI ?6 h/l` | DECOM | origin mode: rows count from the region top and columns from the left margin, and the clamp moves with it. Setting it homes the cursor; save/restore carries it |

### 2.5 DEC private modes

Only the first parameter of a `h`/`l` list acts, matching the baseline parser.

| Mode | Behaviour |
|---|---|
| `?25` | cursor visibility |
| `?47`, `?1047`, `?1049` | the alternate screen — one behaviour for all three spellings. Entering snapshots the main viewport (wrap claims included) and clears; leaving restores; the alternate screen has no scrollback, and leaving without entering is harmless |
| `?1048` | save / restore the cursor |
| `?7` | DECAWM, autowrap: on wraps at the right margin; off, the last cell is overwritten in place, the row takes no wrap claim, no row below is started, and a glyph that cannot fit is dropped whole rather than split |
| `?4` and `4` | IRM, insert mode: an ordinary written glyph opens room for itself. One bit, both spellings, reportable either way; where the glyph would not fit strictly inside the row it overwrites instead |
| `?6`, `?69` | origin mode and the margin gate — see §2.4 |
| `?2026` | synchronised output: while open, nothing is written to the console and damage accumulates; the closing reset paints one union frame. Three ways out — the end sequence, a 100 ms timeout that also clears the mode, and a full scrollback gutter (that frame must land, but the region stays open). Query replies are **not** held: a program that asked a question and waits for the answer must not be deadlocked by its own unfinished frame |
| `?2004` | bracketed paste is stored and reported; the execution is not (see §5.7) |
| `?2048` | in-band window-size reports: while on, a window resize whose shape differs from the last one this handle reported emits `CSI 8 ; rows ; cols t` through the same reply channel as a cursor-position report |
| `?9`, `?1000`, `?1002`–`?1006`, `?1015`, `?1016` | mouse tracking modes: stored one bit each, reported individually, cleared by `ESC c` but not by a soft reset, carried across a rebuild, and since #95 the console's own mouse bit is genuinely armed (with the host's quick-edit mode cleared) — **but this renderer never generates a mouse report** (§5.7) |
| `?1001` | recognised and refused, with its own counter |

### 2.6 Attributes

| Code | Behaviour |
|---|---|
| `0` | reset to the frozen default, including default colours |
| `1` / `2`, `22` | bold on/off — bold participates as *brightening*, the xterm-family meaning |
| `4` / `24` | underline, drawn |
| `5`, `6`, `25` | blink: no state at all — the attribute word this library writes to the console has no blink bit |
| `7` / `27` | reverse video, drawn |
| `3`/`23`, `9`/`29` | italic and crossed-out: kept in the model, nothing drawn (the console attribute has no bit; the legacy parser has the same gap) |
| `30`–`37`, `90`–`97`, `40`–`47`, `100`–`107` | the standard and bright sixteen |
| `38;5;n` / `48;5;n`, `38;2;r;g;b` / `48;2;r;g;b` | 256-colour and 24-bit, applied **through the console's own palette fold** — a deliberate property, not a loss of fidelity |
| `39` / `49` | default foreground / background |
| `38:2::r:g:b`, `38:5:n`, `4:n`, `58:` | colon subparameters are parsed and applied (the colour arms land where the semicolon spellings do; `4:0`/`4:1` underline, `4:2`–`4:5` count the style that cannot be drawn; `58:` is consumed so its numbers cannot be misread) |
| `CSI m` with no parameters | a reset |
| `CSI ?…m` | the whole sequence is dropped and counted — a private prefix on an SGR is not a partial request |

### 2.7 Cursor shape and soft reset

| Sequence | Behaviour |
|---|---|
| `CSI Ps SP q` (DECSCUSR) | 1–6 are remembered. Where the console offers a real shape API, blinking-underline and steady-bar take the shape door; everywhere else 1/2 fold to a tall block and 0/3–6 to a thin underline, and 5/6 are counted as styles that cannot be drawn. Only one door opens per cursor. A session that never asked touches neither |
| `CSI !p` (DECSTR) | soft reset: pen, region, cursor visibility, autowrap, synchronised-output region and all four character sets are restored, the shift is undone — and the screen, the cursor position, the margins and the alternate buffer are left alone. A fresh grid claims no cursor shape, so a user's own setting survives a session that never asked |
| the `SP q` and `!p` guards | the intermediate must be exactly that one byte: `CSI ? SP q`, `CSI ! SP q` and a run of spaces are refused rather than mistaken for the real thing |

### 2.8 OSC

| Code | Behaviour |
|---|---|
| `0`, `1`, `2` | the window title really lands, with the console's own guard (digits must be followed by `;`, payload non-empty), one pair of surrounding quotes stripped; over-long titles are truncated and counted, not dropped |
| `4`, `10`, `11`, `104`, `110`, `111` | the palette: set and query index colours and the default foreground/background. Accepts `#RGB`/`#RRGB`/`#RRGGBB`/`#RRRRGGGGBBBB`, `rgb:r/g/b`, and **676 X11 colour names**; indices 0–15 change the console's own attribute colours, 16–255 the fold's targets; `?` queries answer with the *effective* colour |
| `9;4`, `9;9`, `9;12` | the safe part of the private family is **stored, never obeyed**: taskbar state and progress, a working directory, and `9;12` handled as a prompt-start mark. Both stored values are readable by the application; nothing is executed |
| `52` | clipboard write, **off by default** and switchable only by the host program, never by the byte stream; strict base64 (whole payload or nothing, no whitespace, no hidden bits in the padding, no embedded NUL), one clipboard so only the `c`/empty selection is honoured, and an **empty payload means clear**. A read (`52;c;?`) is refused outright |
| `133` | semantic prompts: `A N P L B I C D`, with the exit code on `D` and `k=v` options recognising a continuation; a line feed or a wrap promotes an output row to a continuation. The marks are model-private and travel with vertical movement |
| anything else | counted in the "other OSC" family; ConEmu's private `9` subcommands with side effects (`1` sleep, `2` message box, `3` environment, `6` macro, `7` process) are counted and **never executed** |

### 2.9 Queries and replies

A query is queued while parsing and answered after the screen is on the console, written back as console input
events on the same channel the console itself uses — which is the only way this library can speak to a program
without owning its input handle. A declined chunk answers nothing (its bytes went to the console, which answers
for them).

| Query | Answer |
|---|---|
| `CSI 5 n` | `CSI 0 n` |
| `CSI 6 n` | `CSI row ; col R`, one-based, measured from the window top, reporting the cursor **as it stood when the question was read** |
| `CSI c`, `CSI 0 c` | the console host's own primary identification, minus the clipboard bit — one session must not present two identities |
| `CSI > c`, `CSI > 0 c` | the console host's secondary identification |
| `OSC 4;i;?`, `OSC 10;?`, `OSC 11;?` | the effective colour, as `rgb:RRRR/GGGG/BBBB` |
| `CSI ? N $ p` (DECRPM) | `CSI ? N ; status $ p` with DEC's own pair — 1 set, 2 reset — and **only** for state the model actually holds: cursor visibility, the three screen modes, autowrap, insert, origin, margins, bracketed paste, synchronised output, in-band size, and each of the nine mouse numbers. Nothing is ever answered "permanently set" or "permanently reset" |

### 2.10 Text: width, glyphs, wrapping

| Property | Behaviour |
|---|---|
| Width source | tables generated from **Unicode 15** with measured overrides, one oracle for the whole stack (the renderer, the printer and the terminal's own line editor all ask the same function); combining and format characters take no cell — the console's own habit of giving a combining mark a cell is deliberately not followed |
| East Asian Ambiguous | counted as **wide**, minus 206 code points measured at one cell across six real fonts; no variation-selector promotion |
| Wide glyphs | two cells, a leading and a trailing half carrying the same code point; a pair that does not fit wraps whole and is never split |
| Supplementary planes | surrogate pairs are reassembled before measuring and written back unchanged; a high surrogate at a chunk boundary is completed on the next write; a lone low surrogate becomes one replacement cell |
| Pair integrity | no operation — erase, fill, insert, delete, or an ordinary glyph over a wide glyph's head — may leave one half standing; the orphan is blanked, and a validator plus a per-chunk grid oracle watch it |
| Wrapping | immediate, with one bit per row recording a soft break so copy and export can join rows; no deferred-wrap state exists (§5.8) |

### 2.11 Tabs

One claim per column plus one flag for "nobody has set stops, use the interval". Defaults are every eighth column —
not column 0, not the last column. `ESC H` claims the cursor's column; `CSI 0g` clears that column, `CSI 3g`
clears the table **and** the interval; `CSI 5g` restores the interval; `CSI Ps I`/`CSI Ps Z` walk forward and back
without ever changing rows. One table serves the main and alternate screens; a rebuild fills the interval only in
columns that did not exist before, so an application's own stops survive. `RIS` restores the interval, `DECSTR`
does not touch the table.

---

## 3 Refused, and what the references do

Each row: this build's verdict, then microsoft/terminal / wezterm / ghostty, then which of the four reasons
carries it.

### 3.1 Character sets and the C1 half

| Item | Here | msfterm | wezterm | ghostty | Reason |
|---|---|---|---|---|---|
| GR, the 8-bit set half | slots load, nothing can select them | yes | yes | yes | **no carrier** — a UTF-16 path produces no C1 and no 8-bit text |
| LS2/LS3/LS1R/LS2R/LS3R | refused | yes | yes | yes | **no carrier** — those are C1 controls |
| `ESC % G` (UTF-8 / Latin-1 selection) | refused, counted | yes | yes | yes | **no carrier** — input is UTF-16 before the grid |
| SS2 / SS3 single shifts | introducer only, next byte prints | no output-side arm | parses | parses | **no carrier** — the only drawable set is already selectable by `SO`/`SI` |

### 3.2 Attributes

| Item | Here | msfterm | wezterm | ghostty | Reason |
|---|---|---|---|---|---|
| blink (`5`/`6`) | no state | no state in the console path | stores, draws | stores, sometimes draws | **no carrier** — the console attribute word has no blink bit |
| invisible (`8`), overline (`53`), double underline (`21`), framed/encircled (`51`/`52`), underline colour (`58`) | skipped / consumed | some | most | most | **no carrier** for the same reason; `58` is at least parsed so its numbers cannot leak |
| italic, crossed-out | stored, never drawn | stored, not drawn | drawn | drawn | **no carrier** in the console attribute; the model keeps the state so `23`/`29` behave |
| push/pop the rendition (`#{`/`#}`) | refused | **yes** | no | no | **GAP** (§6) — a stack of stored attributes is representable |

### 3.3 Modes

| Item | Here | msfterm | wezterm | ghostty | Reason |
|---|---|---|---|---|---|
| `?1` application cursor keys, `?12`, `?8`, keypad and meta-key modes | refused | yes | yes | yes | **no carrier** + **conflicts with #95** — these change how keys are produced, and this renderer owns no input encoding; the input queue belongs to the reader already using it |
| `?3` 132 columns, `?40` | refused | yes (only with `?40`) | yes | yes | **floor** — it means resizing the user's window |
| `?5` reverse video | refused | yes | yes | yes | **GAP** (§6) — a palette path exists here; which inversion is the truth has to be decided |
| `?45` reverse wraparound | refused | no | yes | yes | **conflicts with the wrap model** (§3.8) |
| `?1007` alternate scroll | refused | yes | no | yes (on by default) | **no carrier** / **conflicts with #95** — it rewrites wheel events |
| `?2005` background-colour erase | refused | no | no | no | **conflicts with the advertised `bce`**: this session's erases fill with the live attribute, which is the opposite contract |
| `?2027` grapheme-cluster mode | refused and unanswered | empty case, but answered "permanent" | answered "permanent" | the real text engine | **no carrier** (width is a table lookup) + **would lie** (answering permanent would claim a capability the grid does not have) |
| `?2031`, `?2033`, `?5522`, `?7727`, `?2094`, `?8005`, `?8452` | refused | partly | `9001`, `8452` | `2031`, `2033`, `5522` | **no carrier** / **floor** — these report a window theme, a graphics plane or a paste pipeline this library does not own |
| save/restore a mode (`?Ns`/`?Nr`) | refused | no | warns | yes (one deep) | **GAP** (§6) — every mode it would save is real state now |
| the remaining private and ANSI modes, and GATM/LNM | refused, counted | — | — | — | derived by reading the baseline parser, and re-argued since: LNM is print *echo* (**no carrier**, no input handle), and IRM was once refused with an implementation-shaped sentence and has since been built (#77) |

### 3.4 Erase and rectangular operations

| Item | Here | msfterm | wezterm | ghostty | Reason |
|---|---|---|---|---|---|
| selective erase (`?J`/`?K`) with protection bits | the private byte is ignored: both spellings erase everything | yes, with per-row protection | no (its own code says so) | yes, with DECSCA | **no carrier** while no sequence can protect a cell — and stated with its expiry: if protection ever lands, the selective forms must land with it |
| `CSI 3J` (erase scrollback) | behaves as `2J` | yes | yes | yes (and its own `22J`) | **floor** — the history is the console's; the user's scrollback is not this library's to delete |
| rectangular operations (copy/fill/erase/select-area, insert/delete columns, character-attribute changes, the rectangle checksum) | refused | the full family | the checksum | no | **GAP** (§6) — real work on a grid with a gutter, a viewport, wrap claims and wide pairs; effort, not impossibility |
| the `W` tab-control family | refused (the `5g` spelling works) | registers DECST8C as `?W` | parses `5g`, ignores it | acts on `?5 W`, no `5g` | **GAP** (§6) — the references disagree with each other, so the choice has to be made on its own terms |
| resize the page from the stream (`DECSLPP`) | refused | partly | partly | partly | **floor** — an output library must not resize a user's window from a byte stream |

### 3.5 Reports this build does not answer

| Item | Here | msfterm | wezterm | ghostty | Reason |
|---|---|---|---|---|---|
| `CSI ? 6 n` (extended cursor report) | **refused on purpose** | answers | no | no | **would lie**: answering the plain question with the extended spelling reports a position nobody asked for, and the two forms are not interchangeable |
| `14t` / `16t` (pixels), `19t` (screen cells) | silence, counted | answers 14/16/18 — and its own 14t is a *nominal* cell chosen for graphics emulation, not a measurement | answers 14/16/18 | answers 14/16/18 | **floor** + **would lie**: the only reachable pixel figure is a font metric times a cell count, and one geometry has one name here |
| `20t` (icon), `21t` (report the title) | refused | no | answers behind a config flag | answers behind a config flag | **GAP**, small (§6) — the title string is held, so 21t could be answered honestly today |
| device-status reports beyond 5/6, terminal-parameter request, answer-back | refused | answers most of them | 5/6 only | answers its own two private requests | **would lie** — each states a fact about a device this library is not |
| termcap query, set-terminal-mode query, terminal-version query | refused | version/mode: partly, kitty family yes | termcap and set-mode query yes | termcap, set-mode query and version query yes | termcap: **would lie** (the capability table this session really has is the terminfo entry — see `terminfo/TERMINFO.md`; two sources for one table is how they drift). Set-mode query and version query: **GAP** (§6) |
| a mode number the model does not hold | silence | **always answers**, status 0 for unknown | answers 0 for unknown | full 0–4 vocabulary | **would lie** — this is a deliberate split from all three: an answer of 0 is a claim about the asker's list, and jline's own reader scores 1, 2 and 3 alike, so a wrong convention here is invisible to the one reader in the house |
| window-size report contents (`?2048`) | sends rows and columns only; never answers "permanently set"; does not reply at the moment of enabling | no such mode | no such mode | sends rows, columns and pixel sizes, and replies once on enable | **floor** — pixels cannot be proven here, and a report is bytes the program did not write |

### 3.6 Graphics and the payload protocols

| Item | Here | msfterm | wezterm | ghostty | Reason |
|---|---|---|---|---|---|
| DCS / SOS / PM / APC payloads | framed, consumed, discarded whole, counted | kept for its own graphics and query protocols | kept, with a parser that recognises them | kept, with its own extensions | the container works; the protocols below do not have a surface |
| Sixel | refused | **yes, fully** | **yes** | no | **no carrier** in the seam — there is no pixel plane in front of a buffer this library does not own. Note honestly that msfterm proves it is possible in a Windows console stack, and that this build's primary identification string is inherited from the console host (it is the host's identity, not a claim this renderer makes) |
| kitty graphics / iTerm2 images | refused | no | **yes** | **yes** (large payloads allowed) | **no carrier**, same reason |
| a multiplexer's passthrough control mode, terminal-private extensions | refused | no | no | yes | **no carrier** — there is no peer to pass bytes to and no window to attach an extension to |

### 3.7 The input side: mouse, paste, keys

| Item | Here | msfterm | wezterm | ghostty | Reason |
|---|---|---|---|---|---|
| mouse **reports** from the tracking modes | modes stored, answered, carried, and the console's mouse bit genuinely armed; **no report byte is ever generated** | X10, UTF-8, SGR, focus events | X10, SGR, pixel-SGR, focus | X10, SGR, urxvt-style, focus; encodings mutually exclusive | **conflicts with #95**: the reports would enter the same console input queue the application's own reader pumps, and a second reader starves the first. Answering `?1000$p` = set is a claim about a bit the model holds — it is **not** a claim that events will arrive, and the row says so because the two were once conflated |
| bracketed paste `?2004` | stored and reported, **not** executed | executes | executes | executes | **no carrier** + **conflicts with #95** — the markers are bytes injected into the input stream |
| a modified-key protocol (progressive enhancement, kitty keyboard flags) | refused | set/query family yes | yes, behind a switch that defaults off | yes | **no carrier** + **conflicts with #95** — the key bytes are produced by the input leg, and this library must not read that queue |
| the terminfo capability for the mouse key | deliberately **not** advertised | — | — | — | see `terminfo/TERMINFO.md`: the reader-side test is a capability lookup, but the Windows input leg arms the console directly and the mouse byte prefix is bound either way, so declaring it would name bytes whose sender is somebody else |

### 3.8 The wrap model

| Item | Here | msfterm | wezterm | ghostty | Reason |
|---|---|---|---|---|---|
| deferred (pending) wrap | not implemented — the cursor leaves the last cell the moment it is filled | yes | yes (it drives reflow) | yes (an erase form exists precisely to ask "not pending?") | **conflicts with the wrap claim**: moving to pending wrap changes what a row's soft-break bit means, and every line-ownership and copy/export rule reads that bit. And the measurement this rests on was taken **against the replaced baseline's two write paths, not against the three references** — that limitation is part of the row, not a footnote |
| double-width / double-height lines, screen alignment test | refused (and see §6: one spelling of this family currently does something else) | yes | yes | yes | **conflicts with §6's geometry floor**: a doubled row changes what the viewport is |

---

## 4 Where this build deliberately differs from the console host it replaced

Recorded so nobody "fixes" it back. Each has its own argument in the ledger.

1. An `ESC` inside a half-read sequence abandons and restarts it, instead of being absorbed as a parameter byte.
2. A resumable parser instead of a re-parse window, so a split sequence continues rather than being dropped.
3. Parameter values saturate rather than overflow.
4. ECH erases one row; the baseline walked down through the following rows.
5. IL/DL are bounded by the region; the baseline wrote past its bottom.
6. IND/RI/NEL agree about which rows scroll; the baseline's forward line feed ignored the region.
7. Region clamping uses model coordinates, not absolute buffer rows.
8. Query identities are the console host's strings, so a chunk handed back to the host and a chunk answered here
   do not present two different terminals.
9. A surrogate pair keeps its own units on the way out, and the repeated glyph is stored as a full code point.
10. A scroll region that spans the whole viewport is stored as "no region"; setting a region does not home the
    cursor; a one-row region is accepted. Two of these three agree with the references against the baseline; the
    third is a consequence of a status bar asking for it.
11. Writing the console's extended info struct back can cost a viewport row; every path that sets colours
    re-reads and repairs the geometry, and any new feature writing through it must do the same.

---

## 5 Limits

| Limit | Value | Past it |
|---|---|---|
| grid width / height | 4096 × 256 | the renderer refuses to engage and the application keeps its existing writer |
| parameters per sequence | 16 | surplus dropped and counted |
| parameter value | 65535 | saturates |
| title length | 256 | truncated, counted, and the title still applies |
| OSC/DCS payload collected | 32768 units | a title is truncated and applied; a clipboard payload is refused whole (half a base64 string is not a message) |
| clipboard decoded size | 12288 bytes (16384 encoded) | refused whole |
| queued replies | 64 | a full queue refuses the **new** question and counts it; nothing already asked is dropped. The depth used to be 8, and the nine-member mouse family is what proved it wrong — no reference implementation drops an answer |
| title stack | 2 deep | a third push evicts the oldest |

---

## 6 GAP list — missing work, not arguments

These are the refusals from §3 that cannot name one of the four allowed reasons. Ordered by what a program can
actually trip over.

| # | Missing | Who has it | What it would take | Landed? |
|---|---|---|---|---|
| G1 | **`ESC # 8` is executed as "restore cursor" instead of the screen-alignment test.** A discarded intermediate byte, not a missing feature — the byte sequence the application sent produces an act it did not ask for | all three act on the family | give the `#`-prefixed forms their own arms and count the rest. This is a defect, listed first | ✅ **-54**. `esc_dispatch`'s `#` arm no longer discards the intermediate: `screen_alignment` (`Render.cpp:2421`) fills the viewport with `E` at the *default* attribute and clears region/margins/origin, following MSFT `adaptDispatch.cpp:3143-3162`, wezterm `performer.rs:652-673`, ghostty `Terminal.zig:3714-3782`. Red arm `decaln` → host `fails=3` |
| G2 | **`OSC 7` (working directory)** is refused while the private family's equivalent **is** stored | all three | one more owner of a field that already exists and is already readable | ✅ **-54**. `osc_cwd7`/`osc_is_cwd7` write the *same* `cwd` field `9;9` owns (family-table row; the field index is **0**, not 1). MSFT `adaptDispatch.cpp:2621-2637`, wezterm `performer.rs:940-944`, ghostty `stream_terminal.zig:1527-1545` |
| G3 | **push/pop the rendition** — spelled `CSI # {` / `CSI # }` (**not** `ESC # {`, which an earlier draft of this table said) | microsoft/terminal only | a stack of stored attributes, plus the rebuild-carry obligation, plus what a reset does to a non-empty stack | 🔲 open. Spec now pinned from source: MSFT `src/types/inc/sgrStack.hpp:51` ring of 10 (`c_MaxStoredSgrPushes`), overflow drops the *oldest* (`sgrStack.cpp:48-54`), pop-on-empty returns the **current** attributes not the defaults (`:86`), entry = `TextAttribute` + a `ValidParts` bitset (`:60-64`), options enum `DispatchTypes.hpp:479-493` (`All=0 … SaveBackgroundColor=31`), aliases `CSI # p`/`CSI # q` (`OutputStateMachineEngine.hpp:148-151`), **neither RIS nor DECSTR clears it** (`SoftReset` at `adaptDispatch.cpp:2984-3020` and `HardReset` at `:3042-3096` contain no `_sgrStack` — the member name appears in exactly three places tree-wide: `adaptDispatch.hpp:337`, `adaptDispatchGraphics.cpp:467`, `:479`), and it hangs off the *adapter* (`adaptDispatch.hpp:337`) so a renderer rebuild cannot lose it. ghostty and wezterm: **0 hits** with named controls. No query obligation — there is no DECRQM number for it |
| G4 | **save/restore a mode** | ghostty only (wezterm parses then warns; msfterm has no `?s`/`?r` key at all) | a mode-bit store whose later query answer follows the restored bit | 🔲 open. Spec pinned: **one bool cell per mode, not a stack** — `modes.zig:17-25` "We only allow saving each mode once … we need to be aware of a DoS vector"; restore **re-enters `setMode`** so side effects fire (`stream_handler.zig:281-287`); `?` is an *intermediate* so `CSI ? s` and `CSI s` are different productions (`stream.zig:2332-2336`); multiple numbers per message are legal (`:2334` loop); **restore of a never-saved mode writes `false`, not the default** (`modes.zig:299` default is false for every entry); RIS clears the saved cells (`Terminal.zig:4933` → `modes.zig:33-36`), and DECRQM reads `values`, never `saved` (`:98-101`) |
| G5 | **set-mode query and terminal-version query** (a question about this model's own state) | ghostty, wezterm | the reply channel already exists; these answers are facts, not inventions | ◐ **-54** for the version query: XTVERSION `CSI > q` answers `RENDER_BUILD` (`RC_REP_XTVER`; ghostty `stream_terminal.zig:1442-1447`, wezterm `mod.rs:1440-1447` + `csi.rs:2224-2233`). The *set-mode* half is G11's answer-0 rule, landed the same build |
| G6 | **report the window title** | wezterm, ghostty (both gated) | the string is held, so the answer would be true | ✅ **-54**. `21t` → `RC_REP_TITLE`, answered `\E]l<title>\E\\` (ghostty `stream_terminal.zig:1468-1471`, wezterm `mod.rs:2175-2183`; msfterm has no `Ps t` family) |
| G7 | **reverse video as a mode** | all three | ~~a carrier exists — the palette path~~ **that sentence was wrong and is retracted** | 🔲 open, and now more expensive than it looked. The palette path maps *index → RGB*; reverse video swaps *roles* (low nibble drawn as fg, high as bg), and no permutation of `pal16` moves a nibble between roles — so the carrier this row pointed at does not exist. All three fold at **readout**, never in storage: MSFT `RenderSettings.cpp:193` `attr.IsReverseVideo() ^ GetRenderMode(Mode::ScreenReversed)` then `std::swap(fg,bg)` on resolved COLORREFs, with `TriggerRedrawAll()` on toggle (`adaptDispatch.cpp:1787-1793`); wezterm `screen_line.rs:218-222` same XOR shape with the flag carried in the quad-cache key (`render/pane.rs:426-443`); ghostty swaps only the **defaults** (`render.zig:450-456`) so explicitly-coloured cells are exempt — the three do *not* agree about 256/RGB cells. This library stores the folded `CHAR_INFO` attribute in the cell itself (`Render.cpp:1367`, copied verbatim at `RenderJni.cpp:599`) and re-imports the host's attributes on adopt (`:2207`), so a parse-time XOR is wrong twice over. Doing it honestly means moving the fold to the seam **and** re-marking the viewport on toggle (`rc_mark_all_dirty`, `Render.cpp:196`, is the existing analogue of `TriggerRedrawAll`) — which collides head-on with #103's differential and #99/#101's adopt path, on the owner's named high-priority surface (colour). Cost stated, therefore not free |
| G8 | **the rectangular-edit family**, and the two single-line shift controls that go with it | microsoft/terminal mostly | effort: each shape has to re-derive pair healing and line ownership over a rectangle | 🔲 open — work, not impossibility |
| G9 | **selective erase's other half** — the protection bits | msfterm, ghostty | must arrive *with* G8's selective forms, or the equivalence claimed in §3.4 stops holding | 🔲 open. DECSCA is a **cell bit** in conhost (`adaptDispatchGraphics.cpp:440-456 attr.SetProtected`) and `CHAR_INFO` has no such bit (`conattrs.hpp:9`, read exhaustively this round), so it needs a shadow array beside the grid or it becomes a lie |
| G10 | **the tab-control family** | microsoft/terminal (`?W`), ghostty (`?5 W`) | pick a spelling with a reason; the references disagree | ✅ **-54** for DECST8C: `CSI ? 5 W` → `tabs_reset` (`case 'W'`). MSFT `OutputStateMachineEngine.hpp:116 → adaptDispatch.cpp:2784-2792`, ghostty `stream.zig:1811-1816 → Terminal.zig:2308-2310`; wezterm 0 hits |
| G11 | **the device-status and capability probes this library could answer truthfully** | microsoft/terminal widely, ghostty partly | answer only what the model holds; the rest stays §3.5's "would lie" | ✅ **-54**. A number the state table names no value for answers **0 = not recognised** instead of staying silent (`Render.cpp:2197`; MSFT `adaptDispatch.cpp:1939` + `DispatchTypes.hpp:552-559`, ghostty `modes.zig:80-102`, wezterm `mod.rs:1520-1526`). This moved `?1048`/`?12`/`?2027` off the silence list |

**Not gaps.** Images and sixel (no pixel plane in front of a buffer we do not own); hyperlinks (an owner decision:
a link is a range, not a cell, and the sequence alone buys a user nothing); the side-effecting private commands
(safety: the only floor under executing stream-supplied semantics is not executing them); pixel geometry reports
(quantifying a window this library does not own would be a fabricated measurement); the termcap query (two sources
for one capability table); background-colour erase and reverse wraparound (each conflicts with a contract this
session already advertises); **bracketed-paste execution and key-encoding behaviour** (both wait on who owns the
input queue). ⚠ **Mouse reports left this list on 2026-09-28** — the third owner ruling struck "wait on #95's
ownership decision" as an invalid reason, and the encoder plus the shared injection line shipped in -54 (§3.7 and
`ANSI_TODO.md` §5's mouse row). What still sits outside this library is only *who hands a record to it*.

---

## 7 What the three references disagree about, and what this build chose

| Question | msfterm | wezterm | ghostty | This build |
|---|---|---|---|---|
| Mode query for an unknown number | answers, status 0 | answers, status 0 | answers with the full permanent/unknown vocabulary | **answers, status 0** (since -54; this cell used to read "silent", which was the deviation — see §6 G11) |
| Scroll region: one-parameter form | fills the missing edge | fills it | fills it | fills it (the baseline it replaced cleared the region — a divergence from all four) |
| Inverted region pair | ignored | ignored | ignored | ignored (same) |
| Tab interval reset spelling | `?W` | parses `5g`, ignores it | `?5 W` | `5g` |
| Character-set: which set GL holds by default | G0 | G0 | G0 | G0, and the shift is the only visible half of a designation |
| Repeat-last-grapheme stores what | the last printable | the last printable | the last printable | the last unit **with width**, so an accent after a letter cannot erase the thing worth repeating |
| Cursor position report with a region or origin mode set | reports the cursor | reports the cursor | reports relative to origin mode when it is set | reports the viewport cursor, as a snapshot taken when the question was read |
| Clipboard read request | parsed and dropped | parsed and dropped | answered, gated on a prompt | refused |
| Clipboard write permission | a user setting | no gate | a user setting, default allow | **default off, host-only** — this library is inside someone else's process and has no party who consented |

---

## 8 What is counted when something is refused

Slot names and order are a stable interface between the renderer and its callers; nothing here is renumbered. A
count is how a program can tell "not supported" from "silently did something else", and the census is the reason
the refusals in §3 are reviewable at all.

| Counter | Fires when | also marks the model suspect |
|---|---|---|
| unrecognised | a CSI or ESC final with no case at all | yes |
| alternate buffer | the alternate-screen snapshot could not allocate | no |
| mouse | a tracking mode is asked for and stored (§3.7) | no |
| mode | a mode this model holds no state for, a private prefix on an SGR, `ESC g`/`=`/`>` | no |
| bracketed paste | an OSC request to *execute* a paste | no |
| private OSC | the side-effecting private family | no |
| other OSC | any code no family owns, an unterminated title, an unreadable colour field | no |
| DCS | any DCS/SOS/PM/APC payload | no |
| report | a question this build will not answer (§3.5) | no |
| colon | an arm of a parsed colon sequence that cannot be carried here | no |
| clipboard refusal | policy off, an unknown selection, a bad decode, over size — or a read | no |
| character set | a designator naming a set this build cannot draw | no |

Alongside them: title sets and truncations, clipboard sets and refusals, alternate-screen switches and failures,
report successes and failures, prompt marks, the six synchronised-output tallies (engages, nesting, held frames,
timeouts, gutter overflows, declines), the parameter-truncation count, the bracketed-paste bit and the cursor-shape
door a handle actually has. One rule binds them all: **a count is not a policy** — a refusal that would take input
away from the user is gated on the host program, not on a counter.

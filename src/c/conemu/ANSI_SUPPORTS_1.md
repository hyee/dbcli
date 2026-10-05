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
| `ESC # 8` | DECALN, the screen-alignment test | the viewport is filled with `E` at the *default* attribute, and the scroll region, the margins and the origin mode are cleared with it, because a test pattern and a half-set geometry cannot both be true. Rows above the viewport are not touched. An earlier build read these three bytes as restore-cursor and moved the pointer on a sequence that asked for nothing |
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
| `CSI Pt;Pl;Pb;Pr;Ps $ x` | DECFRA | fills the rect with character Ps (0/absent = space; GL/GR/BMP only — anything else is counted, not painted) in the **live pen**, protection included (G8/G9)
| `CSI Pt;Pl;Pb;Pr $ z` | DECERA | the rect to blanks in the erase pen; non-selective, so protection does not survive it (G8/G9)
| `CSI Pt;Pl;Pb;Pr $ {` | DECSERA | the selective twin: unprotected cells lose their text and keep their attributes (G8/G9)
| `CSI Pt;Pl;Pb;Pr;Ps;Pt2;Pl2;Ps2 $ v` | DECCRA | copies the rect to the destination sized by the source and clipped by the page; the walk runs backwards when the destination is beyond the source, so a copy onto itself arrives whole; page parameters are consumed and dropped (one page)
| `CSI Ps }` / `CSI Ps ~` | DECIC / DECDC | insert/delete columns within the region's rows and the right margin, at the cursor; refused outright for a cursor outside the margins; the cursor does not move
| `CSI ? Ps J` / `CSI ? Ps K` | DECSED / DECSEL | the selective twins of ED/EL: same three geometries, unprotected text goes, attributes stay, protected cells are untouched (and no 2J-style cursor home for the selective form) |

### 2.5 DEC private modes

Only the first parameter of a `h`/`l` list acts, matching the baseline parser.

| Mode | Behaviour |
|---|---|
| `?25` | cursor visibility |
| `?47`, `?1047`, `?1049` | the alternate screen — one behaviour for all three spellings. Entering snapshots the main viewport (wrap claims included) and clears; leaving restores; the alternate screen has no scrollback, and leaving without entering is harmless |
| `?1048` | save / restore the cursor |
| `?7` | DECAWM, autowrap: on wraps at the right margin; off, the last cell is overwritten in place, the row takes no wrap claim, no row below is started, and a glyph that cannot fit is dropped whole rather than split |
| `?4` and `4` | IRM, insert mode: an ordinary written glyph opens room for itself. One bit, both spellings, reportable either way; where the glyph would not fit strictly inside the row it overwrites instead |
| `?1` | DECCKM, application cursor keys: stored, answered by number, cleared by `ESC c` and by a soft reset, and carried across a rebuild (#114). It changes no key bytes here — the encoding belongs to the input leg (§3.7) — so this is state the model really holds, not a promise about what a keystroke will produce |
| `?6`, `?69` | origin mode and the margin gate — see §2.4 |
| `?2026` | synchronised output: while open, nothing is written to the console and damage accumulates; the closing reset paints one union frame. Three ways out — the end sequence, a 100 ms timeout that also clears the mode, and a full scrollback gutter (that frame must land, but the region stays open). Query replies are **not** held: a program that asked a question and waits for the answer must not be deadlocked by its own unfinished frame |
| `?2004` | bracketed paste is stored and reported; the execution is not (see §3.7) |
| `?2048` | in-band window-size reports: while on, a window resize whose shape differs from the last one this handle reported emits `CSI 8 ; rows ; cols t` through the same reply channel as a cursor-position report |
| `?9`, `?1000`, `?1002`, `?1003`, `?1005`, `?1006`, `?1015`, `?1016` | mouse tracking and encoding: one bit each, answered number by number, cleared by `ESC c` but not by a soft reset, carried across a rebuild, and the console's own mouse bit is genuinely armed (with quick-edit cleared). **The report encoding lives here**: five spellings (legacy X10, UTF-8 coordinates, SGR, urxvt, SGR-with-pixels) with the release, motion and no-press rules each one has, and the modifier byte that mode 9 does not take. **Since A1 (2026-10-05) the caller exists too**: dbcli's input pump hands each console record to this library's encoder through JNI and injects the bytes it returns, so the armed format is the format the reader receives |
| `?1004` | focus tracking: stored, answered, carried, and the encoder for `CSI I`/`CSI O` is here, and since A1 it is wired through the same injection channel as the mouse |
| `?1001` | recognised and refused, with its own counter |
| `CSI ? Ps s` / `CSI ? Ps r` (XTSAVE/XTRESTORE) | save/restore a mode, G4: one slot per mode (a second save overwrites), a restore of a mode nobody saved is **off** rather than unchanged, the restore re-runs the mode's act (2026's engage counters tick exactly as a DECSET's would), RIS clears the table and DECSTR keeps it. Saveable: 1, 4, 7, 25, 2004, 2048, 2026 and the five tracking bits — the formats are a last-wins field rather than a bit, and the modes whose acts move the cursor or the screen (6/69, the alt family, 1048) stay out on purpose. The bare `CSI ? r` keeps its DECSTBM-reset reading |

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
| `7` | the working directory: stored as text, readable by the application, **never obeyed** — this library owns no window and never changes the process's directory from an output stream. It writes the same field the private family's path report writes, so one value cannot disagree with itself |
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
| `CSI 18 t` | `CSI 8 ; rows ; cols t` — the text area, from the model's own viewport, in the columns it really paints |
| `CSI 21 t` | the window title this parser last applied, in the operating-system-command spelling the references use. A session that never set a title gets nothing, because the host's pre-session title is a value this library never observed |
| `CSI > q`, `CSI > 0 q` | XTVERSION: this library's own name and build stamp, sent as a device control string. The stamp is the same string a caller reads back out of the loaded library, so the answer cannot name a build that is not the one running |
| `OSC 4;i;?`, `OSC 10;?`, `OSC 11;?` | the effective colour, as `rgb:RRRR/GGGG/BBBB` |
| `CSI ? N $ p` (DECRQM) | `CSI ? N ; status $ p`, in DEC's vocabulary. **1** set / **2** reset for state the model holds (cursor visibility, application cursor keys, autowrap, insert, origin, margins, the three screen modes, bracketed paste, synchronised output, in-band size, and each of the nine mouse numbers). **3** permanently set / **4** permanently reset only where a fact about this build earns it — `?2` because there is no way to change that shape, `?3` because a visible width this library cannot set belongs to the user's console. **0** not recognised for any number the state table does not name, which is what all three references answer and what this build used to leave silent |

### 2.10 Text: width, glyphs, wrapping

| Property | Behaviour |
|---|---|
| Width source | tables generated from **Unicode 15** with measured overrides, one oracle for the whole stack (the renderer, the printer and the terminal's own line editor all ask the same function); combining and format characters take no cell — the console's own habit of giving a combining mark a cell is deliberately not followed |
| East Asian Ambiguous | counted as **wide**, minus 206 code points measured at one cell across six real fonts; no variation-selector promotion |
| Wide glyphs | two cells, a leading and a trailing half carrying the same code point; a pair that does not fit wraps whole and is never split |
| Supplementary planes | surrogate pairs are reassembled before measuring and written back unchanged; a high surrogate at a chunk boundary is completed on the next write; a lone low surrogate becomes one replacement cell |
| Pair integrity | no operation — erase, fill, insert, delete, or an ordinary glyph over a wide glyph's head — may leave one half standing; the orphan is blanked, and a validator plus a per-chunk grid oracle watch it |
| Wrapping | immediate, with one bit per row recording a soft break so copy and export can join rows; no deferred-wrap state exists (§3.8) |

### 2.11 Tabs

One claim per column plus one flag for "nobody has set stops, use the interval". Defaults are every eighth column —
not column 0, not the last column. `ESC H` claims the cursor's column; `CSI 0g` clears that column, `CSI 3g`
clears the table **and** the interval; `CSI 5g` restores the interval and so does the DECST8C spelling `CSI ? 5 W` (a bare `W`, or any other parameter, is refused: a control that wipes state needs a spelling with a reason); `CSI Ps I`/`CSI Ps Z` walk forward and back
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
| `?12` cursor blink, `?8` column mode, the keypad and meta-key modes | refused, and answered **0** as not recognised | partly | partly | partly | **no carrier** — `?12` wants a blink bit the attribute word does not have and `?8` a second column mode, while keypad and meta modes change how keys are *produced*, which §3.7 leaves with the input leg. (`?1` sat in this row; it became real state in #114 and moved to §2.5) |
| `?3` 132 columns, `?40` | refused, and the query for them answers **4** (permanently reset) | yes (only with `?40`) | yes | yes | **floor** — it means resizing the user's window, and this was measured rather than argued: a wider buffer changes no visible column, while widening the visible width moves the user's own window, so there is no third thing the reply could honestly say |
| `?5` reverse video (`DECSCNM`) | refused | yes | yes | yes | **conflicts with #103, #99 and #101** — the folded attribute is stored *in the cell* and the host's attributes are re-imported on an adopt, so a screen-wide inversion has to move the fold into the paint seam and re-mark the whole viewport on every toggle — which is exactly the differential those three items exist to protect, on the surface a user notices colour on. The references do not agree with each other about what the mode does to explicitly-coloured cells either, so there is no free side to take. This row was listed as a GAP, and the carrier it pointed at does not exist: an index-to-colour table cannot swap the two nibble roles |
| `?45` reverse wraparound | refused | no | yes | yes | **conflicts with the wrap model** (§3.8) |
| `?1007` alternate scroll | refused, answered 0 | yes | no | yes (on by default) | **owner decision #116** — it rewrites wheel events into line feeds, and the queue those events arrive on belongs to whoever reads the console records |
| `?2005` background-colour erase | refused | no | no | no | **conflicts with the advertised `bce`**: this session's erases fill with the live attribute, which is the opposite contract |
| `?2027` grapheme-cluster mode | refused, and the query answers **0** (not recognised) | empty case, answered | answered | the real text engine | **no carrier** (width is a table lookup) + **would lie** — answering 1/2/3/4 would claim a capability the grid does not have; 0 claims only that this build does not know the number, which is true |
| `?2031`, `?2033`, `?5522`, `?7727`, `?2094`, `?8005`, `?8452` | refused | partly | `9001`, `8452` | `2031`, `2033`, `5522` | **no carrier** / **floor** — these report a window theme, a graphics plane or a paste pipeline this library does not own |
| save/restore a mode (`?Ns`/`?Nr`) | refused | no | warns | yes (one deep) | **GAP** (§6) — every mode it would save is real state now |
| the remaining private and ANSI modes, and GATM/LNM | refused, counted | — | — | — | derived by reading the baseline parser, and re-argued since: LNM is print *echo* (**no carrier**, no input handle), and IRM was once refused with an implementation-shaped sentence and has since been built (#77) |

### 3.4 Erase and rectangular operations

| Item | Here | msfterm | wezterm | ghostty | Reason |
|---|---|---|---|---|---|
| selective erase (`?J`/`?K`) with protection bits | **selective since G9 (2026-10-05)**: unprotected cells lose their text and keep their attributes, protected cells are untouched; with nothing protected both spellings are exactly their plain twins | yes, with per-row protection | no (its own code says so) | yes, with DECSCA | the expiry clause fired: protection landed (DECSCA pens a shadow bit beside the grid), and the selective forms landed with it, as the row demanded |
| `CSI 3J` (erase scrollback) | behaves as `2J` | yes | yes | yes (and its own `22J`) | **floor** — the history is the console's; the user's scrollback is not this library's to delete |
| rectangular operations (copy/fill/erase/select-area, insert/delete columns) | **modelled since G8+G9 (2026-10-05)**: DECFRA/DECERA/DECSERA/DECCRA (`$ x/z/{/v`), DECIC/DECDC, with the rect calculator honouring origin mode and the edges, direction-correct overlap copying, and pair healing at every rect edge; character-attribute rects (DECCARA/DECRARA) and the checksum (DECRQCRA) stay refused — wezterm-only and msft-only respectively | the full family | the checksum | no | the §6 row is closed; the two sub-forms nobody else has stay out for the reason they always had |
| resize the page from the stream (`DECSLPP`) | refused | partly | partly | partly | **floor** — an output library must not resize a user's window from a byte stream |

### 3.5 Reports this build does not answer

| Item | Here | msfterm | wezterm | ghostty | Reason |
|---|---|---|---|---|---|
| `CSI ? 6 n` (extended cursor report) | **refused on purpose** | answers | no | no | **would lie**: answering the plain question with the extended spelling reports a position nobody asked for, and the two forms are not interchangeable |
| `14t` / `16t` (pixels), `19t` (screen cells) | silence, counted | answers 14/16/18 — and its own 14t is a *nominal* cell chosen for graphics emulation, not a measurement | answers 14/16/18 | answers 14/16/18 | **floor** + **would lie**: the only reachable pixel figure is a font metric times a cell count, and one geometry has one name here |
| `20t` (report the icon name) | refused | no | refused | refused | **no carrier** — there is no icon, and answering with the title would invent a second identity for one string. (`21t` landed since; see §2.9) |
| device-status reports beyond 5/6, terminal-parameter request, answer-back | refused | answers most of them | 5/6 only | answers its own two private requests | **would lie** — each states a fact about a device this library is not |
| termcap query | refused | partly, kitty family yes | yes | yes | **would lie** — the capability table this session really has is the terminfo entry (see `terminfo/TERMINFO.md`), and two sources for one table is how they drift. The set-mode query and the version query both answer now (§2.9) |
| a mode number the model does not hold | answered **0** = not recognised | always answers, status 0 for unknown | answers 0 for unknown | full 0-4 vocabulary | the four now agree. The silence this row used to keep was the deviation, and it was invisible to the one reader in the house, because that reader scores 1, 2 and 3 alike |
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
| mouse and focus **reports** from the tracking modes | the bits, the per-number answers, the carry across a rebuild, the armed console bit and **the encoder** are all here — five mouse formats plus the two focus forms, witnessed by writing them into a real console input stream and reading the bytes back. What a running session does not do is call it: the leg that pumps the console records still builds the legacy X10 bytes itself | X10, UTF-8, SGR, focus events | X10, SGR, pixel-SGR, focus | X10, SGR, urxvt-style, focus, with the encodings mutually exclusive | **gap A1** — not an argument: a program that selects SGR or UTF-8 is told "set" and receives X10. Listed in §6 |
| bracketed paste `?2004` | stored, answered, cleared by both resets, **not** executed | executes | executes | executes | **owner decision #116** — the markers are bytes injected into the input stream, and #108 fixed who owns that queue: the layer that reads the console records. The carrier and the injection channel have landed, so what is left is a caller that knows a paste happened |
| a modified-key protocol (progressive enhancement, kitty keyboard flags) | refused, and the flags query is answered as an unknown number | set/query family yes | yes, behind a switch defaulting off | yes | **owner decision #116** — the key bytes are produced by the input leg, and nothing here stores a pushed flag set, so a query answer would be an invention. Push, pop and their query land together or not at all |
| the terminfo capability for the mouse key (`kmous`) | **not advertised**, and the maintainer documents disagree about whether that is settled: one calls it permanently out because the reports have an owner elsewhere, the other leaves it to be decided | — | — | — | see `terminfo/TERMINFO.md` for the machinery. The open question is which spelling would be true of the session a program actually gets — §6's A2 |

### 3.8 The wrap model

| Item | Here | msfterm | wezterm | ghostty | Reason |
|---|---|---|---|---|---|
| deferred (pending) wrap | not implemented — the cursor leaves the last cell the moment it is filled | yes | yes (it drives reflow) | yes (an erase form exists precisely to ask "not pending?") | **conflicts with the wrap claim**: moving to pending wrap changes what a row's soft-break bit means, and every line-ownership and copy/export rule reads that bit. And the measurement this rests on was taken **against the replaced baseline's two write paths, not against the three references** — that limitation is part of the row, not a footnote |
| double-width / double-height lines (`ESC # 3`/`# 4`, `# 5`/`# 6`) | refused | yes | yes | yes | **conflicts with the geometry contract** — a doubled row changes what the viewport is, and that number is what every scroll, resize and report rule in this file is written against. The other member of that family, the screen-alignment test, is not a geometry claim and has landed (§2.2) |

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

**STATUS 2026-10-05: all six rows are closed.** A1 wired the mouse/focus encoders into the one reader of
console records (JNI seam `encodeMouse0`/`encodeFocus0`; the leg is `cache/gaps/MouseLeg.java` via
`run-mouse.ps1`, which asserts the bytes the *reader* receives per armed format); A2 declared `kmous`
in the terminfo entry (`\E[M`, the legacy prefix the default family puts on the wire -- the same
convention xterm's own entry keeps for an SGR negotiation) across the master, the mirror, the `.ti` and
the jar, with `terminfo_check.sh` at 92 capabilities and the live leg asserting declared == sent; G3
modelled XTPUSHSGR/XTPOPSGR (MSFT's ring-of-ten, empty pop ignored, resets keep it, parts per xterm's
push grammar); G4 modelled XTSAVE/XTRESTORE (ghostty's one-slot-per-mode, never-saved restores off, RIS
clears the table and DECSTR keeps it); G8+G9 modelled the rectangular family and the protection bits
(`$ x/z/{/v`, DECIC/DECDC, DECSCA, and the selective halves of `?J`/`?K`) with the per-cell protection
living in a shadow array the console cannot read back -- the debt the G9 row named, inherited, not
solved. Host gate 8023/0, live both arches 6373/0 + STAGE0; every rule has a leg in `RenderCheck.cpp`
(`plan_sgr_stack`, `plan_xt_modes`, `plan_rect_family`) and every seam-crossing half a case in
`Render.java` (`caseSgrStack`, `caseXtModes`, `caseRectFamily`).

Six rows. Each one says what is missing, what carries it, and which leg has to go red before the work could be
called done. A refusal with one of the four reasons on its row lives in §3, not here; the reason this list is
short is that §3's rows were re-argued, and what could not be argued either shipped (the end of this section) or
acquired a named conflict (§3.3, §3.7, §3.8).

| # | Missing | Who has it | What it would take |
|---|---|---|---|
| A1 | **CLOSED 2026-10-05** (the paragraph kept below for the argument it carried). ~~The mouse and focus encoding is not wired into a running session.~~ The bits are stored, every number is answered, the console's mouse bit is armed, and the encoder for five mouse formats plus the two focus forms is written and tested against a real input stream — but the leg that reads console records still emits the legacy X10 bytes itself. A program that asks for SGR reporting is told "set" and receives X10 | all three produce reports in the format their modes select | one call site: hand the record to this library's encoder and let it inject — or delete one of the two encoders so the product has a single spelling. The leg that decides it: a live session drives a click and asserts the **bytes** the reader gets, per format; model-side legs cannot see the wire. Nothing conflicts; this is the unfinished half of the input-report work |
| A2 | **CLOSED 2026-10-05: declared `kmous=`\E[M` everywhere; `terminfo_check.sh` and the live leg are the witnesses.** ~~`kmous` is not in the terminfo entry.~~ One calls it permanently out, one leaves it pending | the capability a mouse-aware reader asks for before it arms anything | decide first. If it goes in: the five terminfo steps (entry, mirror, source resource, jar, gate) and a leg asserting that the declared string equals the bytes actually sent — which is exactly what A1 would make true. If it stays out, both documents have to say so in the same words |
| G3 | **CLOSED 2026-10-05** — modelled with MSFT's rules; host + rebuild-carry legs. ~~Push and pop the rendition~~ — `CSI # {` and `CSI # }` | microsoft/terminal; the other two have neither sequence | a stack of stored attributes hung off the model, so a rebuild cannot lose it, plus the three rules that decide whether it is honest: depth and what overflow drops, what a pop on an empty stack returns, and whether either reset clears it. No query obligation — there is no DECRQM number for it. Legs: one per rule, plus the rebuild-carry |
| G4 | **CLOSED 2026-10-05** — modelled with ghostty's rules; the bare `?r` keeps its DECSTBM reading by decision. ~~Save and restore a mode~~ — `CSI ? N s` and `CSI ? N r` | ghostty implements it; wezterm parses and warns; microsoft/terminal has no key for it | a saved cell per mode, and a restore that re-runs the mode's *act* rather than rewriting its bit, so an application that saved cursor visibility gets a cursor it can see. Two decisions the references already made, taken deliberately: one save per mode rather than a stack (a stack is a memory-exhaustion surface), and restoring a mode nobody saved means *off*. Careful with `CSI s` — without `?69` it is save-cursor and with it DECSLRM, so the private spelling is a third production, not a variant of either |
| G8 | **CLOSED 2026-10-05** — the family is modelled (DECCRA/DECFRA/DECERA/DECSERA/DECIC/DECDC); DECRQCRA stays out (wezterm-only, as before). ~~The rectangular operations family~~ | microsoft/terminal has the family, wezterm the checksum, ghostty none | each shape has to re-derive two rules the row model already owns: pair healing at a rectangle's left and right edge, and which row owns a wrapped line. A rectangle is a second geometry over the grid, so it needs its own damage rule and its own bounds leg. Effort, not impossibility |
| G9 | **CLOSED 2026-10-05, shipped with G8 as it demanded** — DECSCA pens a shadow bit; the selective trio honours it; the plain erase clears it; the console-readback debt is on record in Render.h's `cellProt`. ~~Selective erase's other half~~ | microsoft/terminal, ghostty | a per-cell bit. The console's own cell type has no such bit, so it lives in a shadow array beside the grid — the same place the soft-wrap claim already lives, and it inherits that one's debt: it cannot be read back off the console, so nothing outside this library can check it. Must arrive with G8's selective forms, or the equivalence §3.4 states stops holding |

**Closed in build -54, so no longer gaps** — and where each one now lives: the screen-alignment test `ESC # 8`
(§2.2; it had been *executed as* restore-cursor, which was a defect rather than a missing feature); `OSC 7`
(§2.8); the title report `CSI 21 t` and XTVERSION `CSI > q` (§2.9); the DECST8C spelling `CSI ? 5 W` (§2.11);
answering a mode number the model does not hold with status 0 instead of silence (§2.9, §3.5); and the mouse and
focus encoders, which closed their own row and left A1 in its place.

**Not gaps.** Images and sixel (no pixel plane in front of a buffer this library does not own); hyperlinks (an
owner decision: a link is a range, not a cell, and the sequence alone buys a user nothing); the side-effecting
private commands (safety: the only floor under executing stream-supplied semantics is not executing them); pixel
geometry reports and the screen-geometry report (the answer would be a fabricated measurement, or a distinction
this build cannot show); reverse video as a screen-wide mode (§3.3, a named collision with the adopt and
differential work, cost on the row); double-width and double-height lines (§3.8, changes what the viewport is);
deferred wrap (§3.8, four discriminators run on both legs agreed); bracketed-paste execution and key encoding
(§3.7, owner decision #116 — with the carrier and the injection channel already landed); the termcap query (two
sources for one capability table); background-colour erase and reverse wraparound (each contradicts a contract
this file already advertises). **None of those closes a question.** Each row above is a claim with a date on it,
and anyone who builds the case where it comes out differently is expected to re-open it.

## 7 What the three references disagree about, and what this build chose

| Question | msfterm | wezterm | ghostty | This build |
|---|---|---|---|---|
| Mode query for an unknown number | answers, status 0 | answers, status 0 | answers with the full permanent/unknown vocabulary | **answers, status 0** (since -54; this cell used to read "silent", which was the deviation — see §6 G11) |
| Scroll region: one-parameter form | fills the missing edge | fills it | fills it | fills it (the baseline it replaced cleared the region — a divergence from all four) |
| Inverted region pair | ignored | ignored | ignored | ignored (same) |
| Tab interval reset spelling | registers it as `?W` | parses `5g`, ignores it | acts on `?5 W`, no `5g` | both `5g` and `?5 W`; a bare `W` and any other parameter are refused |
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
| mouse | a mouse-tracking number this build stores and answers for, or an encoding request the report leg cannot satisfy (§3.7) | no |
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

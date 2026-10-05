# ANSI_SUPPORTS — what the native ANSI renderer supports

Scope: the native renderer behind dbcli's terminal output (`render.dll`, terminal type `windows-conemu`).
This page answers two questions for a reader of the terminal: what a program running in this session can
use, and what it cannot. It carries no code references on purpose — the maintainer-level evidence lives in
`ANSI_TODO.md` (the per-item ledger), `DESIGN.md` (the invariants) and `terminfo/TERMINFO.md` (the
capability entry).

One framing rule: **an unsupported sequence is never half-applied.** It is consumed, counted by family, and
the session keeps running. A sequence the parser has no case for at all additionally marks the frame, which
makes the next paint re-read the console once, so the model re-syncs with what is really on screen.

---

## 1 Structure

| Property | Behaviour |
|---|---|
| Feed | UTF-16 code units; a sequence split across two writes continues in the next one |
| Parameters | up to 16 per sequence; values saturate at 65535; surplus parameters are dropped; an omitted or zero parameter takes the sequence's default |
| Interruptions | `CAN`, `SUB` or `ESC` inside a half-read sequence abandon it cleanly — nothing is half-applied |
| C1 bytes (`0x80`–`0x9F`) | ordinary text, not controls; being zero-width they never reach the screen |

---

## 2 Supported

### 2.1 C0 control characters

| Code | Behaviour |
|---|---|
| `BEL` | takes no cell, rings nothing |
| `BS` | moves left, never erases; steps off the trailing half of a wide glyph |
| `HT` | walks the tab-stop table forward; stops at the end of the line rather than wrapping |
| `LF` | down one line **and to column 0** — the console's own behaviour |
| `CR` | to column 0 |
| `SO` / `SI` | select the drawing set / the default set for subsequent text |
| other C0, `DEL` | ignored, never drawn as a glyph |

### 2.2 ESC sequences

| Sequence | Name | Behaviour |
|---|---|---|
| `ESC 7` / `ESC 8` | save / restore cursor | position only — attributes are not saved; the origin mode travels with it |
| `ESC c` | RIS | full reset: leaves the alternate screen, resets the pen, drops the scroll region and the cursor-shape claim, restores the tab interval, clears all four character sets, scrolls the viewport's content into history and homes the cursor |
| `ESC D` / `ESC E` / `ESC M` | IND / NEL / RI | down a line, CR + down, up a line — all three honour the scroll region; `RI` at the region top inserts a blank line |
| `ESC ( 0` | designate G0 | DEC line drawing for `` ` ``–`~`, one cell per character; `ESC ( B` restores ASCII |
| `ESC ) * + ~` | designate G1–G3 | stored; **invisible until `SO`/`SI` shifts the slot in**. Only the drawing set and ASCII can be named |
| `ESC H` | HTS | claims the cursor's column as a tab stop |
| `ESC N` / `ESC O` | SS2 / SS3 | the introducer is consumed and the next byte prints as ordinary text — nothing is eaten |
| `ESC # 8` | DECALN | screen-alignment test: fills the viewport with `E` and clears the scroll region and origin mode with it |
| `ESC g`, `ESC =`, `ESC >` | visual bell, keypad | counted, nothing happens: this library owns no window to flash and no input encoding to switch |

### 2.3 Cursor movement

| Sequence | Name | Behaviour |
|---|---|---|
| `CSI A B C D` | CUU/CUD/CUF/CUB | movement, clamped to the scroll region when one is set; leftward movement steps off a wide glyph's trailing half |
| `CSI E` / `CSI F` | CNL/CPL | up/down plus column 0 |
| `CSI G`, `` CSI ` `` | CHA/HPA | absolute column |
| `CSI H` / `CSI f` | CUP | absolute position, viewport-relative — never lands in the scrollback gutter; clamped inside the margins when margins exist |
| `CSI d` | VPA | absolute row |
| `CSI a` / `CSI e` | HPR/VPR | relative column / row |
| `CSI s` / `CSI u` | save / restore | `u` restores only without a private byte — `CSI ?u` is somebody else's protocol and is refused, not misread as a cursor jump |
| `CSI ?1048 h/l` | save / restore | the same slot as `ESC 7`/`ESC 8` |

### 2.4 Editing, erasing, scrolling, rectangles

| Sequence | Name | Behaviour |
|---|---|---|
| `CSI J` 0/1/2 | ED | erases to/before/after the cursor, **stopping at the viewport** — the user's scrollback is never destroyed; form 2 also homes the cursor |
| `CSI K` 0/1/2 | EL | erases the line; erasing to the end also clears that row's wrap claim |
| `CSI L` / `CSI M` | IL/DL | insert/delete lines inside the region; refused for a cursor outside it; after a shift that happened the cursor sits at column 0 of its own row |
| `CSI @` / `CSI P` | ICH/DCH | open and close cells within the row; a wide glyph's two halves move as one unit and a pair the shift split is healed |
| `CSI X` | ECH | erases cells **on the cursor's row only** |
| `CSI b` | REP | repeats the last written glyph with the current attributes; it wraps, and a wide glyph costs two cells |
| `CSI S` / `CSI T` | SU/SD | scroll the region; with no region this is the whole-model scroll, carrying history with it |
| `CSI r` | DECSTBM | set the scroll region. A missing parameter takes the viewport's own edge; an inverted pair is ignored; an over-deep bottom is clamped; a one-row region is accepted; a region equal to the viewport is stored as "no region"; setting one does not home the cursor; `CSI ?r` is accepted too |
| `CSI Pl;Pr s` + `CSI ?69 h/l` | DECSLRM / DECLRMM | left/right margins, gated by mode `?69`: off, the same bytes are save-cursor; on, they set margins and home the cursor |
| `CSI ?6 h/l` | DECOM | origin mode: rows count from the region top, columns from the left margin; setting it homes the cursor |
| `CSI Pt;Pl;Pb;Pr;Ps $ x` | DECFRA | fill the rectangle with character `Ps` in the live pen |
| `CSI Pt;Pl;Pb;Pr $ z` | DECERA | erase the rectangle in the erase pen; non-selective, so protection does not survive it |
| `CSI Pt;Pl;Pb;Pr $ {` | DECSERA | selective erase: unprotected cells lose their text and keep their attributes |
| `CSI … $ v` | DECCRA | copy a rectangle to a destination, direction-correct when they overlap, clipped by the page |
| `CSI Ps }` / `CSI Ps ~` | DECIC / DECDC | insert/delete columns within the region's rows; refused for a cursor outside the margins |
| `CSI ? Ps J` / `CSI ? Ps K` | DECSED / DECSEL | the selective twins of ED/EL: unprotected text goes, attributes stay, protected cells are untouched |
| `CSI Ps " q` | DECSCA | the protection pen: `1` protects what is written next, `0`/`2` clear |

### 2.5 DEC private modes

Only the first parameter of an `h`/`l` list acts.

| Mode | Behaviour |
|---|---|
| `?25` | cursor visibility |
| `?47`, `?1047`, `?1049` | the alternate screen — one behaviour for all three spellings. Entering snapshots the main viewport and clears; leaving restores; the alternate screen has no scrollback |
| `?1048` | save / restore the cursor |
| `?7` | autowrap. Off, the last cell is overwritten in place, no row below is started, and a glyph that cannot fit is dropped whole rather than split |
| `?4` and `4` | insert mode (IRM): an ordinary written glyph opens room for itself |
| `?1` | application cursor keys: stored and answerable; the key bytes themselves belong to the input side |
| `?6`, `?69` | origin mode and the margin gate — see §2.4 |
| `?2004` | bracketed paste: stored and reported; the paste markers themselves are injected by the host program |
| `?2026` | synchronised output: while open nothing reaches the screen and damage accumulates; the closing sequence (or a 100 ms timeout, or a full scrollback gutter) paints one combined frame. Query replies are never withheld |
| `?2048` | in-band resize reports: while on, a window resize whose shape differs from the last one reported emits `CSI 8 ; rows ; cols t` through the reply channel |
| `?9`, `?1000`, `?1002`, `?1003`, `?1005`, `?1006`, `?1015`, `?1016` | mouse tracking and encoding: one bit each; the console's own mouse input is genuinely armed; the report format is the armed one (legacy X10, UTF-8 coordinates, SGR, urxvt, SGR-with-pixels) — see §2.12 |
| `?1004` | focus tracking, reported as `CSI I` / `CSI O` — see §2.12 |
| `?1001` | recognised and refused |
| `CSI ? Ps s` / `CSI ? Ps r` | XTSAVE/XTRESTORE: save and restore a mode. One slot per mode (a second save overwrites); restoring a mode nobody saved switches it **off**; RIS clears the table, a soft reset keeps it. Saveable: cursor keys, insert, autowrap, cursor visibility, bracketed paste, in-band resize, synchronised output and the mouse/focus tracking numbers |

### 2.6 Cursor shape and soft reset

| Sequence | Behaviour |
|---|---|
| `CSI Ps SP q` (DECSCUSR) | 1–6 are remembered. Where the console offers a real shape API, the bar shapes take it; elsewhere they fold to a block or an underline. A session that never asked touches neither. Measured under a pseudo-console (Windows Terminal): the console forwards cursor **visibility** but not the shape, so no style is visible there — while a raw `CSI Ps SP q` passes through and the terminal honours it |
| `CSI !p` (DECSTR) | soft reset: pen, region, cursor visibility, autowrap, synchronised output and all four character sets restored — while the screen, the cursor position, the margins and the alternate buffer are left alone. The cursor-shape claim and the tab table are also left alone |
| guards | `CSI ? SP q`, `CSI ! SP q` and other misspellings are refused rather than mistaken for the real thing |

### 2.7 Attributes (SGR)

| Code | Behaviour |
|---|---|
| `0` | reset to the default, including default colours |
| `1` / `2`, `22` | bold on/off — bold participates as *brightening* |
| `4` / `24` | underline, drawn — written as the console's own attribute bit (`0x8000`), which a classic console window paints. **Under a pseudo-console (Windows Terminal) it is invisible**: conhost's cell→VT serializer carries only reverse/foreground/background and drops the bit — measured, the affected cells serialize with **no SGR segment at all** |
| `7` / `27` | reverse video, drawn |
| `3`/`23`, `9`/`29` | italic and crossed-out: kept in the model so on/off pairs behave, but nothing is drawn (the console attribute has no bit) |
| `5`, `6`, `25` | blink: no state — the console attribute word has no blink bit |
| `30`–`37`, `90`–`97`, `40`–`47`, `100`–`107` | the standard and bright sixteen |
| `38;5;n` / `48;5;n`, `38;2;r;g;b` / `48;2;r;g;b` | 256-colour and 24-bit, applied **through the console's own palette fold** — a deliberate property, not a loss of fidelity |
| `39` / `49` | default foreground / background |
| `38:2::r:g:b`, `38:5:n`, `4:n`, `58:` | colon subparameters are parsed; the colour arms land where the semicolon spellings do, and `58:` is consumed so its numbers cannot be misread |
| `CSI m` with no parameters | a reset |
| `CSI ?…m` | the whole sequence is dropped — a private prefix on an SGR is not a partial request |

### 2.8 OSC

| Code | Behaviour |
|---|---|
| `0`, `1`, `2` | the window title really lands; one pair of surrounding quotes is stripped; over-long titles are truncated, not dropped |
| `4`, `10`, `11`, `104`, `110`, `111` | the palette: set and query index colours and the default foreground/background. Accepts `#RGB`/`#RRGGBB`/`#RRRRGGGGBBBB`, `rgb:r/g/b`, and 676 X11 colour names; indices 0–15 change the console's own attribute colours; a `?` query answers with the *effective* colour. Measured under a pseudo-console: the console's colour table is **not forwarded** (16-colour cells serialize as `38;5;n`, naming the *terminal's* palette entry), so recolors are invisible there — while a raw `OSC 4` passes through and the terminal honours it |
| `9;4`, `9;9`, `9;12` | the safe part of the private family is **stored, never obeyed**: taskbar state and progress, a working directory, and a prompt-start mark. Both stored values are readable by the host application |
| `52` | clipboard write, **off by default** and switchable only by the host program, never by the byte stream. Strict base64 (whole payload or nothing); an **empty payload means clear**; a read request is refused outright |
| `7` | the working directory: stored as text, readable by the application, **never obeyed** — no directory is changed because of an output stream |
| `133` | semantic prompts `A N P L B I C D`, with the exit code on `D` and continuation recognition; the marks travel with vertical movement |
| anything else | counted; the side-effecting private `9` subcommands (sleep, message box, environment, macro, run process) are counted and **never executed** |

### 2.9 Queries and replies

A query is answered after the screen is updated, written back as console input events — the only channel
this library has to speak to a program without owning its input handle.

| Query | Answer |
|---|---|
| `CSI 5 n` | `CSI 0 n` |
| `CSI 6 n` | `CSI row ; col R`, one-based, reporting the cursor **as it stood when the question was read** |
| `CSI c`, `CSI 0 c` / `CSI > c`, `CSI > 0 c` | the console host's own primary / secondary identification — one session presents one identity |
| `CSI 18 t` | `CSI 8 ; rows ; cols t` — the text area, in the columns really painted |
| `CSI 21 t` | the window title this parser last applied; a session that never set one gets nothing |
| `CSI 22 t` / `CSI 23 t` | push / pop the title, two levels deep |
| `CSI > q` | XTVERSION: this library's name and build stamp, as a device control string |
| `OSC 4;i;?`, `OSC 10;?`, `OSC 11;?` | the effective colour, as `rgb:RRRR/GGGG/BBBB` |
| `CSI ? N $ p` (DECRQM) | **1** set / **2** reset for every mode the model holds (§2.5); **0** not recognised for any number it does not |

### 2.10 Text: width, glyphs, wrapping

| Property | Behaviour |
|---|---|
| Width source | tables generated from **Unicode 15** with measured overrides — one oracle for the whole stack |
| East Asian Ambiguous | counted as **wide**, minus 206 code points measured at one cell across six real fonts |
| Zero width | combining and format characters take no cell |
| Wide glyphs | two cells, a leading and a trailing half; a pair that does not fit wraps whole and is never split |
| Supplementary planes | surrogate pairs are reassembled for measuring and written back unchanged; a lone low surrogate becomes one replacement cell |
| Pair integrity | no operation may leave one half of a wide glyph standing — the orphan is blanked |
| Wrapping | immediate, with one bit per row recording a soft break so copy and export can join rows |

### 2.11 Tab stops

Defaults are every eighth column. `ESC H` claims the cursor's column; `CSI 0g` clears that column, `CSI 3g`
clears the table and the interval; `CSI 5g` and `CSI ? 5 W` restore the interval (a bare `W` is refused).
`CSI Ps I` / `CSI Ps Z` walk forward and back without changing rows. One table serves the main and
alternate screens; a resize keeps application-set stops; RIS restores the interval, a soft reset does not
touch the table.

### 2.12 Mouse and focus reports

When a tracking mode is set, the console's own mouse input is armed and each console record is handed to
this library's encoder, which injects the report bytes the mode selected: legacy X10, UTF-8 coordinates,
SGR, urxvt or SGR-with-pixels, with the release, motion and modifier rules each format has. Focus changes
are reported as `CSI I` / `CSI O` under `?1004`. A program that asks for a format receives that format.

---

## 3 Not supported

All of the following are consumed and counted — none of them changes anything on screen or claims to.

### 3.1 Character sets

| Item | Why |
|---|---|
| GR, the 8-bit set half; `LS2`/`LS3`/`LS1R`/`LS2R`/`LS3R` | the input path is UTF-16 and produces no C1 bytes and no 8-bit text — there is nothing for these to select |
| `ESC % G` (UTF-8 selection) | the input is already Unicode before the grid; there is no encoding to switch |

### 3.2 Attributes

| Item | Why |
|---|---|
| blink (`5`/`6`) | the console attribute word has no blink bit |
| invisible (`8`), overline (`53`), double underline (`21`), framed/encircled (`51`/`52`) | no carrier in the console attribute |
| underline colour (`58`) | consumed so its numbers cannot be misread, but nothing is drawn |
| italic, crossed-out | stored (so `23`/`29` behave) but never drawn — same missing bit |

### 3.3 Modes

| Item | Why |
|---|---|
| `?12` cursor blink, `?8` columns, keypad and meta-key modes | want a blink bit, a second column mode, or a key *producer* — the input side is not this library's |
| `?3` 132 columns, `?40` | means resizing the user's window; the query for it answers **4** (permanently reset) |
| `?5` reverse video as a screen-wide mode | collides with how the console's own attributes are folded and re-imported |
| `?45` reverse wraparound, `?2005` background-colour erase | each contradicts the wrap/erase contract this renderer advertises |
| `?2027` grapheme clusters | width is a table lookup; the query answers **0** (not recognised) rather than claiming a capability |
| `?2031`, `?2033`, `?5522`, `?7727`, `?2094`, `?8005`, `?8452` | report a window theme, a graphics plane or a paste pipeline this library does not own |

### 3.4 Erase and rectangles

| Item | Why |
|---|---|
| `CSI 3J` (erase scrollback) | behaves as `2J` — the user's scrollback is not this library's to delete |
| DECCARA / DECRARA (attribute rectangles) | not modelled; everything else in the rectangular family is (§2.4) |
| DECRQCRA (rectangle checksum) | nobody else in the reference set has it either |

### 3.5 Reports

| Item | Why |
|---|---|
| `CSI ? 6 n` (extended cursor report) | answering the plain question with the extended spelling reports a position nobody asked for |
| `14t` / `16t` (pixels), `19t`, `20t` | pixel figures here would be fabricated measurements; one geometry has one name |
| device-status beyond 5/6, answerback, terminal-parameter request | each would state a fact about a device this library is not |
| termcap query (`XTGETTCAP`) | the capability table this session has is the terminfo entry; two sources for one table drift |
| `?2048` report contents | rows and columns only, never pixels; nothing is sent at the moment of enabling |

### 3.6 Graphics, hyperlinks and payload protocols

| Item | Why |
|---|---|
| DCS / SOS / PM / APC payloads | the container works; the payload is consumed and discarded whole |
| Sixel, kitty graphics, iTerm2 images | there is no pixel plane in front of a buffer this library does not own |
| OSC 8 hyperlinks | a link is a range, not a cell; the sequence alone buys a user nothing visible |
| OSC 52 clipboard **read** | answering would place the user's clipboard into the next command line |

### 3.7 Input side

| Item | Why |
|---|---|
| bracketed-paste execution | the paste markers are bytes injected into the input stream; that is the host program's act, not this library's |
| kitty keyboard protocol, modified-key reporting | key bytes are produced by the input leg; nothing here stores a pushed flag set to answer a query about |

### 3.8 The wrap model

| Item | Why |
|---|---|
| deferred (pending) wrap | immediate wrap is the measured behaviour of the console being replaced; switching would change what every line-ownership rule reads |
| double-width / double-height lines (`ESC # 3`–`# 6`) | a doubled row changes what the viewport is, and that number is what every scroll and report rule is written against |

---

## 4 Limits

| Limit | Value | Past it |
|---|---|---|
| grid width × height | 4096 × 256 | the renderer refuses to engage and the application keeps its existing writer |
| parameters per sequence | 16 | surplus dropped |
| parameter value | 65535 | saturates |
| title length | 256 | truncated and still applied |
| OSC/DCS payload collected | 32768 units | a title is truncated and applied; a clipboard payload is refused whole |
| clipboard decoded size | 12288 bytes | refused whole |
| queued replies | 64 | a full queue refuses the **new** question; nothing already asked is dropped |
| title stack | 2 deep | a third push evicts the oldest |

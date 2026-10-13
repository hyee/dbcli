# DESIGN.md — render.dll design contract

`src\c\conemu` is the parser, screen model and painter that turn ANSI/VT sequences into console cells,
shipped as `render.dll` plus one Java binding (`com.hyee.ansirender.NativeRenderer`). This page states who
owns what and which properties must hold forever. It carries **no file/line anchors on purpose** — symbols
are the anchors. Companion pages: `ANSI_SUPPORTS.md` (the user-facing support matrix), `ANSI_TODO.md`
(the per-item ledger — every open item is a row there, this page keeps none), `terminfo/TERMINFO.md` (the
capability contract), `JLINE_CHANGES.md` (accounting for jline-tree edits).

## 1 Goals and hard constraints

| Constraint | Meaning |
|---|---|
| All rendering in C/C++ | One parser, one screen model, one planner, one console executor. Java holds a handle and makes one call per chunk. |
| Windows 7 is the floor | Compiled with `-D_WIN32_WINNT=0x0601`, and the linked DLL's import table is grepped against post-Win7 APIs; either check fails the build in both bitnesses. Output is also identical on every Windows version: the model never depends on the console's own VT parser, and a model row is a buffer row (I7). |
| Never execute ConEmu-private OSC 9 | No sleep, message box, environment write, macro or process launch from a byte stream. `9;4`/`9;9`/`9;12` are stored (or routed to the FTCS path), never obeyed. |
| One width oracle | Display width comes from the `ansi_width` tables; no second, independent model (jansi's or anyone else's) and no locale or font input. JLine's `WCWidth` now reads this same generated table (`org/jline/utils/AnsiWidthTables.java`, written by `gen_ansi_tables.py --java`, 2026-10-10), so the ban is on a model that can drift, not on the class name. |
| A feature's absence needs a technical reason | "Nothing in dbcli sends that" is not a reason. Admissible: no carrier, answering would lie, a named owner decision, or a deliberate safety floor. |
| Three oracles, always | Every piece of development reads ghostty, wezterm and microsoft/terminal first and cites what was read. Where the three disagree, follow the side this project measured and record the deviation as deliberate. |
| The user's real surface outranks promises | Mojibake, CJK glyph overlap, `top`, `more`, the status bar and resize are the named high-priority surface; a feature that contradicts one of them at code level goes back to the oracles, then to the owner. |
| No build/test artifacts in the project tree | Everything produced goes to a scratch directory. |

Why the library exists: a console that cannot parse escapes itself used to be served by a *second* parser
in the process, and two parsers disagree. One parser closes that class; speed came with it.

## 2 Architecture

### 2.1 Layers

```
host app ── char[] ──▶ NativeRenderer.write() ──▶ render(h, text, off, len)
      Render.cpp                 Paint.cpp                      RenderJni.cpp
      parser, grid, width,       what this flush should send    the only layer that touches
      colour, damage             (slide/scroll/rect/attr/       the console: reads its shape,
                                 cursor + dirty columns)        applies the plan, reports
```

The division has exactly one test: **a fact obtainable only from a live console belongs to RenderJni.cpp;
everything else belongs to the two console-free files.** That is what makes the model testable on a host
with no terminal at all.

### 2.2 The JNI surface

Production methods: `open`, `render`, `openReason`, `stopReason`, `stats`, `close`, `build`, `snap`,
`isPseudoConsole`, plus the mouse/focus encoders and the clipboard policy. Every other export is gate
scaffolding: `readInput` (the only witness to what a reply *said*), `readopt` (exercises a rebuild on the
handle a case already holds), `plan` (returns the last executed plan — the only eye on painter intent,
because cells show where the console is, never why the painter went there). The build derives the demanded
exports from the Java `native` declarations and fails on any name the DLL does not export, in both
bitnesses.

`render()` returns three values: `PAINTED` (the chunk is on screen), `RAW` (declined — the caller writes the
same bytes raw, once), `GIVEUP` (model gone for good — ask `stopReason()` and write raw from here on).

`snap` re-parks the window on the cursor row after a keystroke (VTP consoles do it themselves; this library
exists for the mode where they do not). `isPseudoConsole` classifies the host by **window class** — the only
fact that does not lie (`WT_SESSION` is inherited by plain consoles, and the VT mode bit is on in both
hosts). An explicit `ANSICON_DEF=conemu` **outranks** the pseudo-console test: the claim means "render
through the renderer" even inside Windows Terminal (owner's ruling).

**ConPTY serialization limits (measured 2026-10-05):** under a pseudo-console, conhost re-serializes cell
writes to the terminal carrying only reverse/foreground/background. The underline bit, the console's colour
table and the cursor shape are dropped; raw VT escapes pass through unchanged. A renderer session in Windows
Terminal therefore shows no underline, no OSC-4 recolour and no cursor-style change, while classic console
windows and raw-write sessions show all three. The loss lives in Windows' serializer, not in this model.

### 2.3 Handle lifecycle: a claim, not a pointer to a grid

Up to four renderers per process. Two independent facts per slot: **`taken`** (owned) and **`g`** (model
alive). Conflating them is a bug in two directions: a renderer that gives up keeps its slot (`stats()` and
`stopReason()` must stay reachable — the census is often the only record that a private OSC ever went past),
and `open()` claims by `!taken`, never by `!g`. A refused `open()` gives the claim back. `release_all()`
clears `taken` last.

### 2.4 Declines, re-adopt and self-heal

The only structural refusals are a buffer row wider than `RC_MAX_COLS` and a viewport that does not fit the
model — never the window being dragged narrow. Otherwise: if the console moved in a way the model did not
do, the next chunk is preceded by an **align** — the model adopts the screen at the model's anchor (I28),
never clearing it (I4). A decline forces a rebuild. Consecutive declines up to a small bound stop the
renderer with a reason. Any sequence whose *effect is unknown* marks the frame suspect, which forces a
re-adopt on the next chunk; known no-ops are counted but cast no doubt.

### 2.5 Integration with the host application

`ANSI_RENDER=off` is the only switch: renderer, or a plain raw write of the same bytes. The DLL is found the
ordinary way (`java.library.path`, then `PATH`). With the renderer off, a full-screen repaint still leaves
the JVM as one chunk — the optimisation is of the text leaving the JVM and is worth the same either way.

## 3 Invariants

One line each; the gate suites pin them, and "no gate" is stated rather than implied.

| # | Invariant |
|---|---|
| I1 | Only `cells[r][c]` with `r < rows && c < cols` is valid; the array has a fixed stride, so past `cols` you read an earlier generation. |
| I2 | The cursor is never in the gutter. |
| I3 | The gutter is exactly one screen; rows ≥ 256 are refused, 129..255 get a partial gutter. |
| I4 | `align()` adopts the screen, never clears it; it reads at the model's anchor, not at the window top. |
| I5 | One flush applies in a fixed order: slide → buffer scroll → rectangles → attributes → cursor. |
| I6 | Geometry: `hist = rows − winRows`, `viewBase = winT − hist`, `base = max(viewBase, baseRow)` when set, `slide = min(k, free_slide)`, `bufScroll = k − slide`, `row0 = base + slide`. |
| I7 | A model row is a buffer row: `cols == bufW − winL`. A narrow window is never a reason to decline. |
| I8 | The painter never leaves the cursor right of `winR`; the model keeps the true column. |
| I9 | The mid-chunk paint hook may paint; it must not touch the parser. |
| I10 | One parser per chunk (and per process): an ESC inside a sequence abandons and restarts it; the parser is resumable, not a reparse window. |
| I11 | The SGR capture is drained at the end of every render. |
| I12 | `defAttr` is frozen for the life of the handle and survives re-adopt. |
| I13 | Erase overwrites attributes wholesale — a wide glyph's trailing half is destroyed by design. |
| I14 | Width is the `ansi_width` table only: control 0, combining 0, ambiguous wide minus the measured narrow exceptions. |
| I15 | Colour is ConEmu's fold chain; the fg==bg avoidance applies at paint time only when the background went through the COLORREF fold. |
| I16 | Cursor visibility costs one console call, and only on a real change. |
| I17 | An empty plan sends nothing. |
| I18 | A paint failure inside the mid-chunk hook disables the hook until the next align re-arms it. |
| I19 | An unsupported sequence is never silent: counted per family; only an unknown effect marks the frame suspect. |
| I20 | Each row stores why it wrapped (pushed off the edge vs a wide pair padded), and erasing to the edge or addressing the row clears it. |
| I21 | OSC/DCS are never silent: titles land, every other family has its own counter, over-long titles truncate and still apply. |
| I22 | Damage granularity is a column range; the model still stores whole buffer rows. |
| I23 | OSC 133 (FTCS) is a first-class family, not an unknown OSC. |
| I24 | The alt screen is one behaviour for three spellings; `?1048` is cursor save/restore only; entering snapshots, leaving restores; the alt screen has no scrollback. |
| I25 | DECSTBM is a modelled region: missing edge = viewport edge, inverted pair ignored, bottom clamped, one-row region accepted, a full-page region = no region, setting does not home the cursor. |
| I26 | The terminfo entry advertises only what the renderer models — absence matters as much as presence. |
| I27 | A slot is claimed until closed; ownership and model-liveness are separate facts. |
| I28 | The anchor is carried across a rebuild, never re-derived from the window. |
| I29 | A query is answered into the console's input stream as key events, never silently; a declined chunk answers nothing. |
| I30 | With buffer room below the claim, a scroll moves the claim's rows first; the scroll API's destination is an absolute buffer coordinate, not a delta. |
| I31 | Once the claim reaches the buffer's last row, the scroll's reach is the buffer: everything rides up and the oldest rows leave. |
| I32 | `?2026` defers a frame, never an answer: queries are sent while the region is open; the timeout clears the mode; a full gutter paints but keeps the region open. |
| I33 | HPR/VPR clamp to the viewport, not the scroll region (both references agree). |
| I34 | The palette is console state: OSC 4/10/11 change it and `close()` hands it back; queries answer the *effective* colour. |
| I35 | Autowrap off: the last cell is overwritten in place, no wrap claim, and a glyph that cannot fit is dropped whole. |
| I36 | Whatever an escape can make happen outside the screen is the host's decision (OSC 52: default off, host-only switch, read refused outright, empty payload = clear). |
| I37 | A counting parameter is bounded by what there is to count, and the bound is named where the parameter is read; DEC's absent/zero both mean one. |
| I38 | A sequence that changes a claim about the terminal needs stored state, and a resize must not quietly undo it (tab stops, margins, modes). |
| I39 | Row identity is order, not storage: a pool plus per-row indirection, with every per-row fact read through that order. |
| I40 | A caller-settable mode is state to hold, answer, reset and carry — the refusal that described the implementation instead of the terminal was the tell (IRM). |
| I41 | Parameter separators are grammar, not private markers; a count names the arm that dropped it. |
| I42 | A reply is a claim about the reader's world: answer only where the model holds the number, and one geometry has one name. |
| I43 | Margins are state: DECOM moves the base and the band; DECLRMM decides *which sequence* `CSI s` is. |
| I44 | A full-screen takeover banks the viewport first: a bare CUP to the viewport top while self-scrolled content is still visible pushes history up before painting. |

## 4 Client contract: the terminfo entry

The entry (`windows-conemu`) is the contract from the reader's side: whatever it advertises, the renderer
must do. Parser facts that make auditing non-obvious:

- The first line is never parsed — prose only; the file's rationale lives there.
- The trailing comma on each capability line is syntax; without it the last capability vanishes silently.
- `\,` does not protect a comma — no capability value may contain one.
- Unknown capability names are dropped silently — audit by asking the loaded `Terminal` for each string,
  never by "did it load".
- A `#` inside a value throws at load time (the parser's only throw).
- The file is LF-only: a CRLF conversion appends a carriage return to every value.
- Unknown escape spellings fail at tputs run time, not at load.
- `%i` plus the host's habit of calling the region setter with `(0,0)` produces a one-line region, not a
  reset — a reset must be a bare `CSI r`.
- The host's acsc box-drawing map and the renderer's forward map must agree letter for letter; the live
  gate checks them against captured bytes, not invented ones.

## 5 Cost model

Measured bands from two sampling campaigns — read as a band, never as an absolute; re-run the bench before
quoting a number:

| Operation | Band |
|---|---|
| read console view (info + cursor) | ≈ 60–85 µs per flush |
| `SetConsoleCursorPosition` | ≈ 36–49 µs — the entire cost of a slide |
| `SetConsoleTextAttribute` | ≈ 26–47 µs |
| `ScrollConsoleScreenBuffer` (one row) | ≈ 150–188 µs, ~4× a slide |
| `WriteConsoleOutputW` | ≈ 40–60 µs + ~43 ns/cell + 1.5–3.5 µs/row |
| the model's own staging | ≈ 1 ns/cell |

Design consequences: **slide instead of scroll** wherever possible (4× cheaper, moves no cells);
**batching at the chunk level** (the per-flush tax is the console read, not JNI); painting to the buffer
edge is charged per cell, so the dirty-column range (I22) makes the full-row figure an upper bound rather
than a constant.

Shape facts gates depend on: the default console profile has a buffer far wider and taller than the window;
Windows Terminal and ConEmu size the buffer to the window; `mode con:` collapses the buffer to the window,
so the wide shape needs its own leg. The row-rotation redesign replaced buffer copies with pointer
rotation: on the default 2000-column profile a scroll used to be ~95% of the cost of printing a line, and
afterwards the residual is the O(cols) work a scrolled-in row genuinely needs, while the rotation itself
measures below the instrument's resolution.

The shipped DLL is stripped of debug sections only, keeping the symbol table so a native fault names its
function. Stripping safety is verified by section comparison **within one file**: two links of the same
source differ (linker randomisation plus wall-clock fields), so an md5 is not evidence about source — every
build carries a `RENDER_BUILD` stamp that the gates print.

## 6 Verification

The doctrine, one line each:

1. Only cells read back from the console are evidence; a pty stream or a self-printed line is not.
2. "The DLL is loaded" is not "the DLL is painting" — the only witness is a substituted build that produces
   a different grid.
3. A control build is rebuilt from the current trunk and must fail a known, countable set of gates; read
   its `fails`, never its totals.
4. A control's defect must be reachable by the leg's workload, or the comparison is empty.
5. Every A/B leg states its own environment, and the switch it claims to set must have a reader — a leg
   setting a variable nothing reads is the treatment leg wearing a control's label.
6. A dirty console is inherited by the next leg: reset SGR before erasing, and assert blank at the default
   attribute.
7. "The legs agree" can be manufactured (both sides blank); use same-rows comparison and check
   expected-difference legs for the opposite failure too.
8. Documented deviations are gated as expected differences — a red there is information about a decision,
   not automatically a regression.
9. Two census formats exist (full family list vs production non-zero report); never read one as the other.
10. A green gate proves the source tree, not the deployment: verify deployed pairs (reflective slot-table
    check, build stamps, md5s, backups taken before swaps).
11. A gate helper can invent failures — zero-cell comparisons, over-long indices, pooled-string overruns;
    an assertion's cost is not its line count, and a helper that can compare nothing eventually will.
12. A number that does not move is a missing witness: a new arm must be seen to fire, and the corpus must
    actually send the family it exercises.
13. A cell diff cannot see painter intent — export internal quantities and read them, never argue about
    them across builds.
14. Read API argument semantics from the callee's contract, not the name; prefer witnesses that read far
    from the operation.
15. An expectation must count the line the cursor stands on; gate *where* the blank row is, not just that
    every row is a line.
16. When two expressions agree on every shape tested, pin the algebra that makes them agree and build the
    shape where they part.
17. A witness to a machine-wide register classifies contention before reporting, and restores what it found
    on every exit path. Its totals move with the register, so two runs are comparable only in the same
    register state: when this box's clipboard stopped answering `OpenClipboard` (ERROR_ACCESS_DENIED, and
    `GetOpenClipboardWindow` naming no owner), the OSC-52 leg bailed with its own line --
    `skip the witness can read what it just wrote: read back ""; an outside process owns the register` --
    and the live gate went from `checks=6373` to `checks=6341` with `failures=0`: a smaller suite, not a
    passing one. pwsh's `Set-Clipboard` in that state returns without error and writes nothing, which is
    why the leg checks for the read-back rather than trusting the call -- and why `clipSeed` succeeding is
    not the same fact as the witness seeing it.
18. Re-run an arm before citing it — "arm X turns check Y red" is a claim about the gate, not the code.
19. An oracle's silence is evidence only about its own list: prove it by breaking the list twice (once seen,
    once correctly silent) and assert its run count.
20. A SKIP is not a pass — declines must be loud in the output and visible in the totals. Implemented
    2026-10-10: `Render.java` counts unwitnessed legs and the totals print
    `checks=N failures=0 unwitnessed-legs=3` with one `NOT WITNESSED:` line each, and the verdict says the
    total is not comparable with a run that had them; `run.ps1` probes the clipboard the same way the gate
    does before any leg runs and prints `CLIPBOARD: writable` or `NOT WITNESSED … ~32 smaller per arch`.
    Exit code stays 0 -- a register the box will not lend is not the library's failure.
21. A sequence learned from a summary is a hypothesis; quote bytes from the decoder's own table.
22. A leg's setup is part of its claim: geometry resets erase evidence placed above them, and content
    inside a scroll region is placed by CUP, never by line feed.

Current gates: the **host gate** (console-free — colour table, full code-point width cross-check,
per-unit resumability, damage bounds) and the **live gate** (a real console, both bitnesses, cells read
back; optional reference leg against upstream ConEmu's own hook). Quote totals only from a fresh run. This
page keeps no per-build paragraphs: every build's witness is a ledger row in `ANSI_TODO.md`, and the
transcripts live in the scratch directories.

## 7 Known deviations

**From the console itself** (both consequences of the buffer-wide model, I7, ungated): a buffer scroll moves
whole buffer rows while the console moves window rows — visible only after horizontal scrolling at the
bottom of a tall buffer; and with a left window margin a wrapped continuation lands at model column 0,
not buffer column 0.

**The ambiguous-width ruling** (I14): "ambiguous = wide" is a ruling, and the measurements are the
exception list. Measured over the whole BMP ambiguous set across six real faces on this box: the console's
answer is a property of the *face*, not the code point, and the code page is irrelevant. The set splits
three ways — wide in every face (follow the ruling), narrow in every face (the encoded exceptions: box
drawing, block elements, accented Latin), and split (the known cost: `°`, `±`, `×`, `÷`, Greek and Cyrillic
capitals, arrows — right on the CJK default face, one column over-predicted elsewhere). Cross-checked
against the one shipping terminal that implements the ruling as a switch (xterm's cjk-width mode): the
blanket rule reproduces point for point and the exception list is the only divergence. The table is
deliberately *narrower* than the console in one place: combining marks take no cell (matching xterm,
Windows Terminal and glibc) where conhost gives them one — listed so nobody "fixes" it from a single-cell
probe.

**Where that ruling does and does not hold** (2026-10-10, read out of the three reference trees because JLine
now inherits this table for its own column arithmetic, so the ruling is no longer only the grid's problem).
All three default ambiguous to *narrow* and make wide a switch rather than a policy, each line opened in this
session: microsoft/terminal `src/types/inc/CodepointWidthDetector.hpp:76 int _ambiguousWidth = 1;`, raised only
by `src/host/VtIo.cpp:55 SetAmbiguousWidth(2)` (the conhost `--ambiguousIsWide` launch argument); wezterm
`wezterm-cell/src/lib.rs:852-856` (`WcWidth::Ambiguous && self.ambiguous_are_wide` → 2) with
`config/src/config.rs:865 treat_east_asian_ambiguous_width_as_wide` defaulting false; ghostty
`src/unicode/main.zig:27 codepointWidth` on a table documented at `:12-21` as "2 for wide codepoints (East
Asian Wide/Fullwidth, regional indicators, clamped at 2), and 1 otherwise" — no ambiguous concept to switch.
The font query that makes the answer face-dependent is installed only `if (!gci.IsInVtIoMode())`
(`src/host/srvinit.cpp:836-843`, giving `Renderer::IsGlyphWideByFont`), and `_checkFallbackViaCache` is reached
from just `CodepointWidthDetector.cpp:1157` and `:1203`; with no renderer pointer `:1221-1225` returns 1.
Read together: **classic conhost on MS Gothic or 新宋体 spends two columns for `●` and `…` — which is what the
six-face sweep measured — and Windows Terminal spends one, unless the user opts in.** The table follows the
first because that is the console dbcli is asked to serve. On the second it over-predicts, and the direction of
that error is the safe one: over-prediction cannot push a line past the margin, it leaves the tail cell unused.
Two of the sweep's own numbers are the evidence for the ruling rather than the reasoning: the 206 carve-out code
points were narrow in *every* one of the six faces, and the 620 split points are wide on the CJK faces and
narrow on the Western ones.

**The oracle is Unicode 16.0 now, and the instrument that decided it disagreed with itself** (2026-10-10, same
day, after the paragraph above). `gen_ansi_tables.py` reads `src/c/luauf8/ucd/EastAsianWidth.txt` and
`UnicodeData.txt` (16.0.0, carried in the tree so the version is a property of the repository rather than of
whichever Python runs the gate; `--interp` remains as the A/B leg, and a missing file aborts instead of falling
back silently). Net effect against the table that shipped all week: **37 code points** move -- 36 marks that 16.0
assigns going 1 -> 0, and U+1171E AHOM CONSONANT SIGN MEDIAL RA going 0 -> 1 because 16.0 reclassifies it Mn ->
Mc -- plus 139 code points that 16.0 reclassifies N -> W. For those 139 the six-face instrument said ONE cell
(1,056 cursor readbacks, `cache/ucd16/measured-moved.csv`), so the model first grew a second measured carve-out
to hold them at 1. A dbcli leg in the pseudo-console then measured the same glyphs the other way: every one of
them occupies **two** cells there, with the 0x0000 trailing cell conhost reserves for a wide glyph, and the pty
stream shows each glyph crossing exactly once (`cache/leg-1010/ucd16*/`, read by `cache/ucd16/check_leg16.py`).
So the carve-out came off and the property is followed. The two console paths really do differ, and the
reference tree documents two different width sources: the renderer's `IsGlyphWideByFont` fallback is installed
only `if (!gci.IsInVtIoMode())` (`src/host/srvinit.cpp:835`), while the VT path answers from the property trie
(`src/types/CodepointWidthDetector.cpp:1153-1157`, where only an ambiguous `width == 3` consults the font cache)
-- that pairing is the mechanism the measurements suggest, not something either leg proved. What settles the
choice is the asymmetry: a table that says 1 where the host spends 2 lays the next column on top of the glyph
(the overlap class), while a table that says 2 where the host spends 1 leaves a blank tail. Verified after the
flip, cell by cell, in a live grid: the trigram column reserves 16 cells and the console spends 16, the CJK
column 6 and 6, the Tai Xuan Jing column 10 and 10, the astral column 6 and 6, and every column to the right of
them starts exactly where the header's dashes start -- `cache/ucd16/check_align16.py`, worst displacement 0.
The narrow answer on the classic WriteConsoleW faces is now a recorded known cost in the same shape as the 620.

One divergence from a reference is recorded rather than smoothed over: ghostty gives **regional indicators**
(U+1F1E6..U+1F1FF) two cells each, this table gives them one (they are EAW=Na, and no measured face was asked).
Per code point, a flag pair then totals 2 cells here and 4 there; neither number is cursor-measured, so this is
written as "unmeasured and differing", not as "settled".

**From the parsers this library is not** (pinned as expected-difference legs): backspace steps over a wide
glyph's trailing half where the old parser clipped; astral code points are stored as their raw surrogate
halves rather than folded to U+FFFD.

**Rejected proposal — deferred wrap**: four discriminating shapes were run on both legs and all four agreed
with immediate wrap, so switching would *create* a divergence rather than remove one. A fifth discriminator
may reopen the row.

## 8 Build and run

```sh
# cross-compile (MinGW-w64 lives in WSL); everything lands in the scratch directory
MSYS_NO_PATHCONV=1 wsl.exe -e bash -lc 'cd /mnt/d/dbcli && bash src/c/conemu/build.sh' 2>&1 | tr -d '\0'

# the two control builds, each from the current trunk (both intentionally fail their host gate)
MSYS_NO_PATHCONV=1 wsl.exe -e bash -lc 'bash /mnt/d/dbcli/cache/scratch-lfbug/make-control.sh' 2>&1 | tr -d '\0'
MSYS_NO_PATHCONV=1 wsl.exe -e bash -lc "tr -d '\r' < /mnt/d/dbcli/cache/scratch-elbug/make-control-el.sh | bash -s" 2>&1 | tr -d '\0'
```

```powershell
pwsh -NoProfile -File src/c/conemu/run.ps1                    # probe + live gate, both bitnesses
pwsh -NoProfile -File src/c/conemu/run.ps1 -Arch x64
pwsh -NoProfile -File cache/java-merge/build-jar.ps1          # rebuild the host jar (-Deploy writes lib\)
pwsh -NoProfile -File cache/java-merge/config-check.ps1       # every ANSI_RENDER spelling vs the deployed jar
```

```sh
# the terminfo contract (tic/infocmp live in WSL; nothing touches the checkout without --refresh)
# the variable assignments must be EXPORTED, and the checkout may be CRLF, hence the tr:
MSYS_NO_PATHCONV=1 wsl.exe -e bash -lc \
  'tr -d "\r" < /mnt/d/dbcli/src/c/conemu/terminfo/terminfo_check.sh | bash -s'
```

Notes that cost time when unknown: a control build needs a sibling `luauf8` directory in its scratch tree
(the width tables are included by relative path); JDK 8's `javac` will not create its own `-d` directory;
`-Deploy` must be invoked through `-Command`, not `-File`; a console leg must run inside a real console —
start it through a `.cmd` wrapper with `MSYS2_ARG_CONV_EXCL='*'` in the environment, and double-quote
`-Send` values (cmd does not treat single quotes as quoting); a `render.dll` held open by a live session
cannot be written in place but can be replaced by writing next to it and renaming over the old name; the
generated width table is never edited by hand — regenerate, then re-run the host gate.

Where the rest of the record lives: no open-work section and no ledger here, deliberately — a numbered row
living on two pages carries its verdict on one and its row number on the other. Everything still owed is a
row of `ANSI_TODO.md` (what to change, which arm must be seen red, which gate must go green).

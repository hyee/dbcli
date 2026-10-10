# render.dll — an ANSI renderer for the Windows console

Design document for `src\c\conemu`: the parser, the screen model and the painter that turn a stream of
ANSI/VT escape sequences into console cells. It ships as `render.dll` plus one Java binding,
`com.hyee.ansirender.NativeRenderer`, and is meant to be used as a library: the embedding application
provides a console handle and a `char[]`, and gets painted cells.

This file is the **contract**. It says who owns what, which properties must hold forever, and which gate
pins each one. Where a property has no gate, that is written out rather than left as an omission — an
ungated invariant is the one that will be broken quietly.

Line numbers *in this tree* are not quoted: function and field names are the anchors, and the gates are
named by test, not by position -- an anchor that is a line number rots one edit later, and this document
has been wrong that way often enough to write it down. A citation into one of the three reference
terminals keeps its `file:line`, because there the claim is about a specific line in somebody else's
file; which makes opening that line the reader's job, not the writer's assurance that it was opened.

## 1 Goals and hard constraints

| Constraint | Meaning in the code |
|---|---|
| All rendering in C/C++ | `Render.cpp` is the only parser and the only screen model; `Paint.cpp` decides what to send; `RenderJni.cpp` executes against the console. Java holds a handle and makes one call per chunk. |
| Windows 7 is the floor | `build.sh` compiles with `-D_WIN32_WINNT=0x0601 -DWINVER=0x0601` **and** greps the linked DLL's import table against a list of post-Win7 APIs. Both bitnesses fail the build if either check trips. **The floor has a second half that no build check can see.** On 1809+ the console runs its own escape parser (`ENABLE_VIRTUAL_TERMINAL_PROCESSING`); on Windows 7 there is none, so a session that leaves the bit on paints *different screens on the two* -- a chunk this renderer declines becomes colour on one and literal text on the other, and cells the console already serialised to a pseudo-console arrive a second time. So while this model is painting, `RenderJni.cpp::claim_output` clears `RC_OUT_VTP` out of the handle's saved output mode, and it is a **borrow**: given back by `give_up` the moment nothing is painting (the caller writes raw from there on and raw bytes need that parser) and by `release_all` at the close, while a grid rebuild is deliberately **not** such a moment -- `readopt` swaps the model and not the handle, so restoring there would hand the host its parser back for the rest of the session one resize in. What is enforced is "one painter per byte stream", and the owner's ruling of 2026-09-27 is its plain form: when render is asked for, Win7 and Win11 must output the same thing, therefore it is the Win10-only renderer that gets switched off -- which is why the claim lives in the library, not in a caller's writer. Witness cannot be the host gate (`RenderJni.cpp` mutations are invisible to it): see `ANSI_TODO.md` #104 and `cache/vtp104/`. |
| Never *execute* ConEmu-private OSC 9 | Nothing in the family runs anything: no sleep, no MessageBox, no environment write, no GuiMacro, no DoProcess. Three subcommands are *stored* or *routed* -- `9;4` keeps a taskbar state and progress, `9;9` keeps a path as text, `9;12` goes into the FTCS `133;B` path it is equivalent to -- which is the same line microsoft/terminal draws at `DoConEmuAction` (adaptDispatch.cpp:3558-3647), and neither stored fact is obeyed: this library owns no window and never changes the process's directory from an output stream. Everything else is counted and ignored (ConEmu issue #687). |
| One width oracle | Display widths come from the `ansi_width` table in `src\c\luauf8`, which `rc_width()` links through the generated `ansi_width_tables.h`. No WCWidth or jansi table may be substituted, and the locale and the font are not consulted. Since 2026-10-10 JLine's own `WCWidth` reads this same table too: `gen_ansi_tables.py --java` writes `org/jline/utils/AnsiWidthTables.java` in the same run that writes the header, and `run.ps1`'s WIDTH CHECK leg fails a tree whose copy has fallen behind -- so the ban is on a model that can drift, not on the class name. |
| Output is the same on every Windows version | The model does not depend on `ENABLE_VIRTUAL_TERMINAL_PROCESSING`, and a model row is a **buffer** row (I7), so wrap points and erase extents agree with the console regardless of window width. |
| A feature's absence needs a **technical** reason, not a local non-user | This is a third-party renderer: its callers are other programs, so "nothing in dbcli sends that" is **not** a reason to leave a sequence unmodelled or a capability undeclared (ruled by the user 2026-09-26, and it re-opens every "no consumer" sentence in `ANSI_SUPPORTS.md` §3 -- see #76). The admissible reasons are: the console offers no surface for it (no attribute bit for blink/invis, no window rectangle for `CSI t`), honouring it would be a claim about the *other* parser that may read the same bytes in the same session (I26: `smam`/`rmam`, `initc`/`ccc`), or it is a floor chosen deliberately for safety (the OSC 9 execution half; OSC 52's default-off). Everything else is work to do: #70 makes `cbt`/`hts`/`tbc` true rather than undeclared (and #90 later declared only `cbt`, because it is the one of the three a reader binds -- see that row), and #76 is the sweep. |
| Three oracles, always | Every piece of development under `src\c\conemu` reads **ghostty** (`D:\Green\github\ghostty`), **wezterm** (`D:\Green\Github\wezterm`) and **microsoft/terminal** (the clone `D:\Green\github\msfterm`, and `adaptDispatch.cpp` is byte-identical between them) before writing code, and the design note for a behaviour cites them by `file:line` -- a decision with no reference line is an invented decision. Where the three disagree, this project takes the side it has *measured* and says so as a deliberate deviation. ConEmu remains the parity baseline, **not** an oracle (ruling 2026-09-26: "upstream does not do it either" is not a reason). Verified per-tree module map: `.dsh/memory/reference/reference-terminal-oracles.md`. Where to look: msfterm `src/terminal/adapter/adaptDispatch.cpp` + `DispatchTypes.hpp:526/535` + `src/buffer/out/Row.cpp`; ghostty `src/terminal/modes.zig` + `page.zig` + its X11 colour-name table (all three carry one: ghostty `src/terminal/res/rgb.txt` + `x11_color.zig:45`, msfterm `src/types/colorTable.cpp` (its own re-derivation), wezterm `color-types/src/rgb.txt` parsed at `color-types/src/lib.rs:391` -- **not** in `term/src/color.rs`, where a 2026-09-27 note looked, got 0 hits and drew a negative conclusion from one file; corrected via `cache/audit90/x11/VERIFY.md` §2); wezterm `term/src/terminalstate/{performer.rs,mouse.rs,keyboard.rs}` and `wezterm-char-props/src/widechar_width.rs`. |
| What the user uses outranks what was merely promised | The named high-priority surface is **mojibake, overlapping glyphs for CJK and other scripts, `top`, `more`, the status bar, and resize** -- the behaviours that actually run under JLine + dbcli. When a feature in development contradicts one of them **at the code level**, the order of recourse is fixed: (1) read msfterm / wezterm / ghostty for how they solved it, (2) if there is no answer, **keep the used behaviour and drop or narrow the feature**, recording the drop as a row of `ANSI_TODO.md` §3 with one of the four legitimate reasons (that row is the subject of the constraint above). This overrides the ledger's "lower ticket number wins" default: sequence says what landed first, this says what is worth more. Under it, mouse tracking and cursor shape yield; palette fidelity, charset/shift state, width and geometry do not. |
| No test artifacts in the project tree | Everything the build and the gates produce goes to a scratch directory (`cache\native-probe` by default). |

The reason this library exists is not speed, although it is fast. It is that a console which cannot parse
escapes itself used to be served by a *second* parser in the process, and two parsers disagree: the
literal `[33m` in mid-output and the white-on-white prompt were both exactly that bug. One parser closes
the class. Speed came with it (I5, I22, §5).

## 2 Architecture

### 2.1 Layers

```
host application ── char[] chunk ──▶ NativeRenderer.write()          Java: handle + one call
                                          │
                                          ▼
                             render(h, text, off, len)               the only production entry point
                                          │
        ┌─────────────────────────────────┼───────────────────────────────────┐
        ▼                                 ▼                                   ▼
  Render.cpp                       Paint.cpp                           RenderJni.cpp
  ANSI state machine, grid,        what this flush should send:        the only layer that touches
  width, colour, damage            slide / scroll / rects / attr /     the console: reads its shape,
                                   cursor, and which columns of        applies the plan, reports errors
                                   which rows are dirty
```

The division has exactly one test: **a fact that can only be obtained from a live console belongs to
`RenderJni.cpp`; everything else belongs to the two console-free files.** That is what makes the model
testable — geometry, damage and wrapping are enumerable in `RenderCheck.cpp` on a Linux host, with no
terminal and no human looking at one.

### 2.2 The JNI surface

Production methods on `com.hyee.ansirender.NativeRenderer`: `open`, `render`, `openReason`, `stopReason`,
`stats`, `close`, `build`, `snap`, `isPseudoConsole`. The rest of the exports (`feed`, `flush`, `sgr`, `align`, `openStatus`, and the
`Java_Render_*` scaffolding: `prepareConsole`, `setGeometry`, `consoleView`, `readCells`, `consoleTitle`,
`readInput`, `readopt`, `plan`, `writeHk`) exist for the gate, which drives the model one step at a time and reads
cells back out of `conhost`. Two of those are scaffolding for facts a grid diff cannot reach: `readInput`
consumes the characters sitting in the console's input stream, which is the only witness to what a reply
*said* (I29), and `readopt` rebuilds the model on the handle the case already holds, which is the only way to
exercise a resize's carry of the anchor (I28) — production reaches the same rebuild through `render()`'s own
state machine, and a case that drove `close()` + `open()` instead would be testing a *new* session, which has
no anchor to carry. A third, `plan`, is scaffolding for a fact a cell diff **cannot** reach at all: the cells
say where the console is and never where the painter believed its own rows were, so a plan that addresses the
right rows for the wrong reason and one that addresses the wrong rows come back looking identical. It returns
the last plan this handle executed — 18 slots, from `seq` and `reason` through the arithmetic (`base`,
`slide`, `bufScroll`, `row0`, `winTop`) to the two outcome flags (`declined`, `moveFail`) — and it is what
turned -11 from a guess into a reading: `seq=422 base=340 slide=0 bufScroll=1 row0=340 winTop=0 moveFail=0`
says the band and the destination directly, next to the cells it produced. `build.sh` asserts the export list
on every build, in both bitnesses; that gate is what catches a method written outside the `extern "C"` block
as a mangled name.

Two of the production natives are not part of the paint and have no handle-shaped result. `snap` is I6's other
half: conhost snaps the view back to the prompt on a keystroke only for a console in VTP mode, and the mode this
library exists for is the one where VTP is off, so `WinSysTerminal` calls it once per key press (through
`ConEmuWriter.snapOnInput`) and the renderer parks the window on its own cursor row — a no-op, and free, unless
the user had scrolled away. `isPseudoConsole` answers a question the *classifier* asks before any handle exists:
`GetClassNameW(GetConsoleWindow())` is `PseudoConsoleWindow` behind a ConPTY client and `ConsoleWindowClass` in a
real console window, which is the only one of these facts that does not lie — `WT_SESSION` is inherited by a plain
console window started from inside a Windows Terminal session, and both ENABLE_VIRTUAL_TERMINAL_PROCESSING and a
successful `SetConsoleMode` say "yes" in either host. A session must not paint a grid it does not own, so the classifier consults this test -- but an explicit
`ANSICON_DEF=conemu` **outranks it**: `WinSysTerminal.createTerminal` reads `conemuClaimed` first and takes
the writer's branch even on a pseudo-console (the owner's ruling of 2026-09-27, #99). Before that ruling the
order was the other way, and a Windows Terminal session carrying `ANSICON_DEF=conemu` never reached the
writer at all -- `ConEmuWriter` being the only caller that reports why -- so the painter was skipped for a
whole session in silence. Two costs were measured on that branch and one has been paid: #104 is in the
library (while this model paints, `claim_output` clears `ENABLE_VIRTUAL_TERMINAL_PROCESSING`, which is what
makes a declined chunk look the same on Windows 7 and on 11) and #103 is not (a headless conhost
re-serialises cell writes back into VT whatever this buffer's mode says, so the rows an adopt merely
re-read arrive as new output in a scrollback that is not ours). `ANSI_RENDER=off` remains the way out of
both, at the price of speed. The wrapper returns a `Boolean`, and `null` — library missing, method
older than this one — means "classify without this fact", which is what the pre-`-15` behaviour was. The
A/B that established the window class -- not `WT_SESSION`, not the mode -- as the fact to read is
`D:\dbcli\cache\wt-classify-20260925` (`ConShape.cpp`, `matrix.cmd`); it is dated 2026-09-25 and
therefore describes the weaker order, and #37, #38 and #99 of `ANSI_TODO.md` §3 are the rows that
changed it.

`render()` returns one of three values and the Java side does nothing but pass them on:

| Result | Meaning | What the caller does |
|---|---|---|
| `PAINTED` | the chunk is on the screen | return |
| `RAW` | this chunk was declined | write the same bytes raw, once |
| `GIVEUP` | the model is gone for good | ask `stopReason()` and write raw from here on |

### 2.3 Handle lifecycle: a claim, not a pointer to a grid

A process can hold up to **four** renderers (`g_h`). Two independent facts are recorded per slot:

* **`taken`** — somebody owns this slot; and
* **`g`** — the slot still has a model (it becomes `NULL` when the renderer gives up).

These are not the same question and conflating them is a bug with two directions. A renderer that gives up
must keep its slot: `stats()` and `stopReason()` have to stay reachable, and the census of unmodelled
families is often the **only** record that a private OSC ever went past. Conversely, `open()` must not hand
a new caller that pointer and take over its console, so it claims a slot by `!taken`, not by `!g`. A
refused `open()` gives the claim back — a refusal must consume nothing. `release_all()` clears `taken`
last, because until that line the slot still answers its own pointer.

### 2.4 Declines, re-adopt and self-heal

Nothing rejects a chunk because of the window being dragged narrow: the only structural refusals are the
buffer row being wider than `RC_MAX_COLS` and the viewport not fitting the model (I3, I7).

`render()` runs an adopt/re-adopt/give-up policy that used to live in Java:

* the model tracks the console; if the console moved in a way the model did not do, the next chunk is
  preceded by an **align** — the model adopts what is on the screen (I4);
* an align reads the console **at the model's anchor**, not at the window's top. The rows it adopts are the
  rows the model claims, and after a resize that is the claim the old grid carried rather than whatever the
  view happens to be over (I28);
* a **decline** forces a rebuild: the bytes were about to be put in front of a console the model never
  painted, and after an alt-screen enter/leave there is no console equivalent of the model at all;
* `RENDER_MAX_DECLINES` consecutive declines stop the renderer, with a sentence in `stopReason()`;
* any sequence whose *effect is unknown* (I19) marks the frame suspect, which forces the next chunk to be
  re-adopted rather than continued. Known-no-op families are counted but do not cast doubt.

### 2.5 Integration with the host application

The host picks this library by choosing its writer: a console that accepts
`ENABLE_VIRTUAL_TERMINAL_PROCESSING` renders escapes itself and needs nothing here; a console that cannot
(a Windows 7 console, or one where the mode was turned off) is given to the writer that owns
`NativeRenderer`. The switch `ANSI_RENDER` (`off`, `OFF`, `0`, `no`, `false` disable it; anything else, and
nothing at all, leave it on) selects between the renderer and a plain `WriteConsoleW` of the same bytes.
That is the only switch: the DLL is found the ordinary way, through `java.library.path` and then `PATH`, which
is where the launcher already puts its own `lib\x64`. A second variable naming that directory was removed on
2026-09-27 at the owner's instruction ("没有这种问题，不需要这个变量") -- it was a fallback for a failure the
launcher cannot produce, and every extra environment variable is one more thing a user has to know.

When the renderer is off, a full-screen repaint on the host side is still sent as one chunk instead of one
cursor-addressed write per line. That is deliberate: the optimisation is of the text *leaving* the JVM, and
it is worth the same whether a renderer or the raw write consumes it.

## 3 Invariants

Each row: the property, where it lives, and the gate that pins it. **No gate** is an explicit result.

| # | Invariant | Mechanism | Gate |
|---|---|---|---|
| I1 | Only `cells[r][c]` with `r < rows && c < cols` is valid. `cells[][]` has a fixed `RC_MAX_COLS` stride, so past `cols` you read an earlier generation. | every writer bounds by `g->cols` / `plan.paintCols` | all `geo_*` cases compare through `eq_text`, which truncates at `cols`; the out-of-bounds read itself is guarded only by loop bounds |
| I2 | The cursor is never in the gutter. | `line_down()` and the coordinate clamp keep `cy` inside the viewport | `plan_gutter`: "gutter: cursor starts on the viewport top" |
| I3 | The gutter is exactly one screen: `open()` asks for `hist = rows` and is cut to `RC_MAX_ROWS - rows`. So `rows ≤ 128` gets a full-screen gutter, `129..255` gets less than a screen (the top rows can never slide back), `rows ≥ 256` is refused outright (`OPEN_NO_GUTTER`). | `open()` in `RenderJni.cpp`, `RC_MAX_ROWS` in `Render.h` | `caseNoScrollback` (`hist == window height`), `caseOpenRefusal` pins all five refusals and both boundaries of the 255/256 rule. Note `cols`/`rows` of **0 is the "ask the console" sentinel**, not a zero-width grid — a test that wants "too big" must pass a negative. |
| I4 | `align()` **adopts** the current screen; it does not clear it. | `align_grid` reads the console at the model's anchor (I28) and copies what it finds into the model's viewport rows — the gutter above them is not read, and a rebuilt grid adopts the claim it carried rather than the rows under the window | every case's precondition ("align adopts the console"), `caseRealign` |
| I5 | One flush applies in a fixed order: slide → buffer scroll → rectangles → attribute → cursor. | `paint_flush` | `caseScroll`, `caseManyScreens`, `caseNoScrollback` on a live console |
| I6 | Geometry: `hist = rows - winRows`, `viewBase = winT - hist`, `base = baseSet ? max(viewBase, baseRow) : viewBase`, `ours = (winT == base + hist)`, `free_slide = ours ? bufH - winRows - winT : 0` (clamped at 0), `slide = min(k, free_slide)`, `bufScroll = k - slide`, `row0 = base + slide`, `winTop = ours ? winT + slide : winT`; `skip`/`drop` from `row0`, and a plan that would address `row0 + rows > bufH` declines whole. A cursor the plan cannot place inside the window the plan leaves behind sets `cursorOffView` and forces `cursorMoved` to 0: following output with a view the user has walked away from is what neither reference terminal does — conhost's `SnapOnOutput` refuses exactly that transaction ("We only want to snap if the user didn't intentionally scroll away", screenInfo.cpp:1715-1726, and `MakeCursorVisible` slides by the least displacement it can, 1684-1705), ghostty's default `scroll-to-bottom` is `{ keystroke = true, output = false }` (Config.zig:10446) and a program cannot address a viewport at all (point.zig:26-30). | `rc_plan_paint` rules 2 and 3, and the clamp at the end of the function | `plan_gutter` on both a wide and a scrolling shape, with every one of those numbers asserted; `plan_anchor` for the `ours` arms and for `cursorOffView` |
| I7 | **A model row is a buffer row**: `cols == bufW - winL`, so each row is painted to the *buffer* edge. A narrow window is never a reason to decline; only the buffer row width and the viewport height are. | the `cols` comment in `Render.h`; the geometry test in `rc_plan_paint` | `plan_runs`, `plan_declines`, `caseEraseToBufferWidth`, `caseRealign`, `caseWideBuffer`; live: the wide-buffer A/B leg. This is a user ruling ("the model is buffer-wide; I7 does not narrow") made against a measured saving, because wide result sets must print in full. |
| I8 | The painter never leaves the cursor right of `winR`: the plan carries `curTX = min(winL + cx, winR)` while the model keeps the true column. | `rc_plan_paint` | measured first: conhost slides `srWindow` sideways to include an out-of-window cursor, and the next frame then fails its geometry check. `plan_cursor_past_window`, `caseWrap`, `caseWideBuffer`. |
| I9 | The mid-chunk paint hook runs inside `rc_feed`: it may call `rc_paint_done`, it must not touch the parser. The grid is consistent at that moment; the input is not consumed. | the `onFlush` hook installed by `open()`, fired from `scroll_up` when the gutter fills | `plan_gutter_hook` (hook called N times, every row painted at least once) |
| I10 | One parser per chunk — and now one parser per process. Two deviations from ConEmu are deliberate and documented in `Render.h`: an ESC inside a CSI abandons and restarts (ConEmu parks the ESC and prints `31m` for `\e[3\e[31m`), and the resumable state machine replaces a byte-limited re-parse buffer that silently drops input past 512 bytes. | `rc_feed` | `gm_abandon_and_restart`, `gm_pending`, `gm_double_esc`, `check_resumable` (every corpus replayed one UTF-16 unit at a time) |
| I11 | SGR sequences consumed by the model are captured, and the capture is **drained at the end of the render** so it cannot accumulate across chunks. Slot 16 counts capture overflows, which is now a parser fact and nothing more: there is no second parser left to replay to. | `cap_push` / `rc_sgr_clear` | every case ends with `slot 16 == 0`; `gm_echo` |
| I12 | `defAttr` — the console default the SGR reset returns to — is frozen for the life of the handle and survives re-adopt. | `RcGrid::defAttr`, seeded at `open()`; a re-adopt deliberately does not re-read it | `geo_sgr_bits`; the re-open path in `caseRealign` |
| I13 | Erase overwrites attributes wholesale rather than merging, so the trailing half of a wide glyph is destroyed by design. | `fill_span` | `geo_erase`: "erase kills TRAILING" |
| I14 | Display width is the `ansi_width` table and nothing else: control 0, wide 2, combining 0. The model's three provenance choices are fixed: upstream's `Wcswidth` equivalence, ambiguous-width code points as **wide** — except the 206 code points measured one cell in *every* console font on this box, which stay narrow (`AMBIGUOUS_NARROW` in the generator: box drawing, block elements, the accented Latin letters) — and no VS16 promotion (so `A\uFE0E` and `A` are the same width). Disagreement with a font's advance is therefore a consequence of the choice, not a defect. The grid always stores the **original code point** — sanitising happens, if at all, on the way out to another interpreter. `ESC ( 0` is unaffected by all of this: `put_cp` takes the width from the *letter* it was given and only then remaps the glyph, so a drawn border stays one cell per letter whatever the ruled width of the glyph it paints. | `rc_width` | `check_widths` compares against the generated table across the whole code point space and pins both outcomes of the ambiguous ruling; `caseWideGlyph`, `caseWrap`, `caseAstral`, `geo_jline_stream`. Cost of the ruling and its cross-validation: see §7. |
| I15 | Colour is ConEmu's chain: `ReSetDisplayParm` → `ExtPrepareColor` → the `Far3Color` fold, with the fg==bg avoidance applied **at paint time** and only when the background really went through the COLORREF fold (index > 15). | `rc_attr`; `vendor/ConEmuRgbMap.h` and `vendor/ConEmuColors3.h`, extracted verbatim from upstream by a script and checked at build time | `check_colors` over the full 256×16 and 24-bit domains. The table is required because a re-derived formula disagrees with upstream on 15 entries. |
| I16 | Cursor visibility (`?25h`/`?25l`) costs one `SetConsoleCursorInfo`, and only on a real change. | plan's `setVisible` | `geo_sgr_bits`, `plan_plain`, `plan_declines`; the live gate does not assert `cursorOn` |
| I17 | An empty plan sends nothing: no read, no rectangle. | `RC_PLAN_EMPTY` and the early return in `paint_flush` | `plan_plain`; `flushQuietly()` in the gate |
| I18 | A paint failure inside the mid-chunk hook disables mid-chunk painting for that handle until an `align()` re-arms it; the refusal is reported at the end of the chunk. | hook teardown in `RenderJni.cpp`, re-arm at the end of `align_grid` | `caseHookDecline` (refusal leg and recovery leg), `plan_gutter_hook` on the host |
| I19 | An unsupported sequence is never swallowed silently: **count, and self-heal**. One counter per family. Only `RC_UN_SUP` — "this switch has no case, so its reach is unknown" — marks the frame suspect. Every *known* no-op (mouse tracking, bracketed paste, the reports this build declines to answer (I29), OSC/DCS framing, modes upstream cases but does nothing for) is counted and leaves the frame trustworthy. The suspect set has narrowed twice: DECSTBM and the alt screen both used to set it and left it when they were modelled. | `unsupported()` / `ignored()`, the self-heal at the end of `flush` and in `align_grid` | `geo_region`'s last block asserts the *current* partition family by family, including "a counted sequence with reach doubts the frame" and "CBT is counted but does not"; `geo_alt`, `gm_wrap_suspect`; `caseSuspectAlign` in the live gate; `report()` prints every non-zero family. Slot indices and `RC_UN_MAX` must never be renumbered — the census is positional on both sides of the seam. |
| I20 | Why a row wrapped is stored per row: `RC_WRAP_FORCED` (the cursor was pushed off the right edge, so the next line continues this one) and `RC_WRAP_PAD` (a wide glyph did not fit and the whole glyph wrapped, leaving a padded cell). Erasing to the edge or moving the cursor explicitly clears it; `scroll_up`, IL and DL carry it. It is not a `CHAR_INFO` bit and never reaches the console. | `rowWrap[]`, set at the four places that can wrap | `gm_wrap_suspect` covers set, clear, carry. A live-console gate is impossible: the bit cannot be read back, which is exactly the `CHAR_INFO` contract in §5. |
| I21 | OSC/DCS are never silent. Titles (`0`/`1`/`2`, with upstream's guard: a digit immediately followed by `;` and a non-empty payload) reach the console; every other family gets its own counter — private 9, other OSC, DCS, unterminated title. Over-long titles are truncated at `RC_TITLE_MAX`, not dropped, and the truncation is counted. A title either lands or is counted; there is no third option. | `osc_finish()`, the payload sink, the title fetch in `RenderJni.cpp` | `caseOscTitle` (applied, painted nothing, counted, truncated at the model's own cap, ST-terminated, private family keeps its own counter and does not change the title, abandoned OSC counted but never applied, DCS counted) |
| I22 | Damage granularity is a **column range**: a dirty row also records `[dirtyLo, dirtyHi]`, and the rectangle write is issued for that range. This is not a narrowing of I7 — the model still stores and can still paint whole buffer rows; the saving is only "columns nobody touched are not rewritten". Ranges are unioned, so a merge can only widen. Two rules bound the risk of painting too *little*: anything that cannot name its range says "whole row" (`rc_mark_all_dirty`, IL/DL, a scrolled-in row), and the bounds check scans the whole corpus. **An adopt is not in that list** (#103): `align_grid` reads the window into the model, so afterwards the viewport is the one region the model *can* name as unchanged, and `rc_adopt_clean` drops its damage instead of marking it -- the rows above the viewport were not read and stay owed. | `mark_dirty` / `mark_row_dirty` / `rc_mark_all_dirty`; `RcRun.lo/hi`; `build_row` / `write_rect` translate the range into buffer columns | `geo_damage`'s range block, `plan_damage_range`, `check_damage_bounds` (every corpus × every gutter shape, at that shape's own width), `grid_equal` now compares damage too; live `caseNarrowRepaint` and `caseWideBuffer` |
| I23 | OSC 133 (FTCS) is a first-class sequence, not an unknown OSC. One letter in field 0 (`L` takes no option; an unknown letter is a no-op, not a suspect). `A`/`N` start a prompt, adding a line first if there is none — the only place in the family that moves the cursor; `P` is a prompt that does not owe a line; `B`/`I` mark where input starts; `C` marks output start and recovers a fish-style continuation; `D` stamps the nearest marked row **above** the cursor with an exit code and `D` with no code leaves the recorded exit unknown. Marks are per row, model-side only, like I20. Guard: digits immediately followed by `;`, so `]0133;A` and `]1334;A` do not match. | `ftcs_apply()` and its helpers; `rc_row_mark` / `rc_prompt_marks`; the last-exit slot | `gm_ftcs` (per-letter semantics), `geo_ftcs` (marks in the grid and their transport), `caseSemanticPrompt`. One recorded deviation, from the era when a declined chunk went to a second parser: those chunks lost the marks. That path no longer exists. |
| I24 | The alt screen is one behaviour with three codes: `?47`, `?1047`, `?1049` all do the same thing (as upstream's `ASB_AlternateScreenBuffer`), `?1048` saves/restores the cursor only. Entering snapshots the viewport rows; the alt's viewport *is* everything and has no scrollback, so a row leaving the top is gone. Leaving restores. Leaving without entering is safe (the restore is gated on the flag, not the pointer). Scrolling in the alt costs no scroll operation. The only refusal is a failed snapshot allocation — which is why the family's counter means "this one did not happen" and both its slots stayed where they were. **Width: the alt is buffer-wide today and that is a known deviation, not a decision.** `snap` is "malloc'd on the first entry at this grid's own stride (cols wide, winRows tall)" (`Render.h:441`) and `cols` is the buffer row width per I7, so an alt screen inherits the buffer width; the owner's ruling of 2026-09-28 is that the alt has no scrollback to protect and should therefore be sized by the *visible* width. Not taken in this pass (recorded, then left alone) because the same pass was changing I25, and an alt-width change moves the snapshot stride, the pair-healing bounds and every `caseAltScreen` expectation at once. | `alt_screen()`, `rc_in_alt`, the `snap*` fields (allocated at this grid's own stride, freed by `rc_reset_hist`, carrying wrap and FTCS marks too) | `geo_alt`, `caseAltScreen`; census "N alt-screen switch(es), M refused" |
| I25 | DECSTBM (`CSI r`) is a region in the model, not a counted refusal. Bounds are clamped to the viewport when set and never re-clamped. Two resets are fixed: a region exactly covering the viewport is recorded as *no region* (the gutter and scroll paths branch on that, and a coincidental full region must not take the other arm), and a bare `CSI r` resets. A geometry change resets it, so a re-opened grid has no region. **A line feed decides by the TOP margin alone** (rewritten 2026-09-29; the earlier 2026-09-28 take shipped as -55/-56 and was rolled back whole with its round, so this build re-derives the rule from the references rather than from that round's artifacts): `top > gutter()` or `marginSet` ⇒ `shift_region`, confined, the evicted line is discarded and the window does not move; `top == gutter()` with the full row span and `bot == rows-1` ⇒ `scroll_up`, the whole-model ring; anything else with the top at the viewport top ⇒ `line_down_page_scroll` -- `rotate_span(0..bot)` so the evicted line lands in the gutter as history, row `bot` blanked and dirtied, `pendingScrolls += 1` so `Paint.cpp` rule 3 can slide the window, and the band below `bot` dirtied because it keeps its content but loses the buffer row it was painted on. The references agree and none of them lets the bottom margin confine: MSFT confines only when `topMargin > page.Top()` and otherwise pans the viewport, copying the band below the bottom margin down to hold it static (adaptDispatch.cpp:2454, :2461-2467, :2474-2477); ghostty creates scrollback whenever the region top is screen row 0 with the full row span, bottom margin or not (Terminal.zig:2392-2411, `cursorScrollAbove`), and confines for a narrowed top or margins (:2436, `cursorScrollRegionUp`); wezterm's `c1_index` scrolls within the margins at the bottom margin and its line list keeps what leaves the top (terminalstate/mod.rs:1228-1239). The horizontal half of the condition is read as `marginSet` ("does the scrolled rect span a whole row"), because our row is buffer-wide by I7 and MSFT's page is window-wide. **No slide-room gate, on purpose** (the rolled-back round had `RcGrid::slideRoom`/`RcPlan::canSlide`; this build does not reinstate them): `Render.cpp` stays console-free, and when the window has no room left to travel the charged scroll is paid by `ScrollConsoleScreenBuffer` -- the same payment the no-region path has always made at the buffer's last row, one call per flush, local on a classic console. The painter cannot be engaged under a pseudo-console (WinSysTerminal's `pseudoConsole()` test precedes every writer choice), so the pty re-serialisation cost that argues for a guard has no production leg. IL/DL/SU/SD stay confined in both shapes (they are not line feeds, and MSFT's pan is `_DoLineFeed`-only). | `case 'r'`, `region()`, `regSet`/`regTop`/`regBot`, `line_down` + `line_down_page_scroll` | `status_bar`'s assertions ("the window advances" = 1, "the bar's row owes a repaint" -- made a real witness by the `rc_paint_done` ahead of it), `geo_region`; mutation arms `band`/`discrim`/`charge`; live: `legsSame("DECSTBM then a scroll", …, TRUE)` -- the two legs agree, and the expectation was flipped when the model gained the feature. |
| I26 | The terminfo entry advertises only what the renderer actually models. Absence matters as much as presence: a lying terminfo is worse than a short one, because the reader does not re-check, it complies. | `windows-conemu.caps` in the host's terminal library | `geo_jline_stream` replays the bytes the host's own line editor writes — the 11 acsc letters it emits, `ESC (B` returning them to text, and an in-place edit landing on the right columns |
| I27 | A slot is claimed until it is closed. Ownership (`taken`) and having a model (`g`) are separate; `stats()` and `stopReason()` work on a claimed slot with no model; `open()` claims an unclaimed slot and returns the claim when it refuses. | `slot_of()` vs `handle()`, `open()`, `release_all()` | the four-slot and refusal tests in `caseOpenRefusal`; the census readable after give-up is asserted by the report path in the live gate |
| I28 | **The anchor is carried across a rebuild, not re-derived from the window.** A grid is rebuilt on a decline, on a resize, and on a `close()`-free re-adopt; each of those would otherwise ask the console where the model's rows are, and the console's answer is the *window* — which the user may have moved, and which a resize has just moved by itself. So the previous claim's **bottom** row is carried into the new grid (`vb - rows + 1`), because a rebuilt grid has a different height and the row the content ends on is the one that means the same thing in both. conhost's straddle sweep — a view that ended up between the old and new window bottom loses the claim — applies **only when the grid changed height** (`reshaped`), because that rule belongs to `_InternalSetViewportSize` (screenInfo.cpp:953, check at 1110-1112) and `SetViewportOrigin`, which is what the scroll wheel drives (642), has no such rule. A carried claim is kept only where the grid it anchors is legal (`vb ≥ winRows-1`, `vb ≤ bufH-1`), which is conhost's own "may not poke above row 0" guard in row-0 form. | `RcHandle::prev*`, `rc_anchor_adopt` | `adopt_anchor` on the host (carry, sweep-when-reshaped, not-swept-on-a-plain-adopt, both illegal-claim arms); live: `caseScrollKeepsHistory`'s resize leg, which calls `readopt()` after dragging the window shorter while the view is scrolled up, and asserts the next prompt lands below the carried anchor with the user's rows unchanged |
| I29 | A device-status or identification query is **answered**, into the console's input stream, and never silently. One `KEY_EVENT` pair per character at `WriteConsoleInputW`, the same synthesis conhost's own ANSI output leg uses (outputStream.cpp:43-45 → inputBuffer.cpp:799-816), so a program blocked on `tput rows` wakes. Replies are flushed at the **end** of a successful paint, even one that painted nothing — the reply is about the reader, not the screen — and are **never** written for a declined chunk, because conhost answers the replayed bytes itself and a second reply would be stray input for the next reader. The queue is bounded: a query that arrives when it is full is refused and counted, not queued and not dropped. Three counters, no fourth outcome: written, failed, refused-for-full. | `rc_report_*`, `flush_reports`, `reply_text` | `gm_reports` on the host (one reply per query and no second one for a later move, FIFO over the three kinds, the cap, the kinds that arm nothing); live: `caseReports`, whose `eqInput` drains the console's input stream and compares the *text* — `\E[4;7R` for a cursor placed at `CSI 4;7H`, and "answered from the snapshot, not from the cursor now" — which is the only witness that can say what a reply *said*. Census: "replies written=N (M failed, K refused)" |
| I30 | **While the buffer has room below the claim**, a buffer scroll moves the rows the anchor claimed **before** this flush's slide, and `ScrollConsoleScreenBuffer`'s destination is an **absolute** buffer coordinate. A slide moves no cell — it asks conhost to drag the window over rows that are already where they belong — so the cells that owe a shift of `k` are the ones at `base + r`, which means a source rect starting `k` rows below the row the plan now addresses (`row0 + by`) and ending at the old band's last row (`base + rows - 1`). Getting either half wrong is invisible in the window, because every row the scroll touches is dirty and gets repainted anyway, and fatal in scrollback: a relative destination turns the call into a shift of `-(by + srcTop)` and hoists the model's whole band hundreds of rows up over the user's history. The band is clamped at both ends (a model reaching above row 0, a shape that moved under the plan); a `by` at or beyond the band's height is a no-op with a reason, since `scroll_up` blanks and marks the whole grid in that case and the paint that follows covers it. | `rc_scroll_band` (the arithmetic, console-free), `scroll_region` (the call) | `plan_scroll_band` on the host, over the `room:` (band, nothing of the user's in it), `whole:` and `gutter:` shapes; live: `caseScrollKeepsHistory` (100 lines through a 400-row buffer, then the view scrolled to row 0 and one more line) asserts per chunk that the ink landed inside the claimed band and the window stayed put, and gates its own premise — `base + rows < bufH`, which is what keeps this branch the answer |
| I31 | **Once the claim a flush leaves behind has the buffer's last row, the scroll's reach is the buffer, not the claim.** A full console buffer has one answer to a new line: everything rides up by `by` and the oldest `by` lines leave the top — conhost's `_stream.cpp:123-126` → `TextBuffer::IncrementCircularBuffer` (reset row 0, advance `_firstRow`: textBuffer.cpp:722-745). The deciding quantity is the plan's **destination** (`row0 + modelRows >= bufH`), never the anchor it started from, because **a slide does not escape an eviction**: sliding is how the claim gets to the last row and it moves no cells, so a flush of `k` lines that slides `f` still owes the remaining `by` evictions — and sliding as far as the buffer allows puts `row0` on `bufH - rows` by construction, which makes every mixed flush an eviction. Inside the claim the rows land identically either way, so the paint is untouched; what changes is everything above it. Where there is no scrollback to move (`row0 == 0`) the two branches coincide. Leaving the eviction unpaid is not conservative: it puts more live lines into the buffer than it has rows, and the shift then drops one of them **in the middle** while the window, being all-dirty, shows nothing. | `rc_scroll_band`'s `full` arm, `scroll_region` | `plan_scroll_band`'s `full:` and `mixed:` shapes (source starts at `by` and ends where the *old* claim ended, lands on row 0, "the claim's own rows ride as before", and a saturated slide's corollary asserted alongside the anchor that would have said otherwise); live: `caseFullBufferEvicts` — 420 numbered lines in 20-line chunks, then the view scrolled to row 0 and one prompt line — which censuses all 400 rows for an unbroken in-order run, compares every row above the claim against a before-capture (`wrong=0 kept=340`), and names the cursor's own blank row rather than assuming every row holds text; oracle: `cache/wide-probe/StartupRepro.java` raw leg vs render leg through `su-cmp.py`, both shapes, "no line the console kept" / "no hole" / "the lines land in order" |
| I32 | **DECSET `?2026` defers a frame, it never defers an answer.** While the mode is on, a flush that would have painted returns "held": the plan is thrown away unexecuted, the damage it was built from stays marked, and the next flush therefore paints everything the region accumulated in one go. Nothing is *stored* about the deferred rows — the model already holds them, and a second copy of a 4 MB grid to say "these cells changed" would be the worst kind of honesty. Four rules make the hold safe to ship rather than merely correct. (1) **The region's first frame is held too**: an application writes its BSU together with the top of the new screen, so a renderer that paints that chunk has just drawn the new frame's head over the old one. (2) **The hold is bounded by a clock, not by silence.** `RC_SYNC_TIMEOUT_MS` is 100 ms and is measured from the first held flush, so it bounds the *age of the region*; the tick is never re-armed by a later chunk, because a re-arming clock would let an in-place, never-ending region freeze the screen forever and would remove the floor MSFT keeps deliberately (`renderer.cpp:540-570` waits on `_isSynchronizingOutput` with `timeout - elapsed`, then unconditionally clears both the flag and `Mode::SynchronizedOutput`; `renderer.cpp:517-537` notes a ~10 FPS floor against BSU spam). An expired clock paints **and clears the mode** — a program that leaked its ESU must not have the rest of its session swallowed one frame at a time. (3) **The scroll gutter outranks the mode.** `scroll_up` asks for a paint once `pendingScrolls` fills the gutter, which is the last moment the rows about to be evicted still exist on screen; answering "not yet" there would let the model evict history the console never painted. So a full gutter paints, counts the preemption, and **leaves the region open** — the two escape hatches differ on purpose. (4) **Replies go out either way** (I29): a query's answer is about the reader, not the screen, and a program that asks `tput rows` inside its own synchronized region while we wait for its ESU is a program that hangs. Its CPR is answered from the plan this flush declined, which describes exactly where the rows will be when the region ends. An empty plan is never held — a chunk of cursor moves only opens or closes the region, and counting those would make the census claim frames were deferred that were not. A declined chunk ends the region (I19's decline path). Nested BSU is a counted no-op; `RIS`/`DECSTR` clear the mode. | `g->sync` set in the `?2026` arm of `h`/`l`; the hold block in `paint_flush`; `RcHandle::syncSince/syncHolding`; `RC_SYNC_TIMEOUT_MS` | `geo_sync` on the host (first frame held, no paint, replies still out, ESU flushes once, timeout paints and clears, gutter preempts and keeps the mode, nested counts, decline ends it); live `caseSyncOutput` (asserts `rectangles == 0` for the whole region and `== nhold` on the flush that lands) and `caseSyncOverflow`; census "sync updates=N (M nested, K flushes held, ended early by X timeout / Y gutter / Z decline)". The gate's hold leg measures its own cheapest paint (`chunkCostMs`) and asks for the number of holds that fits inside the clock, so it tests the contract instead of the machine's latency. |
| I33 | **HPR (`CSI a`) and VPR (`CSI e`) clamp to the viewport, not to the scroll region.** Both reference terminals agree on the one property that matters: MSFT says so in prose — "Unlike CUF/CUD, this is not constrained by margin settings" (`adaptDispatch.cpp:427`, `:437`) — and ghostty routes both to the same margin-free cursor path (`stream.zig:1863`, `:1942`). So they take `clxy`, which clamps to the viewport, and not `move_row`, which honours the region. VPR keeps the *column*, which is what a test written from CUF/CUD intuition gets wrong: characters printed after a VPR advance it, so an expectation of "column 0" was a bug in the expectation, not in the renderer. ConEmu has neither case (its `Ansi.cpp:3816` switch falls to the default at `:971`), which is why these two sat in `RC_UN_SUP` until build -17. | `case 'a'` / `case 'e'` in `Render.cpp` | `geo_hprvpr` on the host — including "VPR past the region bottom stops at the viewport bottom" and "`RC_UN_SUP` does not grow"; live `caseRelativeCursor`. Control arm `cache/witness/hprvpr-control-20260925.txt`: replacing the two arms with `break` + `move_row` produced exactly 8 host FAILs, all in these legs, which is what certifies them as watches rather than decoration. |
| I34 | **The palette is console state, so OSC 4/10/11 changes it and `close()` hands it back.** ConEmu parses these and does nothing, so the grammar here is taken from MSFT, which implements them: `OSC 4` is `(index;spec)*` with `?` as an inquire per index, `OSC 10/11` walks resources forward one per field, `OSC 104` resets slots and stops at the first unparseable index, `OSC 110/111` reset the defaults only with an empty payload (`OutputStateMachineEngine.cpp:779-866`, `:955-1000`, `:1062-1092`). Accepted specs are `#RGB`, `#RRGGBB` and `rgb:r/g/b` with one to four hex digits each, scaled to 8 bits from the top of the field (`ColorFromXParseColorSpec`, `types/utils.cpp:180`); **an X11 colour name is resolved since #84** (`vendor/X11ColorNames.h`, 676 folded keys, generated and cross-checked by `gen_x11colors.sh` -- note that MSFT's own table is not "130 rows": `colorTable.cpp` expands to 669 keys, and the number 130 had been copied around this tree for weeks without ever being measured). A name that is *not* in the table is still counted `RC_UN_OSC_OTHER` like any other unparseable spec, which is the I18 mechanism working rather than a claim that nobody sends one; and a field that begins `#` or `rgb:` is never re-tried as a name, because one spelling must not answer two shapes. Two ranges, two effects: indices **0..15** rewrite the console's own 16-entry table through `SetConsoleScreenBufferInfoEx` (the only palette API a classic console has) *and* the folding table, so what the user sees changes -- but the console write is read-modify-write over the entries an application actually touched (`palTouched`), because setting `OSC 4;3;...` must not silently recolour the other fifteen. The fold table is seeded from `RgbMap`, all 256, and the console's live ColorTable is deliberately **not** consulted: on Win10/11 that table is Campbell while upstream's fold has always used ConEmu's own, so re-seeding would recolour every 256-colour and true-colour SGR in the product -- a change worth measuring on its own, not a passenger on this mode. The gap that leaves is stated plainly rather than hidden: for an index nobody set with OSC 4, the fold believes ConEmu's colour while the console displays the user's. indices **16..255** change only the folding table, because a 4-bit attribute has no other slot to put them in -- `SGR 38;5;196` changes which index it lands on, not what a base colour looks like. The first write of a handle saves the console's current 16 entries and `close()` restores them: a renderer that recolours the user's console and leaves it recoloured is a vandal, and the palette outlives the process on a shared buffer. `OSC 10/11` can only be honoured as an **index** -- the console's default attribute is 4 bits per channel -- so `defAttr`'s nibbles are re-pointed to the nearest entry and a query answers with the RGB of the index actually chosen, i.e. the *effective* colour, not the requested one. That is also the one place where I12's "frozen for the life of the handle" gains an exception, and the exception is the mode's whole purpose. **The re-point stays model-side, and that is a limit rather than a choice**: on a classic console `CONSOLE_SCREEN_BUFFER_INFOEX.wAttributes` *is* the current pen, which the same flush has just set from the plan, so pushing a default into it would fight `SetConsoleTextAttribute` once per frame for one application request. Every cell this library writes carries an explicit attribute, so the visible effect is complete for output; what differs is a fill conhost makes by itself, such as the row a resize brings in. The parser stays console-free: it mutates `g->palette[]` and the `palTouched` mask, and the painter applies the marked entries at the end of a flush, exactly as it applies a cursor shape; a grid rebuilt mid-flush carries both, so a pending console write cannot be lost by the rebuild. And the memo in the vendored `Far3Color::Color2FgIndex` (`static LastColor/LastIndex`) is palette-blind -- with a dynamic table it must be bypassed, or a colour folded before the change folds to the old index forever. | `Render.cpp` (`palette_*`, the OSC arm in `osc_finish`, `rc_attr`'s palette parameter), `Render.h` (`palette[256]`, `palTouched`), `RenderJni.cpp`'s `RcHandle` (`palOrig[16]`, `palOrigSaved`), `Paint.cpp`/`RenderJni.cpp` (apply at flush end, restore at close), `vendor/ConEmuColors3.h` (the memo guard) | `gm_palette` on the host: grammar (pairs, `?` mid-list, 104's stop-at-first-bad, 110 with a payload ignored), the two ranges having different effects, `defAttr` re-pointing, a fold that follows the palette it was given, and the attribute/index round trip at the seed sites -- control `cache/p55/control_arm.py` reverts that conversion and fails exactly four assertions, all of them `got 0x4 want 0x1`. Live: `Render.consolePalette(long[])` reads the console's 16 entries off CONOUT$ and asserts the change landed, that the second write did not revert the first, that the **window did not move** (the ninth slot of `consoleView` is `winB` precisely because the InfoEx round trip costs a row and every other field looks untouched), that the query comes back as bytes, and that `close()` restored the table it found. Answering a query inside a synchronized region is I32's existing leg, which is report-kind agnostic. Numbers: host `checks=3502 fails=0`, live `checks=5205 failures=0` on both architectures and again against the deployed bytes. |
| I35 | **`CSI ?7 h/l` decides whether the margin ends the line.** With the mode off, a glyph is written to the last column and every further glyph overwrites that one cell: the cursor holds at the margin, the row takes no `RC_WRAP_FORCED` claim (nothing ran off its edge, so copy and export must not join it to the next row), and no row below is started. A glyph that cannot fit is dropped **whole** -- MSFT clears the cell it could not fit and says why ("Ignore the character. There's no correct alternative way to handle this situation", `Row.cpp:474-494`), and its anti-deadlock guard names this same case for wrap off (`MSFT_TERMINAL_REFERENCE.md` section 2.1). A wide glyph and a narrow astral pair are both dropped as units, because half a surrogate pair is not a character either. Two invariants the clamp made reachable, so it enforces both: the margin clamp steps **off** a trailing half (a cursor never rests inside a glyph -- `step_back_col`'s rule), and a narrow glyph written over a wide one's front half blanks the orphaned back half (I16's pair is one unit; conhost trims the same cluster). Without the second one, every no-wrap row that mixed CJK and Latin would leave a half glyph at the margin. `RIS`/`DECSTR` restore the mode, DECRQM answers 1 or 2 for it, and it left `RC_UN_MODE` the day it became modelled. **What this does not buy is not a gap:** `smam`/`rmam` stay out of the terminfo entry, because the entry describes sessions where ConEmu's own parser reads the stream and ignores `?7` (its `SetConsoleMode` is commented out, `Ansi.cpp:3268-3281`) -- I26 -- and no dbcli code path sends the pair today (`lua/ansi.lua` defines WRAP and UNWRAP with the call sites commented out at :346-352). This is the third-party case: whatever the screen this library owns is handed gets modelled, not whatever this one product happens to emit. | `RcGrid::wrapMode`; `put_cell`/`put_pair`'s fit test, pair trim and margin clamp; `blank_cell`, `last_free_col`; the `?7` arm of `h`/`l`; `mode_status` | `geo_decawm` on the host (hold-and-overwrite, no wrap claim, drop-whole for a wide and for a narrow astral, step-off-the-trailer, the trim with wrap **on** reached through a CUP, DECRQM 1 and 2, both resets, GATM's non-private spelling still unmodelled, and the MODE census falling to 2 with `?7` left in the stream); live `caseDecawm` (the buffer row's last column holds the last of three overwrites, the row below never starts, the console cursor stays inside the window while `stats` says the model is at column `BUF_W-1`, and `?7h` resumes the wrap from the next character) and `legs("DECAWM off at the margin", ..., FALSE)` -- the first *cell* divergence in that family: native `Q` at column 199 against hk `R` with its `Q` one row down. Numbers: host `checks=3713 fails=0`, live `checks=5469 failures=0` on both arches and again against the deployed bytes. |
| I36 | **Whatever an escape sequence can make happen outside the screen is the host's decision, and the parser's shape is what makes that checkable.** OSC 52 is the first sequence in this library whose effect leaves the console: it asks for the user's clipboard, which belongs to other applications and outlives the session. So the switch is off by default and is only reachable from the host -- `ANSI_CLIPBOARD` read once at class-init, or `NativeRenderer.setClipboardPolicy` -- and nothing the byte stream carries can turn it on, which is the property the census cannot supply on its own (a count cannot distinguish a terminal the user configured from one a script configured). There is no ASK state, because a library that owns no window has no way to ask and inventing a prompt channel would be a second product, not a renderer. Refused, each with its own counter so a report says *which*: a selection field other than `c` or empty (one clipboard on this platform, so `p`/`s`/`q`/`a`-`d`/`0`-`7` are not folded onto it -- ghostty folds only because X11 and macOS really have those registers, `stream_terminal.zig:678-682`); a **read** (`52;c;?`) refused even with writing enabled, because the reply would place what the user last copied into the console's *input* stream -- i.e. into the next command line; a payload that fails a strict RFC 4648 decode (whole-payload or nothing, no whitespace skipped, the final group's unused bits required to be zero, a decoded NUL refused because `CF_UNICODETEXT` is NUL-terminated, so storing the prefix would hand the user half a paste); and a payload over the sink cap. An empty payload is the *clear* request, not an absent one. Nothing is restored at `close()` -- snapshotting the register at open would be the read this half refuses. ConEmu implements none of this (measured: its OSC switch has no `case L'5'`), but **both reference terminals do, and both default to allowing it**: Windows Terminal's `OscActionCodes::SetClipboard = 52` (`OutputStateMachineEngine.hpp:222`, dispatched at `.cpp:821-827`, `adaptDispatch.cpp:3302`) is gated by `compatibility.allowOSC52`, whose default is **true** (`ControlProperties.h:59`, `MTSMSettings.h:119`, read at `Terminal.cpp:106`), and ghostty's `clipboard-write` defaults to `.allow` (`Config.zig:2459`). This library's off-by-default is therefore a **deliberate divergence from both references** and the reason is ours to own: those two are terminals the user configures and answers for -- a setting exists because somebody opened it -- while a renderer living inside someone else's JVM has no such config and no consenting party, so silence must read as "not agreed", never as "agreed". Where the references agree, so do we: neither *answers* a read (WT parses `?` and then drops it, `.cpp:825`; ghostty gates reads behind `clipboard-read=.ask`). One deliberate split remains: WT ignores the selection field -- its own comment at `:1097` says "Currently the first parameter `Pc` is ignored", so `52;p;…` writes the clipboard there -- while this build refuses anything but `c` and empty, because folding answers a question nobody asked. **The second half of the invariant is structural, and it is what let the first half be tested at all:** `osc_finish`'s chain of `if (code == ...)` tests became `rc_osc_families[]` -- `{name, owns(code), apply(...)}` -- because the chain could not be *asked* anything. `geo_osc_families` now sweeps codes 0..4096 for double claims (table order is precedence, and that is only readable as priority if no code is claimed twice), demands that every claimed code has a probe and every probe a family, feeds one well-formed payload per family and asserts it neither falls through to `RC_UN_OSC_OTHER` nor sets `modelSuspect`, and witnesses the mark each handler leaves in a field list that is deliberately *not* the whole grid: the payload sink is part of the grid, so a struct-wide comparison would report "the handler did something" for every sequence that was merely parsed. | `RcGrid::osc[]/nOsc`, `clip[]/nClip/clipPending`, `wrapMode` unchanged; `g_clipPolicy` + `rc_set_clipboard_policy`; `rc_b64_decode`, `osc_clip`, `rc_osc_families`, the tail of `osc_finish`; `clip_apply` and the pending block in `paint_flush`; `NativeRenderer`'s static block and `clipboardPolicy()/clipboardWriteAllowed()` | `gm_clipboard` (the decoder's alphabet, padding, canonicality and length rules one at a time -- including the non-canonical `QR==` case that caught this function's first bug -- then policy off, policy on, `c` vs empty vs `p`, the read, the cap, the NUL, and the empty payload as a clear) and `geo_osc_families` (disjointness, probe coverage, no fall-through, no silent handler) on the host; live `caseClipboard`, which is the leg that cannot be satisfied by the model: it reads the clipboard back from a **second process**, because AWT in this JVM answers from the object it was given once the process owns the clipboard, and that cache made eight assertions red for reasons that had nothing to do with the painter. Numbers: host `checks=4065 fails=0`, live `checks=5517 failures=0` on both architectures and again against copies of the installed bytes. |

| I37 | **A parameter that counts things is bounded by what there is to count, and the bound is named where the parameter is read.** `CSI Ps` has two readings, not one. DEC's rule -- an absent parameter and a zero parameter are the same request, and both mean one -- is the common one, but ECH and REP read the value **raw**, because for them zero is an answer: `CSI 0X` erases nothing and `CSI 0b` repeats nothing (ghostty clamps both to one and is the odd one out). And a count is never the number the application wrote; it is that number limited by the rows below the cursor, the cells in front of it, the region it was told to work in, or the model. Writing each limit as an argument to one helper instead of as an `if` at the arm is what made two of them wrong visible in a week: **DL** had been bounded by the viewport's height when its own blanking loop starts at `rows - n`, so an over-large delete erased the rows *above* the cursor and left its own row standing (IL's loop starts at the cursor, so the same bound was harmless there -- the defect was in a quantity, not in a direction), and **DECSTBM** carried three clamps of which two were unreachable because `arg()` cannot return the non-positive value they tested for. The same naming exercise caught a third thing, outside the model: the host gate's own text comparator could be asked to compare **zero** cells -- and vote "pass" having compared nothing, which is what one leg was doing -- or asked for **more columns than the grid has**, where the cells exist in the fixed `RC_MAX_COLS` stride and hold whatever a wider geometry left there, and its "short string means spaces" padding read past the string's own terminator into the next literal. Both shapes now refuse. What the accumulator's ceiling is *for* is the other half of the policy: digits saturate at `RC_ARG_MAX` rather than wrapping (deviation #3 -- `CSI 999999999999H` means the last row, never row 1610612736 mod the screen), while the OSC parser **refuses** ten digits instead, because there the number is a claim -- an index, an exit code -- and a claim arrived at by truncation is a different claim. | `count_arg`, `count_arg_raw`, `region_arg` (Render.cpp, beside `arg`), `RC_ARG_MAX` (Render.h), `shift_region`/`scroll_up`'s own guards (the model bounding a call from inside this file, which is a different act), `push_arg`'s `nArgTrunc`, `RenderCheck.cpp::eq_text` | `gm_argcap` (the 16-argument cap, the count per dropped argument, saturate-vs-truncate, and ICH/DCH/ECH at the row's end), `geo_region`'s gutter legs ("a delete of more rows than there are below the cursor reaches no higher"), `geo_ftcs`'s mark-in-transit legs, and four arms each seen red: DL back to the window's height (2), the counter un-counted (2), `count_arg` returning the raw argument (5), the accumulator allowed to wrap (1). Live: `caseArgClamp`, which reads both halves off a real console -- the cap through `Java_Render_argTrunc`, the bound through the cells above the cursor. Numbers: host `checks=5298 fails=0`, live `checks=5715 failures=0` on both architectures against copies of the installed -28 bytes (`cache/p63/live28c.txt`, the second -28 build). |

| I38 | **A sequence that can change a claim about the terminal needs stored state, and a resize is not allowed to quietly undo it.** `\t` used to be `((cx + 8) >> 3) << 3`, which is not a rule about tab stops but a restatement of the default interval -- and that is why four real sequences were unspellable here: with nowhere to write, `ESC H` (claim a column), `CSI 0g`/`CSI 3g` (clear one, clear all), `CSI Ps I` and `CSI Ps Z` (walk the table either way) could only be refused, and the refusal's own reason was a description of the implementation ("there is no stop for a back-tab to find"). #70 replaced the arithmetic with the state and its two facts -- a claim per column, and a flag saying whether the unclaimed columns are the interval -- and the flag is what makes `CSI 3g` different from a loop that clears the array: one empties the table, the other empties it *and* stops the defaults from ever coming back. Three consequences are pinned rather than argued. **Main and alternate share one table** because it is terminal state (MSFT on the adapter `:2649`, ghostty on the Terminal `Terminal.zig:56`). **A rebuild carries it** and materializes the interval only in the columns that did not exist, and only if nobody cleared it -- MSFT's `_InitTabStopsForWidth` (`:2799-2817`), against ghostty's rebuild-that-forgets (`Terminal.zig:4019`, `:4082`), and our own resize already carries the palette, the OSC 9 face and DECAWM for the same reason. **RIS restores it**, where MSFT's `HardReset` says nothing about tabs and ghostty restores (`:4943`): one reference each way, and the tiebreaker is that DEC's reset means "as at power-up" and a caller with no way to ask for its defaults back has no way to fix a wrong one. The rule generalises: where this document has ever said "not configurable" about something a VT sequence touches, that is a missing field, not a design choice. | `RcGrid::tabStop[]` + `tabsDefaults`, `tabs_default`, `tabs_reset`, `tab_next`, `tab_prev`, `rc_tabs_widen`; the `HT` arm, `case 'I'`, `case 'Z'`, `case 'g'`, `ESC H`, `full_reset`, `rc_reset_hist`; `build_model`'s carry in `RenderJni.cpp` | `geo_tabs` (defaults, HTS not erasing them, TBC 0 vs 3 vs 5, CHT/CBT walks both ending at the wall and at column 0, DECSTR silence, RIS restore, one table across the alt switch, and `rc_tabs_widen`'s contract: claimed stop kept, old columns not re-decided, new tail filled, nothing added after `CSI 3g`); arms T1-T4 each seen red (the arithmetic back in place, TBC 3 keeping the interval, RIS not restoring, the table treated as per-screen); live `caseTabStops`, which is the resize carry's only witness -- HTS, `readopt` (the rebuild production performs on a resize), then the same tab. Numbers: host `checks=5461 fails=0`, live `checks=5738 failures=0` on both architectures against copies of the installed -29 bytes. |
| I39 | **A row's place in the model is a claim about order, not about storage: the pool holds rows, `of[]` says which one is whose, and every per-row fact is read through that order.** The tab character needed a table and got one in #70; #75 is the same move on the vertical axis, where the table already existed and was being copied instead of permuted. Two rules follow. **Nothing indexes a per-row array by a model row by hand** -- `RC_CELLS`, `RC_ST`, `RC_DTY`, `RC_LO`, `RC_HI` are the only doors, which is what lets a scroll be one loop over `int`s: the damage overlay, the wrap claim and the FTCS mark travel with the content by identity, so the two carry calls that used to be responsible for them are gone and cannot be half-written again (I38's row is the same lesson on the other axis). And **`of` must stay a permutation of 0..rows-1**, which `rc_validate_grid` now checks on both gates -- a double-booked pool row paints one line twice and loses another, and nothing downstream can tell that from a wrong answer about the screen. The measurements that paid for the change are in §5. | `RcGrid::of[]` and the five accessor macros in `Render.h`; `rotate_span` and its four callers in `Render.cpp` (`scroll_up`'s two screens, `shift_region`, IL/DL with no region); the permutation leg of `rc_validate_grid` | host `checks=5472 fails=0`, live `checks=5738 failures=0` on both arches against copies of the installed bytes **with a stats line identical to -29's** (a rotation may not change what reaches the console), the oracle at `runs=455 violations=0` per arch, and arms R1-R6 each seen red (the `#75` row of `ANSI_TODO.md` §3) -- including R4, which came back green until a host leg for the alt's gutter was written. |
| I40 | **A mode a caller can set is a state the model must hold, answer for, reset, and carry -- and the refusal that described the implementation instead of the terminal was the tell.** IRM was refused for years with "there is no entity in the model whose behaviour IRM could alter"; that is a sentence about this code, not about a terminal, and the entity was the write path all along. #77 made the mode four things at once, because a mode that is only a bit is a mode that lies: it *acts* (a written glyph opens its own width, through the same `insert_cells` an ICH performs -- one primitive, so the two cannot drift), it *answers* (`DECRQM` for both `?4$p` and `4$p`: a probe is entitled to the same answer as the setter, and MSFT/ghostty both register the number as ANSI 4), it is *reset* by both resets (MSFT's `SoftReset` names InsertReplace and `HardReset` calls it), and it *survives a resize* (a rebuild carries it, like the palette, DECAWM and the tab table -- the live leg that proves this is the only witness in either gate that reaches `readopt`). Two rulings on the boundary: at the margin a glyph does not insert, it overwrites (ghostty's stated rule), and the *claim* a shift files covers every column from the cursor to the row's end -- which is where this round found a defect older than the mode: ICH and DCH had been claiming only the gap they opened, so the pushed text stayed on the screen at columns it had already left, invisible to every existing leg because the one leg that exercised a shift had wide glyphs in it and pair-healing incidentally claimed the cells. What stays out: the caps entry still does not advertise `smir`/`rmir`/`mir`. The reason on record here used to be "the entry describes sessions where ConEmu's parser reads the bytes" -- true when ConEmuHk sat on every write, retired with it (2026-09-24); what survives is the decline path only (a refused chunk leaves through `WriteConsoleW`, where a real ConEmu hook ignores `?4`, Ansi.cpp:3323-3329) -- I26 narrowed to that leg, and the same reason `smam`/`rmam` stay out (kept out §4, where the lapse condition is written down). | `RcGrid::insertMode` in `Render.h`; `insert_cells` and the IRM guard in `put_cell`, the `h`/`l` arm, `mode_status`, `full_reset`, `soft_reset`, `rc_reset_hist` in `Render.cpp`; the carry in `RenderJni.cpp::build_model` | host `checks=5593 fails=0`, live `checks=5768 failures=0` on both arches against copies of the installed bytes; arms I2 (private spelling only), I3 (no ANSI DECRQM), I4 (DECSTR leaves it), I5 (RIS leaves it) and I6 (the shift claims only its gap) each seen red on the host gate, and the carry arm red **on a real console** against a scratch build (`live31armL1.txt`: `(9,5) = U+46 want U+45`). I1 (drop the margin test) came back green and is recorded as such: `insert_cells` clamps `n` to the room left, so the degenerate insert is already an overwrite -- the guard is the stated rule plus skipping an O(cols) fill and row heal, not a behaviour. The hot path was measured, min-of-three against a control build of the previous stamp (`cache/p63/rot75/hotpath31.txt`): 3319 ns vs 3331 ns per no-scroll line, inside the +/-4% spread. |
| I41 | **A byte that separates parameters is part of the grammar, and reading it as a private-marker is a decision about another parser -- so the count has to name the arm, not the sequence.** ':' arrived in this library through ConEmu, which appends it to the same Pvt buffer it uses for '?' and then drops any SGR whose buffer is non-empty (Ansi.cpp:1788, :3494). That was recorded here as I10 parity, and it made four real spellings unspellable -- `38:5:n`, `38:2:r:g:b`, `38:2::r:g:b` with the deprecated colour-space slot left empty, and `4:n` -- while the census said only "a colon went past". #78 parses the family and the count says which arm was not carried: `38:2:200:40:10m` votes nothing and produces the same folded attribute as `38;2;200;40;10m` (**a form is not supported until it is equivalent, which is what the paired legs pin**), `4:3` puts the underscore on and votes for the shape the console has no bit for, and `58:` -- a colour with no surface on a console underscore -- is **consumed** so its numbers cannot be misread: before this, `58;5;1m` fell through the loop and set **bold**. Two boundaries are ruled rather than inherited. A colon on any other final is still dropped and counted, which is not ConEmu's choice but ghostty's stated rule ("we only allow colon or mixed separators for the 'm' command", stream.zig:1350-1358) with MSFT parsing the ranges for every family and letting each handler decide (`stateMachine.cpp:557-590`, capped at six per parameter). And an empty sub-parameter is stored as -1 rather than 0, because `38:2::1:2:3`'s blank field is *absent*, not *zero* -- MSFT's own comment keeps them distinct ("`CSI 0:::m` should be three sub params", :574-576), and reading it as 0 would make a truncated colour a reset. | `RcGrid::argSub[]`/`csiSub` and the ':' arm of the CSI accumulator, `sgr_apply`'s colour arms and its case 58, the census row "colon" in `Render.cpp`; `geo_colon` and the re-baselined legs in `RenderCheck.cpp`; `caseColon` and the re-baselined counter leg in `Render.java` | host `checks=5728 fails=0`, live `checks=5786 failures=0` on both arches against copies of the installed bytes; arms K1-K6 each seen red (the drop back in place, 13 legs; the colour-space skip removed, 1; a leftover sub read as a rendition, 2; a colon dispatching on CUP, 1; every `4:n` counted as uncarried, 2; 58 leaking its parameters into the loop, 1 -- and that last one is the bug's own witness) |
| I42 | **A reply is a claim about the reader's world, so a family is answered only where the model holds the number -- and where it holds two names for one thing, it says so rather than inventing the difference.** `CSI 18 t` asks for the text area in characters, and the model *is* that: `winRows` and `cols`, returned as `CSI 8 ; rows ; cols t` in MSFT's `function - 10` arithmetic (`adaptDispatch.cpp:3490`). `CSI 19 t` asks for the *screen*, a geometry xterm keeps distinct from the text area; on a console library there is one such number, so answering `9;30;200t` with 18t's values would assert a distinction this build cannot show -- **silence, ruled by the user on 2026-09-26**, counted so the ask stays visible. `14t`/`16t` want pixels; the only reachable figure is a font size times a cell count, and even MSFT's 14t multiplies by a *nominal* Sixel cell (`:3512-3517`), so quoting a constant we did not choose would be a fabricated measurement of the user's window. The title stack is the same rule applied to an effect rather than a reply: `22t` saves the title this parser last applied (the painter has already taken the pending one by then, which is why the model must remember it -- a second copy, deliberately, of one string), and `23t` restores it **through the same sink an OSC 0 uses**, so the two paths cannot drift; with nothing saved it restores nothing, because the console's pre-session title is a value this library never observed and the parser is console-free by construction. Two decisions are recorded rather than inherited: the stack is two deep with a ring (xterm's is unbounded because it owns the window and can be asked), and xterm's sub-codes 0/1/2 are all accepted because the console has one title string -- refusing 0 and 2 would invent a missing icon slot, while 3..6 name formats there is genuinely no surface for. | `RcGrid::title`/`nTitle`/`tstack`/`tstackLen`/`nTStack` and `RC_TITLE_STACK` in `Render.h`; the `case 't'` arm, the `titlePending` flag `rc_title_take` consumes (⚠ this row used to name a `title_apply`, which does not exist -- see §1's anchor rule), the -1 sentinels in `rc_reset_hist` in `Render.cpp`; `RC_REP_WINOP` and `reply_text` plus the carry in `RenderJni.cpp` | host `checks=5876 fails=0`; live `checks=5803 failures=0` on both arches against copies of the installed bytes, with the reply asserted byte for byte (`got=\e[8;30;200t`) and the title read back off the window; arms M1-M6 each seen red on the host gate (4, 1, 2, 2, 8, 2) and the reply prefix arm seen red **on the console** (`render-winbug`: `got=\e[9;30;200t`). Two arms came back green the first time and both were holes in the gate, now fixed and re-run: `18t`'s rows were asserted on a grid with no gutter, where `rows == winRows` makes the wrong answer identical; and `18;5t` was never fed, so the lone-parameter rule had no leg at all |
| I43 | **A margin is state, and a mode that only stores a bit lies.** DECOM (`CSI ?6 h/l`) moves the *base* CUP/HVP count from and the *band* the cursor is clamped into; DECLRMM (`CSI ?69 h/l`) does not narrow anything by itself -- it decides **which sequence `CSI Pl;Pr s` is**, because with the mode off that byte pair is ANSISYS save-cursor (MSFT `adaptDispatch.cpp:2369-2379`), and with it on it is DECSLRM. So #80 ships four obligations per mode (acts, answers, both resets clear it, a resize carries it) plus three rules that are not modes at all: a pair covering the whole page is *cleared* rather than stored (`:2384-2391`, which is why `marginSet` exists next to the two numbers); setting margins or origin **homes the cursor** (`:1794`, DEC's VT420 rule); and the clamp follows the margins **whatever the origin does** (`:366` tests `clampInMargins` or `Origin`), which is the distinction every leg in `geo_margins` names in its own text. SCOSC/SCOSR (`ESC 7`/`ESC 8`) carry the origin bit with the position (`:481`/`:497`) -- the leg that found this was written expecting `CSI s` to save, and under `?69` it no longer does. The terminfo entry says nothing about either mode: ConEmu's parser has no body for `?6`/`?69` and no margin state anywhere, so advertising them would be a claim about the other reader (I26). | `RcGrid::originMode`, `declrmm`, `saveOrigin`, `marginSet` and the pair `leftMargin`/`rightMargin` in `Render.h`; `set_margins`, the `?6`/`?69` arms of `h`/`l`, the `s`/`t` save arms, `mode_status`, both resets and `rc_reset_hist` in `Render.cpp`; the carry in `RenderJni.cpp::build_model` | host `geo_margins` (both modes act, both DECRQM spellings answer, both resets clear them, a whole-page pair *clears* the margins, setting either homes the cursor, and the clamp follows the margins with origin off); live `caseMargins`; the margin leg of `rc_validate_grid`, which refuses a pair that is not an ordered span inside the row and a cursor outside it |
| I44 | **A full-screen takeover banks the viewport before the frame lands.** A *bare* `\E[H` (no parameters) whose target is the viewport's top while the cursor sits below it and content the session scrolled by itself is still on the screen (`unpushed`, set by every natural scroll in `scroll_up`/`line_down_page_scroll`, cleared by RIS and by the takeover itself) is a dashboard's first frame -- the product's `Console.screenBlock` opens with exactly that byte -- and the model answers it by scrolling the live viewport into the gutter (`scroll_up(cy - top + 1)`), charging `pendingScrolls` so the executor pays it in the host's own currency: real line feeds under a pseudo-console, a buffer scroll on a classic console. The owner's contract for `top` is push-then-paint, never a clear and never an overwrite: what the user was reading reaches the scrollback instead of being destroyed (the defect that ate a help listing on every host, measured 2026-10-01). The flag is what makes every later home of the same dashboard a plain repaint -- frames do not scroll, so `unpushed` stays down and nothing is banked twice. The parameterless spelling is the contract's voice on purpose: an explicit `CSI 1;1 H` is addressing (the harness's `gotoRow` parks by number and means the row it named), an upward jump to any other row is not a takeover, an alt screen has no scrollback to gain, and a screen that never scrolled has nothing to bank. | `RcGrid::unpushed` in `Render.h`; the `H`/`f` arm of the CSI dispatch, the flag sets in `scroll_up`/`line_down_page_scroll`, and RIS in `Render.cpp` | host `geo_takeover` (armed push with content and cursor positions, the flag's disarm, repaint-charges-nothing, explicit `1;1` refuses, an upward non-top jump refuses); mutation: disabling the hook turns six assertions red (`cache/p123x/lab`); live `caseManyScreens` still passes unchanged because its `gotoRow(0)` is addressed, not bare |

## 4 Client contract: the terminfo entry

The entry the host ships for this terminal (`windows-conemu`) is part of the library's contract from the
other side: whatever it advertises, the renderer must do. §I26 is the rule; this is the machinery that
makes it easy to get wrong, all of it measured against the deployed parser rather than read off it.

| Fact about the parser (`parseInfoCmp`) | Consequence |
|---|---|
| The line loop starts at index 1 | **Line 1 is never parsed.** It can only carry prose, which is why the file's whole rationale sits there. |
| A token must end with `,` (the terminator class includes a literal `$`, not an end-of-line anchor) | The trailing comma on each line is syntax. Without it the last capability on the line vanishes silently. |
| The `[^,]` alternative is tried before the escaped-comma one, and a backslash is itself `[^,]` | `\,` does **not** protect a comma. No capability value may contain one. |
| Unknown capability names are dropped with no `else` branch | A typo deletes a capability without an error. Auditing means asking the loaded `Terminal` for each string, not "did it load". |
| The `#` arm is tested before the `=` arm | A `#` inside a string value either deletes the entry quietly or throws `NumberFormatException` **at load time** — the only path in the parser that throws. |
| Values are taken literally, including control characters, and a `\r` *before* a comma is part of the value | The file is LF-only, and this is verifiable (`0 CR`). An editor converting it to CRLF would append a carriage return to every capability — which looks like a renderer bug in the grid. |
| Strings stay in their spelling until `doTputs`, whose default arm throws | Only the escapes that decoder knows may be used; an unregistered form fails at run time, not at load. |

Two more integration facts:

* **`%i` and the scroll region.** `csr=\E[%i%p1%d;%p2%dr` combined with the host's habit of calling
  `csr(0, 0)` produces `\E[1;1r`, which since I25 is *a one-line region*, not a reset. A reset must be a
  bare `CSI r`.
* **The acsc family.** The host's line editor maps box-drawing characters backwards through `acsc`
  (11 letters, `r` is not among them) and the renderer maps them forwards again
  (`G0_DRAWING`, indexed by `cp - 0x60`). The two tables must agree letter for letter, which is what
  `geo_jline_stream` exists to check against captured bytes rather than invented ones.

Capabilities deliberately left out, with the reason. **The reason column was re-argued on 2026-09-28 (#112)**
against the owner's ruling that "the caller does not use it / nobody reads it / there is no consumer" is not a
reason at all -- it is the fifth thing, outside the four that can stand (no carrier / would lie / conflicts
with a named feature / a safety floor or an owner's decision). Two clauses used to fail that test and are
rewritten below; the rest already argued from this library's own surface:
`hts`/`tbc` (#70 gave tab stops a state and #90 declared
`cbt`; these two stay out because **the entry is named after a parser that does not honour them** -- measured
2026-09-28 in a real ConEmu window by `cache/p113/tabprobe.py`: `ESC H` loses to the default interval and
`CSI Z`/`CSI I` do not walk a stop table, while the same probe against a classic conhost with VTP on shows all
of `ESC H`/`0g`/`3g`/`Z`/`I` behaving. This library models all five and `geo_tabs` witnesses it, so the names
are true of one parser under this name and false of the other, and declaring them would be a claim about the
other parser (I26). The old clause here -- "no code in this jline reads `Capability.set_tab` or
`Capability.clear_all_tabs`" -- is retired: a third-party library's callers are not limited to this jline, and
#115 measured exactly that with a non-jline reader. Saying "we have tab stops" truthfully needs its own entry,
which is #117),
`smir`/`rmir`/`mir` (the mode is modelled since #77 and acts on every written glyph, I40 -- but this entry is loaded by windows-conemu sessions, and such a session has one raw-fallback leg: a chunk the renderer declines goes out through `WriteConsoleW`, which a real ConEmu window's own hook parses, and there `?4` is "ignored for now" (Ansi.cpp:3323-3329). Advertising the pair would promise IRM for bytes this renderer never saw, which I26 forbids -- the same shape as `smam`/`rmam` directly below. The premise used to be stated as "sessions where ConEmu's parser reads the stream", which was true when ConEmuHk sat on every write and is true now only of that decline path; the day the fallback leg no longer reaches a second parser, this refusal lapses), `smam`/`rmam` (the mode is modelled,
I35, but the same decline path as `smir` above -- a refused chunk reaching `WriteConsoleW` under a real
ConEmu hook that ignores `?7` -- makes the promise a claim about that other parser), `smkx`/`rmkx` (DECCKM selects *input*, which here comes from console records), `blink`, `invis`
(SGR 5/6/8 store nothing), `rmpch` and the `sgr` 10/11 arms (no font switching), `ncv` (no
cannot-coexist bits), `mc5i`, `flash` (`ESC g` would ring a window that is not ours to ring),
`initc`/`ccc` (OSC 4 changes this renderer's palette and the console's 16 entries, I34, but a reader that asks
`tput` whether the terminal *can* is asking whoever parses its bytes -- and under a ConEmu host that is not this
library, so I26 keeps the claim out), `u8`/`u9` (both DA queries are
answered now, and the old clause here -- "nothing in the host reads them, so a value would be invented" -- is
retired by #115, which *measured* a non-jline reader doing exactly that: WSL's ncurses 6.3
`tput -T xterm-256color u8` emits `\E[?%[;0123456789]c` and `u9` emits `\E[c`. Three reasons survive, none of
them about readers: `u8` is a **pattern** carrying `%[` while this stack's DA1 is a fixed 36-byte reply, so
"declared equals transmitted" can never hold (I26); `u9` is the primary DA **request**, so filing a DA2 answer
there lies to the other parser (I26); and declaring `u8` throws inside our own `Curses.tputs`
(`terminal/src/main/java/org/jline/utils/Curses.java:425-426`, `%[` is not in `"cdoxXs"` -- I3-class, a
conflict with a reader that is already in the product)), `kmous` (the facts first, stripped of the reasons an earlier round gave for keeping the name out -- two of
those reasons were about this code or another library rather than about a terminal, which is the I40 tell,
and this paragraph is their replacement. Modelled since #81/#93/#95: the nine mouse modes are stored,
answered number by number in DECRPM, carried across a rebuild, and `CONIN$`'s `ENABLE_MOUSE_INPUT` is
borrowed and returned while any of them is set. Report bytes exist on the wire today and they are X10:
`WinSysTerminal.java:489` routes `MOUSE_EVENT` records, `processMouseEvent` (:537) fills the fixed
`ESC [ M b x y` template and writes it to the slave input pipe (:569-572, re-measured 2026-10-01 -- the
three anchors this paragraph cited before had drifted again, which is why they are now named alongside
their symbols). The renderer's own encoder (`rc_mouse_report`, five formats, with `write_input_units` as
the injection channel) has no production caller: the renderer does not read `CONIN$`, so the records reach
the wire through the product's pump, which ignores the negotiated format and always sends X10. That gap is
gap A1, and it is the real open question -- not whether anybody needs the name. What `kmous` would
advertise is an X10-prefixed report, which is what the session sends whenever tracking is on, so the
declaration would be **true** today; the entry already describes sequences other legs of this product send
(`csr` is jline's `Status`, not this renderer). The name stays out for one reason only: while A1 stands, an
application that selects `?1006` SGR reports keeps receiving X10 bytes, and a reader that trusted the
negotiation over the terminfo name would be told a half-truth about which spelling follows. Declare `kmous`
when A1 closes (the product honours the negotiated format, or the reports move to the renderer's encoder
through the owner's decision on who reads `CONIN$`); `ANSI_SUPPORTS_1.md` §6 gap A2 tracks the
declaration, gap A1 the format), and
`xenl` — measured as absent on every path, so advertising it would be a lie.

Every clause of that list argues from the *output* leg, because that is the leg this library is. Two entries
in the file are not output at all — `kbs` and the `kf` family are read by the terminal's *input* leg
(`AbstractWindowsTerminal.getEscapeSequence`, which turns a console key record into the bytes a `KeyMap`
matches), and no measurement of `render.dll` can adjudicate them. They were settled by reading that leg:

* **`kbs=^H` is correct, and was never a candidate for a "should be DEL" fix.** The value is two literal
  characters until `Curses.tputs`' caret arm makes it 0x08 (`Curses.java:164-167`, reached from
  `AbstractWindowsTerminal.java:363-365`), and the reader binds both spellings to the same widget:
  `ctrl('H')` at `LineReaderImpl:6172` and `del()` (0x7f) at `:6194`. So `^H` and `\177` are
  interchangeable here — and `^H` is what every other Windows-family entry in this jline ships
  (`windows.caps`, `windows-256color.caps`, `windows-vtp.caps` all say `kbs=^H`). The value that *does*
  break editing is a multi-character one that collides with a bound prefix: `kbs=\E[H` is `khome`, which
  `bindArrowKeys` (`:6470`) binds to `BEGINNING_OF_LINE` after `:6194`, so Backspace would jump instead of
  deleting. Every clause of that argument is re-checkable and none of it is permanent: it holds while `Curses`' caret arm
  decodes `^H` to 0x08, while both spellings stay bound to one widget, and while no other Windows entry
  changes shape around them.
* **The `kf` family stops at `kf12`, and the shifted arrows (`kLFT`/`kRIT`/`kUP`/`kDN`/`kHOM`/`kEND`) stop
  with it.** Adding them would not enable a key: the input leg synthesises those bytes with no caps
  consulted — any modifier on F1..F4 emits `\E[1;<mod>P..S`, on F5..F12 `\E[<n>;<mod>~`, on arrows/Home/End
  `\E[1;<mod>[A-F]` (`AbstractWindowsTerminal.java:375-435`, `<mod>` filled by
  `Curses.tputs(seq, keyState + 1)` at `:441`) — so the sequence arrives whichever way this entry is
  written, while terminfo can name only the `mod == 2` arm. Naming that arm declares a `key_*` capability,
  and `bindKeys` binds every present `key_*` capability to `beep` (`LineReaderImpl:6457-6463`) where
  `bindArrowKeys` (`:6465-6479`) binds no shifted key to a widget; the Ctrl and Alt arms have no name to
  declare at all, because nothing in this tree decodes them — `modifyFunctionKeys`, `modifyOtherKeys` and
  `ParsedKey` are zero hits across the whole source. Hardware F13 and above (VK 0x7C..) has no `case` and
  falls to `default: return null` (`:436-439`), so the event is dropped before any sequence is built. The
  entry that does carry `kf13..kf44` is the dbcli overlay's `windows-256color.caps:21-30`, which is a clone
  of xterm's, where an emulator really does send those bytes on the wire; the three jline Windows entries
  all stop at `kf12`, so stopping there is this family's convention rather than this file's omission.

What the terminal's own editor actually puts on the wire, measured rather than assumed, because the
entry describes a *terminal*, and an application that happens not to use a capability is not evidence that the
terminal lacks it. The reference is the built-in editor (`Nano.java`, a Java port of `nano` rather than `nano`
itself): its 4,240 lines write **zero raw escape bytes** -- everything goes out through `Terminal.puts(Capability)`,
`Display`, `Status` and `AttributedCharSequence` -- and it parses nothing on input, matching `KeyMap` prefixes
against terminfo *input* caps instead. So the set it can put on the wire is small and known: `CSI H`, `CSI 2J`
(once per frame, because the editor forces a full erase on Windows terminals), `CSI K`, the CUU/CUD/CUF/CUB
family, `CSI K L M @ P`, `ESC 7`/`ESC 8`, `CSI ?1049h/l`, `CSI ?25h/l`, and the SGR set
`AttributedCharSequence` hard-codes (`38;5;`/`48;5;` -- 256-colour is forced on for this terminal type, so
truecolour spells nothing here). Three worries are therefore not this editor's: it writes no OSC at all (OSC 0/2
stays a prompt-side requirement), it emits no `CSI Ps b` or `CSI Ps X`, and it never queries the terminal. None
of that is a reason to leave `rep`, `ech` or `u6` out; read it as the denominator for what a quiet census means,
and see I19 for the sequences that arrive from somewhere else.

The same audit added capabilities rather than removing them in two places, and both needed a wire test before
they could be believed:

* **`rep=%p1%c\E[%p2%{1}%-%db` (xterm's spelling) is advertised, because `ech` was.** The entry's stated rule
  is a string CEAnsi acts on *and* the renderer models, and `CSI Ps b` satisfies both — upstream has a case
  that replays `m_LastWrittenChar` through `WriteText` (`Ansi.cpp:3070-3087`, refusing the private form at
  `:3085`) and `Render.cpp`'s `b` arm is a call to `put_cp` for the same reason. What it took a run to settle
  is the value. `Curses.doTputs` accepts a conversion only out of `"cdoxXs"` (`Curses.java:425`), so `%c` is
  the only arm in this file that reaches that code, and `toInteger` (`:502-510`) takes a `Number` or else
  `Integer.parseInt(toString)` — a `Character` argument is `parseInt("x")` and dies inside the `IOError`
  `tputs` wraps at `:88`. The working spelling passes the code point as an `int`: `tputs(rep, 0x78, 4)` is
  `x` + `CSI 3b`, and `CSI 0b` for a count of one repeats nothing, which is what both legs say when the
  parameter counts repeats rather than cells. `CapsDump.java`, driven by `caps_check.ps1` asserts all three of those
  sentences, including the failure, because `tputs(rep, 'x', 4)` is the obvious way to write the check.
* **`u7=\E[6n` and `u6=\E[%i%d;%dR` are in, and that reverses this file's earlier position** ("this parser
  never writes a reply back; a caller waiting for one would hang"), because the reply leg now exists (I29):
  `Render.cpp`'s DSR arms register `CSI 5n`/`CSI 6n` and `flush_reports` writes the answer into `CONIN$` as key
  events. Read the pair for what each side is: `u7` is the query the host *writes*, `u6` is the *report
  pattern* the host parses — `CursorSupport.getCursorPosition` (`:83-95`) takes both strings, compiles `u6`
  into a regex, and only ever asks `user6`/`user7`, which is why `u8`/`u9` stay out even though both DA
  queries are answered. `%i` is load-bearing rather than decorative: the reply is one-based, counted from the
  *window's* top (the same arithmetic the painter used, and why the plan, not the parser, computes it), and
  `%i` is what subtracts it back to the zero-based cursor jline hands to its callers. Two refusals are part
  of the advertisement, not omissions from it: `CSI ? 6 n` stays unanswered (both arms are guarded on
`!g->priv`, and the guard is the sentence) — an
  extended question answered with a plain reply is a position the asker did not request), and the queue's
  limit is a counted refusal rather than an eviction. The cost of advertising is real and stated: a caller
  that asks now blocks until a reply lands, so on a handle with no readable input the leg says so once in
  `lastError` and counts the failure instead of retrying per query. Both halves are witnesses of the live
  gate, not of the model: `caseReports` reads the reply *text* out of the console's input stream, and
  `CapsDump.java`, driven by `caps_check.ps1` expands the strings through `Curses.tputs` so that a `%` nobody can
  render fails the audit rather than the session.

## 5 Cost model

Measured on a real console with a purpose-built C++ benchmark (200 samples, median, frequency check
included), so that the JVM is not part of the measurement. Two samples exist, and the difference between
them is itself a fact about the numbers below:

| Operation | 2026-09-23 | 2026-09-24 | |
|---|---|---|---|
| read console view (screen buffer info + cursor info) | 59.1 µs | 85.4 µs | paid once per flush |
| `SetConsoleCursorPosition` | 35.6 µs | 48.5 µs | the entire cost of a slide |
| `SetConsoleTextAttribute` | 25.7 µs | 47.0 µs | |
| `ScrollConsoleScreenBuffer` (one row, whole buffer) | 150.1 µs | 188.4 µs | 4.2× / 3.9× a slide |
| `WriteConsoleOutputW` | ≈ 40 µs + 43 ns/cell + 1.5 µs/row | ≈ 60 µs + 41 ns/cell + 3.5 µs/row | fitted on 100×30 / 4096×1 / 4096×30 |
| our own staging, `build_row`, no console call | 1.03 ns/cell | 1.03 ns/cell | at 4096 columns: 129 µs |

Read the two columns as a **band, not a revision**. Every fixed per-call cost rose 1.4–1.9× between the
samples — the second run's worst view read is 795 µs against the first run's worst of 97.5 µs, and other
sessions were live on that machine — while the two things the design actually leans on did not move:
`WriteConsoleOutputW`'s per-cell throughput (43.2 vs 42.96 ns/cell at 4096×30) and our own staging rate
(1.03 ns/cell in both samples, to the reported precision). A model built on *ratios* and on per-cell
throughput is therefore still the right model; a model built on an absolute microsecond figure would have
been wrong twice. Re-run `bench.sh x64` before quoting an absolute anywhere.

Consequences that shaped the design:

1. **Slide instead of scroll wherever possible** — the plan's first operation exists because it is 4×
   cheaper and moves no cells. Measured again on the 24th: 3.9×.
2. **Batching at the chunk level, not the flush level.** The per-flush tax is the console read, not JNI;
   "flush less often" trades that tax against gutter pressure (I9).
3. **Painting to the buffer edge (I7) is charged per cell** — on the default 2000-column profile a
   full-window repaint of 30 rows is about 2.7 ms (2026-09-24: 2,656 µs for 60,000 cells) against roughly
   6.3 ms for the old in-process parser. That comparison is now **historical**: the retired parser's DLLs
   were deleted, so nothing can re-measure the second number. It stays here as the reason the change was
   made, not as a current claim. Since I22 it is an **upper bound** rather than a constant: a frame pays
   for the columns it actually dirtied, so a one-cell status line costs one call's fixed overhead, not
   sixty thousand cells. The user ruling that keeps I7 wide is about output correctness, not speed, and
   this is the cost of it.
4. What the bench does **not** measure: it drives a full-width paint (`paintCols = bufW - winL`, with
   `winL` pinned to 0), so consequence 3's "upper bound" is a claim about the planner rather than a
   measurement, and the narrow-column path I22 introduced has no timing leg at all. The same `winL` blindness -- no geometry leg and no timing leg for the
   narrow-column path -- is `ANSI_TODO.md` §3's #119.


Shape facts worth remembering, because gates depend on them: the default console profile has a buffer far
wider and taller than the window (2000 × 9001 vs 120 × 60); Windows Terminal and ConEmu size the buffer to
the window; and `mode con: cols=X lines=Y` **collapses the buffer to the window**, so any harness that runs
`mode con:` can never reach the wide-buffer shape — that shape needs its own leg.

Structural choices that still hold: dirty rows are merged into at most 8 runs (past that, one band plus the
union of dirty columns); attributes and cursor moves are sent only on change; the model's own row moves were the exception this document kept calling cheap until #75 measured it; see the table below. Each grid is a fixed
`RC_MAX_ROWS × RC_MAX_COLS × sizeof(CHAR_INFO)` allocation — about 4 MB — bought deliberately so that a
resize never reindexes a live model; in host-language tests it must be static, since it will not fit on a
stack.

**The price of a line feed, measured before and after #75** (`src/c/conemu/RowBench.cpp`, host-compiled from the
real tree at `-O2`, `cache/p63/rot75/{before,after}.txt` are the two runs it printed; `ns/lf` is a whole feed of one line ending in CRLF, `ns/nosc`
the same writes with no line feed, and `ns/scr*` the difference divided by the scrolls the feed actually performed):

| cols × rows | line | ns/lf before | ns/lf after | ns/scr before | ns/scr after |
|---|---|---|---|---|---|
| 80 × 60 | 20 chars | 3146 | 1170 | 2423 | 425 |
| 200 × 100 | 40 chars | 6682 | 2153 | 5210 | 546 |
| 120 × 72 | full width | 9335 | 5960 | 1154 | −47 (noise) |
| 1000 × 100 | full width | 79109 | 41987 | 8215 | 665 |
| 2000 × 100 | 60 chars | 44754 | 3716 | 42947 | 1125 |
| 2000 × 256 | 120 chars | 104722 | 7358 | 99670 | 2193 |

**What #80 cost on this table: nothing measurable, and the number is a range, not a point.** The margin work
puts two `col_right()`/`col_left()` reads on the hottest path in the library (`put_cell`'s fits test and its
post-write edge test), so the feed row was re-measured after -34 shipped: four runs at `80 × 60`, 20-character
line, `ns/lf` = 796, 808, 810, 823 (min 796, spread 3.4%). That is *below* the 1170 the "after" column carries
for the same shape, and the honest reading of that is not "margins are free and also faster than the row-pointer
rotation" — it is that the published before/after pair was measured on another day by another process, and the
only claim the columns support is the **ratio between the two columns of the same run**. A control build of -33
would be needed to say anything about #80's own cost, and the four samples above already say the branch is under
the instrument's resolution. Recorded here rather than in a rewritten table, because the table is a comparison
record and not a current reading.

Three things are worth keeping separate. The **headline is the shape this product runs on**: the default console
profile is a 2000-column buffer, so a 128-row window gives a 256-row model, and there the scroll was 95% of the cost
of printing a line -- 99.7 µs of a 104.7 µs line feed, against the 24 ns the same 255 row moves cost as a rotation.
The **residual is not the rotation**: `ns/scr*` after is the O(`cols`) work a scrolled-in row genuinely needs
(blank at the live attribute, claims dropped, damage claimed), and it is bounded by the width rather than by
`rows × width` the way a copy is. And the **"after" column is noise-bounded, which is the point of measuring it
rather than asserting it**: a second run of the same binary put two of those six entries at −594 and −3351 ns -- a
difference below what the two arms' timings can resolve, so the honest statement is that a scroll no longer costs
anything measurable next to the writing of a row. The **no-scroll column moved a few percent in both directions**,
which is the honest reading of adding one load per row access: the indirection replaces a `r × 16 KB` address
computation, so it is not free and it is not a cost either. Two earlier sentences in this section called the
shuffling "about 1 ns/cell" and "two orders below a console call"; both were true per cell and wrong per line, which
is the difference a measurement makes and a rate does not.

The shipped DLL is stripped with `--strip-debug` on purpose, keeping the COFF symbol table so a native
fault still names its function. The debug sections removed are MinGW runtime cruft, not this library's, and
`-static` has nothing to do with them. The verification that stripping was safe is section comparison
(`.text`/`.rdata` byte-identical, exports intact, imports unchanged) **within one file**: two independent
links of the same source can differ, because the linker randomises the image base and writes three
wall-clock fields — which is also why an md5 is not evidence about source, and why every build carries a
`RENDER_BUILD` stamp that the gates and the A/B legs print.

## 6 Verification

The doctrine, in the order that matters:

1. **Only cells read back with `ReadConsoleOutputW` count as evidence.** A pty byte stream or a
   self-printed line is not evidence: the host terminal re-parses what it receives, so what the user sees
   and what the buffer holds are different claims.
2. **"The DLL is loaded" is not "the DLL is doing the painting."** Loading is eager and happens on both
   legs of an A/B. The only witness is a substituted build that produces a *different* grid.
3. **A control build must be rebuilt from the current trunk** and must fail a known, countable set of
   gates — that failure list is its certificate. A control leg that silently accumulates the trunk's
   changes has stopped being a control. Two exist: one that folds columns on a bare LF, one blind to EL.
   Read only their `fails`, never their totals: the damage-bounds check votes twice on an empty plan, so
   *removing* a feature can increase the check count.
4. **A control's defect must be reachable by the workload.** The LF-folding leg cannot differ on a
   full-screen block repaint, because blocks are joined with `\r\n` and contain no bare LF. Likewise the
   first page of a long-line file cannot differ on the EL-blind leg, because EL has nothing to erase.
5. **Every A/B leg must state its own environment.** Since the renderer defaults to on, a leg that omits
   the switch is a leg with the renderer on, and an "off vs on" comparison of one renderer against itself
   returns a perfect, meaningless zero. Worse than omitted is *unread*: `DBCLI_NATIVE_RENDER` no longer has a
   reader anywhere — not in the sources, not as a string constant in either deployed jar — so a leg that sets
   it to `off` is not a weak control, it is the treatment leg wearing a control's label, and the agreement it
   reports is unfalsifiable rather than merely redundant. Before trusting which leg is which, grep the artifact
   for the variable and find the code that reads it; if you cannot, the A/B is one leg.
6. **A dirty console is inherited by the next gate.** When stdout is redirected, no console is allocated
   and the following leg starts on the previous leg's last frame — attributes included. The live gate
   therefore resets SGR *before* erasing, and asserts the window is blank at the default attribute.
7. **"The legs agree" can be manufactured.** If the two legs paint different rows, both screens come back
   blank and the diff is empty. Position-dependent corpora must use the same-rows comparison, and an
   expected-difference test must be checked for the opposite failure — differing because both sides are
   blank.
8. **An expected difference is as much an assertion as an expected match.** The documented deviations are
   gated as differences, so that whoever reintroduces one is stopped by a red test rather than a comment.
   When I25 landed, the DECSTBM gate flipped from "differ" to "agree" exactly as designed: a red here is
   information about a decision, not automatically a regression.
9. **Two census formats exist and must not be read against each other.** The gate prints a full family
   list including prompt marks and the last `133;D` exit; the production `report()` names only the non-zero
   families. Reading one as the other yields conclusions about sessions that never marked anything.
10. **A green gate proves the source tree, not the deployment.** The gate compiles the Java binding from a
    sourcepath that can be either of two trees; the shipped jar is built from the authoritative one, and
    the stats array is positional on both sides, so a jar older than the DLL silently reads someone
    else's counter. The check is against the deployed artifact (`javap` on the jar), and every deployed
    pair is recorded with its stamp, its md5 and a backup taken before the swap. Positional is not the
    same as *agreed*, so the live gate also reads the slot table out of `NativeRenderer` reflectively and
    fails if `SLOT_UNSUPPORTED`, `SLOT_SYNC_OVERFLOW`, `SLOT_SYNC_ON` or `SLOT_LAST` disagree with its own
    `S_*` constants -- before that leg, "both sides" meant two files that happened to be edited
    in the same hour.
11. **A gate helper can invent failures.** `eq_text(g, row, upto, want, ctx)` indexes `want[i]` for every
    `i < upto` with no NUL guard, so an `upto` larger than the literal walks into the merged string pool and
    compares real cells against unrelated text. Pass the length you actually mean, padding with explicit
    spaces when the row is longer: the `line_down` fix arrived with five fresh FAILs, and they were five bad
    expectations rather than five regressions. The same helper can also be asked to compare **zero** cells and vote
    "pass" having compared nothing -- one leg in `gm_erase` had been doing exactly that for three stamps -- and
    it can be asked for more columns than the grid has, where the cells exist in the fixed `RC_MAX_COLS`
    stride and hold whatever a wider geometry left there; its padding for a short `want` then indexed past
    the string's own terminator into the following literal. Both shapes now refuse, and three older legs
    were rewritten to say the width they meant. An assertion's cost is not its line count, and a helper
    that *can* compare nothing eventually will.
12. **A number that does not move is a missing witness, not a pass.** When a stamp's whole effect is a new
    counter, the gate's census line must be expected to change; if it comes back identical, the corpus never
    sends that family and the shipped binary's new arm has run nowhere but the host gate, which links the
    model directly and so cannot speak for the deployed DLL. Either say so, or put the bytes in the console
    leg. Build -7 came back identical on both arches, and the leg added to answer it is
    `caseSuspectAlign`'s `\E[p\E[61p\E)0q` block. The same reading caught -25: enumerating every CSI
    final the console legs actually send (`cache/p63/seqscan.py`) showed that no leg had ever sent IL, DL,
    ECH, ICH, DCH, REP or DECSTR, so every fix in that stamp was witnessed by the host gate alone -- which
    links `Render.cpp` directly and cannot speak for the shipped DLL. Four console legs closed it and the
    count moved by 171.
13. **A cell diff cannot see a belief, so give the belief an eye.** For three stamps the scroll defect was
    argued from the planner's source and re-argued, because the console reports where it is and never where
    the painter believed its own rows were — and a plan that addresses the right rows for the wrong reason
    leaves exactly the same grid as one that addresses the wrong rows. `plan()` (I30's witness) ended that in
    one line of output: `base=340 slide=0 bufScroll=1 row0=340 winTop=0 moveFail=0` next to the cells it
    produced. The general rule: if you find yourself reasoning about an *internal* quantity across several
    builds, export it.
14. **An API whose arguments read like every other API's is where the reading goes wrong.**
    `ScrollConsoleScreenBuffer(h, src, clip, dest, fill)` takes a destination that is an absolute buffer
    coordinate, not a delta — which is what conhost's own wrapper says: `getset.cpp:947-950` documents
    `target` as "the top left corner of the destination to paste the copy", and `getset.cpp:959` refuses the
    call as a no-op on `source.left == target.x && source.top == target.y`, a comparison that is only
    meaningful in absolute coordinates. A relative `-by` there is not a no-op or an error; it is a
    correct-looking scroll of `by + srcTop` rows, so the call *succeeded* and the damage only showed as
    content hoisted hundreds of rows into the user's scrollback. Two consequences for the doctrine: read the
    callee's source for argument semantics rather than inferring them from the name, and prefer a witness
    that reads *far* from the operation — the window was clean after that call for four stamps, and the rows
    0..339 it was wrecking were out of view.

15. **An expectation must count the line the cursor is standing on.** The census written for I31 failed three
    times before the renderer did, and every one of those failures was the gate's own arithmetic: 420
    CRLF-terminated lines are 421 lines, the last of them empty, so a 400-row buffer holds 399 lines of text
    and the cursor's blank. A gate that asserts "every row is a line of the session" is asserting the writer's
    contract rather than the terminal's, and it will be wrong on the day the renderer is right. Name the blank
    row in the case, and gate *where* it is (`firstBlankRow() == bufH - 1`) — a hole in the middle is the
    defect, and it reads exactly like an off-by-one at the end.
16. **A fix can be right about the mechanism and wrong about which quantity decides.** I30 and I31 are the
    same scroll; -12 shipped the eviction keyed on the anchor and the census caught it only because it counted
    every row of a buffer no window was looking at — a mixed flush (slide 19, scroll 1) left 401 live lines in
    400 rows, which surfaced as one line missing from the *middle* and the last row blank. When two expressions
    agree on every shape a test happens to build, pin the algebra that makes them agree (here: a saturated
    slide puts `row0` on `bufH - rows`) and build the shape where they part.

17. **A witness to a machine-wide register must classify a mismatch before reporting it.** The clipboard leg
reads through a second process, which is what made it a witness at all (rule 3's other half), and that second
process does not own the register. One x64 run came back with exactly one red whose readback was 24 box-drawing
characters -- a value no path in this library can produce, written by something else on the box between our seed
and our read. A red there is not cosmetic: the sentence it prints is "the renderer put text on the clipboard that
it had been told not to", which is the claim the default-off policy exists to prevent. So the two halves of the
case are shaped differently now. A fidelity claim retries its read, and a value this run *offered* is treated as
the library's (rule 3's other half again: the marker is per-run and unique, so a match can only have come from
here); a "nothing was written" claim re-seeds and says in as many words that an outside process held the
register, because in that direction the counters -- which nothing else can touch -- are the assertion and the
read was always corroboration. A register that cannot be taken back is reported as a skip, not a pass and not a
red. The shape was settled by running a deliberate competitor (`cache/p63/clip-hammer.ps1`, writing every 250 ms)
and reading its output: under sustained contention every clipboard leg is unwitnessable, and the same experiment
showed the gate had been leaving the *user's* clipboard holding the test's own seed -- it seeded, then "restored"
the value it had seeded. It now reads what was there before touching anything and puts that back on every exit
path, which is the same courtesy `close()` owes the palette.

   The same rule, read again on 2026-10-10 when the register stopped answering at all: this box's clipboard began
   failing `OpenClipboard` with ERROR_ACCESS_DENIED while `GetOpenClipboardWindow` named no owner and the viewer
   chain was empty, and pwsh's `Set-Clipboard` returned without error having written nothing. `caseClipboard()`
   has two bailouts and only one of them prints `SKIP clipboard: no out-of-process clipboard witness` -- the one
   that fired prints `skip the witness can read what it just wrote: read back ""; an outside process owns the
   register`, because `clipSeed` *reports success* and the read-back comes up empty. Two consequences kept on
   purpose: **the return value of a seeding call is not a witness, the read-back is**; and the totals move with
   the register, so `checks=6341` (this state) and `checks=6373` (register available) are not two runs of one
   suite -- 32 assertions per arch are simply absent, which is why the delta is stated instead of being
   smoothed into "still zero failures". Recovery is not this library's to take: the holder has to let go
   (the owning process exiting, or the session restarted), and `cache/ucd16/clipretry.ps1` is the probe that
   says whether the register answers before a run is interpreted.

18. **A new arm must be seen to fire, and a witness's own environment can veto it.** The four -25 console legs
passed on both arches, and the contention branch above fired exactly once -- under the hammer, where the whole
case declined to witness and said so. Rule 12 read from the other side: a green from a branch that never ran is
not evidence, and neither is a red from a branch that cannot tell who wrote. The -27 corollary costs more than
it looks: **the sentence "arm X turns check Y red" is a claim about the gate, not about the code**, so a row
that inherits it from an earlier stamp is carrying someone else's evidence. The half-carry arm was re-run at -27,
came back green, and the cause was a hole in the gate rather than a toothless arm (the `#73` row of `ANSI_TODO.md` §3) --
which means the -25 row's claim was true of `mark` and false of `col`, and the field the struct was packaged to
protect was the one nothing could see. Re-run an arm before citing it; a green arm is a finding about the gate.


19. **An oracle's silence is evidence only about what it claims to see, so state the boundary by breaking
    it twice.** The grid oracle (#72) went through two arms before it was trusted. Removing the pair heal from
    ICH/DCH makes it say `row 0 column 1: a TRAILING half whose LEADING is gone` -- the arm that proves it can
    see. Removing IL/DL's column home makes it **silent**, correctly: a cursor at column 7 is not an
    inconsistency, it is a wrong-but-legal state, and only the leg that asserts the column catches it. That
    second arm is in the record because the failure mode of a good oracle is over-trust: a green from it means
    "no invariant on the list was broken", not "the screen is right", and the list is written where a reader
    can argue with it (`Render.cpp::rc_validate_grid`). The same rule is why the live gate asserts the oracle's
    *run count* (436 chunks per arch) rather than resting on an absence of red -- rule 12, one stamp later.
20. **A case that prints SKIP is a case that compared nothing.** The both-legs A/B prints
    `SKIP both-leg A/B` and *zero failures* when no `ConEmuHk` is named, and the install tree ships
    `render.dll` but not the hook -- so a whole run of certifications quietly compared one renderer against
    itself. Pass `-Install` a tree that holds `lib/x86/ConEmuHk.dll` and `lib/x64/ConEmuHk64.dll` and the
    A/B's ~230 checks join the total, which is also the cheapest way to notice a leg has gone away: read the
    total, not the exit code. A decline must be loud in the output *and* visible in the number.
    Implemented on 2026-10-10 rather than left as prose: `Render.java` keeps a `skips` counter and a reason
    list, the five legs that can be vetoed by the environment (both-leg A/B, cursor shape, the clipboard
    family both ways, gutter pressure) register there, and the totals print
    `checks=N failures=0 unwitnessed-legs=3` followed by a `NOT WITNESSED:` line for each, with the verdict
    reading `RENDERGATE: ok, 3 leg(s) unwitnessed -- this total is NOT comparable with a run that had them`.
    The exit code stays 0: an environment that cannot lend a register is not the library's failure, and a
    red there would train everyone to ignore it. `run.ps1` now also asks the clipboard the same way the gate
    does, once, before any leg runs, and prints `CLIPBOARD: writable` or `NOT WITNESSED -- … checks will be
    ~32 smaller per arch`, restoring whatever was in the register afterwards. What this caught by name on the
    first run: `checks=6341` and `checks=6373` were never the same suite, and the number now says so.
21. **A sequence learned from a summary is a hypothesis; the bytes are the evidence.** `caseTabStops` fed
    `\u001b[H` meaning HTS and got `CSI H` -- CUP, home -- and the console answered column 0 on both arches
    while the host gate, whose legs used `\u001bH`, stayed green. One character apart, and only the screen
    could tell them apart; the same pair (`\u001b[c` for `\u001bc`) made that round's RIS leg red in the host
    gate, where again the model was right and the leg was wrong. Quote a sequence out of the decoder's own
    table, not out of a description of it.
22. **A leg's setup is part of its claim.** A case that calls `standardGeometry()` re-opens the handle and
    blanks the viewport, so it must sit *below* the cases that read rows an earlier scroll left in the
    buffer: placed above `caseRealign`, a set of brand-new legs erased its evidence and produced eight reds
    about a row they had themselves wiped -- rule 6's dirty-console trap wearing a different costume. And
    content inside a scroll region has to be placed with CUP, never with `\r\n`, because a line
    feed rotates the region: an expectation copied from a linear write is wrong before the renderer runs.


Current gates, and how to read them: the host gate (`RenderCheck`, cross-run on a Linux host: colour table,
full code-point width cross-check, per-UTF-16-unit resumability, damage bounds over the corpus) and the
live-console gate (`run.ps1`, both bitnesses: the model drives a real conhost, cells are read back, and the
optional reference leg is upstream ConEmu's own `ConEmuHk`, fed through `WriteProcessed3` and named with
`-Dhk=<path>` or `DBCLI_HK` -- the retired in-process parser is gone from the install tree, and what is
left of that comparison is the deviation legs of §7. Both gates print totals; quote them only from
a fresh run, since the numbers move with the corpus, and treat any total copied into prose as one build
out of date.

What this section deliberately does not keep: a paragraph per build. It used to -- -13 through -33,
each certifying two gate totals and listing the arms seen red -- and it rotted faster than anything else in the
tree. When this was written the shipped stamp was `render-2026-09-28-54` and the log stopped at -33, so
the page documented a binary nobody runs any more while the current one went unrecorded. Every one of those paragraphs is a row of
`ANSI_TODO.md` §3, whose `build` and proof columns carry the same numbers and the same arm-by-arm witnesses; a
cite written "§6's -NN paragraph" resolves there, and the redirect is declared once in that page's §0. The
 lessons that were worth more than their build number are rules now: 11 (a helper that can compare nothing
 will), 12 (a number that does not move), 18 (a green arm is a finding about the gate), and 20-22 (a SKIP that
 reads as a pass, a sequence quoted from a summary, a leg's own setup). The transcripts themselves are on disk
 where every leg has always put them -- `cache/gateNN/`, `cache/pNN/liveNN.txt`, `cache/wide-probe/`,
`cache/witness/` -- and a row's witness-file column names the ones its decision rests on.

## 7 Known deviations

**From the console itself**, both consequences of the buffer-wide model (I7), neither gated:

1. A buffer scroll moves whole buffer rows, while the console scrolling at the bottom of its own window
   moves window rows. The difference is visible only after horizontal scrolling, and only in a session that
   has actually reached the bottom of a tall buffer or emits IL/DL.
2. With `winL > 0`, a wrapped continuation lands at model column 0 (= buffer column `winL`), where the
   console would put it at buffer column 0. I8 exists to keep `winL` from moving under us.

**From the console font, on the ambiguous ruling (I14).** "Ambiguous is wide" is a ruling, not a
measurement, and the measurements are the exception list rather than the rule:

1. Evidence is 47,766 single-code-point writes on this box, six faces named by what the console reported
   back, over the whole BMP ambiguous set plus a sample of astral private use. The console's answer for an
   ambiguous code point is a property of the **face**, not of the code point, and the code page is
   irrelevant (437, 936 and 65001 agree). Faces must be verified through `GetCurrentConsoleFontEx`;
   `SetCurrentConsoleFontEx` returns TRUE even when it keeps the old face, so a sweep labelled with a font
   that was never applied would be worse than no sweep at all.
2. That splits the set three ways: 7,110 wide in every face (follow the ruling), 229 narrow in every face
   (the exception list), 620 split. The exception list is what `AMBIGUOUS_NARROW` encodes — box drawing,
   block elements, the accented Latin letters — and without it every drawn border, every block progress bar
   and every accented name breaks on every face here.
3. **The known cost** is the 620: `°`, `±`, `×`, `÷`, Greek and Cyrillic capitals, `■`, `●`, the arrows. The
   ruling is unconditional, so these are two columns — right on the CJK default face, one column
   over-predicted on Consolas, Lucida Console and Courier New. Table shape grew with the exception list:
   594 intervals over 112 mixed blocks, longest scan 28 (was 478 / 104 / 15).
4. **Cross-checked against the one shipping terminal that implements the ruling as a switch.** xterm 372
   under WSL documents `cjkWidth` as "characters with East Asian Ambiguous (A) category in UTR 11 have a
   column width of 2" and reports its cursor back through `ESC[6n`, so it can be probed the same way
   conhost was (`cache/ambiguous/xterm/`, xterm 372, `TERM=xterm`, `XLOCALE=false`, `LC_ALL=C.UTF-8`).
   Per code point over the 7,324-point sample: **7,117 agree, and the 207 disagreements are the 206
   exception-list code points plus SOFT HYPHEN** — the blanket half of the rule reproduced point for point
   by a second implementation, with the exception list as the only divergence. Per string, which is what
   the model has to predict: a box top is 24 columns under `-cjk_width` and 12 here, 40 `─` is 80 and 40,
   `éüÖ` is 5 and 3, while `10°C → 20°C` is 14 both places and `中文中文字` is 10 everywhere. xterm's
   default path is glibc's (353 agree; all 6,971 differences are this ruling) and `-mk_width` keeps every
   ambiguous point at one column, so xterm contributes exactly one independent endorsement, and it is the
   `cjkWidth` one. Note too that `cjkWidth` still gives the sampled combining marks zero columns while
   doubling every ambiguous letter — the same ordering the table uses, reached separately — and that even
   xterm's blanket rule is not quite blanket: U+2590 and U+2591 stay one column there.
   `../../luauf8/ansi_width.md` §1.1 and §6 carry the numbers.
5. glibc's `wcwidth()` over all code points now disagrees with the table on exactly one class — 138,156
   code points, every one of them ambiguous — which is the expected footprint of the ruling rather than a
   second opinion worth deferring to.
6. Sequences are the one place where conhost is *wider* than the table and the table still wins: it gives
   a combining mark a cell of its own (`A`+U+0300 costs 2, 中+U+0300 costs 3, an emoji plus U+FE0F costs 3,
   a conjoining jamo pair costs 3, `e`+ZWJ+`t` costs 3). Mn/Me/Cf stay 0, matching xterm, Windows Terminal
   and glibc, because the mark is not a grapheme on its own. This is a divergence from the console, listed
   here so nobody "fixes" it by reading a single-cell probe as a width rule.

**Where that ruling does and does not hold** (2026-10-10, read out of the three reference trees because JLine
now inherits this table for its own column arithmetic, so the ruling stopped being only the grid's problem).
All three default ambiguous to *narrow* and make wide a switch rather than a policy, each line opened in that
session: microsoft/terminal `src/types/inc/CodepointWidthDetector.hpp:76 int _ambiguousWidth = 1;`, raised only
by `src/host/VtIo.cpp:55 SetAmbiguousWidth(2)` (the conhost `--ambiguousIsWide` launch argument); wezterm
`wezterm-cell/src/lib.rs:852-856` (`WcWidth::Ambiguous && self.ambiguous_are_wide` -> 2) with
`config/src/config.rs:865 treat_east_asian_ambiguous_width_as_wide` defaulting false; ghostty
`src/unicode/main.zig:27 codepointWidth` on a table documented at `:12-21` as "2 for wide codepoints (East
Asian Wide/Fullwidth, regional indicators, clamped at 2), and 1 otherwise" -- no ambiguous concept to switch.
The font query that makes the answer face-dependent is installed only `if (!gci.IsInVtIoMode())`
(`src/host/srvinit.cpp:836-843`, giving `Renderer::IsGlyphWideByFont`), and `_checkFallbackViaCache` is reached
from just `CodepointWidthDetector.cpp:1157` and `:1203`; with no fallback pointer `:1221-1225` returns 1.
Read together: **classic conhost on MS Gothic or 新宋体 spends two cells for a black circle or an ellipsis --
which is what item 1 measured -- and Windows Terminal spends one, unless the user opts in.** The table follows
the first because that is the console this library is loaded into by dbcli. On the second it over-predicts, and
the direction of that error is the safe one: over-prediction cannot push a line past the margin, it leaves the
tail cell unused. Under-prediction is what wraps.

Two of the sweep's own counts are the evidence for the ruling rather than the reasoning: the 206 carve-out code
points were narrow in *every* one of the six faces (item 2), and the 620 split points are wide on the CJK faces
and narrow on the Western ones (item 3).

**The oracle is Unicode 16.0 now, and the instrument that decided the 139 disagreed with itself** (2026-10-10,
same day). `gen_ansi_tables.py` reads `src/c/luauf8/ucd/UnicodeData.txt` + `EastAsianWidth.txt` (16.0.0, carried
in the tree, so the version is a property of the repository and not of whichever Python runs the gate; `--interp`
is the A/B leg, and a missing data file aborts rather than falling back). Against the table that shipped all week
the net is **37 code points**: 36 marks 16.0 assigns going 1 -> 0, and U+1171E AHOM CONSONANT SIGN MEDIAL RA going
0 -> 1 because 16.0 reclassifies it Mn -> Mc. No box-drawing, block-element, braille, CJK, jamo or drawn-Cf code
point moves. The third group is the one that fought: 139 code points 16.0 reclassifies to `East_Asian_Width=W`
(the trigrams U+2630..U+2637, the taoist monograms and the Tai Xuan Jing tetragrams, the ideographic-description
tail, two CJK strokes, one Khitan character, the counting rods, seven astral additions). `ambmeasure.exe` wrote
every one of them with `WriteConsoleW` on six conhost faces and all six consumed ONE cell -- the same instrument
that built `AMBIGUOUS_NARROW` -- so the model grew a second measured carve-out holding them at 1, and that build
was deployed. A dbcli leg in the pseudo-console then measured the same glyphs the other way: two cells each, with
the `0x0000` trailing cell conhost reserves for a wide glyph, from a pty stream in which each glyph crosses exactly
once. The two console width paths really do differ, and the reference tree carries both sources: the font fallback
is installed only `if (!gci.IsInVtIoMode())` (`src/host/srvinit.cpp:835`), while the terminal-adapter path answers
from the property trie and consults the font only for an ambiguous `width == 3`
(`src/types/CodepointWidthDetector.cpp:1153-1157`); that trie is generated `from Unicode 16.0.0` (`:46`). The
mechanism is what the measurements suggest, not what either leg proved. What settled the choice is the asymmetry:
a table that says 1 where the host spends 2 lays the next cell of the row on top of the glyph -- the overlap class;
a table that says 2 where the host spends 1 leaves a blank tail. **The 1-cell side was never rendered and
measured, so it is written as the reason for the choice rather than as a witnessed failure.** The carve-out came
off, the table follows the property, and the reversal's blast radius is measured rather than asserted: the
five-face differential run against the jar that carried it names exactly those 139. Verified after the flip in the
layout path, cell by cell, on a live grid: the trigram column reserves 16 and the console spends 16, CJK 6 and 6,
Tai Xuan Jing 10 and 10, astral 6 and 6, every following column starting exactly at its header dash
(`cache/ucd16/check_align16.py`, worst displacement 0), and no wide glyph is cut by the margin when a 120-cell
value folds in a 100-column window (`cache/ucd16/check_split16.py`, 0 split / 0 orphan, with a planted control that
does fire). The narrow answer on the six classic faces is now a recorded known cost, the same shape as the 620.

One divergence from a reference is recorded rather than smoothed over: ghostty gives **regional indicators**
(U+1F1E6..U+1F1FF) two cells each, this table gives them one (they are EAW=Na, and no measured face was asked).
Per code point a flag pair totals 2 cells here and 4 there; neither number is cursor-measured, so this is
written as "unmeasured and differing", not as settled.

**From the parsers this library is not**, measured cell by cell and still pinned as expected-difference
legs. They were taken against the in-process parser that used to sit in this process; that parser is gone
from the install tree, and the legs that survive run against upstream ConEmu's `ConEmuHk` (§6's
reference leg, so they are skipped when no hook is named -- rule 20). They stay because the deviations are
real properties of this model, and because two of them were decisions rather than accidents:

1. **Backspace over the trailing half of a wide glyph.** The old parser counted a wide glyph as one column,
   so the cursor landed one cell short and the next write was clipped. The model steps over the trailing
   cell (as upstream later fixed in its own issue #852). Ours is the correct side; it is gated as a
   difference so the fix cannot be "restored".
2. **Astral code points.** A `CHAR_INFO` is one UTF-16 unit and conhost duplicates the leading unit into the
   trailing cell of a 2-column glyph, so no generation of this contract can store a surrogate pair. The
   model keeps the **raw halves** rather than adopting U+FFFD: a console generation that combines them gets
   the character back, and one that does not shows a box either way.
3. DECSTBM in a region used to be the third such difference and is now agreement (I25); the case stays in
   the gates because the reason it flipped — a region-scoped scroll compared across two different bands —
   is the lesson behind rule 7 above.

One rejected proposal: **deferred wrap** (the delayed-newline model). Four shapes that would discriminate it
were run on both legs at a 200-column buffer with a 100-column window and all four agreed, so switching
would *create* a divergence rather than remove one. That is the whole argument and it is a claim about
four shapes, not a verdict nobody may reopen: whoever builds the fifth discriminator is free to disagree
with it, and §3's I-would-need-a-gate rule applies to this row as to every other.

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
pwsh -NoProfile -File cache/java-merge/build-jar.ps1          # rebuild the host jar (-Deploy writes lib\; read the report first)
pwsh -NoProfile -File cache/java-merge/config-check.ps1       # every ANSI_RENDER spelling against the deployed jar
pwsh -NoProfile -File cache/caps-audit/native-census.ps1 -Native on   # a live session's census line
```

```sh
# the terminfo contract (tic/infocmp live in WSL; nothing here touches the checkout without --refresh)
# the assignments have to be EXPORTED -- written in front of the `tr` they bind to `tr`, and the script
# that reads them sees an empty environment -- and DBCLI_ROOT is no longer needed: the gate finds the
# root by a marker file. The term is spelled backslash-r on purpose; the version printed here held a
# raw newline inside the quotes, which deletes every line break out of the script before bash sees it.
MSYS_NO_PATHCONV=1 wsl.exe -e bash -lc \
  'tr -d "\r" < /mnt/d/dbcli/src/c/conemu/terminfo/terminfo_check.sh | bash -s'
# the tr is not decoration: core.autocrlf=true with no .gitattributes means a checkout hands bash a CRLF script
```

Notes that cost time when unknown: a control build needs a sibling `luauf8` directory in its scratch tree
(the width tables are included by relative path); JDK 8's `javac` will not create its own `-d` directory;
`pwsh -File … -Deploy` swallows the switch — invoke through `-Command`; paths passed to `pwsh -File` from a
POSIX shell need forward slashes; the benchmark is deliberately *not* part of `build.sh`, because a gate must
be able to fail and a measurement has no notion of passing; and **a `render.dll` that some live session already
loaded cannot be written in place** — `cp` fails with "Device or resource busy" — but it can be *replaced*, by
writing the new bytes next to it and renaming over the old name (`cp new.dll x.dll.new && mv -f x.dll.new
x.dll`), which is why a deployment never has to wait for, or kill, the sessions holding the previous pair.
`cache/scratch-pill/who-locks.ps1` names the holding process through the Restart Manager when that surprise
comes up; finding it is informational only, since the answer is the rename and not the kill.

Three more of the same kind, all paid for by a live leg of the status bar on -13: **a console leg cannot be run
from a POSIX shell at all** -- Git Bash has no console to attach to, so `drive-dbcli.ps1`/`ConsoleDriver` must be
started inside one, which in practice means writing a small `.cmd` under the scratch directory and running
`cmd /c start "" /min /wait cmd /c <file.cmd>` (the wrappers for the -13 legs are `cache/gate13/w15.cmd`,
`w16.cmd`; the reports they produced name themselves). That command needs `MSYS2_ARG_CONV_EXCL='*'` in the
environment, because otherwise the POSIX shell rewrites `/min` and `/wait` into paths before `cmd` ever sees
them. And inside such a wrapper `-Send` must be **double**-quoted: `cmd` does not treat a single quote as a
quoting character, so `-Send 'set Status on'` arrives split and the driver binds the remainder onto the following
switch (`-Dbcli`) -- a leg that then "runs" a session with no commands in it, prints a clean-looking grid, and
reports a verdict about nothing.

The generated width table is produced by `gen_ansi_tables.py`, which is not in this tree; the table is
never edited by hand. Regenerate, then re-run the host gate: its width cross-check is the thing that catches
a generator change.

`build.sh` derives the demanded JNI symbols from the `native` declarations in the two Java files rather than
from a hand-kept list, and fails the build on any name the DLL does not export. That is a build check for a
class of bug no build check should have to catch: an export spelled `Java_..._setClipboardPolicy` for a
Java method named `setClipboardPolicy0` links to nothing, the wrapper catches `Throwable` so an older DLL
keeps working, and the result is a feature that never existed, reporting as a switch that does nothing --
on both sides of a green build. A hand-written whitelist copied from the same wrong assumption cannot see
that; it proves presence, not spelling.

Where the rest of the record lives. This page has no open-work section and no ledger, deliberately: a numbered
row that lives on two pages carries its verdict on one and its row number on the other, and the #83 round (a claim about what a resize carries, recorded on one page and
contradicted by the code on the other) is the example of what that costs. Everything still owed is a row of `ANSI_TODO.md` §3 -- including the
four items this page used to keep for itself: #118 (a pager that took the alternate screen leaves one
prompt row too many, mechanism not established), #119 (the `winL` gap in narrow rectangles, I22), #120
(whether the host should emit OSC 133 at all -- its owner's call, not this library's) and #121 (the tree
`javac` reads is versioned only by being copied). A row's last column is where its ticket lives: what to
change, which arm has to be seen red, which gate has to go green.

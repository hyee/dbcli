# render.dll — an ANSI renderer for the Windows console

Design document for `src\c\conemu`: the parser, the screen model and the painter that turn a stream of
ANSI/VT escape sequences into console cells. It ships as `render.dll` plus one Java binding,
`com.hyee.ansirender.NativeRenderer`, and is meant to be used as a library: the embedding application
provides a console handle and a `char[]`, and gets painted cells.

This file is the **contract**. It says who owns what, which properties must hold forever, and which gate
pins each one. Where a property has no gate, that is written out rather than left as an omission — an
ungated invariant is the one that will be broken quietly.

Line numbers are deliberately not quoted. Function and field names are the anchors; the gates are named
by test, not by position.

## 1 Goals and hard constraints

| Constraint | Meaning in the code |
|---|---|
| All rendering in C/C++ | `Render.cpp` is the only parser and the only screen model; `Paint.cpp` decides what to send; `RenderJni.cpp` executes against the console. Java holds a handle and makes one call per chunk. |
| Windows 7 is the floor | `build.sh` compiles with `-D_WIN32_WINNT=0x0601 -DWINVER=0x0601` **and** greps the linked DLL's import table against a list of post-Win7 APIs. Both bitnesses fail the build if either check trips. |
| Never *execute* ConEmu-private OSC 9 | Nothing in the family runs anything: no sleep, no MessageBox, no environment write, no GuiMacro, no DoProcess. Three subcommands are *stored* or *routed* -- `9;4` keeps a taskbar state and progress, `9;9` keeps a path as text, `9;12` goes into the FTCS `133;B` path it is equivalent to -- which is the same line microsoft/terminal draws at `DoConEmuAction` (adaptDispatch.cpp:3558-3647), and neither stored fact is obeyed: this library owns no window and never changes the process's directory from an output stream. Everything else is counted and ignored (ConEmu issue #687). |
| One width oracle | Display widths come from the `ansi_width` table in `src\c\luauf8`, which `rc_width()` links through the generated `ansi_width_tables.h`. No WCWidth or jansi table may be substituted, and the locale and the font are not consulted. |
| Output is the same on every Windows version | The model does not depend on `ENABLE_VIRTUAL_TERMINAL_PROCESSING`, and a model row is a **buffer** row (I7), so wrap points and erase extents agree with the console regardless of window width. |
| A feature's absence needs a **technical** reason, not a local non-user | This is a third-party renderer: its callers are other programs, so "nothing in dbcli sends that" is **not** a reason to leave a sequence unmodelled or a capability undeclared (ruled by the user 2026-09-26, and it re-opens every "no consumer" sentence in `ANSI_SUPPORTS.md` §3 -- see #76). The admissible reasons are: the console offers no surface for it (no attribute bit for blink/invis, no window rectangle for `CSI t`), honouring it would be a claim about the *other* parser that may read the same bytes in the same session (I26: `smam`/`rmam`, `initc`/`ccc`), or it is a floor chosen deliberately for safety (the OSC 9 execution half; OSC 52's default-off). Everything else is work to do: #70 makes `cbt`/`hts`/`tbc` true rather than undeclared, and #76 is the sweep. |
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
successful `SetConsoleMode` say "yes" in either host. A session must not paint a grid it does not own, so
`WinSysTerminal.createTerminal` puts that test above the `ANSICON_DEF` branch; its Java wrapper returns a
`Boolean`, and `null` — library missing, method older than this one — means "classify without this fact", which is
what the pre-`-15` behaviour was. The measured shape of both hosts, and the A/B that says the classifier now reads
the console instead of the environment, is in `D:\dbcli\cache\wt-classify-20260925` (`ConShape.cpp`, `matrix.cmd`).

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
nothing at all, leave it on) selects between the renderer and a plain `WriteConsoleW` of the same bytes;
`ANSI_RENDER_LIB` can name the DLL explicitly rather than finding it on `PATH`.

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
| I22 | Damage granularity is a **column range**: a dirty row also records `[dirtyLo, dirtyHi]`, and the rectangle write is issued for that range. This is not a narrowing of I7 — the model still stores and can still paint whole buffer rows; the saving is only "columns nobody touched are not rewritten". Ranges are unioned, so a merge can only widen. Two rules bound the risk of painting too *little*: anything that cannot name its range says "whole row" (adopt, `rc_mark_all_dirty`, IL/DL, a scrolled-in row), and the bounds check scans the whole corpus. | `mark_dirty` / `mark_row_dirty` / `rc_mark_all_dirty`; `RcRun.lo/hi`; `build_row` / `write_rect` translate the range into buffer columns | `geo_damage`'s range block, `plan_damage_range`, `check_damage_bounds` (every corpus × every gutter shape, at that shape's own width), `grid_equal` now compares damage too; live `caseNarrowRepaint` and `caseWideBuffer` |
| I23 | OSC 133 (FTCS) is a first-class sequence, not an unknown OSC. One letter in field 0 (`L` takes no option; an unknown letter is a no-op, not a suspect). `A`/`N` start a prompt, adding a line first if there is none — the only place in the family that moves the cursor; `P` is a prompt that does not owe a line; `B`/`I` mark where input starts; `C` marks output start and recovers a fish-style continuation; `D` stamps the nearest marked row **above** the cursor with an exit code and `D` with no code leaves the recorded exit unknown. Marks are per row, model-side only, like I20. Guard: digits immediately followed by `;`, so `]0133;A` and `]1334;A` do not match. | `ftcs_apply()` and its helpers; `rc_row_mark` / `rc_prompt_marks`; the last-exit slot | `gm_ftcs` (per-letter semantics), `geo_ftcs` (marks in the grid and their transport), `caseSemanticPrompt`. One recorded deviation, from the era when a declined chunk went to a second parser: those chunks lost the marks. That path no longer exists. |
| I24 | The alt screen is one behaviour with three codes: `?47`, `?1047`, `?1049` all do the same thing (as upstream's `ASB_AlternateScreenBuffer`), `?1048` saves/restores the cursor only. Entering snapshots the viewport rows; the alt's viewport *is* everything and has no scrollback, so a row leaving the top is gone. Leaving restores. Leaving without entering is safe (the restore is gated on the flag, not the pointer). Scrolling in the alt costs no scroll operation. The only refusal is a failed snapshot allocation — which is why the family's counter means "this one did not happen" and both its slots stayed where they were. | `alt_screen()`, `rc_in_alt`, the `snap*` fields (allocated at this grid's own stride, freed by `rc_reset_hist`, carrying wrap and FTCS marks too) | `geo_alt`, `caseAltScreen`; census "N alt-screen switch(es), M refused" |
| I25 | DECSTBM (`CSI r`) is a region in the model, not a counted refusal. Bounds are clamped to the viewport when set and never re-clamped. Two resets are fixed: a region exactly covering the viewport is recorded as *no region* (the gutter and scroll paths branch on that, and a coincidental full region must not take the other arm), and a bare `CSI r` resets. A geometry change resets it, so a re-opened grid has no region. IL/DL and `scroll_up` work within it. | `case 'r'`, `region()`, `regSet`/`regTop`/`regBot` | `geo_region`; live: `legsSame("DECSTBM then a scroll", …, TRUE)` — the two legs now agree, and the expectation was flipped when the model gained the feature. That test is why `legsSame` exists: two side-by-side bands let the reference leg scroll *outside* the region and both screens came back blank. |
| I26 | The terminfo entry advertises only what the renderer actually models. Absence matters as much as presence: a lying terminfo is worse than a short one, because the reader does not re-check, it complies. | `windows-conemu.caps` in the host's terminal library | `geo_jline_stream` replays the bytes the host's own line editor writes — the 11 acsc letters it emits, `ESC (B` returning them to text, and an in-place edit landing on the right columns |
| I27 | A slot is claimed until it is closed. Ownership (`taken`) and having a model (`g`) are separate; `stats()` and `stopReason()` work on a claimed slot with no model; `open()` claims an unclaimed slot and returns the claim when it refuses. | `slot_of()` vs `handle()`, `open()`, `release_all()` | the four-slot and refusal tests in `caseOpenRefusal`; the census readable after give-up is asserted by the report path in the live gate |
| I28 | **The anchor is carried across a rebuild, not re-derived from the window.** A grid is rebuilt on a decline, on a resize, and on a `close()`-free re-adopt; each of those would otherwise ask the console where the model's rows are, and the console's answer is the *window* — which the user may have moved, and which a resize has just moved by itself. So the previous claim's **bottom** row is carried into the new grid (`vb - rows + 1`), because a rebuilt grid has a different height and the row the content ends on is the one that means the same thing in both. conhost's straddle sweep — a view that ended up between the old and new window bottom loses the claim — applies **only when the grid changed height** (`reshaped`), because that rule belongs to `_InternalSetViewportSize` (screenInfo.cpp:953, check at 1110-1112) and `SetViewportOrigin`, which is what the scroll wheel drives (642), has no such rule. A carried claim is kept only where the grid it anchors is legal (`vb ≥ winRows-1`, `vb ≤ bufH-1`), which is conhost's own "may not poke above row 0" guard in row-0 form. | `RcHandle::prev*`, `rc_anchor_adopt` | `adopt_anchor` on the host (carry, sweep-when-reshaped, not-swept-on-a-plain-adopt, both illegal-claim arms); live: `caseScrollKeepsHistory`'s resize leg, which calls `readopt()` after dragging the window shorter while the view is scrolled up, and asserts the next prompt lands below the carried anchor with the user's rows unchanged |
| I29 | A device-status or identification query is **answered**, into the console's input stream, and never silently. One `KEY_EVENT` pair per character at `WriteConsoleInputW`, the same synthesis conhost's own ANSI output leg uses (outputStream.cpp:43-45 → inputBuffer.cpp:799-816), so a program blocked on `tput rows` wakes. Replies are flushed at the **end** of a successful paint, even one that painted nothing — the reply is about the reader, not the screen — and are **never** written for a declined chunk, because conhost answers the replayed bytes itself and a second reply would be stray input for the next reader. The queue is bounded: a query that arrives when it is full is refused and counted, not queued and not dropped. Three counters, no fourth outcome: written, failed, refused-for-full. | `rc_report_*`, `flush_reports`, `reply_text` | `gm_reports` on the host (one reply per query and no second one for a later move, FIFO over the three kinds, the cap, the kinds that arm nothing); live: `caseReports`, whose `eqInput` drains the console's input stream and compares the *text* — `\E[4;7R` for a cursor placed at `CSI 4;7H`, and "answered from the snapshot, not from the cursor now" — which is the only witness that can say what a reply *said*. Census: "replies written=N (M failed, K refused)" |
| I30 | **While the buffer has room below the claim**, a buffer scroll moves the rows the anchor claimed **before** this flush's slide, and `ScrollConsoleScreenBuffer`'s destination is an **absolute** buffer coordinate. A slide moves no cell — it asks conhost to drag the window over rows that are already where they belong — so the cells that owe a shift of `k` are the ones at `base + r`, which means a source rect starting `k` rows below the row the plan now addresses (`row0 + by`) and ending at the old band's last row (`base + rows - 1`). Getting either half wrong is invisible in the window, because every row the scroll touches is dirty and gets repainted anyway, and fatal in scrollback: a relative destination turns the call into a shift of `-(by + srcTop)` and hoists the model's whole band hundreds of rows up over the user's history. The band is clamped at both ends (a model reaching above row 0, a shape that moved under the plan); a `by` at or beyond the band's height is a no-op with a reason, since `scroll_up` blanks and marks the whole grid in that case and the paint that follows covers it. | `rc_scroll_band` (the arithmetic, console-free), `scroll_region` (the call) | `plan_scroll_band` on the host, over the `room:` (band, nothing of the user's in it), `whole:` and `gutter:` shapes; live: `caseScrollKeepsHistory` (100 lines through a 400-row buffer, then the view scrolled to row 0 and one more line) asserts per chunk that the ink landed inside the claimed band and the window stayed put, and gates its own premise — `base + rows < bufH`, which is what keeps this branch the answer |
| I31 | **Once the claim a flush leaves behind has the buffer's last row, the scroll's reach is the buffer, not the claim.** A full console buffer has one answer to a new line: everything rides up by `by` and the oldest `by` lines leave the top — conhost's `_stream.cpp:123-126` → `TextBuffer::IncrementCircularBuffer` (reset row 0, advance `_firstRow`: textBuffer.cpp:722-745). The deciding quantity is the plan's **destination** (`row0 + modelRows >= bufH`), never the anchor it started from, because **a slide does not escape an eviction**: sliding is how the claim gets to the last row and it moves no cells, so a flush of `k` lines that slides `f` still owes the remaining `by` evictions — and sliding as far as the buffer allows puts `row0` on `bufH - rows` by construction, which makes every mixed flush an eviction. Inside the claim the rows land identically either way, so the paint is untouched; what changes is everything above it. Where there is no scrollback to move (`row0 == 0`) the two branches coincide. Leaving the eviction unpaid is not conservative: it puts more live lines into the buffer than it has rows, and the shift then drops one of them **in the middle** while the window, being all-dirty, shows nothing. | `rc_scroll_band`'s `full` arm, `scroll_region` | `plan_scroll_band`'s `full:` and `mixed:` shapes (source starts at `by` and ends where the *old* claim ended, lands on row 0, "the claim's own rows ride as before", and a saturated slide's corollary asserted alongside the anchor that would have said otherwise); live: `caseFullBufferEvicts` — 420 numbered lines in 20-line chunks, then the view scrolled to row 0 and one prompt line — which censuses all 400 rows for an unbroken in-order run, compares every row above the claim against a before-capture (`wrong=0 kept=340`), and names the cursor's own blank row rather than assuming every row holds text; oracle: `cache/wide-probe/StartupRepro.java` raw leg vs render leg through `su-cmp.py`, both shapes, "no line the console kept" / "no hole" / "the lines land in order" |
| I32 | **DECSET `?2026` defers a frame, it never defers an answer.** While the mode is on, a flush that would have painted returns "held": the plan is thrown away unexecuted, the damage it was built from stays marked, and the next flush therefore paints everything the region accumulated in one go. Nothing is *stored* about the deferred rows — the model already holds them, and a second copy of a 4 MB grid to say "these cells changed" would be the worst kind of honesty. Four rules make the hold safe to ship rather than merely correct. (1) **The region's first frame is held too**: an application writes its BSU together with the top of the new screen, so a renderer that paints that chunk has just drawn the new frame's head over the old one. (2) **The hold is bounded by a clock, not by silence.** `RC_SYNC_TIMEOUT_MS` is 100 ms and is measured from the first held flush, so it bounds the *age of the region*; the tick is never re-armed by a later chunk, because a re-arming clock would let an in-place, never-ending region freeze the screen forever and would remove the floor MSFT keeps deliberately (`renderer.cpp:540-570` waits on `_isSynchronizingOutput` with `timeout - elapsed`, then unconditionally clears both the flag and `Mode::SynchronizedOutput`; `renderer.cpp:517-537` notes a ~10 FPS floor against BSU spam). An expired clock paints **and clears the mode** — a program that leaked its ESU must not have the rest of its session swallowed one frame at a time. (3) **The scroll gutter outranks the mode.** `scroll_up` asks for a paint once `pendingScrolls` fills the gutter, which is the last moment the rows about to be evicted still exist on screen; answering "not yet" there would let the model evict history the console never painted. So a full gutter paints, counts the preemption, and **leaves the region open** — the two escape hatches differ on purpose. (4) **Replies go out either way** (I29): a query's answer is about the reader, not the screen, and a program that asks `tput rows` inside its own synchronized region while we wait for its ESU is a program that hangs. Its CPR is answered from the plan this flush declined, which describes exactly where the rows will be when the region ends. An empty plan is never held — a chunk of cursor moves only opens or closes the region, and counting those would make the census claim frames were deferred that were not. A declined chunk ends the region (I19's decline path). Nested BSU is a counted no-op; `RIS`/`DECSTR` clear the mode. | `g->sync` set in the `?2026` arm of `h`/`l`; the hold block in `paint_flush`; `RcHandle::syncSince/syncHolding`; `RC_SYNC_TIMEOUT_MS` | `geo_sync` on the host (first frame held, no paint, replies still out, ESU flushes once, timeout paints and clears, gutter preempts and keeps the mode, nested counts, decline ends it); live `caseSyncOutput` (asserts `rectangles == 0` for the whole region and `== nhold` on the flush that lands) and `caseSyncOverflow`; census "sync updates=N (M nested, K flushes held, ended early by X timeout / Y gutter / Z decline)". The gate's hold leg measures its own cheapest paint (`chunkCostMs`) and asks for the number of holds that fits inside the clock, so it tests the contract instead of the machine's latency. |
| I33 | **HPR (`CSI a`) and VPR (`CSI e`) clamp to the viewport, not to the scroll region.** Both reference terminals agree on the one property that matters: MSFT says so in prose — "Unlike CUF/CUD, this is not constrained by margin settings" (`adaptDispatch.cpp:427`, `:437`) — and ghostty routes both to the same margin-free cursor path (`stream.zig:1863`, `:1942`). So they take `clxy`, which clamps to the viewport, and not `move_row`, which honours the region. VPR keeps the *column*, which is what a test written from CUF/CUD intuition gets wrong: characters printed after a VPR advance it, so an expectation of "column 0" was a bug in the expectation, not in the renderer. ConEmu has neither case (its `Ansi.cpp:3816` switch falls to the default at `:971`), which is why these two sat in `RC_UN_SUP` until build -17. | `case 'a'` / `case 'e'` in `Render.cpp` | `geo_hprvpr` on the host — including "VPR past the region bottom stops at the viewport bottom" and "`RC_UN_SUP` does not grow"; live `caseRelativeCursor`. Control arm `cache/witness/hprvpr-control-20260925.txt`: replacing the two arms with `break` + `move_row` produced exactly 8 host FAILs, all in these legs, which is what certifies them as watches rather than decoration. |
| I34 | **The palette is console state, so OSC 4/10/11 changes it and `close()` hands it back.** ConEmu parses these and does nothing, so the grammar here is taken from MSFT, which implements them: `OSC 4` is `(index;spec)*` with `?` as an inquire per index, `OSC 10/11` walks resources forward one per field, `OSC 104` resets slots and stops at the first unparseable index, `OSC 110/111` reset the defaults only with an empty payload (`OutputStateMachineEngine.cpp:779-866`, `:955-1000`, `:1062-1092`). Accepted specs are `#RGB`, `#RRGGBB` and `rgb:r/g/b` with one to four hex digits each, scaled to 8 bits from the top of the field (`ColorFromXParseColorSpec`, `types/utils.cpp:180`); **X11 colour names are not resolved** (`ColorFromXOrgAppColorName` is a 130-row table) -- a name is counted `RC_UN_OSC_OTHER` like any other unparseable spec, which is the I18 mechanism working rather than a claim that nobody sends one. Two ranges, two effects: indices **0..15** rewrite the console's own 16-entry table through `SetConsoleScreenBufferInfoEx` (the only palette API a classic console has) *and* the folding table, so what the user sees changes -- but the console write is read-modify-write over the entries an application actually touched (`palTouched`), because setting `OSC 4;3;...` must not silently recolour the other fifteen. The fold table is seeded from `RgbMap`, all 256, and the console's live ColorTable is deliberately **not** consulted: on Win10/11 that table is Campbell while upstream's fold has always used ConEmu's own, so re-seeding would recolour every 256-colour and true-colour SGR in the product -- a change worth measuring on its own, not a passenger on this mode. The gap that leaves is stated plainly rather than hidden: for an index nobody set with OSC 4, the fold believes ConEmu's colour while the console displays the user's. indices **16..255** change only the folding table, because a 4-bit attribute has no other slot to put them in -- `SGR 38;5;196` changes which index it lands on, not what a base colour looks like. The first write of a handle saves the console's current 16 entries and `close()` restores them: a renderer that recolours the user's console and leaves it recoloured is a vandal, and the palette outlives the process on a shared buffer. `OSC 10/11` can only be honoured as an **index** -- the console's default attribute is 4 bits per channel -- so `defAttr`'s nibbles are re-pointed to the nearest entry and a query answers with the RGB of the index actually chosen, i.e. the *effective* colour, not the requested one. That is also the one place where I12's "frozen for the life of the handle" gains an exception, and the exception is the mode's whole purpose. **The re-point stays model-side, and that is a limit rather than a choice**: on a classic console `CONSOLE_SCREEN_BUFFER_INFOEX.wAttributes` *is* the current pen, which the same flush has just set from the plan, so pushing a default into it would fight `SetConsoleTextAttribute` once per frame for one application request. Every cell this library writes carries an explicit attribute, so the visible effect is complete for output; what differs is a fill conhost makes by itself, such as the row a resize brings in. The parser stays console-free: it mutates `g->palette[]` and the `palTouched` mask, and the painter applies the marked entries at the end of a flush, exactly as it applies a cursor shape; a grid rebuilt mid-flush carries both, so a pending console write cannot be lost by the rebuild. And the memo in the vendored `Far3Color::Color2FgIndex` (`static LastColor/LastIndex`) is palette-blind -- with a dynamic table it must be bypassed, or a colour folded before the change folds to the old index forever. | `Render.cpp` (`palette_*`, the OSC arm in `osc_finish`, `rc_attr`'s palette parameter), `Render.h` (`palette[256]`, `palTouched`), `RenderJni.cpp`'s `RcHandle` (`palOrig[16]`, `palOrigSaved`), `Paint.cpp`/`RenderJni.cpp` (apply at flush end, restore at close), `vendor/ConEmuColors3.h` (the memo guard) | `gm_palette` on the host: grammar (pairs, `?` mid-list, 104's stop-at-first-bad, 110 with a payload ignored), the two ranges having different effects, `defAttr` re-pointing, a fold that follows the palette it was given, and the attribute/index round trip at the seed sites -- control `cache/p55/control_arm.py` reverts that conversion and fails exactly four assertions, all of them `got 0x4 want 0x1`. Live: `Render.consolePalette(long[])` reads the console's 16 entries off CONOUT$ and asserts the change landed, that the second write did not revert the first, that the **window did not move** (the ninth slot of `consoleView` is `winB` precisely because the InfoEx round trip costs a row and every other field looks untouched), that the query comes back as bytes, and that `close()` restored the table it found. Answering a query inside a synchronized region is I32's existing leg, which is report-kind agnostic. Numbers: host `checks=3502 fails=0`, live `checks=5205 failures=0` on both architectures and again against the deployed bytes. |
| I35 | **`CSI ?7 h/l` decides whether the margin ends the line.** With the mode off, a glyph is written to the last column and every further glyph overwrites that one cell: the cursor holds at the margin, the row takes no `RC_WRAP_FORCED` claim (nothing ran off its edge, so copy and export must not join it to the next row), and no row below is started. A glyph that cannot fit is dropped **whole** -- MSFT clears the cell it could not fit and says why ("Ignore the character. There's no correct alternative way to handle this situation", `Row.cpp:474-494`), and its anti-deadlock guard names this same case for wrap off (`MSFT_TERMINAL_REFERENCE.md` section 2.1). A wide glyph and a narrow astral pair are both dropped as units, because half a surrogate pair is not a character either. Two invariants the clamp made reachable, so it enforces both: the margin clamp steps **off** a trailing half (a cursor never rests inside a glyph -- `step_back_col`'s rule), and a narrow glyph written over a wide one's front half blanks the orphaned back half (I16's pair is one unit; conhost trims the same cluster). Without the second one, every no-wrap row that mixed CJK and Latin would leave a half glyph at the margin. `RIS`/`DECSTR` restore the mode, DECRQM answers 1 or 2 for it, and it left `RC_UN_MODE` the day it became modelled. **What this does not buy is not a gap:** `smam`/`rmam` stay out of the terminfo entry, because the entry describes sessions where ConEmu's own parser reads the stream and ignores `?7` (its `SetConsoleMode` is commented out, `Ansi.cpp:3268-3281`) -- I26 -- and no dbcli code path sends the pair today (`lua/ansi.lua` defines WRAP and UNWRAP with the call sites commented out at :346-352). This is the third-party case: whatever the screen this library owns is handed gets modelled, not whatever this one product happens to emit. | `RcGrid::wrapMode`; `put_cell`/`put_pair`'s fit test, pair trim and margin clamp; `blank_cell`, `last_free_col`; the `?7` arm of `h`/`l`; `mode_status` | `geo_decawm` on the host (hold-and-overwrite, no wrap claim, drop-whole for a wide and for a narrow astral, step-off-the-trailer, the trim with wrap **on** reached through a CUP, DECRQM 1 and 2, both resets, GATM's non-private spelling still unmodelled, and the MODE census falling to 2 with `?7` left in the stream); live `caseDecawm` (the buffer row's last column holds the last of three overwrites, the row below never starts, the console cursor stays inside the window while `stats` says the model is at column `BUF_W-1`, and `?7h` resumes the wrap from the next character) and `legs("DECAWM off at the margin", ..., FALSE)` -- the first *cell* divergence in that family: native `Q` at column 199 against hk `R` with its `Q` one row down. Numbers: host `checks=3713 fails=0`, live `checks=5469 failures=0` on both arches and again against the deployed bytes. |
| I36 | **Whatever an escape sequence can make happen outside the screen is the host's decision, and the parser's shape is what makes that checkable.** OSC 52 is the first sequence in this library whose effect leaves the console: it asks for the user's clipboard, which belongs to other applications and outlives the session. So the switch is off by default and is only reachable from the host -- `ANSI_CLIPBOARD` read once at class-init, or `NativeRenderer.setClipboardPolicy` -- and nothing the byte stream carries can turn it on, which is the property the census cannot supply on its own (a count cannot distinguish a terminal the user configured from one a script configured). There is no ASK state, because a library that owns no window has no way to ask and inventing a prompt channel would be a second product, not a renderer. Refused, each with its own counter so a report says *which*: a selection field other than `c` or empty (one clipboard on this platform, so `p`/`s`/`q`/`a`-`d`/`0`-`7` are not folded onto it -- ghostty folds only because X11 and macOS really have those registers, `stream_terminal.zig:678-682`); a **read** (`52;c;?`) refused even with writing enabled, because the reply would place what the user last copied into the console's *input* stream -- i.e. into the next command line; a payload that fails a strict RFC 4648 decode (whole-payload or nothing, no whitespace skipped, the final group's unused bits required to be zero, a decoded NUL refused because `CF_UNICODETEXT` is NUL-terminated, so storing the prefix would hand the user half a paste); and a payload over the sink cap. An empty payload is the *clear* request, not an absent one. Nothing is restored at `close()` -- snapshotting the register at open would be the read this half refuses. ConEmu implements none of this (measured: its OSC switch has no `case L'5'`), but **both reference terminals do, and both default to allowing it**: Windows Terminal's `OscActionCodes::SetClipboard = 52` (`OutputStateMachineEngine.hpp:222`, dispatched at `.cpp:821-827`, `adaptDispatch.cpp:3302`) is gated by `compatibility.allowOSC52`, whose default is **true** (`ControlProperties.h:59`, `MTSMSettings.h:119`, read at `Terminal.cpp:106`), and ghostty's `clipboard-write` defaults to `.allow` (`Config.zig:2459`). This library's off-by-default is therefore a **deliberate divergence from both references** and the reason is ours to own: those two are terminals the user configures and answers for -- a setting exists because somebody opened it -- while a renderer living inside someone else's JVM has no such config and no consenting party, so silence must read as "not agreed", never as "agreed". Where the references agree, so do we: neither *answers* a read (WT parses `?` and then drops it, `.cpp:825`; ghostty gates reads behind `clipboard-read=.ask`). One deliberate split remains: WT ignores the selection field -- its own comment at `:1097` says "Currently the first parameter `Pc` is ignored", so `52;p;…` writes the clipboard there -- while this build refuses anything but `c` and empty, because folding answers a question nobody asked. **The second half of the invariant is structural, and it is what let the first half be tested at all:** `osc_finish`'s chain of `if (code == ...)` tests became `rc_osc_families[]` -- `{name, owns(code), apply(...)}` -- because the chain could not be *asked* anything. `geo_osc_families` now sweeps codes 0..4096 for double claims (table order is precedence, and that is only readable as priority if no code is claimed twice), demands that every claimed code has a probe and every probe a family, feeds one well-formed payload per family and asserts it neither falls through to `RC_UN_OSC_OTHER` nor sets `modelSuspect`, and witnesses the mark each handler leaves in a field list that is deliberately *not* the whole grid: the payload sink is part of the grid, so a struct-wide comparison would report "the handler did something" for every sequence that was merely parsed. | `RcGrid::osc[]/nOsc`, `clip[]/nClip/clipPending`, `wrapMode` unchanged; `g_clipPolicy` + `rc_set_clipboard_policy`; `rc_b64_decode`, `osc_clip`, `rc_osc_families`, the tail of `osc_finish`; `clip_apply` and the pending block in `paint_flush`; `NativeRenderer`'s static block and `clipboardPolicy()/clipboardWriteAllowed()` | `gm_clipboard` (the decoder's alphabet, padding, canonicality and length rules one at a time -- including the non-canonical `QR==` case that caught this function's first bug -- then policy off, policy on, `c` vs empty vs `p`, the read, the cap, the NUL, and the empty payload as a clear) and `geo_osc_families` (disjointness, probe coverage, no fall-through, no silent handler) on the host; live `caseClipboard`, which is the leg that cannot be satisfied by the model: it reads the clipboard back from a **second process**, because AWT in this JVM answers from the object it was given once the process owns the clipboard, and that cache made eight assertions red for reasons that had nothing to do with the painter. Numbers: host `checks=4065 fails=0`, live `checks=5517 failures=0` on both architectures and again against copies of the installed bytes. |

| I37 | **A parameter that counts things is bounded by what there is to count, and the bound is named where the parameter is read.** `CSI Ps` has two readings, not one. DEC's rule -- an absent parameter and a zero parameter are the same request, and both mean one -- is the common one, but ECH and REP read the value **raw**, because for them zero is an answer: `CSI 0X` erases nothing and `CSI 0b` repeats nothing (ghostty clamps both to one and is the odd one out). And a count is never the number the application wrote; it is that number limited by the rows below the cursor, the cells in front of it, the region it was told to work in, or the model. Writing each limit as an argument to one helper instead of as an `if` at the arm is what made two of them wrong visible in a week: **DL** had been bounded by the viewport's height when its own blanking loop starts at `rows - n`, so an over-large delete erased the rows *above* the cursor and left its own row standing (IL's loop starts at the cursor, so the same bound was harmless there -- the defect was in a quantity, not in a direction), and **DECSTBM** carried three clamps of which two were unreachable because `arg()` cannot return the non-positive value they tested for. The same naming exercise caught a third thing, outside the model: the host gate's own text comparator could be asked to compare **zero** cells -- and vote "pass" having compared nothing, which is what one leg was doing -- or asked for **more columns than the grid has**, where the cells exist in the fixed `RC_MAX_COLS` stride and hold whatever a wider geometry left there, and its "short string means spaces" padding read past the string's own terminator into the next literal. Both shapes now refuse. What the accumulator's ceiling is *for* is the other half of the policy: digits saturate at `RC_ARG_MAX` rather than wrapping (deviation #3 -- `CSI 999999999999H` means the last row, never row 1610612736 mod the screen), while the OSC parser **refuses** ten digits instead, because there the number is a claim -- an index, an exit code -- and a claim arrived at by truncation is a different claim. | `count_arg`, `count_arg_raw`, `region_arg` (Render.cpp, beside `arg`), `RC_ARG_MAX` (Render.h), `shift_region`/`scroll_up`'s own guards (the model bounding a call from inside this file, which is a different act), `push_arg`'s `nArgTrunc`, `RenderCheck.cpp::eq_text` | `gm_argcap` (the 16-argument cap, the count per dropped argument, saturate-vs-truncate, and ICH/DCH/ECH at the row's end), `geo_region`'s gutter legs ("a delete of more rows than there are below the cursor reaches no higher"), `geo_ftcs`'s mark-in-transit legs, and four arms each seen red: DL back to the window's height (2), the counter un-counted (2), `count_arg` returning the raw argument (5), the accumulator allowed to wrap (1). Live: `caseArgClamp`, which reads both halves off a real console -- the cap through `Java_Render_argTrunc`, the bound through the cells above the cursor. Numbers: host `checks=5298 fails=0`, live `checks=5715 failures=0` on both architectures against copies of the installed -28 bytes (`cache/p63/live28c.txt`, the second -28 build). |

| I38 | **A sequence that can change a claim about the terminal needs stored state, and a resize is not allowed to quietly undo it.** `\t` used to be `((cx + 8) >> 3) << 3`, which is not a rule about tab stops but a restatement of the default interval -- and that is why four real sequences were unspellable here: with nowhere to write, `ESC H` (claim a column), `CSI 0g`/`CSI 3g` (clear one, clear all), `CSI Ps I` and `CSI Ps Z` (walk the table either way) could only be refused, and the refusal's own reason was a description of the implementation ("there is no stop for a back-tab to find"). #70 replaced the arithmetic with the state and its two facts -- a claim per column, and a flag saying whether the unclaimed columns are the interval -- and the flag is what makes `CSI 3g` different from a loop that clears the array: one empties the table, the other empties it *and* stops the defaults from ever coming back. Three consequences are pinned rather than argued. **Main and alternate share one table** because it is terminal state (MSFT on the adapter `:2649`, ghostty on the Terminal `Terminal.zig:56`). **A rebuild carries it** and materializes the interval only in the columns that did not exist, and only if nobody cleared it -- MSFT's `_InitTabStopsForWidth` (`:2799-2817`), against ghostty's rebuild-that-forgets (`Terminal.zig:4019`, `:4082`), and our own resize already carries the palette, the OSC 9 face and DECAWM for the same reason. **RIS restores it**, where MSFT's `HardReset` says nothing about tabs and ghostty restores (`:4943`): one reference each way, and the tiebreaker is that DEC's reset means "as at power-up" and a caller with no way to ask for its defaults back has no way to fix a wrong one. The rule generalises: where this document has ever said "not configurable" about something a VT sequence touches, that is a missing field, not a design choice. | `RcGrid::tabStop[]` + `tabsDefaults`, `tabs_default`, `tabs_reset`, `tab_next`, `tab_prev`, `rc_tabs_widen`; the `HT` arm, `case 'I'`, `case 'Z'`, `case 'g'`, `ESC H`, `full_reset`, `rc_reset_hist`; `build_model`'s carry in `RenderJni.cpp` | `geo_tabs` (defaults, HTS not erasing them, TBC 0 vs 3 vs 5, CHT/CBT walks both ending at the wall and at column 0, DECSTR silence, RIS restore, one table across the alt switch, and `rc_tabs_widen`'s contract: claimed stop kept, old columns not re-decided, new tail filled, nothing added after `CSI 3g`); arms T1-T4 each seen red (the arithmetic back in place, TBC 3 keeping the interval, RIS not restoring, the table treated as per-screen); live `caseTabStops`, which is the resize carry's only witness -- HTS, `readopt` (the rebuild production performs on a resize), then the same tab. Numbers: host `checks=5461 fails=0`, live `checks=5738 failures=0` on both architectures against copies of the installed -29 bytes. |

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

Capabilities deliberately left out, with the reason: `cbt`/`hts`/`tbc` (no tab-stop state anywhere),
`smir`/`rmir`/`mir` (IRM has no entity; `CSI @` always inserts), `smam`/`rmam` (the mode is modelled,
I35, but the entry also names sessions where ConEmu's parser reads the bytes and ignores `?7`, so advertising
the pair would be a claim about the other parser), `smkx`/`rmkx` (DECCKM selects *input*, which here comes from console records), `blink`, `invis`
(SGR 5/6/8 store nothing), `rmpch` and the `sgr` 10/11 arms (no font switching), `ncv` (no
cannot-coexist bits), `mc5i`, `flash` (`ESC g` would ring a window that is not ours to ring),
`initc`/`ccc` (OSC 4 changes this renderer's palette and the console's 16 entries, I34, but a reader that asks
`tput` whether the terminal *can* is asking whoever parses its bytes -- and under a ConEmu host that is not this
library, so I26 keeps the claim out), `u8`/`u9` (both DA queries are
answered now, but nothing in the host reads a `user8`/`user9`, so a value would be invented here), and
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
  deleting. Recorded so the next audit leaves the caret alone.
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
  parameter counts repeats rather than cells. `cache/caps-audit/CapsDump.java` asserts all three of those
  sentences, including the failure, because `tputs(rep, 'x', 4)` is the obvious way to write the check.
* **`u7=\E[6n` and `u6=\E[%i%d;%dR` are in, and that reverses this file's earlier position** ("this parser
  never writes a reply back; a caller waiting for one would hang"), because the reply leg now exists (I29):
  `Render.cpp:1470-1482` arms `CSI 5n`/`CSI 6n` and `flush_reports` writes the answer into `CONIN$` as key
  events. Read the pair for what each side is: `u7` is the query the host *writes*, `u6` is the *report
  pattern* the host parses — `CursorSupport.getCursorPosition` (`:83-95`) takes both strings, compiles `u6`
  into a regex, and only ever asks `user6`/`user7`, which is why `u8`/`u9` stay out even though both DA
  queries are answered. `%i` is load-bearing rather than decorative: the reply is one-based, counted from the
  *window's* top (the same arithmetic the painter used, and why the plan, not the parser, computes it), and
  `%i` is what subtracts it back to the zero-based cursor jline hands to its callers. Two refusals are part
  of the advertisement, not omissions from it: `CSI ? 6 n` stays unanswered (`Render.cpp:1470-1482`, whose
guard is `!g->priv` on both arms — an
  extended question answered with a plain reply is a position the asker did not request), and the queue's
  limit is a counted refusal rather than an eviction. The cost of advertising is real and stated: a caller
  that asks now blocks until a reply lands, so on a handle with no readable input the leg says so once in
  `lastError` and counts the failure instead of retrying per query. Both halves are witnesses of the live
  gate, not of the model: `caseReports` reads the reply *text* out of the console's input stream, and
  `cache/caps-audit/CapsDump.java` expands the strings through `Curses.tputs` so that a `%` nobody can
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
   measurement, and the narrow-column path I22 introduced has no timing leg at all. Same gap as `winL` in
   §9.


Shape facts worth remembering, because gates depend on them: the default console profile has a buffer far
wider and taller than the window (2000 × 9001 vs 120 × 60); Windows Terminal and ConEmu size the buffer to
the window; and `mode con: cols=X lines=Y` **collapses the buffer to the window**, so any harness that runs
`mode con:` can never reach the wide-buffer shape — that shape needs its own leg.

Structural choices that still hold: dirty rows are merged into at most 8 runs (past that, one band plus the
union of dirty columns); attributes and cursor moves are sent only on change; the model's own cell shuffling
runs at about 1 ns/cell, two orders below a console call. Each grid is a fixed
`RC_MAX_ROWS × RC_MAX_COLS × sizeof(CHAR_INFO)` allocation — about 4 MB — bought deliberately so that a
resize never reindexes a live model; in host-language tests it must be static, since it will not fit on a
stack.

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
    pair is recorded with its stamp, its md5 and a backup taken before the swap.
11. **A gate helper can invent failures.** `eq_text(g, row, upto, want, ctx)` indexes `want[i]` for every
    `i < upto` with no NUL guard, so an `upto` larger than the literal walks into the merged string pool and
    compares real cells against unrelated text. Pass the length you actually mean, padding with explicit
    spaces when the row is longer: the `line_down` fix arrived with five fresh FAILs, and they were five bad
    expectations rather than five regressions. A helper without a terminator check should get one, or the
    case should not use it.
12. **A number that does not move is a missing witness, not a pass.** When a stamp's whole effect is a new
    counter, the gate's census line must be expected to change; if it comes back identical, the corpus never
    sends that family and the shipped binary's new arm has run nowhere but the host gate, which links the
    model directly and so cannot speak for the deployed DLL. Either say so, or put the bytes in the console
    leg. Build -7 came back identical on both arches, and the leg added to answer it is
    `caseSuspectAlign`'s `\E[p\E[61p\E)0q` block.
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

18. **A new arm must be seen to fire, and a witness's own environment can veto it.** The four -25 console legs
passed on both arches, and the contention branch above fired exactly once -- under the hammer, where the whole
case declined to witness and said so. Rule 12 read from the other side: a green from a branch that never ran is
not evidence, and neither is a red from a branch that cannot tell who wrote. The -27 corollary costs more than
it looks: **the sentence "arm X turns check Y red" is a claim about the gate, not about the code**, so a row
that inherits it from an earlier stamp is carrying someone else's evidence. The half-carry arm was re-run at -27,
came back green, and the cause was a hole in the gate rather than a toothless arm (§6's -27 paragraph and #73) --
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

Current gates, and how to read them: the host gate (`RenderCheck`, cross-run on a Linux host: colour table,
full code-point width cross-check, per-UTF-16-unit resumability, damage bounds over the corpus) and the
live-console gate (`run.ps1`, both bitnesses: the model drives a real conhost, cells are read back, and the
optional reference oracle is the retired in-process parser used purely as an A/B comparison). Both print
totals; quote them only from a fresh run, since the numbers move with the corpus.

Fresh, on `render-2026-09-25-13`: host `checks=3072 fails=0 / RENDERCHECK: ok`; live `checks=4648 failures=0 /
STAGE0 RUN: ok` on **both** arches (`cache/gate13/gate13.txt`, x86-only iteration in `gate13-x86.txt`). Beyond
the two standing gates, the scroll family carries a third witness that is neither: `cache/wide-probe/
StartupRepro.java` writes the same bytes through the plain console API in one process and through render.dll in
another and dumps both whole buffers, and `su-cmp.py` diffs them — the fit shape (40 + 100 lines, nothing may be
lost) and the fill shape (380 + 200, where loss is certain and only *divergence* is a defect) both report
`SU-CMP: ok`, including "the lines land in order raw=399 render=399". That leg is the only one where conhost,
rather than this document, says what the answer is.

Fresh, on `render-2026-09-25-15`: live `checks=4696 failures=0 / RENDERGATE: ok` on **both** arches
(`cache/snap-verify/gate.log`) — 48 checks past the -13 total, which is where the snap's plan cases and the
console-kind line the gate now prints before it paints landed ("console: the gate's own conhost window"). That
line is `isPseudoConsole` answering through the real JNI ABI rather than through the gate's scaffolding. What the
classification changes is not a paint and cannot be gated on cells: the witness is an A/B of the *classifier*, in
`cache/wt-classify-20260925`
(`matrix.cmd` + `run-matrix.ps1`, one report per window). On a real Windows Terminal window with the user's
`ANSICON_DEF=conemu`, the deployed jar picks `windows-conemu` — it hands a painter a grid owned by a headless
conhost that will re-serialise every cell back to VT — and this tree picks `windows-vtp`; clearing `WT_SESSION` in
that window changes neither answer, and a plain conhost window that *inherits* `WT_SESSION` from a WT session keeps
`windows-conemu` here while the environment-only test sends it to `windows-vtp`. The fallback is a leg too: with
`render.dll` unreachable the classifier answers `null` and the old weaker test stands.

Fresh, on `render-2026-09-25-16`: host `checks=3118 fails=0` — the +22 over -15 are the `?u` priv-gate ten
(#49) and the partial-paint fault legs (#44). Both were certified by a control that must fail:
`cache/ansi-2026-20260925/red-arm.sh` recompiles the *trunk* `Render.h` against a `/tmp` copy of `Render.cpp`
with the gate removed → `checks=3118 fails=4`, the four being exactly the new ones; `control-probe-44` reverts
the one line `if (paintUndone) rc_drop_base(g)` → `checks=4723 failures=6` on each arch, all six in
"the refused run came back on its own". That the totals move between trunk and control is §6 rule 3, not a
mystery: a fault-injected plan changes what the damage-bounds check counts, so read a control's *fail list*.

Fresh, on `render-2026-09-25-20`: host `checks=3502 fails=0 / RENDERCHECK: ok`
(`cache/native-probe/out/rendercheck.txt`), live `checks=5205 failures=0 / RENDERGATE: ok / STAGE0 RUN: ok` on
**both** arches against the **deployed** bytes — `run.ps1 -Scratch cache/deploy-20`, whose
`{x86,x64}/render.dll` are md5-identical to `lib/` (`cache/deploy-20/gate.txt`: x86 stamp at :69 and census at
:540, x64 stamp at :610 and census at :1081). That distinction is the point of the run: a green gate against a
build tree says the source passes, and only a `-Scratch` pointed at copies of what ships says the shipping does.
The 465 checks over -15 are DECSET 2026 (I32), HPR/VPR (I33), the `?u` gate and the partial-paint watch, plus
one leg that is not a paint test at all: the gate now reads the report slot table back out of
`NativeRenderer` reflectively and fails if `SLOT_UNSUPPORTED`, `SLOT_SYNC_OVERFLOW`, `SLOT_SYNC_ON` or
`SLOT_LAST` disagrees with its own `S_*` constants. I19 says the census is positional on both sides of the seam;
before that leg, "both sides" meant two files that happened to have been edited in the same hour.

Fresh, on `render-2026-09-26-22`: host `checks=3713 fails=0 / RENDERCHECK: ok`, live `checks=5469 failures=0 / RENDERGATE: ok` on **both** arches, twice -- once against the build tree and once against `cache/p61/deployed`, whose `render.dll`s are md5-identical to `lib/`. The live number is not comparable with -21's 5216 and the difference is worth naming, because it is a hole in how the gate had been run: `caseLegsAgree` prints `SKIP both-leg A/B` and zero failures when it cannot find a ConEmuHk, and `lib/{x86,x64}/` on this install ships `render.dll` but no ConEmuHk, so every recent run silently compared nothing. Pass `-Install` a tree that has `lib/x86/ConEmuHk.dll` and `lib/x64/ConEmuHk64.dll` (`D:/Green/ConEmu/ConEmu` holds both) and the A/B's ~230 checks join the total. Two more things that run taught: a `legs()` case shares one grid with every leg after it, so a mode it turns off must be turned back on inside the same bytes -- `?7l` left set cost `caseWrap` two red assertions three cases later; and `build.sh --no-colorcheck` not only skips the host gate, it leaves a **stale** `out/rendercheck` behind, so a re-run of that binary silently executes the previous build's assertions.

Fresh, on `render-2026-09-26-24`: host `checks=4065 fails=0 / RENDERCHECK: ok`, live `checks=5517 failures=0 / RENDERGATE: ok` on **both** arches, and again against copies of the installed bytes (`cache/p57/live7.txt`). Two of the -24 legs failed for reasons that had nothing to do with the code under test, and both are worth keeping because each is a false green's mirror image -- a test that cannot see the truth.

**The gate's reader was the writer's cache.** `caseClipboard` first read the clipboard back through AWT, and AWT -- once this JVM has called `setContents` -- answers from the object it was handed rather than asking the window system again. Eight assertions went red with the message "read back the same string I seeded", which reads like a painter that never wrote and was a reader that never looked. The leg now witnesses the clipboard from a second process (`pwsh Set-/Get-Clipboard`) and says `SKIP` out loud where that is unavailable, because the fallback is the reader that can lie. Same family as §6 rule 3 and the shadow-buffer trap in the ConPTY harness: a witness that shares state with the subject is not a witness.

**A wrong JNI name is a feature that never existed.** The export was written `Java_..._setClipboardPolicy` for a Java method named `setClipboardPolicy0`; the wrapper catches `Throwable` -- deliberately, so an older render.dll keeps working -- so the missing link arrived as "the clipboard switch does nothing", forever, on both sides of a green build. The hand-maintained export whitelist could not catch it because it was copied from the same wrong assumption: it proves presence, not correctness of spelling. `build.sh` now derives the demanded symbols from the `native` declarations in the two Java files (12 and 18 of them) and fails the build on any name the dll does not export, so the list can no longer drift in that direction. Third lesson, smaller and bluer: `OSC 52;;` never cleared the clipboard because `MultiByteToWideChar` returns 0 for an empty input and the painter read 0 as a conversion failure -- the one payload whose whole meaning is emptiness needed its own branch, and the Win32 sequence gained the `EmptyClipboard()` that documents it.

Fresh, on `render-2026-09-26-25`: host `checks=4236 fails=0 / RENDERCHECK: ok`, live `checks=5688 failures=0 /
RENDERGATE: ok / STAGE0 RUN: ok` on **both** arches against copies of the installed bytes
(`cache/p63/live25-final.txt`; the two runs before it, `cache/p63/live25.txt` and `live25b.txt`, printed -24's
5517 and that is the story below). Six deviations found by reading MSFT's and ghostty's *commit history* against
this code are in this stamp (#64-#69), and the pass earned one lesson that is not about any of them.

**The live count did not move, and that was the finding.** -25's first certification printed `checks=5517
failures=0` -- the number -24 printed. Enumerating every CSI final the console legs send (`cache/p63/seqscan.py`)
showed why: **no leg had ever sent IL, DL, ECH, ICH, DCH, REP or DECSTR.** Every fix in the stamp was witnessed by
the host gate, which links `Render.cpp` directly and cannot speak for the dll that ships (rule 12), and by nothing
else. Four console legs closed it -- `caseEditRows`, `caseEchClamp`, `caseHealPairs`, `caseSoftReset` -- and the
count moved by 171. Two of their lessons are structural, not local. A leg that calls `standardGeometry()` re-opens
the handle and blanks the viewport, so it must sit *below* the cases that read rows an earlier scroll left in the
buffer: placed above `caseRealign`, the new legs erased its evidence and produced eight reds about a row they had
themselves wiped, which is rule 6's dirty-console trap wearing a different costume. And content inside a region
has to be placed with CUP, never with `\r\n`: a line feed rotates the region, so an expectation copied from a
linear write is wrong before the renderer has done anything.

One red on the way was not the renderer's either. See rule 17: the clipboard leg's out-of-process reader caught a
third party's write, and the gate now classifies a mismatch before it reports one.


Fresh, on `render-2026-09-26-26`: host `checks=5201 fails=0 / RENDERCHECK: ok`, live `checks=5689 failures=0 /
RENDERGATE: ok / STAGE0 RUN: ok` on **both** arches against copies of the installed bytes
(`cache/p63/live26b.txt`, x86 summary :922, x64 :1844). The stamp is one feature: `rc_validate_grid()`, the
model's own invariants as a function (#72). The host number grew by 965 because the check now runs at the end
of **every feed** -- all three host paths (whole string, uint16 array, unit-at-a-time) -- over every corpus
string; the live number grew by one because the live gate asserts the export ran 436 times per arch and found
nothing, which is the difference between an arm and a decoration. Nothing was violated: the model was already
consistent, and that is the baseline future stamps are measured against, not a claim the oracle is inert.

What it checks, and what it deliberately does not: geometry bounds, the cursor inside the viewport (a gutter
row is history the painter has no plan for), the saved cursor inside the grid, the region an ordered span,
`rowWrap`/`rowMark` within their enums, a mark's column inside the row, every dirty row naming a range that
exists, and I16 across **every** cell of every row. A cursor resting on a trailing half is **not** on the list
-- `step_back_col` keeps leftward moves off a glyph, but a CUP may name any column and MSFT's `SetXPosition`
does not refuse one either, so that "invariant" would be a red waiting to be explained. See rule 19 for how
both the seeing arm and the silent arm were run.

The pass also caught one of its own witnesses: the clipboard case's final restore failed on x86 with the
register holding the test's own marker, because it attempted the clear **once** and one `pwsh` child had simply
not landed it. The restore is the only leg in that case whose subject is the *user* rather than the library, so
it now retries and, on the non-empty-owner path, refuses to degrade into a skip -- if the restore did not land,
the gate says so out loud.

Fresh, on `render-2026-09-26-27`: host `checks=5218 fails=0 / RENDERCHECK: ok`, live
`checks=5689 failures=0 / RENDERGATE: ok / STAGE0 RUN: ok` on both arches against copies of the installed bytes.
One refactor, no new behaviour: `rowWrap[]` + `rowMark[]` + `markCol[]` and the alt screen's three snapshot
twins became a single `RcRowState` per row (#73). The claim is a shape claim, so it is proved three ways: the
footprint is pinned by `static_assert` in `Render.h` rather than by a measured `sizeof` that differs between
LP64 and LLP64; an arm writes the old half-carry by hand -- the literal -25 #5 bug, now requiring an explicit
two-field act rather than an omission; and the live count is **unchanged** from -26, which is the equality a
refactor is asked to prove.

What the first arm did was come back **green**, and that answer is the part worth keeping. Rule 18 says a new arm
must be seen to fire; the -27 corollary is that a *recycled* arm is a new arm -- `geo_ftcs` was cited in the -25
row as the thing that "still goes red" for a half-carry, nobody re-ran it before repeating the sentence, and it
turned out that every `rc_mark_col()` assertion in the gate
sits on a row that either never moved or was blanked -- for a mark made at column 0, a lost column and a carried
column are the same number, so the arm had nothing to see. The gate was not weak on `mark`; dropping the mark
fires three legs at once. It was weak on the **third field in transit**, which is the field the struct was packaged to protect.
`geo_ftcs` now makes a prompt at column 4 and moves it up with DL and back down with IL, and both arms bite:
carrying wrap+mark leaves `and its column the whole way: got 0x0 want 0x4`, carrying wrap+col leaves three
marks red. Six assertions and three feeds moved the host count by seventeen, and the gap is worth knowing
before you read a leg's cost off its line count: a `put()` also registers its bytes in the corpus, which the
replay and the two damage-bounds sweeps vote on again -- that is why the build log's `resume` line reads 416
strings at -26, 419 after these legs and 427 after #74's. The shipped binaries are untouched by the addition
-- `RenderCheck.cpp` is host-only and never links into `render.dll` (`build.sh:31`) -- so -27's pair, its stamp
and its md5s are still the ones §10 names. What the struct does *not* do is make a half-write impossible: you
can still assign fields one at a time on purpose, and arm A proves it. What it removes is the **default** of
forgetting one, which is the difference between a rule and a shape.

Fresh, on `render-2026-09-26-28`: host `checks=5298 fails=0 / RENDERCHECK: ok`, live
`checks=5715 failures=0 / RENDERGATE: ok / STAGE0 RUN: ok` on both arches against copies of the installed bytes
(`cache/p63/live28c.txt`: x86 stamp at :68, the parameter-bound case from :780, summary at :937; x64 stamp at
:1005, case at :1717, summary at :1874). #74 gave every count its named bound (I37), and two defects came out of the naming.

One was in the model, and rule 18 is what made it provable rather than plausible: the arm that reverts DL's
bound to the viewport's height turns two host legs red and, against a scratch build of that same source on a
**real console**, eight (`cache/p63/live28arm.txt` :792-:799 -- `DL-1` and `DL-2` gone from the two rows above
the cursor, which is the user-visible shape of the bug). A leg nobody has seen fail is a leg nobody has read.

The other was in the gate, and it is the more transferable one: `eq_text(row, upto, want)` compares the columns
`[0, upto)`, so a leg that passed `upto = 0` compared **nothing** and voted pass -- one leg in `gm_erase` had
been doing that since -25. It was not found by reading the leg; it was found because a leg written this morning
made the same mistake and came back green while asserting nothing. The same helper would also read past the
grid's width (the cell array is a fixed `RC_MAX_COLS` stride, so the columns past `cols` hold what a wider
geometry left there), and its padding for a short `want` indexed past the string's own terminator into the
following literal. Both shapes now refuse, and three older legs were rewritten to say the width they meant.
The lesson is rule 12 from the inside: an assertion's cost is not its line count, and a helper that *can*
compare nothing eventually will.

The red that was **not** the code's, recorded because it is the easier mistake to make: the first `caseArgClamp`
asserted that after `CSI 9999M` the rows below "come up into it", and it went red on both arches. The model was
right and the expectation was the ordinary case (delete two, the third lands where the second was) smuggled into
an over-large one, where the honest answer is that everything below the cursor is simply gone. A red is a claim
about one of two things -- the code or the reader's model of it -- and the cheaper reading is usually the wrong
one. Fix the expectation only after the mechanism says which side is wrong.

Fresh, on `render-2026-09-26-29`: host `checks=5461 fails=0 / RENDERCHECK: ok`, live
`checks=5738 failures=0 / RENDERGATE: ok / STAGE0 RUN: ok` on both arches against copies of the installed bytes
(`cache/p63/live29b.txt`). #70 put a table behind `\t`, which is I38, and with it `ESC H`, `CSI Ps g`,
`CSI Ps I` and `CSI Ps Z` stopped being refusals.

The first thing the new case did was catch its own author: the initial `caseTabStops` fed `\u001b[H` for HTS,
which is `CSI H` -- CUP, "home" -- and the console answered column 0 on both arches. The host gate was green
because its legs used `\033H`. Same sequence family, one character apart, and only the screen could tell them
apart; it is the same character that made this round's own RIS leg red in the host gate, where `\033[c` (DA1)
had been fed instead of `\033c`, and the model was right while the leg was wrong both times. **A sequence rule
learned from a summary is a hypothesis; the bytes are the evidence.**

Two census consequences were re-baselined rather than quietly absorbed. `geo_census` had asserted that a CBT
raised `RC_UN_SUP` by one; CBT is modelled now, so that leg asserts the opposite and says why the sentence
changed. And `ESC H` left the counted-ESC row of `ANSI_SUPPORTS.md` §2.2, because "no cell moves" was true of
the refusal and is false of the claim -- it moves state. No census *slot* moved, so nothing about the stats
layout or the jar's table shifted (contrast §6's -28 note on `nArgTrunc`, which is a different kind of
deferral).

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

**From the retired in-process parser**, measured cell by cell and still pinned as expected-difference
gates. The reference leg is gone from production; the comparisons remain because the deviations are real
properties of the model, and because two of them were decisions rather than accidents:

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

One rejected proposal, recorded so it is not retried: **deferred wrap** (the delayed-newline model). Four
shapes that would discriminate it were run on both legs at a 200-column buffer with a 100-column window and
all four agreed. Switching would *create* a divergence, not remove one.

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
MSYS_NO_PATHCONV=1 wsl.exe -e bash -lc   'JLINE_CAPS=/mnt/d/JavaProjects/jline3.29/terminal/src/main/resources/org/jline/utils/windows-conemu.caps    JAR=/mnt/d/dbcli/lib/JLine3.jar tr -d '' < /mnt/d/dbcli/src/c/conemu/terminfo/terminfo_check.sh | bash -s'
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

## 9 Open work

* ~~**A partially failed paint tells the model the paint succeeded.**~~ **Closed at -16 (#44), and the fix is
  option (b) from this bullet's own list** — `rc_paint_done(g)` then `rc_drop_base(g)` at the end of the flush, in
  that order because the drop *is* the re-mark; three lines, no new primitive, and the cost is one whole-viewport
  repaint on the next flush. `SetConsoleTextAttribute` and `SetConsoleCursorInfo` now have their returns checked
  into the same watch (`paintUndone`), so a refused attribute or cursor shape no longer stays asserted by the
  model. What made it shippable was the gate leg that could show it: a gate-only fault injection,
  `Java_Render_faultRect(h, run)`, refuses one named run of one named plan once and then disarms itself, so
  `casePartialPaintFailure` can build a two-run plan, land the first, have the second refused, and then — the
  claim that is #44's boundary — paint one unrelated character and assert the *refused* run came back by itself.
  Red arm `control-probe-44` reverts exactly the `if (paintUndone) rc_drop_base(g)` line and fails 6 on each
  arches, all six in "SECOND didn't come back". The reasoning in this bullet was right and its census was too:
  the shape had never been produced by any leg, which is precisely why the fix needed an injector rather than a
  watcher. Note the asymmetry it documented, since it is the reason a `fails=0` gate never covered this: *a
  refused move corrupts addresses, so it self-heals; a refused run corrupts contents of rows whose address is
  still right.*

* **Quitting a pager that took the alternate screen leaves one prompt row too many.** Recorded while
  re-witnessing #13/#14 at -13 (`cache/witness/pager13-20260925-13.txt`, OBSERVATION block; raw dumps
  `cache/jnatest/outrepro/grid-ceoff.txt-s{0..4}.txt`): the two alternate-screen legs each keep a second `SQL>`
  above the live one -- ceoff restores to `r04|SQL> more cache/pgcorpus`, `r05|SQL>`, `r06|SQL>` with the cursor
  at `(5,6)`, and the `one14` leg shows the same pair at `r12`/`r13` -- while the one-screen auto-exit that never
  entered the alternate screen leaves exactly one prompt row (`r11`). It does not break #13: the cursor and the
  typed command both land on the live row, which is what that task was about. It does sit against the standing
  invariant this library is held to -- *whether starting or quitting, do not disturb the text the terminal
  already showed* -- because the extra row is a prompt the host did not owe that position. **The mechanism is
  not established**, and the two candidates split across the seam: either the restore left the cursor one row
  above where the restored screen ended and JLine's readline then painted a prompt there (host-side), or a row
  the main buffer genuinely held before `SM 1048` is being repainted as a prompt (this library's, and
  `geo_alt`-gated). Distinguishing them needs a leg that dumps the main buffer immediately before entering the
  alternate screen and immediately after leaving it, which no harness here does yet; that leg, not a guess, is
  the item.

* **Status bar: modelled, gated, witnessed live -- and one of its live symptoms turned out to be ours.** The
  byte stream a status line produces — `DECSC`, `csr(0, n)`, `DECRC`, the lines at the bottom — is replayed by
  the host gate case `status_bar`, which pins the three things the feature depends on: the caller's cursor
  never lands in the status rows, ordinary output rotates the region without touching those rows, and the two
  spellings of "undo the region" are different writes. They are, and the difference is the whole story of that
  part of the bullet: `csr` carries `%i`, so `csr(0, 0)` compiles to `CSI 1;1r`, a region one row tall — the
  opposite of a reset, and enough to make every later line feed rotate inside the top row. `CSI r` is the reset.
  The first live leg (`cache/witness/statusbar-live-20260924.txt`, build -5) put the bar on the row directly
  below the prompt, with the cursor at column 5 of that prompt row — outside the region, which is the MSFT
  failure mode this feature was specified to avoid. It also showed two things that leg recorded as *not*
  settled and as upstream of this library: the bar's two lines arriving as one composite row with a blank row
  under it, and the session's text above the prompt gone. **Both were a defect in `line_down`, and both are
  fixed.** A line feed issued while the cursor sat *below* a narrowed region rotated the region and left the
  cursor where it was, so each newline the bar drew moved one row of the session's text away and folded the
  bar's second line onto its first. MSFT's `_DoLineFeed` is the authority and was read locally: it scrolls only
  at `y == bottomMargin` and otherwise clamps to the page bottom (`adaptDispatch.cpp:2443-2453`). The case is
  pinned in `status_bar` on a second grid — four rows of text, region `1;4r`, cursor driven below it, the bar's
  two lines written there, and `nScrolls == 0` asserted alongside the row contents and the final cursor row —
  because "no scroll" is the half that a correct-looking grid can still get wrong.
  Re-witnessed on a real console against the -6 pair, all three legs in
  `cache/witness/statusbar-live-20260924-6.txt`, and again against -13 in `statusbar-live-20260925-13.txt`
  (`VERDICT A/B/C: ok`, every row number the same -- the -6 file is now the history, the -13 file is the record):
  bar opened then `help` -- border on the viewport's
  next-to-last row, title on its last, prompt one row above them, 49 text rows visible where -5 reported 2;
  `help` then bar opened -- the help listing still on rows 36..81, which is the erasure gone; and bar opened,
  `help`, bar closed -- rows 47 and 48 blank again, prompt at 46, nothing above it disturbed. Closing is the
  one shape that leaves a *correct* gap: the freed rows are not redrawn, because redrawing them is the host's
  business and not this library's.
  *How the wrong conclusion survived a control leg* is the part worth keeping. The -5 witness compared `help`
  then `set Status on` with the native renderer on and with `DBCLI_NATIVE_RENDER=off`, got identical grids,
  and inferred the host. That comparison could not have come out any other way: the variable has no reader, so
  both legs ran this parser and this painter (rule 5 above), and what looked like a control was the treatment
  wearing a control's label.
* **The census of what the host's editor depends on is done.** The reference is the terminal's own built-in
  editor, which is a Java port of `nano` rather than `nano` itself: `Nano.java` writes **zero raw escape
  bytes** — all 4,240 lines emit through four layers only, `Terminal.puts(Capability)`, `Display`, `Status`
  and `AttributedCharSequence` — and parses none on input, matching `KeyMap` prefixes against terminfo
  *input* caps instead. The set it can put on the wire is therefore small and known: `CSI H` + `CSI 2 J`
  (once per frame, because the editor forces a full erase on Windows terminals), `CSI K`, the CUU/CUD/CUF/CUB
  family, `CSI K L M @ P`, `ESC 7`/`ESC 8`, `CSI ?1049h/l`, `CSI ?25h/l`, and the SGR set
  `AttributedCharSequence` hard-codes (`38;5;`/`48;5;` — 256-colour is forced on for this terminal type, so
  truecolour spells nothing here). Three of this project's open worries simply do not apply to the editor:
  it writes **no OSC at all** (OSC 0/2 stays a prompt-side requirement), it **never emits** `CSI Ps b` REP or
  `CSI Ps X` ECH — no code path in the whole tree does — and it **never queries** the terminal.
  Read that with the next bullet rather than as a reason to leave `rep` out: the entry describes the
  *terminal*, and an editor that happens not to use a capability is not evidence that the terminal lacks it.
* **Two sequences reached a final, did nothing and left no count — closed, and their witness is narrower than
  the change.** `CSI p` in every spelling but the one DECSTR gates on (`interim == '!'` with no arguments,
  `Ansi.cpp:3645`; the `CSI Ps;Ps!p` restore-memory form drops there too), and a charset designator other than
  `ESC ( 0` — `ESC ) c` and `ESC % c`, which have no case upstream either (`:2751-2767` covers `ESC (` alone
  and falls to `DumpUnknownEscape` at `:2769-2770`). Both now spend `RC_UN_SUP` and set no `modelSuspect`:
  counted as inert, not as a reason to re-adopt the console. The distinction is the half that could have gone
  wrong silently — a charset with no model moves no cursor, so charging a full-window repaint per frame for it
  would have been a performance bug wearing a correctness fix. `ESC % G` matters for a second reason: it is
  what an application writes when it believes it is switching to UTF-8, and the census is the only place that
  can still say so afterwards. Stamp `render-2026-09-24-7`, deployed for both bitnesses with the -6 pair kept
  (`cache/witness/census-20260924-7.txt`).
  What that witness adds, past the usual argument that the host gate links `Render.cpp` directly and so says
  nothing about the shipped binary: the first -7 gate run came out **byte-identical on its census line** to
  the -6 one, and since both new arms feed `unrecognised`, an identical line proves the console gate's own
  corpus contains neither family. That is not a control leg; it is an absence of one. `caseSuspectAlign` now
  paints `\E[p\E[61p\E)0q` through `render.dll` and a real conhost and asserts the delta of 3, the delta of 0
  aligns, and the `q` in the cell — 4364 checks, both arches, and the process-wide line reads
  `unrecognised=6` where -6's read 3.
  The scope statement is the live session's own line, the first ever captured (`-Native on`, `help`, driven to
  `exit` so `report()` lands): 65 flushes, 9997 cells, 59 scrolls, and `not modelled: bracketed paste 5` — no
  `unrecognised` family at all, because a zero is not printed. So neither new arm fires in a real dbcli
  session today. The reason to land it anyway is the census contract: it is only worth having if it holds for
  sequences that have not been sent yet, and the report line is what makes "today's output contains none of
  them" a fact a rollout can read instead of an assumption.
  The caps half of the same audit is §4's rulings (`kbs=^H` stays, `kf13` and the shifted arrow names stay
  out, `rep` advertised with xterm's canonical value, and `u6`/`u7` in now that the reply leg exists), pinned
  by `cache/caps-audit/caps-final.txt` — 81 ok, which means every string was expanded through
  `Curses.tputs` and not merely parsed. One dependency is outside this library: the entry is a classpath
  resource, so nothing a session sees depends on the file in the tree until `lib/JLine3.jar` carries it. That
  gap is now closed and measured rather than predicted: the jar (2026-09-25 01:21, md5
  `94bb0670b2f5819bcb57a6fb30fcff6a`) holds an entry byte-identical to the owner's source resource
  `terminal/src/main/resources/org/jline/utils/windows-conemu.caps` (md5
  `89dea073628196d6e949bdcf2d268f9b`), and `CapsDump` returns `CAPS CHECK: ok` against each of them separately
  (`cache/caps-audit/caps-13-src.txt`, `caps-13-jar.txt`). Two of those assertions had to move with the entry:
  they read `u6 NOT advertised`, which was true of the old file and false of the ruling, so a green caps audit
  was certifying the absence of the reply leg task #29 had just landed — the one real case of a harness
  becoming a second source of truth by pinning a superseded decision.

* **Who answers `CSI 6n` — closed, by answering it.** The earlier reading of this item was that the question
  does not matter, and it was half right: the editor does not ask, and neither does the line editor on this
  platform, because `AbstractWindowsTerminal` does not override `getCursorPosition` and so inherits
  `AbstractTerminal.java:251`'s unconditional `null`, and the only implementation that would write the query
  is `CursorSupport.java:83`, reached from the POSIX and external terminals. What that reasoning missed is
  the *third-party* program run inside the console that probes with `CSI 6n` or `CSI c` and waits. It has an
  answer now (I29), the entry advertises `u6`/`u7` (§4), and the retirement's one real cost is paid. Note the
  asymmetry that survives the fix: advertising the capability does not give the *host* a cursor query,
  because no Windows terminal class implements `CursorSupport` — `grep 'Cursor getCursorPosition'` over
  `terminal/impl` answers `AbstractPosixTerminal`, `ExternalTerminal` and the `AbstractTerminal` null, and
  nothing else. So `set mouse` still refuses on a non-`WinSysTerminal` session, and says why, which is the
  other half of this item: the reader's mouse widget dereferenced that null (`LineReaderImpl.java:5971` →
  `:5984`), the option is off by default but user-reachable, and the refusal turned a click-time NPE into a
  sentence at the command. Witnessed on two live legs, the `WinSysTerminal` one enabling silently and the
  forced-`IS_CONEMU` one printing the refusal where the throw used to be.
* **A paint that wrecked the user's scrollback for six stamps, and what it took to see it.** See I30, I31 and
  §6 rules 14-16. The first defect was in `scroll_region`'s destination and was invisible in the window for as
  long as the plan was only ever *argued* about (-11). The second was in the scroll's *reach* (-12, -13): the
  eviction a full buffer owes was keyed on the anchor instead of on the plan's destination, so a flush that
  slid 19 lines and scrolled 1 kept the band answer and left 401 live lines in 400 rows. Both were invisible
  where a user looks, and both were settled only by reading every row of a buffer no window was looking at —
  first as a hand-written census in the live gate, then against conhost itself, which is the only version of
  this argument that does not depend on this file being right. Recorded here as open because the *class* of it
  is still open: any console call whose arguments this library invents is a candidate, and the only defence is a
  witness that reads outside the region the call touches. Deployed as `render-2026-09-25-13` for both
  bitnesses; the replaced pair is in `cache/deploy-backup-20260925-021247/{x86,x64}` with the before/after md5
  in `md5.txt` beside it (that backup also carries the -11 bytes, which were the last ones shipped before the
  scroll family closed). The whole -8..-13 sequence is in the `RENDER_BUILD` comment at the top of
  `RenderJni.cpp`, which is where a stamp's *divergence rule* lives: which pairs of binary and tree agree on
  every paint, and which single flush is where they part.
  The hand witness for the same arithmetic, `cache/wide-probe/ScrollRepro.java`, had to be split in two for the
  same reason. It fills a 400-row buffer with 420 lines, which is already past saturation, so the paint it was
  written to catch takes the eviction branch — and its long-standing verdict "0 rows changed above the claim"
  came back as a FAIL against a -13 that is behaving correctly. It now runs both shapes and prints which one
  it is in the same breath: `room` (300 lines, 99 rows free below the claim) keeps the original claim exactly,
  `full` (420) asserts the weaker and still real one — every row above the claim holds what its neighbour held,
  in order, with nothing else moved and one line gone from the top. That is also the honest statement of what
  the user gets: scrolling up during a long session, their history stays complete and legible under them, and
  ages by one line per line printed, because that is what the buffer is. (`scroll6-room.txt`,
  `scroll6-full.txt`; both zero FAIL lines on -13. `scroll4.txt` is the stale verdict, kept to show the shape of
  the mistake.)
* **The `winL` gap in narrow rectangles (I22).** `write_rect` translates model columns by `winL`. Nothing
  can produce a `winL > 0` shape in either gate — the live helper pins the rectangle's left edge to 0 — so
  the only witness so far is a real session that happened to be horizontally scrolled. Fix by parameterising
  the geometry helper or adding a gate-only horizontal scroll, then paint one narrow column. Touching
  `RenderJni.cpp` means the build stamp and a full re-run.
  The same blindness runs through the benchmark: `PaintBench.cpp` sets `paintCols = bufW - winL` with
  `winL` pinned to 0, so the I22 narrow-column path has **no timing leg either** (§5 consequence 4). A
  one-cell status line is claimed to cost one call's fixed overhead rather than 60,000 cells, and that
  claim is currently argued from the planner's structure, not measured.
* **`rowWrap[]` (I20) has no reader yet.** Set, carried and cleared with full gate coverage, waiting for the
  product that needs it (copy/selection and paging that distinguish hard from soft wraps). Do not optimise
  for it or change its meaning before then.
* **A/B of a wide-buffer scroll** to record deviation 1 above -- still owed, and now distinguishable from what
  was actually produced at -13: `cache/witness/wide1516-20260925-13.txt` is an A/B of the reader's *line width*
  (a 170-char line in a 2000-column buffer with a 125-column window, against the same line with the window made
  the buffer), not of a scroll. Nothing in it moves a buffer row, so deviation 1 remains ungated by any live
  leg and stands on `plan_runs` plus §3's I31 algebra. The §5 measurement is owed on top of it: real session
  wall clock. The existing harnesses have no timers at all, and a 50-line workload is smaller than
  the JVM's own startup noise.
* **Whether the host should emit OSC 133 at all.** The model reads it (I23) and the marks' only current
  reader is the gate; a live session's census shows no prompt has ever been marked. That is a product
  decision for the host's owner, not this library's.
* **The library is committed; the compile tree still is not.** `5dec33bd` in the host's repository carries
  this directory, the launcher, `render.dll` for both architectures and the refreshed Java side, and drops the
  retired in-process parser's two DLLs — they are gone from the install tree as well, backed up with a per-file
  md5 manifest before deletion. What that commit does *not* cover is `D:\JavaProjects\jline3.29`, whose git
  repository has zero commits: the tree `javac` actually reads is versioned only by being copied into
  `src/java`. The copy is the host's own `src\copy_to_git.bat`, and reading it end to end corrects two things
  this document previously asserted. It is not additive — `del /F/S/Q ".\src\java"` really does empty the
  directory recursively, which is why the mirror under the install root was safe to delete: the next run of the
  script rebuilds it. What drifts instead is *when the script is run*, and the two classes that survived in the
  repository for months after the compile tree dropped them are evidence of that, not of a missing prune.
  The second correction is worse, because it is silent: the script's `jline3.29\opencsv\src` and
  `jline3.29\nuprocess\src` paths no longer exist — opencsv builds from `D:\JavaProjects\dbcli\opencsv2\src`,
  and nuprocess was folded into the dbcli tree itself at `com\zaxxer\nuprocess`, which the jar build's own
  javac output confirms. `XCOPY` of a missing path prints "File not Found" and returns, so those two lines
  currently copy nothing.
  The same drift now has a second, measured instance, and it narrows what §10 row 12 is allowed to claim. The
  audited terminfo entry is `89dea073628196d6e949bdcf2d268f9b`, and the copy inside the *install* tree's
  `D:\dbcli\lib\JLine3.jar` is that entry — but the copy inside the *repository* tree,
  `D:\Green\github\dbcli\lib\JLine3.jar`, is still `bc4bfebf71a999da11524b73f99bce59`, and so is the entry in
  the second jline checkout at `D:\Green\github\jline3.29`. That jar is modified-but-uncommitted in the
  repository, i.e. somebody is mid-edit, so it was deliberately left alone rather than overwritten. The
  sentence "the entry that ships is the entry that was audited" is therefore true of the tree the user runs and
  false of the tree that versions it, and only `unzip -p` on each jar says which is which.

## 10 Task ledger: rows up to #76 (the numbering has holes, and they are deliberate)

Rows 1-74, 76 and 70's row below are here -- which is to say the numbering runs to #76 with holes that are
each accounted for. **#75 is not a row yet**: it is the last architecture-pass ticket the user approved in order
(row-pointer rotation), reserved so that when it ships it can be joined to `ANSI_TODO.md` section 10, where
**#77-#88** (the re-argued refusals), **#89** (the `stats()` slot #74 left unclaimed) and **#90** (the caps
declaration #70 earned) are listed with feasibility and gates. Reserving numbers is what keeps "where is #75?"
from becoming a hunt through the wrong document.


This section exists so a later reader can re-walk the work without re-deriving it from the transcript. It is a
map, not a narrative: one row per tracker task, and each row says **where the behaviour lives**, **what proves
it**, and **what that proof printed most recently**. The tracker's own subjects are quoted verbatim (they are
Chinese, and re-wording them would break the join); the ordered list of the first 36 is kept in
`D:\dbcli\cache\trace\taskdump2.txt`, one subject per line, line *n* = task *#n*. Tasks 37 onward were added to
the tracker on 2026-09-25, after that dump, so their subjects come from the tracker itself — and for #42, #43,
#47 and #50 the tracker's subject line *is* the conclusion ("结案：探针读取 conhost shadow buffer 的假象"), which
is why the rows below read longer than the subject.

`WORK_ORDER.md` numbers its own tickets T1..T6, and the tracker's subjects do not carry those numbers, so the
join has to be written down somewhere (a reader asking "where is T1?" is the evidence): **T1 = #49** (shipped at
build -16), **T2 = #59**, **T4 = #51** (both at -18), **T3 = #50** and **T5 = #58** (both at -17), and **T6 was
never built as a task** -- the order marks it optional and it is still open, with the reason in its own row
below. Where a ticket was executed with a deliberate disagreement, the row says so rather than claiming the
ticket verbatim: #51 refused T4's `RcModeDef` table, its 1048 reply and its "2027/2048 answer 4".

How to re-run the two standing gates, which carry every `render.dll` task between them:

* **Host gate** — `wsl.exe -d Ubuntu-22.04 -- bash -lc 'cd /mnt/d/dbcli && bash src/c/conemu/build.sh'`, and on a
  distro whose `g++` is missing (this box's default WSL has none) `CC_HOST=$(command -v clang++ || command -v g++)
  bash build.sh` from inside `src/c/conemu`. It
  compiles `RenderCheck.cpp` against the console-free core and runs it natively. The passing line is
  `checks=5461 fails=0` followed by `RENDERCHECK: ok`, in `cache/native-probe/out/rendercheck.txt` (3072 at
  build -13, 3118 at -16, 3222 at -17, 3318 at -18, 3329 at -19, 3502 at -20, 3632 at -21, 3713 at -22, 3803 and 3810 at -23, 4054 and 4065 at -24, 4236 at -25, 5201 at -26, 5218 at -27, 5298 at -28 and 5461 at -29; the steps are the pseudo-console and snap legs, then the
  `?u` priv gate plus the partial-paint fault legs, then DECSET 2026 and HPR/VPR, then the interim set and DECRQM, then DECSTBM's validation, then OSC 4/10/11, then OSC 9, then DECAWM, then OSC 52 with the
  family table's disjointness and coverage sweep, then the six cell-integrity witnesses (`heal_pairs` and
  `no_orphan` over every row of every replayed corpus, IL/DL's column, ECH's row clamp, `soft_reset`, the
  recycled row's `markCol`, and what `lastUnit` (`Render.cpp:768`) is allowed to remember), then the grid oracle running at the
  end of every feed, then the six legs that move a prompt made at a **non-zero column** -- the witnesses #73's arm needed after it came back green (#73), then #74's bounds -- the parameter cap and its counter, the row-end limits of ICH/DCH/ECH and the delete-line reach. The corpus behind them reads 416 strings at -27, 419 after the first two and 427 after #74, which is why a leg's cost is not its line count. The `build.sh` export check grew a
  second, derived leg in
  `NativeRenderer.java` and demands the dll export each one, because the hand-written whitelist above can be
  *wrong* -- not short, wrong -- and a wrong JNI name is a feature that silently never existed.
  trap worth recording is that `build.sh --no-colorcheck` **does not run the host gate at all** — the output
  simply has no `RENDERCHECK:` line, so a run that skipped it looks like a run that passed. Check for the line.
  The sharper half of that trap, paid for again on 2026-09-26: the flag also skips *compiling* `out/rendercheck`, so
  the stale binary is still there and re-running it prints a confident, green, wrong `checks=` line for the previous
  build's sources.
* **Live gate** — `pwsh -File src/c/conemu/run.ps1 -Arch both`, and it must be given a real console (Git Bash
  is not one; the established wrapper pattern is a `.cmd` under `cache/gate13/` started with
  `cmd /c start "" /min /wait cmd /c …`; Git Bash rewrites a bare `/min`, so prefix the wrapper with
  `MSYS2_ARG_CONV_EXCL='*'`). Both bitnesses must pass: `checks=5738 failures=0`, `RENDERGATE: ok`,
  `STAGE0 RUN: ok`, currently at `cache/p63/live29b.txt`, which is the run against copies of the **deployed**
  bytes (`-Scratch D:/dbcli/cache/p63/deployed`, md5-equal to `lib/{x86,x64}/render.dll`: x86 stamp at :68, IL/DL
  from :724, ECH from :741, the pair-integrity leg from :751, DECSTR from :774, clipboard from :865, the grid
  oracle's own assertion at :898, summary at :922; x64 stamp at :990, summary at :1844 -- anchors -27
  reproduces exactly on the live side, which is the equality a refactor is asked to prove; -28 puts the stamp at
  :68, `caseArgClamp` from :780 and the summary at :937 on x86, :1874 on x64). 5469 at -22, 5482 at
  -23, 5517 at -24, 5688 at -25 (the +171 is the finding of §6's -25 entry: four console legs that had never
  existed, because no leg had ever sent IL, DL, ECH, ICH, DCH, REP or DECSTR), 5689 at -26 (the +1 is the
  oracle's own "it ran" assertion, and it is a different thing from the 436 runs behind it), 5715 at -28 (the
  parameter-bound case, :780 on x86 and :1717 on x64 -- and its arm, the same gate against a scratch build
  with DL's bound reverted, is `checks=5715 failures=8` in `cache/p63/live28arm.txt`, eight cells: the two rows
  above the cursor, wiped; -29 adds `caseTabStops` at :795 on x86 and the same on x64). **The count depends on a flag the script cannot default to**: `caseLegsAgree` prints
  `SKIP both-leg A/B` and no failures when it finds no ConEmuHk, and `lib/{x86,x64}` on this install ships
  `render.dll` only, so several stamps were run without a single A/B check. Pass
  `-Install D:/dbcli/cache/p61/hk` (a tree holding `lib/x86/ConEmuHk.dll` and `lib/x64/ConEmuHk64.dll`, both
  copied from `D:/Green/ConEmu/ConEmu`) and the ~230 legs-agree checks appear; `-Install D:/dbcli` alone does
  not, because the path is `lib/<arch>/ConEmuHk[64].dll` and it is `ConEmu`'s own directory, not an install
  tree. Note the forward slashes: Git Bash eats the backslashes in a bare `D:\dbcli\...` argument.
  That run was given `-Scratch cache/p62/deployed`, a copy of the
  **deployed** `lib/{x86,x64}/render.dll` (md5-checked against `lib/` before the run) plus the `probe.dll`s the
  script needs, because `run.ps1` compiles its own harness and therefore takes any directory holding those four
  files: it is how the gate verifies shipped bytes rather than freshly built ones. Do not point `-Scratch` at
  `lib/` itself — there is no `probe.dll` there and the script bails out per arch.
  It prints its `console:` line before painting, which puts `isPseudoConsole` through the real JNI ABI as a
  side effect of the gate.

The artifacts these numbers belong to, as of build `render-2026-09-26-29`: `lib/x86/render.dll`
`4fd49b2a6418b1238950f2164d8f9709` (162048) and `lib/x64/render.dll` `194aa0b61243a3915aa02415abcf69c7`
(156799), both printing stamp `render-2026-09-26-29` when read back through the live gate re-run against copies
of *those installed bytes* (`cache/p63/live28c.txt`). **This pair is the second -28 build**, and the reason is
worth the sentence: the first one was deployed, gated on both arches and census-ed (`953e3e0f…` / `3dd3fa1b…`,
kept as `lib/{x86,x64}/render.dll.20260926-173202.bak`) before a loop in the REP arm was rewritten to a form
the compiler accepts -- behaviourally identical, so the gates would have passed either way, but the shipped
bytes were no longer a build of HEAD. "Stamp says -28" is not the same claim as "these bytes are that source",
and only the rebuild plus a re-run settles the second one. -29 adds a 4096-byte array and a flag to the grid plus the
five arms that read them, and grew 1582 and 557 bytes over -28. -28 was real code again -- a named bound wherever
a count is read, a counter on the parameter cap, and a 31st export (`Java_Render_argTrunc`, gate-only) -- and it
grew 593 and 588 bytes over -27, which is the direction new code goes (the two -28 builds are the same size as
each other, which is what the byte counts can honestly say). The pair -29 replaced is
`lib/{x86,x64}/render.dll.20260926-181951.bak` -- the -28 build, `62ef889d…`/`864e5c2a…`, and its own
predecessor is `*.20260926-173202.bak` (`953e3e0f…`/`3dd3fa1b…`, the superseded first -28 link). `lib/dbcli.jar` did **not** move: the truncation
count deliberately stopped short of a `stats()` slot, and #74's row says what that slot would cost. **The
repository's own `lib/` copy is caught up by this commit**: the archive in `D:\Green\github\dbcli` was still
holding the -24 pair, because -25 through -27 recorded their md5s here without re-copying the binaries. The
census in this section describes `D:\dbcli\lib` -- the tree that actually ships, the one the gates were run
against; the repo copy is an archive, and an archive that lags four stamps is how a later reader ends up
diffing the wrong bytes. The pair -28
replaced is `lib/{x86,x64}/render.dll.20260926-170011.bak` -- the -27 pair, read back off the backups themselves
as `a46ae4e5688c10db1202a928a8a7608e` (159873) and `2e25a82778e427aec8086e8573cd95c0` (155654) -- with the first
-28 build sitting between them and this one at `*.20260926-173202.bak` (160466 / 156242, the same sizes, since
the rewrite moved no code the optimiser could not fold back). -27's claim
stands underneath this unchanged: both of its binaries were *smaller* than -26's (159873 vs 160436, 155654 vs
155704) while the live gate printed an identical count, three field stores becoming one struct store at each of
the four sites, which is the direction a shrink should go and the only performance claim that stamp was allowed
to make (the layout is pinned by `static_assert`, not by size). The host count did move, from 5201 to 5218, and it moved for the reason §6's -27 paragraph tells: the
half-carry arm was green until `geo_ftcs` got a witness that could see it. That is `RenderCheck.cpp`, which is
host-only and never links into `render.dll` (`build.sh:31`), and the rebuild of the shipped tree printed those
same two byte counts (`cache/p63/host27b.log`) -- so the pair above is still the pair, and no redeploy is
implied by the extra legs. The pair -27 replaced is `lib/{x86,x64}/render.dll.20260926-154428.bak`
(160436 / 155704, the -26 build); the pair -26 replaced is `*.20260926-145440.bak` (157227 / 153013, the -25
build), whose
own predecessor is `*.20260926-123418.bak` (the -24 pair). No jar moved in either stamp: -25 and -26 touched the
model, the JNI seam and the two gates, and nothing in `com.hyee.ansirender`'s Java side, so `lib/dbcli.jar` is
still `fe2a4ed01bb7d13c61dbbb202059fd58` (682094). Re-running the host gate after that deployment re-linked
`cache/native-probe/{x86,x64}/render.dll` from **unchanged** sources and moved both hashes (`257dbdef…` /
`92ad2d48…`) at identical sizes and the same stamp -- the ImageBase lesson a third time, and the reason the
sentence below insists on hashing `lib/` rather than trusting a build directory. The
sizes are the evidence that the pair is the pair: the first -24 deployment hashed `1f78169b…`/`729191ce…` at
exactly these byte counts, and a later re-link of a **comment-only** change moved both hashes while moving no
code -- GNU ld randomizes the PE ImageBase, so md5 says "different file", the size says "same program", and
only a re-run of the gate against the new bytes settles it, which is what happened. The pair -24 replaced is
`lib/{x86,x64}/render.dll.20260926-025516.bak` (149087 / 144958, the -23 build), with -22's pair in
`*.20260926-010136.bak` and -21's in `*.20260926-003951.bak`. `lib/dbcli.jar` is `fe2a4ed01bb7d13c61dbbb202059fd58` (682094) — one entry away from
`fc484ac327c2919f0c4e89cd3076424d` (`cache/p63/dbcli.jar.20260926-025811.bak`), the same 132 entries with
`com/hyee/ansirender/NativeRenderer.class` the only one differing (`f57364c9…` → `18c1da7c…`), and the
comparison was made entry by entry rather than on the jar's hash precisely because a whole-file hash cannot
say whether 131 innocent entries moved with it. Before this paragraph was last refreshed the deployed pair
was build `render-2026-09-25-20`: `lib/x86/render.dll`
`71d4203b76a6ef4124decd7697aa3d68` (144506) and `lib/x64/render.dll` `cfa885d0f94e5cb858e29f9fe232179d`
(140907), both printing stamp `render-2026-09-25-20` when read back through the gate they passed; the -19 pair
they replaced is in `lib/{x86,x64}/render.dll.20260925-231054.bak` (`2387f193bc7962f4383bc167670b4108` 137624 / `00eb6c6e1fc5823581d98464fbbec7e4` 133533), and the older
backups `*.20260925-210940.bak` (-18) and `*.20260925-201626.bak` (-17) are still beside them
(`54f4f3298f2c9d083e1e68c508695567` 137113 / `1389617b8729caa6fd02d46fbd11bba9` 132510), verified by hashing the
backups themselves. The -16 pair they replaced is in `cache/deploy-backup-20260925-182905/{x86,x64}/render.dll`
(`175c74b9fb04080aeadbc834a33e8a06` 135572 / `d8b2dfbb421502fb723bf2f9f856cdd7` 130982).
`lib/dbcli.jar` `862c479094d83fffa4dc779c2b95d7f2` (681401, 132 entries — same count as its
predecessor `cf018b732fb04a9cd1ee3231f333158e`, kept at
`cache/task38-deploy-20260925/dbcli.jar.20260925-183508.bak`, with exactly **one** entry differing across the
two: `com/hyee/ansirender/NativeRenderer.class`, which is the census table I32 needed a slot family for), and
`lib/Jline3.jar` `43a57e5733d37eef7eba27a74a3b02a4` (1830721), unchanged since #47's deployment of
`039978bd…` → `43a57e57…` at 16:27 (`lib/*.20260925-162706.bak` holds both). A row that cites an older build
says so, because "the gate is green" and "this task was witnessed against the DLL that ships" are different
claims — the second one is why the -17 live gate above was run with `-Scratch` at a copy of `lib/`, and why
`cache/witness/hprvpr-control-20260925.txt` records a *deployed* green next to a control red.

One caution that only grows: another agent is upgrading this tree toward JLine 4.4.6, so `lib/` must never be
assumed to still hold the bytes a row names. Re-hash before trusting any row below that cites a jar.

The whole table was walked against that pair on 2026-09-25 in the small hours, not merely re-read. Two standing
gates were re-run on both arches, and four live legs were re-taken for the tasks whose claim is behavioural
rather than assertion-shaped: `cache/witness/pager13-20260925-13.txt` (#13, #14), `wide1516-20260925-13.txt`
(#15, #16), `statusbar-live-20260925-13.txt` (#23, and with it #33's two symptoms), and the A/B of #11 in
`live-ab-20260925-13.txt`. The sweep produced no regression and one thing each of the four files had not said
before -- #13's second leg is unreadable, #16's fold-not-trim, #23's jar difference, #11's `0 differing lines` --
and the rows below record those rather than smoothing them out, because a ledger that only repeats the passing
half of a witness is not evidence, it is a summary.

| # | Subject | Where it lives | Proof, and what it printed |
|---|---|---|---|
| 1 | 通读 conemu 现状代码与文档 | no file — the read-through | It is §2.1's layer list and §7's deviation inventory. Not gated, and not re-runnable; every later row presumes it. |
| 2 | OSC 族不再静默：分类计数 + 标题落地全链路收口 | `Render.cpp:1741 osc_start`, `:2449 osc_finish`; `RenderJni.cpp:1102-1115` applies the title with `SetConsoleTitleW` and counts a failure into `lastError` | host `gm_osc`, `gm_osc_family`, `gm_dropped`; live `caseOscTitle` (`"a title is not a rectangle"`, `"an abandoned title"`). -13 census: `titles=3 (1 truncated), 3 applied` (`gate13.txt:413`) — parsed equals applied, which is the whole claim. |
| 3 | 按 MSFT 参照清单完成 S1/S2/S3/S5/S6-S8/B5 | `Render.cpp` `step_back_col` (BS `:1574`, CUB `:1121`), explicit pending-wrap flag, `modelSuspect`, per-row `dirtyLo/dirtyHi` (`Render.h:309`) | host `geo_wrap`, `gm_pending`, `gm_wrap_suspect`, `gm_split_sgr`, `gm_double_esc`, `gm_abandon_and_restart`, `check_resumable`, `plan_damage_range`, `check_damage_bounds`; live `caseWrap`, `caseSuspectAlign`, `caseNarrowRepaint`. In -13 host `3072/0`; the damage bounds print `273 corpus strings x 2 shapes, every damaged row inside a run`. |
| 4 | 退格落宽字形尾格：先用栅格证人裁决 | decided by measurement, then #15 landed it | See #15 — the same question, asked of the grid before the code was touched. |
| 5 | B2（脏列区间）待用户复述 I7 裁决后才能开工 | blocked-on-ruling, no code | Cleaved open by #16's ruling; the interval itself is B2 in #3. |
| 6 | B2 文档收口：DESIGN + MSFT 清单 + 记忆 | §5 cost model, §7, `.dsh/memory/` | Documentation; no gate. |
| 7 | 在模型层实现 alt screen（47/1047/1049） | `Render.cpp alt_screen()` (I24) | host `geo_alt`, `plan_alt`; live `caseAltScreen`; hand witness `cache/wide-probe/alt5.txt` → `ALT: the alt screen kept its rows to itself`, with `history rows above the window: 0 cell(s) differ` and `viewport rows: 0 cell(s) differ`. |
| 8 | 计划与执行侧适配 alt 模式 | `Paint.cpp` plan, `Render.java` | live `caseAltScreen`, `caseManyScreens`; -13 census `altbuf=0` and `alt switches=2 (0 refused)`. |
| 9 | 备用屏门禁（host + JNI 栅格） | `RenderCheck.cpp`, `Render.java` | Both arches at -13: `checks=4648 failures=0` twice (`gate13.txt:414,828`). The -4-era pair is `cache/witness/gate-alt-0004.txt`. |
| 10 | 修正 windows-conemu.caps 的 xenl | `terminal/src/main/resources/org/jline/utils/windows-conemu.caps` | Measured, then **deleted from the entry rather than added to it** — the tracker subject was amended to say so. A/B witness `cache/witness/caps-xenl-ab.txt` (delayed-wrap flips with `xenl` absent). |
| 11 | 完成 xenl 修复的实机 A/B 见证 | the caps entry plus the console | `pwsh cache/jnatest/native-ab.ps1 -Control -BugDir …\scratch-lfbug\out\x86 -BugStamp render-lfbug-2026-09-25-2`, re-run at -13 → `cache/witness/live-ab-20260925-13.txt`: `STAGE0 AB: ok`, and the two pairs read as §6 rule 5 predicts — `off vs on … (0 differing line(s))`, which is *one renderer compared with itself* now that ConEmuHk is off disk, against `on vs bug … (58 differing line(s))` with the control's indent census walking (`n=10 min=49 max=62`) while both deployed legs keep one indent (`n=18 min=4 max=4`). 58 is the ceiling for a 32-body-line dump, not a small number: essentially every visible row differs on both sides. Control dll md5 `df0470dceddc6103cd1c00e39d2be7a3`; deployed pair unchanged across the run. |
| 12 | 审计并补齐 ConEmu infocmp 全部能力 | same caps file | `cache/caps-audit/CapsDump.java`, 81 assertions, driven through `tputs`. -13: `CAPS CHECK: ok` against the source file **and separately against the copy inside `lib/JLine3.jar`** (`caps-audit/caps-13-src.txt`, `caps-13-jar.txt`); the two are byte-identical, so the entry that ships is the entry that was audited. |
| 13 | 修复退出 more 后提示符与命令行不在同一行 | the dbcli pager: `D:\JavaProjects\jline3.29\dbcli\src\org\dbcli\More.java` (not this DLL) | **No `render.dll` gate exists for this row** — the pager's screen decision is made in Java from `OSUtils.IS_CONEMU`. Live witness only: `cache/jnatest/repro-more-exit.ps1`, both legs (`-ConEmu on` / `off`), against the *deployed* `lib/dbcli.jar` `2297d5175ca1b499caed802f828ef53f` → `cache/witness/pager13-20260925-13.txt`. Re-run at -13, and only one leg measures it: **`VERDICT #13: ok` on ceoff** -- after `q` the console cursor is at `(5,6)` with `r05\|SQL>` *and* `r06\|SQL>` in the grid, so the live prompt row is the cursor row, and the `top` typed after it lands painted on `r06` (`4x170`-style census clean, `ESC-IN-GRID=0`, `~=0`, `last text row10`). The **ceon leg reads `FAIL ceon : no prompt row in the window`, and that FAIL is the harness, not the fix**: `ESC-IN-GRID=83` on that leg (ConEmu's own parser leaves the escapes as cells -- see §6 rule 4), so `grid-facts.ps1`'s `^\s*(SQL\|\d+C)>` never matches and `promptRow` comes back -1; read as raw content, prompt and typed text do share `r105`. No conclusion about #13 is available from the leg whose env var is set, which is worth remembering the next time someone quotes a "both legs" number for this row. |
| 14 | 修 More 的 quit-if-one-screen 判据 | same file, `quitIfOneScreen` vs the copied list rather than the argument list | Same as #13: no gate, and the check is behavioural — a file that fits one screen must return to the shell without a keypress. Recorded in the same -13 witness: **`VERDICT #14: ok`** -- a 6-row wide-CJK file printed all six lines with no `:`/`(END)` status row, the screen `settled in 1680ms` rather than timing out, and the *proof nothing was waiting for a key* is the next keystroke: the driver typed a second `more` and the shell ran it, then typed a bare `q` and the second pager consumed it. Control in the same session: a 200-row file holds (`settle TIMEOUT after 40113ms (moved=false)`, 48 rows on screen) and is released only by `q`. The deployed bytecode agrees with the subject: `javap -p -c` on `lib/dbcli.jar` shows `107: aload_2` -- the copied `sources` list, help line prepended at `45:` -- where the 2026-09-23 backup had `aload_1`, which is exactly the argument list whose `size()` can never be 2. |
| 15 | 退格落宽字形尾格：造栅格证人并裁决 | `Render.cpp step_back_col` (:1028), used by CUB (:1121) and by BS (:1574, which moves and does not erase) | host `geo_wrap`'s `wide back attr` and `wide at cols-2 back`, and `geo_surrogates`' `the replacement takes the whole cell pair`; live `caseWideGlyph`. The reader-typed case is `cache/jnatest/leg-bswide.ps1` — four wide glyphs, one backspace, then two, then an ASCII into the space just erased, each step held mid-edit at U+0001 so the grid shows the cursor at that keystroke; re-run at -13 into `cache/witness/wide1516-20260925-13.txt` as **`#15 VERDICT: ok`** -- `cursor=19,7 r07\|O19C> echo 中文测试` → one BS `cursor=17,7 … echo 中文测 ` → two more `cursor=13,7 … echo 中     ` → `X` at `cursor=14,7`, i.e. every backspace took a whole glyph and parked on that glyph's *first* column, and the ASCII filled one freed cell with no half-glyph residue. All four dumps CLEAN; identical to the -12 witness. §7 item 1 keeps the difference against the retired in-process parser gated on purpose, so the "fix" cannot be restored. |
| 16 | 裁决 reader 行宽：缓冲区 2000 列 vs 窗口 125 列 | ruled **buffer width, not narrowed** (I7); `Render.cpp` run handling, `Paint.cpp` erase-to-buffer-width | host `plan_runs`; live `caseWideBuffer`, `caseEraseToBufferWidth`. Re-witnessed at -13 with one identical 170-char line typed into two geometries (`cache/witness/wide1516-20260925-13.txt`, **`#16 VERDICT: ok for the design claim`**): with a 2000-column buffer and a 125-column window it lands as a single row `4x170` at columns 5..174, `r05` empty, no warning block -- the line is as wide as the buffer, and `cols-used=125` says only that far of it is *viewed*. With the window made the buffer (`-Mode 'cols=125 lines=30'`) the same line **folds rather than trims**: `4x120` on `r07` plus 50 characters continuing on `r08`, cursor `(50,8)`, all 170 present -- so Lua's warning text ("default to be trimmed") describes a path this build does not take; the trimming branch was left unhunted by instruction, and the finding is recorded as a finding. Two things this row must not be read as claiming: the cursor at `124,4` in leg A is not a defect but `Paint.cpp:201-224`, which clamps the *parked* column into the window because conhost slides the viewport sideways to include a cursor it is told about (measured 2026-09-23, same comment), while the model keeps the true column; and this A/B is of line width, not of a scroll -- §9's wide-buffer-scroll leg is still owed. |
| 17 | 在模型层实现 DECSTBM 滚动区 | `Render.cpp region()` (I25) | host `geo_region`; live `legsSame("DECSTBM then a scroll", TRUE)` — the assertion that turned a differ into an agree. -13 census `decstbm=0`, i.e. nothing about regions reached the unmodelled counter. |
| 18 | 补齐编辑与模式类序列 | `Render.cpp` editing arms and mode table | host `geo_edit`, `gm_charset`, `gm_argcap`, `gm_echo`; in -13 `3072/0`. |
| 19 | 补齐 REP（CSI b）或记为已知惰性 | `Render.cpp` `b` arm; `rep` in the caps entry | `caps-13-src.txt`/`caps-13-jar.txt` print `rep(0x78,4) -> x<e>[3b` as an advertised capability, not an inert one. |
| 20 | 清点 jline3.29 与 nano 依赖的全部 CSI/OSC | `Render.h` `RC_UN_*` family, §9's nano inventory | host partitions the family (`gm_*`); live `report()` prints the census. -13, identical on both arches: `unrecognised=6 decstbm=0 altbuf=0 mouse=2 mode=0 bracketed paste=0 osc9=1 other osc=2 dcs=1 report=1 colon=1`. Every one of those six is a *counted* sequence, and §9 lists which are deliberately not modelled. |
| 21 | 在模型层实现 OSC 133（FTCS 语义提示符） | `Render.cpp ftcs_apply` (I23) | host `gm_ftcs`, `geo_ftcs`; live `caseSemanticPrompt`. -13 census: `prompts marked=2, last 133;D`. |
| 22 | 按主干重建两条控制腿并跑 -Control | `cache/scratch-lfbug/make-control.sh`, `cache/scratch-elbug/make-control.sh` | Both rebuilt from the -13 trunk with exactly one stamp line swapped, and **both must fail** — that is the certificate. `cache/gate13/control-lf2.log`: `render-2026-09-25-13 → render-lfbug-2026-09-25-2`, `checks=3068 fails=4`, `RENDERCHECK: FAILED`. `cache/gate13/control-el.log` and `control-el2.log`: `checks=3084 fails=11`, `RENDERCHECK: FAILED`. The totals differ from trunk's `3072` for the reason §6 rule 3 gives — read a control's `fails`, never its totals, because the damage-bounds check votes twice on an empty plan — and what certifies each leg is its fail *list*, which is exactly the set of assertions that pin the reverted fix. |
| 23 | 实现 Status bar | `Render.cpp` region + DECSC/DECRC handling, `RenderCheck.cpp status_bar` | host `status_bar` pins three things: the caller's cursor never lands in a status row, ordinary output rotates the region without touching those rows, and `csr` and `CSI r` are different writes. All three live legs re-run at -13 → `cache/witness/statusbar-live-20260925-13.txt`: **`VERDICT A/B/C: ok`**, and every row number matches the -6 record it replaces -- A bar-then-output puts the border/title on 47/48 with 49 text rows; B opening the bar *over a finished `help`* moves the window by exactly the two rows the bar holds (35..83 → 36..84) with the listing still on its rows and 0 rows empty, which is the erasure gone; C closing leaves 47/48 blank with the prompt unmoved at 46, `47 text rows + 2 empty` being the correct end state and not a shortfall (a close deliberately does not redraw the freed rows -- §9's status-bar item). All dumps CLEAN (`ESC-IN-GRID=0`). Two caveats the file itself states and this row inherits: `settle TIMEOUT (moved=false)` landed on different steps than on -6, which is the sampling race memory §43 records and carries no information about the fix; and the jar under these legs is `2297d517…` where -6 pinned `0ea9b33c…`, so the two files agree on *shape*, not on Java behaviour. |
| 24 | 把 chunk 渲染策略整体下沉到 C | `RenderJni.cpp render()` — one entry (I5) | `build.sh`'s `gate_dll` asserts the whole export table of each `render.dll`, and the assertion is the gate: at -13 both bitnesses print `render all 19 JNI entrypoints exported OK` (12 `Java_com_hyee_ansirender_NativeRenderer_*` production methods plus the 7 `Java_Render_*` the harness needs), and `no @-decorated JNI exports OK`, which is what `--kill-at` buys and what HotSpot's plain-name lookup requires. It was 16 at build -6; the three added are the reply/census legs. |
| 25 | Java 侧瘦成一次 JNI 调用，并彻底去除 ConEmuHk 依赖 | `com.hyee.ansirender.NativeRenderer`, `Render.java`, `run.ps1` | `STAGE0 RUN: ok` on both arches at -13. The retirement is visible inside the gate's own output: `both-leg A/B skipped: no D:\dbcli\lib\x86\ConEmuHk.dll` (`gate13.txt:3`, and line 417 for x64) — the comparison the old harness ran can no longer be taken, because the other painter is gone from disk. |
| 26 | 用英文重写 DESIGN.md | this file | English contract, §1–§10. Draft history under `cache/design-en/`. |
| 27 | 把 ambiguous 码位改为按宽字符建模 | `ansi_width_tables.h`, `AMBIGUOUS_NARROW` | host `check_widths`; §7 records the cross-check against xterm (`7,117` agree, `207` differ, corpus in `cache/ambiguous/xterm/`) and the 47,766 writes this ruling covers. |
| 28 | 渲染器 Java 迁到 com.hyee.ansirender | package rename + `RenderJni.cpp` symbols | `build.sh`'s `gate_dll` (the whitelist it is given) asserts the mangled names, so a half-moved tree cannot link; since -24 `gate_declared` additionally derives them from the `native` declarations in `Render.java` and `NativeRenderer.java`, which is the half that catches a whitelist copied with a wrong name in it. |
| 29 | 补 DSR/DA 应答腿 + 修 reader 鼠标路径空指针 | `Render.cpp flush_reports` (I29); `LineReaderImpl` mouse path in the jline fork | host `gm_reports`; live `caseReports` (`eqInput`, which reads the reply back off the input stream). -13 census: `replies written=15 (0 failed, 1 refused for a full queue)`, and `mouse=2` counted but not modelled. `u6`/`u7` are advertised in the caps entry (see #12). |
| 30 | 把清点落进 RcUnsupported 计数与 caps | `Render.h` counters; the caps entry | The live gate asserts the counters *as the stream is fed*, so `228: ok the CSI p family and ESC ) c are counted  unrecognised=3` at -13 (`gate13.txt:228`) is a mid-session number with a cause, and the same counter read after the session prints `6` in the census line — one number per decision, and each is checkable against the sequence that earned it. `caseSuspectAlign` is the leg that watches the delta. |
| 31 | 删除已退役的 ConEmuHk 双 DLL | `lib/{x86,x64}`, `copy_to_git.bat` | Backup-then-delete with a manifest: `cache/hk-retire-20260924-183238/MANIFEST.txt` holds both md5s. The consequence for this document is #25's line about the both-leg A/B. |
| 32 | 处置过期的 D:\dbcli\src\java 镜像 | `src\java`, `build-jar.ps1` | Compared first, then archived: `cache/java-mirror-retire-20260924-183622/MANIFEST.txt` and a `tar.gz` at md5 `cf5dca7d…`. §9 records what reading `copy_to_git.bat` corrected. |
| 33 | 定性 Status bar 的两条实机观察 | `Render.cpp line_down` | Both symptoms were ours, not the host's: MSFT's `_DoLineFeed` (`adaptDispatch.cpp:2443-2453`) scrolls only at `y == bottomMargin`. Pinned in `status_bar` on a second grid that asserts `nScrolls == 0` alongside the row contents and the final cursor row, because "no scroll" is the half a correct-looking grid still gets wrong. Live: #23's -13 legs. |
| 34 | 修启动/退出时破坏终端原有文本：全角字重复显示 | `Render.cpp` adopt/align (I4) | `cache/wide-probe/StartupRepro.java` + `su-cmp.py`, four legs at -13: `su13-fit-{raw,render}.txt` and `su13-fill-{raw,render}.txt` all print `verdict: ok  nothing cut, nothing repeated, no hole`, with the raw and render legs reporting the same census (`100 row(s) differ … duplicate pairs 0` at the fit shape, `399` at the fill shape) — the raw leg is the oracle and the render leg does not diverge from it. The in-gate half is `caseRealign` and `caseSuspectAlign` (I4), and the raw-vs-render oracle above is the same one I31 cites. |
| 35 | 修用户上翻时把输出写进 scrollback | `Paint.cpp` — `row0` is never derived from the window top (I30) | host `plan_scroll_band`; live `caseScrollKeepsHistory`. Hand witness at -13, two shapes: `cache/wide-probe/scroll6-room.txt` → `the scrollback the user is reading is untouched (0 rows changed)`; `scroll6-full.txt` → `rode up by exactly 1 row(s), in order (340 rows changed, 0 of them out of place)`. Both `exit=0`. |
| 36 | 让 resize 保住锚点（conhost 的 straddle 规则） | `rc_anchor_adopt` (I28) in `Render.cpp`; `Paint.cpp` refusal | host `adopt_anchor` and `plan_anchor` (`straddle:`); live resize legs through the gate-only `readopt()`. -13, both arches: `ok the resize rebuilt this handle's model, and only its model`, then `resize at winT=0: anchor carried to row 77 of 400, 41 scrollback rows intact` (`gate13.txt:319,332` and `:733,746`). |
| 37 | 在 Windows Terminal 内复现并 A/B 归因 | the classification, not the painter: `WinSysTerminal.createTerminal` | A matrix, one real window per cell, every cell carrying the user's own `ANSICON_DEF=conemu` (`cache/wt-classify-20260925/matrix.cmd` + `run-matrix.ps1`, reports `rep-mx-*.txt`): real WT with the deployed jar reads `TYPE=windows-conemu` and `ENGAGED` -- the bug, reproduced on screen, not argued -- while real WT with the fixed tree reads `TYPE=windows-vtp` and `off`; clearing `WT_SESSION` changes neither cell; real conhost reads `ENGAGED` on both jars, which is the no-regression half. The criterion is `GetClassNameW(GetConsoleWindow())` yielding `PseudoConsoleWindow` or `ConsoleWindowClass`, chosen over the two candidates that look equivalent and are not: `WT_SESSION` is inherited by an ordinary conhost window opened *from* a WT session, and VTP is already on in both hosts (`mode=0x7 vtp=on settable=yes`), so neither separates them. A forged `WT_SESSION` still deceives the jar and does not deceive the fix. |
| 38 | 权威树 WinSysTerminal 的终端分类优先级 | `D:\JavaProjects\jline3.29\dbcli\src\org\dbcli\WinSysTerminal.java:88-109` (ConPTY branch first, `ANSICON_DEF` below it, and `enableVtp` deliberately not called there) | Deployed identity, proved by a whole-tree compile rather than by a file count: `cache/task38-deploy-20260925/build.sh` builds all 57 sources into 112 classes and `census.py` puts **108 of 112 byte-identical to `lib/dbcli.jar`**, the four exceptions being this session's own edits (`Console` family, `NativeRenderer`) whose `javap -p -c` output is identical to the jar's, i.e. differing only in `-g` tables. The jar's `WinSysTerminal.class` is 17087 bytes and holds the `pseudoConsole` reference; the 2026-09-24 backup's is 16459 bytes and does not. Behaviour from the jar alone (no shadowing class on the classpath): `cache/status-top-20260925/rep-wt-real-sOn-kOn.txt` reads `TYPE=windows-vtp … ANSICON_DEF=conemu WT_SESSION=90b2d021…` with `windowclass=PseudoConsoleWindow` in the same window's `win-*.txt`. Line endings are per-file and were preserved per-file -- 571/571 CRLF in `WinSysTerminal.java`, 1106/1106 LF in `Console.java` -- measured with a byte census, because `file` reports a CRLF Java file as plain ASCII text. |
| 39 | 给渲染器补上 snap-on-input（原生 + Java 两腿） | `RenderJni.cpp snap` (build -15) → `NativeRenderer.snapOnInput()` → `ConEmuWriter:69` → `WinSysTerminal:453`, one call per keystroke | Three separate legs, because "the symbol exists", "the screen follows" and "a keystroke still delivers a key" are three claims. Exports: build -15 exports exactly the 14 natives the jar declares, and a reflection walk over every `native` method of `NativeRenderer` with zero arguments reports `BIND: 12 declared natives, 0 unresolved`. The pump: `err-classic-real-sOn-kOn.txt` went 593 bytes → 0, the 593 being an `UnsatisfiedLinkError` on `snap(J)I` thrown inside `AbstractWindowsTerminal.pump` -- the thread that hands keys to the reader, so the "cosmetic" alignment call was killing input. The guard, with an arm that must fail: `cache/render-deploy-20260925/arm-{control,guarded,current}.txt` -- unpatched class against a build -13 dll throws, patched class against **the same** build -13 dll survives three keystrokes, patched class against build -15 survives three. JNI resolves by symbol per call, so a jar newer than its dll loads happily and detonates at the call site; whoever can detect the skew absorbs it, which is why the `UnsatisfiedLinkError` is caught in the library and not in dbcli. |
| 40 | 诊断并修复 Status 开启后 top 的残留带 | `dbcli/src/org/dbcli/Console.java:344-377` (pad the frame to `getScreenHeight()` with real spaces) plus `blankRowOf` | A band of stale text survived every frame of the dashboard, but only on the terminal type that does *not* use this renderer: `isBlockPaintEnabled()` is false for `windows-vtp`, so those rows belong to JLine's `Display.update()` diff, which writes `min(rows, max(oldLines, newLines))` rows and sends **nothing** to a row that appears in neither list. `display(String[])` handed it 8 rows while `getScreenHeight()` claimed 28 (`titles` keeps its two rows after the bar suspends), and the row the bar had scrolled up when it drew itself stayed forever. Witness: `run-probe.ps1` legs read the grid in-process after every frame; the deployed jar on real WT went 15 of 17 frames stale → 0 (the two remaining `STALE` lines are the pre-dashboard filler frames, where nothing has been painted yet), and the four classic legs were clean before and after -- which is the whole reason the fix is in Java: render.dll already clears every row it paints, so it cannot be the thing that leaves a band. `AttributedString.NEWLINE` must not be used as the pad; Display's own sentinel diffs empty-against-empty on the first frame and emits nothing. |
| 41 | 复现并定位人为调整窗口大小后的内容错位 | `terminal/.../utils/Status.java` (`resize(Size)`, `hide()`, `redraw(boolean)`) + `reader/.../impl/LineReaderImpl.java` (`prevWindow`, `doDisplay()`, the `WINCH` branch of `handleSignal`) + `dbcli/src/org/dbcli/Console.java` (`handleResize`, the ctor seed) | Two quantities had been conflated: `terminal.getSize()` is the *window* and `terminal.getBufferSize()` is the *buffer* (2000x9001 on this user's classic consoles), and dragging a window edge moves only the former -- so every handler that gated on the buffer compared a number that never changes and no-oped after the first resize, leaving the bar at the bottom of the window as it was *then*. Three handlers own `WINCH` in turn and all three needed it: `LineReaderImpl.handleSignal` while `readLine()` holds the terminal (:681 installs, :810 restores -- i.e. the one that runs at `SQL>`), `More.handle` while paging (More.java:400/:707), `Console.handleResize` otherwise. `Status.resize()` now moves a *showing* bar to the new bottom instead of losing it, which required `hide()` to stop discarding the lines it erases (three callers then had nothing to redraw) and `redraw(true)` to treat an empty model as "no bar" rather than "a bar of zero rows" -- `Console.readLine()`'s `finally` calls it for sessions that never showed one. Deployed as a byte census, not a rebuilt jar: `cache/resize-fix-20260925/{build,stage-jars,verify-swap}` compiles the whole terminal+reader tree, proves 183 classes match `lib/Jline3.jar` except the 13 edited ones, and asserts every swapped entry belongs to an edited file; `lib/Jline3.jar 712c5e9a…`, `lib/dbcli.jar 8de8200a…`, pre-fix pair in `*.20260925-121918.bak`. Five real-window arms (WT shrink, two-step resize, one-row resize, classic shrink, no-resize control): the bar is present and on the last row in all five, where pre-fix it was *absent* after any shrink. |
| 42 | 归因 WT 放大时旧内容被重排成 20 列阶梯 —— 结案：探针读取 conhost shadow buffer 的假象 | not in this product at all: `F:/tools/conpty/conpty_probe.py`'s window-leg resize path (`window.py`), and the criterion page `.dsh/memory/reference/reference-wt-geometry-witness.md` | **Closed by invalidating a witness, not by changing a paint.** One fixture, two resize paths, each taken twice: the probe's legacy `SetConsoleScreenBufferSize`+`SetConsoleWindowInfo` reads back the staircase (100→120, −20 columns per row) while `PrintWindow` shows the actual window **entirely blank** (`distinct=1`); UIAutomation `TransformPattern.Resize` renders cleanly and reads back **the same staircase** (100→145, −45 per row). ⇒ inside a WT session `ReadConsoleOutputW` reads conhost's **shadow buffer**, not what WT drew, and the user never saw a staircase. The arithmetic closes it: label *n* at linear offset `n*100+8`, recut at pitch 120, gives `8,108,88,68,48,28,8,108…` — matching cell for cell, including two labels sharing a row — and the CSV carries no wrap or rendition bit anywhere. Collateral: §49's "only reproduces with dbcli present" matrix is voided **whole**, because every cell of it read the shadow buffer, and `c-ren0` equalling `c-ren1` no longer means "renderer-independent" — neither leg was reading a renderer. Landed alongside the verdict: one script vocabulary for both legs (`resize`/`capture`/`every`/`resize_after`/`fire_at`), resize+capture on the ConPTY leg, an automatic `WT_RESIZE_NOTE` on the wt leg, `selftest --leg both` at 16/16, and the witness scripts `pw-shot.ps1` (`printed= distinct= off-mode=`; **a uniform pixel field means the capture failed, not that the screen is blank**) and `uia-resize.ps1` (dragging the window corner silently no-ops on WT; only UIA is a qualified resize witness). The genuine defect that was hiding behind this one became #47. **Standing consequence for every row below**: a wt-leg geometry claim is not evidence until a `pw-shot` agrees with it. |
| 43 | 修复"关 status bar 后 resize 把整屏清成一行提示符" | `terminal/.../utils/Status.java:183-197` (`reset()`), `:175-177` (the `scrollRegion` hand-back when hided), `close()` = `hide()` + `reset()` | Mechanism found and removed, **and the row stops there honestly**. The named cause was two-part: a bar torn down left a scroll region behind, and every WINCH handler opens with `carriage_return` + `clr_eos` — an erase that runs from the *current* cursor, so a cursor parked on row 1 makes it a clear-screen. The region residue was itself a compiler artifact: `csr` is `\E[%i%p1%d;%p2%dr`, so `puts(change_scroll_region, 0, 0)` -- which reads like "reset" -- emits `\E[1;1r`, **a region one row tall**, the opposite of undoing anything. `reset()` now writes `CSI r` with no parameters, the only spelling every terminal in scope takes as a reset, and `More.init()`'s second fuse (it closes the bar, and `close()` now resets) is covered by the same line. **What is NOT claimed:** no leg has been re-taken since this `Status.java` landed (16:19). The only measurement on record is from 14:xx, against the `*.20260925-121918.bak` pair swapped into `lib` and restored with md5s re-checked, where pre-fix and post-fix behaved *identically* -- and that leg drove the resize through the probe's legacy path, which #42 voided, so it is now evidence about nothing. Re-take the leg (`set status off`, then a UIAutomation resize, read cells) before quoting this row as "fixed". |
| 44 | 修复"部分失败的 paint 谎报成功"（§9 第一项） | `RenderJni.cpp` -- the `paintUndone` watch through the run loop, `rc_paint_done(g); if (paintUndone) rc_drop_base(g);` at the flush tail, and the previously-ignored returns of `SetConsoleTextAttribute` / `SetConsoleCursorInfo`; gate-only injector `Java_Render_faultRect(h, run)` (`RcHandle::faultRun`, one-shot, self-disarming, in `build.sh`'s export whitelist) | §9's first bullet is the story; this row is the receipt. `casePartialPaintFailure` builds one plan with two runs, refuses the second, and asserts four things at once: `apiErrors` +1, `runs == 2`, the landed FIRST on screen, the refused SECOND **not** on screen -- then paints one unrelated character and asserts SECOND came back by itself, which is the whole claim. Red arm `control-probe-44` reverts the single line `if (paintUndone) rc_drop_base(g)` and keeps #49's gate: `checks=4723 failures=6` on each arch, all six in "SECOND didn't come back", everything else green. Shipped in the -16 batch: `lib/x86` `c8f667b8…`→`175c74b9…` (135016→135572), `lib/x64` `f092c984…`→`d8b2dfbb…` (130942→130982), backups `*.20260925-170640.bak`; the stamp read back out of the deployed bytes is `render-2026-09-25-16` and `cmp`s clean against the staged build that passed the gate, and `run.ps1` was then pointed at **copies of the deployed bytes** and re-run: `checks=4723 failures=0` per bitness. |
| 45 | 把 #38 的 WinSysTerminal 分类修复真正发布，并补 ConEmu 窗口证据 | `D:\JavaProjects\jline3.29\dbcli\src\org\dbcli\WinSysTerminal.java:88-109`, and the two jars | **Open.** #38 proved the shipped *bytes* carry the fix (census: 108 of 112 classes identical, `WinSysTerminal.class` 17087 bytes holding the `pseudoConsole` reference where the 2026-09-24 backup is 16459 and does not) and #37 proved the *behaviour* in two hosts. What is missing is the third: `NativeWinSysTerminal` also answers `windows-conemu` when `ConEmuPID` is set, and no real ConEmu window has ever been measured -- it is inferred from WT and conhost, which is the honest-gap note this row inherits. Also still owed: one window per host taken against the jar that ships *today*, since #47/#48 moved both jars twice since #37's matrix. |
| 46 | 用 Status.size() 取代 Console.getScreenHeight() 的 titles.size() 代理 | `dbcli/src/org/dbcli/Console.java:636-655` -- `getScreenHeight()` = `terminal.getHeight() - barRows()`, `barRows()` returning `Status.size()` and 0 for a closed, hided or suspended bar | The proxy counted `titles`, which is a list dbcli maintains and the bar does not; `Status.size()` is `lines.size() + border`, the number of rows actually reserved. The case that makes the difference visible is `set status off`: nothing is drawn and `titles` keeps both entries, so the proxy claimed two rows of bar that were not there and every frame was laid out two rows short (#40's band). `Console.java:639`'s own javadoc records that. No gate of its own -- the row's witness is #47's live pair, which is also why it is listed separately: #47 moved the border *out* of `titles`, so after it the proxy would have said 1 against a bar of 2 and looked plausible. |
| 47 | 修 status bar 分隔条不跟随 resize —— 结案：分隔条是几何，已交还给 Status.setBorder 模板 | `terminal/.../utils/Status.java:127-151` (`DEFAULT_BORDER`, `setBorder(AttributedString,int)`, `getBorderString(columns)` tiling to `columns + overflow`, cache keyed on `columnLength()` not `length()`) + `Console.setStatus` (template call, `titles` reduced to one row, `prevWidth` and its guard deleted) | Third root cause; the first two are recorded and voided ("Windows never raises WINCH", and "the flush fast path reused `prevWidth`", which was a real but secondary half). The actual fault: **the separator is geometry and dbcli was minting it as text** -- `Console.setStatus` built a fresh run of `-` at `getScreenWidth()-1` and pushed it into `titles`, `resize()` dutifully re-sent the stored content, and `update()` pads any short line with spaces, so a 99-dash rule on a 145-column screen *looked* full-width to every layer downstream. Nothing below that point could repair it, and `LineReaderImpl.handleSignal` was already calling `status.resize()` while parked -- it was only drawing stale content more often. Hence the fix is in the library, tiling a template per draw, same shape as the library's own `getBorderString`. Live witness, classic console leg (`--host auto`, idle frames), `cache/status47-48-20260925/{leg47c.json,bar-rule.py}`: red `h-after-00/01 cols=145 rows=34 rule at row 33 dashes=99 want=144 STALE` -- and `h-help-00` reaching `144 match` only *after* a statement, which is exactly "a new setStatus rescues it" -- against green `i-after-00/01/02 dashes=144 want=144 match` with one rule row on screen (32 rule / 33 status text / 31 prompt), no double, no residue. Unit: `StatusTest.customBorderIsRetiledToTheNewWidthOnResize` + `templateBorderFollowsSetBorderOff`, 6/6 via `run-test.sh`. **Deployed as a pair, and it must stay a pair**: `Jline3.jar 039978bd…`→`43a57e57…`, `dbcli.jar 58f83056…`→`cf018b73…`, backups `lib/*.20260925-162706.bak`, CRC census showing only Status(+inners)/Console(+MyParser) moved and the entry counts unchanged at 746/112 -- because the new `Console` calls a method the old `Status` does not have. |
| 48 | 修 Status 带 border 画法下 `hided` 永不复位 —— resize 拒绝重画且错误交还滚动区 | `terminal/.../utils/Status.java:258-269` -- `hided = false` moved out of the borderless `else if` and into the branch that draws, so the border is then added inside it | Same seam as #47, different disease, and it is a *library* defect: `resize(Size)` reads `hided` twice (:168 as the repaint gate, :175 as the condition for handing the bar's reserved rows back to the text area), and only the borderless branch ever cleared it. A bordered update therefore left the flag set, so the next resize did both jobs wrong at once -- bar frozen at the old geometry **and** its rows inside the scroll region. Found in the wild by `cache/winch-47-20260925/BarNoReader.java` (pure JLine, `setBorder(true)`, `SIG_DFL`): `WITNESS supported=true hided=true closed=false` immediately after `st.update(...)`, then 100x30→145x34 froze a 100-column rule on row 29 forever. dbcli never calls `setBorder(true)` (`grep setBorder dbcli/src` is empty), so this is **not** #47's user-visible cause -- it is the invariant "a bar follows the geometry" made true inside the library, which is the doctrine's own case for fixing it there. **Witness, and its limit:** `StatusTest` 6/6 against the source tree, and a red arm taken for this row -- `/tmp` copy of `Status.java` with *only* the `hided` block reverted to the pre-fix shape, compiled, put first on the classpath: `tests=6 succeeded=4 failed=2`, the two failures being `borderedBarIsRedrawnByResize` and `customBorderIsRetiledToTheNewWidthOnResize`. That one revert reproduces #47's *and* #48's symptoms, which is the strongest statement available that they are one fault line. What is not taken: a post-fix live `BarNoReader` re-run -- every file in `cache/winch-47-20260925/` predates the 16:19 edit -- so the screen-level claim rests on the unit bytes, not on a grid. |
| 49 | ANSI_TODO P0：`CSI ?u` 加 priv 门（探测批把光标瞬移到 DECSC 位置） | `Render.cpp case 'u'`: `if (g->priv) { ignored(g, RC_UN_MODE); break; }`, with the comment saying this is a **deliberate deviation from ConEmu** (`Ansi.cpp:4194` restores unconditionally) and citing WT/ghostty, which route a private marker to the query/ignore arm | The probe batch jline4 sends starts `\E[?u`, and an unconditional DECRC teleports the cursor to wherever DECSC last pointed -- mid-frame, before anything is painted. `CSI ?s` is deliberately *not* gated for symmetry, and the reason is in the comment: storing a position is invisible, it is the *restore* half that moves. Host: ten assertions in `RenderCheck` (`?u` moves neither row nor column, costs one `RC_UN_MODE` vote, and does not set `modelSuspect`; a bare `CSI u` still restores and now costs nothing). Live: `caseReports` replays the real batch `\e[?u\e[?2026$p\e[?2027$p\e[?2048$p\e[c` and asserts cursor `(11,7)→(11,7)`, one mode vote, the DA1 reply still present (matched with `contains` then, deliberately, to leave #51 room; #51 landed as an exact-byte demand on the whole reply sequence instead), and a following bare `CSI u` back at `(4,2)`. Red arms both sides: `cache/ansi-2026-20260925/red-arm.sh` (trunk `Render.h`, `/tmp` `Render.cpp` with the gate removed) → `checks=3118 fails=4`, the four being exactly the new ones; `control-probe-49` → `failures=2` per arch, exactly the two live legs. Baseline numbers taken here for the first time and worth keeping: `sizeof(RcGrid) = 4200816`, with `cursorVisible@4197728`, `alt@4196637`, `priv@4197740`, `interim@4197820` -- the offsets a new field would move. |
| 50 | ANSI_TODO P1：DECSET 2026 同步输出（含超时），治好全屏重绘闪烁 | `Render.h` `g->sync` + the six `nSync*` counters + `RC_SYNC_TIMEOUT_MS`; `RenderJni.cpp`'s hold block in `paint_flush` and `RcHandle::syncSince/syncHolding`; the design is **I32** | jline4 wraps every full-screen update in `CSI ?2026h/l` (`Display.java:134-135`, `:495`, `:846`) and this build used to count it as `RC_UN_MODE` and drop it, so full-screen tables and the status bar still arrived chunk by chunk. I32 is the contract; what belongs in a ledger is how it was found to be broken. **The gate caught a real defect on the way**: the region's *first* held flush only started the clock and then fell through and painted -- so the frame an application writes together with its BSU (which is the normal shape: BSU plus the top of the new screen) went up over the old frame, and the flicker this task exists to kill survived precisely the one chunk where it matters most. Live run 3 read `5182/10` with every hold leg red and `flush=3` on region chunk 1; the fix is one branch, and the eight holds the census now reports are the eight that had been painted. Second thing the gate changed: **the clock's meaning, not its value.** A tempting refactor -- re-arm `syncSince` on each held flush -- was evaluated against MSFT's source and rejected: `renderer.cpp:540-570` bounds *region age* with `timeout - elapsed` and then clears the mode unconditionally, and `:517-537` keeps a deliberate ~10 FPS floor against BSU spam; a silence detector would let an in-place, never-ending region freeze the screen forever, i.e. would delete the DoS floor on purpose. So 100 ms stands, and the leg that "failed" was rewritten to stop testing machine latency: `chunkCostMs()` measures the gate's own cheapest paint and the leg asks for however many holds fit inside the clock (`nhold`). Third: the two escape hatches are deliberately *different* -- an expired clock paints and clears the mode, a full scrollback gutter paints and **keeps** the region open, because `scroll_up` asks for the paint at the last moment the rows about to be evicted still exist on screen and a "not yet" there would drop user history. `caseSyncOutput` and `caseSyncOverflow` pin that, and the overflow leg counts mode-open states per chunk rather than inferring them from paint counts. Census at -17: `sync updates=5 (1 nested, 8 flushes held, ended early by 1 timeout / 1 gutter / 0 decline)`. |
| 51 | ANSI_TODO P1：DECRQM/DECRPM 应答（让 jline4 的探测拿到真答案） | `Render.cpp` (`mode_status`, the `p` case in `csi_dispatch`, `interim_is`), `Render.h` (`RC_REP_DECRPM`, `RcReportItem.mode/.status`), `RenderJni.cpp` (`reply_text`'s DECRPM arm, `flush_reports`) | Landed on #59's interim set. `CSI ? <mode> $ p` answers `CSI ? <mode> ; <status> $ y` for the three state bits this struct actually holds -- 25 `cursorVisible`, 47/1047/1049 `alt` (one bit behind three spellings, so they cannot disagree with each other or with the DECSET that moved them), 2026 `sync` -- and with only two statuses, 1 and 2. Three proposals from WORK_ORDER T4, three verdicts. **Adopted:** the queue entry grew `mode`/`status` because the answer belongs to the moment the request was read, not to the end of the chunk; the host gate proves that in one write (`?2026h ?2026$p ?2026l` replies 2). **Not built:** T4's `RcModeDef` get/set table replacing the `h`/`l` arm -- the query side needs a six-line switch, and rewriting setter semantics behind a table nobody else reads would have moved risk without moving a defect. **Adopted with one id refused:** "25/1048 -> `cursorVisible`" -- 1048 is out, because xterm lists it as "alternating cursor position" and that is exactly what this file implements (`?1048h` saves, `?1048l` restores): an event, not a state a reply could report, while a caller asking about the cursor means 25. **Reversed after reading the asker's parser:** T4's "2027 and 2048 answer 4". VT500's 4 is *permanently set*; jline4's own doc has 4 as *permanently reset* and 3 the other way (`AbstractTerminal.java:663-667`) and treats 1/2/3 as SUPPORTED (:685) -- so the byte means opposite things to the two readers and whichever permanent number is sent, one of them is lied to. 2048 is the dangerous case: "permanently set" claims window sizes arrive in the data stream, and a program that believes it never sends `?2048h` and never gets a notification, which is #52's lesson about a number read as a capability claim wearing a new sequence. Silence costs nothing with this asker: `parseDecrpm` looks each reply up **by mode number** (:675-690) and returns NOT_SUPPORTED for a reply it cannot find just as it does for a 4, so an unanswered id shifts nothing. (The premise this feature was drafted on -- and the live leg first written to -- was a *positional* fence, which is wrong; caught by reading the parser before anything was deployed, and the ids now vote `RC_UN_MODE` like their `h`/`l` siblings, joining the `CSI ? 6 n` ruling: answer what the model can prove, count what it cannot.) No new census slot: replies were already counted by `nReportOk/Fail/Full`, which is why the three-sided `RenderJni.cpp`/`Render.java`/`NativeRenderer.java` stats layout was never touched. Gates: host `checks=3318 fails=0` (the 2027/2048 assertions moved from "answers 4" to "answers nothing plus two MODE votes", and a FIFO witness over three stateful ids replaced the one that used them); live `checks=5188 failures=0` on both architectures, where `caseReports` now demands the batch's exact bytes -- `\e[?2026;<st>$y` then the DA1 fence -- and three refused-mode votes for `?u`/2027/2048. Ships together with #59, which it depended on. |
| 52 | ANSI_TODO P2：SIXEL 误报（DA1 的 `;4` **就是** sixel，不是 132 列） | `Render.cpp`'s DA1 arm (the comment), `ANSI_TODO.md` §5, jline4's `AbstractWindowsTerminal`, `cache/p52/jline4-sixel-report.md` | **The reply is unchanged and cannot change; the mechanism in this row's own title was wrong and is the reason it stayed open.** `4` in a DA1 is Sixel Graphics per Microsoft's own list (`adaptDispatch.cpp:1441`, and that clone really has a `SixelParser` behind it) -- not the VT100 132-column bit, which is what this row was written believing; the correction came from reading the reference terminal rather than the VT100 manual. So the hazard is real and it is ours to describe: `render.dll` drops every DCS payload (`RC_UN_DCS`), meaning a sixel stream sent here vanishes silently, while the identity string this library answers says the terminal draws graphics. Retracting the bit in the reply is not available, because a declined chunk goes to the console unparsed and conhost answers *that* one, and deviation 8 exists precisely so one session does not present two terminals -- `caseReports` pins the bytes. The veto therefore sits where a claim can be refused without falsifying a byte: the consumer. jline4's family layer now returns false for `Mode.SIXEL` whatever DA1 said (ANSI_TODO §5, `cache/jline4-sixel-fix/`), `SixelGraphics` never emits the payload, `setSixelSupportOverride` stays as the escape hatch, and asking about SIXEL alone no longer triggers the probe batch -- which is also the `CSI ?u` exposure (#49) reached from the other side. **Still open, and it is not a code task:** the upstream report. Filing it is a public action against someone else's repository, so it is left for a human; the text, the three-host evidence (old inbox conhost claims the bit and draws nothing, `render.dll` claims it and drops the DCS, current conhost/WT really draw) and the suggested family-level refusal are in `cache/p52/jline4-sixel-report.md`. No stamp: the change here is a comment plus documents, and the rebuilt `render.dll` hashes identical to the deployed -23 pair, which is the control that says so. |
| 53 | ANSI 特性前置：确认 render.dll 构建与门禁基线，再动 C 代码 | `cache/ansi-2026-20260925/`, and the numbers below | Satisfied for #49 and #50, which is what it was raised for: build entry confirmed re-runnable (WSL MinGW-w64, `CC_HOST=$(command -v clang++ \|\| command -v g++) bash build.sh`, and a plain `cd /mnt/d/...` from Git Bash will not find it), baseline host count recorded before the change (`3072` at -13 → `3118` at -16 → `3222` at -17), `sizeof(RcGrid) = 4200816` with the four field offsets a new member would move recorded in #49, the timeout value decided against primary sources rather than by feel (#50's citations), and the census transport confirmed: `STAT_*` indices out of `RenderJni.cpp stats()`, positional into `Render.java S_*` and `NativeRenderer SLOT_*`, with `SLOT_UNSUPPORTED=17` through `SLOT_LAST=46` today. The item it named as still open -- the interim marker's single slot -- became a set in #59, which is what let #51 be written. |
| 54 | DESIGN.md：同步台账与 DECSET 2026 设计段 | this file, and `JLINE_CHANGES.md` | This row is its own proof. Landed: I32 and I33 in §3; §6's fresh paragraphs for -16 and -17; §9's first bullet rewritten from "deliberately not patched yet" to closed; §10's rows #42-#58; the two stale statements at the table tail corrected; and the standing gate numbers moved to host `3222` / live `5188` with the artifact hashes of the deployed -17 pair. New file: **`JLINE_CHANGES.md`** (same directory), which is now where every edit to `D:\JavaProjects\jline3.29` outside `dbcli/` and the renderer is accounted for -- what changed, why, and the question that has to be answered first: *could render.dll have absorbed this instead?* |
| 55 | ANSI_TODO P2：OSC 4/10/11 调色板（真改 16 色表 + 模型 RgbMap 同步） | `Render.cpp` (`color_spec_of`, `palette_set`, `palette_osc`, the arm in `osc_finish`, `attr_to_index`, `rc_attr`'s grid parameter), `Render.h` (`palette[256]`, `pal16[16]`, `palTouched`, `defAttrSeed`, `RC_REP_OSC`), `RenderJni.cpp` (`apply_palette`, the reply arm, the gate-only `consolePalette`), `vendor/ConEmuColors3.h` (the memo guard), `RenderCheck.cpp` (`gm_palette`), `Render.java` (`casePalette`) | Landed as build -20, and the reason it is a *feature* rather than a parser exercise is the user's ruling that ConEmu is a parity oracle only: it parses these and does nothing, so the grammar came from MSFT (`OutputStateMachineEngine.cpp:779-866`, `:955-1000`, `:1062-1092`; `adaptDispatch.cpp:3312-3430` for the reply forms), and the accepted specs are `#RGB`/`#RRGGBB`/`#RRRRGGGGBBBB` and `rgb:r/g/b` with 1-4 digits scaled by bit replication. X11 names are deliberately unresolved (a 130-row table for a form nobody in this tree has a witness for) and land in `RC_UN_OSC_OTHER` like any other unreadable spec, which is I18 counting first rather than a claim that nobody sends one. Four things the live gate had to teach before this could ship. **One: the tables have two domains.** `RgbMap[0..15]` are console *attribute values*, not colours -- that is upstream's own mixed table and the reason `rc_attr` gates the 24-bit path on `> 15` -- so the fold needed a second array, `pal16[16]`, seeded from `GetStdPalette()`; the first draft folded one into the other and the host gate caught it (`the standard 16 are untouched` style failures). **Two: `SetConsoleScreenBufferInfoEx` is not inert.** Writing the struct straight back after reading it costs the window one row on this conhost (`srWindow.Bottom` 29 -> 28 for a 30-row window), the next plan then reads NOGEOM and declines, and the session is over -- setting a colour would have shrunk the user's viewport and refused to paint forever after. The same round trip in `close()` cost the 24-row realign leg a row, which is how it was found twice. Fixed by `apply_palette`: write, re-read the plain info, and put the rect and buffer size back through the APIs that own them, only when the console disagrees. **Three: `defAttr` was being copied into the SGR slots as if it were an index.** It is an attribute, and `rc_attr` converts index -> attribute through `ClrMap`, which is an involution -- so the double conversion is invisible for palindromic entries and wrong for the rest: a profile with a FORE_BLUE default got a red pen over blue cells out of one `rc_reset`. Control `cache/p55/control_arm.py` reverts the conversion and fails exactly four assertions, all of them `got 0x4 want 0x1`. **Four: the vendored fold caches by colour alone** (`static LastColor/LastIndex`), so with a live table it freezes a pre-change answer; both helpers now bypass the memo when a caller supplies a palette. What is deliberately *not* here: the console's own default attribute is untouched by OSC 10/11 (on this console that field *is* the pen, and writing it would fight `SetConsoleTextAttribute` every frame -- I34 records the limit), and the terminfo entry still advertises no `initc`/`ccc`, because declaring a palette capability is a claim about whoever parses the bytes, and under a ConEmu host that is not this library (I26). Gates: host `checks=3502 fails=0` (3329 before; the palette corpus adds 173 replayed checks through the resume and bounds loops), live `checks=5205 failures=0` on both architectures and again against the deployed bytes (`cache/deploy-20/gate.txt`). Deployed: `lib/x86` `2387f193...`->`71d4203b76a6ef4124decd7697aa3d68` (137624 -> 144506) and `lib/x64` `00eb6c6e...`->`cfa885d0f94e5cb858e29f9fe232179d` (133533 -> 140907), backups `render.dll.20260925-231054.bak`. One leg-order lesson worth keeping: a test that erases the viewport cannot sit in the middle of a run whose later rows are read back as they were left -- `casePalette` runs last for exactly that reason, and the failure that taught it was 8 red assertions in `caseRealign`. |
| 56 | ANSI_TODO P2：OSC 8 超链接（区间元数据 + 下划线 + 宿主查询 API） | `Render.cpp`'s OSC arm; a new per-run interval record | **Declined on instruction (用户 2026-09-26："osc 8不做"), and the reason kept as a technical debt rather than a preference.** Nothing about it is hard except where the metadata lives: a link is a *range*, not a cell, so it belongs beside `rowWrap[]` (I20) and inherits that family's standing gap -- it is model-side only and can never be read back through `CHAR_INFO`, which §5 makes explicit for I20 and which will apply here too. Underline-on-hover and a host query API are both beyond the sequence itself; the sequence alone buys nothing for a user. Reopening it requires answering "who consumes it", not "another terminal has it". |
| 57 | ANSI_TODO P2：OSC 52 剪贴板（默认关 + 显式开关 + 白名单） | `Render.h` (`RC_OSC_MAX`, `RC_TITLE_MAX`, `RC_CLIP_*`, `RC_UN_OSC_CLIP`, the grid's `clip[]/nClip/clipPending` and the four `nClip*` tallies), `Render.cpp` (`rc_b64_decode`, `osc_clip`, `g_clipPolicy`, and the `rc_osc_families` table that dispatches to them), `RenderJni.cpp` (`clip_apply`, the pending block in `paint_flush`, `STAT_CLIP`'s seven slots, `setClipboardPolicy0`/`clipboardPolicy0`), `NativeRenderer.java` (`ANSI_CLIPBOARD`, the two wrappers, the report clause), `RenderCheck.cpp` (`gm_clipboard`, `geo_osc_families`), `Render.java` (`caseClipboard`), `build.sh` (29 exports and the derived `gate_declared`) | Landed as build -24. **The row's title is still the design**: the sequence is one escape away from copying anything a program prints into the user's clipboard, so the default is off and off is what a session gets without having asked. Only the host can turn it on -- `ANSI_CLIPBOARD=on|1|true|yes` read at class-init, or `NativeRenderer.setClipboardPolicy` -- and nothing in the byte stream can reach either, which is what makes "off" mean off rather than "not yet asked". There is no ASK value, because this library owns no window to ask in; a host that wants a prompt implements it around the same call. Four refusals, each with its own counter so a report can say which happened: a selection field other than `c` or empty (Windows has one clipboard, so `p`/`s`/`q`/`a`/`b`/`c`/`d`/`0-7` are not folded -- ghostty folds only because X11 and macOS really do have those registers, `stream_terminal.zig:678-682`); a **read** (`52;c;?`), refused with the write switch on too, because the reply would put what the user last copied into the console's *input* stream (ghostty answers it straight to the pty, `:820-826`, from a terminal that also has a `clipboard-read=.ask` policy to gate it -- here the answer is a refusal with no policy to configure); a payload that fails a strict RFC 4648 decode; and one over the cap. Strict means: whole-payload or nothing, never a partial decode; interior whitespace refused rather than skipped (a multi-line wrap is not one message); the unused bits of a final group required to be zero (§3.5); a decoded NUL refused whole, because `CF_UNICODETEXT` is NUL-terminated and storing the prefix hands the user half a paste; and UTF-8 validated with `MB_ERR_INVALID_CHARS` before the UTF-16 conversion, a deliberate split from ghostty's unvalidated bytes. An empty payload is the *clear* request, not an absent one. Nothing is restored at `close()`: snapshotting the register would be the read this half refuses. **ConEmu has no OSC 52 at all** -- measured, not assumed: its OSC switch is `switch (*Code.ArgSZ)` with cases 0/1/2/4/9… and no `case L'5'` -- so ConEmu gives this row no parity to copy -- **but MSFT and ghostty both implement it and both default to allowing it** (`compatibility.allowOSC52` = true in `ControlProperties.h:59`; `clipboard-write = .allow` in ghostty `Config.zig:2459`), which is written down here precisely because it means the off-by-default is a divergence this project has to justify on its own merits, and I36 does: a terminal the user configures is a consenting party, a renderer inside someone else's JVM is not. The one place the references agree is honoured -- neither answers a read (WT `OutputStateMachineEngine.cpp:825`, ghostty `clipboard-read=.ask`) -- and one split is deliberate: WT ignores the selection field (":1097", "Currently the first parameter `Pc` is ignored") where this build refuses it. Four bugs, and the gates caught all four. **One: the decoder's own first bug** -- the non-canonical-tail mask read the bottom of the accumulator instead of the bottom of the *group*, so `QR==` (a legal-looking 'A' with a hidden bit set) decoded instead of being refused; caught by the host assertion written for exactly that case. **Two: a mis-bound JNI export**, `Java_..._setClipboardPolicy` written for a Java method named `setClipboardPolicy0` -- invisible to a whitelist copied by hand from the same wrong assumption, and invisible at run time *because the wrapper catches Throwable so an older dll keeps working*, which is also how it reads forever: "policy off". `build.sh` now derives the required names from the `native` declarations themselves (`gate_declared`: 12 in `Render.java`, 18 in `NativeRenderer.java`) so the list cannot be wrong in that direction again. **Three: the gate's reader was the writer's cache** -- AWT, once this JVM has called `setContents`, answers from the object it was handed, so every readback returned the gate's own string whatever the library wrote: counters said one write, the readback said the text never changed, and the two were describing different clipboards. Eight red assertions looked like a broken painter. `caseClipboard` now witnesses the clipboard from a second process (`pwsh Set-/Get-Clipboard`), and skips loudly where that is unavailable rather than falling back to the reader that can lie. **Four:** `OSC 52;;` never cleared anything, because `MultiByteToWideChar` returns 0 for an empty input and the painter read that as a failed conversion -- and because the Win32 sequence has no `EmptyClipboard()` in it, which is both the documented order and the only way a clear can be expressed. Gates: host `checks=4065 fails=0` (3810 at -23; `gm_clipboard`'s ~48 assertions and `geo_osc_families`' 142 are the difference -- the family table is now provably disjoint, exactly as wide as its probes, and no handler is silent), live `checks=5517 failures=0` on both architectures and again against copies of the installed bytes (`run.ps1 -Scratch D:/dbcli/cache/p63/deployed`). Deployed: `lib/x86` -> `8f6e57baec97ef4569bede145f23f78e` (149087 -> 156705) and `lib/x64` -> `604e05c787ed38739f00d8c03cc557bb` (144958 -> 152491), backups `render.dll.20260926-025516.bak`, and `run.ps1 -Scratch D:/dbcli/cache/p63/deployed` re-ran against copies of the installed bytes **twice** (`cache/p57/live7.txt`, `cache/p57/live8.txt`): the first -24 link hashed `1f78169b…`/`729191ce…` at these same sizes, and a later comment-only re-link moved both hashes without moving a byte of code -- §8's rule that md5 is file identity, not program identity, paid for itself again. `lib/dbcli.jar` -> `fe2a4ed01bb7d13c61dbbb202059fd58` with exactly **one** entry differing (`com/hyee/ansirender/NativeRenderer.class`, `f57364c9…` -> `18c1da7c…`) out of 132, proven entry-by-entry rather than by the jar's own hash; backup `cache/p63/dbcli.jar.20260926-025811.bak`. Shipped-pair control: `cache/p57/clipboot.ps1` boots the installed jar against the installed dll and prints `policy(dll)=false` with the variable unset and `true` for `on`/`1`/`yes`, `false` for `off` -- the static block no gate reaches. Real-session witness (`cache/p57/dbcli-win.txt`, the conpty_probe `window` leg, `ANSI_CLIPBOARD=on`): banner, `login o19c`, `select 1 as one from dual;` -> `ONE/---/1` and `1 rows returned`, status bar line intact, and the clipboard still holding the harness's own marker afterwards. What the same scripted session under `run` (ConPTY) did *not* show is recorded rather than smoothed: the statement produced no visible frame at 30 s settle while the `login` typed on the same channel did, which is a property of that leg and not of the renderer -- the identical statements PASS through the same jar headless. |
| 58 | ANSI_TODO：实现 HPR `CSI a` / VPR `CSI e`（视口钳制，不受滚动区约束） | `Render.cpp case 'a'` / `case 'e'` (both `clxy`, i.e. viewport-clamped); the design is **I33** | Both reference terminals implement them identically and MSFT says why in prose -- "Unlike CUF/CUD, this is not constrained by margin settings" (`adaptDispatch.cpp:427`, `:437`); ghostty agrees (`stream.zig:1863`, `:1942`); ConEmu has neither case, which is how they came to sit in `RC_UN_SUP`. **This row's real content is a test bug, recorded because it is the trap in this family:** the first live leg went red on `caseRelativeCursor` and the renderer was right. VPR preserves the *column*, so the characters printed after it advance that column, and an expectation copied from CUD intuition ("down one line, then column 0") is wrong in three cells at once. Corrected to `Y` at `(winT+17, 1)`, `Z` at `(winT+17, 7)`, cursor `(8, winT+17)`, and the leg now also refuses to run on a non-standard geometry rather than computing expectations from a gutter it has not measured (`standardGeometry()` guards the relative-motion leg and says so in its message). Control arm `cache/witness/hprvpr-control-20260925.txt`: `case 'a': break;` + `case 'e': move_row(...)`, i.e. the two documented wrong answers, which prints `checks=3222 fails=8` with `BUILD FAILURE: host:rendercheck`, all eight in these legs, then restored and green. Shipped with #50 in the -17 batch; §3's I33, §2.3 and §2.5 of `ANSI_SUPPORTS.md` updated, and `a`/`e` removed from §6's inert list. |
| 59 | WORK_ORDER T2：interim 单槽 → 集合（顺带修掉两个"多余字节冒充合法拼法"） | `Render.h` (`RC_INTERIM_MAX`, `RcGrid.interims[]/nInterims/escInterim`); `Render.cpp` (`interim_push`, `interim_is`, `csi_dispatch`, `echoes`, the CSI and ESC parser steps) | Upstream keeps both CSI byte ranges in **one accumulating buffer** -- Ansi.cpp:1788 appends every non-digit, non-`;`, non-final byte into Pvt, 0x20..0x2F and 0x30..0x3F alike -- and every consumer then compares its **length**: :3645 and :3657 both read `PvtLen == 1 && Pvt[0] == X`. A single slot let arrival order decide what a sequence *was*, so two spellings fired here that upstream refuses: `CSI ! SP q` set a cursor shape (the space arrived last), and `CSI ? ! p` ran a hard reset, because the private byte and the intermediate were tested in two unrelated places -- DECSCUSR had always checked `!g->priv`, DECSTR never had. The set plus exact-length matching is the fix, and the three pins that already existed still pass untouched (`CSI 2 SP q` sets the shape, `CSI ! p` resets, an unknown final counts `RC_UN_SUP`) -- that is what a consolidation is allowed to look like. Gates: six new host assertions, written red first (`checks=3241 fails=6`, the failures named one by one: `cell(0,0)=0x20 want 0x41`, `SUP 0 want 1`, `cursorShape 0 want 3`, `SUP 2 want 3`, and the same pair again for a run of ten intermediates), green after at `checks=3241 fails=0`; live unchanged at `checks=5188 failures=0` on both architectures, because nothing in its corpus sends a second intermediate. The ESC introducer is a different lifetime and now has its own field (`escInterim`), so the charset path (`(`, `)`, `%`) behaves byte for byte as it did. Layout: the three fields take 12 bytes where 4 used to be, so everything after them shifts by 8; `sizeof(RcGrid)` is 4200880 measured on the host build (LP64 -- not comparable with the Windows number recorded in `reference-conemu-source-and-build`). Prerequisite of #51: DECRQM is `CSI ? Ps $ p` and `$` needed a home that `!` and the space had already taken. Not deployed on its own -- it ships with #51. |
| 60 | 复核"上游也不做"式理由：DECSTBM 验收改为参照一致 | `Render.cpp`'s `case 'r'`; `ANSI_SUPPORTS.md` 2.4/2.5 and deviation items 10-11; the scan script `cache/upstream-excuse/cand.py` | The user's ruling was that ConEmu is a parity oracle, not a design oracle: where ConEmu implements nothing, "upstream does nothing either" cannot be the reason this build does nothing. Every such sentence in the six documents was extracted and re-read for an independent reason; three verdicts came out. **Wrong, and fixed:** DECSTBM mirrored `Ansi.cpp:3142`'s `ArgC >= 2` gate, so `CSI 3r` -- legal in VT, and what MSFT's own comment at adaptDispatch.cpp:2239 spells out as `[3;r -> 3,h` -- *cleared* the region here, and `CSI 3;2r` cleared it too where both references ignore it. Clearing and ignoring are different acts: clearing hands the next line feed the whole viewport, which is the #47/#48 failure with a new trigger. **Right for the wrong reason, and re-reasoned:** the non-private `CSI Pm h/l` refusal (DECAWM now carried as #61, because MSFT implements `?7` at :1799 and the real reason to refuse it is the caps' `am` declaration, not upstream), IL/DL's region guard (we are the VT-correct side; upstream is the loose one), and the ICH/DCH, `?31m`, parameter-cap, `ESC ) c` and italic/crossed rows, which now cite a capability or an xterm-parity fact instead of an upstream absence. **Never an excuse:** HPR/VPR, OSC 133, the SIXEL family refusal and DECRQM's silence were already reference-driven. What the gate caught on the way is recorded because it is the trap in this family: the first cut used `t >= b` for "ignore", which also refused `CSI 1;1r` -- and `Status.reset()` arrives as exactly that (JLine's `csr` at a 0x0 size through `%i`), so the bar's region would have stayed stuck on. Four host assertions went red on it. The rule is therefore `t > b`, with `Pt == Pb` accepted as a one-row region and an out-of-range bottom clamped rather than rejected: two deliberate splits from MSFT, each with its reason in the comment. Gates: host `checks=3329 fails=0` (3318 before; the +11 are the new region assertions), live `checks=5188 failures=0` on both architectures -- the live count not moving is expected, since no `Render.java` leg sent a one-parameter or inverted DECSTBM. Deployed as `render-2026-09-25-19`: `lib/x86` `1a3d5cc8...`->`2387f193bc7962f4383bc167670b4108` and `lib/x64` `3ab952a6...`->`00eb6c6e1fc5823581d98464fbbec7e4`, both still 137624/133533 bytes -- the edit fits inside existing branch size, which is exactly why md5 and not size is the ship census; backups `render.dll.20260925-210940.bak`, and `run.ps1 -Scratch cache/deploy-19` re-ran against copies of the installed bytes. |
| 61 | DECAWM `?7`：实现或明确不做的决定（连带 caps 的 smam/rmam） | `Render.h` (`wrapMode`), `Render.cpp` (`blank_cell`, `last_free_col`, `put_cell`/`put_pair`'s fit test + trim + margin clamp, the `?7` arm of `h`/`l`, `mode_status`, both reset seeds), `RenderJni.cpp` (`build_model`'s `keepWrap`), `RenderCheck.cpp` (`geo_decawm`, `gm_wrap_suspect`'s census row), `Render.java` (`caseDecawm`, one `legs` arm) | Landed as build -22, and the row's own history is the point: #60 raised it because the refusal had been written as an upstream absence, which is not a reason. The mode is modelled (I35), so `?7l` ends the line at the margin -- cursor holds, no `RC_WRAP_FORCED`, a glyph that cannot fit is dropped whole, per MSFT `Row.cpp:474-494` -- and DECRQM answers it. **The caps half of the question was decided the other way and stays decided**: `smam`/`rmam` are NOT added, because `windows-conemu` also describes sessions where ConEmu's parser reads the bytes and its `?7` arm leaves `SetConsoleMode` commented out (`Ansi.cpp:3268-3281`) -- advertising the pair would be I26's lie about the other parser, and the entry's `am` clause is about the *host* terminal, not about this library's grid. The writer evidence went through a correction of its own on the way: `lua/ansi.lua:150-151` defines WRAP/UNWRAP, but its only call sites are commented out (:346-352), so the claim "an application in this product asks for it" was false as written; what is true is the third-party case -- this library models whatever the screen it owns is handed, and DECAWM is among the most-sent modes in existence. Two invariants the clamp made reachable and had to be enforced with it: the margin clamp steps off a trailing half (a cursor never rests inside a glyph), and a narrow glyph written over a wide one's front half now blanks the orphaned back half -- the pair is I16's unit, and with no-wrap that state would be manufactured on every row that mixed CJK and Latin rather than only where a CUP happened to land. Both resets (RIS, DECSTR) restore the mode; a rebuild carries it (`keepWrap`: a resize is not a request to start wrapping again); the non-private `CSI 7 h/l` is GATM and stays unmodelled, still voting MODE. Two bugs the gates caught, both worth keeping. **One: `build.sh --no-colorcheck` leaves a stale `out/rendercheck`**, and re-running that binary prints a confident green line for the previous build's assertions -- it is how the first -22 "pass" happened, and the doc's own warning at section 8 was not enough to stop it. **Two: `legs()` cases share one grid with every leg that follows**, so `?7l` left behind un-restored failed `caseWrap` two rows away, three cases later; the mode is now turned back on inside the same bytes. Gates: host `checks=3713 fails=0` (3632 before; `geo_decawm` plus the census row, whose `?7l` stayed in the stream as the proof that the MODE count fell by exactly its two spellings). Live `checks=5469 failures=0` on both arches -- **not comparable with -21's 5216**: `caseLegsAgree` prints `SKIP` and no failures when it cannot find a ConEmuHk, `lib/{x86,x64}` on this install has none, and passing `-Install` a tree with both made ~230 A/B checks appear for the first time in several stamps. `DECAWM off at the margin` is the family's first *cell* divergence and it is documented as one: native `Q` at column 199, hk `R` there with its `Q` on the next row. Deployed: `lib/x86` -> `c7667a9fe23535f0bfd791c46def08b1` (146797) and `lib/x64` -> `8b6a6528e705bce1e9f1d0581683d8c0` (143188), backups `render.dll.20260926-0039*.bak`, and `run.ps1 -Scratch cache/p61/deployed` re-ran the gate against copies of those installed bytes. |
| 62 | WORK_ORDER T6：census 元数据登记表（纯收敛，槽位与 stats 布局不动） | `Render.h`'s `RcUnsupported` family, `unsupported()`/`ignored()` in `Render.cpp`, and the name/suspect/description text each of them carries | **Open, added on the user's request 2026-09-25** (the order marks T6 optional). One static table keyed by slot, holding the report name, whether it sets `modelSuspect`, and the sentence; `unsupported()`/`ignored()` query it. Slot order and the stats layout do not move by one byte -- I19 makes the census a positional contract across `RenderJni.cpp`, `Render.java` and `NativeRenderer.java`, and the live gate checks the array length. Because nothing may change behaviour, the proof is equality, not green: dump the registry to normalised text before and after and diff it empty, alongside a green host gate, and name which entries were previously written in three places. |
| 63 | WORK_ORDER T7：OSC 9 安全子集分派（9;4 / 9;9 / 9;12） | `Render.cpp` (`osc9_action`, `path_is_legal`, the `code == 9` arm of `osc_finish`), `Render.h` (`taskbarState/Progress/Seen`, `cwd[]`, `nCwd`), `RenderJni.cpp` (`taskbar0`, `workingDirectory0`, the carry in `build_model`), `NativeRenderer.java` (the two wrappers), `build.sh` (two exports) | Landed as build -21 on the user's instruction that ConEmu is not the design oracle: upstream parses this family and does nothing, so the boundary came from MSFT's `DoConEmuAction` (adaptDispatch.cpp:3558-3647), which acts on 9;4, 9;9 and 9;12 and sends **everything else** to `UnknownSequence()`. Two rules were kept from that source rather than invented: an out-of-range taskbar state is refused without applying (":3596-3600") while an out-of-range progress is clamped to 100 (":3601-3605"), and the path is legal-or-nothing through a filter equivalent to `til::is_legal_path` (its own test pair at ut_til/string.cpp:247-249 is the evidence for what that means in practice: a `;` survives, a `"` inside does not). **The library stores and never obeys**: no window means no taskbar to paint, and a working directory read from an output stream stays a string -- which is the whole #687 posture kept while the safe subset is parsed, and the §2 rule is rewritten to say exactly that rather than the old "not parsed into an action under any circumstances", which this row made false. `9;12` calls `ftcs_apply` with the argument `B` instead of reimplementing what prompt-start marking means, so the two spellings cannot drift apart. Both facts survive a rebuild (a resize is not a re-open), which is the live leg's `readopt` pair. Gates: host `gm_osc9` -- 34 assertions covering the clamps, the refusals, the unterminated payload (which counts only once the parser abandons it, a distinction the first draft got wrong), the DCS framing guard, and `9;12` compared field-by-field against `133;B` on two grids: `checks=3632 fails=0`. Live: `caseOsc9` reads both getters back, proves `9;7;calc.exe` changed neither, and proves the carry across `readopt`: `checks=5216 failures=0` on both architectures. Two test bugs found on the way and worth keeping as warnings: writing `\"a\"` intending a control character produces BEL, which *terminates* the OSC instead of being rejected by it; and an unterminated payload has not been counted yet at the moment the assertion is written, because the parser is still inside it. |
| 64 | 参照 commit history 反查 #1：IL/DL 之后光标要回区域最左列 | `Render.cpp:1290` `case 'L': case 'M':` -- both arms end in `g->cx = 0` (region and no-region), the refused out-of-region arm keeps its column | MSFT states it as the expectation (`adaptDispatch.cpp:2150`, `cursor.SetXPosition(leftMargin)`) and ghostty enforces it in a `defer` (`Terminal.zig:2977`, `:3151`). The cost of the old behaviour is a table redraw: walk in to a column, delete the line, write the replacement from wherever the cursor ended up -- every row n cells off, once per row. Host: `geo_lines`. Live: `caseEditRows` (Render.java), which reads the cursor back from conhost, checks the shifted rows and their wide glyphs, checks the region's own band, and checks that a **refused** IL keeps the column it was refused at, because nothing moved so nothing is owed. Run at -25 on the deployed bytes. |
| 65 | 参照 commit history 反查 #2：ECH 只擦游标所在的一行 | `Render.cpp:1325` `case 'X':` -- clamped to `g->cols - 1`, one row | Both references say it in prose and clamp the same way: MSFT `adaptDispatch.cpp:706-724` ("only erase characters in the current line, and won't wrap to the next", `std::min(startCol + numChars, GetLineWidth(row))`), ghostty `Terminal.zig:3443-3446`. The row this replaces argued the walk-down was ConEmu's buffer-relative shape and only its off-by-one was wrong; **withdrawn** -- a `CSI 999X` erasing the viewport below the cursor deletes content the application never named, which is the one class of deviation that cannot be paid for with parity (§7's list, [[feedback-upstream-not-a-reason]]). `CSI 0X` still erases nothing: the parameter is read raw, MSFT's arithmetic agrees, ghostty's `@max(count,1)` is the outlier and is named as one. Host: `geo_edit`. Live: `caseEchClamp`, four rows of text and an erase that must not reach any of the three below. |
| 66 | 参照 commit history 反查 #3：ICH/DCH/ECH/写入都能把宽字形切成半格 | `Render.cpp:354` `heal_pairs(g, row, from, to)`, called from `fill_span` (:392), `blank_cell`, `put_cell`, `put_pair` and both `case '@' case 'P'` arms (:1404) | ghostty calls this an integrity violation and asserts it (`page.zig:518-540`) and clears at every boundary (`Terminal.zig:3322-3342`, `:3411-3413`, `:3448-3452`); MSFT's `Row.cpp:1215` `_adjustBackward` is the same rule read from the other side. One function rather than five fixes because the failure was never "this call forgot" but "nobody can see the far half of a pair from the near one". Host: `no_orphan()` (RenderCheck.cpp:133) now runs over **every row of every replayed corpus**, and `geo_edit` pins the shapes. Live: `caseHealPairs` + `noOrphan()` on real cells. The witness itself went red twice before the code did: the first draft omitted `if (!bad) continue;` and reported every *legal* pair as an orphan, and two correct old assertions were judged broken until the row's attributes were printed -- see the method note in `.dsh/memory/project/project-renderer-cell-integrity.md`. |
| 67 | 参照 commit history 反查 #4：DECSTR 走的是软复位，不是 full_reset | `Render.cpp:1083` `soft_reset()`; `full_reset()` (:1052) stays RIS's | MSFT's `SoftReset` is `adaptDispatch.cpp:2984-3020`, a list of assignments with no cursor move, no erase and no buffer switch -- those are `HardReset`'s (:3042-3062 (`UseMainScreenBuffer` is at :3047), where `UseMainScreenBuffer` finally appears) -- and it clears the **active** buffer's saved cursor only (GH#19918, :3005-3008). Before -25 a `CSI !p` here left the alternate screen, scrolled a viewport into history and homed the cursor. The saved cursor is cleared by overwriting the two coordinates, because the model has no "is there a save" bit; the cursor **shape** is deliberately left alone (DECSTR's list has none, and `-1` exists so a session that never asked keeps the user's preference). Host: `gm_state_reset`. Live: `caseSoftReset` -- screen kept, cursor kept, pen dropped, DECRC landing where the cursor already stands **plus the control that saves and restores again** so that last claim cannot pass by DECRC being broken. |
| 68 | 参照 commit history 反查 #5：recycled 行只清了 rowWrap 和 rowMark | `Render.cpp:350` `row_reset_state()` now also zeroes `markCol` | ghostty `046a45a5f`, "fully reset row metadata when recycling row storage" (`PageList.zig:5252` -> `Page.zig:1307 resetRow`), found by reading the *history*, not the tree. `shift_region` handed a recycled row a live `markCol` from a row that had moved, which is I23's prompt-start mark pointing at a column of a line that is not there. Invisible on screen by construction -- it never reaches `CHAR_INFO` -- so the proof is host-side: `geo_ftcs` reads the field, and the ledger entry for it is the reason a model-only fact needs a model-side eye. |
| 69 | 参照 commit history 反查 #6：`lastUnit` 记在宽度判定之前 | `Render.cpp:702` `if (rc_width(cp) > 0) g->lastUnit = cp;` | ghostty assigns `previous_char` inside the printable branch only (`Terminal.zig:1469` -> `:1515`). Storing a zero-width unit made `A` + U+0300 followed by `CSI 3b` draw nothing at all, because the thing being repeated was the mark. Host: `gm_state_reset` pins `lastUnit` to `A` after a combining mark. |
| 70 | 用户点名的 `cbt`：`\t` 背后必须是一张表，不是一段算术（架构轮第 4 项） | `Render.h` (`tabStop[]`/`tabsDefaults`/`RC_TAB_INTERVAL`、`rc_tabs_widen`), `Render.cpp` (`tabs_default`/`tabs_reset`/`tab_next`/`tab_prev`；`HT`、`case 'I'`、`case 'Z'`、`case 'g'`、`ESC H`、`full_reset`、`rc_reset_hist`), `RenderJni.cpp` (`build_model` 携带表) | Landed as build -29 as I38. `\t` was `((cx + 8) >> 3) << 3`: not a rule about tab stops, a restatement of the default interval, and the reason four real sequences could only be refused -- with nowhere to write, `ESC H` claims nothing and `CSI Ps Z` has nowhere to back up to, and both refusals said so in those words. Three rulings, each with a citation on the same line as the code: the table is terminal state, so main and alternate **share** one (MSFT on the adapter, ghostty on the Terminal); a rebuild **carries** it and re-materializes the interval only in columns that did not exist, only if nobody cleared it (MSFT extends, ghostty forgets, our own resize already carries the palette and DECAWM); and `ESC c` **restores** it where MSFT's HardReset says nothing -- one reference each way, tiebroken by "a caller with no way to ask for its defaults back". `CSI 3g` is the reason the flag exists: it clears the interval as well as the array, and `CSI 5g` (DECST8C, whose name promises five columns and whose enum value both references spell `SetEvery8Columns`) puts both back. Census: CBT is no longer counted, and `geo_census`'s leg was re-baselined to say so rather than deleted; no slot moved, so no jar. Proof: host `checks=5461 fails=0`; live `checks=5738 failures=0` both arches against copies of the installed bytes (`caseTabStops` at :795); four arms each seen red -- T1 `\t` back to the arithmetic (5 legs), T2 `CSI 3g` keeping the interval (1), T3 RIS not restoring (1), T4 entering the alt throwing the table away (1); control green. T2 and the first T4 came back **green** and both were real gaps, found the only way that works: T2's empty-array-with-live-flag state is indistinguishable until something rebuilds, so `geo_tabs` now drives `CSI 3g` *through the parser* into a widen instead of writing the flag by hand, and T4 was re-written to wipe the table at the alt switch, the place a per-screen table would actually differ. The caps entry still declares no `cbt` -- that is #90, and it has to move with `lib/JLine3.jar`. Opened as the reverse-lookup finding on #7 -- `\t` hardcoded mod 8, no table anywhere -- and approved by the user as its own pass with a red-first control. Both references keep a real table (MSFT `adaptDispatch.cpp:2648-2674` walks `_tabStopColumns`; ghostty has `Tabstops.zig` plus `Terminal.zig:2266`, `:2304`), and `\t` was a second entrance to the #66 class: the cursor can land mid-glyph through a tab, which is why the table's legs are paired with the wide-glyph one. |
| 71 | 在 `src\c\conemu` 补 terminfo / infocmp 一类的文件（用户 2026-09-26 指令） | `terminfo/windows-conemu.caps` (mirror), `terminfo/windows-conemu.ti`, `terminfo/infocmp-windows-conemu.txt`, `terminfo/terminfo_check.sh`, `TERMINFO.md` | The entry the application loads is a jline resource, and `tic` **cannot read it**: its first line carries this project's prose and terminfo parses the commas as field separators (`line 1, col 420: Illegal character - ' '`). So no standard terminfo tool could be pointed at the contract, and the audit harness lived in `cache/`. Now there is a `tic`-clean derivation, a checked-in `infocmp` dump, and a four-leg gate: `tic -x` compiles clean; the `.ti` and the mirrored `.caps` hold the same **90** capabilities spelled alike; `tic -> infocmp` round-trips the same **84** names (names only, on purpose -- `infocmp` rewrites `colors#256` as `colors#0x100`, so a value compare would fail on any entry ever compiled, and the byte-level meaning is the caps harness's job through jline's own decoder); and three copies of the running entry -- mirror, jline source, `lib/JLine3.jar` -- are byte-identical (`89dea0736281`). Arms 1, 2 and 4 were each demonstrated red with one deliberate edit and no other leg moved; **arm 3 was not** -- the only way found to make the dump differ is the way that also makes `tic` complain, which leg 1 catches, so leg 3 stays as the guard against a future ncurses folding or renaming a capability, and that limit is written here rather than in a comment. `TERMINFO.md` also answers the question the jline4 entry raises: of the eight capabilities upstream declares and this one does not, only `kmous` (`MouseSupport.java:85`) and `cbt` (`LineReaderImpl.java:6992`) have readers -- the first is correctly absent because the mouse modes are counted and not implemented, the second is a real (small) cost whose fix is #70, and the remaining six have no reader anywhere in jline4. |
| 72 | 架构对照轮第 1 项：把栅格完整性做成可调用的小神谕，并让它进 live 门禁 | `Render.cpp::rc_validate_grid` (declared in `Render.h` below the struct), `RenderCheck.cpp::grid_ok` hooked into `put`/`put1`/`putu`, `RenderJni.cpp::Java_Render_validateGrid` (gate-only, the 30th export), `Render.java::gridClean` called from `paint()` plus the run-count assertion | Landed as build -26, first because #75 (rotating rows instead of memmoving them) must not be attempted without an eye on the grid, and second because the user's ruling that this is a third-party library means the oracle is also **API**: a host that wants to assert its own invariants can call it. The list is in the function's comment, with the one thing it deliberately omits named there too (a cursor resting on a trailing half is legal after a CUP; only moves keep off a glyph). Gates: host `5201/0` (+965 = one validation per feed over the corpus), live `5689/0` both arches on the deployed bytes with `runs=436 violations=0` per arch. Arms: removing the ICH/DCH `heal_pairs` call -> `fails=3`, naming `row 0 column 1: a TRAILING half whose LEADING is gone`; removing IL/DL's column home -> **silent**, correctly, which is rule 19 and is written down rather than hidden. The same run caught the clipboard case restoring the register with a single attempt (a flaky `pwsh` child left the test's marker on the user's clipboard) -- now retried, and the restore leg refuses to report a skip. |
| 73 | 架构对照轮第 2 项：三张平行行数组打包成一个 `RcRowState` | `Render.h` (`RcRowState`, `rowState[]`, `snapState[]`, the two `static_assert`s), `Render.cpp` (`row_carry`, `row_reset_state`, `rc_forget_row_state`, `alt_screen`'s save and restore loops) | Landed as build -27, second because #75 rotates rows by index and every per-row fact has to travel with the row identity, and because -25's #5 was this shape's failure mode made visible: `shift_region` carried `wrap` and `mark` and left a live `col` behind. ghostty packs the same facts into one `Row = packed struct(u64)` with a single-store `reset()` (`page.zig:2014`, `:2133`); MSFT keeps them inside `ROW` (`Row.hpp:313-317`). The four triple-sites are now one statement each, and the `OscFx` mirror in the host gate copies whole structs too -- a mirror that samples one field is the same bug one level up. Proof is equality, not green: the live count unchanged from -26 (5689/0 both arches, deployed bytes), footprint pinned by static_assert, and arm A re-creating the half-carry by hand -- which came back **green** the first time, because every `rc_mark_col()` witness in the gate sat on a row that had not moved and a column lost from 0 is still 0. Six legs in `geo_ftcs` now move a prompt made at column 4 up with DL and back with IL, and both arms bite (wrap+mark leaves the column red; wrap+col leaves three marks red). Host 5201 at -26, 5218 with those legs; `RenderCheck.cpp` is host-only so the shipped pair did not move. See §6's -27 paragraph for the whole of it, including the claim this row used to carry. |
| 74 | 架构对照轮第 3 项：每一个"数几个"的参数都在读取处说出它的上界 | `Render.cpp` (`count_arg`, `count_arg_raw`, `region_arg` beside `arg`; the `L`/`M`, `@`/`P`, `X`, `b`, `S`/`T`, `r` arms), `Render.h` (`RC_ARG_MAX`, `RcGrid::nArgTrunc`), `RenderJni.cpp` (`Java_Render_argTrunc`, the 31st export), `RenderCheck.cpp` (`gm_argcap`, `geo_region`, and `eq_text` itself) | Landed as build -28, third because it is the change that makes #75's row-rotation safe to reason about: a rotation moves the rows and their bounds with them, and every bound here is a quantity derived from `cy`, `cx`, the region or the model. Naming each limit found two defects. **In the model**: DL clamped its count to the viewport's height while its own blanking loop starts at `rows - n`, so with the cursor below the window's top row an over-large `CSI Ps M` erased the rows *above* the cursor and left its own standing -- IL never suffered it because its loop begins at the cursor, which is the point: the defect was in a quantity nobody had written down, not in a direction. DECSTBM also carried three clamps whose two non-positive tests were unreachable, because `arg()` cannot return what its default rule already excludes. **In the gate**: `eq_text(row, upto, want)` compares `[0, upto)`, so `upto = 0` compared nothing and voted pass (one leg had been doing that since -25), a wider `upto` read past the grid's own columns into bytes a previous geometry left in the fixed-stride cell array, and padding for a short `want` indexed past the string's terminator into the next literal. Both impossible shapes now refuse. The overflow policy is stated once too: digits saturate at `RC_ARG_MAX` because a wrapped `CSI 999999999999H` would name a row nobody asked for, while the OSC parser refuses ten digits outright because there the number is a claim, not a count. The 16-argument cap stays upstream's (Ansi.h:174) but is no longer silent -- `push_arg` counts each dropped argument, exported gate-only so the live gate can read it off the shipping binary. **Deliberately not taken**: a `stats()` slot for that counter. Appending one is safe (`STAT_LAST`, a new index, the jar's `has()` guards), but the report that *names* it lives in `NativeRenderer.java`, in the authority tree another agent is building against, and shipping it means a coordinated `lib/dbcli.jar` -- so it is #89, with its cost written down. Proof: host `checks=5298 fails=0`; live `checks=5715 failures=0` on both arches against copies of the installed bytes (`cache/p63/live28c.txt`); arms each seen red -- DL back to the window's height (2 host legs, and **8 cells on a real console** against a scratch build of that source, `cache/p63/live28arm.txt`), the counter un-incremented (2), `count_arg` returning the raw argument (5), the accumulator allowed to wrap (1). |

| 76 | 按"第三方库要给调用方特性"的新裁决，重论证 `ANSI_SUPPORTS.md` §3 里每一条拒绝并逐条实现 | `ANSI_SUPPORTS.md` §3's rows; the implementations land wherever each sequence belongs (`Render.cpp`'s CSI/DEC arms, `Render.h`'s state, `Paint.cpp` for anything that touches the console) | Opened by the user's ruling 2026-09-26: "应该实现的特性就要实现，包括且不限于 cbt —— 你开发的是独立的第三方，应给调用方更多的特性支持，而不是因为 dbcli 不用就不做". So each refusal must now answer one of §1's three admissible questions, and the ones that answer none become work. The candidates this pass named, with the question each still has to answer: **mouse modes `?9`/`?1000`-`?1006` + `kmous`** (jline4's `MouseSupport.java:85` reads the cap as the answer to "can this terminal do mouse events"; enabling `ENABLE_MOUSE_INPUT` is a console-mode change, and the library already writes replies into the input stream for CPR, so the surface exists -- the open question is restore-on-close and who owns the mode); **colon subparameters** `38:2::r:g:b`/`4:3` (I10 parity with ConEmu is the only reason they are dropped, and parity is not a floor); **DECOM + left/right margins** (`?69`/`?48`/`DECSLRM`, which is what makes `IL/DL`'s `leftMargin` mean something other than column 0 -- #64's citation is MSFT moving the cursor to *leftMargin*, and we hardcode 0 because no margins exist); **`?2048` in-band resize reports** (we stay silent because 3/4 would lie to one of two readers, but 2 is a claim we could earn by emitting the report); **`CSI t` window ops 22/23** (a title stack is entirely inside our own state -- the honest refusal covers only the pixel-size forms); **`u8`/`u9`** (refused for "no consumer in jline", which is exactly the sentence this ruling retires). Deliberately **not** in scope, each with its floor named: the OSC 9 execution half (#687), OSC 52's default (I36), OSC 8 (the user's own ruling, #56), `smam`/`rmam` and `initc`/`ccc` (I26), blink/invis painting (no console attribute bit). |

The honest gaps in the table, stated rather than papered over. **Rows #13 and #14 are dbcli's pager and have no
`render.dll` gate at any level** -- their only witness is a live console leg, which is weaker than the rest of
this section and is the first thing to re-run if the pager misbehaves after a jline change; #14's leg is at least
doubled by a `javap` reading of the shipped bytecode, #13's is not. **Row #13's `ceon` leg is unreadable as
witnessed** (the harness's own prompt regex cannot parse a grid that still holds 83 literal escapes), so the row
rests on one leg, not two. **Row #16's ruling now has a produced A/B, and it is the wrong A/B**: what
`wide1516-20260925-13.txt` measures is *line width* across two geometries, not a wide-buffer scroll, so §9's
scroll leg is still owed and deviation 1 still rests on the planner's algebra. And **row #23's legs and the -6
file they replace were run against different jars** (`2297d517…` vs `0ea9b33c…`), so the two agree on the shape
of the status rows and nothing about Java-side behaviour. Three more, from the 2026-09-25 rows: **#37 and #38
have no real-ConEmu-window leg** -- `NativeWinSysTerminal` also reports `windows-conemu` when `ConEmuPID` is
set, so the third host in this family is unmeasured and only inferred from the two that were. **#39's snap leg
proves the call is safe, not that it helps**: no assertion covers "the user had scrolled away and a keystroke
brought the prompt back", which is the behaviour the task exists for. And **#40's witness is a probe harness,
not a gate** -- the fix is in dbcli's `Console.java`, so neither standing `render.dll` gate can carry it. The
same applies to the CJK-doubling re-check that followed it (`cache/wt-doubling-ab-20260925`): a real Windows
Terminal window read `0 doubled pair(s)` with 14 filler rows intact at `frames_read=192`, and the classic
conhost leg where the renderer *is* engaged read the same `0 doubled pair(s)` at `frames_read=134`, but only
the shipped arm was taken through that harness -- the pre-fix arm rests on #37's ENGAGED/off matrix, not on a
same-harness before/after. **Seven more, from the rows added since:** **#48 has a unit red/green pair and no
post-fix live arm** -- the symptom was watched in a real window and reproduced there, but what closed it is
`StatusTest`'s six cases (`tests=6 found=6 succeeded=6 failed=0`) plus a single-block revert as the control
(`succeeded=4 failed=2`, and the two red are exactly the bordered-resize cases); a library-side proof for a
symptom that only ever shows in a window. **#43 is stated as mechanism-removed, not symptom-witnessed**, for the
reason given below. **#44's proof depends on a hook that ships**: `Java_Render_faultRect` is in `build.sh`'s
export whitelist because the gate links against the released DLL, so `render.dll` exports a fault injector that
nothing at runtime calls -- said here rather than buried, because it is the kind of seam a later reader otherwise
assumes is dead weight. **#45 is a gap that is not about evidence**: #38's classification fix is still not in
`lib/`, and until it is, no ConEmu-window leg can be taken at all. **#53's own list is still open at one item**,
and #51 blocks on it: the interim marker has a single slot where DECRQM/DECRPM need a set. And **#47/#48 leave
their library half un-rehearsed** -- `JLINE_CHANGES.md`'s "What is not witnessed" is the list (`reset()` has no
red/green pair, `resize(Size)` has no unit case of its own), because those are edits to someone else's codebase
and this file does not get to claim their coverage. If a row's witness file is missing, the row is
unproven, whatever the two standing gates say.

**Row #41's two claims are both answered, one by invalidating a witness and one by removing a mechanism.** The
20-column staircase was never on the screen. #42 shows it to be the probe's `ReadConsoleOutputW` readback of
conhost's *shadow* buffer, which keeps the pre-resize pitch while the window itself renders clean -- one fixture
run through two resize paths, with `uia-resize.ps1` as the only qualified resize witness and `pw-shot.ps1`
(`PrintWindow`) as the witness to what a user sees. The trigger is named and it is the harness, and the rule that
survives the finding is in `.dsh/memory/reference/reference-wt-geometry-witness.md`: on a `--host wt` leg a
readback is not evidence about geometry. The second claim -- close the bar, *then* resize, and the screen wipes to
one prompt row -- is #43, where the mechanism was a scroll region a torn-down bar left behind and the removal is
`Status.reset()` writing `CSI r` with no parameters. That row is deliberately narrower than the old paragraph:
`clearScrollRegion()`, the call #41 said `More.init()` was missing, **does not exist anywhere in the tree**, and
`More` reaches the teardown through `close()`, which is `hide()` + `reset()`. But **the leg has not been re-taken
since the fix landed** -- the one measurement on record predates the `Status.java` that carries it and ran through
the resize path #42 voided -- so #43 closes as "mechanism removed", not as "symptom witnessed gone". The script
that would take it is ready at `cache/resize43-20260925/leg43.json`.

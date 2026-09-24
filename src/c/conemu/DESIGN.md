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
| Never execute ConEmu-private OSC 9 | That family is counted and ignored. It is not parsed into an action under any circumstances (ConEmu issue #687). |
| One width oracle | Display widths come from the `ansi_width` table in `src\c\luauf8`, which `rc_width()` links through the generated `ansi_width_tables.h`. No WCWidth or jansi table may be substituted, and the locale and the font are not consulted. |
| Output is the same on every Windows version | The model does not depend on `ENABLE_VIRTUAL_TERMINAL_PROCESSING`, and a model row is a **buffer** row (I7), so wrap points and erase extents agree with the console regardless of window width. |
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
`stats`, `close`, `build`. The rest of the exports (`feed`, `flush`, `sgr`, `align`, `openStatus`, and the
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
`smir`/`rmir`/`mir` (IRM has no entity; `CSI @` always inserts), `smam`/`rmam` (DECAWM is recorded, never
applied), `smkx`/`rmkx` (DECCKM selects *input*, which here comes from console records), `blink`, `invis`
(SGR 5/6/8 store nothing), `rmpch` and the `sgr` 10/11 arms (no font switching), `ncv` (no
cannot-coexist bits), `mc5i`, `flash` (`ESC g` would ring a window that is not ours to ring),
`initc`/`ccc` (OSC 4 is consumed, per I21, but the palette does not change), `u8`/`u9` (both DA queries are
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
  `Render.cpp:1234-1235` arms `CSI 5n`/`CSI 6n` and `flush_reports` writes the answer into `CONIN$` as key
  events. Read the pair for what each side is: `u7` is the query the host *writes*, `u6` is the *report
  pattern* the host parses — `CursorSupport.getCursorPosition` (`:83-95`) takes both strings, compiles `u6`
  into a regex, and only ever asks `user6`/`user7`, which is why `u8`/`u9` stay out even though both DA
  queries are answered. `%i` is load-bearing rather than decorative: the reply is one-based, counted from the
  *window's* top (the same arithmetic the painter used, and why the plan, not the parser, computes it), and
  `%i` is what subtracts it back to the zero-based cursor jline hands to its callers. Two refusals are part
  of the advertisement, not omissions from it: `CSI ? 6 n` stays unanswered (`Render.cpp:1230-1235`, whose
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

* **A partially failed paint tells the model the paint succeeded.** Found by re-reading the flush, not by any
  gate, and deliberately not patched yet. `paint_flush` watches its two *moves*: when the slide or the buffer
  scroll does not land, `movedAsPlanned` drops to 0 (`RenderJni.cpp:616`, `:627`) and the anchor claim is not made
  but reversed -- `rc_drop_base` at `:638`, which "therefore marks the damage" (`Render.h:409-412`) so the next
  flush re-derives the address and repaints rather than writing rectangles at rows nothing owns. The host gate
  pins that promise (`RenderCheck.cpp:2761-2764`: after a drop, row 35 is dirty and the plan re-derives the same
  `row0` an unclaimed model gives). The *cells* have no such watch. The run loop `break`s on the first failed
  `write_rect` (`RenderJni.cpp:671-677`) -- correctly, because "the row below would land in the wrong place" --
  and then falls through to `rc_paint_done(g)` at `:731`, which is `pendingScrolls = 0; rc_clear_dirty(g)`
  (`Paint.cpp:229-233`) and clears the whole array by `memset` (`Render.cpp:261-264`). The rows the refused runs
  owned are still unpainted on the console while the model calls them current, nothing re-marks them, and if any
  earlier run landed then `landed` is already 1, so the flush reports `FLUSH_PAINTED`. The divergence is silent
  and lasts until something else rebuilds the base -- a geometry change, `readopt`, a collapse.
  *What is and is not claimed*: no leg has ever produced it, and that is counted rather than remembered -- every
  witness of this build under `cache/gate13/` and `cache/witness/` prints `apiErrors=0`, **250 readings and not
  one non-zero**, and the string a refused run writes into `lastError` (`"rect r<top> x<n> c<lo>..<hi> =<e>"`,
  `RenderJni.cpp:674`) appears in no file there. So the shape is reasoned from the code and nothing else; it needs
  a `WriteConsoleOutputW` to fail in the middle of a *multi-run* plan, which is also why the gates' own `fails=0`
  does not by itself cover it. It is a weaker thing than the move failure
  it is contrasted with -- a refused move corrupts *addresses*, which is why it self-heals; a refused run
  corrupts *contents* of rows whose address the model still knows right. Two fixes: **(a)** make the clear
  row-accurate -- `write_rect` reports the row it stopped at, the flush clears dirty up to there and leaves the
  rest marked, keeping the claim (it is still correct); **(b)** reuse the move path -- on run failure call
  `rc_paint_done(g)` then `rc_drop_base(g)`, in that order because the drop *is* the re-mark. (b) is three lines
  and needs no new primitive, at the cost of a whole-viewport repaint on the next flush. Taking neither now:
  `D:\dbcli\lib` is closed to deploys while another agent develops there, the live gate runs against the deployed
  dll, and a patch would invalidate every number in §10 without a leg able to show it working. Same family,
  smaller stakes, also unfixed: `SetConsoleTextAttribute` at `:685` and `SetConsoleCursorInfo` at `:699` ignore
  their returns, so an attribute or a cursor shape the host refused is still asserted by the model.

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

## 10 Task ledger: the thirty-six tracked tasks

This section exists so a later reader can re-walk the work without re-deriving it from the transcript. It is a
map, not a narrative: one row per tracker task, and each row says **where the behaviour lives**, **what proves
it**, and **what that proof printed most recently**. The tracker's own subjects are quoted verbatim (they are
Chinese, and re-wording them would break the join); the ordered list of all 36 is kept in
`D:\dbcli\cache\trace\taskdump2.txt`, one subject per line, line *n* = task *#n*.

How to re-run the two standing gates, which carry every `render.dll` task between them:

* **Host gate** — `wsl.exe -d Ubuntu-22.04 -- bash -lc 'cd /mnt/d/dbcli && bash src/c/conemu/build.sh'`. It
  compiles `RenderCheck.cpp` against the console-free core and runs it natively. The passing line is
  `checks=3072 fails=0` followed by `RENDERCHECK: ok`, in `cache/native-probe/out/rendercheck.txt`. The trap
  worth recording is that `build.sh --no-colorcheck` **does not run the host gate at all** — the output simply
  has no `RENDERCHECK:` line, so a run that skipped it looks like a run that passed. Check for the line.
* **Live gate** — `pwsh -File src/c/conemu/run.ps1 -Arch both`, and it must be given a real console (Git Bash
  is not one; the established wrapper pattern is a `.cmd` under `cache/gate13/` started with
  `cmd /c start "" /min /wait cmd /c …`). Both bitnesses must pass: `checks=4648 failures=0`, `RENDERGATE: ok`,
  `STAGE0 RUN: ok`, currently at `cache/gate13/gate13.txt` — x86 census at line 413, x64 at line 827.

The artifacts these numbers belong to: `lib/x86/render.dll` `3cc1fc150c2a79ef98c4996eeac6fc84`,
`lib/x64/render.dll` `f56e9fe42f74a1e9778c5b45e5de9892`, both stamp `render-2026-09-25-13`
(`lib/dbcli.jar` `2297d5175ca1b499caed802f828ef53f`, `lib/JLine3.jar` `94bb0670b2f5819bcb57a6fb30fcff6a`). A row
that cites an older build says so, because "the gate is green" and "this task was witnessed against the DLL that
ships" are different claims.

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
| 2 | OSC 族不再静默：分类计数 + 标题落地全链路收口 | `Render.cpp:1354 osc_start`, `:1574 osc_finish`; `RenderJni.cpp:708-722` applies the title with `SetConsoleTitleW` and counts a failure into `lastError` | host `gm_osc`, `gm_osc_family`, `gm_dropped`; live `caseOscTitle` (`"a title is not a rectangle"`, `"an abandoned title"`). -13 census: `titles=3 (1 truncated), 3 applied` (`gate13.txt:413`) — parsed equals applied, which is the whole claim. |
| 3 | 按 MSFT 参照清单完成 S1/S2/S3/S5/S6-S8/B5 | `Render.cpp` `step_back_col` (BS `:1328`, CUB `:947`), explicit pending-wrap flag, `modelSuspect`, per-row `dirtyLo/dirtyHi` (`Render.h:201`) | host `geo_wrap`, `gm_pending`, `gm_wrap_suspect`, `gm_split_sgr`, `gm_double_esc`, `gm_abandon_and_restart`, `check_resumable`, `plan_damage_range`, `check_damage_bounds`; live `caseWrap`, `caseSuspectAlign`, `caseNarrowRepaint`. In -13 host `3072/0`; the damage bounds print `273 corpus strings x 2 shapes, every damaged row inside a run`. |
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
| 15 | 退格落宽字形尾格：造栅格证人并裁决 | `Render.cpp step_back_col` (:904), used by CUB (:947) and by BS (:1328, which moves and does not erase) | host `geo_wrap`'s `wide back attr` and `wide at cols-2 back`, and `geo_surrogates`' `the replacement takes the whole cell pair`; live `caseWideGlyph`. The reader-typed case is `cache/jnatest/leg-bswide.ps1` — four wide glyphs, one backspace, then two, then an ASCII into the space just erased, each step held mid-edit at U+0001 so the grid shows the cursor at that keystroke; re-run at -13 into `cache/witness/wide1516-20260925-13.txt` as **`#15 VERDICT: ok`** -- `cursor=19,7 r07\|O19C> echo 中文测试` → one BS `cursor=17,7 … echo 中文测 ` → two more `cursor=13,7 … echo 中     ` → `X` at `cursor=14,7`, i.e. every backspace took a whole glyph and parked on that glyph's *first* column, and the ASCII filled one freed cell with no half-glyph residue. All four dumps CLEAN; identical to the -12 witness. §7 item 1 keeps the difference against the retired in-process parser gated on purpose, so the "fix" cannot be restored. |
| 16 | 裁决 reader 行宽：缓冲区 2000 列 vs 窗口 125 列 | ruled **buffer width, not narrowed** (I7); `Render.cpp` run handling, `Paint.cpp` erase-to-buffer-width | host `plan_runs`; live `caseWideBuffer`, `caseEraseToBufferWidth`. Re-witnessed at -13 with one identical 170-char line typed into two geometries (`cache/witness/wide1516-20260925-13.txt`, **`#16 VERDICT: ok for the design claim`**): with a 2000-column buffer and a 125-column window it lands as a single row `4x170` at columns 5..174, `r05` empty, no warning block -- the line is as wide as the buffer, and `cols-used=125` says only that far of it is *viewed*. With the window made the buffer (`-Mode 'cols=125 lines=30'`) the same line **folds rather than trims**: `4x120` on `r07` plus 50 characters continuing on `r08`, cursor `(50,8)`, all 170 present -- so Lua's warning text ("default to be trimmed") describes a path this build does not take; the trimming branch was left unhunted by instruction, and the finding is recorded as a finding. Two things this row must not be read as claiming: the cursor at `124,4` in leg A is not a defect but `Paint.cpp:201-210`, which clamps the *parked* column into the window because conhost slides the viewport sideways to include a cursor it is told about (measured 2026-09-23, same comment), while the model keeps the true column; and this A/B is of line width, not of a scroll -- §9's wide-buffer-scroll leg is still owed. |
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
| 28 | 渲染器 Java 迁到 com.hyee.ansirender | package rename + `RenderJni.cpp` symbols | `build.sh:187` asserts the mangled names, so a half-moved tree cannot link. |
| 29 | 补 DSR/DA 应答腿 + 修 reader 鼠标路径空指针 | `Render.cpp flush_reports` (I29); `LineReaderImpl` mouse path in the jline fork | host `gm_reports`; live `caseReports` (`eqInput`, which reads the reply back off the input stream). -13 census: `replies written=15 (0 failed, 1 refused for a full queue)`, and `mouse=2` counted but not modelled. `u6`/`u7` are advertised in the caps entry (see #12). |
| 30 | 把清点落进 RcUnsupported 计数与 caps | `Render.h` counters; the caps entry | The live gate asserts the counters *as the stream is fed*, so `228: ok the CSI p family and ESC ) c are counted  unrecognised=3` at -13 (`gate13.txt:228`) is a mid-session number with a cause, and the same counter read after the session prints `6` in the census line — one number per decision, and each is checkable against the sequence that earned it. `caseSuspectAlign` is the leg that watches the delta. |
| 31 | 删除已退役的 ConEmuHk 双 DLL | `lib/{x86,x64}`, `copy_to_git.bat` | Backup-then-delete with a manifest: `cache/hk-retire-20260924-183238/MANIFEST.txt` holds both md5s. The consequence for this document is #25's line about the both-leg A/B. |
| 32 | 处置过期的 D:\dbcli\src\java 镜像 | `src\java`, `build-jar.ps1` | Compared first, then archived: `cache/java-mirror-retire-20260924-183622/MANIFEST.txt` and a `tar.gz` at md5 `cf5dca7d…`. §9 records what reading `copy_to_git.bat` corrected. |
| 33 | 定性 Status bar 的两条实机观察 | `Render.cpp line_down` | Both symptoms were ours, not the host's: MSFT's `_DoLineFeed` (`adaptDispatch.cpp:2443-2453`) scrolls only at `y == bottomMargin`. Pinned in `status_bar` on a second grid that asserts `nScrolls == 0` alongside the row contents and the final cursor row, because "no scroll" is the half a correct-looking grid still gets wrong. Live: #23's -13 legs. |
| 34 | 修启动/退出时破坏终端原有文本：全角字重复显示 | `Render.cpp` adopt/align (I4) | `cache/wide-probe/StartupRepro.java` + `su-cmp.py`, four legs at -13: `su13-fit-{raw,render}.txt` and `su13-fill-{raw,render}.txt` all print `verdict: ok  nothing cut, nothing repeated, no hole`, with the raw and render legs reporting the same census (`100 row(s) differ … duplicate pairs 0` at the fit shape, `399` at the fill shape) — the raw leg is the oracle and the render leg does not diverge from it. The in-gate half is `caseRealign` and `caseSuspectAlign` (I4), and the raw-vs-render oracle above is the same one I31 cites. |
| 35 | 修用户上翻时把输出写进 scrollback | `Paint.cpp` — `row0` is never derived from the window top (I30) | host `plan_scroll_band`; live `caseScrollKeepsHistory`. Hand witness at -13, two shapes: `cache/wide-probe/scroll6-room.txt` → `the scrollback the user is reading is untouched (0 rows changed)`; `scroll6-full.txt` → `rode up by exactly 1 row(s), in order (340 rows changed, 0 of them out of place)`. Both `exit=0`. |
| 36 | 让 resize 保住锚点（conhost 的 straddle 规则） | `rc_anchor_adopt` (I28) in `Render.cpp`; `Paint.cpp` refusal | host `adopt_anchor` and `plan_anchor` (`straddle:`); live resize legs through the gate-only `readopt()`. -13, both arches: `ok the resize rebuilt this handle's model, and only its model`, then `resize at winT=0: anchor carried to row 77 of 400, 41 scrollback rows intact` (`gate13.txt:319,332` and `:733,746`). |

Four honest gaps in the table, stated rather than papered over. **Rows #13 and #14 are dbcli's pager and have no
`render.dll` gate at any level** -- their only witness is a live console leg, which is weaker than the rest of
this section and is the first thing to re-run if the pager misbehaves after a jline change; #14's leg is at least
doubled by a `javap` reading of the shipped bytecode, #13's is not. **Row #13's `ceon` leg is unreadable as
witnessed** (the harness's own prompt regex cannot parse a grid that still holds 83 literal escapes), so the row
rests on one leg, not two. **Row #16's ruling now has a produced A/B, and it is the wrong A/B**: what
`wide1516-20260925-13.txt` measures is *line width* across two geometries, not a wide-buffer scroll, so §9's
scroll leg is still owed and deviation 1 still rests on the planner's algebra. And **row #23's legs and the -6
file they replace were run against different jars** (`2297d517…` vs `0ea9b33c…`), so the two agree on the shape
of the status rows and nothing about Java-side behaviour. If a row's witness file is missing, the row is
unproven, whatever the two standing gates say.

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
`writeHk`) exist for the gate, which drives the model one step at a time and reads cells back out of
`conhost`. `build.sh` asserts the export list on every build, in both bitnesses; that gate is what catches
a method written outside the `extern "C"` block as a mangled name.

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
| I4 | `align()` **adopts** the current screen; it does not clear it. | `align_grid` reads the console and copies it into the model | every case's precondition ("align adopts the console"), `caseRealign` |
| I5 | One flush applies in a fixed order: slide → buffer scroll → rectangles → attribute → cursor. | `paint_flush` | `caseScroll`, `caseManyScreens`, `caseNoScrollback` on a live console |
| I6 | Geometry: `hist = rows - winRows`, `free_slide = bufH - winRows - winT`, `slide = min(k, free_slide)`, `bufScroll = k - slide`, `row0 = winTop - hist`, `skip`/`drop` from `row0`. | `rc_plan_paint` | `plan_gutter` on both a wide and a scrolling shape, with every one of those numbers asserted |
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
| I19 | An unsupported sequence is never swallowed silently: **count, and self-heal**. One counter per family. Only `RC_UN_SUP` — "this switch has no case, so its reach is unknown" — marks the frame suspect. Every *known* no-op (mouse tracking, bracketed paste, reports, OSC/DCS framing, modes upstream cases but does nothing for) is counted and leaves the frame trustworthy. The suspect set has narrowed twice: DECSTBM and the alt screen both used to set it and left it when they were modelled. | `unsupported()` / `ignored()`, the self-heal at the end of `flush` and in `align_grid` | `geo_region`'s last block asserts the *current* partition family by family, including "a counted sequence with reach doubts the frame" and "CBT is counted but does not"; `geo_alt`, `gm_wrap_suspect`; `caseSuspectAlign` in the live gate; `report()` prints every non-zero family. Slot indices and `RC_UN_MAX` must never be renumbered — the census is positional on both sides of the seam. |
| I20 | Why a row wrapped is stored per row: `RC_WRAP_FORCED` (the cursor was pushed off the right edge, so the next line continues this one) and `RC_WRAP_PAD` (a wide glyph did not fit and the whole glyph wrapped, leaving a padded cell). Erasing to the edge or moving the cursor explicitly clears it; `scroll_up`, IL and DL carry it. It is not a `CHAR_INFO` bit and never reaches the console. | `rowWrap[]`, set at the four places that can wrap | `gm_wrap_suspect` covers set, clear, carry. A live-console gate is impossible: the bit cannot be read back, which is exactly the `CHAR_INFO` contract in §5. |
| I21 | OSC/DCS are never silent. Titles (`0`/`1`/`2`, with upstream's guard: a digit immediately followed by `;` and a non-empty payload) reach the console; every other family gets its own counter — private 9, other OSC, DCS, unterminated title. Over-long titles are truncated at `RC_TITLE_MAX`, not dropped, and the truncation is counted. A title either lands or is counted; there is no third option. | `osc_finish()`, the payload sink, the title fetch in `RenderJni.cpp` | `caseOscTitle` (applied, painted nothing, counted, truncated at the model's own cap, ST-terminated, private family keeps its own counter and does not change the title, abandoned OSC counted but never applied, DCS counted) |
| I22 | Damage granularity is a **column range**: a dirty row also records `[dirtyLo, dirtyHi]`, and the rectangle write is issued for that range. This is not a narrowing of I7 — the model still stores and can still paint whole buffer rows; the saving is only "columns nobody touched are not rewritten". Ranges are unioned, so a merge can only widen. Two rules bound the risk of painting too *little*: anything that cannot name its range says "whole row" (adopt, `rc_mark_all_dirty`, IL/DL, a scrolled-in row), and the bounds check scans the whole corpus. | `mark_dirty` / `mark_row_dirty` / `rc_mark_all_dirty`; `RcRun.lo/hi`; `build_row` / `write_rect` translate the range into buffer columns | `geo_damage`'s range block, `plan_damage_range`, `check_damage_bounds` (every corpus × every gutter shape, at that shape's own width), `grid_equal` now compares damage too; live `caseNarrowRepaint` and `caseWideBuffer` |
| I23 | OSC 133 (FTCS) is a first-class sequence, not an unknown OSC. One letter in field 0 (`L` takes no option; an unknown letter is a no-op, not a suspect). `A`/`N` start a prompt, adding a line first if there is none — the only place in the family that moves the cursor; `P` is a prompt that does not owe a line; `B`/`I` mark where input starts; `C` marks output start and recovers a fish-style continuation; `D` stamps the nearest marked row **above** the cursor with an exit code and `D` with no code leaves the recorded exit unknown. Marks are per row, model-side only, like I20. Guard: digits immediately followed by `;`, so `]0133;A` and `]1334;A` do not match. | `ftcs_apply()` and its helpers; `rc_row_mark` / `rc_prompt_marks`; the last-exit slot | `gm_ftcs` (per-letter semantics), `geo_ftcs` (marks in the grid and their transport), `caseSemanticPrompt`. One recorded deviation, from the era when a declined chunk went to a second parser: those chunks lost the marks. That path no longer exists. |
| I24 | The alt screen is one behaviour with three codes: `?47`, `?1047`, `?1049` all do the same thing (as upstream's `ASB_AlternateScreenBuffer`), `?1048` saves/restores the cursor only. Entering snapshots the viewport rows; the alt's viewport *is* everything and has no scrollback, so a row leaving the top is gone. Leaving restores. Leaving without entering is safe (the restore is gated on the flag, not the pointer). Scrolling in the alt costs no scroll operation. The only refusal is a failed snapshot allocation — which is why the family's counter means "this one did not happen" and both its slots stayed where they were. | `alt_screen()`, `rc_in_alt`, the `snap*` fields (allocated at this grid's own stride, freed by `rc_reset_hist`, carrying wrap and FTCS marks too) | `geo_alt`, `caseAltScreen`; census "N alt-screen switch(es), M refused" |
| I25 | DECSTBM (`CSI r`) is a region in the model, not a counted refusal. Bounds are clamped to the viewport when set and never re-clamped. Two resets are fixed: a region exactly covering the viewport is recorded as *no region* (the gutter and scroll paths branch on that, and a coincidental full region must not take the other arm), and a bare `CSI r` resets. A geometry change resets it, so a re-opened grid has no region. IL/DL and `scroll_up` work within it. | `case 'r'`, `region()`, `regSet`/`regTop`/`regBot` | `geo_region`; live: `legsSame("DECSTBM then a scroll", …, TRUE)` — the two legs now agree, and the expectation was flipped when the model gained the feature. That test is why `legsSame` exists: two side-by-side bands let the reference leg scroll *outside* the region and both screens came back blank. |
| I26 | The terminfo entry advertises only what the renderer actually models. Absence matters as much as presence: a lying terminfo is worse than a short one, because the reader does not re-check, it complies. | `windows-conemu.caps` in the host's terminal library | `geo_jline_stream` replays the bytes the host's own line editor writes — the 11 acsc letters it emits, `ESC (B` returning them to text, and an in-place edit landing on the right columns |
| I27 | A slot is claimed until it is closed. Ownership (`taken`) and having a model (`g`) are separate; `stats()` and `stopReason()` work on a claimed slot with no model; `open()` claims an unclaimed slot and returns the claim when it refuses. | `slot_of()` vs `handle()`, `open()`, `release_all()` | the four-slot and refusal tests in `caseOpenRefusal`; the census readable after give-up is asserted by the report path in the live gate |

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
`initc`/`ccc` (OSC 4 is consumed, per I21, but the palette does not change), `u6`/`u7` (this parser never
writes a reply back; a caller waiting for one would hang), and `xenl` — measured as absent on every path,
so advertising it would be a lie.

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

The same audit added one capability rather than removing anything, and it is the only string in the entry
that needed a wire test before it could be believed:

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

## 5 Cost model

Measured on a real console with a purpose-built C++ benchmark (200 samples, median, frequency check
included), so that the JVM is not part of the measurement:

| Operation | Median | |
|---|---|---|
| read console view (screen buffer info + cursor info) | 59.1 µs | paid once per flush |
| `SetConsoleCursorPosition` | 35.6 µs | the entire cost of a slide |
| `SetConsoleTextAttribute` | 25.7 µs | |
| `ScrollConsoleScreenBuffer` (one row, whole buffer) | 150.1 µs | 4.2× a slide |
| `WriteConsoleOutputW` | ≈ 40 µs + 43 ns/cell + 1.5 µs/row | fitted on 100×30 / 4096×1 / 4096×30 |

Consequences that shaped the design:

1. **Slide instead of scroll wherever possible** — the plan's first operation exists because it is 4×
   cheaper and moves no cells.
2. **Batching at the chunk level, not the flush level.** The per-flush tax is the console read, not JNI;
   "flush less often" trades that tax against gutter pressure (I9).
3. **Painting to the buffer edge (I7) is charged per cell** — on the default 2000-column profile a
   full-window repaint of 30 rows is about 2.7 ms against roughly 6.3 ms for the old in-process parser.
   Since I22 that number is an **upper bound** rather than a constant: a frame pays for the columns it
   actually dirtied, so a one-cell status line costs one call's fixed overhead, not sixty thousand cells.
   The user ruling that keeps I7 wide is about output correctness, not speed, and this is the cost of it.

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

Current gates, and how to read them: the host gate (`RenderCheck`, cross-run on a Linux host: colour table,
full code-point width cross-check, per-UTF-16-unit resumability, damage bounds over the corpus) and the
live-console gate (`run.ps1`, both bitnesses: the model drives a real conhost, cells are read back, and the
optional reference oracle is the retired in-process parser used purely as an A/B comparison). Both print
totals; quote them only from a fresh run, since the numbers move with the corpus.

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

The generated width table is produced by `gen_ansi_tables.py`, which is not in this tree; the table is
never edited by hand. Regenerate, then re-run the host gate: its width cross-check is the thing that catches
a generator change.

## 9 Open work

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
  `cache/witness/statusbar-live-20260924-6.txt`: bar opened then `help` -- border on the viewport's
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
  The caps half of the same audit is §4's three rulings (`kbs=^H` stays, `kf13` and the shifted arrow names
  stay out, `rep` is now advertised with xterm's canonical value), pinned by `cache/caps-audit/caps-final.txt`
  — 81 ok, which means every string was expanded through `Curses.tputs` and not merely parsed. One
  dependency is outside this library: the entry is a classpath resource, so `rep` and line 1's manifest are
  inert until the owner rebuilds `JLine3.jar`; nothing in this stack emits `rep` at output time, which is why
  no jar redeploy and no new DLL build are needed for it.

* **Who answers `CSI 6n` is a question with two different answers, and the earlier one here was wrong.**
  The editor does not ask, and neither does the line editor on this platform: `AbstractWindowsTerminal` does
  not override `getCursorPosition`, so it inherits `AbstractTerminal.java:251`'s unconditional `null`, and
  the only implementation that would write the query — `CursorSupport.java:83`, reached from the POSIX and
  external terminals — returns early because `u6`/`u7` are deliberately absent from the entry. Nothing on the
  dbcli path stalls on a reply the retired in-process parser used to fake. What the retirement does cost is
  any *third-party* program run inside the console that probes with `CSI 6n` or `CSI c` and waits; that is a
  real but much narrower claim, and it is the one the open answer-leg task should be about.
* **A reachable defect the census turned up, in the host rather than in the model — now closed.** The reader's
  mouse widget calls `terminal.getCursorPosition(...)` (`LineReaderImpl.java:5971`) and dereferences the result
  without a null check at `:5984`. On Windows that call always returns `null` unless `org.dbcli.WinSysTerminal`
  is the terminal in use — `AbstractTerminal.java:251-253` is the null — and the `IS_CONEMU` branch at
  `Console.java:119-122` is exactly what selects some other terminal. The reader's `MOUSE` option is off by
  default (`Console.java:171`) but a `set mouse` switches it on, so the path was user-reachable: enable the
  mouse, release button 1 over the prompt, and the reader threw instead of moving the cursor.
  `Console.enableMouse` now refuses the switch on a terminal that cannot answer the query, and says why.
  Probing `getCursorPosition()` to decide was rejected deliberately — on an ANSI terminal that call *is* the
  `CSI 6n` round trip, and nothing answers it (see the counter at `Render.cpp:1160`), so a probe would turn a
  click-time crash into a start-up hang; the terminal's type decides instead. Witnessed on two live legs: the
  `WinSysTerminal` leg enables silently, the forced-`IS_CONEMU` leg prints the refusal where the NPE used to
  be. The other half of that open item — answering reports — stays a decision not to answer: the model counts
  `CSI 6n`, `CSI c` and window manipulation as `RC_UN_REPORT`, and the terminfo carries no `u6`/`u7` so nothing
  in this host asks. Answering would mean this library writing into the console input buffer, which it does
  not do today and which would leave stray bytes for whoever reads input next.
* **The `winL` gap in narrow rectangles (I22).** `write_rect` translates model columns by `winL`. Nothing
  can produce a `winL > 0` shape in either gate — the live helper pins the rectangle's left edge to 0 — so
  the only witness so far is a real session that happened to be horizontally scrolled. Fix by parameterising
  the geometry helper or adding a gate-only horizontal scroll, then paint one narrow column. Touching
  `RenderJni.cpp` means the build stamp and a full re-run.
* **`rowWrap[]` (I20) has no reader yet.** Set, carried and cleared with full gate coverage, waiting for the
  product that needs it (copy/selection and paging that distinguish hard from soft wraps). Do not optimise
  for it or change its meaning before then.
* **A/B of a wide-buffer scroll** to record deviation 1 above, and the §5 measurement still owed: real
  session wall clock. The existing harnesses have no timers at all, and a 50-line workload is smaller than
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

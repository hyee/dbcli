# JLINE_CHANGES.md — every edit this project made to JLine itself

**Scope.** Anything under `D:\JavaProjects\jline3.29` **except** `dbcli/` (our application) and the renderer's
own Java (`com.hyee.ansirender`, which lives in `dbcli/src`). So: `terminal`, `reader`, `builtins`, `curses`,
`console`, `jansi`, `native`, and their resources. If a file in one of those is not upstream, it belongs on
this page. Files under `dbcli/` are ordinary project code and are documented where they live
(`dbcli/src/org/dbcli/*.java`, the tracker, and `ANSI_TODO.md` §3 for anything that carries a task number --
DESIGN.md's own ledger section is gone since 2026-09-28, and it holds no row numbers now).

**The rule this page enforces.** The renderer is the product; JLine is a dependency. A defect is presumed to be
ours until measurement says otherwise, and a JLine edit is the *last* resort, not the first. Four questions
have to be answered before one is made, and each section below answers them:

1. **Can render.dll absorb it?** The renderer sees bytes in and cells out. It cannot observe a quantity JLine
   compared *before* deciding to write those bytes, and it cannot invent a paint JLine never asked for. When
   the answer is "the bytes never reached us", robustness on our side is impossible by construction — that is
   the only honest justification for a library edit.
2. **Would a JLine-side fix be wrong for every other user of this fork?** A library patch that only makes
   sense for dbcli is a dbcli bug wearing a library costume. Geometry and life-cycle bugs (`resize`,
   `hided`, a scroll region that is never reset) generalise; anything keyed off `OSUtils.IS_CONEMU` does not.
3. **Which side owns the quantity?** "Geometry belongs to whoever draws it" resolved #47 in the library's
   favour and #46 in dbcli's, and both were decided by the same question.
4. **What is the red witness?** A library edit with no leg that fails without it is a guess. Record it, or
   record its absence — see § "What is not witnessed" at the bottom.

**Why the edits are cheap to carry and expensive to lose.** `lib/dbcli.jar` and `lib/Jline3.jar` must be
deployed in the same batch: dbcli's `Console` calls `Status.setBorder(AttributedString, int)`, which does not
exist in an unpatched JLine, so a one-sided swap is a `NoSuchMethodError` at the first status line. And the
tree is being upgraded toward JLine 4.4.6 in parallel by another agent, so every row below is a merge conflict
with a reason attached — that reason is the point of this file.

---

## How to re-derive the diff

The pristine reference is the commit *before* the fork's own history, in the second checkout:

```sh
cd /d/Green/github/jline3.29        # a real jline clone; HEAD a1f0ffc1 is already a fork commit
git log --oneline -3                # c5a8bf12 "baseline before changes for dbcli" is the last stock one
git show c5a8bf12:terminal/src/main/java/org/jline/utils/Status.java > /tmp/base.java
diff /tmp/base.java /d/JavaProjects/jline3.29/terminal/src/main/java/org/jline/utils/Status.java
```

`D:\JavaProjects\jline3.29` has **no commits** (an empty git, everything untracked), so `git diff` there proves
nothing. Compare against `c5a8bf12` blobs, and normalise line endings first — this fork is mixed CRLF/LF
per file, and `diff -q` on a raw pair reports every file as changed.

Against the fork commit (`a1f0ffc1`, not stock upstream) this work stream changed five files:

| File | Differing lines | Ours, or the fork's? |
|---|---|---|
| `terminal/src/main/java/org/jline/utils/Status.java` | 225 | ours (#23, #33, #41, #43, #46's callee, #47, #48, and the `ba06511f` cursor trace). Re-measured 2026-09-29 against the `a1f0ffc1` blob with `diff --strip-trailing-cr \| grep -c '^[<>]'`: **225**, which is the 177 this row used to carry plus the 48 lines `ba06511f` added and nothing else -- the Green HEAD blob and `D:\JavaProjects\jline3.29`'s working copy are byte-identical, so no drift is hiding in that delta. |
| `terminal/src/main/resources/org/jline/utils/windows-conemu.caps` | 33 | ours (#10, #12, #19, #29, #90, plus the 2026-09-28 prose-only pass below -- re-diffed against `a1f0ffc1` the same day and still 33 differing lines, 17 added / 16 removed) |
| `reader/src/main/java/org/jline/reader/impl/LineReaderImpl.java` | 39 | ours (#41) |
| `reader/src/main/java/org/jline/keymap/KeyMap.java` | 4 (:624, :634) | ours — the 2026-09-13 terminal-input round: `unbind` compared `c > map.mapping.length` and threw AIOOBE at the exact boundary; both sites are `>=` now. The rest of KeyMap's divergence between the checkouts (+238/-3) is the 2025 fork commit, not ours — the paragraph below used to wave the whole file away as "not this work stream's", which was wrong about the 4 lines. |
| `terminal/src/test/java/org/jline/utils/StatusTest.java` | new file | ours (#47, #48) |

**What is *not* a JLine change, even though it lives in that tree.** `dbcli/src/com/hyee/ansirender/`
(`NativeRenderer.java` and its peers) does not exist in `a1f0ffc1` at all -- verified 2026-09-26, and
`git show a1f0ffc1:dbcli/src/com/hyee/ansirender/NativeRenderer.java` says the path is not there. It is this
work stream's own code, parked in the JLine checkout because that is the tree whose build produces
`lib/dbcli.jar`. So a slot-table edit there (#89's `SLOT_ARGTRUNC`) is **not** a row in the table above and does
not need one; what does fire this rule is a change to a file JLine ships, which is why the caps entry has both
a row and a section (#90). Re-verified 2026-09-27 for the two files #99 touches:
`git cat-file -e a1f0ffc1:dbcli/src/org/dbcli/WinSysTerminal.java` and the same for `Console.java` — both
**ABSENT**, as they are at stock `c5a8bf12`. So #99 edited none of JLine, and its section below exists by the
owner's request, not by this page's scope rule. Read that section's first line before quoting it as "a library
patch".

What is **not** this work stream's, though it differs between the checkouts: `utils/Display.java`
(modified in both working trees — Green's git shows it, and the two trees match each other), and
`console/src/test/.../TailTipWidgetsTest.java` (Green is *ahead* of the working tree there — the repo copy
has the fork's `isSupported()` the tree copy lacks). Do not "fix" those against `c5a8bf12` — they are
somebody else's in-progress port. `changelog.md`, `console-ui/doc/howto.md` and
`console-ui/doc/ConsoleUI-Logo.svg` differ by line endings only (autocrlf smudge) — verified
content-identical modulo `\r` on 2026-09-28, not changes.

Two tree files uncommitted since the fork era **ship inside `lib/Jline3.jar`** — verified 2026-09-28 by
listing the deployed jar: `terminal/src/main/java/org/jline/utils/DisplayTopTest.java` (2025-05-05, a
top-like repaint scratch driver; its `.class` is in the jar) and
`native/src/main/resources/META-INF/MANIFEST.MF` (2025-05-02, `Main-Class: org.jline.demo.TerminalDemo`,
in the jar too). Not ours either, but the repo must be able to rebuild the artifact.

**Repo sync, 2026-09-28 (local only, never pushed).** `D:\Green\github\jline3.29` commits: `1310cb95` =
the four rows above (Status/caps/LineReaderImpl/StatusTest); `a8373a53` = the KeyMap 4-line fix plus the
two fork-era jar-carrying files. `Display.java` was deliberately left unstaged in Green.

**A fifth commit landed after that paragraph was written: `ba06511f`, 2026-09-28 14:14:52, one file,
`Status.java` +48/-0** -- an opt-in cursor trace, recorded in its own section below because it is the last
commit in that repository and the merge table above pre-dates it. Push state re-read 2026-09-29: `master` is
`[origin/master: ahead 4, behind 1]`, so none of these four commits has left the machine, and `origin/master`
carries one commit this checkout does not (`5fbbdc39 "fixed by AI"`). "Never pushed" still holds; "and the
remote is behind" does not.

## `terminal/src/main/java/org/jline/utils/Status.java` -- MovingCursorDisplay moves by CUP only (2026-09-29)

**The defect.** Every `Status.update()` repaint fed the terminal a burst of bare line feeds. The chain:
`MovingCursorDisplay.update` calls `super.update`; `Display.update`'s "top mode" tail (Display.java:397-400,
a *fork-added* block -- absent from stock c5a8bf12, present in both this tree and the jline4 merge at :830)
parks the cursor on its own last row via `moveVisualCursorTo((rows-1)*columns1)`; the non-fullscreen
down-move of stock jline (`Display.moveVisualCursorTo`, :541-544) spells that as `carriage_return` plus N
bare `'
'`. The bar repaints on the rows its own DECSTBM reserved -- top at the screen top -- so each LF
at the bar's last row scrolled one viewport row into the terminal's scrollback. Measured on the production
pseudo-console leg (`conpty_probe run`, dbcli, two `help`s): **451 history pushes of which 271 blank**, in
blocks of exactly 27 (30-row window, 2-row bar), one block per status repaint. The same emitter on the
render.dll leg was #122's "x9 idle resend": one source, two symptoms.

**The fix.** `MovingCursorDisplay` already owns the local-to-physical frame (`firstLine`); it now overrides
`moveVisualCursorTo(int)` to address every move absolutely (`cursor_address(firstLine + row, col)`) instead
of walking relatively. A bar repaint now emits zero line feeds. CUP clamps out-of-range rows to the screen
edge on every terminal in scope, which is how the park's local row (rows-1) maps to a physical row beyond
the screen without scrolling anything to get there. `Display.java` itself is untouched: its LF down-move is
correct for the reader's Display, where moving past the bottom is output growing the screen.

Four questions: (1) render.dll cannot absorb it -- the defect fires on the vtp path where render.dll is not
in the write path, and on the conemu path the bytes are jline's output either way; (2) the fix generalises --
an overlay repaint that scrolls the screen is wrong for every consumer of Status, on any terminal (Linux
xterm included); (3) the quantity (cursor moves during a bar repaint) is Status's own; (4) red witness:
`StatusTest.barRepaintMustNotFeedLineScrolls` failed on the pre-fix bytes (emitted tail `\E[22A\E[79C \E8`
matching the live capture `ESC[28A ESC[119C ' '`), 7/7 green after; end-to-end on deployed bytes: blank
scrollback pushes **271 -> 0**, `Available comands` exactly x2, banner x1, both help tables pushed once each
(`cache/p123x/h2pty2.bin`).

Deployed: `lib/Jline3.jar` `8b735dd2...` -> `1509863f...` via `jar uf` of the two `Status*` class entries
only (entry set unchanged, audit `cache/status47-48-20260925/crc-Jline3.jar-{before,after}.txt`);
`lib/dbcli.jar` untouched at `bf34aa95...` -- the deploy script's second `ship` also swapped in a tree-built
`Console.class` of unverified provenance and was rolled back from the timestamped backup immediately.

## `terminal/src/main/java/org/jline/utils/Status.java` -- the `ba06511f` cursor trace, and what it settled

The commit adds one private method and four call sites inside `resize(Size)`: `trace("before", null)` right
after the opening `save_cursor`, then `grow-after-csr` / `grow-end` on the give-rows-back branch and
`shrink-end` on the take-rows branch. It writes only when `DBCLI_STATUS_TRACE` names a file, reads the cursor
back through `terminal.getCursorPosition(i -> { })` rather than inferring it, and swallows every throwable --
a diagnostic that can break the bar is worse than no diagnostic.

**What it bought, in the commit's own words and now on this page:** four competing readings of `resize()`
were settled on one Windows Terminal run (rows=65, 2-row bar). The shrink branch does **not** lose the cursor
(`cursor_was == cursor_now`, twice); the grow branch compensates exactly by the scroll delta; therefore the
asymmetry that looked like the fault is not one. The stray empty prompt line is the **application's**:
`Console.setStatus`'s off branch called `suspend()` and its on branch never called `restore()`, so a real
title reached an `update()` that drew nothing. That half is already fixed and shipped -- `Console.java:582`
carries the `restore()` with the diagnosis in the comment above it, and the deployed `lib/dbcli.jar` shows
`Status.close`/`suspend`/**`restore`**/`resize` in `setStatus`'s bytecode, so this is a closed item, not a
todo. Also reverted in that session and never committed: sizing `LineReaderImpl`'s prompt from
`visibleDisplayRows()` and folding it into the WINCH gate -- "the arithmetic already agreed at 63 and the
symptom did not move". Do not re-derive it from the tree; it is not in the tree.

**Not merged into jline4, and that is a decision, not an oversight.** `DBCLI_STATUS_TRACE` is 0 hits across
`D:\JavaProjects\jline4` and 0 hits across `D:\Green\github\jline4`, 0 hits in the `Status.class` inside the
shipped `cache/jline4-build/out/JLine4.jar` (`javap -p` there shows no trace or cursor member), and 1 hit in
the `Status.class` inside the production `lib/JLine3.jar` -- so the instrument exists only on the side that
wrote it. The port is mechanical if it is ever wanted: all four anchors already exist at the same shape in
jline4's `resize(Size)` (`:305` save_cursor, `:312`/`:327` the two branches, `:319`/`:328` the two
`change_scroll_region` puts), and the one API the trace leans on is present (`Terminal.getCursorPosition(IntConsumer)`;
jline4's `Cursor` is a class rather than 3.29's interface, which the trace cannot tell because it only reads
`getX()`/`getY()`). Two things to decide before porting it, both already argued elsewhere on this page: the
env name says `DBCLI_` on a library file (port it under that name and record the deviation, or rename and
break the muscle memory of the 3.29 legs), and a diagnostic with no question attached is dead weight --
the question it answers on the jline4 side would be the #98 family ("the prompt lands inside the bar's rows"),
which is still open there.


---

## `terminal/src/main/java/org/jline/utils/Status.java`

The status bar is a scroll region plus a reserved band at the bottom of the window, and JLine owns both
quantities. Before this work it owned them inconsistently: three handlers disagreed about what "the bottom"
meant, and one of them reserved rows it had already handed back.

| What changed | Why | Why render.dll could not absorb it |
|---|---|---|
| `resize(Size)` (:157-181) now erases the bar at the **old** geometry and redraws it at the new bottom, and hands `scrollRegion` back to `display.rows - 1` when the bar is hidden. | A bar cannot be resized in place: its rows sit at the bottom of the window that no longer exists. It used to be closed on a resize and only came back if something called `setStatus()` again — a session parked at a prompt never does, so resizing lost the bar outright. | The renderer is never invoked. `resize()` decided not to write anything; there is no chunk to make robust. A paint-side workaround would mean guessing where the bar was from cells, which is exactly the ambiguity that created the bug. |
| The gate compares **window** sizes (`size` vs `display.rows/columns`), and `prevWindow` was added to `LineReaderImpl` for the same reason. | `terminal.getSize()` is the window, `getBufferSize()` is the buffer — 2000x9001 on a classic console. Dragging an edge moves only the window, so a handler gated on the buffer compared a constant, no-oped after the first resize, and left the bar painted at the bottom of the window as it was *then*, mid-screen. | Neither quantity is a pixel, a cell or a byte. It is a Java field choice, upstream of every write. |
| `hided = false` moved into the drawing branch, so it is reached whether or not the border is on (:258-269). | `resize()` reads `hided` twice — as "repaint?" and as "hand the rows back". Only the borderless branch ever cleared it, so a bordered update left the flag set and the next resize did **both** jobs wrong: the bar froze at the old geometry *and* its rows fell inside the text area (#48). | `hided` is library-internal state the renderer cannot see and cannot invalidate. |
| `hide()` stops discarding the lines it erases; `redraw(true)` treats an empty model as "no bar", not "a bar of zero rows" (:199-208). | Three callers had nothing left to redraw after a hide, and `Console.readLine()`'s `finally` calls `redraw(true)` for sessions that never showed a bar — where the old code flipped `closed` to false and rewrote the scroll region for a bar nobody asked for. | Both are lifecycle facts about an object graph, not output. |
| `setBorder(AttributedString, int)` + `getBorderString(columns)` tile a **template** to the live width; the border row is recomputed inside every `update()` (:127-151). | The separator *is* geometry, and dbcli had been building it as text: `Console.setStatus` minted a fresh run of `-` at `width-1` and stuffed it into `titles`. `Status` can only re-send what it was given, and `update()` pads a short line with spaces, so a 99-dash rule on a 145-column screen looked full-width to everything downstream and no repair was possible below that point (#47). | The renderer faithfully paints a 99-dash string. There is nothing wrong at the cell level to be robust about. |
| `size()` is the accessor dbcli's `getScreenHeight()` uses now, in place of a `titles.size()` guess (#46). | A proxy that counts title lines is not a quantity the bar maintains, and after #47 the two definitively differ (the border left `titles`). | dbcli-side call, but the *accessor* is the library change that made the honest answer available. |

**Witness.** `terminal/src/test/java/org/jline/utils/StatusTest.java` (added) — 6 cases, and every assertion is
on the **bytes handed to the terminal**, never on a grid rebuilt from those bytes. Current state,
`bash cache/status47-48-20260925/run-test.sh`: `tests=6 found=6 succeeded=6 failed=0`.
Red control, run today by compiling a `/tmp` copy of `Status.java` with only the `hided` block reverted to its
pre-fix shape and putting it first on the classpath: `tests=6 succeeded=4 failed=2`, the two failures
`borderedBarIsRedrawnByResize` and `customBorderIsRetiledToTheNewWidthOnResize` — i.e. that one-line revert
reproduces #47's *and* #48's symptom, which is the clearest evidence the two are the same fault line.
Live legs (`conpty_probe --host auto`, idle frames) are in `cache/status47-48-20260925/`:
red `h-after-00/01 cols=145 rule at row 33 dashes=99 want=144 STALE`, green `i-after-00/01/02 dashes=144 want=144
match`, one rule row on screen, no residue. `selftest --leg both` 16/16 before either.

### 2026-09-28 — an opt-in cursor trace, and what it ruled out (no behaviour changed)

`Status.update()` gained a `trace(where, newRegion)` call at the three places the scroll region moves
(`before`, `grow-after-csr`, `grow-end`, `shrink-end`) plus the `Cursor` readback it needs
(`terminal.getCursorPosition(i -> {})` → `org.jline.terminal.Cursor`, whose accessors are `getX()`/`getY()` —
there is no `getRow()`/`getColumn()` in 3.29, and that cost two failed builds). It writes **only** when
`DBCLI_STATUS_TRACE` names a file, so nothing changes for anyone who does not set it.

It exists because four readings of this method had produced four different mechanisms for the report
"`set status off` then `set status on` leaves an empty `SQL>` one row above the line you are typing on", and
each reading had produced a code change. The trace settled it in one run on the owner's Windows Terminal
(`rows=65`, bar 2 rows, usable 0..62):

- **The shrink branch does not lose the cursor.** `shrink-end cursor_was=62,0 cursor_now=62,0`, twice. So the
  asymmetry I had read as the fault — grow restores the cursor after `change_scroll_region`, shrink does not —
  is not a fault. The `restore_cursor` the shrink branch does not need is the one it never loses.
- **The grow branch compensates exactly.** Two cycles, cursor 64→62 and 63→61, each up by the scroll delta.
  The `Math.min(scrollRegion, terminal.getHeight())` clamp ahead of the loop does not distort the count.
- ⇒ `Status` is cleared of the symptom. The extra prompt line is the **application** drawing it, and the
  paired defect is in `Console.setStatus`: the off branch does `close()` **and `suspend()`**, `update()`
  returns at its first line while suspended, and the on branch — which delivers a real title and nothing
  else — never calls `restore()`. Measured on the headless leg at 120x30: before the one-line fix
  `set status on` left **no bar row at all**; after it the bar is back at row 29 with the cursor on its own
  prompt row. The fix is in `dbcli/src/org/dbcli/Console.java`, not here, so it is recorded in
  `ANSI_TODO.md` as well; it is noted here because the library's `suspend()`/`update()` contract is what makes
  an off branch unrecoverable without an explicit `restore()`, and any future caller needs to know that.

**Reverted, so nobody re-does it:** `LineReaderImpl` was changed the same day to size the prompt from
`visibleDisplayRows()` (window minus bar) and to fold that quantity into the WINCH gate, on the theory that a
bar row-count change was invisible to the editor. The arithmetic was already consistent — `newScrollRegion`
and `visibleDisplayRows()` agree at 63 — and the symptom did not move. Reverted with `git checkout`; the file
is at HEAD. The WINCH-gate observation stands on its own (a bar change does not move the window, so a raise
from `Console` is swallowed by `window == prevWindow`), but it is **not** this bug's cause and was not kept.

## `dbcli/src/org/dbcli/WinSysTerminal.java` (#99) — recorded here on request; **it is not a JLine edit**

Requested as "记录本次对 `Status.java` 重绘逻辑的修改及归因". The attribution moved during the investigation and
the file that changed is this one, so the honest headline goes first: **`Status.java` was not touched for #97 or
#98.** Both stay open on the JLine side, and if one of them is ever patched, its row belongs in the section above,
not here. What #99 fixed is one layer further out: the branch that decides whether `render.dll` is on the
painting path at all. It is on this page because the owner asked and because it is load-bearing for the renderer
— but per the scope rule at the top, no JLine file was edited (`git cat-file -e a1f0ffc1:dbcli/src/org/dbcli/WinSysTerminal.java`
→ absent, re-verified 2026-09-27; the file is ours, sitting in the tree whose build makes `lib/dbcli.jar`).

| What changed | Why | Why render.dll could not absorb it |
|---|---|---|
| `conemuClaimed` (:114 then, :121 as re-measured 2026-09-28) is computed before the branch, and the ConPTY branch is now guarded by `!conemuClaimed` (:116 then, :123 now; the `else if (conemuClaimed)` arm is :131). The block moved down 7 lines when #103 added its WARNING comment ahead of the declaration -- cite the symbols, not the numbers. An explicit `ANSICON_DEF=conemu` therefore outranks `NativeRenderer.pseudoConsole()`. | Under Windows Terminal `pseudoConsole()` is `true`, so the old chain short-circuited into `newConsoleWriter` and never reached the `ConEmuWriter` branch below it. The whole session painted without the renderer, and **nothing said so** — `ConEmuWriter` is the only caller in the tree that reports `unavailableReason()`, and it was never constructed. `Console.java:108-126` accepts `conemu` as a mode, so both ends of the stack looked like "the renderer will run"; the swallowed branch was in between. | The renderer is given bytes by a writer. If the writer is a different class, no amount of parser work can be reached — there is no call to make robust. This is the "the bytes never reached us" case, one level further out than any of #47/#48. |
| `ANSI_RENDER_LIB` deleted in the same batch (#100): `libDir()` and both fallback arms in `loadLibrary()` are gone; the failure sentence now names the two channels actually tried. | The owner's words: "没有这种问题，不需要这个变量". The variable was read only after `System.loadLibrary("render")` threw, and the launcher has `lib\x64` on `PATH` — none of the five arms below set it, and all four renderer arms came up `ENGAGED`. One more environment variable is one more thing a user must know. | Nothing: the renderer's absence was never the fallback's job. Recorded here because it is the same deploy and the same owner decision, and because it removes a switch that `ANSI_TODO.md` and `DESIGN.md` both used to name. |

**The four questions, for #99.**
1. *Can render.dll absorb it?* No — the class that chose the writer ran before the renderer existed in the
   process, and `pseudoConsole()` itself lives on our side of the seam.
2. *Wrong for every other user?* It is not a library statement at all, so the question does not bind; the
   dbcli-only smell is exactly why the reversal is keyed to an explicit `ANSICON_DEF=conemu` and not to
   `OSUtils.IS_CONEMU`. With the variable unset, #37's rule is byte-for-byte the rule it was.
3. *Which side owns the quantity?* The **user** does. `ANSICON_DEF` is written by ConEmu's own `init.cfg`, and
   the owner's standing position is "以前是设了 `ANSICON_DEF` 就调用了 render" — a heuristic that reads the host's
   mind may not overrule what the user typed about their own terminal. That is also why this is a reversal
   rather than a compromise: the cost is knowingly paid (row below).
   ⚠ Measured 2026-09-28 (`cache/conemu102/run8.sh`, six arms, `judge8.py` = PASS 32), and it is sharper than
   "the user does": **ConEmu owns it, and the user reaches it only through ConEmu's configuration.** Inside a real
   ConEmu window a `set ANSICON_DEF=conemu` in the shell does not take (`cache/conemu102/tset.txt`: the same
   script changes a neutral variable to `hello` and leaves `ANSICON_DEF` at `7`, before and after), and neither
   does one inherited from the launcher (`conemu-claim` arm: `ConEmu64.exe` started with `ANSICON_DEF=conemu` in
   its own environment still gives the child `7`). So the claim is unreachable from any batch file, wrapper or
   `dbcli.bat`, and only `data\init.cfg` (or ConEmu's palette setting) can raise it — which also means a ConEmu
   session on this box runs `enableVtp` successfully and therefore takes `windows-vtp` with
   `org.dbcli.WinConsoleWriter`: **the native renderer is not on the paint path in a stock real-ConEmu session**,
   and the arm that shows it *can* be reached is the classic-conhost one (`sim-claim`: `conemuClaimed=true` ->
   `type=windows-conemu` -> `writer = org.dbcli.ConEmuWriter`).
4. *Red witness?* The five-arm matrix, and the failure of its first version — both are in the next two
   paragraphs, because the failure is the part worth carrying.

**The cost, written where it cannot be missed.** `WinSysTerminal.java:107-113` carries a WARNING in the source:
this restores precisely the defect #37 measured and #38 was filed to remove — under a pseudo-console a write of
cells is re-serialised into escapes by something that does not know the model, so rows an adopt merely *read*
(cmd's own listing among them) leave the process as **new output** and land in a scrollback that is not ours.
It applies to every WT session that sets `ANSICON_DEF=conemu`. `ANSI_RENDER=off` is the way back:
`ConEmuWriter` then holds no renderer and every write goes out raw, which is always correct and only slower.
Ledger: `ANSI_TODO.md` §3 rows #37, #38 (both now say who yielded) and #99; ANSI_TODO #99. (Those rows were
in DESIGN.md §10 until that section was removed on 2026-09-28.)

**Witness — five arms, one process each** (`cache/t5-ship46/`, driven by `run-wt.ps1` + `run-classic.ps1` +
`cell.cmd`; every `.cmd` in that directory is ASCII-only for the codepage-936 reason recorded in `cell.cmd`
itself):

| arm | bytes the report says it ran | `PTY` | env | verdict |
|---|---|---|---|---|
| `wt-noenv-old` | `old/…` `SHA=914c1afc81f4a7e7dabf2b8bcd2487bc` `SIZE=17087` (pre-#99, from `cache/audit90/dbcli.jar.20260927-221336.bak`) | true | `ANSICON_DEF=conemu`, `WT_SESSION` cleared | `windows-vtp` / `RENDER=off` |
| `wt-noenv` | `jar:file:/D:/dbcli/lib/dbcli.jar!/…` `SHA=96e3297ebf4bcccc248d6c86727b6b2d` `SIZE=17132` | true | same | `windows-conemu` / `RENDER=ENGAGED` |
| `wt-native` | same as above | true | host's own (`WT_SESSION` set, `ANSICON_DEF` unset) | `windows-vtp` / `off` — #37's defence intact |
| `classic-clean` | same as above | **false** | `ANSICON_DEF=conemu` | `windows-conemu` / `ENGAGED` |
| `classic-fake` | same as above | **false** | `ANSICON_DEF=conemu` + faked `WT_SESSION` | `windows-conemu` / `ENGAGED` — #38's original test still holds |

The first two rows are the red/green pair: same window kind, same environment, `PTY=true` on both, and only the
class bytes differ. The `PTY=` field is not decoration — with `PTY` null or false the pre-#99 chain reaches the
ConEmu branch by itself, so a cell that answers `windows-conemu` without `PTY=true` proves nothing about the
override.

**How this leg was nearly a false green, in two ways.** (1) The version of `TermType.java` before this run
printed only `TYPE`. Its control arm came back with the *same* answer as the patched arm, and the tempting
reading was "the patch is a no-op". The real cause: the extraction step had a failed `cd cur`, so `jar xf`
dumped the **current** class into the control directory — both arms ran the same bytes. The probe now prints
`WINSELF=<code-source URL> SHA=<md5> SIZE=<n>` read through the same classloader the JVM used, which is what
caught it (`old/` said `17132`, not `17087`). (2) Earlier in the same investigation two attributions for this
symptom were made and retracted: an A/B that flipped `DBCLI_NATIVE_RENDER`, **a variable that does not exist**
(the real one is `ANSI_RENDER`), which produced "the renderer makes no difference" from a switch nobody could
pull; and a "the renderer paints the prompt into the status row" claim read off `ReadConsoleOutputW` inside
Windows Terminal, where that call reads conhost's shadow buffer rather than what is on screen. Both are wrong
in the direction of blaming the wrong layer, which is why they are written here instead of deleted.

**Deploy.** `lib/dbcli.jar` `4279e40341c27f46907b5c1bb57d418d` (682853 B) — #99 + #100 together; the
#99-only batch was `05662fcb57dba8c10e89e04147f8d204` (683107 B), and the pre-#99 jar is
`cache/audit90/dbcli.jar.20260927-221336.bak`. Built whole-tree (`cache/task38-deploy-20260925/build.sh`,
112 classes, under Git Bash — WSL has no `cygpath`), and both changed entries were compared against the build
output byte-for-byte after `jar uf`: `WinSysTerminal.class` `96e3297e…`, `NativeRenderer.class` `4ad96ace…`.
`ANSI_RENDER_LIB` is gone from the shipped bytes (`javap`: 0 hits for the string, 0 for `libDir`).



## `reader/src/main/java/org/jline/reader/impl/LineReaderImpl.java`

| What changed | Why | Why render.dll could not absorb it |
|---|---|---|
| `prevWindow` field (:216-218, seeded at :839); the `WINCH` branch (:1276-1307) gates on `terminal.getSize()` instead of the buffer, and ends with `status.resize()` instead of `status.close()`. | `LineReaderImpl` installs its own WINCH handler for the duration of `readLine()` (:684 installs, :813 restores), so **this is the handler that runs while the user sits at `SQL>`** — fixing `Console.handleResize` alone fixed the resize that happens *between* commands and not the one that happens during them. Same window-vs-buffer confusion, same silent no-op. | The handler returns before writing anything. From inside the renderer the session looks idle. |

Two things this row must not be read as claiming. It does **not** touch mouse handling: `mouse()` (:5988) still
dereferences `cursor.getY()` unchecked, and the guard against that NPE is in dbcli
(`Console.enableMouse` refuses to switch the mouse on for a terminal type that cannot report its cursor),
deliberately — the library's behaviour for a null reply is somebody else's contract. And the `#41` fix is split
across three WINCH owners (`LineReaderImpl` while reading, `More.handle` while paging,
`Console.handleResize` otherwise); all three needed it, which is itself an argument for the library owning
`resize()` rather than each caller reimplementing it.

**Witness.** Live, five real-window arms (WT grow, two-step resize, one-row resize, classic shrink, no-resize
control) in `cache/resize-fix-20260925/`: bar present and on the last row in all five, *absent* pre-fix after any
shrink. No unit test covers `LineReaderImpl` — the fork has no harness for a reader sitting on a signal.

## `terminal/src/main/resources/org/jline/utils/windows-conemu.caps`

Not a code change but the library's **client contract**, and the one place where this project's own rules
(I26: advertise only what is modelled) bind a JLine file. `xenl` was measured and then *removed* rather than
added to anything (#10, with a live A/B); `rep`, `u6`/`u7`, `smacs`/`acsc`, `csr`, `indn`/`rin`/`nel`,
`ich`/`dch` and the `sgr`/`setaf`/`setab` forms were added or corrected against what ConEmu's parser and this
renderer both actually act on (#12's audit, #19, #29); **`cbt=\E[Z` went in last, in #90**, and it is the only
addition here that does *not* pass that both-parsers test -- see the rule two paragraphs down; `ncv`, `blink`,
`invis`, `mir`, `smam`, `smkx`, `flash`, `initc`/`ccc`, `kbs`, `kf13`+, the shifted-arrow names and now
`hts`/`tbc` were kept **out**, each with its reason inlined in the entry's description line.

**The rule in the entry's first line was too wide, and #90 narrowed it.** It read as one flat AND -- "every
string here is one CEAnsi really acts on AND the native renderer models" -- which is a rule about the strings
this stack *writes*. A name a reader only uses to *decode bytes the host sends* has a different truth condition:
does the host send them? `cbt` passes that test and fails the other one. Its only consumer in this JLine is
`LineReaderImpl.java:6420`, which binds `REVERSE_MENU_COMPLETE` to the value as the **name of the Shift-Tab
key**; `KeyMap.key` is `Curses.tputs(getStringCapability(..))` (`:342`), and `KeyMap.bind` (`:589`) drops a null
key sequence without a word. So leaving `cbt` out was never refusing a claim -- it silently unbound a key whose
bytes the terminal already produces, from `kcbt` through `AbstractWindowsTerminal.java:368`, decoded at `:441`.
`hts`/`tbc` are the opposite pair: zero readers (both names occur nowhere outside `InfoCmp.java`'s own table),
and they *would* be written, where CEAnsi ignores `ESC H` and `CSI 3g`. Editing the entry also corrected two
claims in `TERMINFO.md`: the reader citation `:6992` belongs to the jline**4** tree (`:6420` here), and dbcli's
`Console.java:295` binding of `^[Z` does **not** cover Shift-Tab, because JLine reads `^[` as one ESC and the
sequence is three bytes.

**Why render.dll could not absorb it:** the entry is what the reader reads to decide which bytes to write. A
lying terminfo is worse than a short one, because JLine complies with it instead of re-checking — no amount of
renderer robustness undoes `Display` trusting an `am`/`xenl` claim that is false.

**Witness.** `src/c/conemu/CapsDump.java` with `caps_check.ps1` -- its own census line reports 84 expectations executed against this entry, 49 of the 91 declared capabilities named by an expectation and the other 42 carried in a table with a reason each, plus a byte-for-byte comparison of the tree's file against the jar's own copy -- run against the source file
**and separately against the copy inside the shipped `lib/JLine3.jar`** — `CAPS CHECK: ok` on both, byte-identical
(#12). Since #90 it has a third section that reads nothing on disk: it builds JLine's headless
`LineDisciplineTerminal` with type `windows-conemu`, which loads the entry **off the classpath** the way a real
session does, and asks the reader's own `menu` keymap what Shift-Tab binds to — so the shipped jar is the thing
under test, and #90 saw it answer `no cbt to look up` against the pre-#90 jar and `reverse-menu-complete`
against the shipped one. Read the caps entry's own comment before editing it; every omission in it is a
measured result.

**2026-09-28: the description line was edited for its own sake, and it is still a JLine change.** Line 0 is never parsed -- `parseInfoCmp` starts its loop at index 1 -- so behaviourally this pass moved nothing, and the capability fields were asserted byte-identical before the file was written (91 tokens, same spelling, same order; the patch script refuses the write if they shift). It was done because that line *is* the record: it carried seven numeric anchors into `Render.cpp`/`RenderJni.cpp` and every one of them pointed somewhere else by this morning (the `CSI 6n` arm, the `?6n` refusal, `flush_reports`, the tab-stop set, the walk backwards), it called `hts`/`tbc` dropped where CEAnsi in fact files `ESC H` as recognised-and-ignored and has no `CSI g` arm at all, it quoted a "33-byte" DA1 that had silently grown to 36 when the sixel term entered the identification, and its kept-out list never once mentioned `kmous` -- the one capability of the seven upstream has that a reader in *this* tree also consumes. `kmous` is now in the list, with the reason that survives #81 and #95: the modes are stored, answered, carried and armed, and this library still writes no mouse report, so the name would advertise bytes whose sender is somebody else (I26).

Shipping it meant all three copies again, and `jar uf` was used rather than a rebuild: the mirror, `D:\JavaProjects\jline3.29\terminal\src\main\resources\...` and `lib/JLine3.jar` are one byte stream (md5 `f35ea41f7421...` -> `9454e34c5e67...`, 6288 -> 7440 bytes). The jar was audited before and after: 908 entries both times, no entry added or removed, and exactly one entry's CRC changed -- `org/jline/utils/windows-conemu.caps` -- with `META-INF/MANIFEST.MF` untouched; the jar is unsigned and carries no `module-info`, so a single-entry update cannot break a signature it never had. Backup of the pre-edit jar: `cache/tisync/JLine3.jar.20260928-004145.bak`. Both gates ran green against the shipped bytes afterwards: `terminfo_check.sh` (three copies byte-identical at `9454e34c5e67`) and `caps_check.ps1` (tree and jar copy each `CAPS CHECK: ok`, `unexplained=0`).

## `terminal/src/main/java/org/jline/terminal/impl/AbstractWindowsTerminal.java` (jline**4** tree)

**This one is not in `D:\JavaProjects\jline3.29`.** The file is
`D:\JavaProjects\jline4\terminal\src\main\java\org\jline\terminal\impl\AbstractWindowsTerminal.java`,
the tree the parallel JLine-4.4.6 upgrade is working in, and it is on this page because the page's rule is not
"files under jline3.29" but "a dependency we edited" -- and because an edit in a tree somebody else is
rewriting is precisely the row that disappears in a merge if nobody wrote down why it exists.

**The change.** `isModeSupported(Mode)` overridden to return false for `Mode.SIXEL` and delegate everything
else (:530-536). No other file touched.

**Why (the four questions).**
1. *Can render.dll absorb it?* No, and this is the clean case: the renderer's DA1 answer is
   `ESC[?61;4;6;7;…c` -- conhost's own identity string, deliberately, because a chunk the renderer declines
   goes to the console unparsed and *conhost answers that one itself* (deviation 8 in `ANSI_SUPPORTS.md`). So
   the `4` cannot be removed from our reply without making one session answer the same question with two
   different terminals. The bytes we are allowed to write are exactly the bytes that say "sixel". The decision
   about what to believe is made upstream of us, in a class that never asked us anything.
2. *Wrong for every other user?* No. It is a family-level statement: "a Windows console's write path cannot
   guarantee that a Sixel payload is drawn", which is true of every member of that family here -- old inbox
   conhost advertises the bit and has no sixel renderer at all, our renderer drops the DCS wholesale
   (`RC_UN_DCS`), and only current conhost/Windows Terminal genuinely draw it. `SixelGraphics` emitting a DCS
   that silently vanishes is the bug either way, and it is not dbcli-specific.
3. *Which side owns the quantity?* The claim lives in the reply (terminal side); the *decision to act on it*
   lives in the reader (JLine side). Only the second can be vetoed without lying, so the veto is there.
4. *Red witness?* `SixelGraphics.isSixelSupported` resolves through override > DA1 probe > static table, and
   the static table has no `windows-*` entry, so with the override the second layer falls away and the net
   answer is false. There is no automated case for it and none was faked: the verification recorded is
   single-file `javac --release 8` in `cache/jline4-sixel-fix/`. A side effect that *is* checkable is that
   asking about SIXEL alone no longer triggers `ensureModesProbed()`'s batch, which is the same probe batch
   #49 had to gate because it moved the cursor through `CSI ?u`.

**Not deployed, and said plainly.** `lib/Jline3.jar` is the 3.29 artifact (mtime 2026-09-25 16:27) and carries
none of this; the class was compiled to `cache/jline4-sixel-fix/classes` and never packaged. The fix becomes
production when the jline4 tree ships, and if that upgrade overwrites this file the veto disappears with no
test to notice -- which is the reason this section exists.

**Re-measured 2026-09-28 (#107), and one sentence above is now stale.** The jar's mtime is 2026-09-28 00:42
(1,832,122 B), which is the *only* thing that paragraph was tracking, so it is corrected rather than dropped.
The claim "the shipping chain carries none of this" was verified the strong way, by scanning the artifact
instead of trusting its name: `cache/p107/scan107.py` expands every `lib/*.jar` -- the classpath is
`lib/bootstrap.lua:71 scan("lib","jar")` through `:206 -Djava.class.path=`, so all thirteen jars are live, not
a chosen subset -- and binary-greps **746 classes'** constant pools for `sixel` / `SIXEL` / `isModeSupported`:
**zero code hits in `JLine3.jar`, zero in `dbcli.jar`** (its single match is the text resource
`org/dbcli/resources/tic-ms-terminal.txt`, where all four matches are `#` comment lines about VT220/VT525 and
none is a capability in an entry). The same matcher over the jline4 impl directory returns four files
(`AbstractTerminal`, `AbstractWindowsTerminal`, `SixelGraphics`, `TerminalGraphics`), so the zero above is
"absent", not "the scanner is blind" -- that control is the reason this paragraph is worth writing.

**The consequence for this page's own wording.** "The fix becomes production when the jline4 tree ships" is
still right, but the risk it guards against is *not* live today: **3.29 has no sixel consumer to be fooled**,
so nothing in dbcli's Java layer currently reads `;4` and emits a DCS. What is live today is the renderer's own
fate for such a payload -- dropped whole, counted `RC_UN_DCS` -- and that now has legs of its own rather than
only a comment (`gm_osc_family`'s sixel arms in `RenderCheck.cpp`, the marker-and-body arm at the tail of
`caseOscTitle` in `Render.java`, both with attributed red arms; see ANSI_TODO #107). **The check to re-run the day jline4
ships:** `scan107.py` must then *hit* `isModeSupported` in whichever jar sits at `JLine3.jar`'s path, and the
override's return value must be false. Today that assertion cannot be written against the loaded chain, because
the class it would assert on is not on it -- recorded as a named missing leg, not as a done item.

**Upstream report owed.** Filing it is a public action against someone else's repository and was left for a
human. Draft with evidence and citations: `cache/p52/jline4-sixel-report.md`. Related: `ANSI_TODO.md` §3 row #52 (the row was DESIGN.md §10's when it was written).

## `terminal/src/test/java/org/jline/utils/StatusTest.java` (added)

A new file, so it changes no library behaviour, and it is still the highest-value item here: it is what lets a
geometry fix be argued about with a red/green pair instead of with prose. `ScreenTerminal.java` already existed
as the fixture; `Runner.java` (in `cache/status47-48-20260925/`) is a one-argument-per-case JUnit launcher,
because the fork's maven build is not what these legs run against.

## Merge into the jline4 tree (2026-09-28)

The parallel upgrade's jline4 checkout already carried a *partial* port of the fork's `Status` (its class
header says so), but it lacked precisely the core this page exists for. This pass merged the four rows above
into `D:\JavaProjects\jline4`:

| Row | Merged into jline4 | Kept from jline4 |
|---|---|---|
| `Status.java` | `setBorder(AttributedString,int)` + `borderTemplate`/`borderOverflow`/`DEFAULT_BORDER` + tiling `getBorderString`; `reset()`'s DECSTBM `\E[r` (save_cursor **before** the write -- DECSTBM homes the cursor); `hide()`'s model preservation; the `hided = false` move into the drawing branch; `redraw(force)`'s empty-model guard; `resize()`'s erase-at-old-geometry + redraw-at-new-bottom | DEC 2026 synchronized-update wrapper, the EAW ellipsis fix, and the region re-apply, which becomes the `else if (!redraw)` arm (it only matters when the geometry did not change) |
| `LineReaderImpl.java` | `prevWindow` field + `doDisplay()` seed + WINCH gate on `terminal.getSize()` (window), buffer kept for layout | the #492 teardown body verbatim -- only the gate changed |
| `KeyMap.java` | **nothing to port** -- jline4's `unbind` already compares `>=` at both sites (`:636`, `:646` in the 4.4.6 file); a sweep of both trees for the buggy `> mapping.length` shape (without `=`) returns zero remaining hits. The 2026-09-13 fix was a backport of what upstream had already gotten right. |
| `Display.java` (8c700c49, 51+/16−) | **nothing to port** -- item by item against the 4.4.6 file: the one semantic fix (`key_backspace` on the output path -> `cursor_left`/`parm_left_cursor`) is already there (jline4 `:641`/`:819` use `puts(cursor_left)`; `key_backspace` is 0 hits in its Display); the `empty()` builder-blanking and `hasColumnAddress` ctor cache are already there verbatim; and the rest was *rejected with reasons*: the `rawPrint(char,int)` batch-write would bypass `byteBuilder` in byte mode (jline4's `rawPrint(int)` is mode-aware at `:1153-1159` -- writer-before-builder breaks frame ordering) for zero gain since builder appends cost no console calls; the `dumbDisplay`/`hasCapability` caches trade a possibly-false "caps never change" premise (jline4 updates caps through probing -- the same batch that made #93) for ns-per-frame lookups, invisible against the 78us-per-console-call cost law; the no-`clear_screen` fallback has no red witness anywhere in this stack (every caps entry in scope defines `clear=`) and jline4's reset branch already does the stronger thing (clear + home + seed `oldLines` with blank rows). |
| `windows-conemu.caps` | byte-for-byte copy of the 3.29 file | nothing to keep; the packed jar's copy was verified identical to the tree |
| `Status.java` again, from `ba06511f` (the commit that post-dates this table) | **nothing ported** -- the 48-line cursor trace is 0 hits in both jline4 trees and 0 hits in the shipped `JLine4.jar`, while the production `JLine3.jar` carries it | porting is mechanical (all four anchors and `getCursorPosition(IntConsumer)` exist in jline4) but needs a decision on the `DBCLI_`-prefixed env name and a live question to point it at; see the trace's own section above |
| `StatusTest.java` | the 6 byte-witness cases appended to jline4's grid suite (constants renamed `B_COLS`/`B_ROWS` to coexist) | the whole grid suite, 13 cases |

**One assertion the merge nearly broke the wrong way.** `resizeWithVisibleStatusMustReReserveScrollRegion`
expects `\E[1;(newRows-1)r`; an edit that "corrected" it to `newRows-2` failed -- `puts(csr, 0, N)` compiles
through `%i` to `N+1`. The original literal was right and the merged redraw path emits it.

**Witness.** `bash cache/jline4-merge/run-test4.sh` → `tests=21 found=21 succeeded=21 failed=0` against the
packed `cache/jline4-build/out/JLine4.jar` (1 683 243 B, whole-tree `--release 8` rebuild, 0 errors).
Red arm: `bash cache/jline4-merge/run-control4.sh` runs the four linkable byte-witness cases against a
reconstructed pre-merge `Status` (base `a1f0ffc1` + drift patch, `borderTemplate` 0 hits): control
`1/3`, merged `4/0`. The three reds are exactly the two resize-repaint faults and the DECSTBM reset;
`hiddenBarStaysHiddenAcrossResize` is a guard and green on both arms, as it was in 3.29. The two
border-template cases have no control arm here for the same reason as on the 3.29 row: the pre-merge class
has no `setBorder(AttributedString,int)` to link against.

**Re-taken on the jline4 side, 2026-09-28/29 -- both owed legs are now witnessed.** Evidence dir:
`cache/jline4-live-20260928/` (and `cache/jline4-caps-20260928/` for the caps leg).

- *CapsDump against the jline4 jar*: `caps_check.ps1 -Caps <jline4 tree> -Jar cache/jline4-build/out/JLine4.jar`
  -> `170 ok / 0 fail`, `CAPS CHECK: ok` on both runs, jar copy and tree byte-identical at
  `9454E34C5E6724163C447AC7949C1015`, `unexplained=0`. Its red arm is the 2026-09-24 pre-merge `JLine4.jar`:
  **2 FAILED, and the two are exactly the `cbt` assertions** (`got=null`, `no cbt to look up`) -- the leg can
  go red, and it goes red for the right reason.
- *The five-arm live matrix, three roots*: production, a mirror whose `lib` is a byte copy of production, and
  the same mirror with `JLine3.jar` replaced by `JLine4.jar`. **15/15 arms put the bar on the last row**
  (WT grow, two-step, one-row, classic shrink, no-resize control). `D:\dbcli\lib` was not written at any point;
  the jline4 session runs from a mirror install because `bootstrap.lua` scans `lib` relative to the CWD and
  `OTHER_LIB` can only *append*, so an extra jar there is shadowed by `JLine3.jar`.
- *Why a mirror instead of a deploy*: this is also the first time dbcli's own `WinSysTerminal` has been loaded
  under jline4 at all. The 2026-09-24 swap only ever ran headless, which resolves to `DumbTerminal`. Before
  the legs, a compile probe put `JLine4.jar` first on the classpath and rebuilt the whole `org.dbcli` tree:
  **57 sources -> 112 classes, `javac` rc=0, 0 errors**, so the switch is not blocked at link time.
- *Why the matrix is reported twice*: every arm above ran at 02:05-02:29 on 2026-09-28 against
  `dbcli.jar faf86eec` + `JLine3.jar 67bcfd7a`, and `lib` moved by two deploys later the same day --
  `JLine3.jar 8b735dd2` (14:02) and `dbcli.jar bf34aa95` (21:17), the latter carrying the #99 reversal
  (`WinSysTerminal.java:130` now tests `Boolean.TRUE.equals(pty)` first). The re-take on the shipping batch
  (`cache/jline4-live-20260928/b329` and `/b4`, both `dbcli.jar bf34aa95`) is **6/6 green**: diag, classic
  shrink and WT grow on each side. It is a different exercise than the first matrix, and that is the point --
  both arms now self-report `WinSysTerminal[name='dbcli', type='windows-vtp']` and print
  `ANSICON_DEF=conemu ignored: this console is a pseudo-console`, so the caps entry under test is
  `windows-vtp.caps` (which does declare `csr`) rather than `windows-conemu.caps`. Read together the two
  passes say the merged jline4 `Status`/`LineReaderImpl` keep the bar on the last row under **both** terminal
  classes dbcli can land on in Windows Terminal.
- *The red arm for the live matrix, and its shape*: with the pre-merge `JLine4.jar` in the same mirror, all
  three arms come back `BAR ABSENT` and the screen carries
  `java.lang.NoSuchMethodError: org.jline.utils.Status.setBorder(Lorg/jline/utils/AttributedString;I)V`.
  So the live leg goes red for the *linkage* reason, not for a geometry reason -- the same limitation the
  "What is not witnessed" list already records for the border unit cases, now on a real screen. Read it as
  the `lib/dbcli.jar` + `lib/Jline3.jar` same-batch rule demonstrated, not as a resize witness.
- **The trap that made the first four jline4 legs meaningless, and it was not jline's doing.** Those legs
  reported `BAR ABSENT` and `NativeWinSysTerminal[name='dbcli', type='', ...]`. `--env MSYSTEM=` on a
  `window` leg sets MSYSTEM to the **empty string**; it does not delete it. jline 3.29 defines
  `IS_MSYSTEM = IS_WINDOWS && MSYSTEM != null && (startsWith("MINGW") || equals("MSYS"))`, so "" is false;
  jline4 defines `IS_MSYSTEM = IS_WINDOWS && MSYSTEM != null`, so "" is **true**. Under jline4 that one
  character makes `Console.java:125` skip dbcli's own `createTerminal`, the generic builder then yields a
  terminal whose type is "", `InfoCmp.getInfoCmp("")` throws, `AbstractTerminal.parseInfoCmp` catches it and
  falls back to `getDefaultInfoCmp("ansi")` -- and `ansi.caps` declares no `csr`, so `Status` is
  `!supported` and no bar is ever drawn. The fix belongs to the harness, not to either library: the `.cmd`
  must `set MSYSTEM=` (cmd's delete form), after which the jline4 leg self-reports
  `WinSysTerminal[name='dbcli', type='windows-conemu']` and passes. Agents.md's "clear the two inherited
  variables" rule is therefore **not satisfiable with `--env NAME=`** on a window leg.
- Still uncovered after this pass, unchanged: `LineReaderImpl` has no automated test -- the matrix above is
  its only witness, on either tree.

**Nothing deployed.** `lib/` untouched; the merge lives in the jline4 source tree and
`cache/jline4-build/out/JLine4.jar` only. The 3.29 tree and its shipped `Jline3.jar` remain the production
pair until the upgrade ships. The SIXEL veto and the `WriterOutputStream` block path were already in the
jline4 tree and survived this rebuild (verified in the compiled classes).

---

## What is not witnessed

Recorded rather than smoothed over, in the same spirit as the task ledger (`ANSI_TODO.md` §3, which carries what
DESIGN.md's §10 used to):

- **`Status.reset()`'s DECSTBM fix has no red/green pair of its own.** The change is real and reasoned —
  `puts(change_scroll_region, 0, 0)` compiles through `csr=\E[%i%p1%d;%p2%dr` into `\E[1;1r`, *a one-row scroll
  region*, which is the opposite of undoing the bar; the reset form is `CSI r` with no parameters (:183-197).
  It is the library half of #43: the symptom was "close the bar, then resize, and the screen collapses to one
  `SQL>` row", whose named mechanism is a bar-left-behind scroll region colliding with the WINCH handler's
  `carriage_return`+`clr_eos` (that erase runs from the *current* cursor, so a cursor on row 1 means "clear the
  screen"). `resize()`'s `scrollRegion` hand-back and `close()`'s true reset both remove that residue, and
  `More.init()` — which used to hide the bar with no reset at all, the same landmine on a second fuse — now gets
  the reset from `close()`. **But the leg has not been re-taken since.** The one measurement on record is from
  14:xx against the 12:19:18 jar pair, where pre-fix and post-fix behaved *identically*, and the `Status.java`
  carrying this fix is from 16:19. So #43 is closed as "mechanism removed, library-side", not as "symptom
  witnessed gone" -- the distinction is written the same way in `ANSI_TODO.md` §3's #43 row.
- **`resize(Size)`'s erase-then-redraw has no unit case.** The five live arms above are its witness, and they
  were taken against a deployed jar, not against a class under test.
- **`LineReaderImpl` has no automated coverage at all.** Its fix is a five-arm live matrix.
- **`StatusTest` cannot red-arm against an older jar for the border-template cases** — an unpatched `Status`
  has no `setBorder(AttributedString,int)` to link against, so their control is the real-terminal leg and the
  `/tmp`-revert arm above, not `run-test.sh --control`.

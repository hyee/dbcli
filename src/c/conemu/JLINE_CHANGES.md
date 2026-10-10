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


## 2026-10-05, WORK_ORDER_1005_REFACTOR slices C+F

- **`dbcli/src/com/hyee/ansirender/NativeRenderer.java`** -- the hand-written `SLOT_*` constants and the
  `UNMODELLED` array became one marker-delimited block generated from `Render.h`'s `RC_CENSUS_X` /
  `RC_STATFAM_X` by `gen_statslots.py`; `build.sh` fails the build if either Java block or
  `RenderJni.cpp`'s `STAT_` chain drifts from the table (values unchanged -- the live gate's
  `reportSlotAgrees` legs re-verify the shipped class against the dll at run time).
- **`terminal/src/main/resources/org/jline/utils/windows-conemu.caps`** -- owner ruling of 2026-10-05:
  align spellings with `xterm-256color` where the function is the same. Adopted: `cub1=^H`, `sgr0=\E(B\E[m`, `khome=\EOH`, `kend=\EOF`, `smcup/rmcup` plus the
  `22;0;0t`/`23;0;0t` title-stack suffixes. `cud1` was adopted as `
` the same morning and reverted
  to `\E[B` the same evening by owner ruling ("change cud1 back to \E[B") -- with cud1 back at the
  CSI, jline's `Display.cursorDownIsNewLine` (Display.java:84) stays false for this entry, the
  pre-batch redraw shape is preserved, and the interactive bar/pager legs ran on exactly that shape. Deliberately kept: `kbs=^H`, `kmous=\E[M` (xterm declares `\E[<`, the SGR
  prefix -- ours names the X10 prefix the default family sends), `sgr` (reduced), and `setaf`/`setab`
  stay `38;5;`/`48;5;` because this jline's `Curses.tputs` cannot evaluate xterm's chained
  conditional (`%? c1 %t a %e c2 %t b ...%;` -- the second `%t` pops a stack the skipped first branch
  never pushed, `Curses.java:379` throws `NoSuchElementException`; measured by `caps_check.ps1`
  before the value was reverted). `cnorm`/`cvvis` stay `\E[?25h`: the renderer's h/l reads
  args[0] only, so xterm's `\E[?12;25h` would apply the 12 and drop the 25.


## 2026-10-05, later the same day: `terminal/src/main/java/org/jline/utils/Curses.java` (owner-ordered fix)

The setaf/setab clause above ("stay 38;5 because tputs cannot chain %t") was superseded by the owner's
ruling the same day: a bug in Curses.java gets fixed in Curses.java, not worked around by keeping the
entry inconsistent with xterm-256color. Two defects, both in the `%` machine of `doTputs`:

1. **`%d` and `%i` had no `exec` guard** -- every other operation checks `if (exec)`; a `%d` inside a
   not-taken branch popped an empty stack and threw `NoSuchElementException` (the original crash).
2. **A single `ifte` enum cannot express an else-if chain** (`%? c1 %t A %e c2 %t B %e C %;`, xterm's
   own setaf/setab shape): after a taken branch the `%e` flipped `exec` back on, so the skipped
   branch's condition ran half-evaluated and the next `%t` popped whatever it found. Replaced the
   enum with a frame stack (`{active, taken}` per `%?`): a taken branch skips to the `%;`, an untaken
   one re-arms at each `%e` so the next condition is evaluated, `%;` restores the enclosing exec --
   nesting-correct, and a `%t` that arrives inside a finished chain skips rather than pops.

Witness: `caps_check.ps1` both arms, with the xterm 3-tier setaf/setab values in the entry --
`setaf(3)=\E[33m`, `setaf(9)=\E[91m`, `setaf(196)=\E[38;5;196m`, `setab(1)=\E[41m`, and the live
gate both arches `checks=6373 failures=0` with the rebuilt jar. The fixed class is deployed in
`lib\JLine3.jar` (compiled `-g -source 8 -target 8`, the flags the JAR CHECK hashes).


## 2026-10-05, Curses.java synced to the jline4 tree (`D:\Green\github\jline4`)

Owner instruction: carry the same fix across. jline4's `terminal/src/main/java/org/jline/utils/Curses.java`
carried both defects verbatim (the unguarded `%d`/`%i`, the single-ifte machine); the conditional
machine now reads identically to jline3.29's (the remaining tree difference is one commented-out
block's indentation). Compiled and run under JDK 22 (`D:\jdk-22`, the tree's enforcer floor) with
`mvn -pl terminal spotless:apply` + `mvn -pl terminal test -Dtest=CursesTest`: **5/5 green** -- the
two pre-existing tests plus three new regression legs added to `CursesTest` (`testElseIfChain`
asserts xterm's exact setaf shape through all three arms: `\E[33m` / `\E[91m` / `\E[38;5;196m`;
`testSequentialConditionals`; `testNestedConditionals`). The crash itself was witnessed red earlier
the same day on jline3.29's byte-identical code, which is the seen-red arm for these tests.

Not synced: jline4's `terminal/src/main/resources/org/jline/utils/windows-conemu.caps` is **not** our
audited entry -- it is jline upstream's generic one (16-colour `setaf=\E[3%p1%dm`, `blink`/`invis`
advertised, no `acsc`/`csr`/`u6`/`u7`/`rep`, `ncv#3`). Porting the audited entry there interacts with
the separate jline4 work and was left for its owner; noted here so the two trees' differing entries
are a recorded fact, not a surprise.


## 2026-10-06, Status.java grow branch: dropped the CUD/cursor_up compensation loops

Defect (user-visible as `help` -> `more l` -> `q` leaving the prompt drawn two rows above the
restored screen, overwriting live help rows): every grow of the bar ran

```
cursor_address(bottom); cursor_down x k; DECSTBM; restore_cursor; cursor_up x k; save_cursor
```

The `cursor_down` loop was written as if CUD at the bottom margin scrolled the region; CUD does
not scroll anywhere (ECMA-48 8.3.19 "does not scroll"; xterm, conhost and this project's native
renderer all clamp), so it never moved content -- and the `cursor_up x k` after `restore_cursor`
then compensated a scroll that never happened, re-saving the caller's cursor k rows above where
it was. Anything that trusted the re-saved position drew k rows high: the pager's exit (its init
`close()`+`reset()` leaves `scrollRegion=rows-1`, so the exit `restore()` always grows) and
`set status on` mid-session. The fix keeps `cursor_address` + `DECSTBM` + `restore_cursor` and
re-saves the caller's position untouched.

Witness: conpty legs `cache/moreq` (before: the pager's exit put the prompt at the saved
`(entry-2)` row over the restored text; after: prompt lands on the row below the restored echo,
one row per round -- the normal newline cost). Live gate both arches `checks=6373 failures=0`
with the rebuilt jar; the class is deployed in `lib\JLine3.jar` alongside a `dbcli.jar` change
(`Console.setStatus` no longer lets a spinner "flush" tick resurrect a closed/suspended bar --
the dbcli side of the same incident, not a jline change).

### 2026-10-06 later — the removal above resurfaced as "top Ctrl-C" ; a conditional re-seat was tried and reverted (no code changed)

The owner reported: `top` -> Ctrl-C -> "Statement is aborted." -> the prompt never appears, the
cursor lands on the bar, and subsequent output scrolls only around the bar. Four-arm A/B on real
window legs pinned the cause to **this grow-branch change**: old dbcli.jar + new jline reproduces,
new dbcli.jar + **old** jline is clean. Mechanism: the exit path (`Console.exitDisplay` ->
`status.restore()`) grows the bar while the caller's cursor sits on what is about to become the
bar's border row, and the plain re-save now leaves it there -- `readLine` writes its prompt at the
hardware cursor, so prompt and bar fight for the same row and the LF scrolls at the real window
bottom, shoving the bar off and repainting it. The removed `cursor_up` loop had been compensating
*that* caller by accident: the same `-k` was poison for the pager and medicine for `top`.

A conditional re-seat was tried (after `restore_cursor`, read the cursor back locally via
`GetConsoleScreenBufferInfo` -- no DSR round-trip -- and CUP above the bar when it is genuinely
buried). It fixed the classic-window `top` leg completely and **broke the conpty regress leg
stably (2/2) with the pre-fix `qexit`/`QMORE` symptom** that the removal above had cured. Reverted;
both legs are witnesses. The lesson is the same one 2026-09-28 taught about the WINCH gate: the
cursor's ledger lives in the reader, and every hardware-level "fix the cursor first" move is a bet
on which consumer reads it next. There is no single cursor semantics for this dance that serves
both callers -- the fix belongs in the reader's geometry (raise WINCH on bar-row-count changes and
fold "visible rows = window - bar rows" into the gate), which stays open on the dbcli side.

### 2026-10-06 final — the dbcli-side fix landed; the reader-geometry half stays unneeded for now

Follow-up to the entry above: the fix was implemented in `dbcli/src/org/dbcli/Console.java`
(prompt-bound restores now `liftCursorAboveBar`: park on the window's last row, `scroll_forward`
the difference so the region itself makes room, then address the row above the bar -- plus a
`WinSysTerminal.getRelativeCursorPosition()` because the plain readback is buffer-absolute and the
window is not always parked at the buffer's end). No jline file changed for it. The WINCH-gate
fold suggested earlier turned out to be unnecessary for every observed trigger: bar row-count
changes only ever happen between readLines, and the lift makes the screen self-consistent before
any consumer reads the cursor. `regress.json`'s more-cycles were retired as an oracle:
`printer.before_command` resets `more_text` for every non-MORE command, so `more l` after
`set status off/on` pages an empty buffer by Lua design -- the "pager not engaging" that ledger
entries had blamed on probe timing is this, and the baseline stream shows the same `qexit`
assembly transiently. The pager is gated by race/fastq/liftsp2 instead.

## 2026-10-07, the hosting terminal's TERM now seeds the Windows type, and render.dll gets its own caps entry

Two changes, both in the files this ledger covers:

1. **`terminal/.../InfoCmp.java`** — the built-in registry gains `windows-render` (`render.caps` beside
   the conemu one). That is all: the Windows gate in `getInfoCmp` stands exactly as the owner ruled it
   on 2026-10-05 (no infocmp shell-out on native Windows), and no caller of the loading chain changed.
2. **`terminal/.../AbstractWindowsTerminal.java`** — `TYPE_WINDOWS_RENDER = "windows-render"`.

The selection itself is dbcli-side (the `dbcli` subtree, recorded in the repo's own ledger):
`WinSysTerminal.createTerminal` seeds `type` from the `TERM` environment variable on native Windows
(`!IS_MSYSTEM && !IS_CYGWIN && !rendererClaimed`), only for names the built-in registry can answer,
`dumb` excluded — so a wezterm/ghostty session that exports `TERM=xterm-256color` encodes its own
dialect instead of `windows-vtp`, while no TERM keeps the Windows defaults. `TERM=windows-render` (what
dbcli.bat exports when `ANSICON_DEF=render` runs with ANSICON present) and `ANSICON_DEF=render` are
renderer claims: they select `ConEmuWriter`/render.dll **and** `windows-render.caps`, outranking any
host TERM. Why render.dll gets an entry of its own rather than reusing the conemu one: the two dialects
are identical today and the fork exists precisely so they can diverge without a re-audit of the other
entry. `render.caps` in the jline resources, the renderer's mirror (`terminfo/windows-render.caps`) and
the shipped jar copy are asserted byte-identical by `terminfo_check.sh`'s new render arm, which also
compiles `windows-render.ti` under `tic -x`.

Witness (2026-10-07): ConPTY five-arm (`cache/termcaps/arm{a..e}`) — TERM=xterm-256color seeds
`xterm-256color` through both the VTP and pass-through branches, no TERM keeps `windows-vtp`,
`TERM=windows-render` + `ANSICON_DEF=render` lands `windows-render` with the painter. Real ConEmu
(`cache/termcaps/TypeDump{2,3}.java` writing to a file, because ConEmu eats injected keystrokes):
TERM=xterm-256color → `xterm-256color` on both the pass-through and default branches, TERM unset →
`windows-conemu`, render claim → `windows-render`. The first ConEmu capture that looked polluted was
the harness inheriting the driver shell's `MSYSTEM=MINGW64` and a global `ANSICON_DEF=7` — the clean
arms clear both in the tab before launching. Live gate 6373/0 x2, STAGE0 ok; liftsp2/offhelp regression
legs green on the same jars.

### 2026-10-07 later — a real ConEmu window defaults to its own dialect, not vtp's

The owner ran dbcli in a real ConEmu and got `type='windows-vtp'`: the branch order
below the TERM seed let `enableVtp` win over the IS_CONEMU branch (new ConEmu conhosts
advertise the VTP bit), and the vtp caps describe conhost's parser while the consumer
of a ConEmu session's bytes is ConEmu itself. Pre-TERM jars reproduce it, so the TERM
work did not introduce it -- it only made the mismatch visible. Fix stays on the
dbcli side: after the TERM seed, an unfilled `type` on a real ConEmu window defaults
to `windows-conemu` (TERM still wins over this; the writer is untouched -- the stream
goes out as-is for ConEmu to parse, only the caps/name now describe the right
consumer). Witness: TypeDump4 file-writer in the real ConEmu, TERM unset ->
`windows-conemu` (was windows-vtp on the old jars), TERM=xterm-256color ->
`xterm-256color`; live gate 6373/0 x2 and the pager legs green on the same jar.


## 2026-10-07 (round 2, the P1 review batch): `Status` border cache, `LineReaderImpl` size reads, and two claims withdrawn

The review of every Java change since 2026-09-24 (`cache/review-1007/JAVA_REVIEW_since-0924.md`) produced the
items below. Library files were edited in `D:\JavaProjects\jline3.29` and copied to
`D:\Green\github\jline3.29` the same day -- verified by md5 with CR stripped, all three files identical.

### `terminal/src/main/java/org/jline/utils/Status.java` -- the border row stops rebuilding

`setBorder(AttributedString,int)` used to null `borderString` unconditionally. The caller that matters,
`dbcli`'s `Console.setStatus("flush", ...)`, rebuilds the template from the colour prefix on every timer tick,
so the cached rule was thrown away once a second and a full-width row of attributed cells was re-tiled to come
out identical. Now the call returns early when `(border, overflow, template)` all compare equal, and the
comparison is by character *and* per-column style -- reference comparison could never match, because the caller
constructs a new `AttributedString` each time, and text-only comparison would swallow a colour change.

No API changed; `setBorder(boolean)` still delegates here. `isSupported()` already existed at :90 -- the defect
was that nobody read it (see the dbcli round below), not that the library had no way to say it.

**Witness.** `StatusTest` gained three cases (7 to 10), each with its own falsification arm run against a
mutant copy of `Status.java` in `D:\dbcli\cache\redlab-1007` (the live tree was never mutated):

| leg | arm | result |
|---|---|---|
| `equalBorderTemplateDoesNotRetileTheRule` | early return deleted | red, only this leg |
| `styleOnlyBorderChangeStillRedrawsTheRule` | `styleAt()` comparison deleted | red, only this leg |
| `glyphChangeUnderTheSameStyleRedrawsTheRule` | `charAt()` comparison deleted | red, only this leg |

The first two assertions are on the identity of the private `borderString` field, read reflectively: the byte
stream is identical either way, so the rebuild is invisible to an output-only test. That is stated here because
it is the one place in this file where the witness is not "the bytes the terminal was handed".

### `reader/src/main/java/org/jline/reader/impl/LineReaderImpl.java` -- a size we cannot read is not a resize

`WinSysTerminal.getSize()` throws `IOError` when `GetConsoleScreenBufferInfo` fails (that throw was deliberate:
a 0 answer used to be read by `Status` as "one row, two billion columns" and by `Console.setStatus` as "no
status bar", both silently). Two of this file's own call sites were newly added on the fork side --
`doDisplay()`'s `prevWindow.copy(terminal.getSize())` and the WINCH branch's `Size window = terminal.getSize()`
-- and both sit on paths where an unchecked throwable is fatal: the signal handler runs on the input pump,
which catches `IOException` but not `Error`. So both reads are now guarded, say once through `Log.warn`, and
keep the last geometry.

Compile-time fact worth keeping: `Terminal.getSize()`/`getBufferSize()` declare no checked exception, so
`catch (IOException | RuntimeException | Error ...)` does not compile. The guards catch
`RuntimeException | Error`.

### Two claims from the review, withdrawn after measurement

- **"A double-width border template overshoots the width and never hits the cache."** Measured against this
  fork's own width model: `new AttributedString("\u25CF").columnLength() == 1`, and tiling `●` to 79/80/78
  columns yields exactly 79/80/78 (`cache/redlab-1007` probe). The `columnSubSequence` trim written for that
  claim was therefore dead code and has been removed from `getBorderString`, which is back to its previous
  body. The dot/braille "2 columns" figure in project memory is `render.dll`'s oracle (`ansi_width.c`), not
  jline's `WCWidth` -- the two disagree for U+25CF, and for this method jline's model is the one that runs.
  **Superseded on 2026-10-10: the two no longer disagree** (`WCWidth` now reads the generated table and answers
  2 for U+25CF), so the sentence above about the models was true of the code at the time and is not a
  description of it now. What the withdrawal rested on -- `columnLength("●") == 1`, making any overshoot
  unreachable -- is gone with it, and the tiling was re-measured instead of left to the old argument:
  `StatusTest.doubleWidthBorderTemplateFitsTheRowItIsDrawnOn` asserts the tile of a 79-column wanted width
  comes out 78 columns (39 dots) because `columnSubSequence` returns nothing for a one-column window that does
  not cover a whole wide glyph, and that the row drawn is exactly that. The decision to keep `getBorderString`
  without its own trim stands, now on a measurement.
- **"`gen_statslots.py:282 if "Render.java" in target:` mis-routes the production block."** `"Render.java"`
  is not a substring of `NativeRenderer.java`. `--check` on the production file exits 0 and its marker block
  equals `prod_block` line-for-line; changing one constant in a copy (17 to 18) exits 1 and names the line.
  The leg is a witness, not a counter.

### Not a JLine change, but it belongs on this page: `ANSICON_DEF=conemu` retired, and the caps entries

The owner ruled the same day that `ANSICON_DEF=conemu` ceases to exist. `WinSysTerminal` no longer treats it as
a renderer claim and `Console`'s mode table no longer lists it, so it normalizes to `default`; the renderer is
reachable only through `ANSICON_DEF=render` / `TERM=windows-render` / a console that cannot parse its own
escapes. Every `ConEmuWriter` branch now names itself `windows-render`, which is also why `windows-conemu.caps`
can stop describing the renderer.

Two facts about the entries, both measured rather than inferred:

- The owner restored `windows-conemu.caps` in the build tree to the stock entry plus `kmous=\E[M` (1090 B,
  `6c28b2e9e993`). The audited mirror and the shipped jar still hold 1575 B (`fc6705a001eb`), and the
  `Green` git tree still holds the 2026-09-28 audit expansion (7440 B, `9454e34c5e67`) -- three live versions.
  `terminfo_check.sh` therefore reports `TERMINFO CHECK: FAILED` on arm 3's jline copy, which is the leg doing
  its job. It is *not* a symptom of today's runtime: every jar reads `fc6705a0`.
- Stock carries **no `csr`**, and `Status`'s constructor requires `change_scroll_region`
  (`Status.java:100`), so a `windows-conemu` session built on the stock entry would draw no status bar and say
  nothing. `Console.setStatus` now says it once (`status bar cannot draw: ... no scroll region (csr) ...`).
  Whether the shipped entry for `windows-conemu` should be stock, or the audited set trimmed of the renderer-only
  claims, is the owner's call and is still open.

`ANSI_SUPPORTS.md` still states the renderer's terminal type is `windows-conemu`, and `DESIGN.md`/`ANSI_SUPPORTS.md`
have zero mentions of `windows-render`; `CapsDump.java` and `caps_check.ps1` have zero legs naming it either, so
the entry a render session actually loads is covered only by the tic/infocmp name round-trip and three-copy
identity, not by the value-level census. Recorded here as the shape of the gap, not as a fixed item.


### `liftCursorAboveBar`'s degenerate geometry, measured both ways

The guard clause is not a theory: `cache/lift-1007` runs `Console.liftCursorAboveBar` against a stubbed
terminal whose cursor read is local (the real one asks the host and blocks), and the mutant that deletes only
`bandTop < 0 ||` produced exactly the bytes the review predicted:

| window | band | mutant bytes | fixed |
|---|---|---|---|
| 2 rows | 2 rows | `\E[2;1H` + 2 LF + `\E[0;1H` | refuses, zero bytes |
| 3 rows | 5 rows | `\E[3;1H` + **5** LF + `\E[-2;1H` | refuses, zero bytes |
| 1 row | 1 row | `\E[1;1H` + 1 LF + `\E[0;1H` | refuses, zero bytes |

Five line feeds on a three-row window is the over-scroll, and `\E[-2;1H` is the malformed cup. The gate also
carries two positive cases (30/2 and 10/1) that assert the lift still happens with exactly the right number of
feeds and lands on the band top -- a refusal-only test would pass if the feature were deleted. 6 checks, 0
failures on the shipped classes; 3 failures on the mutant.

## 2026-10-10 (round 4): `WCWidth` reads the generated table -- JLine and the grid are one width model

Owner's instruction was 改 jline 的 WCWidth, and the question that earned it was "是不是 jline 3.29 关于 wcwidth
计算不准确". Measured 2026-10-08 (`cache/ambiguous/measure/`, six real console faces, 43,944 cursor readbacks,
BMP exhaustive over the ambiguous set): of the 6,475 sampled code points that **every** face draws two cells wide,
JLine answered 1 for 6,471. `DESIGN.md` I14 had long said the `ansi_width` table is the only width oracle; the
Java side was still a second, hand-copied one, and the two disagreed.

### What changed

| file | change |
|---|---|
| `terminal/src/main/java/org/jline/utils/AnsiWidthTables.java` | **new, generated.** 594 runs as parallel `FIRST`/`LAST`/`WIDTH` arrays plus a binary search. Compiled class 15,358 B; `wcwidth` cost is one search instead of Kuhn's search + a chain of hardcoded ranges. |
| `terminal/src/main/java/org/jline/utils/WCWidth.java` | the hand-written table is gone -- `combining[]`, `Interval`, `bisearch` deleted, 180 lines to 92. The control-character test stays first; everything else asks the generated table. |
| `src/c/luauf8/gen_ansi_tables.py` (dbcli tree) | `--java <paths...>` writes the Java form, `--java-check <paths...>` re-derives it and compares the whole file. One run of one script now produces both halves, because two hand-copied tables is the failure mode this closes. |
| `src/c/conemu/run.ps1` | a `WIDTH CHECK` leg: it runs `--java-check` against the build tree always and against every root in `DBCLI_JLINE_TREES`, prints one line per tree, and sets the gate's exit code on a stale copy. `-SkipWidthCheck` exists and says so loudly. |
| both jline trees | `AnsiWidthTables.java` md5 `3e85f146f5d412f969732cccbd95cd60` in `D:\JavaProjects\jline3.29` **and** `D:\Green\github\jline3.29`; `WCWidth.java` md5 `53916958c0e3c0866b253f7fd9d55bab` in both. The C header regenerated after the generator edit differs from the deployed one by **one comment line only** (the "Regenerate with" block), so no width rule moved. |

The table is the same data, not a translation of it: the run list is exactly what
`ansi_width_tables.h` emits. The C file's per-256-block map was deliberately left out of the Java side -- a
594-entry binary search answers the identical question, and a second structure is a second thing to drift.

### What the change moves, measured against the class that shipped before it

`cache/wcwidth-1010/ab1010.py` pulled HEAD's `WCWidth.java` out of git, compiled the two side by side and
dumped both over every code point (surrogates excluded, 1,112,064 of them):

| direction | count | what it is |
|---|---|---|
| 1 -> 2 | 146,194 | the ambiguous ruling (Greek/Cyrillic capitals, `‥ ℃ Ⅰ-ⅻ ⑴-⒀ △ ▽ ◆ ★ ∈ ∝ ∠`), 6,380 private-use code points, and the Wide/Fullwidth assigned characters Kuhn's 1998 ranges never saw |
| 2 -> 1 | 2,589 | 1,354 **unassigned** holes inside Kuhn's blanket CJK ranges, 1,235 plane-1 symbols whose Unicode 15 EAW is Na (mahjong U+1F000.., dominoes, playcards -- text presentation, not emoji presentation) |
| 1 -> 0 | 1,209 | Mn/Me/Cf added to Unicode since the table was cut |
| 0 -> 1 | 8 | the drawn Cf the generator gives a cell to (U+0600..U+0605, U+06DD, U+06DE, U+070F, U+1734) |
| 0 -> 2 | 7 | U+302E/U+302F (Hangul tone marks, Mc **and** W) and the five skin-tone modifiers U+1F3FB..FF (Sk, W -- Kuhn had them zero-width) |

Every one of those 150,007 new answers equals the grid's answer (`oracle.txt` from `lib/x86/utf8.dll`), and the
65 control code points answered identically by both classes -- the -1 contract did not move.

`cache/wcwidth-1010/join1010.py` compares four faces per code point -- the C header parsed back out of
`ansi_width_tables.h`, `lib/x86/utf8.dll`, the generated Java table, and the generator's own rules:
**1,112,000 identical**, 64 differing, 0 unexplained. The 64 are the two documented exceptions:

- 63 controls: table 0, `WCWidth` -1. That is JLine's contract (callers such as `DefaultHighlighter:115` and
  `ScreenTerminal:233` test the negative to mean "cannot be placed"), and `columnLength()` adds it.
- U+0009: the *string* entry point `utf8.ansi_width` replays a lone TAB as one 8-column stop while `cp_width`
  says 0; JLine says -1. Neither answer is this round's -- `tab` measured 9 on the grid, 1 in JLine, before and
  after alike.

### String-level: the loop that reads the table, not just the table

Per-code-point equality does not prove `AttributedCharSequence.columnLength()` composes it the way the grid
does, so `cache/widthparity-1010/parity1010.py` ran 21 whole strings through `AttributedString.fromAnsi(s)
.columnLength()` twice -- once with the jar that was then deployed, once with the staged tree -- against
`utf8.ansi_width` on the same bytes. 19 of 21 agree with the grid; the 2 that do not are the TAB and the
control cases above, and those -1 answers did not move. Eight strings changed their answer with this round,
each one now matching the grid: `结果…` 5→6, `进度 ⅠⅡⅢ ℃` 10→14, `⑴⑵⑶⑷⑸` 5→10, PUA `6→6` (3→6), `●●●○○`
5→10, `↑↓←→` 4→8, `‘’“”` 4→8, and the astral case moved the *other* way, 7→5, because regional indicators are
EAW=N and Kuhn's blanket `0x1f000..0x1feee` said wide. The harness prints the `WCWidth` it actually loaded
(its code source), which is what makes the before/after columns more than a hope.

### Cross-checked against the three reference terminals (I14's rule: no made-up widths)

The `2 -> 1` half was not cursor-measured -- unassigned holes and Na plane-1 symbols are not in the ambiguous
sweep -- so it was checked against the three local implementations instead:

| | our table | msfterm | ghostty | wezterm |
|---|---|---|---|---|
| U+1F000 (So, EAW=Na) | 1 | 1 | 1 | 1 |
| U+2E9A (unassigned hole in 2E80..2EFF) | 1 | 1 | 1 | 1 |
| U+25CF / U+2026 (EAW=A) | **2** | 1 by default | 1 | 1 by default |

Verified lines, opened in this session: `src/types/inc/CodepointWidthDetector.hpp:76 int _ambiguousWidth = 1;`,
`src/types/CodepointWidthDetector.cpp:847/944/1036/1101` (the paths that resolve ambiguous to that value),
`:1157` and `:1203` (the only two callers of `_checkFallbackViaCache`), `:1221-1225`
("Ambiguous glyphs are considered narrow by default ... if (!_pfnFallbackMethod) return 1;"), and
`src/host/srvinit.cpp:836 if (!gci.IsInVtIoMode())` guarding the `:842-843` install of
`pRender->IsGlyphWideByFont`. wezterm: `wezterm-cell/src/lib.rs:849-856` (`Unassigned` forced to 1, and
`ambiguous_are_wide` off by default) with U+2E9A sitting in `UNASSIGNED_TABLE` at
`wezterm-char-props/src/widechar_width.rs:935` while `:414-415` lists `(0x02E80,0x02E99),(0x02E9B,0x02EF3)` --
the hole is excluded on purpose. ghostty: `src/unicode/main.zig:12-27` ("2 for wide ... 1 otherwise") and the
in-repo range tables `src/simd/codepoint_width.cpp:82/99`, which are exactly the same block boundaries.

**What that means for the ruling, and it is worth stating plainly.** None of the three defaults ambiguous to
wide; all three make it a switch (`--ambiguousIsWide` / `compatibility.ambiguousWidth` in the msfterm stack,
`treat_east_asian_ambiguous_width_as_wide` or the per-code-point `cell_widths` map in wezterm, not available at
all in ghostty). Ours is 2 because the console dbcli is asked to serve is a Chinese Windows console whose
default faces are MS Gothic and 新宋体, and the font query the references only run in classic-conhost mode
(`IsGlyphWideByFont` behind `!IsInVtIoMode()`) is precisely what those faces answer 2 to. Two consequences
follow and both are accepted rather than discovered later:

- In classic conhost on a CJK face, JLine now counts what the console spends. That was the under-count, the
  dangerous direction: a line the grid padded to `columns` cells and Display thought were fewer arrived past
  the margin and wrapped.
- In Windows Terminal with the default settings, ambiguous glyphs are drawn **one** cell, so counting them 2
  over-predicts. Over-prediction cannot overflow a line; it leaves cells unused, and a row padded to the full
  width stops short by one cell per ambiguous glyph. This is the price `DESIGN.md` already records for the
  620 split code points, now paid by the Java side too, and it is the same price the Lua grid has paid for
  weeks -- the two halves now pay it identically instead of one paying and one not.

### Gates, legs, and the deployed bytes

`StatusTest` 11/11 against the staged classes (`cache/deploy-1010/run-statustest-1010.sh`, staged first on the
classpath so the suite cannot link against the old jar). The eleventh case is new and belongs to this round:
`doubleWidthBorderTemplateFitsTheRowItIsDrawnOn` -- see the note above, it is the leg that re-measures the
tiling under the new widths. `run.ps1` both arches: `checks=6373 failures=0`
twice, `STAGE0 RUN: ok`, and the new `WIDTH CHECK` leg printed `table is current (594 runs)` for both trees.
Red arms (`cache/wcwidth-1010/redarm1010.py`, all inside cache): flipping one run's width in a copy of the
generated table changed exactly that run's code points and nothing else, and made `join1010` report that many
unexplained differences; a one-hex-digit stale copy is caught by name with the fix command; moving a *rule*
in a copy of the generator (adding U+25CF to `AMBIGUOUS_NARROW`) makes `--java-check` red against the untouched
tree file without writing anything; `javap` confirms the compiled `WCWidth` has no `combining` member left.

Legs, headless ConPTY through the real entry (`dbcli.bat` with `--env MSYSTEM= --env TERM=`), each self-
reporting its terminal type: `WinSysTerminal[name='dbcli', type='windows-vtp', size=Size[cols=120, rows=30]]`.
`top 5` at 120x30, 24 frames captured 0.35 s apart: **24/24 cursor [29,0]**, `feed_errors=0`,
`stripped_sequences={}`, no row touching the right margin with a non-blank row under it. An earlier 8-frame run
at 2 s cadence showed one frame at [7,0] (`r-06`) -- a repaint caught mid-flight, not reproduced in the dense
sampling, and recorded rather than explained away.

Deploy: `lib/JLine3.jar` md5 `5e384e7d7f8e4b1c...` → `e8274f88be144842...`, entries that moved
`org/jline/utils/WCWidth.class` and `org/jline/utils/AnsiWidthTables.class`, set 746 → 747 class entries,
added 1 / removed 0, then every listed entry read back out of the jar byte-for-byte
(`verify_current.py`), and the post-deploy census against the tree is 183/183 identical.
`cache/wcwidth-1010/verify-jar-1010.py` re-ran the four-face differential **with the jar first on the
classpath**: same 1,112,000 / 64 / 0-unexplained result, so the shipped bytes are the measured bytes.

`lib/dbcli.jar` also moved one entry, `org/dbcli/Console$1.class`: census found its `LineNumberTable` sitting
6 lines behind `Console.java` while `javap -p -c` diffed 0 lines -- last round's `ship` list named
`Console.class` and its siblings but not the anonymous class, so it kept the bytes of an earlier staging pass.
Its stack frames named lines that hold other statements. Same md5-independent check as everywhere else:
112 entries before, 112 after, one moved, read back byte-identical.

### Two things the probe turned up that are not this round's, recorded so the next reader does not re-derive them

- **A box-drawing rule template does not go out as U+2500.** `BorderTile.java` fed `Status.setBorder` the
  single glyph `─` and the emitted bytes were `ESC(0` + `q` x n + `ESC(B` -- jline's alternate-charset path,
  driven by the terminal's `enacs`/`exit_alt_charset_mode` caps. Whether a given host draws that as a line was
  not tested here -- xterm honours DEC special graphics, and no leg in this session asked Windows Terminal or
  conhost. It is completely independent of the width table: U+2500 is one column in the old Kuhn answer, in
  the new generated answer, and in the grid. dbcli's template is `-` (`Console.java:759`), so
  nothing in the shipping app is on that path today. Not fixed, not claimed broken -- just named.
- **`src/c/conemu/ANSI_TODO.md` is gone from both trees** (`D:\dbcli` and `D:\Green\github\dbcli`), and it was
  never tracked in git, so `git log` cannot say when. The newest copies found are `cache/topfix/ANSI_TODO-533a.md`
  (476 KB, 2026-10-07 18:50) and `cache/ANSI_TODO.pre-move10.bak` (2026-09-27 23:46). This round's ledger went
  into `JLINE_CHANGES.md` and `DESIGN.md` because that is where a JLine3 change belongs anyway, but the ticket
  table's own rows (#108, #116, #122 and the rest) now have no live home -- if another session did not move it
  on purpose, somebody has to decide where it goes before the next ticket work starts.

### Not covered

- `D:\Green\github\jline4` and `D:\JavaProjects\jline4` still carry Kuhn's `WCWidth` untouched. The owner's
  standing ruling is that no jline4 jar goes into `lib`, so this is a known divergence between the two trees
  rather than a stale deploy -- but the next jline4 merge must either regenerate its table the same way or
  carry the disagreement forward on purpose, and nothing in this round decides which.
- No leg ran in classic conhost on MS Gothic / 新宋体 with this change deployed. The width claim rests on the
  2026-10-08 cursor measurements (which measured the console, not JLine) plus the source cross-check above;
  a `top`/`more` leg whose rows contain `Ⅰ ℃ ⑴ ●` read back through `ReadConsoleOutputW` would close the
  loop, and the probe's *input* path is not a usable way to get those glyphs on screen -- in the 60-column
  leg the typed `────▀▄█` reached the session as `qqqq▀▄█`.
- pyte, the headless leg's cell model, counts ambiguous as 1 like WT does, so a ConPTY leg cannot witness the
  conhost half. Its frames were still the right instrument for the cursor/overflow question.
- The `WIDTH CHECK` leg covers the two trees on this box. A clone elsewhere has no leg until its owner sets
  `DBCLI_JLINE_TREES`; without it the check says out loud that it looked at one tree.



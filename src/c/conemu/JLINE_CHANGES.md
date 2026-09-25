# JLINE_CHANGES.md — every edit this project made to JLine itself

**Scope.** Anything under `D:\JavaProjects\jline3.29` **except** `dbcli/` (our application) and the renderer's
own Java (`com.hyee.ansirender`, which lives in `dbcli/src`). So: `terminal`, `reader`, `builtins`, `curses`,
`console`, `jansi`, `native`, and their resources. If a file in one of those is not upstream, it belongs on
this page. Files under `dbcli/` are ordinary project code and are documented where they live
(`dbcli/src/org/dbcli/*.java`, the tracker, and DESIGN.md §10 for anything that carries a task number).

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

Against the fork commit (`a1f0ffc1`, not stock upstream) this work stream changed exactly four files:

| File | Differing lines | Ours, or the fork's? |
|---|---|---|
| `terminal/src/main/java/org/jline/utils/Status.java` | 177 | ours (#23, #33, #41, #43, #46's callee, #47, #48) |
| `terminal/src/main/resources/org/jline/utils/windows-conemu.caps` | 33 | ours (#10, #12, #19, #29) |
| `reader/src/main/java/org/jline/reader/impl/LineReaderImpl.java` | 39 | ours (#41) |
| `terminal/src/test/java/org/jline/utils/StatusTest.java` | new file | ours (#47, #48) |

Three more differ between the two checkouts and are **not** this work stream's: `keymap/KeyMap.java` (+238/-3,
the 2025 fork commit), `utils/Display.java` (uncommitted in the *Green* checkout only), and
`console/src/test/.../TailTipWidgetsTest.java`. Do not "fix" those against `c5a8bf12` — they are somebody
else's in-progress port.

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
renderer both actually act on (#12's 81-assertion audit, #19, #29); `ncv`, `blink`, `invis`, `mir`, `smam`,
`smkx`, `flash`, `initc`/`ccc`, `kbs`, `kf13`+ and the shifted-arrow names were kept **out**, each with its
reason inlined in the entry's description line.

**Why render.dll could not absorb it:** the entry is what the reader reads to decide which bytes to write. A
lying terminfo is worse than a short one, because JLine complies with it instead of re-checking — no amount of
renderer robustness undoes `Display` trusting an `am`/`xenl` claim that is false.

**Witness.** `cache/caps-audit/` (`CapsDump.java`, 81 assertions through `tputs`), run against the source file
**and separately against the copy inside the shipped `lib/JLine3.jar`** — `CAPS CHECK: ok` on both, byte-identical
(#12). Read the caps entry's own comment before editing it; every omission in it is a measured result.

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

**Upstream report owed.** Filing it is a public action against someone else's repository and was left for a
human. Draft with evidence and citations: `cache/p52/jline4-sixel-report.md`. Related: DESIGN.md §10 row 52.

## `terminal/src/test/java/org/jline/utils/StatusTest.java` (added)

A new file, so it changes no library behaviour, and it is still the highest-value item here: it is what lets a
geometry fix be argued about with a red/green pair instead of with prose. `ScreenTerminal.java` already existed
as the fixture; `Runner.java` (in `cache/status47-48-20260925/`) is a one-argument-per-case JUnit launcher,
because the fork's maven build is not what these legs run against.

---

## What is not witnessed

Recorded rather than smoothed over, in the same spirit as DESIGN.md §10:

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
  witnessed gone" — the distinction is written the same way in DESIGN.md §10's #43 row.
- **`resize(Size)`'s erase-then-redraw has no unit case.** The five live arms above are its witness, and they
  were taken against a deployed jar, not against a class under test.
- **`LineReaderImpl` has no automated coverage at all.** Its fix is a five-arm live matrix.
- **`StatusTest` cannot red-arm against an older jar for the border-template cases** — an unpatched `Status`
  has no `setBorder(AttributedString,int)` to link against, so their control is the real-terminal leg and the
  `/tmp`-revert arm above, not `run-test.sh --control`.

# WORK_ORDER — render.dll feature supplement (executable)

Handed to the developing agent for execution. Snapshot 2026-09-25; line numbers are from that
snapshot and WILL drift — locate by function/symbol name, never by line number.

## 0. Read before writing code (in this order)

1. `D:\dbcli\.dsh\memory\MEMORY.md` — section 1 ("工作约定") is binding; `project-conemu-writer-perf`
   holds the full history of this component.
2. In this directory: `ANSI_SUPPORTS.md` (current support matrix) → `ANSI_TODO.md` (the rationale for
   every task below; note §8's two contract warnings) → `DESIGN.md` (invariants I1–I31, §8 build/gate
   discipline, §10 task ledger) → `MSFT_TERMINAL_REFERENCE.md` (the S1–S8/B1–B7 adjudications — they
   say what NOT to borrow) → `CONEMU_ANSI_DEFECTS.md` (upstream defects; prevents copying their bugs).

### Hard constraints (violating any of these = redo the work)

- **The gates are the spec.** Every step's definition of done is: `build.sh` host gate (RenderCheck)
  green AND `run.ps1` live gate green on BOTH architectures. Write the failing case first (red), then
  implement (green); the control-build discipline is DESIGN §8.
- **The census is positionally contracted.** `RC_UN_*` slot indices are NEVER renumbered (Render.h:78
  comment; RenderJni.cpp reads stats by position and the Java side hardcodes indices). Adding a counter
  means changing C + RenderJni.cpp + Render.java in ONE change set; read the stats-layout comment in
  RenderJni.cpp (~:1400) first to know the shift surface.
- **Edit discipline.** Targeted edits on large files; never rewrite a file wholesale. Comment style
  follows the existing files (every rule carries its upstream/reference coordinates). Never hand-edit
  `vendor/*` or the `gen_rgbmap` output (build.sh re-derives and compares them).
- **Nothing lands in `lib\`.** All builds and verification run out of `cache\native-probe\`. Deploying
  `lib\{x86,x64}\render.dll` requires asking the user first; when approved, back up and record md5 for
  both architectures per house convention.
- **Rulings that must not be reopened**: I7 (model row = buffer row), S2/deferred wrap (decided: not
  implemented), I19 (count + self-heal semantics), `it#8`/fixed-8 tab stops (second-interpreter
  consistency).
- Build note: MinGW cross-build runs in WSL; build.sh's Win8+ API whitelist **rejects
  `GetTickCount64`** — T3's timeout clock lives in the JNI layer and must use `GetTickCount` with a
  wrap-safe comparison. Do not introduce whitelisted APIs.

### Build / gate commands

```sh
# WSL (host gate runs inside the build; both render.dll land in cache\native-probe)
cd /mnt/d/dbcli/src/c/conemu && bash build.sh
```
```powershell
# live gate (D:\jdkx86 / D:\jdkx64; asserts cells read back out of conhost)
pwsh -File D:\dbcli\src\c\conemu\run.ps1 -Arch both
```
New behavior gates go into `RenderCheck.cpp` (host, no console needed); assertions that need a real
console go into `Render.java` (follow the `caseReports` / `caseSuspectAlign` style: assert on cells
read back and on CONIN$ text — never on the screen string alone).

### Concurrent-development discipline (parallel edits already exist in this tree)

- **Re-verify before you write.** Before each task, re-read the target function's CURRENT
  implementation and check it was not already done or half-done by a concurrent change (latest rows of
  the DESIGN §10 ledger + whether a census slot/gate already exists). Skip landed tasks and mark the
  ledger "already landed by a parallel change"; NEVER redo or revert someone else's change.
- **Anchors drift.** Every `file:line` in this order is a snapshot; locate by symbol name and
  re-read the region immediately before editing (pin + re-verify, an established house rule).
- **Keep the tree compilable at every save.** `build.sh` compiles the WHOLE directory — your
  half-finished edit breaks everyone else's build. Small targeted replacements, one edit point at a
  time; split long tasks (T3) into independently compilable saves: model bit → execution gate → escape
  hatches → gates.

---

## 1. Task overview (execute in order)

| # | Task | Priority | Size | Depends on |
|---|---|---|---|---|
| T1 | `CSI ?u` private-marker gate (real bug: jline4's probe batch teleports the cursor) | P0 | ~2 lines + 2 gates | none |
| T2 | interim bytes: single slot → set (pure refactor, zero behavior change) | prerequisite | medium | none |
| T3 | DECSET 2026 synchronized output (with timeout / overflow / decline paths) | P1 | large | independent of T2 |
| T4 | mode table + DECRQM/DECRPM replies | P1 | medium | T2, T3 |
| T5 | HPR `CSI a` / VPR `CSI e` (compatibility reserve) | P2 | small | none |
| T6 | census metadata registry | optional | small | after T4 |
| T7 | OSC 9 safe subset: `9;4` progress / `9;9` cwd / `9;12` prompt-start, per WT's `DoConEmuAction` | P2 | medium | after T4 (stats slot table) |

## 1.1 Parallel-execution topology (if multiple sub-agents are used)

The dependency structure supports **two serial phases with a two-lane middle** — maximum useful
parallelism is 2, NOT one agent per task:

```
Phase 0 (mainline, 1 agent): T2 — reshapes the shared csi_dispatch/echoes signatures; T4/T5 sit on
                             top of them, so T2 goes first.
Two lanes (ownership split; each lane runs gates with its OWN --scratch; never clean the other's):
  Lane A: RenderJni.cpp exclusively — T3 execution gate (sync hold / timeout / overflow / decline /
          stats tail).
  Lane B: Render.cpp + Render.h + RenderCheck.cpp exclusively — T1, T5, T3 model side (sync bit +
          h/l branch + rc_in_sync accessor).
Phase 1 (mainline, after merge): T4 (folds T3's ?2026 branch into the mode table + DECRPM replies)
          → T6.
Merge order: B first (small) → A; after merging, rerun the FULL host+live gates on the merged tree.
```

Two contracts must be fixed BEFORE the lanes start (this is where multi-agent work dies):

1. **sync interface contract**: Lane B lands the `rc_in_sync(g)` accessor and the set/clear points
   first; Lane A depends only on the accessor and NEVER touches `RcGrid` fields — Render.h ownership
   is one-sided (Lane B).
2. **stats slot allocation table**: Lane A's `nSyncEngages/nSyncHeld/nSyncTimeout/nSyncOverflow` and
   T4's future DECRPM reply slot get their numbers NOW, in writing — under the census positional
   contract, two agents appending independently will collide.

Live cases (Render.java) may be written by both lanes ONLY as owner-prefixed append-only blocks
(`caseU…` / `caseSync…`), so merging is a pure append. The ledger (DESIGN §10) and
`ANSI_SUPPORTS.md` are written by the mainline only, after the merge. Whether to use git worktrees
depends on which repo the src tree belongs to (see `reference-dbcli-git-repo`: the dbcli repo lives at
`D:\Green\github\dbcli`); if unsure, fall back to a full-tree copy + manual diff merge.
**Parallelism criterion**: lanes must not share files AND the serial critical path must exceed half a
day — for this order, parallelism = 2; more sub-agents is negative yield.

## 1.2 Refactoring policy (read before T2/T4/T6)

The SANCTIONED refactorings are exactly three, and each is bound to a feature in this order — scoped
to consolidation (identical semantics, gates green, census equal item by item):

1. T2 — interim bytes slot → set (dimension fix, prerequisite of T4);
2. T4's mode table — the `h/l` if-chain becomes a `RcModeDef` table (DECRQM is its first consumer);
3. T6 — census metadata registry (documentation debt only).

Beyond these three, **no re-architecture in this round**:

- Do NOT introduce a dispatch interface layer (à la MSFT `ITerminalDispatch`), do NOT split
  parser/model into separate layers, do NOT convert rows to RLE/three-plane storage, do NOT add
  reflow or font-dependent width queries. The reasons are on file in `MSFT_TERMINAL_REFERENCE.md`
  §13 (B1/B6/B7): this tree has one parser, one writer, one consumer; MSFT/ghostty built those layers
  to solve multi-consumer problems that do not exist here.
- Re-evaluate ONLY on these triggers: (1) a census family stays non-zero on real streams and must be
  modeled (e.g. `RC_UN_COLON` — at that point `args` grows sub-parameter ranges à la WT's
  `_subParameterRanges`); (2) a second consumer of the parser appears (only then does Parser/Model
  separation pay); (3) a third collision on the interim/sub-parameter dimensions.
- If you believe a refactoring outside this list is warranted: STOP and ask the user. The gates pin
  several thousand assertions; restructuring without a driving feature is the one anti-pattern this
  codebase explicitly records against.

---

## 2. Task specifications

### T1 — private-marker gate on `CSI ?u`

- Current behavior: `csi_dispatch` `case 'u'` (Render.cpp ~:1117) does not check `priv`, so
  `CSI ?u` — the kitty keyboard **query** — executes as DECRC and restores the cursor to the last
  DECSC position.
- Trigger: jline4 `AbstractTerminal.probeModes()` (AbstractTerminal.java:620-631) sends one batch
  `CSI ?u + CSI ?2026$p + CSI ?2027$p + CSI ?2048$p + CSI c` on the first `isModeSupported()` call;
  the reader fires it whenever `Option.KITTY_KEYBOARD` is set (LineReaderImpl.java:703).
- Fix: `case 'u': if (g->priv) { ignored(g, RC_UN_MODE); break; } clxy(g, g->saveY, g->saveX); break;`
  — bare `CSI u` unchanged; `?u` counts, is NOT suspect, and gets NO reply (the kitty keyboard
  protocol is out of scope this round; jline4's DA1 fence reads the missing DECRPM as NOT_SUPPORTED,
  which is safe and intended).
- Gates: host case — "`?u` moves no cursor + one `RC_UN_MODE` vote + `modelSuspect` stays clear" and
  "bare `CSI u` still restores". Live — `Render.java` replays the probe batch above and asserts the
  cursor does not move across the `?u`.

### T2 — interim bytes: slot → set (pure refactor)

- Current: `RcGrid.interim` is a single slot (Render.h ~:285); three consumers are mutually exclusive:
  DECSCUSR's `' '`, DECSTR's `'!'`, and T4's `'$'`. The CSI parameter loop (Render.cpp ~:1743)
  overwrites the slot on every 0x20..0x2F byte.
- Change: `RcGrid` gains `uint8_t interims[RC_INTERIM_MAX]` (4 is enough) + `nInterims`; the loop
  appends (bytes past the cap are dropped, matching ConEmu's single-read lazy semantics);
  `csi_dispatch`/`echoes` switch their `uint8_t interim` parameter to a
  `bool has_interim(const RcGrid*, uint8_t ch)` query. The `RC_ESC_INTERIM` charset path
  (`(`/`)`/`%`) is UNCHANGED. `csi_start` (~:1343) clears.
- Definition of done: ZERO behavior change — host/live green with the census equal item by item;
  three regression pins: "`CSI 2 SP q` still sets the cursor shape", "`CSI !p` still full-resets",
  "a final with an unknown interim still counts `RC_UN_SUP`".

### T3 — DECSET 2026 synchronized output

- Model side (Render.cpp/h): `RcGrid` gains `uint8_t sync;`; the `h/l` arm takes `?2026` (folded into
  the mode table in T4); `full_reset`/`rc_reset_hist` clear it; a nested BSU is a no-op (counted).
  Emitter: jline4 `Display` full-screen updates (Display.java:134/495/846) and
  `Terminal.begin/endSynchronizedUpdate` (Terminal.java:1505/1529).
- Execution side (RenderJni.cpp — the model stays console-free): while `sync` is set, flush computes
  but does NOT write — `rc_plan_paint` still runs (CPR reply arithmetic needs the plan's row0/winTop),
  but every console call (rectangles/attributes/cursor/scrolls) is skipped; when sync ends
  (ESU / timeout / overflow / decline) call `rc_mark_all_dirty` so the next frame repaints fully.
  Do NOT merge plans — the full repaint is the only merge-error-free convergence.
- Three escape hatches (missing any one = hang or corruption; each gets a gate):
  1. **Timeout**: timer in the JNI layer (`RcHandle` stores the entry timestamp; `GetTickCount` with
     wrap-safe comparison). Take the value from conhost's own synchronized-output constant — find it
     in the msfterm clone (`cache/msfterm`, grep synchronized/VtIo); do not invent a number. On expiry,
     treat as sync end + count.
  2. **Capacity overflow**: the holdable bound during sync = gutter (`rc_scroll_room`) + winRows. A
     sync interval spanning more output than that MUST release the current frame and count —
     otherwise a full gutter lets `scroll_up` evict unpainted history (I9's constraint applies to the
     `onFlush` hook under sync too).
  3. **Declined chunk**: a declined chunk (replayed to conhost) ends sync and counts — the model is
     no longer trustworthy; take the existing align/adopt path.
- Replies are never held: `flush_reports` belongs to the reader (I29; ANSI_TODO §8.2) and writes to
  CONIN$ during sync. CPR row arithmetic uses the computed plan even when that plan is not executed.
- Counters: `nSyncEngages / nSyncHeld / nSyncTimeout / nSyncOverflow` (stats tail; three-sided change
  + a census-layout assertion).
- Gates: host — "BSU→write→ESU ⇒ zero console calls, then one full frame", "BSU→timeout ⇒ release +
  count", "nested BSU is a no-op", "`CSI 6n` still answers during BSU", "`full_reset` clears sync";
  live — replay a `Display` full-screen update byte stream (BSU/ESU wrapped) and assert the console
  content changes only on the ESU frame, with no double writes.

### T4 — mode table + DECRQM/DECRPM replies

- Table-driven: a static `struct RcModeDef { int id; get; set; }` table absorbs the existing `h/l`
  families: 25 (cursorVisible), 47/1047/1049 (alt), 1048, 2026 (from T3), 2004 (stored bit, see the
  DECRPM paragraph below), mouse 9/1000/1002-1004/1005/1006/1015 (count `RC_UN_MOUSE`), everything
  else (`RC_UN_MODE`). Semantics identical per family — this is consolidation, not redesign.
- DECRPM replies: `CSI ? Ps $ p` (parseable after T2) → new `arm_report` kind `RC_REP_DECRPM`;
  `RcReportItem` gains `uint16_t param`; `reply_text` emits `\e[?Pd;Ps$y`. Reply values: 25/1048 →
  `cursorVisible` as 1/0; 47/1047/1049 → `g->alt`; 2026 → `g->sync`; **2027 and 2048 → 4 (permanently
  reset)** — jline4 reads 3 as SUPPORTED and 4 as NOT_SUPPORTED (DecModeProbeTest :386-388), so
  answering 4 makes it take its fallbacks: 2027 keeps its own grapheme-cluster grouping, 2048 stays
  off (both are the intended outcomes, see ANSI_TODO §4/§8). Parameterized/non-private `$p` keeps
  counting.
- `?2004` (bracketed paste) is PROMOTED from "counted and dropped" to a **stored mode bit** in the
  table: h/l set/clear it, DECRPM answers its state (2 = reset-but-settable / 1 = set), and the bit
  is exposed to the host so dbcli's input pump MAY wrap paste bursts in `\e[200~/\e[201~` when the
  reader asked for it (jline4's consumer side already exists: `LineReaderImpl` BEGIN_PASTE binding
  :7088). The DLL itself NEVER synthesizes paste markers and NEVER reads CONIN$ — markers must
  precede the pasted bytes, which conhost injects as one burst, so peek-then-inject cannot win the
  race and reading would steal the application's keystrokes. The `RC_UN_DECBP` slot stays in the
  census as a dead slot (positional contract), exactly like `RC_UN_DECSTBM`.
- Ordering contract: jline4's fence is "DECRPM present before the DA1 reply ⇒ supported". The probe
  batch arms queries in arrival order and the queue is FIFO, so DECRPM×3 precede DA1 naturally —
  NEVER reorder the arming.
- Gates: host, per-mode reply-text assertions (including 2027/2048 = 4); live — `Render.java` replays
  the full probe batch and compares the whole CONIN$ text sequence
  (`\e[?2026;…$y\e[?2027;4$y\e[?2048;4$y\e[?61;…c`, in order) — this is exactly the byte stream
  jline4's `parseDecrpm`/`parseSixelFromDa1` will consume.

### T5 — HPR `CSI a` / VPR `CSI e`

- `'a'` → CUF-equivalent: `clxy(g, g->cy, g->cx + arg(g,0,1))`; `'e'` → VPR:
  `clxy(g, g->cy + arg(g,0,1), g->cx)` — deliberately NOT via `move_row`'s scroll-region clamp: MSFT's
  comment says VPR is "unlike CUD not constrained by margin" (adaptDispatch.cpp:437); ghostty agrees
  (stream.zig:1942). Removed from `ignored(RC_UN_SUP)`.
- ⚠ **An existing gate must flip**: RenderCheck's `geo_region` tail block asserts the current
  partition ("a/e counted and move nothing") — flip the expectation to "they move and no longer
  count" and write the flip reason in a comment (parity retired; follow the I25 `legsSame` precedent).
  Update the matching row in `ANSI_SUPPORTS.md` §3.

### T6 — census metadata registry (optional, after T4)

- Centralize `RC_UN_*` name / suspect-bit / description into one static registry table queried by
  `unsupported()`/`ignored()`; slot order and the stats layout stay EXACTLY as they are. This
  consolidates documentation debt, not behavior — done when host is green and the census is equal
  item by item.

### T7 — OSC 9 subcommand dispatch (safe subset per WT's `DoConEmuAction`)

- **Precedent (verified in the msfterm clone)**: microsoft/terminal `AdaptDispatch::DoConEmuAction`
  (adaptDispatch.cpp:3558) implements the SAFE face of ConEmu's own dialect — `9;4` taskbar progress
  (state 0..4, progress clamped to 100, :3574-3606), `9;9` working directory (strips ConEmu's
  surrounding quotes `9;"D:/"`, :3608-3629), `9;12` prompt-start marker (WT's own comment:
  "basically the same as 133;B", :3631-3641) — and routes EVERYTHING ELSE to
  `_api.UnknownSequence()` (:3643-3646). The dangerous ConEmu subcommands (`9;1` sleep, `9;2`
  MessageBox, `9;3` set env, `9;7` DoProcess) are implemented by NOBODY in the reference set.
- Current behavior in this tree: the whole `9` family counts `RC_UN_OSC_PRIV` and never acts
  (`osc_finish`, Render.cpp ~:1582).
- Change: inside the `code == 9` branch, parse the subcommand (digit run up to the next `';'`):
  - `9;4;<state>[;<progress>]` → store `{state, progress}` (state clamped 0..4, 0 = remove;
    progress clamped 0..100) in model-side state; expose via stats tail (slots come from T4's
    allocation table). No taskbar call from the DLL — the console window belongs to conhost
    (cross-process ITaskbarList3 is unverified); dbcli renders progress on its own status bar.
  - `9;9;<path>` → strip one pair of surrounding `"` (ConEmu's spelling), basic legality check
    (WT: `til::is_legal_path`), store the path model-side, expose. NEVER `SetCurrentDirectory` from
    the output stream — process side effects are the host's decision.
  - `9;12` → route to the exact code path of FTCS `133;B` (I23), which is the same claim.
  - Everything else — including `9;1/9;2/9;3/9;7` and a `9` with no digits — keeps counting
    `RC_UN_OSC_PRIV` and never acts. Unterminated `9;…` payloads keep counting without applying
    (same rule as titles and 133).
- Gates: host — "`9;4;1;50` stores state=1/progress=50 and clamps 150→100", "`9;9;\"D:/\"` stores
  D:/ with quotes stripped", "`9;12` behaves identical to `133;B`", "`9;7;calc.exe` counts
  `RC_UN_OSC_PRIV`, stores nothing, spawns nothing", "unterminated `9;4` counts, applies nothing";
  live — census visibility on the real leg. Update the matching rows in `ANSI_SUPPORTS.md` §2.8/§3
  and the ledger.

---

## 3. Definition of done (every task, all items)

1. `build.sh` → `BUILD: ok`, RenderCheck 0 failures (including this task's new cases, each of which
   was red before the fix and green after);
2. `run.ps1 -Arch both` green on both architectures;
3. census: pre-existing slots keep their semantics (T2/T6 require item-by-item equality); new counters
   consistent across C / RenderJni.cpp / Render.java;
4. docs updated in the same change: the matching row in `ANSI_SUPPORTS.md`, a new row in the DESIGN
   §10 ledger, and — when a new deviation or ruling emerges — an entry in `CONEMU_ANSI_DEFECTS.md` or
   `MSFT_TERMINAL_REFERENCE.md`;
5. long-lived facts written back to `.dsh\memory\` per the AGENTS.md convention (pointer rows into the
   MEMORY.md index).

## 4. Explicitly out of scope (prevents scope creep)

- **Architecture changes beyond §1.2's three sanctioned refactorings** — same rule as features: the
  list in §1.2 is closed; extensions go through the user;

- Everything in ANSI_TODO §7 stays: mouse/focus/DECCKM/kitty-keyboard mode bits, bracketed-paste
  **marker synthesis inside the DLL** (the `?2004` mode BIT itself is T4's stored state — the
  role-mismatch rationale for why the DLL never synthesizes markers is in ANSI_TODO §6/§7), deferred
  wrap, graphics protocols, italic/strikethrough painting, **the dangerous OSC 9 ConEmu subcommands**
  (`9;1/9;2/9;3/9;7…` — never executed, #687; the safe subset is T7), OSC 8,
  DECOM/DECLRMM, configurable tab stops;
- Two names that used to sit in that list have since landed, and one was closed by ruling: OSC 4/10/11 at
  build -20 (I34), OSC 52 at -24 (I36 — off by default, enableable only by the host), and OSC 8 by the
  user's decision on 2026-09-26, with the technical debt that keeps it closed written into `ANSI_TODO.md` §7
  rather than left as a preference;
- The jline4-side work (SIXEL family-level refusal) is DONE — nothing in this order touches jline4;
- The kitty keyboard query (`?u`) counts and never answers — the DA1 fence on jline4's side is part of
  the design; do NOT "helpfully" implement the kitty protocol.

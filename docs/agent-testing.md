Headless dbcli testing (`agent-test.ps1` / `agent-test.sh`)
===========================================================

Runners for agents, harnesses and CI: they drive dbcli without a console, capture
stdout/stderr byte-exactly, and return a machine-readable verdict. Written because a
console-less environment used to abort dbcli before it printed anything, and because dbcli's
own exit code cannot distinguish success from a failed `login` or a SQL error.

| File | Platform | Invoke |
|---|---|---|
| `agent-test.ps1` | Windows (PowerShell 5.1+/7) | `pwsh -File .\agent-test.ps1 -Login o19c -Commands "…"` |
| `agent-test.cmd` | Windows shim | `.\agent-test.cmd -Login o19c -Commands "…"` |
| `agent-test.sh` | Linux / macOS / WSL | `bash ./agent-test.sh --login o19c --commands "…"` |

Both runners accept the same inputs and produce the **same artifact set, verdict and JSON
fields**; only the flag spelling differs (`-Login` vs `--login`). Examples below use the
PowerShell form — see [Cross-platform flags](#cross-platform-flags) for the shell spelling.

- [Quick start](#quick-start)
- [What it does](#what-it-does)
- [Parameters](#parameters)
- [Cross-platform flags](#cross-platform-flags)
- [Artifacts](#artifacts)
- [The JSON contract](#the-json-contract)
- [Verdict rules and exit codes](#verdict-rules-and-exit-codes)
- [Recipes](#recipes)
- [Troubleshooting](#troubleshooting)
- [Gotchas](#gotchas)

---

Quick start
-----------

```powershell
cd D:\dbcli

# simplest run
pwsh -File .\agent-test.ps1 -Login o19c -Commands "select 1 c1 from dual;"

# run a real dbcli script and fail the process on any error marker
pwsh -File .\agent-test.ps1 -Login o19c -Commands "ora actives -new" -Json -Strict

# other platforms use their own launcher
pwsh -NoProfile -File .\agent-test.ps1 -Db mysql -Login my57 -Commands "select 1 c1;"
pwsh -NoProfile -File .\agent-test.ps1 -Db pgsql -Login pg16 -Script .\my.sql

# cmd shim, identical arguments
.\agent-test.cmd -Login o19c -Commands "select 1 c1 from dual;"
```

`-Commands` / `--commands` splits on `;;`, which is a **separator only** — it does not
terminate anything, so each SQL statement still needs its own `;`:

```powershell
-Commands "select 1 a from dual;;select 2 b from dual;"   # two statements, both terminated
-Commands "select 1 a from dual;;select 2 b from dual"    # WRONG: the first never ends -> ORA-00933
```

A `login` and a trailing `exit` are added automatically unless the command list already
contains them.

```bash
# the same thing under Linux / macOS / WSL
cd /mnt/d/dbcli
bash ./agent-test.sh --login o19c --commands "select 1 c1 from dual;"
bash ./agent-test.sh --login o19c --commands "ora actives -new" --json --strict
```

---

What it does
------------

1. Locates the install (`-Dir` > `$env:DBCLI_HOME` > the script's own directory > current
   directory) and picks the launcher for `-Db`.
2. Builds the command list, writes it to `in.txt`, and starts the launcher
   (`cmd.exe /c <launcher>` on Windows, `./<launcher>` on Linux/macOS/WSL) with stdin, stdout
   and stderr all redirected and no console attached.
3. Sets `COLUMNS`/`LINES` in the child environment. The current build lets a JLine dumb
   terminal pick those up, so results have a **deterministic width** instead of whatever the
   ambient console reports (this is what removes the width-dependent layout surprises).
4. Drains both pipes, feeds the commands, waits up to the timeout, then kills on timeout.
5. Restores the caller's environment and derives a verdict from the captured output.

No console is required. On the current `lib\dbcli.jar` the launcher tries the Windows console
first, catches the failure and falls back to a dumb terminal automatically, so `MSYSTEM` is
**not** needed any more (`-ForceMsys` remains only for the older jar). The shell runner's pipe
path reaches the same dumb terminal through JLine on Linux/macOS/WSL.

---

Parameters
----------

| Parameter | Default | Meaning |
|---|---|---|
| `-Db` | `oracle` | `oracle` -> `dbcli.bat`, `mysql` -> `mysql_dbcli.bat`, `pgsql` -> `pgsql_dbcli.bat` |
| `-Dir` | — | install directory; else `$env:DBCLI_HOME`, else the script dir, else cwd |
| `-Login` | — | connection alias; prepended as `login <alias>` unless the list already logs in |
| `-Commands` | — | command list, split on `;;` (a separator only — keep each statement's `;`) |
| `-Script` | — | a `.sql` file fed line by line (mutually substitutable with `-Commands`) |
| `-Cols` / `-Rows` | `150` / `40` | terminal size exported as `COLUMNS` / `LINES` |
| `-Linesize` | `0` | when > 0 prepends `set linesize N` |
| `-OutDir` | `agent-out\<timestamp>` | where the artifacts go |
| `-TimeoutSec` | `240` | wall-clock cap; timeout gives `exitCode -1` and a FAIL verdict |
| `-KeepAnsi` | off | keep ANSI escapes; `stdout` then points at `out.txt` |
| `-NoSize` | off | do not set `COLUMNS`/`LINES` |
| `-ForceMsys` | off | legacy switch for the pre-2026-09-13 jar |
| `-Match` | — | regex that **must** appear in stdout |
| `-NoMatch` | — | regex that must **not** appear in stdout |
| `-NoDefaultPatterns` | off | disable the built-in error-marker scan |
| `-IgnorePattern` | — | drop individual default-pattern hits (for probes that raise errors on purpose) |
| `-Json` | off | print one compressed JSON object instead of prose |
| `-Quiet` | off | print nothing (pair with `-Strict` and read the exit code) |
| `-Strict` | off | exit 1 when the verdict is not `PASS` |
| `-Keep` | `20` | timestamped runs to keep under `agent-out`; `0` disables pruning |

---

Cross-platform flags
--------------------

`agent-test.sh` mirrors every capability above using GNU-style long options:

| `agent-test.ps1` | `agent-test.sh` |
|---|---|
| `-Db` / `-Dir` / `-Login` | `--db` / `--dir` / `--login` |
| `-Commands` / `-Script` | `--commands` / `--script` |
| `-Cols` / `-Rows` / `-Linesize` | `--cols` / `--rows` / `--linesize` |
| `-OutDir` / `-TimeoutSec` | `--out` / `--timeout` |
| `-Match` / `-NoMatch` / `-IgnorePattern` | `--match` / `--no-match` / `--ignore-pattern` |
| `-NoDefaultPatterns` | `--no-default-patterns` |
| `-Json` / `-Quiet` / `-Strict` | `--json` / `--quiet` / `--strict` |
| `-KeepAnsi` / `-NoSize` / `-Keep` | `--keep-ansi` / `--no-size` / `--keep` |
| `-ForceMsys` | *(no equivalent — Windows-only console quirk)* |
| — | `--pty` *(shell only: run under a real pty, see below)* |

The JSON output is field-for-field identical, so a harness can parse one shape from either OS.
`agent-test.sh --help` prints the embedded usage block.

### `--pty` (shell only)

By default the shell runner uses the pipe path, exactly like Windows: dbcli falls back to a
JLine dumb terminal and `COLUMNS`/`LINES` give it a deterministic width. `--pty` instead wraps
dbcli in `script(1)` so it sees a **real tty** (no dumb fallback) — use it when you are testing
behaviour that depends on a terminal.

```bash
bash ./agent-test.sh --login o19c --pty --cols 120 --rows 30 --commands "select 1 c1 from dual;"
```

Two pty caveats, both inherent rather than bugs:

- `script(1)` echoes the stdin command list into the capture, and dbcli's readline re-echoes the
  line it reads, so `out.txt` contains those command lines as well as the results. Do not anchor
  on the first lines; match on content (`--match`, or patterns after the banner).
- `--pty` report includes `"pty":true` and, with a real tty, `dumbTerminal` is `false` — the
  opposite of the pipe path, and a useful check that the pty really was established.

---

Artifacts
---------

`-OutDir` defaults to `<install>\agent-out\<yyyyMMdd-HHmmss>\`:

| File | Contents |
|---|---|
| `in.txt` | the exact command list written to stdin — an echo of what actually ran |
| `out.txt` | raw stdout, ANSI escapes intact |
| `out.plain.txt` | stdout with ANSI stripped — **use this for matching and diffing** |
| `err.txt` | stderr, verbatim |

With `-KeepAnsi` only the raw form is kept and the `stdout` field points at `out.txt`.
When `-OutDir` is omitted, old timestamped runs are pruned down to `-Keep`.

---

The JSON contract
-----------------

`-Json` prints exactly one compressed JSON object (and nothing else), so a harness can:

```powershell
$r = pwsh -NoProfile -File .\agent-test.ps1 -Login o19c -Commands "ora actives" -Json -OutDir $tmp |
     ConvertFrom-Json
if (-not $r.ok) { throw ($r.problems -join '; ') }
Get-Content $r.stdout
```

| Field | Meaning |
|---|---|
| `ok` | `true` iff `verdict` is `PASS` |
| `verdict` | `PASS` / `FAIL` |
| `problems` | array of human-readable reasons; empty on `PASS` |
| `stdout` / `stderr` / `outDir` | artifact paths |
| `exitCode` | dbcli's process exit code (`-1` on timeout) |
| `timeout` | `true` if `-TimeoutSec` elapsed |
| `elapsedSec` | wall-clock duration of the run |
| `stdoutBytes`, `ansiEscapes` | size and escape count of raw stdout |
| `colwrapNoise`, `dumbTerminal`, `attachError` | diagnostic flags normally `false` / `true` / `false` |
| `db`, `login`, `install`, `cols`, `rows`, `linesize`, `commands` | echo of what ran |

---

Verdict rules and exit codes
----------------------------

A run is `FAIL` when any of these hold:

- stdout is empty, or the process timed out or never exited;
- the output pipes did not drain in time (the tail may be missing);
- stderr carried anything other than the known dumb-terminal chatter;
- stdout matched an error marker. Defaults: `ORA-`/`PLS-`/`SP2-`/`DBC-`/`MIS-`/`SCR-`/`VAR-`
  followed by a number, plus `Cannot find`, `is not connected`, `No such command`;
- `-Match <regex>` was not found in stdout;
- `-NoMatch <regex>` did match stdout.

Exit codes: `0` ran · `1` `-Strict` and verdict is `FAIL` · `2` usage error.

> **dbcli's exit code is not a success signal.** A failed `login` or a SQL error still exits 0
> and appears only as text in stdout — that is precisely what this verdict exists to catch, and
> why `-Strict` is the right flag for a harness.

A **warning is not a failure**: a clean run is reported `PASS` with an empty `problems` array.

When a probe is *supposed* to raise something, do not reach for `-NoDefaultPatterns` first —
scope it:

```powershell
# this probe deliberately hits a missing table; only that error is tolerated
pwsh -File .\agent-test.ps1 -Login o19c -Commands "select * from no_such_table;" `
     -IgnorePattern 'ORA-00942' -Json
```

Override the default `login`/`exit` behaviour by putting your own `login ...` or `exit` line in
`-Script`/`-Commands`.

---

Recipes
-------

**Assert a value, not just "it ran"**

```powershell
pwsh -File .\agent-test.ps1 -Login o19c -Commands "select count(*) n from dual;" `
     -Match '1 rows returned' -Json -Strict
```

**Exercise a dbcli script under the real template engine**
Use `-Commands "ora <name> <opts>"`; `-Script` would bypass the engine and not expand
`&var` / `@NAME` / `$IF`.

```powershell
foreach ($opt in '', '-new', '-u', '-i', '-m') {
  $tag = if ($opt) { $opt.TrimStart('-') } else { 'default' }
  pwsh -NoProfile -File .\agent-test.ps1 -Login o19c -Commands "ora actives $opt" `
       -Linesize 300 -Cols 250 -OutDir "D:\tmp\actives-$tag" -Json -Strict
}
```

**Run a SQL fixture file** (plain SQL: statements need `;`, PL/SQL blocks need `/`)

```powershell
pwsh -File .\agent-test.ps1 -Login o19c -Script .\cache\act\probe.sql -Linesize 300
```

**Keep the caller's environment** (e.g. you set `COLUMNS` yourself): add `-NoSize`.

**Fast fail in CI**: `-Json -Strict -Quiet` and read only the exit code.

**Batch many commands into one invocation** — each run costs ~10-15s of startup, so `;;`-joining
is much cheaper than looping the script (remember each statement keeps its own `;`):

```powershell
pwsh -File .\agent-test.ps1 -Login o19c -Json -Strict -Cols 250 -Linesize 300 `
     -Commands "ora actives;;ora actives -new;;ora actives -u;;ora actives -m;"
```

```bash
bash ./agent-test.sh --login o19c --json --strict --cols 250 --linesize 300 \
     --commands "ora actives;;ora actives -new;;ora actives -u;;ora actives -m;"
```

---

Troubleshooting
---------------

| Symptom | Cause / fix |
|---|---|
| `stdout is empty` + `attachError=true` | `lib\dbcli.jar` is older than the Console.java fallback: rebuild it, or add `-ForceMsys` |
| `verdict: FAIL -- stderr said: …` | real stderr output; if it is expected, it is not covered by the noise filter — report it rather than widening the filter blindly |
| `verdict: FAIL -- error markers: ORA-00942` | a probe that raises on purpose: add `-IgnorePattern 'ORA-00942'` |
| `verdict: FAIL -- error markers: ORA-00933` | almost always a missing `;` in `--commands` — `;;` separates, it does not terminate |
| `-Match '…' not found` | the text really is absent; check `out.plain.txt` before blaming the match — escape specials and remember output is ANSI-stripped already |
| width looks wrong / rows folded | raise `-Cols`, and pass `-Linesize` — `-Cols` controls the grid width, `set linesize` controls folding |
| `cannot locate the dbcli install` | pass `-Dir <install>` / `--dir <install>`, or set `DBCLI_HOME` |
| `launcher not runnable` (shell) | `chmod +x dbcli.sh` — the `.sh` launchers need the execute bit on Linux/macOS |
| run takes ~15s even for `select 1` | expected: that is dbcli/JVM startup, not the query |
| `--pty` output starts with the command list | inherent to `script(1)` + readline; match on content instead of the first lines |

---

Gotchas
-------

- **A run costs ~10-15s** of dbcli/JVM startup. Batch many commands into one invocation
  (`-Commands "a;;b;;c"`) instead of looping the script, unless you need per-command isolation.
- **`;;` separates, it does not terminate.** Every statement in `-Commands`/`--commands` keeps
  its own `;`; a missing one yields `ORA-00933` (which the verdict will report).
- **`=` in command-line arguments is rewritten by dbcli itself** (`lua/env.lua:1334` replaces
  the first `=` of each argument with a space). Anything needing a literal `=` — filters,
  comparisons — should go through `-Script`, or use a predicate that avoids `=`.
- **`-Script` does not go through dbcli's script engine.** Template directives
  (`&var` / `@NAME` / `$IF`) are only expanded for scripts launched with `ora <name>`. Use
  `-Script` for SQL text you want sent as-is, and `-Commands "ora …"` to test a real script.
- **Known-noise-only stderr.** The dumb-terminal warning (`org.jline.utils.Log` + "creating a
  dumb terminal") is filtered. Any other stderr line fails the run by design.
- **Environment is restored**, so `COLUMNS`/`LINES`/`MSYSTEM` do not leak into the caller even
  when the run fails (`finally` on PowerShell, subshell-scoped assignment in the shell runner).
- **The shell runner keeps LF line endings.** `.sh` files must not be converted to CRLF:
  `#!/usr/bin/env bash` with a trailing CR breaks the shebang on Linux/macOS.

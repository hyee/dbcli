#!/usr/bin/env bash
# ============================================================================================
# agent-test.sh -- headless dbcli runner for Linux / macOS / WSL (sibling of agent-test.ps1)
# ============================================================================================
#
# WHAT IT DOES
#   Feeds a list of dbcli commands to the launcher over stdin and captures stdout / stderr
#   separately and byte-exactly, with a deterministic terminal width and a machine-readable
#   verdict. The Windows sibling is agent-test.ps1; the two accept the same inputs and produce
#   the same artifacts, verdict and JSON fields.
#
# QUICK START
#   bash ./agent-test.sh --login o19c --commands "select 1 c1 from dual;"
#   bash ./agent-test.sh --login o19c --commands "ora actives -new" --json --strict
#   bash ./agent-test.sh --db mysql --login my57 --commands "select 1 c1;"
#   bash ./agent-test.sh --db pgsql --login pg16 --script ./my.sql --linesize 300
#
#   --commands splits on ';;', which is a SEPARATOR ONLY (';;' does not terminate anything):
#   each SQL statement still needs its own ';'  ->  --commands "select 1 a from dual;;select 2 b from dual;"
#   --script feeds a .sql file line by line. Every statement still needs its own ';' and every
#   PL/SQL block its own '/'. 'login <alias>' and a trailing 'exit' are added unless present.
#
# PIPE VS PTY
#   Default is the pipe path: dbcli falls back to a JLine dumb terminal, which is quiet and
#   deterministic, but a dumb terminal has no width of its own -- that is why COLUMNS/LINES are
#   exported (the current build lets a dumb terminal pick them up).
#   --pty wraps dbcli in script(1) so it gets a REAL pty (no dumb fallback, the app sees a tty).
#   The pty echoes whatever is written to it, so --pty also turns echo off; without that the
#   command list would appear at the top of out.txt. Use --pty when you are testing behaviour
#   that depends on having a real terminal.
#
# WHERE THE OUTPUT GOES  (--out defaults to <install>/agent-out/<yyyyMMdd-HHMMSS>/)
#   in.txt          the exact command list written to stdin (echo of what ran)
#   out.txt         raw stdout
#   out.plain.txt   stdout with ANSI stripped -- use this for matching/diffing (default)
#   err.txt         stderr, verbatim
#
# READING THE RESULT
#   Human mode prints a one-line summary, the artifact paths, a `verdict:` line and the first
#   non-empty output lines. --quiet prints nothing. --json prints ONE JSON object -- the
#   machine-readable contract for a harness:
#     ok, verdict, problems[], db, login, install, outDir, stdout, stderr, exitCode, timeout,
#     elapsedSec, stdoutBytes, ansiEscapes, colwrapNoise, dumbTerminal, attachError,
#     cols, rows, linesize, commands, pty, os
#
# EXIT CODE
#   0 = ran (see `verdict`)   1 = --strict and verdict != PASS   2 = usage error
#
#   !! dbcli's own exit code is NOT a success signal: a failed `login` or a SQL error still
#   !! exits 0 and only shows up as text in stdout. That is why the verdict exists. Use
#   !! --strict when a harness needs a failing process exit code.
#
# VERDICT RULES  (a run FAILs when any of these hold)
#   - stdout is empty, or the run timed out / never finished
#   - stderr carried anything other than the known dumb-terminal chatter
#   - stdout matched an error marker (defaults: ORA-/PLS-/SP2-/DBC-/MIS-/SCR-/VAR- numbers,
#     "Cannot find", "is not connected", "No such command")   -> suppress with
#     --no-default-patterns, or drop individual hits with --ignore-pattern (e.g. a probe that
#     deliberately raises ORA-00942)
#   - --match <regex> was not found in stdout
#   - --no-match <regex> did match stdout
#   A warning is NOT a failure, so a clean run reports an empty problems list.
#
# GOTCHAS WORTH KNOWING
#   * A full run costs ~10-15s of dbcli/JVM startup; the SQL is not the slow part. Batch many
#     commands into one invocation (--commands "a;;b;;c") instead of looping the script.
#   * Commands whose arguments contain '=' lose the first '=' inside dbcli itself
#     (env.lua:1334 rewrites argv), so pass such SQL via --script instead of --commands.
#   * --script does NOT go through dbcli's script engine, so template directives (&var / @NAME /
#     $IF) are not expanded there. To exercise a real script use --commands "ora <name> <opts>".
#   * macOS ships bash 3.2 and BSD `script`; this file stays compatible with both.
#
# Full guide with recipes and troubleshooting: docs/agent-testing.md
# ============================================================================================
set -o pipefail

db=oracle login="" script="" commands="" cols=150 rows=40 linesize=0
pty=0 keep_ansi=0 out="" timeout_sec=240 dir=""
match="" nomatch="" ignore_pattern="" no_default_patterns=0
json=0 quiet=0 strict=0 keep=20

self="${BASH_SOURCE[0]:-$0}"
guess="$(cd "$(dirname "$self")" 2>/dev/null && pwd || true)"

usage() { sed -n '/^# QUICK START/,/^# ====/p' "$self" | sed 's/^# \{0,1\}//' | sed '$d'; }

need_value() { [ -n "$2" ] || { echo "option $1 needs a value" >&2; exit 2; }; }

while [ $# -gt 0 ]; do
  case "$1" in
    --db) need_value "$1" "${2:-}"; db="$2"; shift 2;;
    --login) need_value "$1" "${2:-}"; login="$2"; shift 2;;
    --script) need_value "$1" "${2:-}"; script="$2"; shift 2;;
    --commands) need_value "$1" "${2:-}"; commands="$2"; shift 2;;
    --cols) need_value "$1" "${2:-}"; cols="$2"; shift 2;;
    --rows) need_value "$1" "${2:-}"; rows="$2"; shift 2;;
    --linesize) need_value "$1" "${2:-}"; linesize="$2"; shift 2;;
    --out) need_value "$1" "${2:-}"; out="$2"; shift 2;;
    --timeout) need_value "$1" "${2:-}"; timeout_sec="$2"; shift 2;;
    --dir) need_value "$1" "${2:-}"; dir="$2"; shift 2;;
    --match) need_value "$1" "${2:-}"; match="$2"; shift 2;;
    --no-match) need_value "$1" "${2:-}"; nomatch="$2"; shift 2;;
    --ignore-pattern) need_value "$1" "${2:-}"; ignore_pattern="$2"; shift 2;;
    --keep) need_value "$1" "${2:-}"; keep="$2"; shift 2;;
    --pty) pty=1; shift;;
    --keep-ansi) keep_ansi=1; shift;;
    --json) json=1; shift;;
    --quiet) quiet=1; shift;;
    --strict) strict=1; shift;;
    --no-default-patterns) no_default_patterns=1; shift;;
    --no-size) cols=0; rows=0; shift;;
    -h|--help) usage; exit 0;;
    *) echo "unknown option: $1" >&2; exit 2;;
  esac
done

# the numeric knobs are interpolated into SQL and stty, so validate them
for pair in "cols:$cols" "rows:$rows" "linesize:$linesize" "timeout:$timeout_sec" "keep:$keep"; do
  case "${pair#*:}" in ''|*[!0-9]*) echo "--${pair%%:*} must be a non-negative integer" >&2; exit 2;; esac
done

case "$db" in
  oracle) launcher="dbcli.sh";;
  mysql)  launcher="mysql_dbcli.sh";;
  pgsql)  launcher="pgsql_dbcli.sh";;
  *) echo "--db must be oracle|mysql|pgsql" >&2; exit 2;;
esac

case "$(uname -s)" in
  Darwin) os=mac;;
  Linux) if grep -qi microsoft /proc/version 2>/dev/null; then os=wsl; else os=linux; fi;;
  *) os=unix;;
esac

# install dir: --dir > $DBCLI_HOME > this script's dir > $PWD (never hardcoded)
if [ -z "$dir" ]; then
  for c in "${DBCLI_HOME:-}" "$guess" "$PWD"; do
    if [ -n "$c" ] && [ -f "$c/dbcli.sh" ]; then dir="$c"; break; fi
  done
fi
if [ -z "$dir" ]; then
  echo "cannot locate the dbcli install (no dbcli.sh in: ${DBCLI_HOME:-<DBCLI_HOME unset>}; ${guess:-<script dir unknown>}; $PWD)." >&2
  echo "Pass --dir <path> or set DBCLI_HOME." >&2
  exit 2
fi
cd "$dir" || { echo "cannot cd $dir" >&2; exit 2; }
[ -f "./$launcher" ] || { echo "launcher not found: $dir/$launcher" >&2; exit 2; }
[ -x "./$launcher" ] || { echo "launcher not runnable: $dir/$launcher (chmod +x?)" >&2; exit 2; }
if [ -z "$script" ] && [ -z "$commands" ]; then echo "give --script <file> or --commands 'a;;b'" >&2; exit 2; fi

# ------------------------------------------------------------------ build the stdin command list
lines=()
push_line() { lines[${#lines[@]}]="$1"; }
if [ -n "$script" ]; then
  [ -f "$script" ] || { echo "script not found: $script" >&2; exit 2; }
  while IFS= read -r l || [ -n "$l" ]; do push_line "$l"; done < "$script"
else
  while IFS= read -r l; do push_line "$l"; done <<< "${commands//;;/$'\n'}"
fi
if [ "$linesize" -gt 0 ]; then
  lines=("set linesize $linesize" "${lines[@]}")
fi
if [ -n "$login" ] && ! printf '%s\n' "${lines[@]}" | grep -Eq '^[[:space:]]*(login|logon|conn|connect)([[:space:]]|$)'; then
  lines=("login $login" "${lines[@]}")
fi
if ! printf '%s\n' "${lines[@]}" | grep -Eq '^[[:space:]]*(exit|quit)[[:space:]]*$'; then push_line "exit"; fi

# ------------------------------------------------------------------ artifact directory
generated_out=0
if [ -z "$out" ]; then out="$dir/agent-out/$(date +%Y%m%d-%H%M%S)"; generated_out=1; fi
mkdir -p "$out" || { echo "cannot create --out $out" >&2; exit 2; }
inF="$out/in.txt"; outF="$out/out.txt"; errF="$out/err.txt"; plainF="$out/out.plain.txt"
printf '%s\n' "${lines[@]}" > "$inF"

# ------------------------------------------------------------------ run with a portable watchdog
# `timeout` is GNU coreutils and absent on stock macOS, so fall back to a TERM watchdog.
run_limited() {
  local sec="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$sec" "$@"; return $?; fi
  "$@" & local child=$!
  ( sleep "$sec"; kill -TERM "$child" 2>/dev/null ) & local watcher=$!
  local rc=0
  wait "$child" || rc=$?
  kill -TERM "$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
  return $rc
}

start_secs=$(date +%s)
timed_out=0
if [ "$pty" = 1 ]; then
  # A pty echoes what is written to it; turn echo off so the command list does not land in out.txt
  inner="stty rows $rows cols $cols -echo 2>/dev/null; exec ./$launcher"
  if [ "$os" = mac ] || [ "$os" = unix ]; then
    # BSD script: script [-q] file [command ...]
    run_limited "$timeout_sec" script -q /dev/null /bin/sh -c "$inner" < "$inF" > "$outF" 2> "$errF"
  else
    # util-linux script: script -q -e -c <command> file
    run_limited "$timeout_sec" script -q -e -c "$inner" /dev/null < "$inF" > "$outF" 2> "$errF"
  fi
  code=$?
else
  # exported only for the child; the harness's own environment is untouched
  COLUMNS="$cols" LINES="$rows" run_limited "$timeout_sec" "./$launcher" < "$inF" > "$outF" 2> "$errF"
  code=$?
fi
end_secs=$(date +%s)
elapsed=$((end_secs - start_secs))
# 124 = GNU timeout fired, 143 = our watchdog TERM'd the child
if [ "$code" = 124 ] || [ "$code" = 143 ]; then timed_out=1; fi

# ------------------------------------------------------------------ plain text + measurements
if [ "$keep_ansi" = 1 ]; then plainF="$outF"; else
  ESC=$(printf '\033'); BEL=$(printf '\007')
  sed -E -e "s/${ESC}\][^${BEL}]*${BEL}//g" -e "s/${ESC}\[[0-9;?<=>]*[ -/]*[@-~]//g" \
      -e "s/${ESC}([@-Z]|[\\\\_-])//g" -e 's/\r//g' "$outF" > "$plainF"
fi
bytes=$(wc -c < "$outF" | tr -d ' ')
esc=$(tr -cd '\033' < "$outF" | wc -c | tr -d ' ')
nlines=$(wc -l < "$outF" | tr -d ' ')
errbytes=$(wc -c < "$errF" | tr -d ' ')
dumb=$(grep -c 'creating a dumb terminal' "$errF" 2>/dev/null || true)
colwrap=$(grep -c "Invalid value for 'COLWRAP'" "$outF" 2>/dev/null || true)
attach=$(grep -c 'Failed to get console mode' "$errF" 2>/dev/null || true)

# ------------------------------------------------------------------ verdict
problems=()
add_problem() {
  local p="$1" q
  [ -n "$p" ] || return 0
  for q in ${problems[@]+"${problems[@]}"}; do [ "$q" = "$p" ] && return 0; done
  problems[${#problems[@]}]="$p"
}
[ "$timed_out" = 1 ] && add_problem "timeout after ${timeout_sec}s"
[ "$bytes" -eq 0 ] && add_problem "stdout is empty"

# stderr other than the known dumb-terminal chatter is a real problem
err_signal="$(grep -v -E 'creating a dumb terminal|Failed to get console mode|org\.jline\.utils\.Log' "$errF" 2>/dev/null | grep -v '^[[:space:]]*$' | head -1)"
[ -n "$err_signal" ] && add_problem "stderr said: $err_signal"

if [ "$no_default_patterns" = 0 ] && [ "$bytes" -gt 0 ]; then
  hits="$(grep -oE 'ORA-[0-9]{4,5}|PLS-[0-9]{4,5}|SP2-[0-9]{4}|DBC-[0-9]{4,5}|MIS-[0-9]{4,5}|SCR-[0-9]{4,5}|VAR-[0-9]{4,5}|Cannot find|is not connected|No such command' "$plainF" 2>/dev/null | sort -u)"
  if [ -n "$ignore_pattern" ]; then hits="$(printf '%s\n' "$hits" | grep -v -E "$ignore_pattern" || true)"; fi
  hits="$(printf '%s\n' "$hits" | grep -v '^[[:space:]]*$' | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
  [ -n "$hits" ] && add_problem "error markers: $hits"
fi
if [ -n "$match" ] && ! grep -qE "$match" "$plainF" 2>/dev/null; then
  add_problem "--match '$match' not found"
fi
if [ -n "$nomatch" ]; then
  bad="$(grep -oE "$nomatch" "$plainF" 2>/dev/null | sort -u | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
  [ -n "$bad" ] && add_problem "--no-match '$nomatch' matched: $bad"
fi

if [ "${#problems[@]}" -eq 0 ]; then verdict=PASS; else verdict=FAIL; fi
if [ "$keep_ansi" = 1 ]; then stdout_path="$outF"; else stdout_path="$plainF"; fi

# ------------------------------------------------------------------ JSON helpers (no jq/python)
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}
json_string_array() {
  local first=1 v out=""
  for v in ${problems[@]+"${problems[@]}"}; do
    [ "$first" = 1 ] || out="$out,"
    first=0
    out="$out\"$(json_escape "$v")\""
  done
  printf '[%s]' "$out"
}

# ------------------------------------------------------------------ report
if [ "$json" = 1 ]; then
  ok=false; [ "$verdict" = PASS ] && ok=true
  printf '{"ok":%s,"verdict":"%s","problems":%s,"db":"%s","login":"%s","install":"%s","outDir":"%s",' \
    "$ok" "$verdict" "$(json_string_array)" "$(json_escape "$db")" "$(json_escape "$login")" \
    "$(json_escape "$dir")" "$(json_escape "$out")"
  printf '"stdout":"%s","stderr":"%s","exitCode":%s,"timeout":%s,"elapsedSec":%s,' \
    "$(json_escape "$stdout_path")" "$(json_escape "$errF")" "$code" \
    "$([ "$timed_out" = 1 ] && echo true || echo false)" "$elapsed"
  printf '"stdoutBytes":%s,"ansiEscapes":%s,"colwrapNoise":%s,"dumbTerminal":%s,"attachError":%s,' \
    "$bytes" "$esc" "$([ "$colwrap" = 0 ] && echo false || echo true)" \
    "$([ "$dumb" = 0 ] && echo false || echo true)" "$([ "$attach" = 0 ] && echo false || echo true)"
  printf '"cols":%s,"rows":%s,"linesize":%s,"commands":%s,"pty":%s,"os":"%s"}\n' \
    "$cols" "$rows" "$linesize" "${#lines[@]}" "$([ "$pty" = 1 ] && echo true || echo false)" "$os"
elif [ "$quiet" = 0 ]; then
  echo "db=$db login=$login pty=$pty os=$os install=$dir exit=$code out=${bytes}B esc=$esc lines=$nlines cols=$cols rows=$rows linesize=$linesize colwrapNoise=$colwrap"
  echo "stdout : $stdout_path"
  echo "stderr : $errF (dumbWarn=$dumb, attachError=$attach, ${errbytes}B)"
  if [ "${#problems[@]}" -eq 0 ]; then
    echo "verdict: PASS"
  else
    echo "verdict: FAIL -- $(printf '%s; ' ${problems[@]+"${problems[@]}"} | sed 's/; $//')"
  fi
  if [ "$timed_out" = 1 ]; then echo "!! TIMEOUT after ${timeout_sec}s"; fi
  if [ "$bytes" -eq 0 ]; then
    echo "!! stdout is empty"
    if [ "$attach" != 0 ]; then echo "!! dbcli could not attach a console (rebuild lib/dbcli.jar)"; fi
    grep -v '^[[:space:]]*$' "$errF" 2>/dev/null | head -3 | sed 's/^/!! stderr: /'
  else
    echo "--- first non-empty lines ---"
    grep -v '^[[:space:]]*$' "$plainF" | head -6 | sed 's/^/  /'
  fi
fi

# ------------------------------------------------------------------ prune old artifact dirs
# --keep 0 disables pruning entirely; otherwise keep the newest N timestamped runs
if [ "$generated_out" = 1 ] && [ "$keep" -gt 0 ]; then
  root="$(dirname "$out")"
  ls -1d "$root"/*/ 2>/dev/null | sed 's:/$::' | grep -E '/[0-9]{8}-[0-9]{6}$' \
    | sort -r | tail -n +"$((keep + 1))" | while IFS= read -r d; do
      [ "$d" = "$out" ] || rm -rf -- "$d"
    done
fi

if [ "$strict" = 1 ] && [ "$verdict" != PASS ]; then exit 1; fi
exit 0

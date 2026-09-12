# ============================================================================================
# agent-test.ps1 -- headless dbcli runner for agents / harnesses / CI
# ============================================================================================
#
# WHAT IT DOES
#   Feeds a list of dbcli commands to the launcher over stdin and captures stdout / stderr
#   separately and byte-exactly. No console is needed: the launcher falls back to a JLine dumb
#   terminal, and the terminal size is forced from the environment so width-dependent layout
#   (grid folding, COLWRAP) is deterministic.
#
# QUICK START
#   pwsh -File .\agent-test.ps1 -Login o19c -Commands "select 1 c1 from dual;"
#   pwsh -File .\agent-test.ps1 -Login o19c -Commands "ora actives -new" -Json -Strict
#   pwsh -File .\agent-test.ps1 -Db mysql -Login my57 -Commands "select 1 c1;"
#   pwsh -File .\agent-test.ps1 -Db pgsql -Login pg16 -Script .\my.sql -Linesize 300
#   .\agent-test.cmd -Login o19c -Commands "select 1 c1 from dual;"      &rem cmd shim, same args
#
#   -Commands splits on ';;', which is a SEPARATOR ONLY (';;' does not terminate anything):
#   each SQL statement still needs its own ';'  ->  -Commands "select 1 a from dual;;select 2 b from dual;"
#   -Script feeds a .sql file line by line. Every statement still needs its own ';' and every
#   PL/SQL block its own '/'; the comments are sent too, so keep script files plain.
#   'login <alias>' and a trailing 'exit' are added automatically unless already present.
#
# WHERE THE OUTPUT GOES  (<OutDir> defaults to <install>\agent-out\<yyyyMMdd-HHmmss>\)
#   in.txt          the exact command list written to stdin (echo of what ran)
#   out.txt         raw stdout, ANSI escapes intact
#   out.plain.txt   stdout with ANSI stripped -- use this for matching/diffing (default)
#   err.txt         stderr, verbatim
#   `-KeepAnsi` keeps only the raw form and points `stdout` at out.txt.
#
# READING THE RESULT
#   Human mode (default) prints a one-line summary, the artifact paths, a `verdict:` line and the
#   first non-empty output lines. `-Quiet` prints nothing. `-Json` prints ONE compressed JSON
#   object -- the machine-readable contract for a harness:
#     ok, verdict ("PASS"/"FAIL"), problems[], db, login, install, outDir, stdout, stderr,
#     exitCode, timeout, elapsedSec, stdoutBytes, ansiEscapes, colwrapNoise, dumbTerminal,
#     attachError, cols, rows, linesize, commands
#
# EXIT CODE
#   0 = ran (see `verdict` for success)   1 = -Strict and verdict != PASS   2 = usage error
#
#   !! dbcli's own exit code is NOT a success signal: a failed `login` or a SQL error still
#   !! exits 0 and only shows up as text in stdout. That is why the verdict exists. Use
#   !! `-Strict` when a harness needs a failing process exit code.
#
# VERDICT RULES  (a run FAILs when any of these hold)
#   - stdout is empty, or the process timed out / never exited
#   - the output pipes did not drain in time (tail may be missing)
#   - stderr carried anything other than the known dumb-terminal chatter
#   - stdout matched an error marker (defaults: ORA-/PLS-/SP2-/DBC-/MIS-/SCR-/VAR- numbers,
#     "Cannot find", "is not connected", "No such command")   -> suppress with -NoDefaultPatterns,
#     or drop individual hits with -IgnorePattern (e.g. a probe that deliberately raises ORA-00942)
#   - -Match <regex> was not found in stdout
#   - -NoMatch <regex> did match stdout
#   A warning is NOT a failure, so a clean run is not reported as a problem.
#
# USEFUL FLAGS
#   -Cols/-Rows      terminal size for a dumb terminal (default 150x40). Raise -Cols for wide
#                    result sets instead of relying on `set linesize`.
#   -Linesize N      prepends `set linesize N`; needed to stop wide rows being folded/trimmed.
#   -NoSize          do not set COLUMNS/LINES (keeps the caller's environment).
#   -TimeoutSec N    wall-clock cap (default 240); on timeout exitCode is -1 and verdict FAILs.
#   -KeepAnsi        keep escapes in the file the summary points at.
#   -ForceMsys       legacy: sets MSYSTEM for the pre-2026-09-13 jar whose WinSysTerminal aborted
#                    instead of falling back. Harmless but unnecessary on the current build.
#   -Keep N          keep N timestamped runs under agent-out (default 20; 0 disables pruning).
#                    Only applies when -OutDir was not given.
#   -Dir / $env:DBCLI_HOME   where the dbcli install lives; otherwise the script dir, then cwd.
#
# GOTCHAS WORTH KNOWING
#   * A full run costs ~14s of dbcli/JVM startup; the SQL itself is not the slow part.
#   * Commands whose arguments contain '=' lose the first '=' inside dbcli itself
#     (env.lua:1334 rewrites argv), so pass such SQL via -Script instead of -Commands.
#   * -Script does NOT go through dbcli's script engine, so template directives (&var / @NAME /
#     $IF) are not expanded there. To exercise a real script use -Commands "ora <name> <opts>".
#
# Full guide with recipes and troubleshooting: docs\agent-testing.md
# ============================================================================================
param(
  [ValidateSet('oracle', 'mysql', 'pgsql')][string]$Db = 'oracle',
  [string]$Dir,
  [string]$Login,
  [string]$Script,
  [string]$Commands,
  [int]$Cols = 150,
  [int]$Rows = 40,
  [int]$Linesize = 0,
  [string]$OutDir,
  [int]$TimeoutSec = 240,
  [switch]$KeepAnsi,
  [switch]$NoSize,
  [switch]$ForceMsys,
  # --- verdict controls (all optional; the defaults reproduce the historical behaviour) ---
  [string]$Match,
  [string]$NoMatch,
  [switch]$NoDefaultPatterns,
  [string]$IgnorePattern,
  [switch]$Json,
  [switch]$Quiet,
  [switch]$Strict,
  [int]$Keep = 20
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding $false

# stderr text dbcli emits on a working dumb terminal; never treated as a failure. The JLine message is
# two lines (a java.util.logging header, then the warning), so both are excluded.
$noisePattern = 'creating a dumb terminal|Failed to get console mode|org\.jline\.utils\.Log'
# errors that must fail a run even though dbcli exited 0
$errorPattern = 'ORA-\d{4,5}|PLS-\d{4,5}|SP2-\d{4}|DBC-\d{4,5}|MIS-\d{4,5}|SCR-\d{4,5}|VAR-\d{4,5}|Cannot find|is not connected|No such command'

function Write-Utf8([string]$Path, [string]$Text) { [IO.File]::WriteAllText($Path, $Text, $utf8) }
function Strip-Ansi([string]$Text) {
  $t = [regex]::Replace($Text, "\e\][^\a\e]*(\a|\e\\)", '')
  $t = [regex]::Replace($t, "\e\[[0-9;?<=>]*[ -/]*[@-~]", '')
  [regex]::Replace($t, "\e[@-Z\\-_]", '')
}
function Exit-With([int]$Code, [string]$Message) {
  if ($Message) { if ($Json) { Write-Output (@{ ok = $false; error = $Message } | ConvertTo-Json -Compress) } else { Write-Host "!! $Message" } }
  exit $Code
}

# ---------------------------------------------------------------- locate install + launcher
$launchers = @{ oracle = 'dbcli.bat'; mysql = 'mysql_dbcli.bat'; pgsql = 'pgsql_dbcli.bat' }
$candidates = @()
if ($Dir) { $candidates += $Dir }
if ($env:DBCLI_HOME) { $candidates += $env:DBCLI_HOME }
$candidates += $PSScriptRoot
$candidates += (Get-Location).Path
$install = $null
foreach ($c in $candidates) {
  if ($c -and (Test-Path (Join-Path $c 'dbcli.bat'))) { $install = (Resolve-Path $c).Path; break }
}
if (-not $install) { Exit-With 2 "cannot locate the dbcli install (no dbcli.bat in: $($candidates -join '; ')). Pass -Dir <path> or set DBCLI_HOME." }
$launcher = Join-Path $install $launchers[$Db]
if (-not (Test-Path $launcher)) { Exit-With 2 "launcher not found: $launcher" }
if (-not $Script -and -not $Commands) { Exit-With 2 "give -Script <file> or -Commands 'a;;b'" }

# ---------------------------------------------------------------- build the stdin command list
$lines = @()
if ($Script) {
  if (-not (Test-Path $Script)) { Exit-With 2 "script not found: $Script" }
  $lines += [IO.File]::ReadAllLines($Script)
} else {
  $lines += ($Commands -split ';;')
}
if ($Linesize -gt 0) { $lines = @("set linesize $Linesize") + $lines }
if ($Login -and -not ($lines | Where-Object { $_.Trim() -match '^(login|logon|conn|connect)\b' })) {
  $lines = @("login $Login") + $lines
}
$alreadyExits = ($lines | Where-Object { $_.Trim() -match '^(exit|quit)$' }).Count -gt 0
if (-not $alreadyExits) { $lines += 'exit' }
$stdin = ($lines -join "`r`n") + "`r`n"

# ---------------------------------------------------------------- artifact directory
if (-not $OutDir) { $OutDir = Join-Path (Join-Path $install 'agent-out') (Get-Date -Format 'yyyyMMdd-HHmmss') }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$OutDir = (Resolve-Path $OutDir).Path
$inF = Join-Path $OutDir 'in.txt'
$outF = Join-Path $OutDir 'out.txt'
$errF = Join-Path $OutDir 'err.txt'
Write-Utf8 $inF $stdin

# ---------------------------------------------------------------- run, always restoring the environment
$saved = @{}
foreach ($k in @('COLUMNS', 'LINES', 'MSYSTEM')) { $saved[$k] = [Environment]::GetEnvironmentVariable($k) }
$outBytes = 0; $errText = ''; $code = -1; $finished = $false; $timedOut = $false; $drained = $true
$oStream = $null; $eStream = $null
$sw = [Diagnostics.Stopwatch]::StartNew()
try {
  if (-not $NoSize) { $env:COLUMNS = "$Cols"; $env:LINES = "$Rows" }
  if ($ForceMsys) { $env:MSYSTEM = 'MINGW64' }

  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = 'cmd.exe'
  $psi.Arguments = '/c "' + $launcher + '"'
  $psi.WorkingDirectory = $install
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true

  $p = [Diagnostics.Process]::Start($psi)
  # drain both pipes before feeding stdin, so a child that writes early can never fill a pipe and block
  $oStream = [IO.File]::Create($outF)
  $eStream = [IO.File]::Create($errF)
  $tOut = $p.StandardOutput.BaseStream.CopyToAsync($oStream)
  $tErr = $p.StandardError.BaseStream.CopyToAsync($eStream)
  $inBytes = $utf8.GetBytes($stdin)
  try {
    $p.StandardInput.BaseStream.Write($inBytes, 0, $inBytes.Length)
    $p.StandardInput.BaseStream.Flush()
  } catch { }   # dbcli may exit on its own before consuming every line; not an error by itself
  try { $p.StandardInput.Close() } catch { }
  $finished = $p.WaitForExit($TimeoutSec * 1000)
  if (-not $finished) {
    $timedOut = $true
    try { $p.Kill() } catch { }
    $p.WaitForExit(10000) | Out-Null
  }
  # the pipes are closed by now; give the async copies a bounded drain and report if they ran out of time
  $drained = $tOut.Wait(10000) -and $tErr.Wait(10000)
  $oStream.Close(); $eStream.Close()
  $oStream = $null; $eStream = $null
  $code = if ($timedOut) { -1 } else { $p.ExitCode }
} finally {
  # never leave the artifact handles open, even if the run above threw
  foreach ($s in @($oStream, $eStream)) { if ($s) { try { $s.Close() } catch { } } }
  foreach ($k in @('COLUMNS', 'LINES', 'MSYSTEM')) {
    if ($null -eq $saved[$k]) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue } else { Set-Item "Env:$k" $saved[$k] }
  }
  $sw.Stop()
}

# ---------------------------------------------------------------- read back + derive verdict
$outBytes = [IO.File]::ReadAllBytes($outF)
$errText = [IO.File]::ReadAllText($errF, $utf8)
$outText = [Text.Encoding]::UTF8.GetString($outBytes)
$esc = ([regex]::Matches($outText, "\e")).Count
$plainF = Join-Path $OutDir 'out.plain.txt'
$plain = $outText
if (-not $KeepAnsi) {
  $plain = Strip-Ansi $outText
  Write-Utf8 $plainF $plain
}

$dumbWarn = $errText -match 'creating a dumb terminal'
$noConsole = $errText -match 'Failed to get console mode'
$colwrap = $outText -match "Invalid value for 'COLWRAP'"

# stderr that is not the known dumb-terminal chatter is a real problem
$errSignal = (Strip-Ansi $errText) -split "`r?`n" |
  Where-Object { $_.Trim() -and $_ -notmatch $noisePattern }
$errSignal = @($errSignal)

$problems = @()
if ($timedOut) { $problems += "timeout after ${TimeoutSec}s" }
if (-not $finished -and -not $timedOut) { $problems += 'process did not exit' }
if ($outBytes.Length -eq 0) { $problems += 'stdout is empty' }
if (-not $drained) { $problems += 'output pipes did not drain in time (tail may be missing)' }
if ($errSignal.Count -gt 0) { $problems += "stderr said: $($errSignal[0])" }

if (-not $NoDefaultPatterns -and $outBytes.Length -gt 0) {
  $hits = [regex]::Matches($plain, $errorPattern) | ForEach-Object { $_.Value } | Select-Object -Unique
  if ($IgnorePattern) { $hits = @($hits | Where-Object { $_ -notmatch $IgnorePattern }) }
  if ($hits.Count -gt 0) { $problems += "error markers: $($hits -join ', ')" }
}
if ($Match -and -not [regex]::IsMatch($plain, $Match)) { $problems += "-Match '$Match' not found" }
if ($NoMatch) {
  $bad = [regex]::Matches($plain, $NoMatch) | ForEach-Object { $_.Value } | Select-Object -Unique
  if ($bad.Count -gt 0) { $problems += "-NoMatch '$NoMatch' matched: $($bad -join ', ')" }
}
$problems = @($problems | Select-Object -Unique)   # NOT Select-Object -Unique alone: it unrolls a single item

$verdict = if ($problems.Count -eq 0) { 'PASS' } else { 'FAIL' }
$stdoutPath = if ($KeepAnsi) { $outF } else { $plainF }

# ---------------------------------------------------------------- report
if ($Json) {
  $result = [ordered]@{
    ok          = ($verdict -eq 'PASS')
    verdict     = $verdict
    problems    = $problems
    db          = $Db
    login       = $Login
    install     = $install
    outDir      = $OutDir
    stdout      = $stdoutPath
    stderr      = $errF
    exitCode    = $code
    timeout     = $timedOut
    elapsedSec  = [math]::Round($sw.Elapsed.TotalSeconds, 2)
    stdoutBytes = $outBytes.Length
    ansiEscapes = $esc
    colwrapNoise = $colwrap
    dumbTerminal = $dumbWarn
    attachError  = $noConsole
    cols        = $Cols
    rows        = $Rows
    linesize    = $Linesize
    commands    = $lines.Count
  }
  Write-Output ($result | ConvertTo-Json -Compress)
} elseif (-not $Quiet) {
  Write-Host "db=$Db login=$Login install=$install exit=$code timeout=$timedOut out=$($outBytes.Length)B esc=$esc cols=$Cols rows=$Rows linesize=$Linesize colwrapNoise=$colwrap"
  Write-Host "stdout : $stdoutPath"
  Write-Host "stderr : $errF (dumbWarn=$dumbWarn, attachError=$noConsole, $($errText.Length)B)"
  Write-Host "verdict: $verdict$(if ($problems.Count) { ' -- ' + ($problems -join '; ') })"
  if ($outBytes.Length -eq 0) {
    Write-Host "!! stdout is empty"
    if ($noConsole) { Write-Host "!! dbcli could not attach a console -> rebuild lib\dbcli.jar from the Console.java change, or re-run with -ForceMsys" }
    $firstErr = ($errText -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 3) -join ' / '
    if ($firstErr) { Write-Host "!! stderr: $firstErr" }
  } else {
    $head = ($outText -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 6) -join "`n  "
    Write-Host "--- first non-empty lines ---`n  $head"
  }
}

# ---------------------------------------------------------------- prune old artifact dirs (no -OutDir only)
# -Keep 0 disables pruning entirely; otherwise keep the newest N timestamped runs
if (-not $PSBoundParameters.ContainsKey('OutDir') -and $Keep -gt 0) {
  $root = Split-Path $OutDir -Parent
  $old = Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\d{8}-\d{6}$' -and $_.FullName -ne $OutDir } |
    Sort-Object Name -Descending | Select-Object -Skip $Keep
  foreach ($d in $old) { Remove-Item $d.FullName -Recurse -Force -ErrorAction SilentlyContinue }
}

if ($Strict -and $verdict -ne 'PASS') { exit 1 }
exit 0

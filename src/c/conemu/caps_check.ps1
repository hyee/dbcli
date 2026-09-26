# caps_check.ps1 -- build and run CapsDump.java, the byte-level gate over the terminfo entry.
#
# CapsDump reads a .caps file through the parser jline uses at runtime (InfoCmp.parseInfoCmp) and asserts what
# the terminal will actually see, then again through Curses.tputs, because the two layers disagree by design:
# the parser keeps the file's spelling verbatim and skips line 0, and it is doTputs that turns "\E" and "^I"
# into bytes. 81 assertions, and `CAPS CHECK: ok` is the verdict.
#
# It runs TWICE by default -- against this tree's mirror and against the copy packed inside the jline jar --
# and the two files are compared byte for byte first. That second run is the whole point of the script: the
# entry the user's session reads is the one in the jar, and "the entry that ships is the entry that was
# audited" is only true if someone checks.
#
#   pwsh -NoProfile -File src/c/conemu/caps_check.ps1
#   pwsh -NoProfile -File src/c/conemu/caps_check.ps1 -SkipJar         # mirror only
#   pwsh -NoProfile -File src/c/conemu/caps_check.ps1 -Jar D:\other\JLine3.jar
#
# Nothing here is a fixed path: -Caps/-Jar/-Jdk, then DBCLI_CAPS/DBCLI_JLINE_JAR/JAVA_HOME, then the tree this
# script sits in, then the candidates named in the refusal. build.sh and run.ps1 follow the same rule.

param(
    [string]$Caps = '',
    [string]$Jar = '',
    [string]$Jdk = '',
    [string]$Scratch = '',
    [switch]$SkipJar
)

$ErrorActionPreference = 'Stop'
$src  = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $src))
$rc   = 0

if (-not $Caps)    { $Caps = $env:DBCLI_CAPS }
if (-not $Caps)    { $Caps = Join-Path $src 'terminfo\windows-conemu.caps' }
if (-not $Jar)     { $Jar = $env:DBCLI_JLINE_JAR }
if (-not $Jar)     { $Jar = Join-Path $root 'lib\JLine3.jar' }
if (-not $Scratch) { $Scratch = Join-Path $root 'cache\caps-check' }

if (-not (Test-Path $Caps)) {
    Write-Host "no caps file at $Caps (candidates: -Caps, DBCLI_CAPS, $(Join-Path $src 'terminfo\windows-conemu.caps'))"
    exit 1
}
if (-not $SkipJar -and -not (Test-Path $Jar)) {
    Write-Host "no jline jar at $Jar (candidates: -Jar, DBCLI_JLINE_JAR, $(Join-Path $root 'lib\JLine3.jar')); pass -SkipJar to audit the tree's copy alone"
    exit 1
}

# The JDK. This install runs on D:\jdkx86 (the JVM is created in-process by bootstrap.lua), but a jar and a
# class file built by *some* javac is all this needs, so PATH is a legitimate last resort.
$javac = $java = $null
foreach ($cand in @($Jdk, $env:JAVA_HOME, 'D:\jdkx86', 'D:\jdkx64')) {
    if ($cand -and (Test-Path (Join-Path $cand 'bin\javac.exe'))) {
        $javac = Join-Path $cand 'bin\javac.exe'; $java = Join-Path $cand 'bin\java.exe'; break
    }
}
if (-not $javac) {
    $onPath = Get-Command javac.exe -ErrorAction SilentlyContinue
    if ($onPath) { $javac = $onPath.Source; $java = (Get-Command java.exe).Source }
    else { Write-Host 'no javac: pass -Jdk <dir with bin\javac.exe>, set JAVA_HOME, or put it on PATH'; exit 1 }
}
Write-Host "caps file: $Caps"
Write-Host "javac:     $javac"

New-Item -ItemType Directory -Force -Path $Scratch | Out-Null
$out = Join-Path $Scratch 'out'
New-Item -ItemType Directory -Force -Path $out | Out-Null
# JDK 8's javac will not create its -d target, and a stale class file would silently be the thing tested.
Remove-Item -Recurse -Force -ErrorAction SilentlyContinue (Join-Path $out 'CapsDump.class')

& $javac -g -nowarn -encoding UTF-8 -cp $Jar -d $out (Join-Path $src 'CapsDump.java') 2>&1 |
    ForEach-Object { Write-Host "$_" }
if ($LASTEXITCODE -ne 0) { Write-Host 'CAPSDUMP: does not compile'; exit 1 }

function Invoke-Caps([string]$label, [string]$file) {
    Write-Host "--- $label"
    $lines = & $java -cp "$Jar;$out" CapsDump $file 2>&1
    $code = $LASTEXITCODE
    # Write-Host, not the pipeline: whatever a helper writes to the output stream becomes part of its
    # return value, and a gate whose verdict is "an array of 173 lines plus an exit code" reads as a failure.
    $lines | ForEach-Object { Write-Host "$_" }
    # The program prints its own verdict line and exits 0 either way, so the string is the witness -- a
    # non-zero exit is checked as well, because a JVM that never reached main would print neither. Select-String
    # rather than `-notmatch`: on an array, both -match and -notmatch *filter* and return the array, and a
    # non-empty array is true -- so `if ($lines -notmatch 'ok')` fires on a run that said ok.
    if (-not ($lines | Select-String -SimpleMatch 'CAPS CHECK: ok')) { $code = 1 }
    return $code
}

# Run 1: the tree's mirror.
$rc1 = Invoke-Caps 'the tree' $Caps
if ($rc1 -ne 0) { Write-Host 'CAPS CHECK (tree mirror): FAILED'; $rc = 1 }

if (-not $SkipJar) {
    # Run 2: the copy that ships, extracted from the jar rather than trusted from memory. The comparison is
    # byte-level on purpose: CapsDump can read a file, but only a diff says the audited text is the shipped one.
    $tmp = Join-Path $Scratch 'jar-caps.caps'
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($Jar)
    try {
        $entry = $zip.Entries | Where-Object { $_.FullName -like '*windows-conemu.caps' } | Select-Object -First 1
        if (-not $entry) { Write-Host "no windows-conemu.caps inside $Jar"; $rc = 1 }
        else {
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $tmp, $true)
            $a = [System.IO.File]::ReadAllBytes($Caps); $b = [System.IO.File]::ReadAllBytes($tmp)
            $ha = (Get-FileHash -Algorithm MD5 -Path $Caps).Hash
            $hb = (Get-FileHash -Algorithm MD5 -Path $tmp).Hash
            Write-Host "--- the jar's copy: $($b.Length) bytes md5=$hb ($($entry.FullName))"
            Write-Host "    the tree's copy: $($a.Length) bytes md5=$ha"
            if ($ha -ne $hb) {
                Write-Host 'DRIFT: the shipped entry and the audited entry are different files -- the jar was not'
                Write-Host '       rebuilt from this tree (or this tree was edited and the jar was not). That is'
                Write-Host '       the condition this second run exists to catch.'
                $rc = 1
            }
            $rc2 = Invoke-Caps 'the jar' $tmp
            if ($rc2 -ne 0) { Write-Host 'CAPS CHECK (jar copy): FAILED'; $rc = 1 }
        }
    } finally { $zip.Dispose() }
}

if ($rc -eq 0) { Write-Host 'CAPS CHECK: ok' } else { Write-Host 'CAPS CHECK: FAILED' }
exit $rc

# Runs the stage-0 gate against the DLLs src/c/conemu/build.sh cross-built into cache\native-probe.
#
# D:\jdkx86 is the default runtime for this install (the JVM is created in-process by bootstrap.lua), and
# both bitnesses have to pass because lib\x86 and lib\x64 ship separate natives.
#
# Render.java drives com.hyee.ansirender.NativeRenderer -- the library's production class, which lives in the
# java source tree it ships from (D:\JavaProjects\jline3.29\dbcli\src) -- so javac needs that root on its
# sourcepath. The gate would otherwise be testing its own copy of the declarations, which is how an ABI can
# go unbuilt and a gate stay green.
param(
    [ValidateSet('x86', 'x64', 'both')] [string]$Arch = 'both',
    [string]$Scratch = 'D:\dbcli\cache\native-probe',
    [string]$JavaSrc = '',
    # the install tree, for the optional ConEmuHk reference leg the both-leg A/B compares against. Never a hardcoded default:
    # param > env > the tree this script sits in, and the candidates are named when none of them work.
    [string]$Install = ''
)

$src  = Split-Path -Parent $MyInvocation.MyCommand.Path
$jdk  = @{ x86 = 'D:\jdkx86'; x64 = 'D:\jdkx64' }
$rc   = 0

if (-not $Install) { $Install = $env:DBCLI_HOME }
if (-not $Install) { $Install = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $src))) }

if (-not $JavaSrc) {
    # never a hardcoded install directory: derive it from this script, and say so when it is not there
    $cand = @($env:DBCLI_JAVA_SRC, 'D:\JavaProjects\jline3.29\dbcli\src', (Join-Path $Install 'src\java'))
    foreach ($c in $cand) {
        if ($c -and (Test-Path (Join-Path $c 'com\hyee\ansirender\NativeRenderer.java'))) { $JavaSrc = $c; break }
    }
    if (-not $JavaSrc) {
        Write-Host "no com\hyee\ansirender\NativeRenderer.java on the sourcepath; tried: $(@($cand) -join ', ')"
        exit 1
    }
}
Write-Host "java source tree: $JavaSrc"

foreach ($a in @($Arch -eq 'both' ? @('x86', 'x64') : @($Arch))) {
    Write-Host "=== $a ($($jdk[$a])) ==="
    # The retired fallback leg, kept only as the A/B's reference oracle: the gate names the same file the
    # writer used to load, 'ConEmuHk' on x86 and 'ConEmuHk64' on x64.
    $hk = Join-Path $Install ('lib\{0}\ConEmuHk{1}.dll' -f $a, ($a -eq 'x86' ? '' : '64'))
    if (-not (Test-Path $hk)) {
        Write-Host "  both-leg A/B skipped: no $hk (candidates: -Install, DBCLI_HOME, $(Split-Path -Parent (Split-Path -Parent $src)))"
        $hk = ''
    }
    if (-not (Test-Path "$Scratch\$a\probe.dll")) { Write-Host "no $Scratch\$a\probe.dll - run build.sh first"; $rc = 1; continue }
    # JDK 8's javac will not create its -d target directory
    New-Item -ItemType Directory -Force -Path "$Scratch\out\$a" | Out-Null
    & "$($jdk[$a])\bin\javac.exe" -nowarn -encoding UTF-8 -d "$Scratch\out\$a" "$src\Probe.java"
    if ($LASTEXITCODE -ne 0) { Write-Host "javac failed for $a"; $rc = 1; continue }
    & "$($jdk[$a])\bin\java.exe" "-Djava.library.path=$Scratch\$a" -cp "$Scratch\out\$a" Probe
    if ($LASTEXITCODE -ne 0) { Write-Host "probe failed for $a (exit $LASTEXITCODE)"; $rc = 1 }

    # The renderer gate: paints through render.dll and reads the cells back out of conhost.
    if (-not (Test-Path "$Scratch\$a\render.dll")) { Write-Host "no $Scratch\$a\render.dll - run build.sh first"; $rc = 1; continue }
    & "$($jdk[$a])\bin\javac.exe" -nowarn -encoding UTF-8 -implicit:class -sourcepath "$JavaSrc" `
        -d "$Scratch\out\$a" "$src\Render.java"
    if ($LASTEXITCODE -ne 0) { Write-Host "javac Render.java failed for $a"; $rc = 1; continue }
    & "$($jdk[$a])\bin\java.exe" "-Djava.library.path=$Scratch\$a" "-Dhk=$hk" -cp "$Scratch\out\$a" Render
    if ($LASTEXITCODE -ne 0) { Write-Host "render gate failed for $a (exit $LASTEXITCODE)"; $rc = 1 }
}

Write-Host "STAGE0 RUN: $(if ($rc -eq 0) { 'ok' } else { 'failed' })"
exit $rc

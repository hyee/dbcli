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
    [string]$Install = '',
    # The jar the *application* loads NativeRenderer from. This gate compiles the class out of the source tree and
    # runs its own build, so without this path there is no comparison between what the gate tested and what ships.
    [string]$DbcliJar = '',
    [switch]$SkipJarCheck
)

$src  = Split-Path -Parent $MyInvocation.MyCommand.Path
$jdk  = @{ x86 = 'D:\jdkx86'; x64 = 'D:\jdkx64' }
$rc   = 0

if (-not $Install) { $Install = $env:DBCLI_HOME }
if (-not $Install) { $Install = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $src))) }

# The tree this script sits in, independent of -Install (which names the ConEmuHk reference tree and is often a
# different directory). The shipped jar belongs to the tree under test, not to the reference leg.
$treeRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $src))
if (-not $DbcliJar) { $DbcliJar = $env:DBCLI_DBCLI_JAR }
if (-not $DbcliJar) { $DbcliJar = Join-Path $treeRoot 'lib\dbcli.jar' }

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

    # The seam this gate cannot see by construction: it compiles NativeRenderer.java out of $JavaSrc and runs
    # THAT class, while a real session loads the one packed in lib\dbcli.jar. #89 is why this leg exists -- the
    # source grew a stats() slot, the shipped jar did not, and every gate passed because nobody had compared
    # the two. Byte level on purpose: "the shipped class is the class that was audited" is the only claim worth
    # making here, and a hash says it. Absent input is a FAILURE, not a note (the same rule terminfo_check.sh's
    # third arm learned the hard way); -SkipJarCheck is how a tree with no jar opts out explicitly.
    if ($SkipJarCheck) { Write-Host '  JAR CHECK: skipped by -SkipJarCheck' }
    else {
        $classOut = Join-Path $Scratch ('out\{0}\com\hyee\ansirender\NativeRenderer.class' -f $a)
        if (-not (Test-Path $DbcliJar)) {
            Write-Host "  JAR CHECK: no $DbcliJar (candidates: -DbcliJar, DBCLI_DBCLI_JAR, $(Join-Path $treeRoot 'lib\dbcli.jar')); pass -SkipJarCheck on a tree without one"
            $rc = 1
        } elseif (-not (Test-Path $classOut)) {
            Write-Host "  JAR CHECK: the gate left no $classOut, so there is nothing to compare"
            $rc = 1
        } else {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip = [System.IO.Compression.ZipFile]::OpenRead($DbcliJar)
            try {
                $entry = $zip.Entries | Where-Object { $_.FullName -like '*NativeRenderer.class' } | Select-Object -First 1
                if (-not $entry) { Write-Host "  JAR CHECK: no NativeRenderer.class inside $DbcliJar"; $rc = 1 }
                else {
                    $tmp = Join-Path $Scratch ('jar-NativeRenderer-{0}.class' -f $a)
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $tmp, $true)
                    $ha = (Get-FileHash -Algorithm MD5 -Path $classOut).Hash
                    $hb = (Get-FileHash -Algorithm MD5 -Path $tmp).Hash
                    if ($ha -ne $hb) {
                        Write-Host "  JAR CHECK: DRIFT -- the class the gate ran is $ha, the class $DbcliJar ships is $hb."
                        Write-Host '           The library report line is what changed: redeploy the jar, then re-run.'
                        $rc = 1
                    } else { Write-Host "  ok   the shipped class is the class the gate ran ($ha)" }
                }
            } finally { $zip.Dispose() }
        }
    }
}

Write-Host "STAGE0 RUN: $(if ($rc -eq 0) { 'ok' } else { 'failed' })"
exit $rc

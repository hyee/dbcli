param(
    [ValidateSet('x86', 'x64', 'both')] [string]$Arch = 'both',
    [string]$Scratch = 'D:\dbcli\cache\native-probe',
    [string]$JavaSrc = '',
    [string]$Install = '',
    [string]$DbcliJar = '',
    [switch]$SkipJarCheck,
    [switch]$SkipWidthCheck
)

$src  = Split-Path -Parent $MyInvocation.MyCommand.Path
$jdk  = @{ x86 = 'D:\jdkx86'; x64 = 'D:\jdkx64' }
$rc   = 0

if (-not $Install) { $Install = $env:DBCLI_HOME }
if (-not $Install) { $Install = (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $src))) }

$treeRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $src))
if (-not $DbcliJar) { $DbcliJar = $env:DBCLI_DBCLI_JAR }
if (-not $DbcliJar) { $DbcliJar = Join-Path $treeRoot 'lib\dbcli.jar' }

if (-not $JavaSrc) {
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

# --------------------------------------------------------------------------- width table drift
# org/jline/utils/AnsiWidthTables.java is generated, and it is the table JLine's whole column
# arithmetic reads. If the generator's rules move and that file is not regenerated, the grid and
# the layout disagree again -- the bug this file exists to keep from coming back, and invisible in
# any single test because both sides stay internally consistent. So the gate re-derives the Java
# table from the generator and refuses a stale copy. Every tree that builds is checked, not only
# the one being compiled: the trees are copies of each other by convention, and a half-synced
# pair is how the last one was found.
if ($SkipWidthCheck) {
    Write-Host '  WIDTH CHECK: skipped by -SkipWidthCheck'
} else {
    $genPy = Join-Path (Split-Path -Parent $src) 'luauf8\gen_ansi_tables.py'
    $py = if ($env:DBCLI_PYTHON) { $env:DBCLI_PYTHON } else { 'F:\tools\python312\python.exe' }
    $termSrc = Join-Path (Split-Path -Parent (Split-Path -Parent $JavaSrc)) 'terminal\src\main\java'
    $trees = @($termSrc)
    if ($env:DBCLI_JLINE_TREES) { $trees += @($env:DBCLI_JLINE_TREES -split '[;,]' | Where-Object { $_ }) }
    if (-not (Test-Path $py) -and -not (Get-Command $py -ErrorAction SilentlyContinue)) {
        Write-Host "  WIDTH CHECK: FAILED -- no python at $py (set DBCLI_PYTHON)"
        $rc = 1
    } elseif (-not (Test-Path $genPy)) {
        Write-Host "  WIDTH CHECK: FAILED -- no generator at $genPy"
        $rc = 1
    } else {
        foreach ($t in $trees) {
            $java = Join-Path $t 'org\jline\utils\AnsiWidthTables.java'
            if (-not (Test-Path $java)) {
                if ($t -eq $termSrc) {
                    Write-Host "  WIDTH CHECK: FAILED -- the build tree has no $java"
                    $rc = 1
                } else {
                    Write-Host "  WIDTH CHECK: skipped a tree with no $java"
                }
                continue
            }
            & $py $genPy --java-check $java 2>&1 | ForEach-Object { Write-Host "  WIDTH: $_" }
            if ($LASTEXITCODE -ne 0) {
                Write-Host "  WIDTH CHECK: FAILED (exit $LASTEXITCODE) for $java"
                $rc = 1
            }
        }
        if ($trees.Count -lt 2) {
            Write-Host '  WIDTH CHECK: only the build tree was checked; set DBCLI_JLINE_TREES to'
            Write-Host '               include every other copy of this source (semicolon separated).'
        }
    }
}

foreach ($a in @($Arch -eq 'both' ? @('x86', 'x64') : @($Arch))) {
    Write-Host "=== $a ($($jdk[$a])) ==="
    $hk = Join-Path $Install ('lib\{0}\ConEmuHk{1}.dll' -f $a, ($a -eq 'x86' ? '' : '64'))
    if (-not (Test-Path $hk)) {
        Write-Host "  both-leg A/B skipped: no $hk (candidates: -Install, DBCLI_HOME, $(Split-Path -Parent (Split-Path -Parent $src)))"
        $hk = ''
    }
    if (-not (Test-Path "$Scratch\$a\probe.dll")) { Write-Host "no $Scratch\$a\probe.dll - run build.sh first"; $rc = 1; continue }
    New-Item -ItemType Directory -Force -Path "$Scratch\out\$a" | Out-Null
    & "$($jdk[$a])\bin\javac.exe" -nowarn -encoding UTF-8 -d "$Scratch\out\$a" "$src\Probe.java"
    if ($LASTEXITCODE -ne 0) { Write-Host "javac failed for $a"; $rc = 1; continue }
    & "$($jdk[$a])\bin\java.exe" "-Djava.library.path=$Scratch\$a" -cp "$Scratch\out\$a" Probe
    if ($LASTEXITCODE -ne 0) { Write-Host "probe failed for $a (exit $LASTEXITCODE)"; $rc = 1 }

    if (-not (Test-Path "$Scratch\$a\render.dll")) { Write-Host "no $Scratch\$a\render.dll - run build.sh first"; $rc = 1; continue }
    & "$($jdk[$a])\bin\javac.exe" -nowarn -g -source 8 -target 8 -encoding UTF-8 -implicit:class -sourcepath "$JavaSrc" `
        -d "$Scratch\out\$a" "$src\Render.java"
    if ($LASTEXITCODE -ne 0) { Write-Host "javac Render.java failed for $a"; $rc = 1; continue }
    & "$($jdk[$a])\bin\java.exe" "-Djava.library.path=$Scratch\$a" "-Dhk=$hk" -cp "$Scratch\out\$a" Render
    if ($LASTEXITCODE -ne 0) { Write-Host "render gate failed for $a (exit $LASTEXITCODE)"; $rc = 1 }

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

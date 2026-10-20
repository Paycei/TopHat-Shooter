#Requires -Version 7.0
<#
  Builds the three TopHat-ShooterOS release artifacts into ship/:

    TopHatShooterOS-PORTABLE.zip          nimble WinRelease
    TopHatShooterOS-Installer_<ver>.exe   the same exe + niminst/Inno (vendor/niminst)
    TopHatShooterOS-linux-x86_64.tar.gz   nimble LinuxRelease, inside WSL
    SHA256SUMS.txt

  Compiler flags live in TopHatShooter.nimble, not here -- every build shells out
  to the matching task. The version comes from there too, and is synced into
  TopHatShooter.ini so the installer can never be stamped stale.

  Usage:  nimble ship     (or: pwsh -File tools/ship.ps1)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$env:WSL_UTF8 = '1'      # make wsl.exe emit UTF-8 instead of UTF-16LE

$RepoRoot     = Split-Path -Parent $PSScriptRoot
$ShipDir      = Join-Path $RepoRoot 'ship'
$PortableName = 'TopHatShooterOS-PORTABLE.zip'
$LinuxTarName = 'TopHatShooterOS-linux-x86_64.tar.gz'
$LinuxBinName = 'TopHatShooterOS-linux-x86_64'
$WinExeName   = 'TopHatShooterOS.exe'
$NiminstDir   = Join-Path $RepoRoot 'vendor/niminst'

function Run([string] $exe, [string[]] $argv, [string] $what) {
    & $exe @argv
    if ($LASTEXITCODE -ne 0) { throw "$what failed (exit $LASTEXITCODE)." }
}

function Use-Msvc {
    if (Get-Command cl.exe -ErrorAction SilentlyContinue) { return }
    # Rank installs by vswhere's installationVersion, never by folder name:
    # VS 2026 lives under "26", which sorts below "2019".
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { throw 'vswhere.exe not found; the release builds use --cc:vcc, so install the VC++ Build Tools.' }
    $best = & $vswhere -all -prerelease -products * -format json | ConvertFrom-Json |
        Where-Object { Test-Path (Join-Path $_.installationPath 'VC\Auxiliary\Build\vcvars64.bat') } |
        Sort-Object { [version] $_.installationVersion } -Descending | Select-Object -First 1
    if (-not $best) { throw 'No Visual Studio install has vcvars64.bat; add the "Desktop development with C++" workload.' }

    $vcvars = Join-Path $best.installationPath 'VC\Auxiliary\Build\vcvars64.bat'
    foreach ($line in (cmd.exe /c "`"$vcvars`" >nul 2>&1 && set")) {
        # SetEnvironmentVariable, not Set-Item Env:, because names like
        # ProgramFiles(x86) are not valid Env: provider paths.
        if ($line -match '^([^=]+)=(.*)$') { [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2]) }
    }
    if (-not (Get-Command cl.exe -ErrorAction SilentlyContinue)) { throw 'Imported the MSVC env but cl.exe is still missing.' }
}

function Build-Niminst {
    # niminst and the uninstaller the installer ships come from the vendor/niminst
    # submodule, rebuilt every time so they always match the recorded commit.
    # niminst.exe lands in the submodule root, next to the setup.ico its Inno
    # template resolves as getAppDir()/setup.ico. Both exes are gitignored there.
    Push-Location $NiminstDir
    try {
        Run 'nimble' @('--accept', 'install', '-d') 'niminst dependencies'
        Run 'nimble' @('release') 'niminst build'
        Run 'nimble' @('uninstaller') 'uninstaller build'
    }
    finally { Pop-Location }
    foreach ($f in 'niminst.exe', 'uninstaller.exe') {
        if (-not (Test-Path (Join-Path $NiminstDir $f))) { throw "vendor/niminst build finished but $f is missing." }
    }
}

function Find-Distro {
    foreach ($raw in (& wsl.exe -l -q)) {
        $name = $raw.Trim()
        if (-not $name -or $name -like 'docker-desktop*') { continue }
        # Needs a shell: `wsl -e` execs the binary directly, with no $HOME expansion.
        & wsl.exe -d $name -e bash -c 'test -x "$HOME/.nimble/bin/nim"' 2>$null
        if ($LASTEXITCODE -eq 0) { return $name }
    }
    throw 'No WSL distribution has Nim at ~/.nimble/bin/nim; install it there with choosenim.'
}

function Get-WslPath([string] $distro, [string] $path) {
    $p = & wsl.exe -d $distro -e wslpath -a "$path"
    if ($LASTEXITCODE -ne 0) { throw "Could not translate '$path' to a WSL path." }
    ($p | Select-Object -First 1).Trim()
}

function Assert-Submodule([string] $path) {
    # vendor/naylib and vendor/niminst are git submodules. Ship only what the game
    # commit records: a stray checkout or a local edit would make binaries no
    # commit can rebuild.
    $line = @(git -C $RepoRoot submodule status -- $path 2>$null)[0]
    if ($LASTEXITCODE -ne 0 -or -not $line) { throw "$path is not registered as a submodule." }
    switch ($line.Substring(0, 1)) {
        '-' { throw "$path is empty: run nimble submodules." }
        '+' { throw "$path is at a different commit than the game records: run nimble submodules, or commit the new pointer." }
        'U' { throw "$path has merge conflicts." }
    }
    if (git -C (Join-Path $RepoRoot $path) status --porcelain --untracked-files=no) {
        throw "$path has uncommitted changes: commit them in the submodule (and the new pointer here) first."
    }
}

function Build-Windows {
    # One WinRelease (speed, full LTO) build feeds both Windows artifacts:
    # the portable zip and the installer ship the same exe.
    Use-Msvc
    Run 'nimble' @('--accept', 'WinRelease') 'nimble WinRelease'
    $exe = Join-Path $RepoRoot $WinExeName
    if (-not (Test-Path $exe)) { throw "WinRelease finished but $WinExeName was not produced." }
    Compress-Archive -Path $exe -DestinationPath (Join-Path $ShipDir $PortableName) -CompressionLevel Optimal -Force

    Push-Location $RepoRoot     # niminst resolves the .ini's paths from the CWD
    try { Run (Join-Path $NiminstDir 'niminst.exe') @('inno', 'TopHatShooter.ini') 'niminst inno' }
    finally { Pop-Location }

    $built = Join-Path $RepoRoot "build\TopHatShooterOS-Installer_$Version.exe"
    if (-not (Test-Path $built)) { throw "Inno Setup reported success but $built is missing." }
    Copy-Item $built $ShipDir -Force
}

function Build-Linux {
    $distro = Find-Distro
    $repo = Get-WslPath $distro $RepoRoot
    $ship = Get-WslPath $distro $ShipDir
    # tar, not zip: only tar records the executable bit. --mode overrides the 777
    # that DrvFs reports for every file under /mnt.
    $cmd = "export PATH=`"`$HOME/.nimble/bin:`$PATH`" && cd '$repo' && nimble --accept LinuxRelease && " +
           "tar -czf '$ship/$LinuxTarName' --mode=755 --owner=0 --group=0 -C '$repo' '$LinuxBinName'"
    Run 'wsl.exe' @('-d', $distro, '-e', 'bash', '-c', $cmd) 'WSL Linux build'
    if (-not (Test-Path (Join-Path $ShipDir $LinuxTarName))) { throw "LinuxRelease finished but $LinuxTarName is missing." }
}

try {
    $iniFile = Join-Path $RepoRoot 'TopHatShooter.ini'
    if ((Get-Content -Raw (Join-Path $RepoRoot 'TopHatShooter.nimble')) -notmatch '(?m)^\s*version\s*=\s*"([^"]+)"') {
        throw 'Could not read the version assignment from TopHatShooter.nimble.'
    }
    $Version = $Matches[1]

    $iniText = Get-Content -Raw $iniFile
    if ($iniText -notmatch '(?m)^Version:\s*"([^"]*)"') { throw "Could not read Version from $iniFile." }
    if ($Matches[1] -ne $Version) {
        # .nimble is the single source of truth. Worth a word, since this writes
        # to a tracked file.
        [Console]::Error.WriteLine("ship: TopHatShooter.ini said $($Matches[1]); synced to $Version")
        $new = $iniText -replace '(?m)^(Version:\s*)"[^"]*"', ('${1}"' + $Version + '"')
        [IO.File]::WriteAllText($iniFile, $new, [Text.UTF8Encoding]::new($false))
    }

    # Verify the toolchain before the first compile: three release builds cost
    # minutes, a missing iscc.exe costs milliseconds.
    foreach ($t in 'nim', 'nimble') {
        if (-not (Get-Command $t -ErrorAction SilentlyContinue)) { throw "'$t' is not on PATH." }
    }
    Use-Msvc
    if ($iniText -match '(?m)^\s*path\s*=\s*r?"([^"]+)"') {
        $iscc = $Matches[1]
        if (-not (Test-Path $iscc)) { throw "Inno Setup compiler not found at '$iscc' ([InnoSetup] path in TopHatShooter.ini)." }
    }
    Find-Distro | Out-Null
    Assert-Submodule 'vendor/naylib'
    Assert-Submodule 'vendor/niminst'
    Build-Niminst      # seconds; the .ini's vendor\niminst\uninstaller.exe must exist before Inno runs

    Push-Location $RepoRoot
    try { Run 'nim' @('check', '--mm:orc', 'src/main.nim') 'nim check' }
    finally { Pop-Location }

    if (-not (Test-Path $ShipDir)) { New-Item -ItemType Directory -Path $ShipDir -Force | Out-Null }
    else {
        # Clear only the files this script produces, so anything staged by hand
        # survives. Installers are version-stamped, so the glob also sweeps away
        # one built for an older version.
        Get-ChildItem $ShipDir -File | Where-Object {
            $_.Name -like 'TopHatShooterOS-Installer_*.exe' -or
            $_.Name -in $PortableName, $LinuxTarName, 'SHA256SUMS.txt' } | Remove-Item -Force
    }

    Build-Windows
    Build-Linux

    $sums = foreach ($f in (Get-ChildItem $ShipDir -File | Sort-Object Name)) {
        '{0}  {1}' -f (Get-FileHash -Algorithm SHA256 -LiteralPath $f.FullName).Hash.ToLower(), $f.Name
    }
    # LF endings and two spaces: the format `sha256sum -c` expects.
    [IO.File]::WriteAllText((Join-Path $ShipDir 'SHA256SUMS.txt'), (($sums -join "`n") + "`n"), [Text.UTF8Encoding]::new($false))

    Get-ChildItem $ShipDir -File | Sort-Object Name
}
catch {
    [Console]::Error.WriteLine("ship: $($_.Exception.Message)")
    exit 1
}

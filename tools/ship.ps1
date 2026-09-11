#Requires -Version 7.0
<#
  Builds the three TopHat-ShooterOS release artifacts into ship/:

    TopHatShooterOS-PORTABLE.zip          nimble WinReleaseMin (size)
    TopHatShooterOS-Installer_<ver>.exe   nimble WinRelease (speed) + niminst/Inno
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

function Find-Niminst {
    # niminst's Inno template resolves its icon as getAppDir()/setup.ico, and
    # `nimble install` copies only the binary into <pkg>/bin -- so the copy on
    # PATH is usually the broken one. Take whichever has setup.ico beside it.
    $onPath = (Get-Command niminst -ErrorAction SilentlyContinue).Source
    if (-not $onPath) { throw "'niminst' is not on PATH (needed to generate the Inno Setup script)." }
    foreach ($c in @($onPath, (Join-Path (Split-Path (Split-Path $onPath)) 'niminst.exe'))) {
        if ((Test-Path $c) -and (Test-Path (Join-Path (Split-Path $c) 'setup.ico'))) { return $c }
    }
    throw "Found niminst at $onPath but no setup.ico beside it, nor beside the package-root copy."
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

function Build-Portable {
    Use-Msvc
    Run 'nimble' @('--accept', 'WinReleaseMin') 'nimble WinReleaseMin'
    $exe = Join-Path $RepoRoot $WinExeName
    if (-not (Test-Path $exe)) { throw "WinReleaseMin finished but $WinExeName was not produced." }
    Compress-Archive -Path $exe -DestinationPath (Join-Path $ShipDir $PortableName) -CompressionLevel Optimal -Force
}

function Build-Installer {
    Use-Msvc
    Run 'nimble' @('--accept', 'WinRelease') 'nimble WinRelease'
    $exe = Join-Path $RepoRoot $WinExeName
    if (-not (Test-Path $exe)) { throw "WinRelease finished but $WinExeName was not produced." }

    Push-Location $RepoRoot     # niminst resolves the .ini's paths from the CWD
    try { Run (Find-Niminst) @('inno', 'TopHatShooter.ini') 'niminst inno' }
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
    $uninstaller = Join-Path (Split-Path $RepoRoot) 'niminst\uninstaller.exe'   # the .ini's ..\niminst\uninstaller.exe
    if (-not (Test-Path $uninstaller)) { throw "TopHatShooter.ini references $uninstaller but it does not exist." }
    if ($iniText -match '(?m)^\s*path\s*=\s*r?"([^"]+)"') {
        $iscc = $Matches[1]
        if (-not (Test-Path $iscc)) { throw "Inno Setup compiler not found at '$iscc' ([InnoSetup] path in TopHatShooter.ini)." }
    }
    Find-Niminst | Out-Null
    Find-Distro  | Out-Null

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

    # Portable before installer: both write TopHatShooterOS.exe, and this order
    # leaves the speed-optimised build in the repo root.
    Build-Portable
    Build-Installer
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

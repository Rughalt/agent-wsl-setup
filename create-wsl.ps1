[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$DistroName = 'Ubuntu-Imps',

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$')]
    [string]$LinuxUser = 'imps',

    [string]$Distribution = 'Ubuntu-24.04',

    [string]$InstallLocation = (Join-Path $env:LOCALAPPDATA 'WSL\Ubuntu-Imps'),

    [string]$GitName = 'Ubuntu Imp',

    [string]$GitEmail = 'ubuntu-imps@localhost',

    [ValidateSet('all', 'devin', 'gh', 'glab', 'gt', 'zcode')]
    [string[]]$Tools = @(),

    [string]$SetupScript = (Join-Path $PSScriptRoot 'setup-wsl.sh'),

    [switch]$SetupOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$script:Step = 0
$script:TotalSteps = 4

function Show-Step {
    param([Parameter(Mandatory)][string]$Message)

    $script:Step++
    $percent = [Math]::Min(100, [Math]::Round(($script:Step / $script:TotalSteps) * 100))
    Write-Progress -Activity 'Ubuntu-Imps' -Status $Message -PercentComplete $percent
    Write-Host ("[{0}/{1}] {2}" -f $script:Step, $script:TotalSteps, $Message) -ForegroundColor Cyan
}

function Invoke-Wsl {
    param([Parameter(Mandatory)][string[]]$Arguments)

    & wsl.exe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "wsl.exe failed with exit code $LASTEXITCODE."
    }
}

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw 'WSL is not installed. Install the current Microsoft Store version of WSL first.'
}

if (-not (Test-Path -LiteralPath $SetupScript -PathType Leaf)) {
    throw "Setup script not found: $SetupScript"
}

foreach ($value in @($GitName, $GitEmail)) {
    if ($value -match "[`r`n]") {
        throw 'Git identity values must not contain newlines.'
    }
}

$installed = @(& wsl.exe --list --quiet) |
    ForEach-Object { ($_ -replace "`0", '').Trim() } |
    Where-Object { $_ }
$exists = $installed -contains $DistroName

if ($SetupOnly) {
    if (-not $exists) {
        throw "Distribution '$DistroName' is not installed."
    }
}
else {
    if ($exists) {
        throw "Distribution '$DistroName' already exists. Use -SetupOnly to re-run hardening."
    }

    $wslHelp = ((& wsl.exe --help 2>&1 | Out-String) -replace "`0", '')
    if ($wslHelp -notmatch '--name' -or $wslHelp -notmatch '--location') {
        throw 'This script needs a current Store version of WSL. Run: wsl --update'
    }

    if (Test-Path -LiteralPath $InstallLocation) {
        $children = @(Get-ChildItem -LiteralPath $InstallLocation -Force)
        if ($children.Count -gt 0) {
            throw "Install location is not empty: $InstallLocation"
        }
    }
    else {
        New-Item -ItemType Directory -Path $InstallLocation -Force | Out-Null
    }

    Show-Step "Installing a fresh $Distribution distribution as $DistroName"
    Invoke-Wsl @(
        '--install', $Distribution,
        '--name', $DistroName,
        '--location', $InstallLocation,
        '--version', '2',
        '--no-launch',
        '--web-download'
    )
}

$selectedTools = if ($Tools -contains 'all') {
    @('devin', 'gh', 'glab', 'gt', 'zcode')
}
else {
    @($Tools | Sort-Object -Unique)
}

Show-Step 'Applying the Linux baseline and WSL hardening'
$setupArgs = @(
    '--user', $LinuxUser,
    '--git-name', $GitName,
    '--git-email', $GitEmail,
    '--tools', ($selectedTools -join ',')
)

# The setup script is streamed over stdin so it does not depend on /mnt/c.
Get-Content -LiteralPath $SetupScript -Raw |
    & wsl.exe --distribution $DistroName --user root -- bash -s -- @setupArgs
if ($LASTEXITCODE -ne 0) {
    throw "Setup failed with exit code $LASTEXITCODE. The distribution was left installed for inspection."
}

# Restart only this distribution so /etc/wsl.conf takes effect.
Show-Step 'Restarting the distribution to apply wsl.conf'
Invoke-Wsl @('--terminate', $DistroName)

Show-Step 'Finished'
Write-Progress -Activity 'Ubuntu-Imps' -Completed

Write-Host ''
Write-Host "Ubuntu-Imps is ready. Start it with: wsl -d $DistroName"
Write-Host 'Windows drives and Windows-process interop are disabled for this distribution.'
if ($selectedTools.Count -gt 0) {
    Write-Host ("Optional tools installed: {0}" -f ($selectedTools -join ', '))
}
else {
    Write-Host 'No optional CLIs were installed. Re-run with -SetupOnly -Tools gh,gt,... later.'
}
Write-Host 'GitHub authentication was intentionally not automated. Inside the distro, run:'
Write-Host '  ssh-keygen -t ed25519 -a 100 -C "your-machine-user@users.noreply.github.com"'
Write-Host '  gh auth login --git-protocol ssh'
Write-Host ''
Write-Warning 'WSL is useful separation, not a strong security boundary. Use a separate VM for untrusted code.'

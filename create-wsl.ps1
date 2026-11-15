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

    [ValidateSet('all', 'devin', 'figcraft', 'gh', 'glab', 'go', 'gt', 'lerd', 'node', 'shiori', 'uv', 'zcode')]
    [string[]]$Tools = @(),

    [string]$SetupScript = (Join-Path $PSScriptRoot 'setup-wsl.sh'),

    [switch]$SetupOnly,

    [switch]$ResetDistro
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

function Remove-ManagedInstallLocation {
    param([Parameter(Mandatory)][string]$Path)

    $managedRoot = [System.IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'WSL'))
    $target = [System.IO.Path]::GetFullPath($Path)
    $managedPrefix = $managedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $target.StartsWith($managedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to recursively remove an install location outside the managed WSL directory: $target"
    }
    if (Test-Path -LiteralPath $target) {
        Remove-Item -LiteralPath $target -Recurse -Force
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

$selectedTools = if ($Tools -contains 'all') {
    @('devin', 'figcraft', 'gh', 'glab', 'go', 'gt', 'lerd', 'node', 'uv', 'zcode', 'shiori')
}
else {
    @($Tools | Sort-Object -Unique)
}
$script:TotalSteps = if ($selectedTools -contains 'lerd') { 5 } else { 4 }

$installed = @(& wsl.exe --list --quiet) |
    ForEach-Object { ($_ -replace "`0", '').Trim() } |
    Where-Object { $_ }
$exists = $installed -contains $DistroName

if ($exists -and -not $SetupOnly -and -not $ResetDistro) {
    Write-Host ''
    Write-Warning "Distribution '$DistroName' already exists."
    $answer = Read-Host 'Choose: [S] re-run setup, [R] reset and recreate, [C] cancel (default: S)'
    switch -Regex ($answer) {
        '^\s*$|^(?i:s|setup|y|yes|t|tak)$' { $SetupOnly = $true; break }
        '^(?i:r|reset)$' { $ResetDistro = $true; break }
        default {
            Write-Host 'Cancelled. The existing distribution was not changed.' -ForegroundColor Yellow
            return
        }
    }
}

if ($ResetDistro) {
    Write-Host ''
    Write-Warning "RESET PERMANENTLY DELETES '$DistroName' AND EVERY FILE AND CREDENTIAL STORED INSIDE IT."
    $confirmation = Read-Host "Type the exact distribution name '$DistroName' to continue"
    if ($confirmation -cne $DistroName) {
        Write-Host 'Reset cancelled. Nothing was deleted.' -ForegroundColor Yellow
        return
    }
    if ($exists) {
        & wsl.exe --terminate $DistroName 2>$null
        & wsl.exe --unregister $DistroName
        if ($LASTEXITCODE -ne 0) {
            throw "Could not unregister distribution '$DistroName'."
        }
    }
    Remove-ManagedInstallLocation -Path $InstallLocation
    $exists = $false
    $SetupOnly = $false
    Write-Host "Distribution '$DistroName' was removed and will be recreated." -ForegroundColor Yellow
}

if ($SetupOnly) {
    if (-not $exists) {
        throw "Distribution '$DistroName' is not installed."
    }
    Show-Step "Using the existing $DistroName distribution"
}
else {
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

Show-Step 'Applying the Linux baseline and WSL hardening'
$setupArgs = @(
    '--user', $LinuxUser,
    '--git-name', $GitName,
    '--git-email', $GitEmail,
    '--tools', ($selectedTools -join ',')
)

# PowerShell appends CRLF when piping a string to a native process. Without a
# final sentinel, an LF-terminated script gains a blank line containing only CR,
# which Bash attempts to execute as `$'\r'`. Let a comment absorb that suffix.
$setupInput = (Get-Content -LiteralPath $SetupScript -Raw).TrimEnd([char[]]"`r`n") + "`n# PowerShell stdin terminator"

# The setup script is streamed over stdin so it does not depend on /mnt/c.
$setupInput |
    & wsl.exe --distribution $DistroName --user root -- bash -s -- @setupArgs
if ($LASTEXITCODE -ne 0) {
    throw "Setup failed with exit code $LASTEXITCODE. The distribution was left installed for inspection."
}

# Restart only this distribution so /etc/wsl.conf takes effect.
Show-Step 'Restarting the distribution to apply wsl.conf'
Invoke-Wsl @('--terminate', $DistroName)

if ($selectedTools -contains 'lerd') {
    Show-Step 'Finishing Lerd setup after the systemd restart'
    $postRestartArgs = @($setupArgs) + '--post-restart'
    $setupInput |
        & wsl.exe --distribution $DistroName --user root -- bash -s -- @postRestartArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Lerd post-restart setup failed with exit code $LASTEXITCODE."
    }
    Invoke-Wsl @('--terminate', $DistroName)
}

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
Write-Host 'To enable password-based sudo for the agent user, run once from PowerShell:'
Write-Host "  wsl -d $DistroName -u root -- passwd $LinuxUser"
Write-Host ''
Write-Warning 'WSL is useful separation, not a strong security boundary. Use a separate VM for untrusted code.'

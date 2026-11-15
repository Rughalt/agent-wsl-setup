[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$DistroName = 'Ubuntu-Imps',

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$')]
    [string]$LinuxUser = 'imps',

    [string]$Distribution = 'Ubuntu-24.04',

    [string]$GitName = 'Ubuntu Imp',

    [string]$GitEmail = 'ubuntu-imps@localhost',

    [ValidateSet('all', 'devin', 'gh', 'glab', 'go', 'gt', 'lerd', 'node', 'uv', 'zcode')]
    [string[]]$Tools = @(),

    [switch]$SetupOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$rawBase = 'https://raw.githubusercontent.com/Rughalt/agent-wsl-setup/main'
$downloadRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-wsl-setup-{0}" -f [Guid]::NewGuid().ToString('N'))
$createPath = Join-Path $downloadRoot 'create-wsl.ps1'
$setupPath = Join-Path $downloadRoot 'setup-wsl.sh'

Write-Host 'Downloading the current Ubuntu-Imps installer from GitHub...' -ForegroundColor Cyan
New-Item -ItemType Directory -Path $downloadRoot | Out-Null

try {
    Invoke-WebRequest -UseBasicParsing -Uri "$rawBase/create-wsl.ps1" -OutFile $createPath
    Invoke-WebRequest -UseBasicParsing -Uri "$rawBase/setup-wsl.sh" -OutFile $setupPath

    $createScript = [ScriptBlock]::Create((Get-Content -LiteralPath $createPath -Raw))
    $arguments = @{
        DistroName   = $DistroName
        LinuxUser    = $LinuxUser
        Distribution = $Distribution
        GitName      = $GitName
        GitEmail     = $GitEmail
        Tools        = $Tools
        SetupScript  = $setupPath
    }
    if ($SetupOnly) {
        $arguments.SetupOnly = $true
    }

    & $createScript @arguments
}
finally {
    Remove-Item -LiteralPath $createPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $setupPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $downloadRoot -Force -ErrorAction SilentlyContinue
}

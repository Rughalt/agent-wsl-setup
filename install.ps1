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

    [switch]$SetupOnly,

    [switch]$ResetDistro
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# `irm ... | iex` cannot pass script parameters. Allow the concise README
# one-liner to provide the optional tool list through a separate variable.
if ($Tools.Count -eq 0) {
    $oneLineTools = Get-Variable -Name AgentWslTools -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($oneLineTools) {
        $Tools = @($oneLineTools -split '\s*,\s*' | Where-Object { $_ })
    }
}

if (-not $SetupOnly) {
    $oneLineSetupOnly = Get-Variable -Name AgentWslSetupOnly -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($oneLineSetupOnly -eq $true) {
        $SetupOnly = $true
    }
}

if (-not $ResetDistro) {
    $oneLineReset = Get-Variable -Name AgentWslResetDistro -Scope Global -ValueOnly -ErrorAction SilentlyContinue
    if ($oneLineReset -eq $true) {
        $ResetDistro = $true
    }
}

$allowedTools = @('all', 'devin', 'gh', 'glab', 'go', 'gt', 'lerd', 'node', 'uv', 'zcode')
$invalidTools = @($Tools | Where-Object { $_ -notin $allowedTools })
if ($invalidTools.Count -gt 0) {
    throw "Unknown tool(s): $($invalidTools -join ', '). Allowed values: $($allowedTools -join ', ')."
}

$rawBase = 'https://raw.githubusercontent.com/Rughalt/agent-wsl-setup/main'
$cacheBust = [Guid]::NewGuid().ToString('N')
$downloadRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-wsl-setup-{0}" -f [Guid]::NewGuid().ToString('N'))
$createPath = Join-Path $downloadRoot 'create-wsl.ps1'
$setupPath = Join-Path $downloadRoot 'setup-wsl.sh'

Write-Host 'Downloading the current Ubuntu-Imps installer from GitHub...' -ForegroundColor Cyan
New-Item -ItemType Directory -Path $downloadRoot | Out-Null

try {
    Invoke-WebRequest -UseBasicParsing -Uri "$rawBase/create-wsl.ps1?cache=$cacheBust" -OutFile $createPath
    Invoke-WebRequest -UseBasicParsing -Uri "$rawBase/setup-wsl.sh?cache=$cacheBust" -OutFile $setupPath

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
    if ($ResetDistro) {
        $arguments.ResetDistro = $true
    }

    & $createScript @arguments
}
finally {
    Remove-Item -LiteralPath $createPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $setupPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $downloadRoot -Force -ErrorAction SilentlyContinue
}

[CmdletBinding()]
param(
    [ValidatePattern('^[A-Za-z0-9._-]+$')]
    [string]$DistroName = 'Ubuntu-Imps',

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$')]
    [string]$LinuxUser = 'imps',

    [string]$Distribution = 'Ubuntu-24.04',

    [ValidatePattern('^(main|[0-9a-fA-F]{7,40})$')]
    [string]$SourceRef = 'main',

    [string]$GitName = 'Imp Kodzislaw',

    [string]$GitEmail = 'cespenar@dragonshorn.info',

    [ValidateSet('all', 'devin', 'figcraft', 'gh', 'glab', 'go', 'gt', 'lerd', 'node', 'shiori', 'uv', 'zcode')]
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

$oneLineSourceRef = Get-Variable -Name AgentWslSourceRef -Scope Global -ValueOnly -ErrorAction SilentlyContinue
if ($oneLineSourceRef) {
    $SourceRef = [string]$oneLineSourceRef
}
if ($SourceRef -notmatch '^(main|[0-9a-fA-F]{7,40})$') {
    throw 'SourceRef must be "main" or a 7-40 character hexadecimal commit SHA.'
}

$allowedTools = @('all', 'devin', 'figcraft', 'gh', 'glab', 'go', 'gt', 'lerd', 'node', 'shiori', 'uv', 'zcode')
$invalidTools = @($Tools | Where-Object { $_ -notin $allowedTools })
if ($invalidTools.Count -gt 0) {
    throw "Unknown tool(s): $($invalidTools -join ', '). Allowed values: $($allowedTools -join ', ')."
}

$rawBase = "https://raw.githubusercontent.com/Rughalt/agent-wsl-setup/$SourceRef"
$cacheBust = [Guid]::NewGuid().ToString('N')
$downloadRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-wsl-setup-{0}" -f [Guid]::NewGuid().ToString('N'))
$createPath = Join-Path $downloadRoot 'create-wsl.ps1'
$setupPath = Join-Path $downloadRoot 'setup-wsl.sh'

Write-Host "Downloading the Ubuntu-Imps installer from GitHub ref: $SourceRef" -ForegroundColor Cyan
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

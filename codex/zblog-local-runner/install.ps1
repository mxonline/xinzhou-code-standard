[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'),

    [string]$TaskName = 'XinZhao ZBlog Local Runner'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Require-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Config file not found: $ConfigPath. Copy config.example.json to config.json and edit the local paths first."
}

Require-Command 'git'
Require-Command 'gh'
Require-Command 'codex'
Require-Command 'php'
Require-Command 'powershell.exe'
Require-Command 'schtasks.exe'

$ghStatus = & gh auth status 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI is not authenticated. Complete 'gh auth login' once before installing the unattended runner.`n$ghStatus"
}

$codexVersion = & codex --version 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    throw "Codex CLI is not available.`n$codexVersion"
}

$configFull = (Resolve-Path -LiteralPath $ConfigPath).Path
$runnerFull = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot 'runner.ps1')).Path

# Keep the unattended policy in its own Codex profile instead of changing the global default.
$codexDir = Join-Path $env:USERPROFILE '.codex'
$codexConfig = Join-Path $codexDir 'config.toml'
New-Item -ItemType Directory -Path $codexDir -Force | Out-Null
if (-not (Test-Path -LiteralPath $codexConfig)) {
    New-Item -ItemType File -Path $codexConfig -Force | Out-Null
}

$currentCodexConfig = Get-Content -LiteralPath $codexConfig -Raw -ErrorAction SilentlyContinue
if ($null -eq $currentCodexConfig) { $currentCodexConfig = '' }
if ($currentCodexConfig -notmatch '(?m)^\[profiles\.zblog_unattended\]\s*$') {
    $profile = @'

# XinZhao Z-Blog unattended local runner.
# Keep this profile scoped to the runner; do not turn the global Codex default into full access.
[profiles.zblog_unattended]
approval_policy = "never"
sandbox_mode = "workspace-write"
model_reasoning_effort = "high"
'@
    Add-Content -LiteralPath $codexConfig -Value $profile -Encoding UTF8
    Write-Host "Added Codex profile: zblog_unattended"
}
else {
    Write-Host "Codex profile already exists: zblog_unattended"
}

# Preflight validates GitHub auth, Codex availability, PHP, repo origins and local worktrees.
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runnerFull -ConfigPath $configFull -Preflight
if ($LASTEXITCODE -ne 0) {
    throw 'Runner preflight failed. Scheduled task was not registered.'
}

$taskCommand = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$runnerFull`" -ConfigPath `"$configFull`" -Once"
& schtasks.exe /Create /TN $TaskName /TR $taskCommand /SC MINUTE /MO 1 /F | Out-Host
if ($LASTEXITCODE -ne 0) {
    throw 'Windows Task Scheduler registration failed.'
}

Write-Host ''
Write-Host 'Z-Blog Local Runner installation: PASS'
Write-Host "Task: $TaskName"
Write-Host "Runner: $runnerFull"
Write-Host "Config: $configFull"
Write-Host "Codex profile: zblog_unattended"
Write-Host ''
Write-Host 'The runner can now consume [LOCAL-RUNNER] GitHub Issues without opening the Codex desktop app.'

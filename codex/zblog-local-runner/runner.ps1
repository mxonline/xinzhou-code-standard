[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'),

    [switch]$Once,
    [switch]$Preflight
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-RunnerLog {
    param([string]$Message, [string]$Level = 'INFO', [string]$LogFile = $null)
    $line = ('{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message)
    Write-Host $line
    if ($LogFile) {
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    }
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$File,
        [Parameter(Mandatory = $false)][string[]]$Arguments = @(),
        [Parameter(Mandatory = $false)][string]$WorkingDirectory = $null
    )

    $old = Get-Location
    try {
        if ($WorkingDirectory) { Set-Location -LiteralPath $WorkingDirectory }
        $output = & $File @Arguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        return [pscustomobject]@{ ExitCode = $exitCode; Output = $output.TrimEnd() }
    }
    finally {
        Set-Location -LiteralPath $old
    }
}

function Require-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not found: $Name"
    }
}

function Expand-PathValue {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    return [Environment]::ExpandEnvironmentVariables($Value)
}

function Load-RunnerConfig {
    param([string]$Path)
    $full = (Resolve-Path -LiteralPath $Path).Path
    $cfg = Get-Content -LiteralPath $full -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $cfg.projects) { throw 'config.json has no projects.' }
    if (-not $cfg.task_title_prefix) { $cfg | Add-Member -NotePropertyName task_title_prefix -NotePropertyValue '[LOCAL-RUNNER]' }
    if (-not $cfg.task_marker) { $cfg | Add-Member -NotePropertyName task_marker -NotePropertyValue 'XINZHOU_LOCAL_RUNNER_TASK_V1' }
    if (-not $cfg.max_local_attempts) { $cfg | Add-Member -NotePropertyName max_local_attempts -NotePropertyValue 3 }
    if (-not $cfg.poll_limit) { $cfg | Add-Member -NotePropertyName poll_limit -NotePropertyValue 10 }
    if (-not $cfg.codex_profile) { $cfg | Add-Member -NotePropertyName codex_profile -NotePropertyValue 'zblog_unattended' }
    $cfg.log_root = Expand-PathValue ([string]$cfg.log_root)
    return $cfg
}

function Get-ProjectConfig {
    param($Config, [string]$ProjectName)
    foreach ($p in $Config.projects) {
        if ([string]$p.name -eq $ProjectName) { return $p }
    }
    return $null
}

function Assert-ProjectConfig {
    param($Project)
    if (-not $Project.name -or -not $Project.repo -or -not $Project.worktree -or -not $Project.base_branch) {
        throw 'Project config is missing name/repo/worktree/base_branch.'
    }
    $Project.worktree = Expand-PathValue ([string]$Project.worktree)
    if (-not (Test-Path -LiteralPath $Project.worktree -PathType Container)) {
        throw "Worktree not found: $($Project.worktree)"
    }
    if (-not (Test-Path -LiteralPath (Join-Path $Project.worktree '.git'))) {
        throw "Worktree is not a Git repository: $($Project.worktree)"
    }
}

function Assert-Preflight {
    param($Config)
    Require-Command 'git'
    Require-Command 'gh'
    Require-Command 'codex'
    Require-Command 'powershell.exe'

    $gh = Invoke-Native 'gh' @('auth', 'status')
    if ($gh.ExitCode -ne 0) { throw "GitHub CLI is not authenticated.`n$($gh.Output)" }

    $codex = Invoke-Native 'codex' @('--version')
    if ($codex.ExitCode -ne 0) { throw "Codex CLI is not available.`n$($codex.Output)" }

    foreach ($p in $Config.projects) {
        Assert-ProjectConfig $p
        $php = if ($p.php_executable) { [string]$p.php_executable } else { 'php' }
        Require-Command $php

        $remote = Invoke-Native 'git' @('-C', $p.worktree, 'remote', 'get-url', 'origin')
        if ($remote.ExitCode -ne 0) { throw "Cannot read Git origin for $($p.name)." }
        if ($remote.Output -notmatch [regex]::Escape([string]$p.repo)) {
            throw "Git origin mismatch for $($p.name). Expected repo $($p.repo), got $($remote.Output)"
        }
    }
}

function Parse-TaskFromIssue {
    param([string]$Body, [string]$Marker)
    if ($Body -notmatch [regex]::Escape($Marker)) { return $null }
    $match = [regex]::Match($Body, '(?s)```json\s*(.*?)\s*```')
    if (-not $match.Success) { throw 'Task issue does not contain a fenced JSON block.' }
    return ($match.Groups[1].Value | ConvertFrom-Json)
}

function Validate-Task {
    param($Task, $Project)
    if ([int]$Task.schema_version -ne 1) { throw 'Unsupported task schema_version.' }
    if ([string]$Task.project -ne [string]$Project.name) { throw 'Task project does not match runner project.' }
    if ([string]$Task.run_id -notmatch '^DEV-\d{8}-\d{3,}$') { throw 'Invalid run_id.' }
    if ([string]$Task.target_branch -notmatch '^[A-Za-z0-9._/-]+$') { throw 'Invalid target_branch.' }
    if ([string]$Task.target_branch -match '\.\.' -or [string]$Task.target_branch -match '^/' -or [string]$Task.target_branch -match '/$') {
        throw 'Unsafe target_branch.'
    }

    $allowed = $false
    foreach ($prefix in $Project.allowed_branch_prefixes) {
        if ([string]$Task.target_branch -like (([string]$prefix) + '*')) { $allowed = $true; break }
    }
    if (-not $allowed) { throw "Branch prefix is not allowed: $($Task.target_branch)" }
    if ([string]::IsNullOrWhiteSpace([string]$Task.objective)) { throw 'Task objective is empty.' }
}

function Add-IssueComment {
    param([string]$Repo, [int]$IssueNumber, [string]$Body)
    $tmp = [IO.Path]::GetTempFileName()
    try {
        Set-Content -LiteralPath $tmp -Value $Body -Encoding UTF8
        return Invoke-Native 'gh' @('issue', 'comment', [string]$IssueNumber, '--repo', $Repo, '--body-file', $tmp)
    }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

function Close-Issue {
    param([string]$Repo, [int]$IssueNumber)
    return Invoke-Native 'gh' @('issue', 'close', [string]$IssueNumber, '--repo', $Repo)
}

function Get-StatePath {
    param([string]$StateRoot, [string]$Repo, [int]$IssueNumber)
    $safeRepo = $Repo -replace '[^A-Za-z0-9._-]', '_'
    return Join-Path $StateRoot ("{0}-{1}.json" -f $safeRepo, $IssueNumber)
}

function Save-State {
    param([string]$Path, $State)
    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Prepare-Worktree {
    param($Project, $Task, [bool]$Resume, [string]$LogFile)
    $worktree = [string]$Project.worktree
    $branch = [string]$Task.target_branch

    if (-not $Resume) {
        $status = Invoke-Native 'git' @('-C', $worktree, 'status', '--porcelain')
        if ($status.ExitCode -ne 0) { throw $status.Output }
        if (-not [string]::IsNullOrWhiteSpace($status.Output)) {
            throw 'Worktree has uncommitted changes. Runner will not overwrite them.'
        }
    }

    $fetch = Invoke-Native 'git' @('-C', $worktree, 'fetch', 'origin', '--prune')
    Write-RunnerLog $fetch.Output 'GIT' $LogFile
    if ($fetch.ExitCode -ne 0) { throw 'git fetch failed.' }

    if ($Resume) {
        $current = Invoke-Native 'git' @('-C', $worktree, 'branch', '--show-current')
        if ($current.ExitCode -ne 0 -or $current.Output.Trim() -ne $branch) {
            throw "Resume state expects branch $branch but current branch is $($current.Output.Trim())."
        }
        return
    }

    $remoteBranch = Invoke-Native 'git' @('-C', $worktree, 'ls-remote', '--exit-code', '--heads', 'origin', $branch)
    if ($remoteBranch.ExitCode -eq 0) {
        $checkout = Invoke-Native 'git' @('-C', $worktree, 'checkout', '-B', $branch, ("origin/{0}" -f $branch))
    }
    else {
        $base = [string]$Project.base_branch
        $checkout = Invoke-Native 'git' @('-C', $worktree, 'checkout', '-B', $branch, ("origin/{0}" -f $base))
    }
    Write-RunnerLog $checkout.Output 'GIT' $LogFile
    if ($checkout.ExitCode -ne 0) { throw 'git checkout failed.' }
}

function Build-CodexPrompt {
    param($Task, $Project, [string]$FailureContext = '')

    $criteria = @()
    if ($Task.acceptance_criteria) {
        foreach ($item in $Task.acceptance_criteria) { $criteria += ('- ' + [string]$item) }
    }

    $prompt = @"
You are the local implementation worker for Z-Blog development run $($Task.run_id).

Hard boundaries:
- Work only on the current Git repository/worktree: $($Project.worktree)
- Do not modify Z-Blog zb_system core files outside this repository.
- Do not perform git commit, git push, merge, tag, release, or issue operations. The PowerShell runner owns Git/GitHub state.
- Do not deploy to production and do not modify production data.
- Complete the requested code change end to end without asking the user for routine confirmation.
- Keep changes focused and compatible with the existing project style and Z-Blog native mechanisms.
- Inspect the real existing code before changing it.
- If a local command is blocked by the sandbox, continue with code work where possible and report the blocker in the final result; do not request interactive approval.

Objective:
$($Task.objective)

Acceptance criteria:
$($criteria -join "`n")
"@

    if (-not [string]::IsNullOrWhiteSpace($FailureContext)) {
        $trimmed = $FailureContext
        if ($trimmed.Length -gt 12000) { $trimmed = $trimmed.Substring($trimmed.Length - 12000) }
        $prompt += @"

Previous automated validation failed. Fix the root cause, then leave the worktree ready for another validation pass.

Validation/CI output:
$trimmed
"@
    }
    return $prompt
}

function Invoke-CodexWorker {
    param($Config, $Project, $Task, [string]$FailureContext, [string]$LogFile)
    $prompt = Build-CodexPrompt $Task $Project $FailureContext
    Write-RunnerLog "Starting Codex for $($Task.run_id)" 'CODEX' $LogFile
    $result = Invoke-Native 'codex' @('exec', '--profile', [string]$Config.codex_profile, $prompt) $Project.worktree
    Write-RunnerLog $result.Output 'CODEX' $LogFile
    return $result
}

function Invoke-PhpLint {
    param($Project)
    if (-not $Project.tests -or -not $Project.tests.php_lint) {
        return [pscustomobject]@{ Success = $true; Output = 'PHP lint: skipped' }
    }
    $php = if ($Project.php_executable) { [string]$Project.php_executable } else { 'php' }
    $lines = New-Object System.Collections.Generic.List[string]
    $ok = $true
    $files = Get-ChildItem -LiteralPath $Project.worktree -Recurse -Filter '*.php' -File | Where-Object { $_.FullName -notmatch '[\\/]vendor[\\/]' }
    foreach ($file in $files) {
        $r = Invoke-Native $php @('-l', $file.FullName)
        $lines.Add($r.Output)
        if ($r.ExitCode -ne 0) { $ok = $false }
    }
    return [pscustomobject]@{ Success = $ok; Output = ($lines -join "`n") }
}

function Invoke-PhpUnit {
    param($Project)
    if (-not $Project.tests -or -not $Project.tests.phpunit) {
        return [pscustomobject]@{ Success = $true; Output = 'PHPUnit: skipped' }
    }

    $candidates = @(
        (Join-Path $Project.worktree 'vendor\bin\phpunit.bat'),
        (Join-Path $Project.worktree 'vendor\bin\phpunit.cmd'),
        (Join-Path $Project.worktree 'vendor\bin\phpunit')
    )
    $exe = $null
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $exe = $candidate; break }
    }
    if (-not $exe -and (Get-Command 'phpunit' -ErrorAction SilentlyContinue)) { $exe = 'phpunit' }

    if (-not $exe) {
        $required = $false
        if ($Project.tests.phpunit_required) { $required = [bool]$Project.tests.phpunit_required }
        return [pscustomobject]@{ Success = (-not $required); Output = 'PHPUnit executable not found.' }
    }

    $r = Invoke-Native $exe @() $Project.worktree
    return [pscustomobject]@{ Success = ($r.ExitCode -eq 0); Output = $r.Output }
}

function Invoke-TrustedProjectTest {
    param($Project)
    if (-not $Project.tests -or -not $Project.tests.trusted_test_script) {
        return [pscustomobject]@{ Success = $true; Output = 'Trusted project test: not configured' }
    }

    $script = Expand-PathValue ([string]$Project.tests.trusted_test_script)
    $required = $false
    if ($Project.tests.trusted_test_script_required) { $required = [bool]$Project.tests.trusted_test_script_required }
    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
        return [pscustomobject]@{ Success = (-not $required); Output = "Trusted test script not found: $script" }
    }

    # The trusted test script must live outside the Codex-editable worktree.
    $worktreeFull = [IO.Path]::GetFullPath([string]$Project.worktree).TrimEnd('\')
    $scriptFull = [IO.Path]::GetFullPath($script)
    if ($scriptFull.StartsWith($worktreeFull, [StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{ Success = $false; Output = 'Refusing to execute trusted_test_script from inside the Codex-editable worktree.' }
    }

    $r = Invoke-Native 'powershell.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptFull, '-Worktree', [string]$Project.worktree)
    return [pscustomobject]@{ Success = ($r.ExitCode -eq 0); Output = $r.Output }
}

function Invoke-HttpSmoke {
    param($Project)
    if (-not $Project.tests -or -not $Project.tests.http_smoke) {
        return [pscustomobject]@{ Success = $true; Output = 'HTTP smoke: skipped' }
    }

    $url = [string]$Project.tests.site_url
    $timeout = if ($Project.tests.http_timeout_sec) { [int]$Project.tests.http_timeout_sec } else { 20 }
    try {
        $response = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec $timeout
        $code = [int]$response.StatusCode
        $ok = ($code -ge 200 -and $code -lt 500)
        return [pscustomobject]@{ Success = $ok; Output = "HTTP $code $url" }
    }
    catch {
        return [pscustomobject]@{ Success = $false; Output = ("HTTP smoke failed: " + $_.Exception.Message) }
    }
}

function Invoke-LocalValidation {
    param($Project, [string]$LogFile)
    $parts = New-Object System.Collections.Generic.List[string]
    $success = $true

    $lint = Invoke-PhpLint $Project
    $parts.Add("=== PHP LINT ===`n$($lint.Output)")
    if (-not $lint.Success) { $success = $false }

    $unit = Invoke-PhpUnit $Project
    $parts.Add("=== PHPUNIT ===`n$($unit.Output)")
    if (-not $unit.Success) { $success = $false }

    $trusted = Invoke-TrustedProjectTest $Project
    $parts.Add("=== TRUSTED PROJECT TEST ===`n$($trusted.Output)")
    if (-not $trusted.Success) { $success = $false }

    $http = Invoke-HttpSmoke $Project
    $parts.Add("=== HTTP SMOKE ===`n$($http.Output)")
    if (-not $http.Success) { $success = $false }

    $output = $parts -join "`n`n"
    Write-RunnerLog $output 'TEST' $LogFile
    return [pscustomobject]@{ Success = $success; Output = $output }
}

function Commit-And-Push {
    param($Project, $Task, [string]$LogFile, [bool]$Wip = $false)
    $worktree = [string]$Project.worktree
    $status = Invoke-Native 'git' @('-C', $worktree, 'status', '--porcelain')
    if ([string]::IsNullOrWhiteSpace($status.Output)) {
        $sha = Invoke-Native 'git' @('-C', $worktree, 'rev-parse', 'HEAD')
        return [pscustomobject]@{ Success = $true; Changed = $false; Commit = $sha.Output.Trim(); Output = 'No changes to commit.' }
    }

    $add = Invoke-Native 'git' @('-C', $worktree, 'add', '-A')
    if ($add.ExitCode -ne 0) { return [pscustomobject]@{ Success = $false; Changed = $true; Commit = ''; Output = $add.Output } }

    if ($Wip) {
        $message = "wip: $($Task.run_id) local runner validation failed"
    }
    else {
        $message = [string]$Task.commit_message
        if ([string]::IsNullOrWhiteSpace($message)) { $message = "feat: complete $($Task.run_id)" }
        $message = ($message -replace '[\r\n]+', ' ').Trim()
        if ($message.Length -gt 160) { $message = $message.Substring(0, 160) }
    }

    $commit = Invoke-Native 'git' @('-C', $worktree, 'commit', '-m', $message)
    Write-RunnerLog $commit.Output 'GIT' $LogFile
    if ($commit.ExitCode -ne 0) { return [pscustomobject]@{ Success = $false; Changed = $true; Commit = ''; Output = $commit.Output } }

    $sha = Invoke-Native 'git' @('-C', $worktree, 'rev-parse', 'HEAD')
    if ($Task.auto_push -eq $false) {
        return [pscustomobject]@{ Success = $true; Changed = $true; Commit = $sha.Output.Trim(); Output = 'Committed; push disabled by task.' }
    }

    $push = Invoke-Native 'git' @('-C', $worktree, 'push', '-u', 'origin', [string]$Task.target_branch)
    Write-RunnerLog $push.Output 'GIT' $LogFile
    return [pscustomobject]@{ Success = ($push.ExitCode -eq 0); Changed = $true; Commit = $sha.Output.Trim(); Output = $push.Output }
}

function Wait-GitHubCI {
    param($Project, [string]$CommitSha, [string]$LogFile)
    if (-not $Project.ci -or -not $Project.ci.enabled) {
        return [pscustomobject]@{ Success = $true; Found = $false; Output = 'CI: disabled'; FailedLogs = '' }
    }

    $repo = [string]$Project.repo
    $branch = [string](Invoke-Native 'git' @('-C', $Project.worktree, 'branch', '--show-current')).Output.Trim()
    $discoverTimeout = if ($Project.ci.discovery_timeout_sec) { [int]$Project.ci.discovery_timeout_sec } else { 180 }
    $completeTimeout = if ($Project.ci.completion_timeout_sec) { [int]$Project.ci.completion_timeout_sec } else { 900 }
    $poll = if ($Project.ci.poll_interval_sec) { [int]$Project.ci.poll_interval_sec } else { 15 }
    $required = $true
    if ($null -ne $Project.ci.required) { $required = [bool]$Project.ci.required }

    $foundRuns = @()
    $deadline = (Get-Date).AddSeconds($discoverTimeout)
    while ((Get-Date) -lt $deadline) {
        $list = Invoke-Native 'gh' @('run', 'list', '--repo', $repo, '--branch', $branch, '--limit', '20', '--json', 'databaseId,status,conclusion,headSha,workflowName,url')
        if ($list.ExitCode -eq 0 -and -not [string]::IsNullOrWhiteSpace($list.Output)) {
            $items = $list.Output | ConvertFrom-Json
            $foundRuns = @($items | Where-Object { [string]$_.headSha -eq $CommitSha })
            if ($foundRuns.Count -gt 0) { break }
        }
        Start-Sleep -Seconds $poll
    }

    if ($foundRuns.Count -eq 0) {
        $msg = "No GitHub Actions run found for commit $CommitSha within ${discoverTimeout}s."
        return [pscustomobject]@{ Success = (-not $required); Found = $false; Output = $msg; FailedLogs = '' }
    }

    $completeDeadline = (Get-Date).AddSeconds($completeTimeout)
    while ((Get-Date) -lt $completeDeadline) {
        $list = Invoke-Native 'gh' @('run', 'list', '--repo', $repo, '--branch', $branch, '--limit', '20', '--json', 'databaseId,status,conclusion,headSha,workflowName,url')
        if ($list.ExitCode -ne 0) { Start-Sleep -Seconds $poll; continue }
        $items = $list.Output | ConvertFrom-Json
        $foundRuns = @($items | Where-Object { [string]$_.headSha -eq $CommitSha })
        if ($foundRuns.Count -gt 0 -and @($foundRuns | Where-Object { $_.status -ne 'completed' }).Count -eq 0) { break }
        Start-Sleep -Seconds $poll
    }

    if (@($foundRuns | Where-Object { $_.status -ne 'completed' }).Count -gt 0) {
        return [pscustomobject]@{ Success = $false; Found = $true; Output = "CI did not complete within ${completeTimeout}s."; FailedLogs = '' }
    }

    $failed = @($foundRuns | Where-Object { $_.conclusion -notin @('success', 'skipped', 'neutral') })
    $summary = ($foundRuns | ForEach-Object { "[$($_.conclusion)] $($_.workflowName) $($_.url)" }) -join "`n"
    Write-RunnerLog $summary 'CI' $LogFile

    if ($failed.Count -eq 0) {
        return [pscustomobject]@{ Success = $true; Found = $true; Output = $summary; FailedLogs = '' }
    }

    $logs = New-Object System.Collections.Generic.List[string]
    foreach ($run in $failed) {
        $view = Invoke-Native 'gh' @('run', 'view', [string]$run.databaseId, '--repo', $repo, '--log-failed')
        $logs.Add("=== $($run.workflowName) / $($run.databaseId) ===`n$($view.Output)")
    }
    return [pscustomobject]@{ Success = $false; Found = $true; Output = $summary; FailedLogs = ($logs -join "`n`n") }
}

function Process-TaskIssue {
    param($Config, $Project, $Issue, [string]$StateRoot)
    $task = Parse-TaskFromIssue ([string]$Issue.body) ([string]$Config.task_marker)
    if (-not $task) { return }
    Validate-Task $task $Project

    $issueNumber = [int]$Issue.number
    $logDir = Join-Path $Config.log_root ([string]$task.run_id)
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $logFile = Join-Path $logDir ("issue-{0}.log" -f $issueNumber)
    $statePath = Get-StatePath $StateRoot ([string]$Project.repo) $issueNumber
    $resume = Test-Path -LiteralPath $statePath

    if (-not $resume) {
        $state = [pscustomobject]@{
            run_id = [string]$task.run_id
            repo = [string]$Project.repo
            issue = $issueNumber
            branch = [string]$task.target_branch
            status = 'claimed'
            local_attempt = 0
            ci_repair_attempt = 0
            started_at = (Get-Date).ToString('o')
        }
        Save-State $statePath $state
        Add-IssueComment $Project.repo $issueNumber ("[LOCAL-RUNNER][CLAIMED]`n`nRunner: $($Config.runner_id)`nRun: $($task.run_id)`nBranch: $($task.target_branch)") | Out-Null
    }
    else {
        $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-RunnerLog "Resuming task $($task.run_id) from local state." 'STATE' $logFile
    }

    try {
        Prepare-Worktree $Project $task $resume $logFile
        $failureContext = ''
        $localPassed = $false
        $maxAttempts = [Math]::Max(1, [Math]::Min(10, [int]$Config.max_local_attempts))

        for ($attempt = ([int]$state.local_attempt + 1); $attempt -le $maxAttempts; $attempt++) {
            $state.local_attempt = $attempt
            $state.status = 'codex'
            Save-State $statePath $state

            $codex = Invoke-CodexWorker $Config $Project $task $failureContext $logFile
            if ($codex.ExitCode -ne 0) {
                $failureContext = "Codex process failed with exit code $($codex.ExitCode).`n$($codex.Output)"
                Write-RunnerLog $failureContext 'ERROR' $logFile
                continue
            }

            $state.status = 'local_validation'
            Save-State $statePath $state
            $validation = Invoke-LocalValidation $Project $logFile
            if ($validation.Success) {
                $localPassed = $true
                break
            }
            $failureContext = $validation.Output
        }

        if (-not $localPassed) {
            $wip = Commit-And-Push $Project $task $logFile $true
            $body = "[LOCAL-RUNNER][FAILED]`n`nRun: $($task.run_id)`nStage: local validation`nBranch: $($task.target_branch)`nCommit: $($wip.Commit)`n`nSee runner log for full output.`n`nLast validation:`n```text`n$failureContext`n```"
            if ($body.Length -gt 60000) { $body = $body.Substring(0, 60000) }
            Add-IssueComment $Project.repo $issueNumber $body | Out-Null
            Close-Issue $Project.repo $issueNumber | Out-Null
            Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
            return
        }

        $state.status = 'commit_push'
        Save-State $statePath $state
        $git = Commit-And-Push $Project $task $logFile $false
        if (-not $git.Success) { throw "Commit/push failed.`n$($git.Output)" }
        $commitSha = [string]$git.Commit

        $ciRepairMax = 0
        if ($Project.ci -and $Project.ci.max_repair_attempts) { $ciRepairMax = [int]$Project.ci.max_repair_attempts }
        $ciResult = $null

        for ($ciAttempt = ([int]$state.ci_repair_attempt); $ciAttempt -le $ciRepairMax; $ciAttempt++) {
            $state.ci_repair_attempt = $ciAttempt
            $state.status = 'ci_wait'
            Save-State $statePath $state
            $ciResult = Wait-GitHubCI $Project $commitSha $logFile
            if ($ciResult.Success) { break }
            if ($ciAttempt -ge $ciRepairMax) { break }

            $state.status = 'ci_repair'
            Save-State $statePath $state
            $repairContext = if ($ciResult.FailedLogs) { $ciResult.FailedLogs } else { $ciResult.Output }
            $codexRepair = Invoke-CodexWorker $Config $Project $task $repairContext $logFile
            if ($codexRepair.ExitCode -ne 0) { continue }
            $validation = Invoke-LocalValidation $Project $logFile
            if (-not $validation.Success) { continue }
            $repairCommit = Commit-And-Push $Project $task $logFile $false
            if (-not $repairCommit.Success) { throw "CI repair push failed.`n$($repairCommit.Output)" }
            $commitSha = [string]$repairCommit.Commit
        }

        if ($ciResult -and -not $ciResult.Success) {
            $body = "[LOCAL-RUNNER][FAILED]`n`nRun: $($task.run_id)`nStage: GitHub CI`nBranch: $($task.target_branch)`nCommit: $commitSha`n`nCI:`n```text`n$($ciResult.Output)`n```"
            Add-IssueComment $Project.repo $issueNumber $body | Out-Null
            Close-Issue $Project.repo $issueNumber | Out-Null
            Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
            return
        }

        $state.status = 'completed'
        Save-State $statePath $state
        $ciText = if ($ciResult) { $ciResult.Output } else { 'CI not configured.' }
        $successBody = "[LOCAL-RUNNER][SUCCESS]`n`nRun: $($task.run_id)`nProject: $($Project.name)`nBranch: $($task.target_branch)`nCommit: $commitSha`nLocal validation: PASS`n`nCI:`n```text`n$ciText`n```"
        Add-IssueComment $Project.repo $issueNumber $successBody | Out-Null
        Close-Issue $Project.repo $issueNumber | Out-Null
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
        Write-RunnerLog "Completed $($task.run_id) at $commitSha" 'DONE' $logFile
    }
    catch {
        $msg = $_.Exception.Message
        Write-RunnerLog $msg 'FATAL' $logFile
        Add-IssueComment $Project.repo $issueNumber ("[LOCAL-RUNNER][BLOCKED]`n`nRun: $($task.run_id)`nRunner: $($Config.runner_id)`n`n$msg`n`nLocal state retained for automatic resume unless the issue is closed manually.") | Out-Null
        throw
    }
}

$mutex = New-Object System.Threading.Mutex($false, 'Global\XinZhaoZBlogLocalRunner')
$hasMutex = $false
try {
    $hasMutex = $mutex.WaitOne(0)
    if (-not $hasMutex) { exit 0 }

    $config = Load-RunnerConfig $ConfigPath
    New-Item -ItemType Directory -Path $config.log_root -Force | Out-Null
    $stateRoot = Join-Path ([IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $ConfigPath).Path)) 'state'
    New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null

    Assert-Preflight $config
    if ($Preflight) {
        Write-Host 'Z-Blog Local Runner preflight: PASS'
        exit 0
    }

    foreach ($project in $config.projects) {
        Assert-ProjectConfig $project
        $search = (([string]$config.task_title_prefix) + ' in:title')
        $issuesResult = Invoke-Native 'gh' @('issue', 'list', '--repo', [string]$project.repo, '--state', 'open', '--search', $search, '--limit', [string]$config.poll_limit, '--json', 'number,title,body,url,createdAt')
        if ($issuesResult.ExitCode -ne 0) {
            Write-RunnerLog "Cannot list issues for $($project.repo): $($issuesResult.Output)" 'ERROR'
            continue
        }
        if ([string]::IsNullOrWhiteSpace($issuesResult.Output)) { continue }
        $issues = @($issuesResult.Output | ConvertFrom-Json)
        foreach ($issue in $issues) {
            if ([string]$issue.title -notlike (([string]$config.task_title_prefix) + '*')) { continue }
            try {
                $task = Parse-TaskFromIssue ([string]$issue.body) ([string]$config.task_marker)
                if (-not $task) { continue }
                if ([string]$task.project -ne [string]$project.name) { continue }
                Process-TaskIssue $config $project $issue $stateRoot
            }
            catch {
                Write-RunnerLog "Issue #$($issue.number) failed: $($_.Exception.Message)" 'ERROR'
            }
        }
    }
}
finally {
    if ($hasMutex) { $mutex.ReleaseMutex() | Out-Null }
    $mutex.Dispose()
}

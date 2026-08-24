[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'),
    [switch]$Preflight,
    [switch]$Once
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Native {
    param([string]$Exe, [string[]]$Args = @(), [string]$Cwd = $null)
    $old = Get-Location
    try {
        if ($Cwd) { Set-Location -LiteralPath $Cwd }
        $out = & $Exe @Args 2>&1 | Out-String
        $code = $LASTEXITCODE
        [pscustomobject]@{ Code = $code; Out = $out.TrimEnd() }
    }
    finally {
        Set-Location -LiteralPath $old
    }
}

function Need {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing required command: $Name"
    }
}

function ExpandPath {
    param([string]$Value)
    [Environment]::ExpandEnvironmentVariables($Value)
}

function Log {
    param([string]$Text, [string]$Kind = 'INFO', [string]$File = $null)
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Kind, $Text
    Write-Host $line
    if ($File) { Add-Content -LiteralPath $File -Value $line -Encoding UTF8 }
}

function LoadConfig {
    param([string]$Path)
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $cfg = Get-Content -LiteralPath $resolved -Raw -Encoding UTF8 | ConvertFrom-Json
    $cfg.log_root = ExpandPath ([string]$cfg.log_root)
    $cfg
}

function CheckProject {
    param($Project)
    $Project.worktree = ExpandPath ([string]$Project.worktree)
    if (-not (Test-Path -LiteralPath $Project.worktree -PathType Container)) {
        throw "Worktree not found: $($Project.worktree)"
    }
    $inside = Native 'git' @('-C', [string]$Project.worktree, 'rev-parse', '--is-inside-work-tree')
    if ($inside.Code -ne 0 -or $inside.Out.Trim() -ne 'true') {
        throw "Not a Git worktree: $($Project.worktree)"
    }
    $remote = Native 'git' @('-C', [string]$Project.worktree, 'remote', 'get-url', 'origin')
    if ($remote.Code -ne 0 -or $remote.Out -notmatch [regex]::Escape([string]$Project.repo)) {
        throw "Git origin mismatch for $($Project.name). Expected $($Project.repo), got $($remote.Out)"
    }
}

function Preflight {
    param($Config)
    Need 'git'; Need 'gh'; Need 'codex'; Need 'powershell.exe'
    $gh = Native 'gh' @('auth', 'status')
    if ($gh.Code -ne 0) { throw "gh auth failed: $($gh.Out)" }
    $cx = Native 'codex' @('--version')
    if ($cx.Code -ne 0) { throw "Codex unavailable: $($cx.Out)" }
    foreach ($p in $Config.projects) {
        CheckProject $p
        $php = if ($p.php_executable) { [string]$p.php_executable } else { 'php' }
        Need $php
    }
}

function ParseTask {
    param([string]$Body, [string]$Marker)
    if ($Body -notmatch [regex]::Escape($Marker)) { return $null }
    $m = [regex]::Match($Body, '(?s)```json\s*(.*?)\s*```')
    if (-not $m.Success) { throw 'Task JSON block not found.' }
    $m.Groups[1].Value | ConvertFrom-Json
}

function ValidateTask {
    param($Task, $Project)
    if ([int]$Task.schema_version -ne 1) { throw 'Unsupported task schema.' }
    if ([string]$Task.project -ne [string]$Project.name) { throw 'Task/project mismatch.' }
    if ([string]$Task.run_id -notmatch '^DEV-\d{8}-\d{3,}$') { throw 'Invalid run_id.' }
    $branch = [string]$Task.target_branch
    if ($branch -notmatch '^[A-Za-z0-9._/-]+$' -or $branch -match '\.\.' -or $branch.StartsWith('/') -or $branch.EndsWith('/')) {
        throw 'Unsafe target branch.'
    }
    $allowed = $false
    foreach ($prefix in $Project.allowed_branch_prefixes) {
        if ($branch.StartsWith([string]$prefix, [StringComparison]::Ordinal)) { $allowed = $true; break }
    }
    if (-not $allowed) { throw "Branch prefix not allowed: $branch" }
    if ([string]::IsNullOrWhiteSpace([string]$Task.objective)) { throw 'Task objective is empty.' }
}

function CommentIssue {
    param([string]$Repo, [int]$Number, [string]$Body)
    $tmp = [IO.Path]::GetTempFileName()
    try {
        Set-Content -LiteralPath $tmp -Value $Body -Encoding UTF8
        Native 'gh' @('issue', 'comment', [string]$Number, '--repo', $Repo, '--body-file', $tmp) | Out-Null
    }
    finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

function CloseIssue {
    param([string]$Repo, [int]$Number)
    Native 'gh' @('issue', 'close', [string]$Number, '--repo', $Repo) | Out-Null
}

function StatePath {
    param([string]$Root, [string]$Repo, [int]$Number)
    $safe = $Repo -replace '[^A-Za-z0-9._-]', '_'
    Join-Path $Root ("$safe-$Number.json")
}

function SaveState {
    param([string]$Path, $State)
    $State | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function PrepareRepo {
    param($Project, $Task, [bool]$Resume, [string]$LogFile)
    $wt = [string]$Project.worktree
    $branch = [string]$Task.target_branch

    if (-not $Resume) {
        $dirty = Native 'git' @('-C', $wt, 'status', '--porcelain')
        if ($dirty.Code -ne 0) { throw $dirty.Out }
        if (-not [string]::IsNullOrWhiteSpace($dirty.Out)) {
            throw 'Worktree has uncommitted changes; runner will not overwrite them.'
        }
    }

    $fetch = Native 'git' @('-C', $wt, 'fetch', 'origin', '--prune')
    Log $fetch.Out 'GIT' $LogFile
    if ($fetch.Code -ne 0) { throw 'git fetch failed.' }

    if ($Resume) {
        $cur = Native 'git' @('-C', $wt, 'branch', '--show-current')
        if ($cur.Code -ne 0 -or $cur.Out.Trim() -ne $branch) {
            throw "Resume expects $branch but current branch is $($cur.Out.Trim())."
        }
        return
    }

    $remoteBranch = Native 'git' @('-C', $wt, 'ls-remote', '--exit-code', '--heads', 'origin', $branch)
    if ($remoteBranch.Code -eq 0) {
        $co = Native 'git' @('-C', $wt, 'checkout', '-B', $branch, "origin/$branch")
    }
    else {
        $base = [string]$Project.base_branch
        $co = Native 'git' @('-C', $wt, 'checkout', '-B', $branch, "origin/$base")
    }
    Log $co.Out 'GIT' $LogFile
    if ($co.Code -ne 0) { throw 'git checkout failed.' }
}

function CodexPrompt {
    param($Task, $Project, [string]$Failure = '')
    $criteria = ''
    foreach ($x in $Task.acceptance_criteria) { $criteria += "- $x`n" }
    $p = @"
You are the local implementation worker for Z-Blog run $($Task.run_id).

Mandatory boundaries:
- Work only in the current Git worktree: $($Project.worktree)
- Inspect existing code before editing it.
- Do not modify Z-Blog zb_system core files outside this repository.
- Do not commit, push, merge, tag, release, edit GitHub issues, or deploy production. The PowerShell runner owns those actions.
- Do not modify production data.
- Complete normal in-scope development without asking the user for routine approval.
- Prefer Z-Blog native hooks/APIs and keep changes focused and maintainable.
- If the sandbox blocks an operation, continue what can be done and report the blocker instead of requesting interactive approval.

Objective:
$($Task.objective)

Acceptance criteria:
$criteria
"@
    if ($Failure) {
        if ($Failure.Length -gt 12000) { $Failure = $Failure.Substring($Failure.Length - 12000) }
        $p += @"

The previous automated validation or CI run failed. Fix the root cause using the real error output below, then leave the worktree ready for another validation pass.

Failure output:
$Failure
"@
    }
    $p
}

function RunCodex {
    param($Config, $Project, $Task, [string]$Failure, [string]$LogFile)
    $prompt = CodexPrompt $Task $Project $Failure
    Log "Codex start: $($Task.run_id)" 'CODEX' $LogFile
    $r = Native 'codex' @('exec', '--profile', [string]$Config.codex_profile, $prompt) ([string]$Project.worktree)
    Log $r.Out 'CODEX' $LogFile
    $r
}

function PhpLint {
    param($Project)
    if (-not [bool]$Project.tests.php_lint) { return [pscustomobject]@{ Ok=$true; Out='PHP lint skipped.' } }
    $php = if ($Project.php_executable) { [string]$Project.php_executable } else { 'php' }
    $ok = $true; $buf = New-Object System.Collections.Generic.List[string]
    $files = Get-ChildItem -LiteralPath $Project.worktree -Recurse -Filter '*.php' -File | Where-Object { $_.FullName -notmatch '[\\/]vendor[\\/]' }
    foreach ($f in $files) {
        $r = Native $php @('-l', $f.FullName)
        $buf.Add($r.Out)
        if ($r.Code -ne 0) { $ok = $false }
    }
    [pscustomobject]@{ Ok=$ok; Out=($buf -join "`n") }
}

function PhpUnit {
    param($Project)
    if (-not [bool]$Project.tests.phpunit) { return [pscustomobject]@{ Ok=$true; Out='PHPUnit skipped.' } }
    $exe = $null
    foreach ($p in @('vendor\bin\phpunit.bat','vendor\bin\phpunit.cmd','vendor\bin\phpunit')) {
        $candidate = Join-Path $Project.worktree $p
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $exe = $candidate; break }
    }
    if (-not $exe -and (Get-Command 'phpunit' -ErrorAction SilentlyContinue)) { $exe = 'phpunit' }
    if (-not $exe) {
        return [pscustomobject]@{ Ok=(-not [bool]$Project.tests.phpunit_required); Out='PHPUnit executable not found.' }
    }
    $r = Native $exe @() ([string]$Project.worktree)
    [pscustomobject]@{ Ok=($r.Code -eq 0); Out=$r.Out }
}

function TrustedTest {
    param($Project)
    $scriptValue = [string]$Project.tests.trusted_test_script
    if ([string]::IsNullOrWhiteSpace($scriptValue)) { return [pscustomobject]@{ Ok=$true; Out='Trusted test not configured.' } }
    $script = ExpandPath $scriptValue
    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
        return [pscustomobject]@{ Ok=(-not [bool]$Project.tests.trusted_test_script_required); Out="Trusted test not found: $script" }
    }
    $wt = [IO.Path]::GetFullPath([string]$Project.worktree).TrimEnd('\')
    $sp = [IO.Path]::GetFullPath($script)
    if ($sp.StartsWith($wt, [StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{ Ok=$false; Out='Trusted test must live outside the Codex-editable worktree.' }
    }
    $r = Native 'powershell.exe' @('-NoProfile','-ExecutionPolicy','Bypass','-File',$sp,'-Worktree',[string]$Project.worktree)
    [pscustomobject]@{ Ok=($r.Code -eq 0); Out=$r.Out }
}

function HttpSmoke {
    param($Project)
    if (-not [bool]$Project.tests.http_smoke) { return [pscustomobject]@{ Ok=$true; Out='HTTP smoke skipped.' } }
    try {
        $timeout = [int]$Project.tests.http_timeout_sec
        $r = Invoke-WebRequest -UseBasicParsing -Uri ([string]$Project.tests.site_url) -TimeoutSec $timeout
        $code = [int]$r.StatusCode
        [pscustomobject]@{ Ok=($code -ge 200 -and $code -lt 500); Out="HTTP $code $($Project.tests.site_url)" }
    }
    catch { [pscustomobject]@{ Ok=$false; Out=("HTTP smoke failed: " + $_.Exception.Message) } }
}

function ValidateLocal {
    param($Project, [string]$LogFile)
    $parts = New-Object System.Collections.Generic.List[string]; $ok = $true
    foreach ($pair in @(
        @{N='PHP LINT'; R=(PhpLint $Project)},
        @{N='PHPUNIT'; R=(PhpUnit $Project)},
        @{N='TRUSTED TEST'; R=(TrustedTest $Project)},
        @{N='HTTP SMOKE'; R=(HttpSmoke $Project)}
    )) {
        $parts.Add("=== $($pair.N) ===`n$($pair.R.Out)")
        if (-not $pair.R.Ok) { $ok = $false }
    }
    $out = $parts -join "`n`n"
    Log $out 'TEST' $LogFile
    [pscustomobject]@{ Ok=$ok; Out=$out }
}

function CommitPush {
    param($Project, $Task, [bool]$Wip, [string]$LogFile)
    $wt = [string]$Project.worktree
    $s = Native 'git' @('-C',$wt,'status','--porcelain')
    if ([string]::IsNullOrWhiteSpace($s.Out)) {
        $sha = Native 'git' @('-C',$wt,'rev-parse','HEAD')
        return [pscustomobject]@{ Ok=$true; Sha=$sha.Out.Trim(); Changed=$false; Out='No changes.' }
    }
    $a = Native 'git' @('-C',$wt,'add','-A'); if ($a.Code -ne 0) { return [pscustomobject]@{Ok=$false;Sha='';Changed=$true;Out=$a.Out} }
    $msg = if ($Wip) { "wip: $($Task.run_id) failed unattended validation" } else { [string]$Task.commit_message }
    if ([string]::IsNullOrWhiteSpace($msg)) { $msg = "feat: complete $($Task.run_id)" }
    $msg = ($msg -replace '[\r\n]+',' ').Trim(); if ($msg.Length -gt 160) { $msg = $msg.Substring(0,160) }
    $c = Native 'git' @('-C',$wt,'commit','-m',$msg); Log $c.Out 'GIT' $LogFile
    if ($c.Code -ne 0) { return [pscustomobject]@{Ok=$false;Sha='';Changed=$true;Out=$c.Out} }
    $sha = (Native 'git' @('-C',$wt,'rev-parse','HEAD')).Out.Trim()
    if (-not [bool]$Task.auto_push) { return [pscustomobject]@{Ok=$true;Sha=$sha;Changed=$true;Out='Push disabled.'} }
    $p = Native 'git' @('-C',$wt,'push','-u','origin',[string]$Task.target_branch); Log $p.Out 'GIT' $LogFile
    [pscustomobject]@{ Ok=($p.Code -eq 0); Sha=$sha; Changed=$true; Out=$p.Out }
}

function WaitCI {
    param($Project, [string]$Sha, [string]$LogFile)
    if (-not [bool]$Project.ci.enabled) { return [pscustomobject]@{Ok=$true;Out='CI disabled.';Failed=''} }
    $repo=[string]$Project.repo; $wt=[string]$Project.worktree
    $branch=(Native 'git' @('-C',$wt,'branch','--show-current')).Out.Trim()
    $poll=[int]$Project.ci.poll_interval_sec; $discover=(Get-Date).AddSeconds([int]$Project.ci.discovery_timeout_sec)
    $runs=@()
    while ((Get-Date) -lt $discover) {
        $q=Native 'gh' @('run','list','--repo',$repo,'--branch',$branch,'--limit','20','--json','databaseId,status,conclusion,headSha,workflowName,url')
        if ($q.Code -eq 0 -and $q.Out) {
            $all=@($q.Out | ConvertFrom-Json); $runs=@($all | Where-Object { [string]$_.headSha -eq $Sha })
            if ($runs.Count -gt 0) { break }
        }
        Start-Sleep -Seconds $poll
    }
    if ($runs.Count -eq 0) {
        $required=[bool]$Project.ci.required
        return [pscustomobject]@{Ok=(-not $required);Out="No CI run found for $Sha.";Failed=''}
    }
    $deadline=(Get-Date).AddSeconds([int]$Project.ci.completion_timeout_sec)
    while ((Get-Date) -lt $deadline) {
        $q=Native 'gh' @('run','list','--repo',$repo,'--branch',$branch,'--limit','20','--json','databaseId,status,conclusion,headSha,workflowName,url')
        if ($q.Code -eq 0) {
            $all=@($q.Out | ConvertFrom-Json); $runs=@($all | Where-Object { [string]$_.headSha -eq $Sha })
            if ($runs.Count -gt 0 -and @($runs | Where-Object { [string]$_.status -ne 'completed' }).Count -eq 0) { break }
        }
        Start-Sleep -Seconds $poll
    }
    if (@($runs | Where-Object { [string]$_.status -ne 'completed' }).Count -gt 0) {
        return [pscustomobject]@{Ok=$false;Out='CI completion timeout.';Failed=''}
    }
    $bad=@($runs | Where-Object { [string]$_.conclusion -notin @('success','skipped','neutral') })
    $summary=($runs | ForEach-Object { "[$($_.conclusion)] $($_.workflowName) $($_.url)" }) -join "`n"; Log $summary 'CI' $LogFile
    if ($bad.Count -eq 0) { return [pscustomobject]@{Ok=$true;Out=$summary;Failed=''} }
    $buf=New-Object System.Collections.Generic.List[string]
    foreach ($r in $bad) { $x=Native 'gh' @('run','view',[string]$r.databaseId,'--repo',$repo,'--log-failed'); $buf.Add("$($r.workflowName):`n$($x.Out)") }
    [pscustomobject]@{Ok=$false;Out=$summary;Failed=($buf -join "`n`n")}
}

function ProcessIssue {
    param($Config,$Project,$Issue,[string]$StateRoot)
    $task=ParseTask ([string]$Issue.body) ([string]$Config.task_marker); if (-not $task) { return }
    ValidateTask $task $Project
    $num=[int]$Issue.number; $logDir=Join-Path $Config.log_root ([string]$task.run_id); New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $logFile=Join-Path $logDir ("issue-$num.log"); $sp=StatePath $StateRoot ([string]$Project.repo) $num; $resume=Test-Path -LiteralPath $sp
    if ($resume) { $state=Get-Content -LiteralPath $sp -Raw -Encoding UTF8 | ConvertFrom-Json }
    else {
        $state=[pscustomobject]@{run_id=[string]$task.run_id;branch=[string]$task.target_branch;local_attempt=0;ci_repair_attempt=0;status='claimed'}; SaveState $sp $state
        CommentIssue $Project.repo $num "[LOCAL-RUNNER][CLAIMED]`nRunner: $($Config.runner_id)`nRun: $($task.run_id)`nBranch: $($task.target_branch)"
    }
    try {
        PrepareRepo $Project $task $resume $logFile
        $failure=''; $passed=$false; $max=[int]$Config.max_local_attempts
        for($i=([int]$state.local_attempt+1);$i -le $max;$i++) {
            $state.local_attempt=$i; $state.status='codex'; SaveState $sp $state
            $cx=RunCodex $Config $Project $task $failure $logFile
            if($cx.Code -ne 0){$failure="Codex exit $($cx.Code):`n$($cx.Out)";continue}
            $state.status='local_validation';SaveState $sp $state;$v=ValidateLocal $Project $logFile
            if($v.Ok){$passed=$true;break};$failure=$v.Out
        }
        if(-not $passed){$w=CommitPush $Project $task $true $logFile;CommentIssue $Project.repo $num "[LOCAL-RUNNER][FAILED]`nRun: $($task.run_id)`nStage: local validation`nBranch: $($task.target_branch)`nCommit: $($w.Sha)`nLast error:`n$failure";CloseIssue $Project.repo $num;Remove-Item $sp -Force -ErrorAction SilentlyContinue;return}
        $g=CommitPush $Project $task $false $logFile;if(-not $g.Ok){throw "Commit/push failed: $($g.Out)"};$sha=$g.Sha
        $ci=$null;$maxCi=[int]$Project.ci.max_repair_attempts
        for($j=([int]$state.ci_repair_attempt);$j -le $maxCi;$j++){
            $state.ci_repair_attempt=$j;$state.status='ci_wait';SaveState $sp $state;$ci=WaitCI $Project $sha $logFile;if($ci.Ok){break};if($j -ge $maxCi){break}
            $state.status='ci_repair';SaveState $sp $state;$ctx=if($ci.Failed){$ci.Failed}else{$ci.Out};$cx=RunCodex $Config $Project $task $ctx $logFile;if($cx.Code -ne 0){continue};$v=ValidateLocal $Project $logFile;if(-not $v.Ok){continue};$g=CommitPush $Project $task $false $logFile;if(-not $g.Ok){throw "Repair push failed: $($g.Out)"};$sha=$g.Sha
        }
        if($ci -and -not $ci.Ok){CommentIssue $Project.repo $num "[LOCAL-RUNNER][FAILED]`nRun: $($task.run_id)`nStage: GitHub CI`nBranch: $($task.target_branch)`nCommit: $sha`nCI:`n$($ci.Out)";CloseIssue $Project.repo $num;Remove-Item $sp -Force -ErrorAction SilentlyContinue;return}
        CommentIssue $Project.repo $num "[LOCAL-RUNNER][SUCCESS]`nRun: $($task.run_id)`nProject: $($Project.name)`nBranch: $($task.target_branch)`nCommit: $sha`nLocal validation: PASS`nCI:`n$($ci.Out)";CloseIssue $Project.repo $num;Remove-Item $sp -Force -ErrorAction SilentlyContinue;Log "Completed $($task.run_id) $sha" 'DONE' $logFile
    }
    catch { Log $_.Exception.Message 'BLOCKED' $logFile; CommentIssue $Project.repo $num "[LOCAL-RUNNER][BLOCKED]`nRun: $($task.run_id)`n$($_.Exception.Message)`nLocal state retained for resume."; throw }
}

$mutex=New-Object System.Threading.Mutex($false,'Global\XinZhaoZBlogLocalRunnerV1');$locked=$false
try {
    $locked=$mutex.WaitOne(0);if(-not $locked){exit 0}
    $cfg=LoadConfig $ConfigPath;New-Item -ItemType Directory -Path $cfg.log_root -Force | Out-Null
    $stateRoot=Join-Path ([IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $ConfigPath).Path)) 'state';New-Item -ItemType Directory -Path $stateRoot -Force | Out-Null
    Preflight $cfg;if($Preflight){Write-Host 'Z-Blog Local Runner preflight: PASS';exit 0}
    foreach($project in $cfg.projects){CheckProject $project;$q=Native 'gh' @('issue','list','--repo',[string]$project.repo,'--state','open','--limit',[string]$cfg.poll_limit,'--json','number,title,body,url,createdAt');if($q.Code -ne 0){Log $q.Out 'ERROR';continue};if(-not $q.Out){continue};foreach($issue in @($q.Out|ConvertFrom-Json)){if([string]$issue.title -notlike (([string]$cfg.task_title_prefix)+'*')){continue};try{$t=ParseTask ([string]$issue.body) ([string]$cfg.task_marker);if($t -and [string]$t.project -eq [string]$project.name){ProcessIssue $cfg $project $issue $stateRoot}}catch{Log "Issue #$($issue.number): $($_.Exception.Message)" 'ERROR'}}}
}
finally{if($locked){$mutex.ReleaseMutex()|Out-Null};$mutex.Dispose()}

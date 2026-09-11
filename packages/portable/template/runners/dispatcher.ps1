param([string]$Root = (Split-Path $PSScriptRoot -Parent), [switch]$TestMode, [switch]$IgnoreHours, [string]$RetryId, [string]$RetryReason, [switch]$PrepareRetryOnly)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'telemetry.ps1')
. (Join-Path $PSScriptRoot 'process-runtime.ps1')
function Read-Utf8([string]$Path) { return [IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8) }
$Root = [IO.Path]::GetFullPath($Root)
$cfg = Read-Utf8 (Join-Path $Root 'runners/dispatcher.json') | ConvertFrom-Json
if($cfg.codex_wsl_distribution -or $cfg.codex_wsl_user -or $cfg.ollama -or $cfg.git_checkpoint_script -or $cfg.health_script){throw 'This portable edition supports native Codex and Claude only; WSL, Ollama, relay and local observer integrations are not installed.'}
if ($env:COMPUTERNAME -ne $cfg.host -and !$TestMode) { throw 'This computer is not the designated dispatcher.' }
[IO.Directory]::CreateDirectory((Join-Path $Root 'state')) | Out-Null
$observerLog=Join-Path $Root 'state/observer.log'
function ConvertTo-NativeArgument([string]$Argument) {
    if ([string]::IsNullOrEmpty($Argument)) { return '""' }
    if ($Argument -notmatch '[\s"]') { return $Argument }
    $escaped = $Argument -replace '(\\*)"', '$1$1\"';$escaped = $escaped -replace '(\\+)$', '$1$1'
    return '"' + $escaped + '"'
}
try { $dispatchLock=[IO.File]::Open((Join-Path $Root 'state/dispatcher.lock'),'OpenOrCreate','ReadWrite','None') } catch [IO.IOException] { return }
$mutex = New-Object Threading.Mutex($false, ('Local\AgentOS-' + $cfg.host));$taskTouched=$false;$touched=[Collections.Generic.List[object]]::new()
try { $acquired=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $acquired=$true }; if (!$acquired) { $mutex.Dispose(); $dispatchLock.Dispose(); return }
function Save-Json($Path, $Value, [switch]$SkipLedger) {
    if (!$SkipLedger -and $script:runLedger -and [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($Path)) -eq [IO.Path]::GetFullPath((Join-Path $Root "work/status"))) { Save-LedgerStatus ([IO.Path]::GetFileNameWithoutExtension($Path)) $Value }
    $temp = "$Path.tmp"
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temp -Encoding UTF8
    Move-Item -LiteralPath $temp -Destination $Path -Force
}
. (Join-Path $PSScriptRoot "run-ledger.ps1")
function Get-RunVerdict([string]$OutDir,[string]$Stage,[string]$Id,[string]$Nonce,[string]$ResultPath) {
    # The verdict is nonce-bound so narrative prose can never assert it and a verdict from
    # another run or another stage can never be mistaken for this one. A missing signal is not a pass.
    $verdictPath = Join-Path $OutDir "$Stage-verdict.json"
    if (Test-Path $verdictPath) {
        try { $v = Read-Utf8 $verdictPath | ConvertFrom-Json } catch { return [pscustomobject]@{verdict='NEEDS_ATTENTION';source='verdict-file';note='Verdict file is not readable JSON.'} }
        if ([string]$v.nonce -cne $Nonce) { return [pscustomobject]@{verdict='NEEDS_ATTENTION';source='verdict-file';note='Verdict file nonce does not match this run. Stale or copied verdict rejected.'} }
        if ([string]$v.id -cne $Id) { return [pscustomobject]@{verdict='NEEDS_ATTENTION';source='verdict-file';note='Verdict file id does not match this work order.'} }
        if ([string]$v.stage -cne $Stage) { return [pscustomobject]@{verdict='NEEDS_ATTENTION';source='verdict-file';note='Verdict file stage does not match this run stage.'} }
        if ([string]$v.verdict -ceq 'PASS') { return [pscustomobject]@{verdict='PASS';source='verdict-file';note=''} }
        if ([string]$v.verdict -ceq 'NEEDS_ATTENTION') { return [pscustomobject]@{verdict='NEEDS_ATTENTION';source='verdict-file';note='Agent reported NEEDS_ATTENTION in its verdict file.'} }
        return [pscustomobject]@{verdict='NEEDS_ATTENTION';source='verdict-file';note='Verdict file value is not exactly PASS or NEEDS_ATTENTION.'}
    }
    $pattern = '^AGENTOS-VERDICT (PASS|NEEDS_ATTENTION) ' + [regex]::Escape($Nonce) + '$'
    foreach ($line in ((Read-Utf8 $ResultPath) -split "\r?\n")) {
        if ($line.Trim() -cmatch $pattern) {
            if ($Matches[1] -ceq 'PASS') { return [pscustomobject]@{verdict='PASS';source='signed-line';note=''} }
            return [pscustomobject]@{verdict='NEEDS_ATTENTION';source='signed-line';note='Agent reported NEEDS_ATTENTION.'}
        }
    }
    return [pscustomobject]@{verdict='NEEDS_ATTENTION';source='none';note='No verdict file and no signed verdict line carrying this run nonce. Completion signal missing; inspect the result before retrying.'}
}
try {
    foreach ($d in @('work/inbox','work/status','work/results','work/receipts')) { New-Item -ItemType Directory -Path (Join-Path $Root $d) -Force | Out-Null }
    Initialize-RunLedger
    if ($RetryId) {
        if ((Get-LedgerRecord $RetryId).retired) { throw 'Retired IDs cannot be retried; use a new linked ID.' }
        Restore-LedgerStatus $RetryId (Join-Path $Root "work/inbox/$RetryId.json") (Join-Path $Root "work/status/$RetryId.json")
        $taskTouched=$true
        $touched.Add([pscustomobject]@{id=$RetryId;stage='manual'})
        if ($RetryId -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}$' -or [string]::IsNullOrWhiteSpace($RetryReason)) { throw 'Retry requires a valid ID and non-empty reason.' }
        $retryStatusPath=Join-Path $Root "work/status/$RetryId.json"
        if (!(Test-Path $retryStatusPath)) { throw 'Retry status does not exist.' }
        $retryStatus=Read-Utf8 $retryStatusPath|ConvertFrom-Json
        if ($retryStatus.state -eq 'completed') { throw 'Completed work cannot be retried.' }
        if ($retryStatus.state -notin @('blocked','needs_attention')) { throw 'Only blocked or needs_attention work can be retried.' }
        $stamp=[DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ');$archive=Join-Path $Root "work/retry-archive/$RetryId/$stamp";New-Item -ItemType Directory $archive -Force|Out-Null
        $results=Join-Path $Root "work/results/$RetryId";if(Test-Path $results){Move-Item $results (Join-Path $archive 'results')}
        Copy-Item $retryStatusPath (Join-Path $archive 'status.json')
        $retryReceipt=Join-Path $Root "work/receipts/$RetryId.json";if(Test-Path $retryReceipt){Copy-Item $retryReceipt (Join-Path $archive 'receipt.json')}
        $retryStatus.state='pending';$retryStatus|Add-Member -NotePropertyName note -NotePropertyValue "Retry prepared: $RetryReason. Prior diagnostics: work/retry-archive/$RetryId/$stamp" -Force;$retryStatus|Add-Member -NotePropertyName updated_at -NotePropertyValue ([DateTime]::UtcNow.ToString('o')) -Force;Save-Json $retryStatusPath $retryStatus;Save-Json $retryReceipt $retryStatus
        if ($PrepareRetryOnly) { return }
    }
    # Dispatch is available every day, at every hour. IgnoreHours remains for compatibility.
    # An unconfirmed process cleanup must not overlap subsequent model launches.
    if (!$TestMode -and (Test-Path (Join-Path $Root 'state/runtime-quarantine.json'))) { return }
    foreach ($file in Get-ChildItem (Join-Path $Root 'work/inbox') -Filter '*.json' | Sort-Object Name) {
        if (((Get-Date).ToUniversalTime() - $file.LastWriteTimeUtc).TotalSeconds -lt $cfg.settle_seconds) { continue }
        $id = $file.BaseName
        if ($id -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}$') { continue }
        $statusPath = Join-Path $Root "work/status/$id.json"
        try { Restore-LedgerStatus $id $file.FullName $statusPath } catch {
            New-Item -ItemType Directory (Join-Path $Root 'state/alerts') -Force|Out-Null
            Save-Json (Join-Path $Root "state/alerts/ledger-$id.json") @{id=$id;error=$_.Exception.Message;at=[DateTime]::UtcNow.ToString('o')} -SkipLedger
            continue
        }
        $s = $null
        if (Test-Path $statusPath) {
            $s = Read-Utf8 $statusPath | ConvertFrom-Json
            if ($s.state -in @('completed','needs_attention','blocked')) { continue }
            if ($s.state -eq 'running') {
                $s.state = 'needs_attention'; $s.note = 'Previous dispatcher stopped during a run. Inspect output before retrying; no automatic replay.'
                Save-Json $statusPath $s; continue
            }
        }
        try {
            $taskTouched=$true
            $runStarted=$false
            $task = Read-Utf8 $file.FullName | ConvertFrom-Json
            if ($task.relay_source -or $task.owner -eq 'ollama') { throw 'Portable dispatcher supports ordinary Codex and Claude work orders only.' }
            if ($task.id -ne $id -or $task.owner -notin @('codex','claude') -or $task.status -ne 'ready' -or !$task.objective -or !$task.acceptance) { throw 'Invalid work order: require matching id, owner codex/claude, status ready, objective and acceptance.' }
            if (!$TestMode -and (!$task.authorization -or !$task.task_id -or !$task.assigned_revision)) { throw 'Work order requires authorization, task_id and assigned_revision before launch.' }
            $budget = Get-EffectiveBudget $task $cfg $task.owner
            if (!$s) { $s = [pscustomobject]@{id=$id; state='pending'; stage='execute'; owner=$task.owner; updated_at=''; note=''} }
            $touched.Add([pscustomobject]@{id=$id;stage=[string]$s.stage})
            $agent = $task.owner
            if ($s.stage -eq 'review') { if ($agent -eq 'codex') { $agent = 'claude' } else { $agent = 'codex' } }
            $budget = Get-EffectiveBudget $task $cfg $agent
            $runStarted = $false
            $command = $cfg.$agent
            if (!$TestMode -and ($env:OPENAI_API_KEY -or $env:CODEX_API_KEY -or $env:ANTHROPIC_API_KEY)) { throw 'API-key environment detected. Dispatcher requires subscription-only login; no model launched.' }
            if (!$TestMode -and !(Get-Command $command -ErrorAction SilentlyContinue)) { throw "$agent command unavailable. Install/sign in, inspect the blocked attempt, and publish a new linked ID." }
            $outDir = Join-Path $Root "work/results/$id"
            New-Item -ItemType Directory $outDir -Force | Out-Null
            if ($s.stage -eq 'review' -and !(Test-Path (Join-Path $outDir 'execute.txt'))) { throw 'Producer output missing; inspect archived evidence. No execution replay or empty review permitted.' }
            $result = Join-Path $outDir "$($s.stage).txt"
            $verdictNonce = [Guid]::NewGuid().ToString()
            $s.state = 'running'; $s.updated_at = [DateTime]::UtcNow.ToString('o'); Save-Json $statusPath $s
            $prompt = @"
You are $agent, executing a delegated AgentOS assignment for the workspace principal. Read AGENTS.md and TEAM.md, then runners/README.md for the automated ownership contract.
Read only the task packet and relevant linked evidence. The work order is the accepted automated assignment; do not edit the coordinator task packet. Every file you read stays in context for the rest of the run. Never send email. Fulfill the delegated outcome with reasonable judgment.
This work order is the assignment, not permission to redesign the operating system.
Do not modify runners, inbox, status or receipts. Put deliverables in work/results/$id/.
Stage: $($s.stage)
Work order:
$($task | ConvertTo-Json -Depth 8)
For execute: complete the assignment, then state what was done, evidence and blockers.
For review: read work/results/$id/execute.txt and its deliverables. Check acceptance criteria independently.
For execution telemetry use execute-runtime.json. Do not read raw *-stderr.txt or *-stdout.txt unless the summary is missing or inconsistent; record why and retrieve only the necessary excerpt. Unknown counts are not zero and do not justify a full log read. Telemetry does not prove that no external action occurred.
Effective budget: $($budget | ConvertTo-Json -Compress). Source limits count distinct documents relied on; search limits count provider requests. Source/search limits and Codex turn limits are advisory. Stop and report NEEDS_ATTENTION if required evidence cannot fit; never silently weaken acceptance.
State deliverable paths, verification, and any remaining decisions. Never claim success for blocked work.
Completion signal (required, do both). This run is recorded from the signal below, not from your prose. Use PASS only when the assignment is satisfied.
1. Write work/results/$id/$($s.stage)-verdict.json containing exactly: {"id":"$id","stage":"$($s.stage)","verdict":"PASS","nonce":"$verdictNonce"} with verdict set to PASS or NEEDS_ATTENTION.
2. End your reply with one line and nothing after it: AGENTOS-VERDICT PASS $verdictNonce
Substitute NEEDS_ATTENTION for PASS in both places if the assignment is not satisfied. The nonce is unique to this run; copy it exactly, never invent or reuse one.
Omitting both signals records this run as needs_attention no matter what work you completed.
"@
            if ($TestMode) { "Simulated $($s.stage) for dispatcher testing only.`nAGENTOS-VERDICT PASS $verdictNonce" | Set-Content $result; $exitCode = 0 }
            else {
                $inputPath = Join-Path $outDir "$($s.stage)-prompt.txt"
                $prompt | Set-Content $inputPath -Encoding UTF8
                $stdout = Join-Path $outDir "$($s.stage)-stdout.txt"
                $stderr = Join-Path $outDir "$($s.stage)-stderr.txt"
                if ($agent -eq 'codex') { $arguments = @('exec','--skip-git-repo-check','--sandbox','workspace-write','--cd',$Root,'--add-dir',$outDir,'--output-last-message',$result,'-') }
                else { $arguments = @('-p','--permission-mode','acceptEdits','--permission-prompts','none','--strict-mcp-config','--tools','Read,Write,Edit,Glob,Grep,Bash,WebSearch,WebFetch','--allowedTools','WebSearch,WebFetch,Bash','--output-format','json') }
                if($agent -eq 'claude' -and $null -ne $budget.max_turns){$arguments += @('--max-turns',[string]$budget.max_turns)}
                $sw = [Diagnostics.Stopwatch]::StartNew()
                # Start-Process can expose a null ExitCode in background/scheduled Windows
                # PowerShell sessions. Use Process directly and drain both streams
                # asynchronously so completion and exit status are deterministic.
                $psi = New-Object Diagnostics.ProcessStartInfo
                $psi.FileName = $command
                $psi.Arguments = (($arguments | ForEach-Object { ConvertTo-NativeArgument ([string]$_) }) -join ' ')
                $psi.WorkingDirectory = $Root
                $psi.UseShellExecute = $false
                # PowerShell 7 startup telemetry hangs in the restricted Windows sandbox on this host.
                # Opt out only for this runner and its children; keep sandbox permissions unchanged.
                $psi.EnvironmentVariables['POWERSHELL_TELEMETRY_OPTOUT'] = '1'
                $psi.EnvironmentVariables['PATH'] = $env:PATH
                $psi.CreateNoWindow = $true
                $psi.RedirectStandardInput = $true
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
                $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
                $processTimeoutMs=[int]$cfg.timeout_minutes*60000
                $runStarted = $true
                $hostResult = Invoke-AgentProcess -ProcessStartInfo $psi -InputText ([IO.File]::ReadAllText($inputPath,[Text.Encoding]::UTF8)) -TimeoutMilliseconds $processTimeoutMs -StdoutPath $stdout -StderrPath $stderr
                $exitCode = $hostResult.exit_code
                if($hostResult.cleanup_status -eq 'unconfirmed'){
                    Save-Json (Join-Path $Root 'state/runtime-quarantine.json') ([pscustomobject]@{id=$id;stage=$s.stage;run_id=$verdictNonce;recorded_at=[DateTime]::UtcNow.ToString('o');reason='Process cleanup unconfirmed. Inspect owned processes before clearing this quarantine.'})
                }
                $sw.Stop()
                $terminal = [pscustomobject]@{payload=$null;failure_reason=$null}
                $costUsd = ''; $usageNote = [string]$hostResult.failure_reason
                if ($agent -eq 'claude') {
                    $terminal = Get-ClaudeTerminal $stdout
                    $payload = $terminal.payload
                    if($null -ne $payload.result){Set-Content -LiteralPath $result -Value $payload.result -Encoding UTF8}
                    if($null -ne $payload.total_cost_usd){$costUsd=[string]$payload.total_cost_usd}
                    if($null -ne $payload.usage){$u=$payload.usage;$usageNote += " in=$($u.input_tokens) out=$($u.output_tokens) cache_r=$($u.cache_read_input_tokens) cache_w=$($u.cache_creation_input_tokens)"}
                    if($terminal.failure_reason){$usageNote += " $($terminal.failure_reason)"}
                }
                $runtime = Write-AgentRuntime -Root $Root -OutDir $outDir -Stage $s.stage -Id $id -Agent $agent -Nonce $verdictNonce -HostResult $hostResult -Budget $budget -OrderPath $file.FullName -Terminal $terminal
                # state/costs.csv header is fixed: run_at,team,job,duration_s,est_cost_usd,exit_code,note
                $costRow = ('{0},{1},{2},{3},{4},{5},"{6}"' -f `
                    [DateTime]::UtcNow.ToString('o'), $agent, "$id`:$($s.stage)", `
                    [int]$sw.Elapsed.TotalSeconds, $costUsd, $exitCode, ($usageNote -replace '"','""'))
                Write-CostRow -CostPath (Join-Path $Root 'state/costs.csv') -OutDir $outDir -Stage $s.stage -Row $costRow
            }
            if (!$TestMode) {
                if($hostResult.failure_reason -or $null -eq $exitCode -or $terminal.failure_reason){throw "Run incomplete: host=$($hostResult.failure_reason); provider=$($terminal.failure_reason). Inspect runtime summary; no automatic replay."}
                if($runtime.wrapper -and ($runtime.wrapper.parse_error -or $runtime.wrapper.children_retired -isnot [bool] -or $runtime.wrapper.children_retired -ne $true -or $runtime.wrapper.reason -cne 'completed' -or $runtime.wrapper.runtime -cne 'wsl-ubuntu-24.04' -or $runtime.wrapper.exit_code -isnot [int] -or $runtime.wrapper.exit_code -ne $exitCode)){throw 'WSL cleanup or completion is unconfirmed. Inspect runtime summary.'}
            }
            if ($exitCode -ne 0 -or !(Test-Path $result)) { throw "Runner failed (exit $exitCode). See work/results/$id logs; login or permissions may need attention." }
            $verdict = Get-RunVerdict $outDir ([string]$s.stage) $id $verdictNonce $result
            if ($verdict.verdict -cne 'PASS') { $s.state = 'needs_attention'; $s.note = $verdict.note }
            elseif ($s.stage -eq 'execute') { $s.stage = 'review'; $s.state = 'pending'; $s.note = "Execution finished; independent review queued. Verdict source: $($verdict.source)." }
            else { $s.state = 'completed'; $s.note = "Execution and independent review passed. Verdict source: $($verdict.source)." }
            $s.updated_at = [DateTime]::UtcNow.ToString('o')
            Save-Json $statusPath $s
            Save-Json (Join-Path $Root "work/receipts/$id.json") $s
            if ($s.state -eq 'completed') { Publish-DeliveryHandoff $id }
        } catch {
            $errorStatus = [pscustomobject]@{id=$id;state=$(if($runStarted){'needs_attention'}else{'blocked'});stage=$(if($s){$s.stage}else{'execute'});owner=$(if($s){$s.owner}else{''});updated_at=[DateTime]::UtcNow.ToString('o');note=$_.Exception.Message}
            Save-Json $statusPath $errorStatus
            Save-Json (Join-Path $Root "work/receipts/$id.json") $errorStatus
            if (!$TestMode -and (Test-Path (Join-Path $Root 'state/runtime-quarantine.json'))) { break }
        }
    }
} finally {
    $mutex.ReleaseMutex();$mutex.Dispose();$dispatchLock.Dispose()

}

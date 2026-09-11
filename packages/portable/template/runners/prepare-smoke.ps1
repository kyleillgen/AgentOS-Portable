#requires -Version 5.1
param(
    [string]$Root=(Split-Path $PSScriptRoot -Parent),
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Principal,
    [switch]$AuthorizeLocalGreeting
)
$ErrorActionPreference='Stop'
if(!$AuthorizeLocalGreeting) { throw 'Use -AuthorizeLocalGreeting to authorize one local greeting and independent review. No order has been published.' }
if($Principal -match '[\r\n]' -or $Principal.Trim() -eq 'TODO') { throw 'Supply the principal name recorded in TEAM.md.' }
$Root=[IO.Path]::GetFullPath($Root)
$team=[IO.File]::ReadAllText((Join-Path $Root 'TEAM.md'))
if($team -notmatch ('(?m)^Principal:\s*'+[regex]::Escape($Principal.Trim())+'\s*$')) { throw 'First set Principal in TEAM.md to this name and fill in the team access and boundaries.' }
$cfg=Get-Content -LiteralPath (Join-Path $Root 'runners/dispatcher.json') -Raw|ConvertFrom-Json
if($cfg.host -ne $env:COMPUTERNAME -or !$cfg.run_ledger) { throw 'Run setup on this computer first.' }
$id='smoke-'+[DateTime]::UtcNow.ToString('yyyyMMddHHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
$taskDir=Join-Path $Root ('tasks/'+$id)
$null=New-Item -ItemType Directory -Path $taskDir -ErrorAction Stop
$utc=[DateTime]::UtcNow.ToString('o')
$order=[ordered]@{id=$id;status='ready';owner='codex';project_id='onboarding';task_id=$id;assigned_revision=2;authorization="$Principal authorizes one local greeting file and independent review. No external actions, purchases or email.";objective="Write work/results/$id/greeting.txt containing exactly Hello, team! and one trailing newline.";acceptance='Reviewer independently checks the greeting text and trailing newline, leaving producer files unchanged. Report evidence and blockers.';budget=@{max_turns=8}}
$utf8=[Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $taskDir 'order.json'),($order|ConvertTo-Json -Depth 5),$utf8)
$packet=@"
# First-run greeting
Protocol: 1
ID: $id
Project: onboarding
State: accepted
Revision: 3
Assigned revision: 2
Created at (UTC): $utc
Coordinator: $Principal (human)
Producer: codex
Reviewer: claude
Previous task: none (independent first-run check)

## Objective
$($order.objective)
## Acceptance criteria
$($order.acceptance)
## Authorization
$($order.authorization)
Budget: one execution and one independent review; no automatic retry.
## Context and inputs
Only this packet and the specified greeting. No external input is required.
## Expected artifacts and delivery
work/results/$id/greeting.txt; show it to $Principal after review passes.
## History
1. $utc intake: human requested the local check.
2. $utc assigned: Codex produces; Claude independently reviews revision 2.
3. $utc accepted: human coordinator records acceptance on the producer's behalf; live access remains unverified until the attempt.
"@
[IO.File]::WriteAllText((Join-Path $taskDir 'task.md'),$packet,$utf8)
[IO.File]::WriteAllText((Join-Path $taskDir 'acceptance.md'),"Task: $id`nAssigned revision: 2`nDecision: accepted by $Principal as human coordinator on behalf of Codex, for the stated greeting only.`nLive provider access: not tested.`nUTC: $utc`n",$utf8)
Write-Output "Prepared $id. No models launched; no order published."
Write-Output "Read tasks/$id/task.md, then publish:"
Write-Output "powershell -NoProfile -ExecutionPolicy Bypass -File .\runners\publish-order.ps1 -OrderPath .\tasks\$id\order.json"
Write-Output 'Then run .\runners\monitor.ps1 in the foreground. Use runners/doctor.ps1 to inspect status. Deliver the reviewed greeting and record closure separately.'

#requires -Version 5.1
param([string]$Root=(Split-Path $PSScriptRoot -Parent),[switch]$Json)
$ErrorActionPreference='Stop'
$checks=New-Object 'Collections.Generic.List[object]'
function Check([string]$Name,[string]$Status,[string]$Detail) {
    $checks.Add([pscustomobject]@{check=$Name;status=$Status;detail=$Detail})
}
try {
    $Root=[IO.Path]::GetFullPath($Root)
    $cfg=Get-Content -LiteralPath (Join-Path $Root 'runners/dispatcher.json') -Raw|ConvertFrom-Json
    if($cfg.host -eq 'CONFIGURE_WITH_SETUP') { Check 'configuration' 'FAIL' 'Run runners/setup.ps1 with your CLI paths and a new external ledger.' }
    elseif($cfg.host -ne $env:COMPUTERNAME) { Check 'host' 'FAIL' 'Configured for a different computer. Do not move a configured workspace or reuse its ledger.' }
    else { Check 'host' 'PASS' 'This is the designated computer.' }
    foreach($provider in @('codex','claude')) {
        $binary=[string]$cfg.$provider
        if([IO.Path]::IsPathRooted($binary) -and [IO.Path]::GetExtension($binary) -ieq '.exe' -and (Test-Path -LiteralPath $binary -PathType Leaf)) {
            Check $provider 'PASS' 'Configured executable exists. Version, login and CLI compatibility require a live check.'
        } else { Check $provider 'FAIL' 'Configured executable is missing or is a shim. Check the path after CLI upgrades.' }
    }
    $ledger=$null
    try {
        if(!$cfg.run_ledger){throw 'missing'}
        $ledger=Get-Content -LiteralPath (Join-Path $cfg.run_ledger 'ledger.json') -Raw|ConvertFrom-Json
        if($ledger.schema -ne 1 -or [IO.Path]::GetFullPath([string]$ledger.root) -ne $Root -or $ledger.orders -isnot [pscustomobject]) {throw 'invalid'}
        Check 'ledger' 'PASS' 'Ledger header matches this workspace. Dispatcher validates all records before running.'
    } catch { Check 'ledger' 'FAIL' 'Ledger missing, unreadable or mismatched. For an existing installation restore a verified backup; never create an empty replacement.' }
    if($cfg.timeout_minutes -isnot [int] -or $cfg.timeout_minutes -lt 1 -or $cfg.timeout_minutes -gt 1440 -or $cfg.settle_seconds -lt 0) {
        Check 'timing' 'FAIL' 'Use an integer timeout_minutes from 1 to 1440 and nonnegative settle_seconds.'
    } else { Check 'timing' 'PASS' 'Attempt timeout and settling period are configured.' }
    if($env:OPENAI_API_KEY -or $env:CODEX_API_KEY -or $env:ANTHROPIC_API_KEY) { Check 'authentication' 'FAIL' 'API-key environment detected. Use a separate subscription-login terminal; no key values were read into this report.' }
    else { Check 'authentication' 'NOT_TESTED' 'No API-key environment detected. Sign in to both CLIs locally; this does not verify account access.' }
    if(Get-Command git -ErrorAction SilentlyContinue) { Check 'git' 'PASS' 'Git is available on PATH.' }
    else { Check 'git' 'WARN' 'Git was not found on PATH. Install Git for Windows and reopen PowerShell before CLI testing.' }
    if(Test-Path -LiteralPath (Join-Path $Root 'state/runtime-quarantine.json')) { Check 'runtime' 'FAIL' 'Runtime quarantined after uncertain process cleanup. Inspect the incident before any new model run.' }
    elseif(Test-Path -LiteralPath (Join-Path $Root 'state/monitor.stop')) { Check 'runtime' 'WARN' 'Graceful stop requested. Remove state/monitor.stop only when you intend to resume.' }
    else { Check 'runtime' 'PASS' 'No stop marker or quarantine. This does not prove a monitor is running.' }
    $attention=0;$complete=0;$pending=0
    if($ledger) { foreach($entry in $ledger.orders.PSObject.Properties) {
        switch($entry.Value.status.state) { 'completed' {$complete++} {$_ -in @('blocked','needs_attention')} {$attention++} default {$pending++} }
    } }
    Check 'orders' $(if($attention){'WARN'}else{'PASS'}) "$complete completed; $pending pending/running; $attention need attention. Completed is not proof of delivery."
} catch { Check 'configuration' 'FAIL' 'Could not inspect configuration. Extract a complete package and check that dispatcher.json is valid JSON.' }
Check 'live verification' 'NOT_TESTED' 'This read-only check launches no models and tests no scheduled task. Run the greeting workflow to verify execution and review.'
$failed=@($checks|Where-Object status -eq 'FAIL').Count
if($Json) { [pscustomobject]@{schema=1;ok=($failed -eq 0);checks=@($checks.ToArray())}|ConvertTo-Json -Depth 5 }
else { $checks|Format-Table -AutoSize -Wrap; Write-Output 'No credentials, prompts, usernames or configured paths are included. Review any report before sharing.' }
if($failed){exit 1}

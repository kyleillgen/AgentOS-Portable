$ErrorActionPreference = 'Stop'
$monitorPath = Join-Path $PSScriptRoot 'monitor.ps1'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('agentos-monitor-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory "$testRoot/runners","$testRoot/work/inbox","$testRoot/work/status","$testRoot/state" -Force | Out-Null
@{settle_seconds=1} | ConvertTo-Json | Set-Content "$testRoot/runners/dispatcher.json" -Encoding UTF8
@'
param([string]$Root,[switch]$TestMode)
$ErrorActionPreference='Stop'
if (!$TestMode) { throw 'TestMode was not forwarded' }
$guard = [IO.File]::Open("$Root/state/fake-child.lock",'OpenOrCreate','ReadWrite','None')
try {
    Add-Content "$Root/calls.txt" ("start|$PID|" + [DateTime]::UtcNow.ToString('o'))
    Start-Sleep -Milliseconds 800
    foreach ($file in Get-ChildItem "$Root/work/inbox" -Filter '*.json') {
        $statusPath="$Root/work/status/$($file.Name)"
        if (!(Test-Path $statusPath)) {
            @{id=$file.BaseName;state='pending';stage='review'} | ConvertTo-Json | Set-Content $statusPath
        } elseif ((Get-Content $statusPath -Raw | ConvertFrom-Json).state -eq 'pending') {
            @{id=$file.BaseName;state='completed';stage='review'} | ConvertTo-Json | Set-Content $statusPath
        }
    }
    Add-Content "$Root/calls.txt" ("end|$PID|" + [DateTime]::UtcNow.ToString('o'))
} finally { $guard.Dispose() }
'@ | Set-Content "$testRoot/runners/dispatcher.ps1" -Encoding UTF8
function Start-TestMonitor([string]$name) {
    Start-Process -FilePath "$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe" -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$monitorPath+'"'),'-Root',('"'+$testRoot+'"'),'-ReconcileSeconds','300','-HeartbeatSeconds','1','-TestMode','-StopAfterSeconds','45') -RedirectStandardOutput "$testRoot/$name.stdout.txt" -RedirectStandardError "$testRoot/$name.stderr.txt"
}
function Wait-Condition([scriptblock]$condition,[string]$description,[int]$seconds=15) {
    $timer=[Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt $seconds) {
        if (& $condition) { return }
        Start-Sleep -Milliseconds 100
    }
    throw "Timed out: $description. Test artifacts: $testRoot"
}
function Completed([string]$id) {
    $path="$testRoot/work/status/$id.json"
    if (!(Test-Path $path)) { return $false }
    try { return (Get-Content $path -Raw | ConvertFrom-Json).state -eq 'completed' } catch { return $false }
}
$monitor=$null
$duplicate=$null
try {
    $monitor=Start-TestMonitor 'primary'
    Wait-Condition { Test-Path "$testRoot/state/monitor-heartbeat.json" } 'monitor heartbeat'
    $duplicate=Start-TestMonitor 'duplicate'
    Wait-Condition { $duplicate.Refresh(); $duplicate.HasExited } 'duplicate monitor exclusion' 8
    $monitor.Refresh(); if ($monitor.HasExited) { throw 'Primary monitor exited unexpectedly' }
    @{id='event-one';status='ready';owner='codex'} | ConvertTo-Json | Set-Content "$testRoot/work/inbox/event-one.json"
    Wait-Condition { Completed 'event-one' } 'event-driven execute and immediate review' 12
    $before=@(Get-Content "$testRoot/calls.txt").Count
    Start-Sleep -Seconds 3
    if (@(Get-Content "$testRoot/calls.txt").Count -ne $before) { throw 'Idle monitor continuously launched empty dispatchers' }
    $workerLock=[IO.File]::Open("$testRoot/state/dispatcher.lock",'OpenOrCreate','ReadWrite','None')
    try {
        @{id='lock-test';status='ready';owner='codex'} | ConvertTo-Json | Set-Content "$testRoot/work/inbox/lock-test.json"
        Start-Sleep -Seconds 4
        if (@(Get-Content "$testRoot/calls.txt").Count -ne $before) { throw 'Monitor launched dispatcher while another worker held its lock' }
    } finally { $workerLock.Dispose() }
    Wait-Condition { Completed 'lock-test' } 'queued work after worker lock release' 12
    @{id='event-two';status='ready';owner='codex'} | ConvertTo-Json | Set-Content "$testRoot/work/inbox/event-two.json"
    Wait-Condition { Completed 'event-two' } 'second event without minute polling' 12
    @{id='stop-test';status='ready';owner='codex'} | ConvertTo-Json | Set-Content "$testRoot/work/inbox/stop-test.json"
    Wait-Condition { $lines=@(Get-Content "$testRoot/calls.txt"); $lines[-1] -like 'start|*' } 'active child before stop'
    New-Item -ItemType File "$testRoot/state/monitor.stop" -Force | Out-Null
    Wait-Condition { $monitor.Refresh(); $monitor.HasExited } 'graceful monitor stop' 10
    $lines=@(Get-Content "$testRoot/calls.txt")
    if ($lines[-1] -notlike 'end|*') { throw 'Monitor exited before its active child completed' }
    for ($i=0; $i -lt $lines.Count; $i+=2) {
        if ($lines[$i] -notlike 'start|*' -or $lines[$i+1] -notlike 'end|*' -or $lines[$i].Split('|')[1] -ne $lines[$i+1].Split('|')[1]) { throw 'Overlapping or unfinished dispatcher child detected' }
    }
    if ((Get-Item "$testRoot/primary.stderr.txt").Length -gt 0) { throw "Monitor stderr: $(Get-Content "$testRoot/primary.stderr.txt" -Raw)" }
    Write-Output "PASS: event wakeup, immediate review, idle stability, duplicate exclusion, worker lock exclusion and recovery, serialized children, heartbeat, graceful stop. Artifacts: $testRoot"
} finally {
    New-Item -ItemType File "$testRoot/state/monitor.stop" -Force | Out-Null
    foreach ($proc in @($duplicate,$monitor)) { if ($proc) { $proc.Refresh(); if (!$proc.HasExited) { $null=$proc.WaitForExit(5000); if (!$proc.HasExited) { $proc.Kill() } } } }
}

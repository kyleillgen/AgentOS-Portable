param(
    [string]$Root=(Split-Path $PSScriptRoot -Parent),
    [ValidateRange(5,86400)][int]$ReconcileSeconds=300,
    [ValidateRange(1,60)][int]$HeartbeatSeconds=5,
    [switch]$TestMode,
    [ValidateRange(0,86400)][int]$StopAfterSeconds=0
)
$ErrorActionPreference='Stop'
$cfg=Get-Content (Join-Path $Root 'runners/dispatcher.json') -Raw|ConvertFrom-Json
if(!$TestMode -and $env:COMPUTERNAME -ne $cfg.host){throw 'This computer is not the designated dispatcher.'}
$state=Join-Path $Root 'state';$inbox=Join-Path $Root 'work/inbox'
New-Item -ItemType Directory $state,$inbox -Force|Out-Null
try{$monitorLock=[IO.File]::Open((Join-Path $state 'monitor.lock'),'OpenOrCreate','ReadWrite','None')}catch [IO.IOException]{return}
$watcher=$null;$child=$null;$subscriptions=@();$outTask=$null;$errTask=$null
$clock=[Diagnostics.Stopwatch]::StartNew();$dirty=$true;$nextDue=$null;$nextReconcile=[DateTime]::UtcNow;$nextHeartbeat=[DateTime]::MinValue;$lastEvent=$null
function Write-MonitorLog([string]$Message){
    $line="$([DateTime]::UtcNow.ToString('o')) $Message"
    try{Add-Content -LiteralPath (Join-Path $state 'monitor.log') -Encoding UTF8 -Value $line}
    catch{
        # Diagnostics in a synced folder must not stop queue supervision.
        if($cfg.run_ledger){try{Add-Content -LiteralPath (Join-Path ([string]$cfg.run_ledger) 'monitor-diagnostics.log') -Encoding UTF8 -Value $line}catch{}}
    }
}
function Get-NextWorkTime {
    if(Test-Path (Join-Path $state 'runtime-quarantine.json')){return $null}
    $earliest=$null
    foreach($file in Get-ChildItem -LiteralPath $inbox -Filter '*.json' -File){
        if($file.BaseName -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}$'){continue}
        $statusPath=Join-Path $Root "work/status/$($file.BaseName).json"
        if(Test-Path -LiteralPath $statusPath){
            try{$status=Get-Content -LiteralPath $statusPath -Raw|ConvertFrom-Json}catch{continue}
            if($status.state -in @('completed','needs_attention','blocked')){continue}
        }
        $due=$file.LastWriteTimeUtc.AddSeconds([Math]::Max(0,[double]$cfg.settle_seconds)+0.25)
        if($null -eq $earliest -or $due -lt $earliest){$earliest=$due}
    }
    return $earliest
}
try{
    $watcher=[IO.FileSystemWatcher]::new($inbox,'*.json');$watcher.NotifyFilter=[IO.NotifyFilters]'FileName,LastWrite,Size'
    foreach($eventName in @('Created','Changed','Renamed','Deleted','Error')){
        $source="AgentOSMonitor-$PID-$eventName";Register-ObjectEvent $watcher $eventName -SourceIdentifier $source|Out-Null;$subscriptions+=$source
    }
    $watcher.EnableRaisingEvents=$true
    Write-MonitorLog "started pid=$PID event-driven reconcile_seconds=$ReconcileSeconds"
    while($true){
        $now=[DateTime]::UtcNow
        $stopping=(Test-Path (Join-Path $state 'monitor.stop')) -or ($StopAfterSeconds -gt 0 -and $clock.Elapsed.TotalSeconds -ge $StopAfterSeconds)
        foreach($source in $subscriptions){
            $events=@(Get-Event -SourceIdentifier $source -ErrorAction SilentlyContinue)
            if($events.Count){$dirty=$true;$lastEvent=$now.ToString('o');$events|Remove-Event}
        }
        if($null -ne $child -and $child.HasExited){
            $exit=$child.ExitCode
            Write-MonitorLog "dispatcher-finished pid=$($child.Id) exit=$exit"
            if($null -ne $errTask -and $errTask.IsCompleted -and !$errTask.IsFaulted -and $errTask.Result){Write-MonitorLog ($errTask.Result.Substring(0,[Math]::Min(1500,$errTask.Result.Length)))}
            $child.Dispose();$child=$null;$dirty=$true
            # Exceptional launch failures back off; don't spin a broken worker.
            if($exit -ne 0){$nextDue=$now.AddSeconds(10);$dirty=$false}
        }
        if($now -ge $nextReconcile){$dirty=$true;$nextReconcile=$now.AddSeconds($ReconcileSeconds)}
        if($dirty -and $null -eq $child){$nextDue=Get-NextWorkTime;$dirty=$false}
        if(!$stopping -and $null -eq $child -and $null -ne $nextDue -and $now -ge $nextDue){
            # A surviving worker from a prior monitor still owns this lock.
            # Wait locally rather than spawning no-op dispatchers and observers.
            $workerBusy=$false
            try{$probe=[IO.File]::Open((Join-Path $state 'dispatcher.lock'),'OpenOrCreate','ReadWrite','None');$probe.Dispose()}catch [IO.IOException]{$workerBusy=$true}
            if($workerBusy){$nextDue=$now.AddSeconds(2)}else{
            $psi=New-Object Diagnostics.ProcessStartInfo
            $psi.FileName=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
            $dispatchPath=Join-Path $Root 'runners/dispatcher.ps1'
            $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$dispatchPath+'" -Root "'+$Root+'"'+$(if($TestMode){' -TestMode'}else{''})
            $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
            $psi.EnvironmentVariables['POWERSHELL_TELEMETRY_OPTOUT']='1'
            $child=[Diagnostics.Process]::Start($psi);$outTask=$child.StandardOutput.ReadToEndAsync();$errTask=$child.StandardError.ReadToEndAsync()
            Write-MonitorLog "dispatcher-started pid=$($child.Id)";$nextDue=$null
            }
        }
        if($now -ge $nextHeartbeat){
            $heartbeat=[ordered]@{schema_version='agentos-monitor-v1';utc=$now.ToString('o');pid=$PID;mode='event-driven';child_pid=$(if($child){$child.Id}else{$null});stopping=[bool]$stopping;last_event_utc=$lastEvent;reconcile_seconds=$ReconcileSeconds}
            $path=Join-Path $state 'monitor-heartbeat.json'
            try{
                $heartbeat|ConvertTo-Json|Set-Content "$path.tmp" -Encoding UTF8;Move-Item "$path.tmp" $path -Force
                $lastHeartbeatError=$null
            }catch{
                if($lastHeartbeatError -ne $_.Exception.Message){Write-MonitorLog "heartbeat-publish-failed: $($_.Exception.Message)"}
                $lastHeartbeatError=$_.Exception.Message
            }
            $nextHeartbeat=$now.AddSeconds($HeartbeatSeconds)
        }
        if($stopping -and $null -eq $child){break}
        Wait-Event -Timeout 1|Out-Null
    }
    Write-MonitorLog "stopped pid=$PID"
}finally{
    foreach($source in $subscriptions){Unregister-Event -SourceIdentifier $source -ErrorAction SilentlyContinue;Get-Event -SourceIdentifier $source -ErrorAction SilentlyContinue|Remove-Event}
    if($watcher){$watcher.Dispose()};if($child){$child.Dispose()};$monitorLock.Dispose()
}

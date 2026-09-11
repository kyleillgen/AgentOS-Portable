param([string]$MonitorPath=(Join-Path $PSScriptRoot 'monitor.ps1'),[switch]$ExpectFailure)
$ErrorActionPreference='Stop'
$root=Join-Path $env:TEMP ('agentos-monitor-io-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory "$root/runners","$root/work/inbox","$root/state" -Force|Out-Null
@{settle_seconds=1}|ConvertTo-Json|Set-Content "$root/runners/dispatcher.json"
$heartbeat="$root/state/monitor-heartbeat.json";[IO.File]::WriteAllText($heartbeat,'locked')
$lock=[IO.File]::Open($heartbeat,'Open','ReadWrite','None')
$p=New-Object Diagnostics.Process
$p.StartInfo.FileName="$env:SystemRoot/System32/WindowsPowerShell/v1.0/powershell.exe"
$p.StartInfo.Arguments="-NoProfile -ExecutionPolicy Bypass -File `"$MonitorPath`" -Root `"$root`" -TestMode -HeartbeatSeconds 1 -StopAfterSeconds 4"
$p.StartInfo.UseShellExecute=$false;$p.StartInfo.CreateNoWindow=$true;$p.StartInfo.RedirectStandardError=$true;$p.StartInfo.RedirectStandardOutput=$true
try{
    $null=$p.Start();$err=$p.StandardError.ReadToEndAsync();$stdout=$p.StandardOutput.ReadToEndAsync()
    if(!$ExpectFailure){Start-Sleep -Seconds 2;$lock.Dispose();$lock=$null}
    if(!$p.WaitForExit(15000)){throw 'Monitor exceeded test deadline'}
    $code=$p.ExitCode
}finally{if($lock){$lock.Dispose()};$p.Dispose()}
if($ExpectFailure){if($code -eq 0){throw 'Expected baseline sharing failure was not reproduced'};"REPRODUCED baseline locked-heartbeat failure: $($err.Result)"}
else{if($code -ne 0){throw "Monitor failed on a busy heartbeat: $($err.Result)"};if((Get-Content $heartbeat -Raw|ConvertFrom-Json).schema_version -ne 'agentos-monitor-v1'){throw 'Heartbeat did not recover after lock release'};'PASS: busy heartbeat does not terminate the monitor; heartbeat recovers after lock release; bounded graceful stop preserved.'}

#requires -Version 5.1
param(
    [string]$Root=(Split-Path $PSScriptRoot -Parent),
    [string]$TaskName='AgentOS Portable Dispatcher',
    [PSCredential]$Credential
)
$ErrorActionPreference='Stop'
$Root=[IO.Path]::GetFullPath($Root)
$existing=Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if($existing) { Write-Output 'Existing task preserved.'; $existing|Select-Object TaskName,State; return }
$cfg=Get-Content (Join-Path $Root 'runners/dispatcher.json') -Raw|ConvertFrom-Json
if($cfg.host -ne $env:COMPUTERNAME -or !$cfg.run_ledger -or !(Test-Path (Join-Path $cfg.run_ledger 'ledger.json'))) { throw 'Run setup and validate foreground dispatch first.' }
if(!$Credential) { throw 'Supply -Credential (Get-Credential) locally. Never place passwords in files or command text.' }
$engine=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$monitor=Join-Path $Root 'runners/monitor.ps1'
$arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$monitor+'" -Root "'+$Root+'"'
$action=New-ScheduledTaskAction -Execute $engine -Argument $arguments -WorkingDirectory $Root
$trigger=New-ScheduledTaskTrigger -AtStartup
$settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -User $Credential.UserName -Password $Credential.GetNetworkCredential().Password -RunLevel Limited|Select-Object TaskName,State

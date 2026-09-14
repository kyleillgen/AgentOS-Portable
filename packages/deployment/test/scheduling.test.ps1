#requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../deployment-common.ps1')
$folder=Join-Path ([IO.Path]::GetTempPath()) ('agentos-schedule-contract-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path (Join-Path $folder 'state') -Force
$receipt=[pscustomobject]@{id=[guid]::NewGuid().ToString('N');profile='Unattended';modules=@('base','runner','operations');root=$folder;local_state=$folder+'-local';python='C:\Tools\python.exe';host=$env:COMPUTERNAME;status='configured';tasks=@()}
$credential=[PSCredential]::new('test-account',(ConvertTo-SecureString 'not-a-real-password' -AsPlainText -Force))
$script:registered=@{};$script:deniedAt=0;$script:registerCalls=0;$script:starts=0;$script:mismatch=$false
function Get-ScheduledTask{param($TaskName,$ErrorAction);if($script:lookupDenied){throw 'Simulated task lookup denied'};return @($script:registered.Values)}
function New-ScheduledTaskAction{param($Execute,$Argument,$WorkingDirectory);return [pscustomobject]@{Execute=$Execute;Arguments=$Argument}}
function New-ScheduledTaskTrigger{param([switch]$AtStartup);return 'startup'}
function New-ScheduledTaskSettingsSet{param($MultipleInstances,[switch]$StartWhenAvailable,[switch]$AllowStartIfOnBatteries,[switch]$DontStopIfGoingOnBatteries,$ExecutionTimeLimit,$RestartCount,$RestartInterval);return [pscustomobject]@{ExecutionTimeLimit='PT0S';Enabled=$true}}
function Register-ScheduledTask{
    param($TaskName,$TaskPath,$Action,$Trigger,$Settings,$User,$Password,$RunLevel,$ErrorAction)
    if($ErrorAction -ne 'Stop'){throw 'Registration must use terminating errors'}
    $script:registerCalls++
    if($script:registerCalls -eq $script:deniedAt){throw 'Simulated access denied'}
    $script:registered[$TaskName]=[pscustomobject]@{TaskName=$TaskName;TaskPath=$TaskPath;Actions=@($Action);Settings=$Settings;Principal=[pscustomobject]@{LogonType=$(if($script:mismatch){'Interactive'}else{'Password'})};State='Ready'}
}
function Start-ScheduledTask{param($TaskName,$TaskPath,$ErrorAction);$script:starts++;$script:registered[$TaskName].State='Running'}
function Stop-ScheduledTask{param($TaskName,$TaskPath,$ErrorAction);$script:registered[$TaskName].State='Ready'}
function Unregister-ScheduledTask{param($TaskName,$TaskPath,$Confirm,$ErrorAction);$script:registered.Remove($TaskName)}
function Assert([bool]$Condition,[string]$Message){if(!$Condition){throw $Message}}
foreach($denial in @(1,2,3)){
    $script:deniedAt=$denial;$script:registerCalls=0;$script:starts=0;$receipt.status='configured'
    $failed=$false
    try{Enable-Deployment $receipt $credential}catch{$failed=$true}
    Assert $failed 'Registration denial was hidden'
    Assert ($script:registered.Count -eq 0) 'Partial registration was not rolled back'
    Assert ($script:starts -eq 0) 'Started before all registrations were verified'
}
$script:deniedAt=0;$script:mismatch=$true;$receipt.status='configured'
$failed=$false;try{Enable-Deployment $receipt $credential}catch{$failed=$true}
Assert ($failed -and $script:registered.Count -eq 0) 'Readback mismatch was accepted'
$script:mismatch=$false;$receipt.status='configured'
$script:lookupDenied=$true;$failed=$false
try{Enable-Deployment $receipt $credential}catch{$failed=$true}
Assert $failed 'Unreadable scheduler was treated as an empty scheduler'
Disable-Deployment $receipt
Assert ($receipt.status -eq 'disabled') 'A never-activated installation should be removable without scheduler access'
$script:lookupDenied=$false
Enable-Deployment $receipt $credential
Assert ($script:registered.Count -eq 3 -and $receipt.status -eq 'active') 'Expected three separately owned startup tasks'
$specs=@(Get-DeploymentTasks $receipt)
$original=$script:registered[$specs[0].name].Actions[0].Arguments
$script:registered[$specs[0].name].Actions[0].Arguments='unrelated task'
$failed=$false;try{Disable-Deployment $receipt}catch{$failed=$true}
Assert ($failed -and $script:registered.Count -eq 3) 'Unrelated task was touched during removal'
$script:registered[$specs[0].name].Actions[0].Arguments=$original
Disable-Deployment $receipt
Assert ($script:registered.Count -eq 0 -and $receipt.status -eq 'disabled') 'Owned tasks were not removed'
Write-Output 'PASS: simulated Windows scheduling failures and ownership boundaries. No real Windows task was registered.'

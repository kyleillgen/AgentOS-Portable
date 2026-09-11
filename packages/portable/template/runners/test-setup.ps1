$ErrorActionPreference='Stop'
$testRoot=Join-Path $env:TEMP ('agentos-setup-'+[guid]::NewGuid().ToString('N'))
$workspace=Join-Path $testRoot 'workspace with spaces'
$ledger=Join-Path $testRoot 'ledger'
New-Item -ItemType Directory "$workspace/runners" -Force|Out-Null
$fixtureConfig=Get-Content "$PSScriptRoot/dispatcher.json" -Raw|ConvertFrom-Json
$fixtureConfig.host='CONFIGURE_WITH_SETUP';$fixtureConfig.run_ledger=$null
$fixtureConfig|ConvertTo-Json -Depth 10|Set-Content "$workspace/runners/dispatcher.json"
$binary=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
& "$PSScriptRoot/setup.ps1" -Root $workspace -CodexPath $binary -ClaudePath $binary -LedgerDirectory $ledger
$config=Get-Content "$workspace/runners/dispatcher.json" -Raw|ConvertFrom-Json
if($config.host -ne $env:COMPUTERNAME -or $config.run_ledger -ne [IO.Path]::GetFullPath($ledger)) { throw 'Configuration mismatch' }
$before=(Get-FileHash "$ledger/ledger.json").Hash
$refused=$false
try { & "$PSScriptRoot/setup.ps1" -Root $workspace -CodexPath $binary -ClaudePath $binary -LedgerDirectory $ledger } catch { $refused=$true }
if(!$refused -or (Get-FileHash "$ledger/ledger.json").Hash -ne $before) { throw 'Setup overwrote existing ledger/config' }
$orderPath=Join-Path $testRoot 'order.json'
Copy-Item "$PSScriptRoot/smoke-order.example.json" $orderPath
& "$PSScriptRoot/publish-order.ps1" -Root $workspace -OrderPath $orderPath
$published=Join-Path $workspace 'work/inbox/dispatcher-smoke-001.json'
if((Get-FileHash $published).Hash -ne (Get-FileHash $orderPath).Hash) { throw 'Published bytes differ' }
$refused=$false
try { & "$PSScriptRoot/publish-order.ps1" -Root $workspace -OrderPath $orderPath } catch { $refused=$true }
if(!$refused) { throw 'Duplicate publish not rejected' }
$order=Get-Content $orderPath -Raw|ConvertFrom-Json
$order.id='../escape';$order|ConvertTo-Json|Set-Content $orderPath
$refused=$false
try { & "$PSScriptRoot/publish-order.ps1" -Root $workspace -OrderPath $orderPath } catch { $refused=$true }
if(!$refused) { throw 'Invalid ID not rejected' }
# Mock every scheduler API: this test never registers a real task.
$global:AgentOSFixtureRegistration=$null
function Get-ScheduledTask { param($TaskName,$ErrorAction) return $null }
function New-ScheduledTaskAction { param($Execute,$Argument,$WorkingDirectory) return @{Execute=$Execute;Argument=$Argument;WorkingDirectory=$WorkingDirectory} }
function New-ScheduledTaskTrigger { param([switch]$AtStartup) return @{AtStartup=[bool]$AtStartup} }
function New-ScheduledTaskSettingsSet { param($MultipleInstances,[switch]$StartWhenAvailable,[switch]$AllowStartIfOnBatteries,[switch]$DontStopIfGoingOnBatteries,$ExecutionTimeLimit,$RestartCount,$RestartInterval) return @{ExecutionTimeLimit=$ExecutionTimeLimit} }
function Register-ScheduledTask { param($TaskName,$Action,$Trigger,$Settings,$User,$Password,$RunLevel) $global:AgentOSFixtureRegistration=@{TaskName=$TaskName;Action=$Action;Trigger=$Trigger;Settings=$Settings;RunLevel=$RunLevel}; return @{TaskName=$TaskName} }
$credential=[PSCredential]::new('fixture-user',(ConvertTo-SecureString 'fixture-only' -AsPlainText -Force))
& "$PSScriptRoot/install-dispatcher.ps1" -Root $workspace -Credential $credential
if($global:AgentOSFixtureRegistration.RunLevel -ne 'Limited' -or $global:AgentOSFixtureRegistration.Settings.ExecutionTimeLimit -ne [TimeSpan]::Zero -or !$global:AgentOSFixtureRegistration.Trigger.AtStartup -or $global:AgentOSFixtureRegistration.Action.Argument -notmatch 'monitor.ps1') { throw 'Scheduled action contract invalid' }
$global:AgentOSFixtureRegistration=$null
function Get-ScheduledTask { param($TaskName,$ErrorAction) return @{TaskName=$TaskName;State='Ready'} }
& "$PSScriptRoot/install-dispatcher.ps1" -Root $workspace -Credential $credential
if($null -ne $global:AgentOSFixtureRegistration) { throw 'Existing task overwritten' }
'PASS: setup, external ledger initialization, no overwrite, atomic order publication, invalid IDs, scheduler configuration and existing-task preservation. No real scheduler registration or model calls.'

$ErrorActionPreference='Stop'
$root=Join-Path $env:TEMP ('agentos-ledger-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory "$root/runners","$root/work/inbox","$root/ledger" -Force|Out-Null
$cfg=Get-Content "$PSScriptRoot/dispatcher.json" -Raw|ConvertFrom-Json
$cfg.host='test-'+[guid]::NewGuid().ToString('N');$cfg.settle_seconds=0;$cfg.git_checkpoint_script=$null;$cfg.health_script=$null;$cfg.run_ledger="$root/ledger"
$cfg|ConvertTo-Json|Set-Content "$root/runners/dispatcher.json"
@{schema=1;root=$root;orders=@{}}|ConvertTo-Json|Set-Content "$root/ledger/ledger.json"
$dispatcher="$PSScriptRoot/dispatcher.ps1"
@{id='once';status='ready';owner='codex';objective='Synthetic';acceptance='Synthetic'}|ConvertTo-Json|Set-Content "$root/work/inbox/once.json"
& $dispatcher -Root $root -TestMode
& $dispatcher -Root $root -TestMode
if((Get-Content "$root/ledger/ledger.json" -Raw|ConvertFrom-Json).orders.once.status.state -ne 'completed'){throw 'Terminal record not durable'}
Move-Item "$root/work/status" "$root/saved-status"
Move-Item "$root/work/receipts" "$root/saved-receipts"
Move-Item "$root/work/results" "$root/saved-results"
Move-Item "$root/work/handoffs" "$root/saved-handoffs"
& $dispatcher -Root $root -TestMode
if((Get-Content "$root/work/status/once.json" -Raw|ConvertFrom-Json).state -ne 'completed'){throw 'Deleted runtime state not restored'}
if(Test-Path "$root/work/results/once/execute.txt"){throw 'Completed order replayed'}
if((Get-Content "$root/work/handoffs/once.json" -Raw|ConvertFrom-Json).delivery_state -ne 'pending'){throw 'Delivery handoff not reconstructed'}
@{id='once';state='pending';stage='execute'}|ConvertTo-Json|Set-Content "$root/work/status/once.json"
& $dispatcher -Root $root -TestMode
if((Get-Content "$root/work/status/once.json" -Raw|ConvertFrom-Json).state -ne 'completed'){throw 'Stale pending overrode terminal ledger'}
Add-Content "$root/work/inbox/once.json" ' '
& $dispatcher -Root $root -TestMode
if(!(Test-Path "$root/state/alerts/ledger-once.json")){throw 'Mutated bytes were not detected'}
$ledger=Get-Content "$root/ledger/ledger.json" -Raw|ConvertFrom-Json
@{id='interrupted';status='ready';owner='codex';objective='Never replay';acceptance='Never'}|ConvertTo-Json|Set-Content "$root/work/inbox/interrupted.json"
$interrupted=@{order_sha256=(Get-FileHash "$root/work/inbox/interrupted.json").Hash.ToLowerInvariant();retired=$false;status=@{id='interrupted';state='running';stage='execute';owner='codex';note='crash'}}
$ledger.orders|Add-Member interrupted $interrupted
$retired=@{order_sha256=$null;retired=$true;status=@{id='retired';state='needs_attention';stage='execute';owner='codex';note='historical'}}
$ledger.orders|Add-Member retired $retired
$ledger|ConvertTo-Json -Depth 20|Set-Content "$root/ledger/ledger.json"
@{id='retired';status='ready';owner='codex';objective='Never replay';acceptance='Never'}|ConvertTo-Json|Set-Content "$root/work/inbox/retired.json"
& $dispatcher -Root $root -TestMode
if((Get-Content "$root/work/status/interrupted.json" -Raw|ConvertFrom-Json).state -ne 'needs_attention'){throw 'Lost running attempt replayed'}
if(Test-Path "$root/work/results/interrupted/execute.txt"){throw 'Interrupted task executed again'}
if((Get-Content "$root/work/status/retired.json" -Raw|ConvertFrom-Json).state -ne 'needs_attention'){throw 'Retired ID not suppressed'}
$rejected=$false;try{& $dispatcher -Root $root -TestMode -RetryId retired -RetryReason 'test'}catch{$rejected=$true}
if(!$rejected){throw 'Retired retry accepted'}
New-Item -ItemType Directory "$root/fault-runners" -Force|Out-Null
foreach($name in 'dispatcher.ps1','run-ledger.ps1','telemetry.ps1','process-runtime.ps1'){Copy-Item "$PSScriptRoot/$name" "$root/fault-runners/$name"}
Add-Content "$root/fault-runners/run-ledger.ps1" @'
function Publish-DeliveryHandoff([string]$Id) { if($Id -eq 'publication' -and (Get-LedgerRecord $Id).status.state -eq 'completed'){throw 'Injected handoff publication failure'} }
'@
@{id='publication';status='ready';owner='codex';objective='Synthetic';acceptance='Synthetic'}|ConvertTo-Json|Set-Content "$root/work/inbox/publication.json"
& "$root/fault-runners/dispatcher.ps1" -Root $root -TestMode
$rejected=$false;try{& "$root/fault-runners/dispatcher.ps1" -Root $root -TestMode}catch{$rejected=$true}
if(!$rejected){throw 'Injected publication failure was not detected'}
if((Get-Content "$root/ledger/ledger.json" -Raw|ConvertFrom-Json).orders.publication.status.state -ne 'completed'){throw 'Publication failure downgraded completed outcome'}
$rejected=$false;try{& $dispatcher -Root $root -TestMode -RetryId publication -RetryReason 'Must reject'}catch{$rejected=$true}
if(!$rejected){throw 'Publication failure made completed work retryable'}
& $dispatcher -Root $root -TestMode
if(!(Test-Path "$root/work/handoffs/publication.json")){throw 'Publication recovery did not rebuild handoff'}
Move-Item "$root/ledger/ledger.json" "$root/ledger/ledger.saved"
$rejected=$false;try{& $dispatcher -Root $root -TestMode}catch{$rejected=$true}
if(!$rejected){throw 'Missing ledger accepted'}
'{bad'|Set-Content "$root/ledger/ledger.json"
$rejected=$false;try{& $dispatcher -Root $root -TestMode}catch{$rejected=$true}
if(!$rejected){throw 'Corrupt ledger accepted'}
"PASS: protected terminal restore after runtime deletion, stale-state rejection, immutable hash, historical retirement, retry rejection, missing/corrupt ledger fail-closed. $root"

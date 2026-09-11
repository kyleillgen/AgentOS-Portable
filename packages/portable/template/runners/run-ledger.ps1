# Loaded by dispatcher after Save-Json is defined; initialized only under its lock.
function Initialize-RunLedger {
    $script:runLedger=$null;$script:runLedgerFile=$null
    if (!$cfg.run_ledger) { if($TestMode){return};throw 'Normal dispatch requires a protected run_ledger configuration.' }
    $script:runLedgerFile=Join-Path ([string]$cfg.run_ledger) 'ledger.json'
    if (!(Test-Path -LiteralPath $script:runLedgerFile -PathType Leaf)) { throw 'Protected run ledger missing. Operator recovery required; no model launched.' }
    $script:runLedger=Read-Utf8 $script:runLedgerFile|ConvertFrom-Json
    if ($script:runLedger.schema -ne 1 -or [IO.Path]::GetFullPath([string]$script:runLedger.root) -ne [IO.Path]::GetFullPath($Root) -or $null -eq $script:runLedger.orders -or $script:runLedger.orders -isnot [pscustomobject]) { throw 'Protected run ledger invalid or belongs to another root.' }
    foreach($entry in $script:runLedger.orders.PSObject.Properties) {
        if($entry.Name -notmatch '^[a-zA-Z0-9][a-zA-Z0-9_-]{0,79}$' -or $entry.Value.status.id -ne $entry.Name -or $entry.Value.status.state -notin @('pending','running','completed','needs_attention','blocked') -or $entry.Value.status.stage -notin @('execute','review')){throw 'Protected run ledger contains an invalid record.'}
        if(!$entry.Value.retired -and [string]$entry.Value.order_sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'Protected run ledger contains an invalid order hash.'}
    }
}
function Get-LedgerRecord([string]$Id) {
    if($null -eq $script:runLedger){return $null}
    $property=$script:runLedger.orders.PSObject.Properties[$Id]
    if($property){return $property.Value}
    return $null
}
function Save-LedgerStatus([string]$Id,$Status) {
    if($null -eq $script:runLedger){return}
    $old=Get-LedgerRecord $Id
    if($old.retired){throw 'Retired work order cannot be modified or retried. Use a new linked ID.'}
    if($old.status.state -eq 'completed' -and $Status.state -ne 'completed'){throw 'Protected completed outcome cannot be downgraded by a projection or handoff failure.'}
    $orderPath=Join-Path $Root "work/inbox/$Id.json"
    $hash=(Get-FileHash -LiteralPath $orderPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if($old -and $old.order_sha256 -cne $hash){throw 'Published order bytes changed; protected record preserved.'}
    $record=[pscustomobject]@{order_sha256=$hash;retired=$false;status=$Status}
    if($Status.state -eq 'completed'){
        $order=Read-Utf8 $orderPath|ConvertFrom-Json
        $reviewer=if($order.owner -eq 'ollama'){[string]$cfg.ollama.reviewer}elseif($order.owner -eq 'codex'){'claude'}else{'codex'}
        $record|Add-Member -NotePropertyName handoff -NotePropertyValue ([ordered]@{schema='agentos-delivery-handoff-v1';id=$Id;project_id=$order.project_id;task_id=$order.task_id;producer=$order.owner;reviewer=$reviewer;attempt_state='completed';delivery_state='pending';closure_state='pending';execute="work/results/$Id/execute.txt";review="work/results/$Id/review.txt";next_action='Coordinator: deliver reviewed artifacts, record actual delivery evidence, then revision-checked project closure. Never infer delivery from this record.'})
    }
    $script:runLedger.orders|Add-Member -NotePropertyName $Id -NotePropertyValue $record -Force
    $temp=$script:runLedgerFile+'.tmp'
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($script:runLedger|ConvertTo-Json -Depth 20))
    $stream=[IO.File]::Open($temp,'Create','Write','None')
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    [IO.File]::Replace($temp,$script:runLedgerFile,$script:runLedgerFile+'.previous', $true)
}
function Restore-LedgerStatus([string]$Id,[string]$OrderPath,[string]$StatusPath) {
    $record=Get-LedgerRecord $Id
    if(!$record){return}
    if(!$record.retired -and $record.order_sha256 -cne (Get-FileHash -LiteralPath $OrderPath -Algorithm SHA256).Hash.ToLowerInvariant()){throw "Order $Id differs from its protected hash. Use a new linked ID."}
    # Shared runtime files are projections, never authority over the protected record.
    Save-Json $StatusPath $record.status -SkipLedger
    Save-Json (Join-Path $Root "work/receipts/$Id.json") $record.status -SkipLedger
    Publish-DeliveryHandoff $Id
}
function Publish-DeliveryHandoff([string]$Id) {
    $record=Get-LedgerRecord $Id
    if($record.status.state -eq 'completed' -and $record.handoff){
        $dir=Join-Path $Root 'work/handoffs';New-Item -ItemType Directory $dir -Force|Out-Null
        $path=Join-Path $dir "$Id.json"
        # Preserve any coordinator's delivery update; regenerate only if absent.
        if(!(Test-Path -LiteralPath $path)){Save-Json $path $record.handoff -SkipLedger}
    }
}

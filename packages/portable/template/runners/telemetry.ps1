# Supplemental evidence, never a substitute for independent acceptance review.
function Write-CostRow([string]$CostPath,[string]$OutDir,[string]$Stage,[string]$Row) {
    # Per-attempt runtime already contains the authoritative observed usage.
    # A shared aggregate lock must never turn valid work into a replay candidate.
    try { Add-Content -LiteralPath $CostPath -Value $Row -Encoding UTF8 }
    catch {
        $pending=Join-Path $OutDir "$Stage-cost-pending.json"
        try {
            [IO.File]::WriteAllText($pending,(@{row=$Row;reason=$_.Exception.Message;state='pending-aggregate-append'}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        } catch { Write-Warning 'Cost aggregate and pending record unavailable; consult stage runtime usage evidence.' }
    }
}
function Assert-PositiveBudgetInteger($Value, [string]$Name) {
    if (($Value -isnot [int] -and $Value -isnot [long]) -or $Value -lt 1 -or $Value -gt [int]::MaxValue) { throw "$Name must be a positive JSON integer at most 2147483647." }
}
function Get-EffectiveBudget($Task,$Config,[string]$Agent) {
    if ($null -ne $Task.PSObject.Properties['budget']) {
        if ($Task.budget -isnot [pscustomobject]) { throw 'budget must be a JSON object.' }
        foreach ($key in @('max_sources','max_searches','max_turns')) {
            if ($null -ne $Task.budget.PSObject.Properties[$key]) { Assert-PositiveBudgetInteger $Task.budget.$key "budget.$key" }
        }
    }
    $turns=$null
    if ($null -ne $Config.PSObject.Properties['claude_max_turns']) { Assert-PositiveBudgetInteger $Config.claude_max_turns 'claude_max_turns'; if($Agent -eq 'claude'){$turns=$Config.claude_max_turns} }
    if ($null -ne $Task.budget.max_turns) { if($null -eq $turns){$turns=$Task.budget.max_turns}else{$turns=[Math]::Min($turns,$Task.budget.max_turns)} }
    return [pscustomobject]@{max_turns=$turns;max_sources=$Task.budget.max_sources;max_searches=$Task.budget.max_searches;turn_enforcement=$(if($Agent -eq 'claude'){'cli'}else{'advisory'});source_search_enforcement='advisory'}
}
function Get-EvidenceHash([string]$Path) {
    if(Test-Path -LiteralPath $Path -PathType Leaf){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()};return $null
}
function Get-ClaudeTerminal([string]$Path) {
    try {
        $p=[IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8)|ConvertFrom-Json
        if($p -isnot [pscustomobject] -or $p.type -cne 'result' -or $p.is_error -isnot [bool] -or [string]::IsNullOrWhiteSpace($p.subtype)){throw 'Invalid terminal shape'}
        return [pscustomobject]@{payload=$p;failure_reason=$(if($p.is_error -or $p.subtype -cne 'success'){'provider_error:'+ $p.subtype}else{$null})}
    } catch {return [pscustomobject]@{payload=$null;failure_reason='malformed_or_missing_terminal_json'}}
}
function Write-AgentRuntime([string]$Root,[string]$OutDir,[string]$Stage,[string]$Id,[string]$Agent,[string]$Nonce,$HostResult,$Budget,[string]$OrderPath,$Terminal) {
    $path=Join-Path $OutDir "$Stage-runtime.json";$wrapper=$null
    if(Test-Path -LiteralPath $path){try{$wrapper=[IO.File]::ReadAllText($path)|ConvertFrom-Json}catch{$wrapper=[pscustomobject]@{parse_error=$true}}}
    $payload=$Terminal.payload;$searches=$null;$denials=$null
    if($null -ne $payload){
        if($payload.permission_denials -is [array]){$denials=$payload.permission_denials.Count}
        if($payload.modelUsage -is [pscustomobject] -and @($payload.modelUsage.PSObject.Properties).Count -gt 0){
            $sum=0L;$known=$true
            foreach($m in $payload.modelUsage.PSObject.Properties){$v=$m.Value.webSearchRequests;if(($v -isnot [int] -and $v -isnot [long]) -or $v -lt 0){$known=$false;break};$sum+=$v}
            if($known){$searches=$sum}
        }
    }
    $hashes=[ordered]@{}
    foreach($name in @('prompt.txt','stdout.txt','stderr.txt')){$hashes[$name]=Get-EvidenceHash (Join-Path $OutDir "$Stage-$name")}
    $artifacts=@(Get-ChildItem -LiteralPath $OutDir -File | Where-Object {$_.Name -notmatch '(runtime\.json$|-(prompt|stdout|stderr)\.txt$|dispatcher-commit\.json$|^relay-packet\.json$)'} | ForEach-Object {[pscustomobject]@{path=$_.Name;sha256=Get-EvidenceHash $_.FullName}})
    $policyHashes=[ordered]@{}
    foreach($policy in @('CLAUDE.md','AGENTS.md','OPERATING.md','CURRENT.md','DELEGATION.md')){$policyHashes[$policy]=Get-EvidenceHash (Join-Path $Root $policy)}
    $record=[ordered]@{
        schema_version='agentos-runtime-v1';run_id=$Nonce;id=$Id;stage=$Stage;provider=$Agent;recorded_at=[DateTime]::UtcNow.ToString('o')
        host=$HostResult;effective_budget=$Budget;wrapper=$wrapper;order_sha256=Get-EvidenceHash $OrderPath
        dispatcher_sha256=Get-EvidenceHash (Join-Path $PSScriptRoot 'dispatcher.ps1');telemetry_sha256=Get-EvidenceHash $PSCommandPath
        process_helper_sha256=Get-EvidenceHash (Join-Path $PSScriptRoot 'process-runtime.ps1');policy_hashes=$policyHashes
        permission_denials_count=$denials;web_search_requests=$searches;web_search_source=$(if($null -ne $searches){'sum(modelUsage.*.webSearchRequests)'}else{'unknown'})
        tool_call_count=$null;completeness='partial; terminal data is not an action audit';num_turns=$payload.num_turns
        provider_duration_ms=$payload.duration_ms;provider_subtype=$payload.subtype;provider_is_error=$payload.is_error;provider_failure=$Terminal.failure_reason
        usage=$payload.usage;model_usage=$payload.modelUsage;estimated_cost_usd=$payload.total_cost_usd;local_inference=$payload.ollama
        ollama_adapter_sha256=$(if($Agent -eq 'ollama'){Get-EvidenceHash (Join-Path $PSScriptRoot 'ollama-adapter.py')}else{$null})
        provider_version=$(if($Agent -eq 'codex'){$wrapper.codex_version}else{$null});provider_version_source=$(if($Agent -eq 'codex' -and $wrapper.codex_version){'wrapper'}else{'unknown'})
        log_hashes=$hashes;artifact_snapshot=$artifacts;claim_provenance='not captured; use task evidence map'
    }
    $temp="$path.tmp";$record|ConvertTo-Json -Depth 16|Set-Content -LiteralPath $temp -Encoding UTF8;Move-Item -LiteralPath $temp -Destination $path -Force
    return [pscustomobject]$record
}

param([string]$HelperPath = (Join-Path $PSScriptRoot 'telemetry.ps1'))
$ErrorActionPreference = 'Stop'
. $HelperPath
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('agentos-telemetry-' + [guid]::NewGuid())
New-Item -ItemType Directory $testRoot -Force | Out-Null
$checks=0
function Assert-Test([bool]$Condition,[string]$Message) { if(!$Condition){throw $Message}; $script:checks++ }
function Read-JsonText([string]$Text) { return ($Text | ConvertFrom-Json) }
$config=Read-JsonText '{"claude_max_turns":40}'
$task=Read-JsonText '{"budget":{"max_turns":12,"max_sources":6,"max_searches":8}}'
$budget=Get-EffectiveBudget $task $config 'claude'
Assert-Test ($budget.max_turns -eq 12 -and $budget.turn_enforcement -eq 'cli') 'Claude task cap should lower config cap'
$higher=Get-EffectiveBudget (Read-JsonText '{"budget":{"max_turns":80}}') $config 'claude'
Assert-Test ($higher.max_turns -eq 40) 'Config cap should bound larger task cap'
$codex=Get-EffectiveBudget $task $config 'codex'
Assert-Test ($codex.max_turns -eq 12 -and $codex.turn_enforcement -eq 'advisory') 'Codex task turns must remain advisory'
$codexDefault=Get-EffectiveBudget (Read-JsonText '{}') $config 'codex'
Assert-Test ($null -eq $codexDefault.max_turns) 'Claude config cap must not become Codex cap'
Assert-Test ($budget.max_sources -eq 6 -and $budget.max_searches -eq 8 -and $budget.source_search_enforcement -eq 'advisory') 'Source/search limits should remain explicit advisory evidence'
$orderPath=Join-Path $testRoot 'order.json'; Set-Content $orderPath '{"id":"test"}' -Encoding UTF8
Set-Content (Join-Path $testRoot 'OPERATING.md') 'synthetic policy evidence' -Encoding UTF8
$hostResult=[pscustomobject]@{exit_code=0;failure_reason=$null;elapsed_ms=17}
$cases=@(
    @{name='sum';json='{"type":"result","subtype":"success","is_error":false,"permission_denials":[],"usage":{"server_tool_use":{"web_search_requests":0}},"modelUsage":{"modelA":{"webSearchRequests":2},"modelB":{"webSearchRequests":3}}}';searches=5;denials=0},
    @{name='zero';json='{"type":"result","subtype":"success","is_error":false,"permission_denials":[],"modelUsage":{"modelA":{"webSearchRequests":0}}}';searches=0;denials=0},
    @{name='unknown';json='{"type":"result","subtype":"success","is_error":false,"usage":{"server_tool_use":{"web_search_requests":0}}}';searches=$null;denials=$null},
    @{name='partial';json='{"type":"result","subtype":"success","is_error":false,"permission_denials":[{"tool_name":"Bash"}],"modelUsage":{"modelA":{"webSearchRequests":2},"modelB":{}}}';searches=$null;denials=1}
)
foreach($case in $cases){
    $dir=Join-Path $testRoot $case.name; New-Item -ItemType Directory $dir -Force|Out-Null
    Set-Content (Join-Path $dir 'execute-stdout.txt') $case.json -Encoding UTF8
    Set-Content (Join-Path $dir 'execute-stderr.txt') 'PRIVATE_RAW_LOG_SENTINEL' -Encoding UTF8
    Set-Content (Join-Path $dir 'execute-prompt.txt') 'PRIVATE_PROMPT_SENTINEL' -Encoding UTF8
    Set-Content (Join-Path $dir 'deliverable.md') 'test artifact' -Encoding UTF8
    $terminal=Get-ClaudeTerminal (Join-Path $dir 'execute-stdout.txt')
    Assert-Test ($null -eq $terminal.failure_reason) "Valid terminal rejected: $($case.name)"
    $record=Write-AgentRuntime $testRoot $dir 'execute' 'test' 'claude' 'nonce' $hostResult $budget $orderPath $terminal
    Assert-Test ($record.web_search_requests -ceq $case.searches) "Wrong search count: $($case.name)"
    Assert-Test ($record.permission_denials_count -ceq $case.denials) "Wrong denial count: $($case.name)"
    Assert-Test (($null -eq $case.searches -and $record.web_search_source -eq 'unknown') -or ($null -ne $case.searches -and $record.web_search_source -eq 'sum(modelUsage.*.webSearchRequests)')) 'Search evidence source incorrect'
    Assert-Test ($record.order_sha256 -ceq (Get-FileHash $orderPath).Hash.ToLowerInvariant()) 'Order hash mismatch'
    Assert-Test ($record.log_hashes['stderr.txt'] -ceq (Get-FileHash (Join-Path $dir 'execute-stderr.txt')).Hash.ToLowerInvariant()) 'Log hash mismatch'
    Assert-Test ($record.telemetry_sha256 -ceq (Get-FileHash $HelperPath).Hash.ToLowerInvariant()) 'Telemetry helper hash mismatch'
    Assert-Test ($record.policy_hashes['OPERATING.md'] -ceq (Get-FileHash (Join-Path $testRoot 'OPERATING.md')).Hash.ToLowerInvariant()) 'Policy hash mismatch'
    Assert-Test ($null -eq $record.policy_hashes['CLAUDE.md']) 'Missing policy hash must stay unknown'
    $artifact=@($record.artifact_snapshot|Where-Object path -eq 'deliverable.md')
    Assert-Test ($artifact.Count -eq 1 -and $artifact[0].sha256 -ceq (Get-FileHash (Join-Path $dir 'deliverable.md')).Hash.ToLowerInvariant()) 'Artifact hash mismatch'
    $runtimeText=Get-Content (Join-Path $dir 'execute-runtime.json') -Raw
    Assert-Test ($runtimeText -notmatch 'PRIVATE_RAW_LOG_SENTINEL|PRIVATE_PROMPT_SENTINEL') 'Runtime copied raw prompt or stderr content'
}
$terminalCases=@(
    @{name='malformed';json='{invalid';failure='malformed_or_missing_terminal_json'},
    @{name='max-turns';json='{"type":"result","subtype":"error_max_turns","is_error":true}';failure='provider_error:error_max_turns'},
    @{name='is-error';json='{"type":"result","subtype":"success","is_error":true}';failure='provider_error:success'},
    @{name='wrong-type';json='{"type":"assistant","subtype":"success","is_error":false}';failure='malformed_or_missing_terminal_json'},
    @{name='missing-error';json='{"type":"result","subtype":"success"}';failure='malformed_or_missing_terminal_json'},
    @{name='error-string';json='{"type":"result","subtype":"success","is_error":"false"}';failure='malformed_or_missing_terminal_json'}
)
foreach($case in $terminalCases){$path=Join-Path $testRoot "$($case.name).json";Set-Content $path $case.json -Encoding UTF8;$terminal=Get-ClaudeTerminal $path;Assert-Test ($terminal.failure_reason -ceq $case.failure) "Failure not rejected: $($case.name)"}
$missing=Get-ClaudeTerminal (Join-Path $testRoot 'missing.json')
Assert-Test ($missing.failure_reason -eq 'malformed_or_missing_terminal_json') 'Missing terminal should fail'
$wslDir=Join-Path $testRoot 'wsl';New-Item -ItemType Directory $wslDir -Force|Out-Null
Set-Content (Join-Path $wslDir 'execute-runtime.json') '{"reason":"completed","children_retired":true,"codex_version":"test-version","nested":{"preserve":"evidence"}}' -Encoding UTF8
$terminal=[pscustomobject]@{payload=$null;failure_reason=$null}
$record=Write-AgentRuntime $testRoot $wslDir 'execute' 'test' 'codex' 'wsl-nonce' $hostResult $codex $orderPath $terminal
Assert-Test ($record.wrapper.reason -eq 'completed' -and $record.wrapper.children_retired -eq $true -and $record.wrapper.nested.preserve -eq 'evidence') 'WSL wrapper evidence not preserved'
Assert-Test ($record.provider_version -eq 'test-version' -and $record.provider_version_source -eq 'wrapper') 'WSL version evidence lost'
Assert-Test ($null -eq $record.web_search_requests -and $null -eq $record.permission_denials_count) 'Unavailable Codex usage must remain unknown'
"PASS: $checks telemetry assertions. No live models. Test artifacts: $testRoot"

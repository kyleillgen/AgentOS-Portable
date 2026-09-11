$ErrorActionPreference = 'Stop'
$dispatcherPath = Join-Path $PSScriptRoot 'dispatcher.ps1'
$tokens = $null
$parseErrors = $null
$dispatcherAst = [Management.Automation.Language.Parser]::ParseFile($dispatcherPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw "Dispatcher syntax invalid: $($parseErrors[0].Message)" }
$dispatcherText = Get-Content -LiteralPath $dispatcherPath -Raw
if (!$dispatcherText.Contains("'--cd',`$Root,'--add-dir',`$outDir,'--output-last-message',`$result")) { throw 'Codex paths and result write root are not passed as structured arguments' }
if ($dispatcherText -notmatch 'Read AGENTS\.md and TEAM\.md') { throw 'Lean context preamble missing' }
if (!$dispatcherText.Contains("'--strict-mcp-config','--tools','Read,Write,Edit,Glob,Grep,Bash,WebSearch,WebFetch'")) { throw 'Claude launch no longer restricts MCP servers and built-in tools' }
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('agentos-test-' + [guid]::NewGuid())
New-Item -ItemType Directory "$testRoot/runners","$testRoot/work/inbox" -Force | Out-Null
$cfg = Get-Content "$PSScriptRoot/dispatcher.json" -Raw | ConvertFrom-Json
$cfg | Add-Member -NotePropertyName run_ledger -NotePropertyValue $null -Force
$cfg.settle_seconds = 0
$cfg.host = 'test-' + [guid]::NewGuid().ToString('N')
$cfg.git_checkpoint_script = $null
$cfg.health_script = $null
$cfg | ConvertTo-Json | Set-Content "$testRoot/runners/dispatcher.json"
@{id='test-001';status='ready';owner='codex';objective='Test';acceptance='Test'} | ConvertTo-Json | Set-Content "$testRoot/work/inbox/test-001.json"
& $dispatcherPath -Root $testRoot -TestMode
$s = Get-Content "$testRoot/work/status/test-001.json" -Raw | ConvertFrom-Json
if ($s.state -ne 'pending' -or $s.stage -ne 'review') { throw 'Execution transition failed' }
& $dispatcherPath -Root $testRoot -TestMode
$s = Get-Content "$testRoot/work/status/test-001.json" -Raw | ConvertFrom-Json
if ($s.state -ne 'completed') { throw 'Review transition failed' }
$before = (Get-Item "$testRoot/work/results/test-001/review.txt").LastWriteTimeUtc
& $dispatcherPath -Root $testRoot -TestMode
if ((Get-Item "$testRoot/work/results/test-001/review.txt").LastWriteTimeUtc -ne $before) { throw 'Duplicate run occurred' }
'{"id":"bad","status":"ready","owner":"unknown"}' | Set-Content "$testRoot/work/inbox/bad.json"
& $dispatcherPath -Root $testRoot -TestMode
if ((Get-Content "$testRoot/work/status/bad.json" -Raw | ConvertFrom-Json).state -ne 'blocked') { throw 'Invalid input not blocked' }
$s.state='running'; $s | ConvertTo-Json | Set-Content "$testRoot/work/status/test-001.json"
& $dispatcherPath -Root $testRoot -TestMode
if ((Get-Content "$testRoot/work/status/test-001.json" -Raw | ConvertFrom-Json).state -ne 'needs_attention') { throw 'Interrupted run not flagged' }
# Load only the two production function definitions, never the live dispatcher body.
foreach ($functionName in @('Read-Utf8','Get-RunVerdict')) {
    $definition = $dispatcherAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true) | Where-Object Name -eq $functionName
    if (@($definition).Count -ne 1) { throw "Expected exactly one $functionName function" }
    . ([scriptblock]::Create($definition.Extent.Text))
}
$nonce = 'test-nonce-A'
$signed = "AGENTOS-VERDICT PASS $nonce"
$validFile = @{id='verdict-test';stage='execute';nonce=$nonce;verdict='PASS'}
$staleFile = $validFile.Clone(); $staleFile.nonce = 'stale'
$wrongStage = $validFile.Clone(); $wrongStage.stage = 'review'
$wrongId = $validFile.Clone(); $wrongId.id = 'other'
$verdictCases = @(
    @{name='no-signal';text='ordinary prose';expected='NEEDS_ATTENTION'},
    @{name='unsigned-prose';text="PASS`ndid not pass`nAGENTOS-VERDICT PASS";expected='NEEDS_ATTENTION'},
    @{name='signed-correct';text=$signed;expected='PASS'},
    @{name='signed-wrong';text='AGENTOS-VERDICT PASS wrong';expected='NEEDS_ATTENTION'},
    @{name='signed-attention';text="AGENTOS-VERDICT NEEDS_ATTENTION $nonce";expected='NEEDS_ATTENTION'},
    @{name='lowercase';text="AGENTOS-VERDICT pass $nonce";expected='NEEDS_ATTENTION'},
    @{name='valid-file';text='prose';file=$validFile;expected='PASS'},
    @{name='stale-file-no-fallback';text=$signed;file=$staleFile;expected='NEEDS_ATTENTION'},
    @{name='wrong-stage';text=$signed;file=$wrongStage;expected='NEEDS_ATTENTION'},
    @{name='wrong-id';text=$signed;file=$wrongId;expected='NEEDS_ATTENTION'},
    @{name='malformed-json';text=$signed;rawFile='{invalid';expected='NEEDS_ATTENTION'},
    @{name='stage-isolation';text=$signed;stage='review';executeFile=$validFile;expected='PASS'},
    @{name='crlf-spaces';text="prose`r`n$signed   `r`n";expected='PASS'},
    @{name='utf8-bom';text=$signed;bom=$true;expected='PASS'}
)
foreach ($case in $verdictCases) {
    $caseDir = Join-Path $testRoot ('verdict-tests/' + $case.name)
    New-Item -ItemType Directory $caseDir -Force | Out-Null
    $stage = if ($case.stage) { $case.stage } else { 'execute' }
    $resultPath = Join-Path $caseDir "$stage.txt"
    [IO.File]::WriteAllText($resultPath, $case.text, [Text.UTF8Encoding]::new([bool]$case.bom))
    if ($case.file) { $case.file | ConvertTo-Json | Set-Content (Join-Path $caseDir "$stage-verdict.json") -Encoding UTF8 }
    if ($case.rawFile) { Set-Content (Join-Path $caseDir "$stage-verdict.json") $case.rawFile -Encoding UTF8 }
    if ($case.executeFile) { $case.executeFile | ConvertTo-Json | Set-Content (Join-Path $caseDir 'execute-verdict.json') -Encoding UTF8 }
    $actual = Get-RunVerdict $caseDir $stage 'verdict-test' $nonce $resultPath
    if ($actual.verdict -cne $case.expected) { throw "Verdict case $($case.name): expected $($case.expected), got $($actual.verdict)" }
}
# Submit all budget shapes through the real input-validation path in TestMode.
# Each gets a fresh order ID; no model process or live observer is launched.
$budgetCases = @(
    @{name='omitted';omit=$true;expected='pending'},
    @{name='empty';budget=@{};expected='pending'},
    @{name='valid';budget=@{max_sources=6;max_searches=8;max_turns=40};expected='pending'},
    @{name='upper-bound';budget=@{max_sources=2147483647};expected='pending'},
    @{name='nonobject-string';budget='6';expected='blocked'},
    @{name='nonobject-array';budget=@(1,2);expected='blocked'},
    @{name='nonobject-number';budget=6;expected='blocked'},
    @{name='nonobject-null';budget=$null;expected='blocked'},
    @{name='nonobject-bool';budget=$true;expected='blocked'}
)
foreach ($field in @('max_sources','max_searches','max_turns')) {
    foreach ($bad in @(@{name='zero';value=0},@{name='negative';value=-1},@{name='overflow';value=2147483648},@{name='bool';value=$true},@{name='string';value='6'},@{name='float';value=1.5},@{name='null';value=$null})) {
        $budget = @{}; $budget[$field] = $bad.value
        $budgetCases += @{name="$field-$($bad.name)";budget=$budget;expected='blocked'}
    }
}
foreach ($case in $budgetCases) {
    $caseId = 'budget-' + $case.name
    $order = @{id=$caseId;status='ready';owner='codex';objective='Test budget validation';acceptance='Test only'}
    if (!$case.omit) { $order.budget = $case.budget }
    $order | ConvertTo-Json -Depth 8 | Set-Content "$testRoot/work/inbox/$caseId.json" -Encoding UTF8
}
& $dispatcherPath -Root $testRoot -TestMode
foreach ($case in $budgetCases) {
    $actual = Get-Content "$testRoot/work/status/budget-$($case.name).json" -Raw | ConvertFrom-Json
    if ($actual.state -ne $case.expected) { throw "Budget case $($case.name): expected $($case.expected), got $($actual.state): $($actual.note)" }
    if ($case.expected -eq 'pending' -and $actual.stage -ne 'review') { throw "Accepted budget did not execute: $($case.name)" }
}
"PASS: syntax, structured paths, task/context prompt, lifecycle, duplicate suppression, invalid input, interrupted run, $($verdictCases.Count) verdict cases, $($budgetCases.Count) budget cases. Observers disabled; isolated mutex. Test artifacts: $testRoot"

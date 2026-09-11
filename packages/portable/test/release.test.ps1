#requires -Version 5.1
$ErrorActionPreference='Stop'
$packageRoot=Split-Path $PSScriptRoot -Parent
$engine=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$testRoot=Join-Path $env:TEMP ('agentos-release-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $testRoot
$downloads=Join-Path $testRoot 'downloads'
& "$packageRoot/build-bundles.ps1" -OutputDirectory $downloads
$version=(Get-Content "$packageRoot/package.json" -Raw|ConvertFrom-Json).version
Add-Type -AssemblyName System.IO.Compression.FileSystem
$manual=Join-Path $testRoot 'manual workspace'
$agent=Join-Path $testRoot 'agent bundle'
[IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $downloads "agentos-manual-$version.zip"),$manual)
[IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $downloads "agentos-agent-setup-$version.zip"),$agent)
foreach($item in @("$manual/LICENSE","$manual/VERSION","$manual/START-HERE.md","$agent/LICENSE","$agent/AGENT-SETUP.md")) {if(!(Test-Path -LiteralPath $item)){throw "Missing $item"}}
# These are executable-path fixtures, not actual provider clients; never launch them as models.
& "$manual/runners/setup.ps1" -CodexPath $engine -ClaudePath $engine -LedgerDirectory (Join-Path $testRoot 'manual ledger')
$guided=Join-Path $testRoot 'guided workspace'
& "$agent/Install-AgentOS.ps1" -Destination $guided -CodexPath $engine -ClaudePath $engine -LedgerDirectory (Join-Path $testRoot 'guided ledger')
$report=& $engine -NoProfile -ExecutionPolicy Bypass -File "$manual/runners/doctor.ps1" -Json
if($LASTEXITCODE -ne 0 -or !($report|ConvertFrom-Json).ok){throw 'Doctor rejected mechanically configured installation.'}
if(($report -join '') -match [regex]::Escape($testRoot)){throw 'Doctor disclosed local paths.'}
$teamPath=Join-Path $manual 'TEAM.md'
(Get-Content -LiteralPath $teamPath -Raw).Replace('Principal: TODO','Principal: Test Principal')|Set-Content -LiteralPath $teamPath -Encoding UTF8
& "$manual/runners/prepare-smoke.ps1" -Principal 'Test Principal' -AuthorizeLocalGreeting
$orders=@(Get-ChildItem -LiteralPath "$manual/tasks" -Recurse -Filter order.json)
if($orders.Count -ne 1 -or @(Get-ChildItem -LiteralPath "$manual/work/inbox" -File).Count -ne 0){throw 'Smoke preparation must create one draft and publish nothing.'}
$order=Get-Content $orders[0].FullName -Raw|ConvertFrom-Json
if($order.objective -notmatch [regex]::Escape($order.id) -or !(Test-Path -LiteralPath (Join-Path $orders[0].DirectoryName 'acceptance.md'))){throw 'Smoke packet invalid.'}
& "$manual/runners/publish-order.ps1" -OrderPath $orders[0].FullName
if(!(Test-Path -LiteralPath "$manual/work/inbox/$($order.id).json")){throw 'Draft publication failed.'}
# Reject bad install paths and preexisting collisions before creating an external ledger.
foreach($case in @('wildcard','collision','hidden-history','overlap','bad-cli')) {
    $dest=Join-Path $testRoot $case
    $ledger=Join-Path $testRoot ($case+'-ledger')
    if($case -eq 'wildcard'){$dest=Join-Path $testRoot 'workspace [brackets]'}
    $null=New-Item -ItemType Directory -Path $dest
    Get-ChildItem -LiteralPath "$packageRoot/template" -Force|Copy-Item -Destination $dest -Recurse
    if($case -eq 'collision'){[IO.File]::WriteAllText((Join-Path $dest 'work'),'preserve')}
    if($case -eq 'hidden-history'){
        $null=New-Item -ItemType Directory -Path (Join-Path $dest 'state')
        $hidden=Join-Path $dest 'state/history.json';[IO.File]::WriteAllText($hidden,'{}');(Get-Item -LiteralPath $hidden).Attributes='Hidden'
    }
    if($case -eq 'overlap'){$ledger=Join-Path $dest 'ledger'}
    $binary=if($case -eq 'bad-cli'){'C:\not-installed\codex.cmd'}else{$engine}
    $before=(Get-FileHash -LiteralPath "$dest/runners/dispatcher.json").Hash
    $rejected=$false
    try {& "$dest/runners/setup.ps1" -CodexPath $binary -ClaudePath $engine -LedgerDirectory $ledger}catch{$rejected=$true}
    if(!$rejected -or (Test-Path -LiteralPath $ledger) -or (Get-FileHash -LiteralPath "$dest/runners/dispatcher.json").Hash -ne $before){throw "Unsafe preflight: $case"}
}
# Missing ledger must be visible as a failure without creating a replacement.
$ledgerFile=Join-Path $testRoot 'manual ledger/ledger.json'
Move-Item -LiteralPath $ledgerFile -Destination ($ledgerFile+'.test-backup')
$report=& $engine -NoProfile -ExecutionPolicy Bypass -File "$manual/runners/doctor.ps1" -Json
if($LASTEXITCODE -ne 1 -or ($report|ConvertFrom-Json).ok -or (Test-Path -LiteralPath $ledgerFile)){throw 'Doctor did not fail closed for missing ledger.'}
# Run the complete runtime suite from the actual agent-assisted installed download.
& $engine -NoProfile -ExecutionPolicy Bypass -File "$guided/runners/test-all.ps1"
if($LASTEXITCODE -ne 0){throw 'Installed runtime suite failed.'}
& $engine -NoProfile -ExecutionPolicy Bypass -File "$agent/test/install.test.ps1"
if($LASTEXITCODE -ne 0){throw 'Guided overwrite-preservation checks failed.'}
Write-Output "PASS: both extracted install paths, license/version, diagnostics, smoke draft/publish, preservation and runtime checks. No real model/scheduler calls. Evidence: $testRoot"

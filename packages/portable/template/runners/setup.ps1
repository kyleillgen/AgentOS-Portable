#requires -Version 5.1
param(
    [string]$Root=(Split-Path $PSScriptRoot -Parent),
    [Parameter(Mandatory)][string]$CodexPath,
    [Parameter(Mandatory)][string]$ClaudePath,
    [Parameter(Mandatory)][string]$LedgerDirectory
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'paths.ps1')
$Root=Get-AgentOSLocalPath $Root
$LedgerDirectory=Get-AgentOSLocalPath $LedgerDirectory
Assert-AgentOSSeparatePaths $Root $LedgerDirectory
foreach($cli in @($CodexPath,$ClaudePath)) {
    Assert-AgentOSBinary $cli
}
$configPath=Join-Path $Root 'runners/dispatcher.json'
$setupLock=$null
try {
try { $setupLock=[IO.File]::Open($configPath+'.setup-lock','OpenOrCreate','ReadWrite','None') }
catch { throw 'Another setup may be running, or the configuration folder is not writable.' }
$cfg=Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json
if($cfg.host -ne 'CONFIGURE_WITH_SETUP' -or $cfg.run_ledger) { throw 'Existing configuration preserved. Setup only initializes a fresh starter workspace.' }
foreach($relative in @('work','state')) {
    $path=Join-Path $Root $relative
    if((Test-Path -LiteralPath $path) -and @(Get-ChildItem -LiteralPath $path -Recurse -File -Force).Count) { throw 'Existing runtime records found. Never initialize an empty ledger over prior work.' }
}
if(Test-Path -LiteralPath ($configPath+'.before-setup')) { throw 'A previous setup backup exists. Inspect the preserved installation before continuing.' }
foreach($relative in @('work','state','work/inbox','work/status','work/receipts','work/results','work/handoffs')) {
    $path=Join-Path $Root $relative
    if((Test-Path -LiteralPath $path) -and !(Test-Path -LiteralPath $path -PathType Container)) { throw "A file occupies the required directory $relative. Choose a fresh extraction; no ledger was created." }
    $null=Get-AgentOSLocalPath $path
}
if(Test-Path -LiteralPath $LedgerDirectory) { throw 'Ledger destination must be a new directory; existing state is never replaced.' }
$parent=Split-Path $LedgerDirectory -Parent
if(!(Test-Path -LiteralPath $parent -PathType Container)) { throw 'Ledger parent directory must already exist.' }
$null=New-Item -ItemType Directory -Path $LedgerDirectory -ErrorAction Stop
$utf8=[Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText((Join-Path $LedgerDirectory 'ledger.json'),(@{schema=1;root=$Root;orders=@{}}|ConvertTo-Json -Depth 10),$utf8)
$cfg.host=$env:COMPUTERNAME
$cfg.codex=[IO.Path]::GetFullPath($CodexPath)
$cfg.claude=[IO.Path]::GetFullPath($ClaudePath)
$cfg.run_ledger=$LedgerDirectory
foreach($relative in @('work/inbox','work/status','work/receipts','work/results','work/handoffs','state')) { New-Item -ItemType Directory -Path (Join-Path $Root $relative) -Force|Out-Null }
[IO.File]::WriteAllText($configPath+'.setup-new',($cfg|ConvertTo-Json -Depth 10),$utf8)
[IO.File]::Replace($configPath+'.setup-new',$configPath,$configPath+'.before-setup')
Write-Output 'Configured. No models launched and no scheduled task installed. Follow runners/README.md for the smoke test.'
} finally { if($setupLock){$setupLock.Dispose()} }

#requires -Version 5.1
param(
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$CodexPath,
    [Parameter(Mandatory)][string]$ClaudePath,
    [Parameter(Mandatory)][string]$LedgerDirectory
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'template/runners/paths.ps1')
$Destination=Get-AgentOSLocalPath $Destination
$LedgerDirectory=Get-AgentOSLocalPath $LedgerDirectory
Assert-AgentOSSeparatePaths $Destination $LedgerDirectory
foreach($binary in @($CodexPath,$ClaudePath)) { Assert-AgentOSBinary $binary }
if(Test-Path -LiteralPath $LedgerDirectory) { throw 'Ledger destination already exists. Choose a new folder.' }
if(!(Test-Path -LiteralPath (Split-Path $LedgerDirectory -Parent) -PathType Container)) { throw 'Ledger parent must exist.' }
if(Test-Path -LiteralPath $Destination) { throw 'Destination exists. Choose a new folder; existing work is never overwritten.' }
if(!(Test-Path -LiteralPath (Split-Path $Destination -Parent) -PathType Container)) { throw 'Destination parent must exist.' }
New-Item -ItemType Directory -Path $Destination|Out-Null
Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'template') -Force | Copy-Item -Destination $Destination -Recurse
& (Join-Path $Destination 'runners/setup.ps1') -Root $Destination -CodexPath $CodexPath -ClaudePath $ClaudePath -LedgerDirectory $LedgerDirectory
Write-Output "Workspace: $Destination. Configure TEAM.md and follow FIRST-RUN.md for diagnostics and the greeting workflow."

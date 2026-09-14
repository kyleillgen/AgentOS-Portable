#requires -Version 5.1
param(
    [Parameter(Mandatory)][string]$Destination,
    [Parameter(Mandatory)][string]$CodexPath,
    [Parameter(Mandatory)][string]$ClaudePath,
    [Parameter(Mandatory)][string]$LedgerDirectory
)
# IAF-branded entry point; retain the original implementation for compatibility.
$ErrorActionPreference='Stop'
$global:LASTEXITCODE=0
& (Join-Path $PSScriptRoot 'Install-AgentOS.ps1') @PSBoundParameters
exit $LASTEXITCODE

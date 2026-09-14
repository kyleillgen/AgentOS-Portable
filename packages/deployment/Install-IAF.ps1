#requires -Version 5.1
param(
    [Parameter(Mandatory)][string]$Destination,
    [ValidateSet('Manual','Automated','Unattended')][string]$Profile='Manual',
    [switch]$Desk,
    [string]$CodexPath,[string]$ClaudePath,[string]$LocalStateDirectory,[string]$PythonPath
)
# IAF-branded entry point; legacy implementation and state formats stay compatible.
$ErrorActionPreference='Stop'
$global:LASTEXITCODE=0
& (Join-Path $PSScriptRoot 'Install-AgentOS.ps1') @PSBoundParameters
exit $LASTEXITCODE

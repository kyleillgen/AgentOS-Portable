#requires -Version 5.1
param(
    [ValidateSet('Doctor','Run','Check','Snapshot','Desk','Enable','Disable','RemoveDesk','Uninstall')][string]$Action='Doctor',
    [string]$Root=$PSScriptRoot,[PSCredential]$Credential,[switch]$Json,
    [ValidateRange(1024,65535)][int]$Port=8765
)
# IAF-branded entry point; legacy implementation and state formats stay compatible.
$ErrorActionPreference='Stop'
$global:LASTEXITCODE=0
& (Join-Path $PSScriptRoot 'AgentOS.ps1') @PSBoundParameters
exit $LASTEXITCODE

#requires -Version 5.1
$ErrorActionPreference='Stop'
$package=Split-Path $PSScriptRoot -Parent
$engine=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('iaf-alias-tests-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $fixture
$destination=Join-Path $fixture 'workspace with spaces'
$ledger=Join-Path $fixture 'ledger'
$arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $package 'Install-IAF.ps1'),'-Destination',$destination,'-CodexPath',$engine,'-ClaudePath',$engine,'-LedgerDirectory',$ledger)
& $engine @arguments | Out-Null
if($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath (Join-Path $destination 'runners/dispatcher.json'))){throw 'IAF installer alias did not configure the fixture.'}
$before=(Get-FileHash -LiteralPath (Join-Path $destination 'TEAM.md')).Hash
$prior=$ErrorActionPreference
try{$ErrorActionPreference='Continue';& $engine @arguments *> $null;$rejected=$LASTEXITCODE}finally{$ErrorActionPreference=$prior}
if($rejected -eq 0){throw 'IAF installer alias swallowed duplicate-install failure.'}
if((Get-FileHash -LiteralPath (Join-Path $destination 'TEAM.md')).Hash -ne $before){throw 'Duplicate install changed the fixture.'}
Write-Output 'PASS: IAF installer alias preserves arguments, successful setup, nonzero failure and existing files. No provider calls.'
# GitHub's PowerShell wrapper exits with LASTEXITCODE; the refusal above was expected.
$global:LASTEXITCODE=0

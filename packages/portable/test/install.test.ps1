$ErrorActionPreference='Stop'
$packageRoot=Split-Path $PSScriptRoot -Parent
$temp=Join-Path $env:TEMP ('agentos-guided-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $temp|Out-Null
$dest=Join-Path $temp 'guided workspace'
$ledger=Join-Path $temp 'guided ledger'
$binary=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
& "$packageRoot/Install-AgentOS.ps1" -Destination $dest -CodexPath $binary -ClaudePath $binary -LedgerDirectory $ledger
foreach($path in @('AGENTS.md','runners/dispatcher.ps1','runners/README.md','runners/test-all.ps1','.gitignore')) {
    if((Get-FileHash (Join-Path $dest $path)).Hash -ne (Get-FileHash (Join-Path "$packageRoot/template" $path)).Hash) { throw "Template mismatch: $path" }
}
if((Get-Content "$dest/runners/dispatcher.json" -Raw|ConvertFrom-Json).run_ledger -ne [IO.Path]::GetFullPath($ledger)) { throw 'Guided configuration not set' }
$rejected=$false
try { & "$packageRoot/Install-AgentOS.ps1" -Destination $dest -CodexPath $binary -ClaudePath $binary -LedgerDirectory $ledger } catch { $rejected=$true }
if(!$rejected) { throw 'Guided installer overwrote existing directory' }
# Users run these checks AFTER setup, so verify the suite's setup fixture works from configured source.
& "$dest/runners/test-setup.ps1"
'PASS: agent-assisted entrypoint copies the same template, configures the common setup, preserves an existing workspace, and tests work after installation.'

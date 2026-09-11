#requires -Version 5.1
$ErrorActionPreference='Stop'
$engine=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$tests=@('test-setup.ps1','test-dispatcher.ps1','test-run-ledger.ps1','test-telemetry.ps1','test-cost-lock.ps1','test-dispatcher-runtime.ps1','test-process-runtime.ps1','test-monitor.ps1','test-monitor-io.ps1')
foreach($test in $tests) {
    Write-Output "Running $test"
    & $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot $test)
    if($LASTEXITCODE -ne 0) { throw "Failed: $test" }
}
Write-Output 'PASS: all portable dispatcher tests. Live model and scheduled-context smoke checks are separate.'

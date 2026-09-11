param([string]$OutputDirectory = (Join-Path $env:TEMP ('agentos-process-tests-' + [guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'process-runtime.ps1')
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$engine = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$cases = @(
    @{ Name='early-stdin-failure'; Code='[Console]::Out.Write("early-exit"); exit 0'; Input=('x' * 2000000); Timeout=60000; MaxSeconds=12; Exit=$null; Failure='process_io_error:*'; Contains='early-exit' },
    @{ Name='normal'; Code='$text=[Console]::In.ReadToEnd(); [Console]::Out.Write("echo:"+$text); [Console]::Error.Write("warning")'; Input='hello'; Timeout=15000; Exit=0; Failure=$null; Contains='echo:hello' },
    @{ Name='nonzero'; Code='[Console]::Out.Write("failed-output"); exit 7'; Input=''; Timeout=15000; Exit=7; Failure='nonzero_exit'; Contains='failed-output' },
    @{ Name='hanging-stdin'; Code='[Console]::Out.Write("before-input-hang"); [Console]::Out.Flush(); Start-Sleep -Seconds 30'; Input=('x' * 2000000); Timeout=6000; Exit=$null; Failure='timeout'; Contains='before-input-hang' },
    @{ Name='partial-timeout'; Code='[Console]::Out.Write("partial-out"); [Console]::Out.Flush(); [Console]::Error.Write("partial-err"); [Console]::Error.Flush(); Start-Sleep -Seconds 30'; Input=''; Timeout=6000; Exit=$null; Failure='timeout'; Contains='partial-out' },
    @{ Name='descendant-held-pipes'; Code='$p=New-Object Diagnostics.ProcessStartInfo; $p.FileName=$env:SystemRoot+"\System32\cmd.exe"; $p.Arguments="/c ping -n 15 127.0.0.1 >nul"; $p.UseShellExecute=$false; $p.CreateNoWindow=$true; [Diagnostics.Process]::Start($p)|Out-Null; [Console]::Out.Write("parent-done")'; Input=''; Timeout=6000; Exit=$null; Failure='timeout'; Contains='parent-done' }
)
$results = foreach ($case in $cases) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $engine
    $info.Arguments = '-NoLogo -NoProfile -NonInteractive -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($case.Code))
    $outPath = Join-Path $OutputDirectory ($case.Name + '-stdout.txt')
    $errPath = Join-Path $OutputDirectory ($case.Name + '-stderr.txt')
    $result = Invoke-AgentProcess -ProcessStartInfo $info -InputText $case.Input -TimeoutMilliseconds $case.Timeout -StdoutPath $outPath -StderrPath $errPath
    if ($result.failure_reason -notlike $case.Failure) { throw "$($case.Name): unexpected failure $($result.failure_reason)" }
    if ($case.ContainsKey('MaxSeconds') -and $result.duration_s -gt $case.MaxSeconds) { throw "$($case.Name): early failure exceeded cleanup grace: $($result.duration_s)" }
    if ($null -ne $case.Exit -and $result.exit_code -ne $case.Exit) { throw "$($case.Name): wrong exit" }
    if ($result.duration_s -gt ($case.Timeout / 1000 + 4.5)) { throw "$($case.Name): exceeded bounded timeout: $($result.duration_s)" }
    if (![IO.File]::ReadAllText($outPath).Contains($case.Contains)) { throw "$($case.Name): partial output missing; bytes=$([Convert]::ToBase64String([IO.File]::ReadAllBytes($outPath)))" }
    if ($case.Name -eq 'partial-timeout' -and ![IO.File]::ReadAllText($errPath).Contains('partial-err')) { throw 'Partial stderr missing' }
    [pscustomobject]@{name=$case.Name; pass=$true; result=$result}
}
$results | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutputDirectory 'results.json') -Encoding UTF8
$results | Format-Table name,pass,@{n='seconds';e={$_.result.duration_s}},@{n='cleanup';e={$_.result.cleanup_status}}
Write-Output "Evidence: $OutputDirectory"

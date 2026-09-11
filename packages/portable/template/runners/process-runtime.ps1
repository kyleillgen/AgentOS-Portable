# Dot-source safe. Windows PowerShell 5.1 / .NET Framework compatible.
function Invoke-AgentProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][Diagnostics.ProcessStartInfo]$ProcessStartInfo,
        [AllowEmptyString()][string]$InputText = '',
        [Parameter(Mandatory=$true)][ValidateRange(100,2147483647)][int]$TimeoutMilliseconds,
        [Parameter(Mandatory=$true)][string]$StdoutPath,
        [Parameter(Mandatory=$true)][string]$StderrPath
    )
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $cleanupDeadline = [long]$TimeoutMilliseconds + 3000
    $workDeadline = $TimeoutMilliseconds
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $ProcessStartInfo
    $ProcessStartInfo.UseShellExecute = $false
    $ProcessStartInfo.CreateNoWindow = $true
    $ProcessStartInfo.RedirectStandardInput = $true
    $ProcessStartInfo.RedirectStandardOutput = $true
    $ProcessStartInfo.RedirectStandardError = $true
    $outFile = $null; $errFile = $null; $killProcess = $null
    $exitCode = $null; $failure = $null; $cleanup = 'not_needed'; $started = $false
    $inputClosed = $false; $outTask = $null; $errTask = $null; $inputTask = $null
    try {
        $outFile = [IO.FileStream]::new($StdoutPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::Read, 4096, $true)
        $errFile = [IO.FileStream]::new($StderrPath, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::Read, 4096, $true)
        $started = $process.Start()
        if (!$started) { throw 'Runner process did not start.' }
        # Copy bytes directly to files: timeout paths retain output already received.
        $outTask = $process.StandardOutput.BaseStream.CopyToAsync($outFile)
        $errTask = $process.StandardError.BaseStream.CopyToAsync($errFile)
        $inputBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($InputText)
        $inputTask = $process.StandardInput.BaseStream.WriteAsync($inputBytes, 0, $inputBytes.Length)
        while ($watch.ElapsedMilliseconds -lt $workDeadline) {
            if ($inputTask.IsCompleted -and !$inputClosed) {
                if ($inputTask.IsFaulted -or $inputTask.IsCanceled) { throw 'Runner stdin write failed.' }
                $process.StandardInput.BaseStream.Close()
                $inputClosed = $true
            }
            if ($outTask.IsFaulted -or $errTask.IsFaulted -or $outTask.IsCanceled -or $errTask.IsCanceled) { throw 'Runner output capture failed.' }
            if ($process.HasExited -and $inputClosed -and $outTask.IsCompleted -and $errTask.IsCompleted) {
                $exitCode = $process.ExitCode
                if ($exitCode -ne 0) { $failure = 'nonzero_exit' }
                break
            }
            [Threading.Thread]::Sleep([Math]::Min(10, [Math]::Max(1, $workDeadline - $watch.ElapsedMilliseconds)))
        }
        if ($null -eq $exitCode) { Write-Verbose ("deadline: root={0} stdin={1} stdout={2} stderr={3}" -f $process.HasExited, $inputTask.Status, $outTask.Status, $errTask.Status); $failure = 'timeout' }
    }
    catch { $failure = 'process_io_error: ' + $_.Exception.Message }
    finally {
        if ($started -and $null -ne $failure -and $failure -ne 'nonzero_exit') {
            $cleanup = 'unconfirmed'
            $cleanupDeadline = [Math]::Min($cleanupDeadline, $watch.ElapsedMilliseconds + 3000)
            # taskkill itself is a child with a bounded wait, never a synchronous shell call.
            try {
                if (!$process.HasExited -and $watch.ElapsedMilliseconds -lt $cleanupDeadline) {
                    $killInfo = New-Object Diagnostics.ProcessStartInfo
                    $killInfo.FileName = Join-Path $env:SystemRoot 'System32\taskkill.exe'
                    $killInfo.Arguments = '/PID ' + $process.Id + ' /T /F'
                    $killInfo.UseShellExecute = $false
                    $killInfo.CreateNoWindow = $true
                    $killProcess = New-Object Diagnostics.Process
                    $killProcess.StartInfo = $killInfo
                    if ($killProcess.Start()) {
                        $remaining = [Math]::Max(0, $cleanupDeadline - $watch.ElapsedMilliseconds)
                        if (!$killProcess.WaitForExit([int]$remaining)) { try { $killProcess.Kill() } catch {} }
                    }
                }
                while ($watch.ElapsedMilliseconds -lt $cleanupDeadline) {
                    if ($process.HasExited -and $outTask.IsCompleted -and $errTask.IsCompleted) { $cleanup = 'root_exited_streams_closed'; break }
                    [Threading.Thread]::Sleep(5)
                }
                if ($process.HasExited) { $exitCode = $process.ExitCode }
            } catch { $cleanup = 'unconfirmed' }
        }
        # Closing pipe handles cancels pending local I/O; do not wait on unfinished tasks.
        if ($started) {
            try { $process.StandardInput.BaseStream.Dispose() } catch {}
            try { $process.StandardOutput.BaseStream.Dispose() } catch {}
            try { $process.StandardError.BaseStream.Dispose() } catch {}
        }
        if ($null -ne $outFile) { $outFile.Dispose() }
        if ($null -ne $errFile) { $errFile.Dispose() }
        if ($null -ne $killProcess) { $killProcess.Dispose() }
        $process.Dispose()
        $watch.Stop()
    }
    [pscustomobject]@{
        exit_code = $exitCode
        failure_reason = $failure
        duration_s = [Math]::Round($watch.Elapsed.TotalSeconds, 3)
        cleanup_status = $cleanup
        timed_out = ($failure -eq 'timeout')
    }
}

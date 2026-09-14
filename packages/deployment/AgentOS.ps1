#requires -Version 5.1
param(
    [ValidateSet('Doctor','Run','Check','Snapshot','Desk','Enable','Disable','RemoveDesk','Uninstall')][string]$Action='Doctor',
    [string]$Root=$PSScriptRoot,[PSCredential]$Credential,[switch]$Json,
    [ValidateRange(1024,65535)][int]$Port=8765
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'deployment-common.ps1')
$receipt=Read-Installation $Root
$Root=$receipt.root
$registry=if($receipt.local_state){Join-Path $receipt.local_state 'operations'}else{$null}
function Require-Module([string]$Name){if($receipt.modules -notcontains $Name){throw "The $Name package is not installed. See FIRST-RUN.md for profile choices."}}
$managementLock=$null
try{
if($Action -in @('Enable','Disable','RemoveDesk','Uninstall')){
    try{$managementLock=[IO.File]::Open((Join-Path $Root 'agentos-management.lock'),'OpenOrCreate','ReadWrite','None')}catch [IO.IOException]{throw 'Another installation management action is running.'}
    $receipt=Read-Installation $Root
}
switch($Action){
    'Doctor'{
        $checks=New-Object 'Collections.Generic.List[object]'
        function Check([string]$Name,[string]$Status,[string]$Detail){$checks.Add([pscustomobject]@{check=$Name;status=$Status;detail=$Detail})}
        Check 'installation' $(if($receipt.status -in @('installation_failed','installing','activating')){'FAIL'}else{'PASS'}) ($receipt.profile+' / '+$receipt.status)
        foreach($file in $receipt.files){
            $path=Get-OwnedPath $Root $file.path
            if(!(Test-Path -LiteralPath $path -PathType Leaf)){Check $file.path 'FAIL' 'Package file missing.';continue}
            if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $file.sha256){
                Check $file.path $(if($file.module -eq 'base' -or $file.path -eq 'runners/dispatcher.json'){'WARN'}else{'FAIL'}) 'Changed since installation; inspect before restoring.'
            }
        }
        if($receipt.modules -contains 'runner'){
            if($receipt.host -ine $env:COMPUTERNAME){Check 'host' 'FAIL' 'Configured for a different machine.'}
            $engine=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
            $raw=& $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'runners/doctor.ps1') -Root $Root -Json
            try{$runner=$raw|ConvertFrom-Json;foreach($check in $runner.checks){$checks.Add($check)}}catch{Check 'runner' 'FAIL' 'Runner diagnostics could not be read.'}
        }
        if($receipt.modules -contains 'operations'){
            if(!(Test-Path -LiteralPath $receipt.python -PathType Leaf)){Check 'python' 'FAIL' 'Configured Python is missing.'}
            foreach($healthName in @('checker-health.json','watchdog.json')){
                try{
                    $health=Get-Content -LiteralPath (Join-Path $registry $healthName) -Raw|ConvertFrom-Json
                    $stamp=if($healthName -eq 'watchdog.json'){$health.observed_at}else{$health.last_success_at}
                    $age=([DateTimeOffset]::UtcNow-[DateTimeOffset]::Parse($stamp)).TotalSeconds
                    $limit=if($healthName -eq 'watchdog.json'){30}else{360}
                    if($age -lt -5 -or $age -gt $limit -or $health.error -or ($healthName -eq 'watchdog.json' -and !$health.healthy)){throw 'Health is stale or reports a failure.'}
                    Check $healthName 'PASS' 'Recent successful health evidence.'
                }catch{Check $healthName $(if($receipt.status -eq 'active'){'FAIL'}else{'WARN'}) 'No current healthy background evidence. Run Check or activate Unattended.'}
            }
        }
        if($receipt.profile -eq 'Unattended'){
            foreach($spec in Get-DeploymentTasks $receipt){
                try{
                    $task=Find-DeploymentTask $spec.name
                    if(!$task){throw 'Not registered.'}
                    Assert-TaskOwner $task $spec
                    if($task.State -ne 'Running' -or !$task.Settings.Enabled){throw 'Task is not enabled and running.'}
                    Check $spec.name 'PASS' 'Registered action matches and Windows reports running.'
                }catch{Check $spec.name $(if($receipt.status -eq 'active'){'FAIL'}else{'WARN'}) 'Not verified running. Use Enable after foreground verification; inspect Windows Task Scheduler if activation fails.'}
            }
        }
        Check 'receiving-machine verification' 'NOT_TESTED' 'These checks do not establish provider login, actual account access, reboot, signed-out use or cloud delivery.'
        $result=[pscustomobject]@{schema=1;ok=(@($checks|Where-Object status -eq 'FAIL').Count -eq 0);profile=$receipt.profile;status=$receipt.status;modules=$receipt.modules;checks=@($checks.ToArray())}
        if($Json){$result|ConvertTo-Json -Depth 7}else{$checks|Format-Table -AutoSize -Wrap}
        if(!$result.ok){exit 1}
    }
    'Run'{
        Require-Module 'runner'
        if(Test-Path -LiteralPath (Join-Path $Root 'state/monitor.stop')){throw 'Graceful stop is active. Inspect prior work before removing state/monitor.stop to resume.'}
        & (Join-Path $Root 'runners/monitor.ps1') -Root $Root
    }
    'Check'{Require-Module 'operations'; & $receipt.python -E -s (Join-Path $Root 'extensions/operations/operations_service.py') --root $Root --registry $registry --once; if($LASTEXITCODE){exit $LASTEXITCODE}}
    'Snapshot'{Require-Module 'operations'; & $receipt.python -E -s (Join-Path $Root 'extensions/operations/operations_service.py') --root $Root --registry $registry --snapshot; if($LASTEXITCODE){exit $LASTEXITCODE}}
    'Desk'{Require-Module 'desk'; & $receipt.python -E -s (Join-Path $Root 'extensions/desk/operations_desk.py') --root $Root --registry $registry --port $Port; if($LASTEXITCODE){exit $LASTEXITCODE}}
    'Enable'{Enable-Deployment $receipt $Credential;Write-Output 'Windows activation requested for runner, checker and watchdog. Run Doctor to verify current health. Reboot and signed-out execution require separate verification.'}
    'Disable'{Disable-Deployment $receipt;Write-Output 'Background registrations removed after graceful runner stop. Files and records retained.'}
    {$_ -in @('RemoveDesk','Uninstall')}{
        if($Action -eq 'RemoveDesk'){Require-Module 'desk';$remove=@('desk')}
        else{Disable-Deployment $receipt;$remove=@('runner','operations','desk')}
        if($receipt.modules -contains 'desk'){
            Set-Content -LiteralPath (Join-Path $registry 'interface.stop') -Value 'Interface removal requested.' -Encoding UTF8
            $deadline=[DateTime]::UtcNow.AddSeconds(10)
            do{
                $stream=$null;$busy=$false
                try{$stream=[IO.File]::Open((Join-Path $registry 'interface.lock'),'OpenOrCreate','ReadWrite','None')}catch [IO.IOException]{$busy=$true}finally{if($stream){$stream.Dispose()}}
                if(!$busy){break};Start-Sleep -Milliseconds 250
            }while([DateTime]::UtcNow -lt $deadline)
            if($busy){throw 'The interface has not stopped yet. Its files were preserved; retry after it retires.'}
        }
        $preserved=@();$remaining=@()
        foreach($file in $receipt.files){
            if($remove -notcontains $file.module -or $file.path -eq 'runners/dispatcher.json'){$remaining+=$file;continue}
            $path=Get-OwnedPath $Root $file.path
            if(Test-Path -LiteralPath $path){
                if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $file.sha256){$preserved+=$file.path;$remaining+=$file;continue}
                Remove-Item -LiteralPath $path -ErrorAction Stop
            }
        }
        $receipt.files=$remaining
        $receipt.modules=@($receipt.modules|Where-Object {$remove -notcontains $_})
        if($Action -eq 'Uninstall'){$receipt.profile='Manual';$receipt.status='automation_removed'}
        Write-DeploymentJson (Join-Path $Root 'agentos-installation.json') $receipt
        if($preserved.Count){Write-Warning ('Modified files preserved: '+($preserved -join ', '))}
        Write-Output 'Selected package files removed. Base workspace, tasks, reports, recovery journal, configuration and protected ledger retained.'
    }
}
}finally{if($managementLock){$managementLock.Dispose()}}

# Deployment ownership and scheduling. No work-order execution logic lives here.
function Get-DeploymentPath([string]$Path){
    if([string]::IsNullOrWhiteSpace($Path) -or $Path -notmatch '^[A-Za-z]:[\\/]'){throw 'Use an absolute local drive folder.'}
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    if($full.Length -le 2 -or $full.IndexOfAny([char[]]'[]*?"') -ge 0){throw 'Choose a dedicated ordinary folder; spaces are supported.'}
    $ancestor=$full
    while($ancestor){
        if((Test-Path -LiteralPath $ancestor) -and ((Get-Item -LiteralPath $ancestor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Deployment paths cannot traverse links or junctions.'}
        $ancestor=Split-Path $ancestor -Parent
    }
    return $full
}
function Assert-SeparateDeploymentPaths([string]$Left,[string]$Right){
    if($Left.Equals($Right,[StringComparison]::OrdinalIgnoreCase) -or $Left.StartsWith($Right+'\',[StringComparison]::OrdinalIgnoreCase) -or $Right.StartsWith($Left+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Workspace and local state must be separate; neither may contain the other.'}
}
function Assert-DeploymentBinary([string]$Path){
    if(!$Path -or ![IO.Path]::IsPathRooted($Path) -or [IO.Path]::GetExtension($Path) -ine '.exe' -or !(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'Supply absolute paths to real .exe files. No command or PowerShell shims.'}
}
function Get-OwnedPath([string]$Root,[string]$Relative){
    if(!$Relative -or $Relative -match '(^|/|\\)\.\.($|/|\\)|:|^[/\\]' -or $Relative.IndexOfAny([char[]]'[]*?"') -ge 0){throw 'Invalid package-owned path.'}
    $base=[IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $path=[IO.Path]::GetFullPath((Join-Path $base $Relative))
    if(!$path.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Package path escapes the installation.'}
    $null=Get-DeploymentPath $path
    return $path
}
function Write-DeploymentJson([string]$Path,$Value){
    $temp=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    try{
        [IO.File]::WriteAllText($temp,($Value|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
        if(Test-Path -LiteralPath $Path){[IO.File]::Replace($temp,$Path,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$Path)}
    }finally{if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp}}
}
function Read-Installation([string]$Root){
    $Root=Get-DeploymentPath $Root
    $receipt=Get-Content -LiteralPath (Join-Path $Root 'agentos-installation.json') -Raw|ConvertFrom-Json
    if($receipt.schema -ne 1 -or $receipt.root -ine $Root -or $receipt.id -notmatch '^[a-f0-9]{32}$'){throw 'Installation receipt is invalid or belongs to another folder.'}
    if($receipt.local_state){$local=Get-DeploymentPath $receipt.local_state;Assert-SeparateDeploymentPaths $Root $local}
    return $receipt
}
function Get-DeploymentTasks($Receipt){
    $prefix='AgentOS-'+$Receipt.id.Substring(0,12)
    $engine=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $root=$Receipt.root
    $registry=Join-Path $Receipt.local_state 'operations'
    @(
        [pscustomobject]@{name=$prefix+'-Checker';execute=$Receipt.python;arguments='-E -s "'+(Join-Path $root 'extensions/operations/operations_service.py')+'" --root "'+$root+'" --registry "'+$registry+'"'}
        [pscustomobject]@{name=$prefix+'-Watchdog';execute=$Receipt.python;arguments='-E -s "'+(Join-Path $root 'extensions/operations/operations_health.py')+'" --root "'+$root+'" --registry "'+$registry+'"'}
        [pscustomobject]@{name=$prefix+'-Runner';execute=$engine;arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+(Join-Path $root 'extensions/operations/run-monitor.ps1')+'" -Root "'+$root+'"'}
    )
}
function Assert-TaskOwner($Task,$Spec){
    if(@($Task.Actions).Count -ne 1 -or $Task.Actions.Execute -ine $Spec.execute -or $Task.Actions.Arguments -cne $Spec.arguments){throw "Scheduled task ownership mismatch: $($Spec.name). Nothing was changed."}
}
function Find-DeploymentTask([string]$Name){
    # Enumerate readably and filter locally: access denied must never mean absent.
    $matches=@(Get-ScheduledTask -ErrorAction Stop|Where-Object {$_.TaskName -eq $Name -and $_.TaskPath -eq '\'})
    if($matches.Count -gt 1){throw 'Ambiguous Windows task ownership.'}
    if($matches.Count){return $matches[0]}
    return $null
}
function Enable-Deployment($Receipt,[PSCredential]$Credential){
    if($Receipt.profile -ne 'Unattended' -or $Receipt.status -notin @('configured','disabled','active')){throw 'Only a configured Unattended profile can be activated.'}
    if($Receipt.host -ine $env:COMPUTERNAME){throw 'This is not the configured host.'}
    if(!$Credential){throw 'Supply -Credential (Get-Credential) locally. Passwords are never written to configuration.'}
    $specs=@(Get-DeploymentTasks $Receipt)
    foreach($spec in $specs){
        if(Find-DeploymentTask $spec.name){throw 'An installation task already exists. Run Doctor or Disable; activation never replaces existing registrations.'}
    }
    $created=@()
    $Receipt.status='activating'
    Write-DeploymentJson (Join-Path $Receipt.root 'agentos-installation.json') $Receipt
    try{
        foreach($spec in $specs){
            $action=New-ScheduledTaskAction -Execute $spec.execute -Argument $spec.arguments -WorkingDirectory $Receipt.root
            $trigger=New-ScheduledTaskTrigger -AtStartup
            $settings=New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
            Register-ScheduledTask -TaskName $spec.name -TaskPath '\' -Action $action -Trigger $trigger -Settings $settings -User $Credential.UserName -Password $Credential.GetNetworkCredential().Password -RunLevel Limited -ErrorAction Stop | Out-Null
            $created+=$spec
            $registered=Find-DeploymentTask $spec.name
            if(!$registered){throw 'Registered task is absent on readback.'}
            Assert-TaskOwner $registered $spec
            if($registered.Principal.LogonType -ne 'Password' -or $registered.Settings.ExecutionTimeLimit -ne 'PT0S' -or !$registered.Settings.Enabled){throw 'Registration settings failed readback.'}
        }
        $marker=Join-Path $Receipt.root 'state/monitor.stop'
        if(Test-Path -LiteralPath $marker){Remove-Item -LiteralPath $marker}
        foreach($spec in $specs){Start-ScheduledTask -TaskName $spec.name -TaskPath '\' -ErrorAction Stop}
    }catch{
        # If a start partially succeeded, use the same graceful retirement path.
        # A live worker blocks rollback rather than being terminated.
        Disable-Deployment $Receipt
        throw
    }
    $Receipt.tasks=$specs;$Receipt.status='active'
    Write-DeploymentJson (Join-Path $Receipt.root 'agentos-installation.json') $Receipt
}
function Disable-Deployment($Receipt){
    $specs=if($Receipt.profile -eq 'Unattended' -and ($Receipt.status -in @('active','activating') -or @($Receipt.tasks).Count)){@(Get-DeploymentTasks $Receipt)}else{@()}
    foreach($spec in $specs){$task=Find-DeploymentTask $spec.name;if($task){Assert-TaskOwner $task $spec}}
    if($Receipt.modules -contains 'runner'){
        # Request a graceful stop. Never terminate a producer to uninstall software.
        Set-Content -LiteralPath (Join-Path $Receipt.root 'state/monitor.stop') -Value 'Deployment disabled by operator.' -Encoding UTF8
        $deadline=[DateTime]::UtcNow.AddSeconds(30)
        do{
            $busy=$false
            foreach($lockName in @('monitor.lock','dispatcher.lock')){
                $stream=$null
                try{$stream=[IO.File]::Open((Join-Path $Receipt.root ('state/'+$lockName)),'OpenOrCreate','ReadWrite','None')}catch [IO.IOException]{$busy=$true}finally{if($stream){$stream.Dispose()}}
            }
            if(!$busy){break}
            Start-Sleep -Milliseconds 250
        }while([DateTime]::UtcNow -lt $deadline)
        if($busy){throw 'A runner is still finishing work. Stop was requested; wait for it, then run Disable again. No worker was killed.'}
    }
    foreach($spec in $specs){
        $task=Find-DeploymentTask $spec.name
        if($task){Assert-TaskOwner $task $spec;Stop-ScheduledTask -TaskName $spec.name -TaskPath '\' -ErrorAction Stop;Unregister-ScheduledTask -TaskName $spec.name -TaskPath '\' -Confirm:$false -ErrorAction Stop}
    }
    $Receipt.tasks=@();$Receipt.status='disabled'
    Write-DeploymentJson (Join-Path $Receipt.root 'agentos-installation.json') $Receipt
}

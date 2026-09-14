#requires -Version 5.1
param(
    [Parameter(Mandatory)][string]$Destination,
    [ValidateSet('Manual','Automated','Unattended')][string]$Profile='Manual',
    [switch]$Desk,
    [string]$CodexPath,[string]$ClaudePath,[string]$LocalStateDirectory,[string]$PythonPath
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'deployment-common.ps1')
$Destination=Get-DeploymentPath $Destination
if(Test-Path -LiteralPath $Destination){throw 'Destination exists. Existing workspaces are preserved; choose a new folder.'}
if(!(Test-Path -LiteralPath (Split-Path $Destination -Parent) -PathType Container)){throw 'Destination parent must exist.'}
$spec=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'package.json') -Raw|ConvertFrom-Json
if($Desk -and $Profile -eq 'Manual'){throw 'Desk requires an Automated or Unattended profile.'}
$modules=@($spec.profiles.$Profile)
if($Desk){$modules=@($modules+'operations'+'desk'|Select-Object -Unique)}
if($Profile -ne 'Manual'){
    if(!$LocalStateDirectory){throw 'Supply a new LocalStateDirectory outside the workspace and outside file synchronization.'}
    $LocalStateDirectory=Get-DeploymentPath $LocalStateDirectory
    Assert-SeparateDeploymentPaths $Destination $LocalStateDirectory
    if(Test-Path -LiteralPath $LocalStateDirectory){throw 'Local state already exists. Never initialize over an existing ledger.'}
    if(!(Test-Path -LiteralPath (Split-Path $LocalStateDirectory -Parent) -PathType Container)){throw 'Local state parent must exist.'}
    foreach($binary in @($CodexPath,$ClaudePath)){Assert-DeploymentBinary $binary}
}
if($modules -contains 'operations'){
    Assert-DeploymentBinary $PythonPath
    $pythonVersion=& $PythonPath -I -c 'import sys; print(sys.version_info.major, sys.version_info.minor); sys.exit(0 if sys.version_info >= (3,10) else 1)'
    if($LASTEXITCODE -ne 0){throw 'Python 3.10 or newer is required for operations.'}
}
$inventory=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'package-files.json') -Raw|ConvertFrom-Json
if($inventory.schema -ne 1 -or $inventory.version -ne $spec.version){throw 'Package inventory version mismatch.'}
foreach($entry in $inventory.files){
    $path=Get-OwnedPath $PSScriptRoot $entry.path
    if(!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $entry.sha256){throw "Package is incomplete or modified: $($entry.path)"}
}
# Validate every selected file and dependency before creating either destination.
$selected=@()
foreach($module in $modules){
    foreach($dependency in $spec.modules.$module.requires){if($modules -notcontains $dependency){throw "Missing dependency $dependency"}}
    $prefix='modules/'+$module+'/'
    $entries=@($inventory.files|Where-Object {$_.path.StartsWith($prefix)})
    if(!$entries.Count){throw "Package has no files for $module"}
    foreach($entry in $entries){
        $relative=$entry.path.Substring($prefix.Length)
        $null=Get-OwnedPath $Destination $relative
        $selected+=@{module=$module;path=$relative;source=$entry.path}
    }
}
if(@($selected.path|Select-Object -Unique).Count -ne $selected.Count){throw 'Two packages own the same file.'}
$null=New-Item -ItemType Directory -Path $Destination -ErrorAction Stop
$receipt=[ordered]@{schema=1;id=[guid]::NewGuid().ToString('N');version=$spec.version;profile=$Profile;modules=$modules;root=$Destination;local_state=$LocalStateDirectory;python=$PythonPath;host=$env:COMPUTERNAME;status='installing';created_at=[DateTime]::UtcNow.ToString('o');files=@();tasks=@()}
Write-DeploymentJson (Join-Path $Destination 'agentos-installation.json') $receipt
try{
    foreach($entry in $selected){
        $path=Get-OwnedPath $Destination $entry.path
        $null=New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force
        Copy-Item -LiteralPath (Get-OwnedPath $PSScriptRoot $entry.source) -Destination $path
    }
    foreach($name in @('IAF.ps1','AgentOS.ps1','deployment-common.ps1')){
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $Destination $name)
        $selected+=@{module='management';path=$name}
    }
    if($Profile -ne 'Manual'){
        $null=New-Item -ItemType Directory -Path $LocalStateDirectory -ErrorAction Stop
        & (Join-Path $Destination 'runners/setup.ps1') -Root $Destination -CodexPath $CodexPath -ClaudePath $ClaudePath -LedgerDirectory (Join-Path $LocalStateDirectory 'ledger') | Out-Null
        if($modules -contains 'operations'){$null=New-Item -ItemType Directory -Path (Join-Path $LocalStateDirectory 'operations')}
    }
    foreach($entry in $selected){$receipt.files+=@{module=$entry.module;path=$entry.path;sha256=(Get-FileHash -LiteralPath (Get-OwnedPath $Destination $entry.path) -Algorithm SHA256).Hash.ToLowerInvariant()}}
    $receipt.status='configured'
    Write-DeploymentJson (Join-Path $Destination 'agentos-installation.json') $receipt
}catch{
    $receipt.status='installation_failed'
    Write-DeploymentJson (Join-Path $Destination 'agentos-installation.json') $receipt
    throw ('Installation stopped; preserved files and state at '+$Destination+'. Inspect before recovery. '+$_.Exception.Message)
}
Write-Output "Installed $Profile at $Destination. No models or scheduled tasks started. Read FIRST-RUN.md, then run IAF.ps1 Doctor."

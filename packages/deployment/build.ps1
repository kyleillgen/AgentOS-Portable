#requires -Version 5.1
param([Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
if(Test-Path -LiteralPath $OutputDirectory){throw 'Build output must be a new folder.'}
$spec=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'package.json') -Raw|ConvertFrom-Json
$template=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../portable/template'))
if((Get-Content -LiteralPath (Join-Path $template 'VERSION') -Raw).Trim() -ne $spec.foundation_version){throw 'Foundation version changed. Review compatibility before building.'}
$inventory=@(Get-Content -LiteralPath (Join-Path $PSScriptRoot '../portable/release-files.txt')|Where-Object {$_})
$actual=@(Get-ChildItem -LiteralPath $template -Recurse -File -Force|ForEach-Object {$_.FullName.Substring($template.Length+1).Replace('\','/')})
if(Compare-Object $inventory $actual){throw 'Foundation inventory changed. Review before building.'}
$cfg=Get-Content -LiteralPath (Join-Path $template 'runners/dispatcher.json') -Raw|ConvertFrom-Json
if($cfg.host -ne 'CONFIGURE_WITH_SETUP' -or $cfg.run_ledger){throw 'Cannot build from an installed runtime.'}
$stage=Join-Path $OutputDirectory ('iaf-'+$spec.version)
$null=New-Item -ItemType Directory -Path $stage
function Copy-ModuleFile([string]$Source,[string]$Module,[string]$Relative){
    if((Get-Item -LiteralPath $Source).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked sources are not supported.'}
    $target=Join-Path $stage ('modules/'+$Module+'/'+$Relative)
    $null=New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force
    Copy-Item -LiteralPath $Source -Destination $target
}
foreach($relative in $inventory){
    if($relative.StartsWith('runners/')){
        if($relative -match '^runners/test-' -or $relative -eq 'runners/install-dispatcher.ps1'){continue}
        Copy-ModuleFile (Join-Path $template $relative) 'runner' $relative
    }else{Copy-ModuleFile (Join-Path $template $relative) 'base' $relative}
}
foreach($module in @('base','operations','desk')){
    $source=Join-Path $PSScriptRoot ('payload/'+$module)
    foreach($file in Get-ChildItem -LiteralPath $source -File -Recurse -Force){
        if($file.FullName -match '__pycache__|\.pyc$'){continue}
        $relative=$file.FullName.Substring($source.Length+1).Replace('\','/')
        if($module -ne 'base'){$relative='extensions/'+$module+'/'+$relative}
        Copy-ModuleFile $file.FullName $module $relative
    }
}
foreach($name in @('Install-IAF.ps1','IAF.ps1','Install-AgentOS.ps1','AgentOS.ps1','deployment-common.ps1','README.md','CONTRACTS.md','package.json')){
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination (Join-Path $stage $name)
}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../../LICENSE') -Destination (Join-Path $stage 'LICENSE')
$files=@()
foreach($file in Get-ChildItem -LiteralPath $stage -File -Recurse -Force){
    $relative=$file.FullName.Substring($stage.Length+1).Replace('\','/')
    $content=[IO.File]::ReadAllText($file.FullName)
    if($content -match '(?i)[A-Z]:[\\/]Users[\\/](?!Public\b|Default\b)[^\\/\s]+|[A-Z]:[\\/]Astra[\\/]|D:[\\/]AIFolders|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|-----BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY-----'){throw "Potential private content in $relative"}
    $files+=@{path=$relative;sha256=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()}
}
@{schema=1;version=$spec.version;files=$files}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $stage 'package-files.json') -Encoding UTF8
$zip=Join-Path $OutputDirectory ('iaf-profiles-'+$spec.version+'.zip')
[IO.Compression.ZipFile]::CreateFromDirectory($stage,$zip)
(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()+'  '+[IO.Path]::GetFileName($zip)|Set-Content -LiteralPath (Join-Path $OutputDirectory 'SHA256SUMS.txt') -Encoding ascii
Write-Output "Built $zip"

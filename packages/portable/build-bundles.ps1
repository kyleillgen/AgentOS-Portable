#requires -Version 5.1
param([string]$OutputDirectory=(Join-Path $PSScriptRoot 'downloads'))
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$template=Join-Path $PSScriptRoot 'template'
$version=(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'package.json') -Raw|ConvertFrom-Json).version
if($version -notmatch '^\d+\.\d+\.\d+$' -or (Get-Content -LiteralPath (Join-Path $template 'VERSION') -Raw).Trim() -ne $version) {throw 'Package and template version must match.'}
$expected=@(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'release-files.txt')|Where-Object {$_})
$actual=@(Get-ChildItem -LiteralPath $template -Recurse -File -Force|ForEach-Object {$_.FullName.Substring($template.Length+1).Replace('\','/')})
if(Compare-Object $expected $actual) {throw 'Template inventory differs from release-files.txt. Review added/removed files explicitly before building.'}
if(Get-ChildItem -LiteralPath $template -Recurse -Force|Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}) {throw 'Release template cannot contain links or junctions.'}
$cfg=Get-Content -LiteralPath (Join-Path $template 'runners/dispatcher.json') -Raw|ConvertFrom-Json
if($cfg.host -ne 'CONFIGURE_WITH_SETUP' -or $cfg.codex -ne 'CONFIGURE_WITH_SETUP' -or $cfg.claude -ne 'CONFIGURE_WITH_SETUP' -or $cfg.run_ledger) {throw 'Refusing to package a configured installation.'}
foreach($relative in $actual) {
    if($relative -match '(^|/)(work|state|node_modules|\.git|\.codex|\.claude|\.gemini)/|(^|/)(auth\.json|credentials[^/]*|\.env[^/]*)$|\.before-setup$|\.setup-(lock|new)$') {throw "Private/runtime file in template: $relative"}
    $content=[IO.File]::ReadAllText((Join-Path $template $relative))
    if($content -match '(?i)[A-Z]:[\\/]Users[\\/](?!Public\b|Default\b)[^\\/\s]+|[A-Z]:[\\/]Astra[\\/]|D:[\\/]AIFolders|sk-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|-----BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY-----') {throw "Potential personal path or credential in $relative. Review before release."}
}
$OutputDirectory=[IO.Path]::GetFullPath($OutputDirectory)
$bundleNames=@("agentos-manual-$version.zip","agentos-agent-setup-$version.zip")
foreach($name in @($bundleNames)+@('SHA256SUMS.txt')) {if(Test-Path -LiteralPath (Join-Path $OutputDirectory $name)){throw "Output exists: $name. Use a new output directory."}}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
$stage=Join-Path ([IO.Path]::GetTempPath()) ('agentos-bundle-'+[guid]::NewGuid().ToString('N'))
$manual=Join-Path $stage 'manual';$agent=Join-Path $stage 'agent'
$null=New-Item -ItemType Directory -Path $manual,$agent
Get-ChildItem -LiteralPath $template -Force|Copy-Item -Destination $manual -Recurse
Copy-Item -LiteralPath (Join-Path $template 'FIRST-RUN.md') -Destination (Join-Path $manual 'START-HERE.md')
foreach($name in @('template','bin','test','package.json','README.md','ARCHITECTURE.md','START-HERE.md','AGENT-SETUP.md','Install-AgentOS.ps1','Install-IAF.ps1','build-bundles.ps1','LICENSE','CHANGELOG.md','release-files.txt')) {Copy-Item -LiteralPath (Join-Path $PSScriptRoot $name) -Destination $agent -Recurse}
[IO.Compression.ZipFile]::CreateFromDirectory($manual,(Join-Path $OutputDirectory $bundleNames[0]))
[IO.Compression.ZipFile]::CreateFromDirectory($agent,(Join-Path $OutputDirectory $bundleNames[1]))
$a=[IO.Compression.ZipFile]::OpenRead((Join-Path $OutputDirectory $bundleNames[0]))
$b=[IO.Compression.ZipFile]::OpenRead((Join-Path $OutputDirectory $bundleNames[1]))
try {
    foreach($relative in $expected) {
        $left=@($a.Entries|Where-Object {$_.FullName.Replace('\','/') -eq $relative})
        $right=@($b.Entries|Where-Object {$_.FullName.Replace('\','/') -eq ('template/'+$relative)})
        if($left.Count -ne 1 -or $right.Count -ne 1) {throw "Bundle missing or duplicate: $relative"}
        $ls=$left[0].Open();$rs=$right[0].Open();$sha=[Security.Cryptography.SHA256]::Create()
        try {
            $lh=[Convert]::ToBase64String($sha.ComputeHash($ls));$rh=[Convert]::ToBase64String($sha.ComputeHash($rs))
            $source=[Convert]::ToBase64String($sha.ComputeHash([IO.File]::ReadAllBytes((Join-Path $template $relative))))
            if($lh -ne $rh -or $lh -ne $source) {throw "Bundle mismatch: $relative"}
        } finally {$ls.Dispose();$rs.Dispose();$sha.Dispose()}
    }
} finally {$a.Dispose();$b.Dispose()}
Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $OutputDirectory $bundleNames[0]),(Join-Path $OutputDirectory $bundleNames[1])|ForEach-Object {$_.Hash.ToLowerInvariant()+'  '+[IO.Path]::GetFileName($_.Path)}|Set-Content -Encoding ascii (Join-Path $OutputDirectory 'SHA256SUMS.txt')
Write-Output "PASS: version $version; matching template bytes, dotfiles, license and inventory. Downloads: $OutputDirectory"

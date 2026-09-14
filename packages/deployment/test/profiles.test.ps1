#requires -Version 5.1
param([Parameter(Mandatory)][string]$PythonPath)
$ErrorActionPreference='Stop'
$package=Split-Path $PSScriptRoot -Parent
$engine=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('agentos-profile-tests-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $testRoot
$passed=New-Object 'Collections.Generic.List[string]'
function Assert([bool]$Condition,[string]$Message){if(!$Condition){throw $Message}}
function Child([string[]]$Arguments,[int]$ExpectedExit=0){
    $prior=$ErrorActionPreference
    try{$ErrorActionPreference='Continue';$output=& $engine -NoProfile -ExecutionPolicy Bypass @Arguments 2>&1;$exitCode=$LASTEXITCODE}finally{$ErrorActionPreference=$prior}
    if($ExpectedExit -eq 0){Assert ($exitCode -eq 0) ('Child failed: '+($output -join [Environment]::NewLine))}
    else{Assert ($exitCode -ne 0) 'Expected child to fail'}
    return $output
}
function Install([string]$Name,[string]$Profile,[switch]$Desk){
    $arguments=@('-File',$installer,'-Destination',(Join-Path $testRoot $Name),'-Profile',$Profile)
    if($Profile -ne 'Manual'){$arguments+=@('-CodexPath',$engine,'-ClaudePath',$engine,'-LocalStateDirectory',(Join-Path $testRoot ($Name+'-local')))}
    if($Profile -eq 'Unattended' -or $Desk){$arguments+=@('-PythonPath',$PythonPath)}
    if($Desk){$arguments+='-Desk'}
    $null=Child $arguments
    return Join-Path $testRoot $Name
}
try{
    $null=Child @('-File',(Join-Path $package 'build.ps1'),'-OutputDirectory',(Join-Path $testRoot 'build'))
    $version=(Get-Content -LiteralPath (Join-Path $package 'package.json') -Raw|ConvertFrom-Json).version
    # Install from extracted ZIP, not from source or the build staging directory.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $extracted=Join-Path $testRoot 'extracted'
    [IO.Compression.ZipFile]::ExtractToDirectory((Join-Path $testRoot ('build/iaf-profiles-'+$version+'.zip')),$extracted)
    $installer=Join-Path $extracted 'Install-IAF.ps1'
    $manual=Install 'manual with spaces' 'Manual'
    Assert (!(Test-Path -LiteralPath (Join-Path $manual 'runners'))) 'Manual must not install a runner'
    Assert (!(Test-Path -LiteralPath (Join-Path $manual 'extensions'))) 'Manual must not install extensions'
    $doctor=(Child @('-File',(Join-Path $manual 'IAF.ps1'),'Doctor','-Json'))|ConvertFrom-Json
    Assert $doctor.ok 'Manual diagnostics failed'
    $passed.Add('Manual from ZIP: no providers, runtime or background services required')
    # The branded command must preserve failure status from the legacy implementation.
    $manualReceipt=Join-Path $manual 'agentos-installation.json'
    $originalReceipt=[IO.File]::ReadAllText($manualReceipt)
    try{
        $failedReceipt=$originalReceipt|ConvertFrom-Json
        $failedReceipt.status='installation_failed'
        [IO.File]::WriteAllText($manualReceipt,($failedReceipt|ConvertTo-Json -Depth 20))
        $null=Child @('-File',(Join-Path $manual 'IAF.ps1'),'Doctor','-Json') 1
    }finally{[IO.File]::WriteAllText($manualReceipt,$originalReceipt)}
    $passed.Add('IAF command propagates failed diagnostics to the caller')
    $before=(Get-FileHash -LiteralPath (Join-Path $manual 'TEAM.md')).Hash
    $null=Child @('-File',$installer,'-Destination',$manual) 1
    Assert ((Get-FileHash -LiteralPath (Join-Path $manual 'TEAM.md')).Hash -eq $before) 'Repeated installation changed work'
    $passed.Add('Repeated install preserves existing workspace')
    $bad=Join-Path $testRoot 'bad'
    $null=Child @('-File',$installer,'-Destination',$bad,'-Profile','Manual','-Desk') 1
    Assert (!(Test-Path -LiteralPath $bad)) 'Dependency failure created destination'
    $null=Child @('-File',$installer,'-Destination',$bad,'-Profile','Automated') 1
    Assert (!(Test-Path -LiteralPath $bad)) 'Missing prerequisite created destination'
    $passed.Add('Invalid dependencies and missing prerequisites fail before writes')
    $automated=Install 'automated' 'Automated'
    Assert (Test-Path -LiteralPath (Join-Path $automated 'runners/run-ledger.ps1')) 'Missing mandatory ledger protection'
    Assert (!(Test-Path -LiteralPath (Join-Path $automated 'extensions'))) 'Automated unexpectedly requires operations'
    $doctor=(Child @('-File',(Join-Path $automated 'IAF.ps1'),'Doctor','-Json'))|ConvertFrom-Json
    Assert $doctor.ok 'Automated diagnostics failed'
    $passed.Add('Automated has runner safeguards and no Python/operations dependency')
    $unattended=Install 'unattended' 'Unattended'
    Assert (Test-Path -LiteralPath (Join-Path $unattended 'extensions/operations/operations_service.py')) 'Missing checker'
    Assert (!(Test-Path -LiteralPath (Join-Path $unattended 'extensions/desk'))) 'Unattended unexpectedly requires desk'
    $receipt=Get-Content -LiteralPath (Join-Path $unattended 'agentos-installation.json') -Raw|ConvertFrom-Json
    Assert ($receipt.status -eq 'configured' -and @($receipt.tasks).Count -eq 0) 'Install must not register or start tasks'
    $passed.Add('Unattended installs headless checker/watchdog with no desk or implicit activation')
    $withDesk=Install 'with desk' 'Unattended' -Desk
    $local=Join-Path $testRoot 'with desk-local'
    $ledger=Join-Path $local 'ledger/ledger.json'
    $ledgerHash=(Get-FileHash -LiteralPath $ledger).Hash
    $null=Child @('-File',(Join-Path $withDesk 'IAF.ps1'),'RemoveDesk')
    Assert (!(Test-Path -LiteralPath (Join-Path $withDesk 'extensions/desk/operations_desk.py'))) 'Desk server remained installed'
    Assert (Test-Path -LiteralPath (Join-Path $withDesk 'extensions/operations/operations_service.py')) 'Removing desk removed checker'
    Assert ((Get-FileHash -LiteralPath $ledger).Hash -eq $ledgerHash) 'Removing desk changed ledger'
    $passed.Add('Desk removal preserves independent operations and ledger')
    $results=Join-Path $withDesk 'work/results/preserved'
    $null=New-Item -ItemType Directory -Path $results
    Set-Content -LiteralPath (Join-Path $results 'report.md') -Value 'User evidence'
    Add-Content -LiteralPath (Join-Path $withDesk 'runners/README.md') -Value 'User customization'
    $null=Child @('-File',(Join-Path $withDesk 'IAF.ps1'),'Uninstall')
    Assert (Test-Path -LiteralPath (Join-Path $results 'report.md')) 'Uninstall removed evidence'
    Assert (Test-Path -LiteralPath (Join-Path $withDesk 'runners/README.md')) 'Uninstall removed a modified file'
    Assert (Test-Path -LiteralPath (Join-Path $withDesk 'TEAM.md')) 'Uninstall removed base'
    Assert ((Get-FileHash -LiteralPath $ledger).Hash -eq $ledgerHash) 'Uninstall changed ledger'
    Assert (!(Test-Path -LiteralPath (Join-Path $withDesk 'runners/dispatcher.ps1'))) 'Uninstall left unchanged dispatcher'
    $passed.Add('Uninstall preserves base, evidence, modified files and protected state')
    $tamper=Join-Path $extracted 'modules/base/TEAM.md'
    Add-Content -LiteralPath $tamper -Value 'Unexpected package change'
    $null=Child @('-File',$installer,'-Destination',(Join-Path $testRoot 'tampered')) 1
    Assert (!(Test-Path -LiteralPath (Join-Path $testRoot 'tampered'))) 'Tampered package created destination'
    $passed.Add('Package integrity failure makes no installation writes')
    $null=Child @('-File',(Join-Path $PSScriptRoot 'scheduling.test.ps1'))
    $passed.Add('Windows scheduling contract: denial, mismatch, rollback and ownership')
    & $PythonPath -E -s (Join-Path $PSScriptRoot 'operations.test.py')
    Assert ($LASTEXITCODE -eq 0) 'Operations behavior tests failed'
    $passed.Add('Operations behavioral tests passed')
    @{ok=$true;checks=@($passed.ToArray());test_root=$testRoot;verification='Isolated Windows folder and process tests; provider login, live startup registration and signed-out use not tested'}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $testRoot 'result.json') -Encoding UTF8
    Write-Output ('PASS: '+$passed.Count+' packaging groups. Evidence: '+(Join-Path $testRoot 'result.json'))
}catch{
    @{ok=$false;passed=@($passed.ToArray());error=$_.Exception.Message;test_root=$testRoot}|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $testRoot 'result.json') -Encoding UTF8
    throw
}

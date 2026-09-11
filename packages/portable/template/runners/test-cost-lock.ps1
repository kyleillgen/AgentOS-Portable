$ErrorActionPreference='Stop'
. "$PSScriptRoot/telemetry.ps1"
$dir=Join-Path $env:TEMP ('agentos-cost-lock-'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $dir|Out-Null
$path=Join-Path $dir 'costs.csv';[IO.File]::WriteAllText($path,'header')
$lock=[IO.File]::Open($path,'Open','ReadWrite','None')
try{Write-CostRow -CostPath $path -OutDir $dir -Stage execute -Row 'synthetic-row'}finally{$lock.Dispose()}
$pending=Get-Content "$dir/execute-cost-pending.json" -Raw|ConvertFrom-Json
if($pending.row -ne 'synthetic-row'){throw 'Busy aggregate row was not retained'}
Write-CostRow -CostPath $path -OutDir $dir -Stage review -Row 'review-row'
if((Get-Content $path -Raw) -notmatch 'review-row'){throw 'Available aggregate append failed'}
'PASS: busy accounting file retains deferred row without failing the attempt; normal append preserved.'

#requires -Version 5.1
param([string]$Root=(Split-Path $PSScriptRoot -Parent),[Parameter(Mandatory)][string]$OrderPath)
$ErrorActionPreference='Stop'
$Root=[IO.Path]::GetFullPath($Root)
$text=[IO.File]::ReadAllText([IO.Path]::GetFullPath($OrderPath),[Text.Encoding]::UTF8)
$order=$text|ConvertFrom-Json
if($order.id -cnotmatch '^[a-z][a-z0-9-]{0,63}$' -or $order.id -match '^(con|prn|aux|nul|com[0-9]|lpt[0-9])$') { throw 'Use a nonreserved lowercase task ID of at most 64 characters.' }
if($order.owner -notin @('codex','claude') -or $order.status -ne 'ready' -or !$order.objective -or !$order.acceptance -or !$order.authorization -or !$order.task_id -or !$order.assigned_revision) { throw 'Require owner codex/claude, status ready, objective, acceptance, authorization, task_id and assigned_revision.' }
$inbox=Join-Path $Root 'work/inbox'
if(!(Test-Path -LiteralPath $inbox -PathType Container)) { throw 'Run setup first.' }
$final=Join-Path $inbox ($order.id+'.json')
if(Test-Path -LiteralPath $final) { throw 'Published IDs are immutable. Use a new linked order.' }
$temp=Join-Path $inbox ([guid]::NewGuid().ToString('N')+'.publishing')
try {
    [IO.File]::WriteAllText($temp,$text,[Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temp,$final)
} finally { if(Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp } }
Write-Output "Published $final"

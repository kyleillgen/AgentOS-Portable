$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('agentos-runtime-integration-' + [guid]::NewGuid())
New-Item -ItemType Directory "$testRoot/runners","$testRoot/work/inbox" -Force | Out-Null
$fakeExe = Join-Path $testRoot 'fake-cli.exe'
$source = @"
using System;
using System.IO;
using System.Text.RegularExpressions;
public class AgentOsFakeCli {
 public static int Main(string[] args) {
  string prompt = Console.In.ReadToEnd();
  Match nonce = Regex.Match(prompt, @"AGENTOS-VERDICT PASS ([a-f0-9-]{36})");
  if (!nonce.Success) return 91;
  string result = "Fake evidence. AGENTOS integration only.\nAGENTOS-VERDICT PASS " + nonce.Groups[1].Value;
  string path = null;
  for(int i=0;i+1<args.Length;i++) if(args[i]=="--output-last-message") path=args[i+1];
  if(path!=null) { File.WriteAllText(path,result); return 0; }
  if(prompt.Contains("FAKE_MALFORMED")) { Console.WriteLine("{broken terminal"); return 0; }
  bool error = prompt.Contains("FAKE_ERROR") || prompt.Contains("FAKE_TURN_LIMIT");
  string subtype=prompt.Contains("FAKE_TURN_LIMIT") ? "error_max_turns" : (error ? "error_during_execution" : "success");
  string escaped=result.Replace("\\","\\\\").Replace("\"","\\\"").Replace("\n","\\n");
  Console.WriteLine("{\"type\":\"result\",\"subtype\":\""+subtype+"\",\"is_error\":"+(error?"true":"false")+",\"result\":\""+escaped+"\",\"permission_denials\":[],\"modelUsage\":{\"fake\":{\"webSearchRequests\":0}},\"num_turns\":1}");
  return prompt.Contains("FAKE_NONZERO") ? 7 : 0;
 }
}
"@
Add-Type -TypeDefinition $source -Language CSharp -OutputAssembly $fakeExe -OutputType ConsoleApplication
$cfg = Get-Content "$PSScriptRoot/dispatcher.json" -Raw | ConvertFrom-Json
$cfg | Add-Member -NotePropertyName run_ledger -NotePropertyValue "$testRoot/ledger" -Force
New-Item -ItemType Directory "$testRoot/ledger" -Force|Out-Null
@{schema=1;root=$testRoot;orders=@{}}|ConvertTo-Json|Set-Content "$testRoot/ledger/ledger.json"
$cfg.settle_seconds=0
$cfg.host='test-'+[guid]::NewGuid().ToString('N')
$cfg.codex=$fakeExe; $cfg.claude=$fakeExe
foreach($key in @('git_checkpoint_script','health_script','codex_wsl_distribution','codex_wsl_user')) { $cfg | Add-Member -NotePropertyName $key -NotePropertyValue $null -Force }
$cfg | ConvertTo-Json -Depth 10 | Set-Content "$testRoot/runners/dispatcher.json" -Encoding UTF8
$cases=@(
 @{id='a-success';owner='claude';objective='FAKE_SUCCESS';expected='pending'},
 @{id='b-malformed';owner='claude';objective='FAKE_MALFORMED';expected='needs_attention'},
 @{id='c-error';owner='claude';objective='FAKE_ERROR';expected='needs_attention'},
 @{id='d-turn-limit';owner='claude';objective='FAKE_TURN_LIMIT';expected='needs_attention'},
 @{id='e-nonzero';owner='claude';objective='FAKE_NONZERO';expected='needs_attention'},
 @{id='f-codex';owner='codex';objective='FAKE_SUCCESS';expected='pending'}
)
foreach($case in $cases) { @{id=$case.id;owner=$case.owner;objective=$case.objective;status='ready';authorization='Fake CLI test only';task_id='synthetic';assigned_revision=2;acceptance='Fake integration acceptance only'} | ConvertTo-Json | Set-Content "$testRoot/work/inbox/$($case.id).json" -Encoding UTF8 }
$priorHost=$env:COMPUTERNAME
try {
 $env:COMPUTERNAME=$cfg.host
 & "$PSScriptRoot/dispatcher.ps1" -Root $testRoot
 foreach($case in $cases) {
  $status=Get-Content "$testRoot/work/status/$($case.id).json" -Raw | ConvertFrom-Json
  if($status.state -ne $case.expected) { throw "$($case.id): expected $($case.expected), got $($status.state): $($status.note)" }
  if($case.expected -eq 'pending' -and $status.stage -ne 'review') { throw "$($case.id): review not queued" }
  $runtime=Get-Content "$testRoot/work/results/$($case.id)/execute-runtime.json" -Raw | ConvertFrom-Json
  if($runtime.schema_version -ne 'agentos-runtime-v1') { throw "$($case.id): runtime absent/invalid" }
  if($runtime.host.duration_s -lt 0) { throw 'Invalid runtime duration' }
 }
 $rows=@(Get-Content "$testRoot/state/costs.csv")
 if($rows.Count -ne $cases.Count) { throw "Expected $($cases.Count) cost rows, got $($rows.Count)" }
 & "$PSScriptRoot/dispatcher.ps1" -Root $testRoot
 foreach($id in @('a-success','f-codex')) {
  $status=Get-Content "$testRoot/work/status/$id.json" -Raw|ConvertFrom-Json
  if($status.state -ne 'completed') { throw "$id independent alternate-provider review failed: $($status.note)" }
  if(!(Test-Path "$testRoot/work/results/$id/review-runtime.json")) { throw "$id review runtime missing" }
 }
 if(@(Get-Content "$testRoot/state/costs.csv").Count -ne 8) { throw 'Unexpected total cost rows; failed runs may have replayed' }
 "PASS: six actual fake-CLI executions, four failures rejected despite provider success text where available, both provider review routes completed, runtime/cost evidence retained, no failed replay. Artifacts: $testRoot"
} finally { $env:COMPUTERNAME=$priorHost }

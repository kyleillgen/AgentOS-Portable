#requires -Version 5.1
param([Parameter(Mandatory)][string]$Root)
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class AgentOSUnattendedPower {
    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern uint SetThreadExecutionState(uint flags);
}
'@
if([AgentOSUnattendedPower]::SetThreadExecutionState([uint32]2147483649) -eq 0){throw 'Windows refused the system-awake request.'}
try{& (Join-Path $Root 'runners/monitor.ps1') -Root $Root}
finally{$null=[AgentOSUnattendedPower]::SetThreadExecutionState([uint32]2147483648)}

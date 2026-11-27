<#
  audit-fleet.ps1  -  read-only audit of the three-node fleet.

  Measures WORK, not just the queue. The D:/fleet task queue is one transport; the agent
  lanes on each station are the other. An idle queue with busy lanes is normal and must not
  be reported as a stall - that mistake was made on 2026-11-27 and is why this file exists.
#>
[CmdletBinding()]
param(
    [string]   $Coordinator = 'node-a',
    [string[]] $Workers     = @('node-b', 'node-c'),
    [string]   $StationScript = 'C:\\Users\\<user>\audit-station.ps1'
)
$ErrorActionPreference = 'Continue'
$opt = @('-o','BatchMode=yes','-o','ConnectTimeout=10','-o','StrictHostKeyChecking=accept-new')
$stations = @($Coordinator) + $Workers
$local = Join-Path $PSScriptRoot 'audit-station.ps1'

Write-Host ('FLEET AUDIT  ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor Cyan

Write-Host '## station activity'
$all = @{}
foreach ($s in $stations) {
    if (Test-Path $local) { & scp @opt $local "${s}:$StationScript" 2>&1 | Out-Null }
    $txt = (& ssh @opt $s "powershell -ExecutionPolicy Bypass -File $StationScript" 2>&1 | Out-String)
    $all[$s] = $txt
    $busy = ([regex]::Matches($txt, 'worker\s+:')).Count
    $nh   = ([regex]::Matches($txt, 'activity\s+:')).Count
    Write-Host ('  {0,-18} agents={1}  repos-with-activity={2}' -f $s, $busy, $nh)
    foreach ($line in ($txt -split "`n")) {
        if ($line -match 'repo\s+:|activity\s+:|worker\s+:') { Write-Host ('     ' + $line.Trim()) }
    }
}

Write-Host ''
Write-Host '## queue transport (idle is normal when lanes work directly)'
$q = (& ssh @opt $Coordinator 'powershell -ExecutionPolicy Bypass -File C:\\Users\\<user>\audit-coordinator.ps1' 2>&1 | Out-String)
foreach ($line in ($q -split "`n")) {
    if ($line -match 'queue\s+:|reaper') { Write-Host ('  ' + $line.Trim()) }
}

Write-Host ''
Write-Host '## findings' -ForegroundColor Cyan
$busyStations = 0
foreach ($s in $stations) { if ($all[$s] -match 'worker\s+:') { $busyStations++ } }
if ($busyStations -gt 0) { Write-Host ('  OK     work in progress on {0}/{1} stations' -f $busyStations, $stations.Count) -ForegroundColor Green }
else { Write-Host '  HIGH   no busy agent process on any station' -ForegroundColor Red }

$unpushed = 0
foreach ($s in $stations) { foreach ($m in [regex]::Matches($all[$s], 'unpushed=(\d+)')) { $n = [int]$m.Groups[1].Value; if ($n -gt $unpushed) { $unpushed = $n } } }
if ($unpushed -gt 0) { Write-Host ('  INFO   up to {0} commits are unpushed on their station (bundled 2026-11-27, see rotation/inventory log)' -f $unpushed) }

if ($q -match 'worker-credentials\.csv PRESENT') { Write-Host '  HIGH   worker-credentials.csv still on the coordinator (runbook step 3)' -ForegroundColor Red }
if ($q -match 'queue=0 claimed=0 results=0') { Write-Host '  INFO   task queue empty - transport idle, not a stall' }
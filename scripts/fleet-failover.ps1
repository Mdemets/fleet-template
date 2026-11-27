<#
  fleet-failover.ps1  -  move the fleet between primary and standby coordinator.

    -To node-a   : node-a is primary, node-b is standby. Both workers run on node-a.
    -To node-b      : node-b is primary, node-a is down/unavailable. node-b's own worker is
                    disabled (SMB loopback check), so node-c is the only worker.

  Assumption this relies on: fleet-worker-c has the SAME password on both coordinators, so the
  worker's stored credential works against either and no rotation is needed to switch.
  If auth fails after a switch, that assumption has been broken - fix the account, do not
  rekey the worker blindly.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('node-a','node-b')][string] $To)
$ErrorActionPreference = 'Continue'
$opt = @('-o','BatchMode=yes','-o','ConnectTimeout=10','-o','StrictHostKeyChecking=accept-new')
$addr = @{ 'node-a' = '10.0.0.10'; 'node-b' = '10.0.0.11' }
$other = if ($To -eq 'node-a') { 'node-b' } else { 'node-a' }
function Sh($h,$c){ (& ssh @opt $h $c 2>&1 | Out-String).Trim() }

Write-Host ('FAILOVER -> {0} ({1})' -f $To, $addr[$To]) -ForegroundColor Cyan

# 0. target reachable?
if (-not (Test-NetConnection -ComputerName $addr[$To] -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue)) {
    Write-Host '  target unreachable on 22 - aborting, nothing changed' -ForegroundColor Red; exit 1
}

# 1. drain check on the target share
$q = Sh $To ('powershell -NoProfile -Command "(Get-ChildItem ' + $(if($To -eq 'node-b'){'C:\fleetshare'}else{'D:\fleet'}) + '\queue -Recurse -File -Filter *.json).Count"')
Write-Host ('  target queue depth: {0}' -f $q)

# 2. repoint DESKTOP (hard stop, config, start)
Write-Host '  node-c'
Sh 'node-c' 'schtasks /end /tn FleetWorker' | Out-Null
Sh 'node-c' ('powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter ""Name=''powershell.exe''"" | Where-Object { $_.CommandLine -match ''FleetWorker'' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"') | Out-Null
Sh 'node-c' ('powershell -NoProfile -Command "Set-Content -Path C:\fleet\coordinator.unc -Value ''\\' + $addr[$To] + '\fleet'' -Encoding ascii"') | Out-Null
Sh 'node-c' 'schtasks /run /tn FleetWorker' | Out-Null
Write-Host ('    -> {0}' -f $addr[$To])

# 3. the other host: worker when it is primary, coordinator (worker off) when it is standby
if ($To -eq 'node-a') {
    Write-Host '  node-b: back to worker'
    Sh 'node-b' ('powershell -NoProfile -Command "Set-Content -Path C:\fleet\coordinator.unc -Value ''\\' + $addr[$To] + '\fleet'' -Encoding ascii"') | Out-Null
    Sh 'node-b' 'schtasks /change /tn FleetWorker /enable' | Out-Null
    Sh 'node-b' 'schtasks /run /tn FleetWorker' | Out-Null
    Sh 'node-b' 'schtasks /change /tn FleetReaper /disable' | Out-Null
    Write-Host '    worker enabled, standby reaper disabled'
} else {
    Write-Host '  node-b is now coordinator: its worker must be off (loopback)'
    Sh 'node-b' 'schtasks /end /tn FleetWorker' | Out-Null
    Sh 'node-b' 'schtasks /change /tn FleetWorker /disable' | Out-Null
    Sh 'node-b' 'schtasks /change /tn FleetReaper /enable' | Out-Null
    Write-Host '    worker disabled, reaper enabled'
}

Write-Host '  verifying in 45s...'
Start-Sleep -Seconds 45
$hb = Sh $To ('powershell -NoProfile -Command "Get-ChildItem ' + $(if($To -eq 'node-b'){'C:\fleetshare'}else{'D:\fleet'}) + '\results -Recurse -File -Filter heartbeat.json | ForEach-Object { $_.Directory.Name + ''='' + [int]((Get-Date)-$_.LastWriteTime).TotalSeconds + ''s'' }"')
Write-Host ('  heartbeats: {0}' -f $hb)
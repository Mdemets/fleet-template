<#
  recover-after-reboot.ps1  -  run from operator workstation once the coordinator is powered on again.
  Read-only until -StartWorkers, which restarts the fleet worker on both nodes.

  Why this exists: the 2026-11-27 reboot left the coordinator off the network. The two risks on
  return are (a) the WMI repair did not take, and (b) the coordinator is on DHCP, so it may come
  back on a different address while both workers still point at 10.0.0.10.
#>
[CmdletBinding()]
param([string] $Subnet = '10.0.0',
    [string] $Expected = '10.0.0.10',
    [switch] $StartWorkers,          # restart FleetWorker on both nodes
    [switch] $RepairIp               # rewrite coordinator.unc on the workers if the IP moved
)
$ErrorActionPreference = 'Continue'
$opt = @('-o','BatchMode=yes','-o','ConnectTimeout=8','-o','StrictHostKeyChecking=accept-new')

function Sh($h, $c) { (& ssh @opt $h $c 2>&1 | Out-String).Trim() }

Write-Host ('RECOVERY CHECK  ' + (Get-Date).ToString('HH:mm:ss')) -ForegroundColor Cyan

# 1. find the coordinator
$ip = $null
if ((Test-NetConnection -ComputerName $Expected -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue)) { $ip = $Expected }
else {
    Write-Host ('  {0}:22 closed - scanning the subnet for SSH' -f $Expected) -ForegroundColor Yellow
    foreach ($i in 1..254) {
        $cand = "$Subnet.$i"
        if (Test-NetConnection -ComputerName $cand -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue) { $ip = $cand; break }
    }
}
if (-not $ip) { Write-Host '  no host with SSH on the subnet - the machine is still not up' -ForegroundColor Red; exit 1 }
Write-Host ('  coordinator at {0}' -f $ip) -ForegroundColor Green
if ($ip -ne $Expected) {
    Write-Host ('  IP MOVED from {0} - workers still point at the old address' -f $Expected) -ForegroundColor Yellow
    if ($RepairIp) {
        foreach ($w in @('node-b','node-c')) {
            Sh $w ('Set-Content -Path C:\fleet\coordinator.unc -Value "\\' + $ip + '\fleet" -Encoding ascii') | Out-Null
            Write-Host ('    updated coordinator.unc on ' + $w)
        }
    } else { Write-Host '    re-run with -RepairIp to point the workers at the new address' }
}

# 2. services on the coordinator
Write-Host '  checking services'
if ($ip -eq $Expected) {
  $svc = Sh 'node-a' 'powershell -NoProfile -Command "(Get-Service sshd).Status.ToString() + "/" + (Get-Service sshd).StartType.ToString()"'
  Write-Host ('    sshd        : {0}' -f $svc)
  $share = Sh 'node-a' 'net share fleet'
  Write-Host ('    share fleet : {0}' -f $(if ($share -match 'fleet') { 'present' } else { 'MISSING' }))
  $reap = Sh 'node-a' 'schtasks /query /tn FleetReaper /fo LIST'
  Write-Host ('    FleetReaper : {0}' -f $(if ($reap -match 'Ready|Running') { 'registered' } else { 'MISSING' }))
  # the actual WMI test: the classes that were broken
  $wmi = Sh 'node-a' 'powershell -NoProfile -Command "try { $null = Get-NetIPAddress -ErrorAction Stop; ''OK'' } catch { ''FAIL'' }"'
  Write-Host ('    Get-NetIPAddress : {0}' -f $wmi)
  if ($wmi -match 'FAIL') { Write-Host '    WMI still broken: winmgmt /verifyrepository then /salvagerepository, then reboot ONLY with a console path' -ForegroundColor Yellow }
} else { Write-Host '    skipped: host address differs, check by hand' -ForegroundColor Yellow }

# 3. optionally bring the workers back
if ($StartWorkers) {
    foreach ($w in @('node-b','node-c')) {
        Sh $w 'schtasks /run /tn FleetWorker' | Out-Null
        Write-Host ('  started FleetWorker on ' + $w)
    }
    Start-Sleep -Seconds 45
    Write-Host '  heartbeats: (check results/<node>/heartbeat.json ages on the coordinator)'
}

$ErrorActionPreference='Continue'
$share='D:\fleet'
$logDir='C:\Users\Maarten\fleet\logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log=Join-Path $logDir 'restart.log'
function L($m){ (Get-Date).ToUniversalTime().ToString('o') + '  ' + $m | Out-File $log -Append -Encoding utf8 }

L 'restart: helper started'
Start-Sleep -Seconds 2
schtasks /end /tn FleetDashboard 2>&1 | Out-Null
Start-Sleep -Seconds 1
schtasks /run /tn FleetDashboard 2>&1 | Out-Null
L 'restart: FleetDashboard ended and started'

$ok=$false
for ($i=1; $i -le 30; $i++) {
  Start-Sleep -Seconds 1
  try { $h=Invoke-RestMethod -Uri 'http://192.168.0.196:8080/health' -TimeoutSec 3 -ErrorAction Stop; if ($h.total -ge 1) { $ok=$true; break } } catch { }
}
if ($ok) {
  L ('restart: recovered in ' + $i + 's, /health answers')
  Remove-Item (Join-Path $share 'status\restart-attention.txt') -Force -ErrorAction SilentlyContinue
  'recovered' | Out-File (Join-Path $share 'status\restart-last.txt') -Encoding utf8
} else {
  L 'restart: FAILED to recover within 30s - attention required'
  ('restart failed at ' + (Get-Date).ToUniversalTime().ToString('o') + ' - run: schtasks /run /tn FleetDashboard') | Out-File (Join-Path $share 'status\restart-attention.txt') -Encoding utf8
  'failed' | Out-File (Join-Path $share 'status\restart-last.txt') -Encoding utf8
}

# a monitor start is also a good moment to check the repositories, rather than waiting for the next tick
try {
    Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Users\Maarten\fleet\FleetRepoWatch.ps1' -WindowStyle Hidden -ErrorAction Stop
    L 'repo watch triggered by monitor start'
} catch { L ('repo watch trigger failed - ' + $_.Exception.Message) }
# and the same for work: run the queue monitor once so a redrawn board immediately has tasks to show
try {
    Start-Process -FilePath 'powershell.exe' -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Users\Maarten\fleet\FleetQueueMonitor.ps1' -WindowStyle Hidden -ErrorAction Stop
    L 'queue monitor (refill check) triggered by monitor start'
} catch { L ('queue monitor trigger failed - ' + $_.Exception.Message) }

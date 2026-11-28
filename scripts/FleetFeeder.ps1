
$ErrorActionPreference='Continue'
. 'C:\Users\Maarten\fleet\FleetCounter.ps1'
$share='D:\fleet'
$logDir='C:\Users\Maarten\fleet\logs'; New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log=Join-Path $logDir 'feeder.log'
function L($m){ (Get-Date).ToUniversalTime().ToString('o') + '  ' + $m | Out-File $log -Append -Encoding utf8 }

L ('feeder loop starting total=' + (Get-Created))
while ($true) {
  $queue=@(Get-ChildItem (Join-Path $share 'queue') -File -Filter 'task-*.json' -ErrorAction SilentlyContinue).Count
  if ($queue -lt 1000) { & 'C:\Users\Maarten\fleet\FleetCorpusFinder.ps1' }
  Start-Sleep -Milliseconds 400
}

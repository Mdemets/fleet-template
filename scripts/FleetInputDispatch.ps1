$ErrorActionPreference='Continue'
. 'C:\Users\Maarten\fleet\FleetCounter.ps1'
$share='D:\fleet'
$inDir=Join-Path $share 'inputs'
New-Item -ItemType Directory -Force -Path $inDir | Out-Null
$stateFile=Join-Path $inDir 'dispatched.txt'
$done=@()
if (Test-Path $stateFile) { $done=@(Get-Content $stateFile | Where-Object { $_.Trim() }) }
$queueNow=@(Get-ChildItem (Join-Path $share 'queue') -File -Filter 'task-agent-*.json' -ErrorAction SilentlyContinue).Count
if ($queueNow -ge 8) { exit 0 }
$made=0
foreach ($f in @(Get-ChildItem $inDir -File -Filter '*.json' -ErrorAction SilentlyContinue)) {
  if ($done -contains $f.BaseName) { continue }
  try { $spec = Get-Content $f.FullName -Raw | ConvertFrom-Json } catch { continue }
  if (-not $spec.prompt) { continue }
  $id = 'agent-' + $f.BaseName + '-' + (Get-Date).ToUniversalTime().ToString('yyMMddHHmmss')
  $task = [ordered]@{ id = $id; kind = 'agent'; payload = @{ prompt = [string]$spec.prompt }; timeoutSeconds = 300 }
  try {
    $task | ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath (Join-Path (Join-Path $share 'queue') ('task-' + $id + '.json')) -Encoding utf8
    $done += $f.BaseName
    $made++
    $null = Add-Created 1 'agent'
  } catch { }
}
if ($made -gt 0) { $done | Set-Content -LiteralPath $stateFile -Encoding utf8 }
Write-Output ('dispatched=' + $made + ' inputs=' + @(Get-ChildItem $inDir -File -Filter '*.json').Count)

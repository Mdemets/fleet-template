
$ErrorActionPreference='Continue'
$share='D:/fleet'
$log=Join-Path $share 'status/watchdog.log'
function W($m){ ((Get-Date).ToUniversalTime().ToString('o')) + '  ' + $m | Add-Content -LiteralPath $log -Encoding utf8 }

$queue=@(Get-ChildItem (Join-Path $share 'queue') -File -Filter 'task-*.json' -ErrorAction SilentlyContinue)
$qnames=@{}
foreach ($f in $queue) { $qnames[$f.Name]=$true }

# 1. stale claim markers: marker exists, its task is still queued, marker older than 5 minutes
$stale=@()
$marks=@(Get-ChildItem (Join-Path $share 'locks') -File -Filter '*.claim' -ErrorAction SilentlyContinue)
foreach ($m in $marks) {
    $taskName = $m.Name -replace '\.claim$',''
    if ($qnames.ContainsKey($taskName) -and $m.LastWriteTimeUtc -lt (Get-Date).ToUniversalTime().AddMinutes(-5)) { $stale += $m }
}
if ($stale.Count -gt 0) {
    $n=0
    foreach ($m in $stale) { try { Remove-Item -LiteralPath $m.FullName -Force -ErrorAction Stop; $n++ } catch { } }
    W ("cleared " + $n + " stale claim markers blocking queued tasks")
}

# 2. progress check: nothing completed recently while work is waiting
$recent = @(Get-ChildItem (Join-Path $share 'results') -Recurse -File -Filter 'result-*.json' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTimeUtc -gt (Get-Date).ToUniversalTime().AddMinutes(-10) }).Count
$stateFile = Join-Path $share 'status/watchdog.state'
$frozenSince = $null
if (Test-Path $stateFile) { try { $frozenSince = [datetime]::Parse((Get-Content $stateFile -Raw).Trim()) } catch { } }

if ($queue.Count -gt 100 -and $recent -eq 0) {
    if (-not $frozenSince) { $frozenSince = (Get-Date).ToUniversalTime(); $frozenSince.ToString('o') | Set-Content -LiteralPath $stateFile -Encoding utf8; W ("frozen: queue=" + $queue.Count + " no completions in 10 min - armed") }
    elseif (((Get-Date).ToUniversalTime() - $frozenSince).TotalMinutes -ge 10) {
        W ("frozen for " + [int]((Get-Date).ToUniversalTime() - $frozenSince).TotalMinutes + " min with queue=" + $queue.Count + " - restarting agents")
        foreach ($t in @('FleetAgent')) { schtasks /end /tn $t 2>&1 | Out-Null; Start-Sleep -Milliseconds 500; schtasks /run /tn $t 2>&1 | Out-Null }
        W 'agents restarted by watchdog'
        Remove-Item $stateFile -Force -ErrorAction SilentlyContinue
    }
} else {
    if (Test-Path $stateFile) { Remove-Item $stateFile -Force -ErrorAction SilentlyContinue; W ("cleared frozen state (queue=" + $queue.Count + " recent=" + $recent + ")") }
}
Write-Output ("queue=" + $queue.Count + " stale_cleared=" + $stale.Count + " recent10m=" + $recent)

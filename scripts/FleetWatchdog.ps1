
$ErrorActionPreference='Continue'
$share='D:/fleet'
$log=Join-Path $share 'status/watchdog.log'
function W($m){ ((Get-Date).ToUniversalTime().ToString('o')) + '  ' + $m | Add-Content -LiteralPath $log -Encoding utf8 }


# ---- operator reboot request: drain, then restart ----
$nodeMap = @{ 'MDMFURY' = 'mdmfury'; 'MDMA' = 'mdma'; 'DESKTOP-GR2C3P8' = 'gr2c3p8' }
$nodeName = $nodeMap[$env:COMPUTERNAME.ToUpper()]
if ($nodeName) {
    $req = Join-Path $share ('control/reboot/' + $nodeName + '.json')
    if (Test-Path $req) {
        # a request must be explicit and fresh: a stray or forgotten file must never restart a machine
        $rq = $null
        try { $rq = Get-Content $req -Raw -ErrorAction Stop | ConvertFrom-Json } catch { }
        $confirmed = ($rq -and [string]$rq.confirm -eq 'drain-then-reboot')
        $ageMin = 9999
        if ($rq -and $rq.requested) { try { $ageMin = ((Get-Date).ToUniversalTime() - [datetime]::Parse([string]$rq.requested).ToUniversalTime()).TotalMinutes } catch { } }
        if (-not $confirmed) {
            W 'reboot request ignored: no explicit confirmation in the file'
        } elseif ($ageMin -gt 30) {
            W ('reboot request expired (' + [int]$ageMin + ' min old) - removed without restarting')
            Remove-Item -LiteralPath $req -Force -ErrorAction SilentlyContinue
        } else {
        $active = -1
        $hb = Join-Path $share ('results/' + $nodeName + '/heartbeat.json')
        if (Test-Path $hb) { try { $active = [int]((Get-Content $hb -Raw -ErrorAction Stop | ConvertFrom-Json).active) } catch { } }
        if ($active -gt 0) {
            W ('reboot requested: draining (' + $active + ' task(s) still running)')
        } else {
            if ($env:FLEET_REBOOT_DRYRUN -eq '1') {
                W 'reboot requested: drained - DRY RUN, not restarting'
            } else {
                W 'reboot requested: drained - restarting in 10 seconds'
                Remove-Item -LiteralPath $req -Force -ErrorAction SilentlyContinue
                shutdown.exe /r /t 10 /c "FleetWatch: operator-requested reboot after drain" 2>&1 | Out-Null
            }
        }
        }
    }
}

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

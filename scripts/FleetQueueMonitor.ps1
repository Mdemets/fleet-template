
$ErrorActionPreference='Continue'
$share='D:/fleet'
$log=Join-Path $share 'status/queue-monitor.log'
$alert=Join-Path $share 'status/queue-alert.txt'
$ctl=Join-Path $share 'control'
$alarm=Join-Path $ctl 'alarm.txt'
New-Item -ItemType Directory -Force -Path $ctl | Out-Null

function Q($m){ ((Get-Date).ToUniversalTime().ToString('o')) + '  ' + $m | Add-Content -LiteralPath $log -Encoding utf8 }

function Count-Queue { return @(Get-ChildItem (Join-Path $share 'queue') -File -Filter 'task-*.json' -ErrorAction SilentlyContinue).Count }
function Count-Recent([int]$min) { return @(Get-ChildItem (Join-Path $share 'results') -Recurse -File -Filter 'result-*.json' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTimeUtc -gt (Get-Date).ToUniversalTime().AddMinutes(-$min) }).Count }

if (Test-Path $alarm) {
    Q 'ALARM received - immediate recovery'
    $qnames=@{}
    foreach ($f in @(Get-ChildItem (Join-Path $share 'queue') -File -Filter 'task-*.json' -ErrorAction SilentlyContinue)) { $qnames[$f.Name]=$true }
    $cleared=0
    foreach ($mk in @(Get-ChildItem (Join-Path $share 'locks') -File -Filter '*.claim' -ErrorAction SilentlyContinue)) {
        $name = $mk.Name -replace '\.claim$',''
        if ($qnames.ContainsKey($name) -and $mk.LastWriteTimeUtc -lt (Get-Date).ToUniversalTime().AddMinutes(-2)) { try { Remove-Item -LiteralPath $mk.FullName -Force -ErrorAction Stop; $cleared++ } catch { } }
    }
    Q ('alarm: cleared ' + $cleared + ' stale claim markers')
    $tA = 0
    $corpusA = Join-Path $share 'backlog/corpus.json'
    if (Test-Path $corpusA) { try { $tA = @(Get-Content $corpusA -Raw | ConvertFrom-Json | ForEach-Object { $_ }).Count } catch { } }
    $seenA = 0
    $seenAFile = Join-Path $share 'backlog/corpus-seen.txt'
    if (Test-Path $seenAFile) { $seenA = @(Get-Content $seenAFile | Where-Object { $_.Trim() }).Count }
    if ($tA -gt 0 -and $seenA -ge $tA) {
        Remove-Item $seenAFile -Force -ErrorAction SilentlyContinue
        $cycleFileA = Join-Path $share 'backlog/corpus-cycle.txt'
        @{ ts = (Get-Date).ToUniversalTime().ToString('o'); by = 'alarm' } | ConvertTo-Json | Set-Content -LiteralPath $cycleFileA -Encoding utf8
        Q 'alarm: supply was exhausted - started a new verification cycle'
    }
    try { & 'C:/Users/Maarten/fleet/FleetCorpusFinder.ps1' | Out-Null; Q 'alarm: finder kicked' } catch { Q ('alarm: finder failed - ' + $_.Exception.Message) }
    if ((Count-Recent 5) -eq 0) {
        Q 'alarm: no completions in five minutes - restarting the local agent'
        schtasks /end /tn FleetAgent 2>&1 | Out-Null
        Start-Sleep -Milliseconds 800
        schtasks /run /tn FleetAgent 2>&1 | Out-Null
    }
    Move-Item -LiteralPath $alarm -Destination (Join-Path $ctl 'alarm-done.txt') -Force -ErrorAction SilentlyContinue
    Q 'alarm: handled'
}

$queue = Count-Queue
$total = 0
$corpus = Join-Path $share 'backlog/corpus.json'
if (Test-Path $corpus) { try { $total = @(Get-Content $corpus -Raw | ConvertFrom-Json | ForEach-Object { $_ }).Count } catch { } }
$seen = 0
$seenFile = Join-Path $share 'backlog/corpus-seen.txt'
if (Test-Path $seenFile) { $seen = @(Get-Content $seenFile | Where-Object { $_.Trim() }).Count }
$remaining = $total - $seen
if ($remaining -lt 0) { $remaining = 0 }
$recent = Count-Recent 5

Q ('queue=' + $queue + ' supply_total=' + $total + ' seen=' + $seen + ' remaining=' + $remaining + ' completed5m=' + $recent)

# operator controls win: no scheduled refill while paused or draining
$stateFile = Join-Path $ctl 'state.json'
$paused = $false
if (Test-Path $stateFile) {
    try { $st = Get-Content $stateFile -Raw | ConvertFrom-Json; if ($st.pause -or $st.drain) { $paused = $true } } catch { }
}

$refillStamp = Join-Path $share 'status/last-refill.txt'
$lastRefill = [datetime]::MinValue
if (Test-Path $refillStamp) { try { $lastRefill = [datetime]::Parse((Get-Content $refillStamp -Raw).Trim()) } catch { } }
$dueMin = ((Get-Date).ToUniversalTime() - $lastRefill.ToUniversalTime()).TotalMinutes
if ($paused) {
    Q ('scheduled refill held: operator pause or drain is active (' + [int]$dueMin + ' min since last refill)')
} elseif ($dueMin -ge 10) {
    Q ('scheduled refill: ' + [int]$dueMin + ' min since the last run')
    try { & 'C:/Users/Maarten/fleet/FleetCorpusFinder.ps1' | Out-Null; (Get-Date).ToUniversalTime().ToString('o') | Set-Content -LiteralPath $refillStamp -Encoding utf8 } catch { Q ('scheduled refill failed - ' + $_.Exception.Message) }
}

if ($queue -lt 20 -and $remaining -gt 0) {
    Q ('low water: queue=' + $queue + ' - kicking the finder')
    try { & 'C:/Users/Maarten/fleet/FleetCorpusFinder.ps1' | Out-Null; (Get-Date).ToUniversalTime().ToString('o') | Set-Content -LiteralPath $refillStamp -Encoding utf8 } catch { Q ('finder failed - ' + $_.Exception.Message) }
}

if ($queue -eq 0 -and $remaining -eq 0) {
    ('supply exhausted at ' + (Get-Date).ToUniversalTime().ToString('o') + ' - refresh backlog/corpus.json, or press Alarm to force a re-verification cycle') | Set-Content -LiteralPath $alert -Encoding utf8
    Q 'SUPPLY EXHAUSTED - no task can be created'
} else {
    Remove-Item $alert -Force -ErrorAction SilentlyContinue
}

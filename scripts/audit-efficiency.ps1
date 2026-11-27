<#
  audit-efficiency.ps1 - measure fleet transport efficiency from the share.
  Reports only what the artefacts support; names the gaps instead of estimating them.
#>
[CmdletBinding()]
param([string] $Share = (Join-Path $env:SystemDrive 'fleet'), [int] $EffectiveWorkers = 2)
$ErrorActionPreference = 'Continue'

$res = @(Get-ChildItem (Join-Path $Share 'results') -Recurse -File -Filter 'result-*.json' -ErrorAction SilentlyContinue)
$rows = foreach ($f in $res) {
    $j = Get-Content $f.FullName -Raw | ConvertFrom-Json
    $c = [datetime]$j.claimedAt
    $d = [datetime]$j.finishedAt
    [pscustomobject]@{
        id = $j.id; node = $j.node; kind = $j.kind; exit = $j.exitCode
        claimed = $c; finished = $d; seconds = [math]::Round(($d - $c).TotalSeconds, 3)
    }
}

'=== throughput ==='
$n = @($rows).Count
$ok = @($rows | Where-Object { $_.exit -eq 0 }).Count
'  tasks recorded      : ' + $n
'  succeeded (exit 0)  : ' + $ok + '   failed: ' + ($n - $ok)
if ($n) { '  success rate        : ' + [math]::Round(100.0 * $ok / $n, 1) + ' %' }

'=== execution time (claimed -> finished) ==='
if ($n) {
    $s = $rows.seconds | Sort-Object
    '  min / median / max  : ' + $s[0] + ' / ' + $s[[int][math]::Floor($s.Count/2)] + ' / ' + $s[-1] + ' s'
    $busy = ($s | Measure-Object -Sum).Sum
    '  total task seconds  : ' + [math]::Round($busy,3)
}

'=== utilisation ==='
if ($n) {
    $first = ($rows.claimed | Sort-Object)[0]
    $window = ((Get-Date).ToUniversalTime() - $first.ToUniversalTime()).TotalSeconds
    $busy = (($rows.seconds | Measure-Object -Sum).Sum)
    $capacity = $EffectiveWorkers * $window
    '  measured window     : ' + [math]::Round($window/60,1) + ' min (since first claimed task)'
    '  worker capacity     : ' + $EffectiveWorkers + ' workers x ' + [math]::Round($window/60,1) + ' min = ' + [math]::Round($capacity/60,1) + ' worker-minutes'
    '  busy                : ' + [math]::Round($busy/60,3) + ' worker-minutes'
    '  utilisation         : ' + [math]::Round(100.0 * $busy / [math]::Max($capacity,1), 3) + ' %'
}

'=== reaper health (from reaper.log) ==='
$log = Join-Path $Share 'reaper.log'
if (Test-Path $log) {
    $lines = Get-Content $log
    $retried = 0; $done = 0; $dead = 0; $pruned = 0
    foreach ($l in $lines) {
        if ($l -match 'retried=(\d+)') { $retried += [int]$Matches[1] }
        if ($l -match 'done=(\d+)')    { $done    += [int]$Matches[1] }
        if ($l -match 'dead=(\d+)')    { $dead    += [int]$Matches[1] }
        if ($l -match 'pruned=(\d+)')  { $pruned  += [int]$Matches[1] }
    }
    '  sweeps logged       : ' + @($lines | Where-Object { $_ -match 'sweep complete' }).Count
    '  retried / done / dead / pruned : ' + $retried + ' / ' + $done + ' / ' + $dead + ' / ' + $pruned
    $times = @($lines | ForEach-Object { if ($_ -match '^(\S+Z)') { [datetime]$Matches[1] } } | Sort-Object)
    if ($times.Count -gt 1) { '  sweep cadence       : ' + [math]::Round((($times[-1] - $times[0]).TotalSeconds / ($times.Count-1)), 1) + ' s' }
}

'=== not measurable from these artefacts ==='
'  queue wait (submit -> claim) : no submittedAt is recorded; the queue file is deleted on claim'
'  worker idle vs busy          : heartbeat carries only node and timestamp'
'  retry cost                   : reaper counts retries but not the work they duplicated'
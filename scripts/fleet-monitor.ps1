<#
  fleet-monitor.ps1 - periodic health check that writes a status file and logs anomalies.

  Run on the coordinator every few minutes. It exists because this fleet's failures are
  silent: an agent that stops claiming, a claim stuck under a dead worker, a queue growing
  while nothing finishes. None of those raise an error anywhere - they just stop contributing.
#>
[CmdletBinding()]
param(
  [string] $Share = '',
  [int] $HeartbeatLimitSeconds = 120,
  [int] $LockLimit = 25,
  [int] $ClaimLimit = 80
)
$ErrorActionPreference = 'SilentlyContinue'
# the station's own coordinator.unc is the source of truth for where the share is
if (-not $Share) {
    $uncF = Join-Path (Split-Path -Parent $PSCommandPath) 'coordinator.unc'
    if (-not (Test-Path $uncF)) { $uncF = 'C:\fleet\coordinator.unc' }
    if (Test-Path $uncF) { $Share = (Get-Content $uncF -Raw).Trim() }
    if (-not $Share) { $Share = (Join-Path $env:SystemDrive 'fleet') }
}
$statusDir = Join-Path $Share 'status'
New-Item -ItemType Directory -Force -Path $statusDir | Out-Null
$log = Join-Path $statusDir 'monitor.log'

$anomalies = @()
$nodes = @{}

$hbs = Get-ChildItem (Join-Path $Share 'results') -Recurse -File -Filter 'heartbeat.json'
foreach ($hb in $hbs) {
    $node = $hb.Directory.Name
    $age = [int]((Get-Date).ToUniversalTime() - $hb.LastWriteTime.ToUniversalTime()).TotalSeconds
    $active = $null
    try { $active = ((Get-Content $hb.FullName -Raw | ConvertFrom-Json).active) } catch { }
    $nodes[$node] = @{ heartbeatAgeSeconds = $age; active = $active }
    if ($age -gt $HeartbeatLimitSeconds) { $anomalies += ('stale heartbeat: ' + $node + ' ' + $age + 's') }
}

$queue = @(Get-ChildItem (Join-Path $Share 'queue') -File -Filter '*.json').Count
$claimed = @(Get-ChildItem (Join-Path $Share 'claimed') -Recurse -File -Filter '*.json' | Where-Object { $_.Directory.Name -ne 'done' }).Count
$locks = @(Get-ChildItem (Join-Path $Share 'locks') -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddMinutes(-15) }).Count

if ($locks -gt $LockLimit) { $anomalies += ('claim markers accumulating: ' + $locks) }
if ($claimed -gt $ClaimLimit) { $anomalies += ('claims outstanding: ' + $claimed) }

# a queue that is not shrinking is a stall even when every heartbeat is fresh
if ($queue -gt 0) {
    $recent = @(Get-ChildItem (Join-Path $Share 'results') -Recurse -File -Filter 'result-*.json' | Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-5) }).Count
    if ($recent -eq 0) { $anomalies += ('queue stalled: ' + $queue + ' waiting, no result in 5 min') }
}

# Per-node activity, derived from results (authoritative, unlike log line counts):
# what finished recently, how long it took, and whether anything failed.
$activity = [ordered]@{}
foreach ($nodeName in @($nodes.Keys)) {
    $res = @(Get-ChildItem (Join-Path $Share 'results') -Recurse -File -Filter 'result-*.json' | Where-Object { $_.Directory.Parent.Name -eq $nodeName -or $_.Directory.Name -eq $nodeName })
    $recent = @($res | Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-15) })
    $durations = @()
    $fails = 0
    foreach ($rf in $recent) {
        try {
            $j = Get-Content $rf.FullName -Raw | ConvertFrom-Json
            if ($j.claimedAt -and $j.finishedAt) {
                $d = ([datetime]::Parse($j.finishedAt).ToUniversalTime() - [datetime]::Parse($j.claimedAt).ToUniversalTime()).TotalMilliseconds
                if ($d -ge 0) { $durations += [int]$d }
            }
            if ($j.exitCode -ne 0) { $fails++ }
        } catch { }
    }
    $median = 0
    if ($durations.Count) { $median = ($durations | Sort-Object)[[int]($durations.Count / 2)] }
    $activity[$nodeName] = [ordered]@{ finishedLast15Min = $recent.Count; medianMs = $median; failures = $fails }
}

$status = [ordered]@{
    ts = (Get-Date).ToUniversalTime().ToString('o')
    queue = $queue; claimed = $claimed; locks = $locks
    nodes = $nodes
    activity = $activity
    anomalies = $anomalies
    healthy = ($anomalies.Count -eq 0)
}
$status | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $statusDir 'health.json') -Encoding utf8

if ($anomalies.Count) {
    $line = (Get-Date).ToUniversalTime().ToString('o') + '  ' + ($anomalies -join ' | ')
    Add-Content -LiteralPath $log -Value $line
    Write-Output ('ANOMALY ' + $line)
} else {
    Write-Output ('ok queue=' + $queue + ' claimed=' + $claimed + ' locks=' + $locks + ' nodes=' + $nodes.Count)
}

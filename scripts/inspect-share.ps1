<#
  inspect-share.ps1 - read-only view of the fleet transport, for a monitoring agent.

  Run ON the coordinator (the machine that hosts the share); no credential is needed there,
  and nothing here writes to the share. Bindings, results, claims and markers are reported
  exactly as they stand.
#>
[CmdletBinding()]
param([string] $Share = '', [int] $HeartbeatLimitSeconds = 120, [int] $RecentMinutes = 60)
$ErrorActionPreference = 'SilentlyContinue'
if (-not $Share) {
    $unc = Join-Path (Split-Path -Parent $PSCommandPath) 'coordinator.unc'
    if (Test-Path $unc) { $Share = (Get-Content $unc -Raw).Trim() }
    if (-not $Share) { $Share = Join-Path $env:SystemDrive 'fleet' }
}
$contains = { param($p) @(Get-ChildItem $p -File -Filter '*.json' -ErrorAction SilentlyContinue).Count }
$claims = @(Get-ChildItem (Join-Path $Share 'claimed') -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object { $_.Directory.Name -ne 'done' }).Count
$locks = @(Get-ChildItem (Join-Path $Share 'locks') -File -ErrorAction SilentlyContinue).Count
$queue = & $contains (Join-Path $Share 'queue')
  'queue={0}  claimed={1}  locks={2}' -f $queue, $claims, $locks
foreach ($hb in @(Get-ChildItem (Join-Path $Share 'results') -Recurse -File -Filter 'heartbeat.json')) {
    $age = [int]((Get-Date).ToUniversalTime() - $hb.LastWriteTime.ToUniversalTime()).TotalSeconds
    $act = try { (Get-Content $hb.FullName -Raw | ConvertFrom-Json).active } catch { '?' }
    '  {0,-10} heartbeat={1,4}s active={2} {3}' -f $hb.Directory.Name, $age, $act, $(if ($age -gt $HeartbeatLimitSeconds) { 'STALE' } else { 'ok' })
}
$recent = @(Get-ChildItem (Join-Path $Share 'results') -Recurse -File -Filter 'result-*.json' | Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-$RecentMinutes) })
$bad = @($recent | ForEach-Object { Get-Content $_.FullName -Raw | ConvertFrom-Json } | Where-Object { $_.exitCode -ne 0 })
  'results last {0} min: {1}  non-zero: {2}' -f $RecentMinutes, $recent.Count, $bad.Count
$bad | Select-Object -First 5 | ForEach-Object { '    FAIL ' + $_.id + ' node=' + $_.node + ' exit=' + $_.exitCode }
$rl = Join-Path $Share 'reaper.log'
if (Test-Path $rl) { '  reaper: ' + (Get-Content $rl -Tail 1) }
$h = Join-Path $Share 'status\health.json'
if (Test-Path $h) { $j = Get-Content $h -Raw | ConvertFrom-Json; '  monitor: healthy=' + $j.healthy + ' anomalies=' + @($j.anomalies).Count }
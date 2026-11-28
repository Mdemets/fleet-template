
$ErrorActionPreference='Continue'
$share='D:/fleet'
$log=Join-Path $share 'status/repo-watch.log'
function L($m){ ((Get-Date).ToUniversalTime().ToString('o')) + '  ' + $m | Add-Content -LiteralPath $log -Encoding utf8 }

$ctl = Join-Path $share 'control/state.json'
if (Test-Path $ctl) { try { $cs = Get-Content $ctl -Raw | ConvertFrom-Json; if ($cs.pause -or $cs.drain) { L 'held: operator pause or drain'; exit 0 } } catch { } }

$corpusPath = Join-Path $share 'backlog/corpus.json'
if (-not (Test-Path $corpusPath)) { L 'no corpus to merge into'; exit 0 }
$corpus = @(Get-Content $corpusPath -Raw | ConvertFrom-Json | ForEach-Object { $_ })
$have = @{}; foreach ($i in $corpus) { $have[[string]$i.r + '#' + [string]$i.n] = $true }

# per-repo ETag + last update time: an unchanged repo answers 304 and costs no quota
$statePath = Join-Path $share 'status/repo-etags.json'
$state = @{}
if (Test-Path $statePath) { try { $raw = Get-Content $statePath -Raw | ConvertFrom-Json; foreach ($p in $raw.PSObject.Properties) { $state[$p.Name] = $p.Value } } catch { } }

$repos = @('Marvisak/VIctory','JMAN730/project-flamingo')
$added = 0; $notModified = 0; $requests = 0
$ua = 'fleet-repo-watch'

foreach ($r in $repos) {
  $ston = $state[$r]
  $uri = 'https://api.github.com/repos/' + $r + '/issues?state=all&sort=updated&direction=desc&per_page=50'
  $since = $null
  if ($ston -and $ston.since) { $since = [string]$ston.since; $uri = $uri + '&since=' + [uri]::EscapeDataString($since) }

  $headers = @{ 'User-Agent' = $ua; 'Accept' = 'application/vnd.github+json' }
  if ($ston -and $ston.etag) { $headers['If-None-Match'] = [string]$ston.etag }

  $resp = $null; $etag = $null; $status = 200
  try {
    $resp = Invoke-WebRequest -Uri $uri -Headers $headers -UseBasicParsing -TimeoutSec 25
    $requests++
    $etag = $resp.Headers['ETag']
  } catch {
    $code = 0
    try { $code = [int]$_.Exception.Response.StatusCode } catch { }
    if ($code -eq 304) { $notModified++; L ('polled ' + $r + ': 304 not modified (no quota used)'); continue }
    L ('poll failed ' + $r + ' - ' + $_.Exception.Message)
    continue
  }

  # a JSON array must be enumerated, not wrapped: PowerShell otherwise yields the array as one item
  $items = @($resp.Content | ConvertFrom-Json | ForEach-Object { $_ })
  $new = 0
  foreach ($i in $items) {
    $key = $r + '#' + $i.number
    if ($have.ContainsKey($key)) { continue }
    $body = [string]$i.body
    $commits = @([regex]::Matches($body, '\b[0-9a-f]{7,40}\b') | ForEach-Object { $_.Value } | Select-Object -Unique -First 6)
    $plain = $body -replace '\s+',' '
    $corpus += [pscustomobject]@{
      r = $r; n = $i.number;
      t = ([string]$i.title).Substring(0, [Math]::Min(140, ([string]$i.title).Length));
      pr = [bool]$i.pull_request; c = @($commits);
      b = if ($plain.Length -gt 400) { $plain.Substring(0,400) } else { $plain }
    }
    $have[$key] = $true
    $new++; $added++
  }
  $state[$r] = [pscustomobject]@{ etag = [string]$etag; since = (Get-Date).ToUniversalTime().ToString('o') }
  L ('polled ' + $r + ': ' + $items.Count + ' returned, new=' + $new)
}

$state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding utf8

if ($added -gt 0) {
  $corpus | ConvertTo-Json -Depth 5 -Compress | Set-Content -LiteralPath $corpusPath -Encoding utf8
  [ordered]@{ ts = (Get-Date).ToUniversalTime().ToString('o'); added = $added; repos = $repos } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $share 'status/repo-change.json') -Encoding utf8
  ((Get-Date).ToUniversalTime().AddMinutes(-11).ToString('o')) | Set-Content -LiteralPath (Join-Path $share 'status/last-refill.txt') -Encoding utf8
  L ('corpus grew by ' + $added + ' - refill signalled')
  try { & 'C:/Users/Maarten/fleet/FleetCorpusFinder.ps1' | Out-Null; L 'refill run after merge' } catch { L ('refill failed - ' + $_.Exception.Message) }
} else {
  L ('no new issues (corpus=' + $corpus.Count + ', requests=' + $requests + ', not_modified=' + $notModified + ')')
}
Write-Output ('added=' + $added + ' requests=' + $requests + ' 304=' + $notModified)

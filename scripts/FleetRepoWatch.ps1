
$ErrorActionPreference='Continue'
$share='D:/fleet'
$log=Join-Path $share 'status/repo-watch.log'
function L($m){ ((Get-Date).ToUniversalTime().ToString('o')) + '  ' + $m | Add-Content -LiteralPath $log -Encoding utf8 }

$discPath = Join-Path $share 'status/repo-discovery.json'
$disc = $null
if (Test-Path $discPath) { try { $disc = Get-Content $discPath -Raw | ConvertFrom-Json } catch { } }
if (-not $disc) { $disc = [pscustomobject]@{ open=$false; since=$null; discovered=0; reported=0; last=$null; lastPoll=$null; lastResult='never polled' } }
foreach ($f in @('open','discovered','reported','lastPoll','lastResult')) { if (-not ($disc.PSObject.Properties.Name -contains $f)) { $disc | Add-Member -NotePropertyName $f -NotePropertyValue ($(if ($f -in @('discovered','reported')) { 0 } elseif ($f -eq 'open') { $false } else { $null })) -Force } }
function Save-Disc($d){ $d | ConvertTo-Json -Compress | Set-Content -LiteralPath $discPath -Encoding utf8 }

$ctl = Join-Path $share 'control/state.json'
$held = $false
if (Test-Path $ctl) { try { $cs = Get-Content $ctl -Raw | ConvertFrom-Json; if ($cs.pause -or $cs.drain) { $held = $true } } catch { } }
if ($held) {
    $disc.lastPoll = (Get-Date).ToUniversalTime().ToString('o'); $disc.lastResult = 'held: operator pause or drain'; Save-Disc $disc
    L 'held: operator pause or drain'
    exit 0
}

$corpusPath = Join-Path $share 'backlog/corpus.json'
if (-not (Test-Path $corpusPath)) { $disc.lastResult = 'no corpus'; Save-Disc $disc; L 'no corpus to merge into'; exit 0 }
$corpus = @(Get-Content $corpusPath -Raw | ConvertFrom-Json | ForEach-Object { $_ })
$have = @{}; foreach ($i in $corpus) { $have[[string]$i.r + '#' + [string]$i.n] = $true }

$statePath = Join-Path $share 'status/repo-etags.json'
$state = @{}
if (Test-Path $statePath) { try { $raw = Get-Content $statePath -Raw | ConvertFrom-Json; foreach ($p in $raw.PSObject.Properties) { $state[$p.Name] = $p.Value } } catch { } }

$repos = @('Marvisak/VIctory','JMAN730/project-flamingo')
$added = 0; $notModified = 0; $requests = 0
$ua = 'fleet-repo-watch'

foreach ($r in $repos) {
  $ston = $state[$r]
  $uri = 'https://api.github.com/repos/' + $r + '/issues?state=all&sort=updated&direction=desc&per_page=50'
  $headers = @{ 'User-Agent' = $ua; 'Accept' = 'application/vnd.github+json' }
  if ($ston -and $ston.etag) { $headers['If-None-Match'] = [string]$ston.etag }

  try {
    $resp = Invoke-WebRequest -Uri $uri -Headers $headers -UseBasicParsing -TimeoutSec 25
    $requests++
    $etag = $resp.Headers['ETag']
  } catch {
    $code = 0; try { $code = [int]$_.Exception.Response.StatusCode } catch { }
    if ($code -eq 304) { $notModified++; L ('polled ' + $r + ': 304 not modified (no quota used)'); continue }
    L ('poll failed ' + $r + ' - ' + $_.Exception.Message)
    $disc.lastResult = 'poll failed for ' + $r
    continue
  }

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

  if (-not $disc.open) { $disc.open = $true; $disc.since = (Get-Date).ToUniversalTime().ToString('o'); $disc.reported = 0 }
  $disc.discovered = [int]$disc.discovered + $added
  $disc.last = (Get-Date).ToUniversalTime().ToString('o')
  Save-Disc $disc
  L ('discovery open since ' + $disc.since + ': ' + $added + ' topic(s) found, ' + $disc.discovered + ' pending dispatch')

  try {
    & 'C:/Users/Maarten/fleet/FleetCorpusFinder.ps1' | Out-Null
    $disc.reported = [int]$disc.reported + $disc.discovered
    $disc.discovered = 0            # pulled in: the counter starts again from nothing
    $disc.last = (Get-Date).ToUniversalTime().ToString('o')
    L ('refill run - ' + $disc.reported + ' topic(s) reported to the queue this window, counter reset')
  } catch { L ('refill failed - ' + $_.Exception.Message) }
} else {
  if ($disc.open -and $disc.last) {
    try {
      if (((Get-Date).ToUniversalTime() - [datetime]::Parse([string]$disc.last).ToUniversalTime()).TotalMinutes -ge 10) {
        $disc.open = $false
        L ('discovery window closed: ' + $disc.reported + ' topic(s) reported in total')
      }
    } catch { }
  }
  L ('no new issues (corpus=' + $corpus.Count + ', requests=' + $requests + ', not_modified=' + $notModified + ', pending=' + $disc.discovered + ')')
}

$disc.lastPoll = (Get-Date).ToUniversalTime().ToString('o')
$disc.lastResult = ('new=' + $added + ' not_modified=' + $notModified + ' requests=' + $requests)
Save-Disc $disc
Write-Output ('added=' + $added + ' requests=' + $requests + ' 304=' + $notModified + ' pending=' + $disc.discovered)

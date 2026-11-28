
$ErrorActionPreference='Continue'
. 'C:/Users/Maarten/fleet/FleetCounter.ps1'
$share='D:/fleet'
$log='C:/Users/Maarten/fleet/logs/feeder.log'
function L($m){ (Get-Date).ToUniversalTime().ToString('o') + '  ' + $m | Out-File $log -Append -Encoding utf8 }

$TargetDepth=800; $Budget=150; $CooldownMin=180
$ctl = Join-Path $share 'control/state.json'
if (Test-Path $ctl) { try { $cs = Get-Content $ctl -Raw | ConvertFrom-Json; if ($cs.pause -or $cs.drain) { L ('feeder paused by operator (pause=' + $cs.pause + ' drain=' + $cs.drain + ')'); exit 0 } } catch { } }
$queueNow=@(Get-ChildItem (Join-Path $share 'queue') -File -Filter 'task-*.json' -ErrorAction SilentlyContinue).Count
if ($queueNow -ge $TargetDepth) { exit 0 }
$room=$TargetDepth-$queueNow; if ($room -gt $Budget) { $room=$Budget }

$corpus=Join-Path $share 'backlog/corpus.json'
if (-not (Test-Path $corpus)) { exit 0 }
$items=@(Get-Content $corpus -Raw | ConvertFrom-Json | ForEach-Object { $_ })
if ($items.Count -eq 0) { exit 0 }

$state=Join-Path $share 'backlog/corpus-seen.txt'
$cycleFile=Join-Path $share 'backlog/corpus-cycle.txt'
$seen=@(); if (Test-Path $state) { $seen=@(Get-Content $state | Where-Object { $_.Trim() }) }
$seenSet=@{}; foreach ($s in $seen) { $seenSet[$s]=$true }

if ($seenSet.Count -ge $items.Count) {
  $last=[datetime]::MinValue
  if (Test-Path $cycleFile) { try { $last=[datetime]::Parse((Get-Content $cycleFile -Raw).Split([char]124)[0]) } catch { } }
  if (((Get-Date).ToUniversalTime() - $last.ToUniversalTime()).TotalMinutes -lt $CooldownMin) { exit 0 }
  $cycle=1; if (Test-Path $cycleFile) { try { $cycle=[int]((Get-Content $cycleFile -Raw).Split([char]124)[1]) + 1 } catch { } }
  ((Get-Date).ToUniversalTime().ToString('o') + '|' + $cycle) | Set-Content -LiteralPath $cycleFile -Encoding utf8
  $seen=@(); $seenSet=@{}; Remove-Item $state -Force -ErrorAction SilentlyContinue
  L ('corpus exhausted - re-verification cycle ' + $cycle + ' over ' + $items.Count + ' items')
}

$template = @'
$ErrorActionPreference='Continue'
$repo='C:/Users/Maarten/projects/victory'
if (-not (Test-Path (Join-Path $repo '.git'))) { $repo='C:/Temp/v-63bcca4' }
Write-Output ('NODE=' + $env:COMPUTERNAME)
Write-Output ('ITEM=__REPO__#__N__')
Write-Output ('TITLE=__TITLE__')
if (-not (Test-Path (Join-Path $repo '.git'))) { Write-Output 'NO_REPO'; exit 0 }
Write-Output ('BASE=' + (git -C $repo rev-parse --short HEAD 2>$null))
$hit=0; $miss=0; $invalid=0
foreach ($c in @(__COMMITS__)) {
  if (-not $c) { continue }
  $t=(git -C $repo cat-file -t $c 2>$null)
  if ($t -ne 'commit') { $invalid++; continue }
  git -C $repo merge-base --is-ancestor $c HEAD 2>$null
  if ($LASTEXITCODE -eq 0) { $hit++ } else { $miss++ }
}
Write-Output ('IN_HEAD=' + $hit + ' NOT_IN_HEAD=' + $miss + ' INVALID=' + $invalid)
'@

$stamp=(Get-Date).ToUniversalTime().ToString('yyMMddHHmmss')
$made=0
foreach ($i in $items) {
  if ($made -ge $room) { break }
  $key=[string]$i.r + '#' + [string]$i.n
  if ($seenSet.ContainsKey($key)) { continue }
  if (@($i.c).Count -eq 0) { $seenSet[$key]=$true; $seen += $key; continue }
  $title=([string]$i.t) -replace '[|\r\n]',' '
  if ($title.Length -gt 80) { $title=$title.Substring(0,80) }
  $commits=(@($i.c) | ForEach-Object { "'" + $_ + "'" }) -join ','
  $script=$template.Replace('__REPO__',[string]$i.r).Replace('__N__',[string]$i.n).Replace('__TITLE__',$title).Replace('__COMMITS__',$commits)
  $id='cor' + $i.n + '-' + $stamp
  $task=[ordered]@{ id=$id; kind='powershell'; payload=@{ script=$script; topic=($i.r + ' - ' + $title) }; timeoutSeconds=180 }
  try {
    $task | ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath (Join-Path (Join-Path $share 'queue') ('task-' + $id + '.json')) -Encoding utf8
    $seenSet[$key]=$true; $seen += $key; $made++
  } catch { break }
}
if ($made -gt 0) { $null=Add-Created $made 'corpus'; $seen | Set-Content -LiteralPath $state -Encoding utf8; L ('corpus: created ' + $made + ' tasks total=' + (Get-Created)) }

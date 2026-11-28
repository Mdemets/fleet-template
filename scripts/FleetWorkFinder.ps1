
$ErrorActionPreference='Continue'
. 'C:\Users\Maarten\fleet\FleetCounter.ps1'
$share='D:\fleet'
$log='C:\Users\Maarten\fleet\logs\feeder.log'
function L($m){ (Get-Date).ToUniversalTime().ToString('o') + '  ' + $m | Out-File $log -Append -Encoding utf8 }

$TargetDepth=1200; $Chunk=2
$queueNow=@(Get-ChildItem (Join-Path $share 'queue') -File -Filter 'task-*.json' -ErrorAction SilentlyContinue).Count
if ($queueNow -ge $TargetDepth) { exit 0 }
$room = $TargetDepth - $queueNow
if ($room -gt 96) { $room = 96 }

$template = @'
$ErrorActionPreference='Continue'
$repo='__REPO__'
$nums=@(__NUMS__)
Write-Output ('NODE=' + $env:COMPUTERNAME)
Write-Output ('BATCH=' + $nums.Count + ' repo=' + $repo)
$local='C:\Users\Maarten\projects\victory'
$alt='C:\Temp\v-63bcca4'
if (Test-Path (Join-Path $alt '.git')) { $local=$alt }
$hasRepo = Test-Path (Join-Path $local '.git')
if ($hasRepo) { Write-Output ('BASE=' + (git -C $local rev-parse --short HEAD 2>&1)) }
foreach ($num in $nums) {
  try { $iss = Invoke-RestMethod -Uri ('https://api.github.com/repos/' + $repo + '/issues/' + $num) -Headers @{ 'Accept'='application/vnd.github+json'; 'User-Agent'='fleet' } -TimeoutSec 20 -ErrorAction Stop } catch { Write-Output ('  #' + $num + ' FETCH_FAILED'); continue }
  if (-not $hasRepo) { Write-Output ('  #' + $num + ' NO_REPO'); continue }
  $cands=@([regex]::Matches([string]$iss.body,'[0-9a-f]{7,40}') | ForEach-Object { $_.Value } | Select-Object -Unique)
  $hit=0; $miss=0
  foreach ($c in $cands) {
    $t=(git -C $local cat-file -t $c 2>$null)
    if ($t -ne 'commit') { continue }
    git -C $local merge-base --is-ancestor $c HEAD 2>$null
    if ($LASTEXITCODE -eq 0) { $hit++ } else { $miss++ }
  }
  Write-Output ('  #' + $num + ' IN_HEAD=' + $hit + ' NOT_IN_HEAD=' + $miss)
}
Write-Output ('BATCH_DONE=' + $nums.Count)
'@

$cache=Join-Path $share 'backlog\issues-cache.json'
if (-not (Test-Path $cache)) { exit 0 }
$items=@(Get-Content $cache -Raw | ConvertFrom-Json | ForEach-Object { $_ })
if ($items.Count -eq 0) { exit 0 }
$state=Join-Path $share 'backlog\issues-seen.txt'
$seen=@()
if (Test-Path $state) { $seen=@(Get-Content $state | Where-Object { $_.Trim() }) }
$seenSet=@{}
foreach ($s in $seen) { $seenSet[$s]=$true }
if ($seenSet.Count -ge $items.Count) {
  $cycleFile = Join-Path $share 'backlog\cycle.txt'
  $last = [datetime]::MinValue
  if (Test-Path $cycleFile) { try { $last = [datetime]::Parse((Get-Content $cycleFile -Raw).Split([char]124)[0]) } catch { } }
  if (((Get-Date).ToUniversalTime() - $last.ToUniversalTime()).TotalSeconds -lt 120) { exit 0 }
  $cycle = 1
  if (Test-Path $cycleFile) { try { $cycle = [int]((Get-Content $cycleFile -Raw).Split([char]124)[1]) + 1 } catch { } }
  ((Get-Date).ToUniversalTime().ToString('o') + '|' + $cycle) | Set-Content -LiteralPath $cycleFile -Encoding utf8
  $seen=@(); $seenSet=@{}
  Remove-Item $state -Force -ErrorAction SilentlyContinue
  L ('backlog exhausted - re-verification cycle ' + $cycle + ' begins over ' + $items.Count + ' items')
}

$stamp=(Get-Date).ToUniversalTime().ToString('yyMMddHHmmss')
$made=0; $idx=0
$batch=@(); $batchRepo=$null
foreach ($i in $items) {
  if ($made -ge $room) { break }
  $key = $i.repo + '#' + $i.number
  if ($seenSet.ContainsKey($key)) { continue }
  if ($batch.Count -gt 0 -and $i.repo -ne $batchRepo) {
    $script = $template.Replace('__REPO__', $batchRepo).Replace('__NUMS__', ($batch -join ','))
    $id = 'bat' + $stamp + '-' + $idx
    $task = [ordered]@{ id=$id; kind='powershell'; payload=@{ script=$script }; timeoutSeconds=900; topic=([string]$i.title -replace '[|]',' ') }
    try { $task | ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath (Join-Path (Join-Path $share 'queue') ('task-' + $id + '.json')) -Encoding utf8; $made++ } catch { }
    $idx++; $batch=@()
  }
  $batchRepo=$i.repo
  $batch += [string]$i.number
  $seenSet[$key]=$true; $seen += $key
  if ($batch.Count -ge $Chunk) {
    $script = $template.Replace('__REPO__', $batchRepo).Replace('__NUMS__', ($batch -join ','))
    $id = 'bat' + $stamp + '-' + $idx
    $task = [ordered]@{ id=$id; kind='powershell'; payload=@{ script=$script }; timeoutSeconds=900; topic=([string]$i.title -replace '[|]',' ') }
    try { $task | ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath (Join-Path (Join-Path $share 'queue') ('task-' + $id + '.json')) -Encoding utf8; $made++ } catch { }
    $idx++; $batch=@()
  }
}
if ($made -gt 0) {
  $null = Add-Created $made 'issue-batch'
  $seen | Set-Content -LiteralPath $state -Encoding utf8
  L ('workfind: batches=' + $made + ' chunk=' + $Chunk + ' total=' + (Get-Created))
}

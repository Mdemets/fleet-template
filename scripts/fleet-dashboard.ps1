<#
  fleet-dashboard.ps1 - browser dashboard for the fleet, served by the coordinator.

  Per station: is it working, on what, how fast, how utilised over 15 minutes, and what failed.
  Every station the fleet knows of appears; a missing heartbeat shows as DOWN rather than vanishing.
  /health is cached ~1.5 s: computing per request was slow enough to time out under load.
#>
[CmdletBinding()]
param([int] $Port = 8080, [string] $Share = '', [string] $BindAddress = '', [int] $CacheMs = 1500)
$ErrorActionPreference = 'Continue'

if (-not $Share) {
    $unc = Join-Path (Split-Path -Parent $PSCommandPath) 'coordinator.unc'
    if (Test-Path $unc) { $Share = (Get-Content $unc -Raw).Trim() }
    if (-not $Share) { $Share = Join-Path $env:SystemDrive 'fleet' }
}
if (-not $BindAddress) {
    $BindAddress = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.*' } |
        Select-Object -First 1).IPAddress
}
$statusDir = Join-Path $Share 'status'
New-Item -ItemType Directory -Force -Path $statusDir | Out-Null
$log = Join-Path $statusDir 'dashboard.log'
function Dlog([string]$m) { try { Add-Content -LiteralPath $log -Value ((Get-Date).ToUniversalTime().ToString('HH:mm:ssZ') + '  ' + $m) } catch { } }
$script:cache = @{ ts = [datetime]::MinValue; body = '' }

function Compute {
    $nowUtc = (Get-Date).ToUniversalTime()
    $qFiles = @(Get-ChildItem (Join-Path $Share 'queue') -File -Filter '*.json' -ErrorAction SilentlyContinue)
    $oldest = 0
    if ($qFiles.Count) { $oldest = [int]($nowUtc - ($qFiles | Sort-Object LastWriteTime | Select-Object -First 1).LastWriteTime.ToUniversalTime()).TotalSeconds }
    $claimed = @(Get-ChildItem (Join-Path $Share 'claimed') -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object { $_.Directory.Name -ne 'done' }).Count
    $locks = @(Get-ChildItem (Join-Path $Share 'locks') -File -ErrorAction SilentlyContinue).Count

    $roster = @()
    $rf = Join-Path $Share 'fleet-roster.json'
    if (Test-Path $rf) { try { $roster = @((Get-Content $rf -Raw | ConvertFrom-Json).nodes) } catch { } }
    $known = @()
    $known += @(Get-ChildItem (Join-Path $Share 'results') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $known += @(Get-ChildItem (Join-Path $Share 'claimed') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name } | Where-Object { $_ -ne 'done' })
    $known += $roster
    $known = @($known | Where-Object { $_ } | Sort-Object -Unique)

    $nodes = [ordered]@{}
    foreach ($name in $known) {
        $resDir = Join-Path (Join-Path $Share 'results') $name
        $claimDir = Join-Path (Join-Path $Share 'claimed') $name
        $claimFiles = @(Get-ChildItem $claimDir -File -Filter 'task-*.json' -ErrorAction SilentlyContinue)
        $running = @($claimFiles | ForEach-Object { $_.BaseName -replace '^task-', '' } | Sort-Object | Select-Object -First 4)
        $res = @(Get-ChildItem $resDir -File -Filter 'result-*.json' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt $nowUtc.AddMinutes(-30) })
        $series = [int[]]::new(30)
        foreach ($f in $res) {
            $mins = [int]($nowUtc - $f.LastWriteTime.ToUniversalTime()).TotalMinutes
            if ($mins -ge 0 -and $mins -lt 30) { $i = 29 - $mins; $series[$i] = $series[$i] + 1 }
        }
        $hb = Join-Path $resDir 'heartbeat.json'
        if (-not (Test-Path $hb)) {
            $nodes[$name] = [ordered]@{ state = 'DOWN'; heartbeatAge = -1; active = 0; running = $running; runningCount = $claimFiles.Count; finished15m = 0; medianMs = 0; failures = 0; utilPct = 0; series = $series }
            continue
        }
        $age = [int]($nowUtc - (Get-Item $hb).LastWriteTime.ToUniversalTime()).TotalSeconds
        $active = 0
        try { $active = [int]((Get-Content $hb -Raw | ConvertFrom-Json).active) } catch { }
        $recent = @($res | Sort-Object LastWriteTime -Descending | Select-Object -First 80)
        $fails = 0; $busyMs = 0; $durs = @()
        foreach ($r in $recent) {
            try {
                $j = Get-Content $r.FullName -Raw | ConvertFrom-Json
                if ($j.exitCode -ne 0) { $fails++ }
                if ($j.claimedAt -and $j.finishedAt) {
                    $d = ([datetime]::Parse($j.finishedAt).ToUniversalTime() - [datetime]::Parse($j.claimedAt).ToUniversalTime()).TotalMilliseconds
                    if ($d -ge 0) {
                        $durs += [int]$d
                        if ($r.LastWriteTime -gt $nowUtc.AddMinutes(-15)) { $busyMs += $d }
                    }
                }
            } catch { }
        }
        $med = 0
        if ($durs.Count) { $med = ($durs | Sort-Object)[[int]($durs.Count / 2)] }
        $util = [math]::Min(100, [math]::Round(100.0 * $busyMs / (15 * 60 * 1000), 1))
        $state = if ($age -gt 120) { 'STALE' } else { 'ok' }
        $nodes[$name] = [ordered]@{ state = $state; heartbeatAge = $age; active = $active; running = $running; runningCount = $claimFiles.Count; finished15m = @($res | Where-Object { $_.LastWriteTime -gt $nowUtc.AddMinutes(-15) }).Count; medianMs = $med; failures = $fails; utilPct = $util; series = $series }
    }

    $order = $nodes.Keys | Sort-Object @{ Expression = { if ($nodes[$_].state -eq 'DOWN') { 2 } elseif ($nodes[$_].active -gt 0) { 0 } else { 1 } } }, @{ Expression = { $nodes[$_].active }; Descending = $true }
    $sorted = [ordered]@{}
    foreach ($k in $order) { $sorted[$k] = $nodes[$k] }
    $working = @($nodes.Keys | Where-Object { $nodes[$_].active -gt 0 }).Count
    $reaper = 'n/a'
    $rl = Join-Path $Share 'reaper.log'
    if (Test-Path $rl) {
        $last = (Get-Content $rl -Tail 1 -ErrorAction SilentlyContinue | Select-Object -Last 1)
        $reaper = [string]$last
        if ($reaper.Length -gt 200) { $reaper = $reaper.Substring(0, 200) }
    }
    $monitor = 'n/a'
    $h = Join-Path $statusDir 'health.json'
    if (Test-Path $h) { try { $m = Get-Content $h -Raw | ConvertFrom-Json; $monitor = 'healthy=' + $m.healthy + ' anomalies=' + @($m.anomalies).Count } catch { } }
    [ordered]@{ ts = $nowUtc.ToString('o'); queue = $qFiles.Count; queueOldestSec = $oldest; claimed = $claimed; locks = $locks; working = $working; total = $nodes.Count; nodes = $sorted; reaper = $reaper; monitor = $monitor }
}

function Health {
    $now = Get-Date
    if ($script:cache.body -and ($now - $script:cache.ts).TotalMilliseconds -lt $CacheMs) { return $script:cache.body }
    $body = (Compute | ConvertTo-Json -Depth 6 -Compress)
    if ($body.Length -gt 200000) {
        Dlog ('snapshot too large (' + $body.Length + ' bytes) - suppressed')
        $body = '{"ts":"' + (Get-Date).ToUniversalTime().ToString('o') + '","error":"snapshot too large","nodes":{},"queue":0,"claimed":0,"locks":0,"working":0,"total":0,"reaper":"","monitor":""}'
    }
    $script:cache = @{ ts = $now; body = $body }
    return $body
}

$page = @'
<!doctype html><html><head><meta charset="utf-8"><title>Fleet</title>
<style>
:root{color-scheme:dark}body{font:13px/1.5 ui-monospace,Menlo,Consolas,monospace;background:#111;color:#e6e6e6;margin:0;padding:22px}
h1{font-size:15px;font-weight:600;margin:0 0 4px}.sub{color:#888;margin-bottom:16px;font-size:12px}
table{border-collapse:collapse;width:100%;max-width:1180px}
th,td{text-align:left;padding:7px 10px;border-bottom:1px solid #242424;vertical-align:middle}
th{color:#888;font-weight:500;font-size:11px;text-transform:uppercase;letter-spacing:.05em}
.ok{color:#4ade80}.warn{color:#fbbf24}.bad{color:#f87171}.dim{color:#666}
.kpi{display:flex;gap:16px;margin:0 0 18px;flex-wrap:wrap}
.kpi div{border:1px solid #242424;border-radius:8px;padding:8px 14px;min-width:76px}
.kpi b{display:block;font-size:18px;font-weight:600}
.kpi span{color:#888;font-size:10px;text-transform:uppercase;letter-spacing:.05em}
tr.work td{background:#12201a}tr.work td:first-child{box-shadow:inset 3px 0 0 #4ade80}
.now{font-size:12px;color:#bbb;max-width:190px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.track{display:inline-block;width:70px;height:6px;background:#242424;border-radius:3px;vertical-align:middle}
.bar{display:inline-block;height:6px;border-radius:3px;background:#4ade80;vertical-align:middle}
</style></head><body>
<h1>Fleet</h1><div class="sub" id="sub">loading</div>
<div class="kpi">
<div><span>working</span><b id="w">-</b></div>
<div><span>queue</span><b id="q">-</b></div>
<div><span>oldest queued</span><b id="qo">-</b></div>
<div><span>claimed</span><b id="c">-</b></div>
<div><span>claim markers</span><b id="l">-</b></div>
</div>
<table><thead><tr><th>station</th><th>state</th><th>hb</th><th>active</th><th>running now</th><th>done 15m</th><th>util 15m</th><th>activity, last 30 min</th><th>median</th><th>fail</th></tr></thead>
<tbody id="rows"></tbody></table>
<p class="dim" id="foot"></p>
<script>
function esc(s){return String(s).replace(/[&<>]/g,function(c){return ({'&':'&amp;','<':'&lt;','>':'&gt;'})[c];});}
function arr(v){if(Array.isArray(v))return v;if(v&&Array.isArray(v.value))return v.value;return [];}
let peak=1;
function spark(series,peak){
  const w=4,g=1,h=26;let x=0,out='';
  const list=arr(series);
  for(const v of list){
    const bh=Math.max(v>0?2:0,Math.round(h*v/peak));
    out+='<rect x="'+x+'" y="'+(h-bh)+'" width="'+w+'" height="'+bh+'" fill="'+(v>0?'#4ade80':'#242424')+'"></rect>';
    x+=w+g;
  }
  return '<svg width="'+x+'" height="'+h+'" role="img">'+out+'</svg>';
}
async function tick(){
 try{
  const r=await fetch('/health',{cache:'no-store'});const d=await r.json();
  if(d.error){throw new Error(d.error);}
  document.getElementById('w').textContent=d.working+'/'+d.total;
  document.getElementById('q').textContent=d.queue;
  document.getElementById('qo').textContent=d.queue>0?(d.queueOldestSec+'s'):'-';
  document.getElementById('c').textContent=d.claimed;
  document.getElementById('l').textContent=d.locks;
  const s=document.getElementById('sub');
  s.textContent='updated '+new Date(d.ts).toLocaleTimeString()+'  (2s refresh)';
  s.className='sub';
  const names=Object.keys(d.nodes||{});
  peak=1;
  for(const n of names){for(const v of arr(d.nodes[n].series)){if(v>peak)peak=v;}}
  let html='';
  for(const n of names){
   const v=d.nodes[n];
   const work=(v.active>0)?'work':'';
   const scls=v.state==='ok'?'ok':(v.state==='STALE'?'warn':'bad');
   const hb=v.heartbeatAge<0?'-':v.heartbeatAge+'s';
   const hcls=v.heartbeatAge<0?'bad':(v.heartbeatAge>30?'warn':'ok');
   const ids=arr(v.running);
   let now='-';
   if(ids.length){now=ids.map(esc).join(', ');if(v.runningCount>ids.length){now+=' +'+(v.runningCount-ids.length);}}
   const util=Math.min(100,Math.round(v.utilPct||0));
   html+='<tr class="'+work+'"><td>'+esc(n)+'</td><td class="'+scls+'">'+v.state+'</td>'
        +'<td class="'+hcls+'">'+hb+'</td><td>'+v.active+'</td>'
        +'<td class="now" title="'+esc(now)+'">'+now+'</td>'
        +'<td>'+v.finished15m+'</td>'
        +'<td><span class="track"><span class="bar" style="width:'+util+'%"></span></span> '+util+'%</td>'
        +'<td>'+spark(v.series,peak)+'</td>'
        +'<td>'+v.medianMs+'ms</td>'
        +'<td class="'+(v.failures?'bad':'ok')+'">'+v.failures+'</td></tr>';
  }
  document.getElementById('rows').innerHTML=html||'<tr><td colspan=10 class=dim>no stations known</td></tr>';
  document.getElementById('foot').textContent=d.reaper+'   |   monitor: '+d.monitor;
 }catch(e){
  const s=document.getElementById('sub');s.textContent='dashboard error: '+e.message;s.className='bad';
 }
}
tick();setInterval(tick,2000);
</script></body></html>
'@

$prefix = 'http://' + $BindAddress + ':' + $Port + '/'
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
try { $listener.Start() } catch { Dlog ('bind failed: ' + $_.Exception.Message); throw }
Dlog ('listening on ' + $prefix)
while ($listener.IsListening) {
    try {
        $ctx = $listener.GetContext()
        $body = if ($ctx.Request.Url.AbsolutePath -eq '/health') { Health } else { $page }
        $bytes = [Text.Encoding]::UTF8.GetBytes($body)
        $ctx.Response.ContentType = if ($ctx.Request.Url.AbsolutePath -eq '/health') { 'application/json' } else { 'text/html; charset=utf-8' }
        $ctx.Response.Headers.Add('Cache-Control','no-store')
        $ctx.Response.ContentLength64 = $bytes.Length
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $ctx.Response.Close()
    } catch { Start-Sleep -Milliseconds 150 }
}
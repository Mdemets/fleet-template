<#
  fleet-dashboard.ps1 - browser dashboard for the fleet, served by the coordinator.

  Per station: is it working, on what, how fast, how utilised over 15 minutes, and what failed.
  Every station the fleet knows of appears; a missing heartbeat shows as DOWN rather than vanishing.
  /health is cached ~1.5 s: computing per request was slow enough to time out under load.
#>
[CmdletBinding()]
param([int] $Port = 8080, [string] $Share = '', [string] $BindAddress = '', [int] $CacheMs = 8000)
$ErrorActionPreference = 'Continue'
. 'C:\Users\Maarten\fleet\FleetCounter.ps1'
$script:baseCreated = Get-Created
$script:doneCache = -1
$script:doneCacheAt = [datetime]::MinValue
$script:winCache = $null
$script:winAt = [datetime]::MinValue
function Get-Tput {
    $rows = @()
    $f = Join-Path (Join-Path $Share 'status') 'queue-monitor.log'
    if (-not (Test-Path $f)) { return $rows }
    foreach ($ln in @(Get-Content $f -Tail 90 -ErrorAction SilentlyContinue)) {
        $m = [regex]::Match($ln, '^(\S+)\s+queue=(\d+).*completed5m=(\d+)')
        if ($m.Success) { $rows += [ordered]@{ t = $m.Groups[1].Value; q = [int]$m.Groups[2].Value; c = [int]$m.Groups[3].Value } }
    }
    return $rows
}

function Get-WatchRepos {
    $f = Join-Path (Join-Path $Share 'status') 'repo-etags.json'
    if (Test-Path $f) { try { (Get-Content $f -Raw -ErrorAction Stop | ConvertFrom-Json).PSObject.Properties.Name } catch { } }
}

function Get-Discovery {
    $f = Join-Path (Join-Path $Share 'status') 'repo-discovery.json'
    if (Test-Path $f) { try { return (Get-Content $f -Raw -ErrorAction Stop | ConvertFrom-Json) } catch { } }
    return $null
}

function Get-Scope {
    $f = Join-Path (Join-Path $Share 'status') 'scope.txt'
    if (Test-Path $f) { try { return ((Get-Content $f -Raw -ErrorAction Stop).Trim()) } catch { } }
    return ''
}

function Get-Supply {
    $f = Join-Path (Join-Path $Share 'status') 'supply.json'
    if (-not (Test-Path $f)) { return $null }
    try { return (Get-Content $f -Raw -ErrorAction Stop | ConvertFrom-Json) } catch { return $null }
}

function Get-Specs {
    try {
        $f = Join-Path (Join-Path $Share 'status') 'specs.json'
        if (Test-Path $f) { return (Get-Content $f -Raw -ErrorAction Stop | ConvertFrom-Json) }
    } catch { }
    return $null
}

function Win-Counts {
    if (((Get-Date).ToUniversalTime() - $script:winAt).TotalSeconds -lt 60 -and $script:winCache) { return $script:winCache }
    $now = (Get-Date).ToUniversalTime()
    $b = [ordered]@{ h1 = 0; h6 = 0; d1 = 0; w1 = 0; all = 0 }
    try {
        foreach ($f in @(Get-ChildItem (Join-Path $Share 'results') -Recurse -File -Filter 'result-*.json' -ErrorAction SilentlyContinue)) {
            $age = ($now - $f.LastWriteTimeUtc).TotalHours
            $b.all++
            if ($age -le 168) { $b.w1++ }
            if ($age -le 24) { $b.d1++ }
            if ($age -le 6) { $b.h6++ }
            if ($age -le 1) { $b.h1++ }
        }
    } catch { }
    $script:winCache = $b
    $script:winAt = $now
    return $b
}

function Done-Total {
    if (((Get-Date).ToUniversalTime() - $script:doneCacheAt).TotalSeconds -gt 60) {
        try { $script:doneCache = @(Get-ChildItem (Join-Path $Share 'results') -Recurse -File -Filter 'result-*.json' -ErrorAction SilentlyContinue).Count } catch { }
        $script:doneCacheAt = (Get-Date).ToUniversalTime()
    }
    return [int]$script:doneCache
}
$script:startedAt = (Get-Date).ToUniversalTime().ToString('o')

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
        $res = @(Get-ChildItem $resDir -File -Filter 'result-*.json' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime.ToUniversalTime() -gt $nowUtc.AddMinutes(-30) })
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
                        if ($r.LastWriteTime.ToUniversalTime() -gt $nowUtc.AddMinutes(-15)) { $busyMs += $d }
                    }
                }
            } catch { }
        }
        $med = 0
        if ($durs.Count) { $med = ($durs | Sort-Object)[[int]($durs.Count / 2)] }
        $util = [math]::Min(100, [math]::Round(100.0 * $busyMs / (15 * 60 * 1000), 1))
        $state = if ($age -gt 120) { 'STALE' } else { 'ok' }
        $nodes[$name] = [ordered]@{ state = $state; heartbeatAge = $age; active = $active; running = $running; runningCount = $claimFiles.Count; finished15m = @($res | Where-Object { $_.LastWriteTime.ToUniversalTime() -gt $nowUtc.AddMinutes(-15) }).Count; medianMs = $med; failures = $fails; utilPct = $util; series = $series }
    }

    $order = $nodes.Keys | Sort-Object   # fixed order: a three-station board does not need to rearrange itself
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
    $ev = @()
$topicLookups = 0
$hbRoot = Join-Path $Share 'results'
foreach ($nd in @(Get-ChildItem $hbRoot -Directory -ErrorAction SilentlyContinue)) {
    $hf = Join-Path $nd.FullName 'heartbeat.json'
    if (Test-Path $hf) {
        try {
            $hj = Get-Content $hf -Raw -ErrorAction Stop | ConvertFrom-Json
            if ($hj.ids) { foreach ($rid in @($hj.ids)) { if ($rid) { $tp = ''; $cf = Join-Path (Join-Path (Join-Path $Share 'claimed') $nd.Name) ('task-' + $rid + '.json'); try { if (Test-Path $cf) { $tj = Get-Content $cf -Raw -ErrorAction Stop | ConvertFrom-Json; if ($tj.payload.topic) { $tp = [string]$tj.payload.topic } elseif ($tj.topic) { $tp = [string]$tj.topic } } } catch { }; $ev += [ordered]@{ id = [string]$rid; node = $nd.Name; state = 'running'; ts = (Get-Date).ToUniversalTime().ToString('o'); ms = 0; topic = $tp } } } }
        } catch { }
    }
}
$evLog = Join-Path (Join-Path $Share 'status') 'events.log'
if (Test-Path $evLog) {
    try {
        foreach ($ln in @(Get-Content $evLog -Tail 150 -ErrorAction SilentlyContinue)) {
            $p = $ln.Split('|')
            if ($p.Count -ge 5) { $tp2 = ''; if ($topicLookups -lt 30) { $cbase = Join-Path (Join-Path $Share 'claimed') $p[1]; foreach ($cf2 in @((Join-Path $cbase ('task-' + $p[2] + '.json')), (Join-Path (Join-Path $cbase 'done') ('task-' + $p[2] + '.json')))) { try { if (Test-Path $cf2) { $tj2 = Get-Content $cf2 -Raw -ErrorAction Stop | ConvertFrom-Json; if ($tj2.payload.topic) { $tp2 = [string]$tj2.payload.topic; $topicLookups++; break } elseif ($tj2.topic) { $tp2 = [string]$tj2.topic; $topicLookups++; break } } } catch { } } }; $ev += [ordered]@{ id = $p[2]; node = $p[1]; state = 'done'; ts = $p[0]; ms = [int]$p[4]; topic = $tp2 } }
        }
    } catch { }
}
$ev = @($ev | Sort-Object { $_.ts } -Descending | Select-Object -First 150)
$pending = $qFiles.Count + (@($nodes.Keys | ForEach-Object { [int]$nodes[$_].active }) | Measure-Object -Sum).Sum
[ordered]@{ ts = $nowUtc.ToString('o'); queue = $qFiles.Count; queueOldestSec = $oldest; claimed = $claimed; locks = $locks; working = $working; total = $nodes.Count; nodes = $sorted; reaper = $reaper; monitor = $monitor; created = (Get-Created); tput = (Get-Tput); supply = (Get-Supply); scope = (Get-Scope); discovery = (Get-Discovery); watchRepos = (Get-WatchRepos); createdNew = ((Get-Created) - $script:baseCreated); startedAt = $script:startedAt; doneTotal = (Done-Total); specs = (Get-Specs); doneWin = (Win-Counts); uptimeSec = ([int]((Get-Date) - [datetime]::Parse($script:startedAt)).TotalSeconds); pending = $pending; events = $ev }
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
<!doctype html><html><head><meta charset="utf-8"><title>FleetWatch</title>
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
tr.sel td{background:#132a3a!important}tr.work td{background:#12201a}tr.work td:first-child{box-shadow:inset 3px 0 0 #4ade80}


.now{font-size:12px;color:#bbb;max-width:190px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.track{display:inline-block;width:70px;height:6px;background:#242424;border-radius:3px;vertical-align:middle}
.bar{display:inline-block;height:6px;border-radius:3px;background:#4ade80;vertical-align:middle}
body{padding-right:300px}
#log{position:fixed;right:0;top:0;bottom:0;width:280px;overflow-y:auto;border-left:1px solid #242424;padding:14px 10px;font-size:11px;background:#111;transition:width .15s}
#log.wide{width:620px}
#log.min{width:54px;padding:8px 4px;cursor:pointer} #log.min #loglist{display:none} #log.min h2 span{display:flex} #log.min #xmin{display:none} body.min{padding-right:62px}
body.wide{padding-right:640px}
#log h2{font-size:11px;color:#888;text-transform:uppercase;letter-spacing:.05em;margin:0 0 8px;display:flex;justify-content:space-between;align-items:center}
#xlog{background:#1b1b1b;color:#e6e6e6;border:1px solid #333;border-radius:5px;font:inherit;font-size:10px;padding:2px 7px;cursor:pointer}
.ev{display:flex;gap:7px;align-items:center;padding:3px 0;border-bottom:1px solid #1b1b1b;white-space:nowrap;overflow:hidden}
.ev .id{flex:1;overflow:hidden;text-overflow:ellipsis;color:#bbb}
.ev .nd{color:#666;font-size:10px}
.ring{width:14px;height:14px;flex:0 0 14px}
.dot{width:8px;height:8px;border-radius:50%;background:#4ade80;flex:0 0 8px}
.ficon[data-form=laptop]{border-color:#2f6d94;background:#0b1620}
.ficon[data-form=laptop] .fform{color:#5eb8e0;font-weight:600}
.ficon[data-form=desktop]{border-color:#8a6320;background:#1a1408}
.ficon[data-form=desktop] .fform{color:#e8b45e;font-weight:600}
.ficon:hover{opacity:1!important}
.ficon{position:relative}.pw{position:absolute;top:-7px;right:-7px;font-size:11px;color:#888;background:#141414;border:1px solid #333;border-radius:50%;width:17px;height:17px;line-height:15px;text-align:center;cursor:pointer;opacity:0}.ficon:hover .pw{opacity:1}.pw:hover{color:#f87171;border-color:#8a2020}.offdot{position:absolute;top:-4px;left:-4px;width:7px;height:7px;border-radius:50%}body.nolog #log{display:none} body.nolog{padding-right:12px} #acttoggle.on{background:#12301f;border-color:#2c5d3a}#viewctl{margin:0 0 8px}#viewctl button{background:#1b1b1b;color:#e6e6e6;border:1px solid #333;border-radius:6px;font:inherit;font-size:11px;padding:4px 10px;cursor:pointer}#acttoggle{background:#1b1b1b;color:#e6e6e6;border:1px solid #333;border-radius:6px;font:inherit;font-size:11px;padding:4px 10px;cursor:pointer;white-space:nowrap}#acttoggle.on{background:#12301f;border-color:#2c5d3a}</style></head><body>
<aside id="log"><h2>activity</h2><div id="loglist"></div></aside>
<div style="display:flex;align-items:center;justify-content:space-between;gap:14px"><h1 style="margin:0">FleetWatch</h1><button id="acttoggle" title="show or hide the activity panel">activity: on</button></div><div id="scopebar" style="margin:6px 0 10px">
  <div id="scope" style="font-size:11px;color:#b9b9b9;line-height:1.5;margin-bottom:6px"></div>
  <div style="display:flex;gap:6px;align-items:center">
    <input id="cmsg" placeholder="message to the agent..." style="flex:1;max-width:640px;background:#141414;color:#e6e6e6;border:1px solid #333;border-radius:6px;padding:5px 8px;font:inherit;font-size:11px">
    <button id="csend" style="background:#1b1b1b;color:#e6e6e6;border:1px solid #333;border-radius:6px;font:inherit;font-size:11px;padding:5px 12px;cursor:pointer">send</button>
    <span id="clog" style="font-size:10px;opacity:.6"></span>
  </div>
</div>
<div id="endgame"></div><div id="fleet-icons" style="display:flex;gap:14px;align-items:center;margin:6px 0 2px"></div><div id="specbox" style="font-size:11px;color:#bbb;margin:0 0 10px;min-height:0"></div><div class="sub" id="sub">loading</div>
<p id="ctl"><button data-cmd="refill">refill</button> <button data-cmd="pause">pause</button> <button data-cmd="resume">resume</button> <button data-cmd="drain">drain</button> <button data-cmd="alarm" style="border-color:#8a2020">alarm</button> <span class="dim" id="ctlmsg"></span></p>
<p><button id="restart" data-token="__RESTART_TOKEN__" style="background:#1b1b1b;color:#e6e6e6;border:1px solid #333;border-radius:6px;padding:6px 12px;font:inherit;cursor:pointer">restart dashboard</button> <span class="dim" id="rsmsg"></span></p>
<div class="kpi">
<div><span>working</span><b id="w">-</b></div>
<div><span>new since restart</span><b id="crnew">-</b></div><div><span>completed 1h</span><b id="cw">-</b></div><div><span>pending</span><b id="pend">-</b></div><div><span>queue</span><b id="q">-</b></div>
<div><span>oldest queued</span><b id="qo">-</b></div>
<div><span>claimed</span><b id="c">-</b></div>
<div><span>claim markers</span><b id="l">-</b></div>
<div><span>tasks created</span><b id="cr">__CREATED__</b></div>
</div>
<p id="winbar"><button id="w1h">1h</button> <button id="w6h">6h</button> <button id="wd1">24h</button> <button id="ww1">7d</button> <button id="wAll">all</button></p>
<table><thead><tr><th>station</th><th>state</th><th>hb</th><th >active</th><th>running now</th><th>done 15m</th><th>util 15m</th><th>activity, last 30 min</th><th>median</th><th>fail</th></tr></thead>
<tbody id="rows"></tbody></table>

<div style="display:flex;gap:28px;align-items:flex-start;flex-wrap:wrap;margin-top:18px">
  <div style="flex:1 1 420px;min-width:320px">
    <h2 style="font-size:11px;color:#888;text-transform:uppercase;letter-spacing:.05em;margin:0 0 6px">task topics</h2>
    <div id="topics" style="font-size:11px;color:#bbb"></div>
  </div>
  
</div>
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
   html+='<tr class="'+work+(selNode===n?' sel':'')+'" onclick="pickNode(\''+esc(n)+'\')" style="cursor:pointer"><td>'+esc(n)+'</td><td class="'+scls+'">'+v.state+'</td>'
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
</script><script>document.getElementById("restart").onclick=async()=>{const b=document.getElementById("restart"),m=document.getElementById("rsmsg");const t=b.getAttribute("data-token");m.textContent="restarting...";const r=await fetch("/restart",{method:"POST",headers:{"X-Restart-Token":t}});if(r.status===202){m.textContent="restart accepted - reloading in 5s";setTimeout(()=>location.reload(),5000);}else{m.textContent="refused ("+r.status+")";}};</script>
<script id="createdPoll">setInterval(async()=>{try{const r=await fetch("/health",{cache:"no-store"});const d=await r.json();const e=document.getElementById("cr");if(e&&d.created!==undefined)e.textContent=d.created;}catch(x){}},2000);</script>
<script>
const R=6.5,C=2*Math.PI*R;
function ring(p){return '<svg class="ring" viewBox="0 0 16 16"><circle cx="8" cy="8" r="'+R+'" fill="none" stroke="#2a2a2a" stroke-width="2"></circle><circle cx="8" cy="8" r="'+R+'" fill="none" stroke="#4ade80" stroke-width="2" stroke-linecap="round" transform="rotate(-90 8 8)" stroke-dasharray="'+C+'" stroke-dashoffset="'+(C*(1-p))+'" /></svg>';}
let selNode=null;function pickNode(n){selNode=(selNode===n)?null:n;}
function renderLog(ev){ev=(selNode?ev.filter(function(e){return e.node===selNode;}):ev);const box=document.getElementById('loglist');if(!box)return;const now=Date.now();box.innerHTML=ev.map(function(e){const age=(now-Date.parse(e.ts))/1000;if(e.state==='running'){return '<div class="ev">'+ring(Math.min(0.95,Math.max(0.05,age/6)))+'<span class="id">'+e.id+'</span><span class="nd">'+e.node+'</span></div>';}return '<div class="ev"><span class="dot"></span><span class="id">'+e.id+'</span><span class="nd">'+e.node+(e.ms?' '+e.ms+'ms':'')+'</span></div>';}).join('');}
const logEl=document.getElementById('log');
const at=document.getElementById('acttoggle');if(at){if(document.body.classList.contains('nolog')){at.textContent='activity: off';}else{at.classList.add('on');}at.onclick=function(){var off=document.body.classList.toggle('nolog');at.textContent='activity: '+(off?'off':'on');at.classList.toggle('on',!off);};}

logEl.addEventListener('click',function(){if(logEl.classList.contains('min')){logEl.classList.remove('min');document.body.classList.remove('min');}});
function renderDiscovery(j){
  var el=document.getElementById('scope'); if(!el) return;
  var d=j.discovery; if(!d) return;
  var pend=Number(d.discovered||0), rep=Number(d.reported||0);
  var ago=null;
  if(d.lastPoll){ try{ ago=Math.max(0, Math.round((Date.now()-Date.parse(d.lastPoll))/1000)); }catch(e){} }
  var active=(ago!==null && ago<900);
  var wcol=active?'#4ade80':'#f87171';
  var wtxt=(ago===null?'watcher: never polled':('watcher: '+(active?'active':'stale')+' &middot; polled '+(ago<120?ago+'s':Math.round(ago/60)+'m')+' ago'));
  var line='<div style="margin-top:3px;font-size:10px"><span style="color:'+wcol+'">'+wtxt+'</span>'
    +' &middot; pending topics <b style="color:'+(pend>0?'#e8b45e':'#777')+'">'+pend+'</b>'
    +' &middot; reported this window '+rep
    +(d.open?' <span style="color:#e8b45e">(update window open since '+String(d.since||'').slice(11,19)+' UTC)</span>':'')
    +' &middot; monitoring <span style="color:#9ab">'+(Array.isArray(j.watchRepos)?j.watchRepos.join(', '):'none')+'</span>'
    +'</div>';
  el.innerHTML = el.innerHTML.split('<div style="margin-top:3px;font-size:10px">')[0] + line;
}
function renderScope(j){
  var el=document.getElementById('scope'); if(!el) return;
  var t=(j&&j.scope)?String(j.scope):'';
  if(!t){ el.innerHTML=''; return; }
  var parts=String(t).split(/\r?\n/).filter(function(x){return x.trim().length;});
  var head='<span style="color:#888;text-transform:uppercase;letter-spacing:.05em;font-size:10px">scope</span> &middot; '+esc(parts[0]||'');
  var rest=parts.slice(1).map(function(x){return '<div style="margin-top:4px;opacity:.72;font-style:italic">'+esc(x)+'</div>';}).join('');
  el.innerHTML=head+rest;
}
function renderEndgame(j){
  var el=document.getElementById('endgame'); if(!el) return;
  var sp=j.supply||{}; var rem=(sp.remaining===undefined?null:Number(sp.remaining));
  if(rem===null){ el.innerHTML=''; return; }
  if(rem<=0){
    el.innerHTML='<div style="border:1px solid #8a6320;background:#1a1408;color:#e8b45e;border-radius:6px;padding:5px 10px;font-size:11px;margin:2px 0 6px">ENDGAME - no further tasks can be created from scope (corpus '+sp.corpus+', all seen). Remaining queue and running work is the last of it.</div>';
  } else {
    el.innerHTML='<div style="color:#777;font-size:10px;margin:2px 0 6px">work still to be created: '+rem+' of '+sp.corpus+'</div>';
  }
}
function renderIcons(sp,jSt){var box=document.getElementById('fleet-icons');if(!box)return;var keys=Object.keys(sp);if(!keys.length){box.innerHTML='';return;}box.innerHTML=keys.map(function(k){var v=sp[k];var ic=(v.form==='laptop')?'\uD83D\uDCBB':'\uD83D\uDDA5';var cls=(selNode===k)?'style="opacity:1;border-color:#4ade80"':'style="opacity:.65;border-color:#333"';var st=(jSt[k]||{});var age=(st.heartbeatAge===undefined?-1:Number(st.heartbeatAge));var dot=(age<0?'#555':(age>180?'#f87171':(age>60?'#e8b45e':'#4ade80')));var off=(st.state==='offline'||age>180);return '<span class="ficon" data-n="'+k+'" data-form="'+v.form+'" '+cls+' title="'+k+' ('+v.form+') heartbeat '+age+'s">'+(off?'<span class="offdot" style="background:'+dot+'"></span>':'')+ic+'<span class="fname">'+k+'<br><span class="fform">'+v.form+'</span></span><span class="pw" data-node="'+k+'" title="reboot '+k+' after drain">&#9211;</span></span>';}).join('');Array.prototype.forEach.call(box.querySelectorAll('.pw'),function(sw){sw.onclick=function(ev){ev.stopPropagation();var n=sw.getAttribute('data-node');if(!confirm('Reboot '+n+'?\n\nIt stops claiming new tasks, finishes what is running, then restarts.'))return;if(n==='mdmfury'){var typed=prompt('The coordinator hosts the share for the whole fleet.\n\nType REBOOT to restart it:');if(!typed||typed.trim().toUpperCase()!=='REBOOT'){var b0=document.getElementById('specbox');if(b0){b0.textContent='coordinator reboot cancelled';}return;}}var tok=document.getElementById('restart');fetch('/control?cmd=reboot&node='+encodeURIComponent(n),{method:'POST',headers:{'X-Restart-Token':tok?tok.getAttribute('data-token'):''}}).then(function(r){return r.json();}).then(function(){var b=document.getElementById('specbox');if(b){b.textContent='reboot queued for '+n+' (drains, then restarts)';}}).catch(function(){});};});Array.prototype.forEach.call(box.querySelectorAll('.ficon'),function(el){el.onclick=function(){var n=el.getAttribute('data-n');var v=sp[n];var b=document.getElementById('specbox');if(!b)return;if(b.getAttribute('data-n')===n){b.innerHTML='';b.removeAttribute('data-n');return;}b.setAttribute('data-n',n);b.innerHTML='<b>'+n+'</b> &middot; '+v.role+' &middot; '+v.model+' &middot; '+v.cpu+' ('+v.cores+'c/'+v.threads+'t) &middot; '+v.ramGB+' GB RAM &middot; '+v.gpu+' &middot; '+v.slots+' slots &middot; '+v.freeGB+' GB free &middot; '+v.host;};});}
function renderTopics(ev){const box=document.getElementById('topics');if(!box)return;if(selNode)ev=ev.filter(function(e){return e.node===selNode;});const run=ev.filter(e=>e.state==='running'&&e.topic);const done=ev.filter(e=>e.state==='done');const parts=[];run.slice(0,10).forEach(e=>parts.push('<div>▶ <span style="color:#4ade80">'+esc(e.topic)+'</span> <span style="color:#666">'+esc(e.node)+'</span></div>'));done.slice(0,8).forEach(e=>parts.push('<div style="color:#555">✓ '+(e.topic?('<span style="color:#777">'+esc(e.topic)+'</span>'):esc(e.id))+'</div>'));box.innerHTML=parts.join('')||'<span style="color:#555">no topics yet</span>';}let winKey='h1';let lastD=null;const winMap={w1h:'h1',w6h:'h6',wd1:'d1',ww1:'w1',wAll:'all'};function updateCw(){const el=document.getElementById('cw');if(el&&lastD&&lastD.doneWin)el.textContent=lastD.doneWin[winKey];}Object.keys(winMap).forEach(function(id){const b=document.getElementById(id);if(b){b.onclick=function(){winKey=winMap[id];updateCw();};b.style.cssText='background:#1b1b1b;color:#e6e6e6;border:1px solid #333;border-radius:5px;font:inherit;font-size:10px;padding:3px 8px;cursor:pointer';}});setInterval(async function(){try{const r=await fetch('/health',{cache:'no-store'});const d=await r.json();renderLog(d.events||[]);renderTopics(d.events||[]);renderIcons(d.specs||{},d.nodes||{});renderScope(d);renderDiscovery(d);renderEndgame(d);(function(){var el=document.getElementById('cw');if(el&&d.doneWin&&d.doneWin[winKey]!==undefined)el.textContent=d.doneWin[winKey];})();const cn=document.getElementById('crnew');if(cn&&d.createdNew!==undefined)cn.textContent=d.createdNew;const tot=document.getElementById('kpitot');const cur=document.querySelector('.kpi');
function fillTotals(d){lastD=d;if(d&&d.doneWin)updateCw();var a=document.getElementById('t1');if(a)a.textContent=d.created;var b=document.getElementById('t2');if(b)b.textContent=d.doneTotal;var c=document.getElementById('t3');if(c)c.textContent=d.createdNew;var e2=document.getElementById('t4');if(e2)e2.textContent=(d.uptimeSec||0)+'s';}
const pd=document.getElementById('pend');if(pd&&d.pending!==undefined)pd.textContent=d.pending;const cq=document.getElementById('q');if(cq&&d.queue!==undefined)cq.textContent=d.queue;}catch(x){}},400);
</script>
<script>
(function(){var tok=document.getElementById('restart');var t=tok?tok.getAttribute('data-token'):'';
Array.prototype.forEach.call(document.querySelectorAll('#ctl button[data-cmd]'),function(b){b.style.cssText='background:#1b1b1b;color:#e6e6e6;border:1px solid #333;border-radius:6px;font:inherit;font-size:11px;padding:4px 10px;cursor:pointer';
b.onclick=async function(){var m=document.getElementById('ctlmsg');m.textContent=b.dataset.cmd+'...';
try{var r=await fetch('/control?cmd='+b.dataset.cmd,{method:'POST',headers:{'X-Restart-Token':t},cache:'no-store'});var j=await r.json();
m.textContent=r.status===200?('ok: '+j.cmd+' (pause='+j.pause+' drain='+j.drain+')'):('refused '+r.status);}catch(e){m.textContent='failed';}};
});})();
</script>
<script>
(function(){var tok=document.getElementById('restart');var t=tok?tok.getAttribute('data-token'):'';
var b=document.getElementById('csend');
b.onclick=async function(){var i=document.getElementById('cmsg');var v=(i.value||'').trim();if(!v)return;
try{var r=await fetch('/control?cmd=say&text='+encodeURIComponent(v),{method:'POST',headers:{'X-Restart-Token':t}});
var j=await r.json();i.value='';document.getElementById('clog').innerHTML=(j.recent||[]).map(function(x){return '<div>'+x+'</div>';}).join('');}catch(e){}};
})();
</script>
<script>
/* csendHandler */
(function(){
  function token(){var r=document.getElementById('restart');return r?r.getAttribute('data-token'):'';}
  function show(lines){var c=document.getElementById('clog');if(!c)return;c.innerHTML=(lines||[]).map(function(x){return '<div>'+String(x).replace(/[&<>]/g,function(k){return {'&':'&amp;','<':'&lt;','>':'&gt;'}[k];})+'</div>';}).join('');}
  function send(){
    var i=document.getElementById('cmsg'); if(!i) return;
    var v=(i.value||'').trim(); if(!v) return;
    i.value=''; show(['sending...']);
    fetch('/control?cmd=say&text='+encodeURIComponent(v),{method:'POST',headers:{'X-Restart-Token':token()},cache:'no-store'})
      .then(function(r){return r.json();})
      .then(function(j){ if(j&&j.ok){ show(j.recent||['sent']); } else { show(['refused: '+(j&&j.error?j.error:'no token')]); } })
      .catch(function(e){ show(['failed: '+e]); });
  }
  var b=document.getElementById('csend'); if(b){ b.onclick=send; }
  var i=document.getElementById('cmsg'); if(i){ i.addEventListener('keydown',function(e){ if(e.key==='Enter') send(); }); }
})();
</script>
</body></html>
'@

$prefix = 'http://' + $BindAddress + ':' + $Port + '/'
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
try { $listener.Start() } catch { Dlog ('bind failed: ' + $_.Exception.Message); throw }
Dlog ('listening on ' + $prefix)
while ($listener.IsListening) {
    try {
        $ctx = $listener.GetContext()
        $reqPath = $ctx.Request.Url.AbsolutePath
if ($reqPath -eq '/control') {
    $tokFile = 'C:\Users\Maarten\fleet\restart.token'
    $supplied = $ctx.Request.Headers['X-Restart-Token']
    if (-not $supplied) { $supplied = $ctx.Request.QueryString['token'] }
    $authorised = $false
    if ((Test-Path $tokFile) -and $supplied) { $authorised = ($supplied -eq ((Get-Content $tokFile -Raw).Trim())) }
    if (-not $authorised) {
        $ctx.Response.StatusCode = 403
        $body = '{"error":"control requires a valid token"}'
    } else {
        $cmd = [string]$ctx.Request.QueryString['cmd']
        $sayLines = @()
        $ctl = 'D:\fleet\control'
        New-Item -ItemType Directory -Force -Path $ctl | Out-Null
        $stateFile = Join-Path $ctl 'state.json'
        $state = @{ pause = $false; drain = $false }
        if (Test-Path $stateFile) { try { $j = Get-Content $stateFile -Raw | ConvertFrom-Json; $state.pause = [bool]$j.pause; $state.drain = [bool]$j.drain } catch { } }
        switch ($cmd) {
            'pause'  { $state.pause = $true }
            'resume' { $state.pause = $false; $state.drain = $false }
            'drain'  { $state.drain = $true }
            'reboot' {
                $node = [string]$ctx.Request.QueryString['node']
                $known = @('mdmfury','mdma','gr2c3p8')
                if ($known -contains $node) {
                    New-Item -ItemType Directory -Force -Path (Join-Path $ctl 'reboot') | Out-Null
                    ([ordered]@{ node = $node; requested = (Get-Date).ToUniversalTime().ToString('o'); by = 'FleetWatch'; confirm = 'drain-then-reboot' } | ConvertTo-Json -Compress) | Set-Content -LiteralPath (Join-Path $ctl ('reboot/' + $node + '.json')) -Encoding utf8
                    Dlog ('reboot requested for ' + $node + ' after drain')
                    $sayLines = @('queued: reboot ' + $node + ' after its running tasks finish')
                } else { $sayLines = @('unknown node') }
            }
            'say'    {
                $txt = [string]$ctx.Request.QueryString['text']
                if ($txt) {
                    $chatDir = 'D:\fleet\chat'
                    New-Item -ItemType Directory -Force -Path $chatDir | Out-Null
                    (((Get-Date).ToUniversalTime().ToString('o')) + '|' + $txt) | Add-Content -LiteralPath (Join-Path $chatDir 'inbox.log') -Encoding utf8
                    Dlog ('console > ' + $txt)
                    try { $sayLines = @(Get-Content (Join-Path $chatDir 'inbox.log') -Tail 6 | ForEach-Object { [string]$_ }) } catch { }
                }
            }
            'alarm'  { ((Get-Date).ToUniversalTime().ToString('o')) | Set-Content -LiteralPath (Join-Path $ctl 'alarm.txt') -Encoding utf8; Dlog ('ALARM raised from ' + $ctx.Request.RemoteEndPoint.Address) }
            'refill' {
                $seeF = 'D:\fleet\backlog\corpus-seen.txt'
                $corF = 'D:\fleet\backlog\corpus.json'
                $tN = 0; if (Test-Path $corF) { try { $tN = @(Get-Content $corF -Raw | ConvertFrom-Json | ForEach-Object { $_ }).Count } catch { } }
                $sN = 0; if (Test-Path $seeF) { $sN = @(Get-Content $seeF | Where-Object { $_.Trim() }).Count }
                if ($tN -gt 0 -and $sN -ge $tN) {
                    Remove-Item $seeF -Force -ErrorAction SilentlyContinue
                    Dlog 'control: refill found supply exhausted - started a new verification cycle'
                }
                Start-Process powershell -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File','C:\Users\Maarten\fleet\FleetCorpusFinder.ps1' -WindowStyle Hidden
            }
        }
        $state | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding utf8
        Dlog ('control: ' + $cmd + ' pause=' + $state.pause + ' drain=' + $state.drain)
        $ctx.Response.StatusCode = 200
        if ($cmd -eq 'say') {
            $body = ('{"ok":true,"cmd":"say","recent":' + (ConvertTo-Json -Compress @($sayLines)) + '}')
        } else {
            $body = ('{"ok":true,"cmd":"' + $cmd + '","pause":' + $state.pause.ToString().ToLower() + ',"drain":' + $state.drain.ToString().ToLower() + '}')
        }
    }
} elseif ($reqPath -eq '/restart') {
    $tokFile = 'C:\Users\Maarten\fleet\restart.token'
    $supplied = $ctx.Request.Headers['X-Restart-Token']
    $authorised = $false
    if ((Test-Path $tokFile) -and $supplied) {
        $authorised = ($supplied -eq ((Get-Content $tokFile -Raw).Trim()))
    }
    if (-not $authorised) {
        Dlog ('restart DENIED from ' + $ctx.Request.RemoteEndPoint.Address)
        $ctx.Response.StatusCode = 403
        $body = '{"error":"restart requires a valid X-Restart-Token"}'
    } else {
        Dlog ('restart requested by ' + $ctx.Request.RemoteEndPoint.Address)
        schtasks /run /tn FleetDashboardRestart 2>&1 | Out-Null
        $ctx.Response.StatusCode = 202
        $body = '{"status":"restarting","task":"FleetDashboard"}'
    }
} else {
    $body = if ($reqPath -eq '/health') { Health } else { $page.Replace('__RESTART_TOKEN__', ((Get-Content 'C:\Users\Maarten\fleet\restart.token' -Raw).Trim())).Replace('__CREATED__', [string](Get-Created)) }
}
        $bytes = [Text.Encoding]::UTF8.GetBytes($body)
        $ctx.Response.ContentType = if ($ctx.Request.Url.AbsolutePath -eq '/health') { 'application/json' } else { 'text/html; charset=utf-8' }
        $ctx.Response.Headers.Add('Cache-Control','no-store')
        $ctx.Response.ContentLength64 = $bytes.Length
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $ctx.Response.Close()
    } catch { Start-Sleep -Milliseconds 150 }
}
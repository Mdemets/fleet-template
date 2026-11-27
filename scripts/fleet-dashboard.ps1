<#
  fleet-dashboard.ps1 - browser dashboard for the fleet, served by the coordinator.

  Shows every worker known to the fleet - live heartbeats, claimed directories and an optional
  fleet-roster.json - ordered so the stations DOING WORK come first, then idle, then down.
  /health is computed per request, so the page reflects now rather than the 5-minute monitor file.
#>
[CmdletBinding()]
param([int] $Port = 8080, [string] $Share = '', [string] $BindAddress = '')
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

function Snapshot {
    $q = @(Get-ChildItem (Join-Path $Share 'queue') -File -Filter '*.json' -ErrorAction SilentlyContinue).Count
    $c = @(Get-ChildItem (Join-Path $Share 'claimed') -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object { $_.Directory.Name -ne 'done' }).Count
    $l = @(Get-ChildItem (Join-Path $Share 'locks') -File -ErrorAction SilentlyContinue).Count
    $roster = @()
    $rosterFile = Join-Path $Share 'fleet-roster.json'
    if (Test-Path $rosterFile) { try { $roster = @((Get-Content $rosterFile -Raw | ConvertFrom-Json).nodes) } catch { } }
    $known = @()
    $known += @(Get-ChildItem (Join-Path $Share 'results') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $known += @(Get-ChildItem (Join-Path $Share 'claimed') -Directory -ErrorAction SilentlyContinue | ForEach-Object { $_.Name } | Where-Object { $_ -ne 'done' })
    $known += $roster
    $known = @($known | Where-Object { $_ } | Sort-Object -Unique)
    $nodes = @{}
    foreach ($name in $known) {
        $hb = Join-Path (Join-Path $Share 'results') ($name + '\heartbeat.json')
        if (-not (Test-Path $hb)) {
            $nodes[$name] = [ordered]@{ state = 'DOWN'; heartbeatAge = -1; active = 0; finished15m = 0; medianMs = 0; failures = 0 }
            continue
        }
        $age = [int]((Get-Date).ToUniversalTime() - (Get-Item $hb).LastWriteTime.ToUniversalTime()).TotalSeconds
        $active = 0
        try { $active = [int]((Get-Content $hb -Raw | ConvertFrom-Json).active) } catch { }
        $res = @(Get-ChildItem (Split-Path $hb -Parent) -File -Filter 'result-*.json' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -gt (Get-Date).AddMinutes(-15) })
        $fails = 0; $durs = @()
        foreach ($rf in $res) {
            try {
                $j = Get-Content $rf.FullName -Raw | ConvertFrom-Json
                if ($j.exitCode -ne 0) { $fails++ }
                if ($j.claimedAt -and $j.finishedAt) {
                    $d = ([datetime]::Parse($j.finishedAt).ToUniversalTime() - [datetime]::Parse($j.claimedAt).ToUniversalTime()).TotalMilliseconds
                    if ($d -ge 0) { $durs += [int]$d }
                }
            } catch { }
        }
        $med = 0
        if ($durs.Count) { $med = ($durs | Sort-Object)[[int]($durs.Count / 2)] }
        $state = if ($age -gt 120) { 'STALE' } else { 'ok' }
        $nodes[$name] = [ordered]@{ state = $state; heartbeatAge = $age; active = $active; finished15m = $res.Count; medianMs = $med; failures = $fails }
    }
    $order = $nodes.Keys | Sort-Object @{ Expression = { if ($nodes[$_].state -eq 'DOWN') { 2 } elseif ($nodes[$_].active -gt 0) { 0 } else { 1 } } }, @{ Expression = { $nodes[$_].active }; Descending = $true }
    $sorted = [ordered]@{}
    foreach ($k in $order) { $sorted[$k] = $nodes[$k] }
    $working = @($nodes.Keys | Where-Object { $nodes[$_].active -gt 0 }).Count
    $reaper = 'n/a'
    $rl = Join-Path $Share 'reaper.log'
    if (Test-Path $rl) { $reaper = (Get-Content $rl -Tail 1) }
    $monitor = 'n/a'
    $h = Join-Path $statusDir 'health.json'
    if (Test-Path $h) { try { $m = Get-Content $h -Raw | ConvertFrom-Json; $monitor = 'healthy=' + $m.healthy + ' anomalies=' + @($m.anomalies).Count } catch { } }
    [ordered]@{ ts = (Get-Date).ToUniversalTime().ToString('o'); queue = $q; claimed = $c; locks = $l; working = $working; total = $nodes.Count; nodes = $sorted; reaper = $reaper; monitor = $monitor }
}

$page = @'
<!doctype html><html><head><meta charset="utf-8"><title>Fleet</title>
<style>
:root{color-scheme:dark}body{font:14px/1.5 ui-monospace,Menlo,Consolas,monospace;background:#111;color:#e6e6e6;margin:0;padding:24px}
h1{font-size:16px;font-weight:600;margin:0 0 4px}.sub{color:#888;margin-bottom:18px}
table{border-collapse:collapse;width:100%;max-width:980px}
th,td{text-align:left;padding:8px 12px;border-bottom:1px solid #262626}
th{color:#888;font-weight:500;font-size:12px;text-transform:uppercase;letter-spacing:.05em}
.ok{color:#4ade80}.warn{color:#fbbf24}.bad{color:#f87171}.dim{color:#666}
.kpi{display:flex;gap:24px;margin:0 0 20px;flex-wrap:wrap}
.kpi div{border:1px solid #262626;border-radius:8px;padding:10px 16px;min-width:86px}
.kpi b{display:block;font-size:20px;font-weight:600}
.kpi span{color:#888;font-size:11px;text-transform:uppercase;letter-spacing:.05em}
tr.work td{background:#132018}tr.work td:first-child{box-shadow:inset 3px 0 0 #4ade80}
</style></head><body>
<h1>Fleet</h1><div class="sub" id="sub">loading</div>
<div class="kpi">
<div><span>working</span><b id="w">-</b></div>
<div><span>queue</span><b id="q">-</b></div>
<div><span>claimed</span><b id="c">-</b></div>
<div><span>claim markers</span><b id="l">-</b></div>
</div>
<table><thead><tr><th>station</th><th>state</th><th>heartbeat</th><th>active</th><th>done 15m</th><th>median</th><th>failures</th></tr></thead>
<tbody id="rows"></tbody></table>
<p class="dim" id="foot"></p>
<script>
async function tick(){
 try{
  const r=await fetch('/health',{cache:'no-store'});const d=await r.json();
  document.getElementById('w').textContent=d.working+'/'+d.total;
  document.getElementById('q').textContent=d.queue;
  document.getElementById('c').textContent=d.claimed;
  document.getElementById('l').textContent=d.locks;
  const s=document.getElementById('sub');
  s.textContent='updated '+new Date(d.ts).toLocaleTimeString();
  s.className='sub';
  let html='';
  for(const n of Object.keys(d.nodes)){
   const v=d.nodes[n];
   const work=(v.active>0)?'work':'';
   const scls=v.state==='ok'?'ok':(v.state==='STALE'?'warn':'bad');
   const hb=v.heartbeatAge<0?'-':v.heartbeatAge+'s';
   const hcls=v.heartbeatAge<0?'bad':(v.heartbeatAge>30?'warn':'ok');
   html+='<tr class="'+work+'"><td>'+n+'</td><td class="'+scls+'">'+v.state+'</td>'
        +'<td class="'+hcls+'">'+hb+'</td><td>'+v.active+'</td><td>'+v.finished15m+'</td>'
        +'<td>'+v.medianMs+'ms</td><td class="'+(v.failures?'bad':'ok')+'">'+v.failures+'</td></tr>';
  }
  document.getElementById('rows').innerHTML=html||'<tr><td colspan=7 class=dim>no stations known</td></tr>';
  document.getElementById('foot').textContent=d.reaper+'   |   monitor: '+d.monitor;
 }catch(e){
  const s=document.getElementById('sub');s.textContent='coordinator unreachable: '+e;s.className='bad';
 }
}
tick();setInterval(tick,2000);
</script></body></html>
'@

$prefix = 'http://' + $BindAddress + ':' + $Port + '/'
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add($prefix)
try { $listener.Start() } catch { Dlog ('bind failed: ' + $_.Exception.Message); throw }
Dlog ('listening on ' + $prefix + ' share=' + $Share)
while ($listener.IsListening) {
    try {
        $ctx = $listener.GetContext()
        $path = $ctx.Request.Url.AbsolutePath
        $body = if ($path -eq '/health') { (Snapshot | ConvertTo-Json -Depth 5) } else { $page }
        $bytes = [Text.Encoding]::UTF8.GetBytes($body)
        $ctx.Response.ContentType = if ($path -eq '/health') { 'application/json' } else { 'text/html; charset=utf-8' }
        $ctx.Response.Headers.Add('Cache-Control','no-store')
        $ctx.Response.ContentLength64 = $bytes.Length
        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $ctx.Response.Close()
    } catch { Start-Sleep -Milliseconds 200 }
}
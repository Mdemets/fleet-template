$ErrorActionPreference='SilentlyContinue'
"host        : $env:COMPUTERNAME"
# --- where the lanes actually run: find repos, bounded ---
$roots = @("$env:USERPROFILE", 'C:\projects', 'D:\projects')
$gits = @()
foreach ($r in $roots) { if (Test-Path $r) { $gits += @(Get-ChildItem $r -Directory -Recurse -Depth 4 -Force -Filter '.git' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(target|node_modules|\.cargo|AppData)\\' } | ForEach-Object { $_.Parent.FullName }) } }
$gits = $gits | Sort-Object -Unique
if (-not $gits) { '  repos       : none found' }
foreach ($g in $gits) {
  $br    = (& git -C $g rev-parse --abbrev-ref HEAD 2>&1)
  $last  = (& git -C $g log -1 --format='%ad|%s' --date=format:'%m-%d %H:%M' 2>&1)
  $dirty = @(& git -C $g status --porcelain 2>&1).Count
  $un    = (& git -C $g rev-list --count HEAD --not --remotes 2>&1)
  "  repo        : {0}  [{1}]" -f (Split-Path $g -Leaf), $br
  "     commit   : {0}" -f $last
  "     tree     : dirty={0} unpushed={1}" -f $dirty, $un
  $nf = Get-ChildItem $g -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(target|node_modules|\.git)\\' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($nf) { "     activity : {0}  {1}" -f $nf.LastWriteTime, $nf.Name }
}
# --- is an agent working right now? ---
$agents = Get-Process | Where-Object { $_.ProcessName -match 'DeepAI|codex|claude|node|pwsh' -and $_.CPU -gt 60 } | Sort-Object CPU -Descending | Select-Object -First 4
if ($agents) { foreach ($a in $agents) { "  worker      : {0,-16} cpu={1}s mem={2}MB" -f $a.ProcessName, [math]::Round($a.CPU,0), [math]::Round($a.WS/1MB,0) } } else { '  worker      : no busy agent process' }
'STATION_END'
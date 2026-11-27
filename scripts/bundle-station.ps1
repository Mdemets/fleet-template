$ErrorActionPreference='SilentlyContinue'
$out = Join-Path "$env:USERPROFILE\bundles" $env:COMPUTERNAME
New-Item -ItemType Directory -Force -Path $out | Out-Null
$roots = @("$env:USERPROFILE", 'C:\projects', 'D:\projects')
$gits = @()
foreach ($r in $roots) { if (Test-Path $r) { $gits += @(Get-ChildItem $r -Directory -Recurse -Depth 4 -Force -Filter '.git' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(target|node_modules|\.cargo|AppData)\\' } | ForEach-Object { $_.Parent.FullName }) } }
$gits = $gits | Sort-Object -Unique
"host : $env:COMPUTERNAME"
"out  : $out"
$made = 0; $skipped = 0; $failed = 0
foreach ($g in $gits) {
  $name = Split-Path $g -Leaf
  $un = (& git -C $g rev-list --count HEAD --not --remotes 2>&1)
  if ($LASTEXITCODE -ne 0 -or -not ($un -match '^\d+$')) { "  skip  {0,-42} (no commits)" -f $name; $skipped++; continue }
  if ([int]$un -eq 0) { $skipped++; continue }
  $safe = ($name -replace '[^A-Za-z0-9._-]','_')
  $b = Join-Path $out ($safe + '.bundle')
  & git -C $g bundle create $b --all 2>&1 | Out-Null
  if ($LASTEXITCODE -eq 0 -and (Test-Path $b)) { "  ok    {0,-42} unpushed={1,-5} {2} MB" -f $name, $un, [math]::Round((Get-Item $b).Length/1MB,1); $made++ }
  else { "  FAIL  {0,-42} unpushed={1}" -f $name, $un; $failed++ }
}
"summary: made=$made skipped(clean/no-commits)=$skipped failed=$failed"
"total  : " + [math]::Round((Get-ChildItem $out -Filter '*.bundle' | Measure-Object Length -Sum).Sum/1MB,1) + ' MB in ' + @(Get-ChildItem $out -Filter '*.bundle').Count + ' bundles'
'BUNDLE_END'
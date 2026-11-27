<#
  audit-coordinator.ps1 - one-screen health report for the coordinating station.

    audit-coordinator.ps1 -Share (Join-Path $env:SystemDrive 'fleet')
    audit-coordinator.ps1 -Repos 'C:\work\one','C:\work\two'

  Project-neutral: it reports on the transport, the reaper and whatever repositories you
  name. It does not assume a share drive letter or a particular project layout.
#>
[CmdletBinding()]
param(
  [string] $Share = (Join-Path $env:SystemDrive 'fleet'),
  [string[]] $Repos = @(),
  [string] $BundleDir = ''
)
$ErrorActionPreference = 'SilentlyContinue'

$s = Get-Service sshd
"coordinator : $env:COMPUTERNAME  sshd=$($s.Status)/$($s.StartType)  uptime_h=" + [math]::Round([Environment]::TickCount64/3600000,1)
$q = @(Get-ChildItem (Join-Path $Share 'queue') -Recurse -File -Filter '*.json').Count
$c = @(Get-ChildItem (Join-Path $Share 'claimed') -Recurse -File -Filter '*.json').Count
$r = @(Get-ChildItem (Join-Path $Share 'results') -Recurse -File -Filter '*.json').Count
"queue       : queue=$q claimed=$c results=$r"
$rl = Get-Content (Join-Path $Share 'reaper.log') -Tail 1
"reaper log  : $rl"
& schtasks /query /tn FleetReaper /fo LIST 2>&1 | Select-String 'Status|Last Run Time' | ForEach-Object { 'reaper task : ' + ($_ -replace '\s+',' ').Trim() }

foreach ($g in @($Repos | ForEach-Object { [string]$_ -split ',' } | Where-Object { $_.Trim() })) {
    $br = (& git -C $g rev-parse --abbrev-ref HEAD 2>&1)
    $dirty = @(& git -C $g status --porcelain 2>&1).Count
    $unpushed = (& git -C $g rev-list --count HEAD --not --remotes 2>&1)
    "repo        : {0,-14} branch={1} dirty={2} unpushed={3}" -f (Split-Path $g -Leaf), $br, $dirty, $unpushed
}

if ($BundleDir) {
    $bl = Get-ChildItem $BundleDir -Filter '*.bundle' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    "bundle      : " + $(if ($bl) { $bl.Name + ' ' + [math]::Round($bl.Length/1MB,1) + 'MB ' + $bl.LastWriteTime } else { 'none' })
}
"credentials : " + $(if (Test-Path (Join-Path $Share 'worker-credentials.csv')) { 'PRESENT (delete after provisioning)' } else { 'absent' })
"admin keys  : " + @(Get-Content 'C:\ProgramData\ssh\administrators_authorized_keys' -ErrorAction SilentlyContinue).Count
'COORD_END'
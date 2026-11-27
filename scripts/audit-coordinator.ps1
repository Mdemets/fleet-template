$ErrorActionPreference='SilentlyContinue'
$s = Get-Service sshd
"coordinator : $env:COMPUTERNAME  sshd=$($s.Status)/$($s.StartType)  uptime_h=" + [math]::Round([Environment]::TickCount64/3600000,1)
$q = @(Get-ChildItem 'D:\fleet\queue' -Recurse -File -Filter '*.json').Count
$c = @(Get-ChildItem 'D:\fleet\claimed' -Recurse -File -Filter '*.json').Count
$r = @(Get-ChildItem 'D:\fleet\results' -Recurse -File -Filter '*.json').Count
"queue       : queue=$q claimed=$c results=$r"
$rl = Get-Content 'D:\fleet\reaper.log' -Tail 1
"reaper log  : $rl"
& schtasks /query /tn FleetReaper /fo LIST 2>&1 | Select-String 'Status|Last Run Time' | ForEach-Object { 'reaper task : ' + ($_ -replace '\s+',' ').Trim() }
foreach ($g in @('C:\\Users\\<user>\projects\victory','C:\\Users\\<user>\projects\Claude Workspace\fleet-template','C:\\Users\\<user>\projects\Claude Workspace\flamingo')) {
  $br = (& git -C $g rev-parse --abbrev-ref HEAD 2>&1)
  $d = @(& git -C $g status --porcelain 2>&1).Count
  $u = (& git -C $g rev-list --count HEAD --not --remotes 2>&1)
  "repo        : {0,-14} branch={1} dirty={2} unpushed={3}" -f (Split-Path $g -Leaf), $br, $d, $u
}
"bundle      : " + ((Get-ChildItem 'C:\\Users\\<user>\bundles' -Filter '*.bundle' | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object { $_.Name + ' ' + [math]::Round($_.Length/1MB,1) + 'MB ' + $_.LastWriteTime }) -join '')
"credentials : worker-credentials.csv " + $(if (Test-Path 'D:\fleet\worker-credentials.csv') { 'PRESENT (runbook 3: delete)' } else { 'absent' })
"admin keys  : " + @(Get-Content 'C:\ProgramData\ssh\administrators_authorized_keys').Count
'COORD_END'
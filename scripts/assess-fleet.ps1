<#
  assess-fleet.ps1 - measure a fleet and recommend roles and slot counts.

    assess-fleet.ps1 -Local -Hosts node-a,node-b

  Hardware-independent: nothing assumes three stations, a particular CPU, or a particular subnet and address range
  network. Feed it whatever the new fleet has; it measures and recommends.

  Roles (see docs/fleet-sizing.md):
    coordinator - stability first (static address), then storage for the share, then RAM;
    workers     - every other host, including the coordinator from its local path;
    auditor     - needs independence from what it audits: prefer a host that is NOT the
                  coordinator and NOT the busiest worker, with read-only share access;
    slots       - logical threads for interpreter-bound payloads, cores for compiled ones.
#>
[CmdletBinding()]
param([string[]] $Hosts = @(), [switch] $Local, [int] $SlotCap = 32, [string] $AuditorHost = '')
$ErrorActionPreference = 'Continue'
# a comma-joined string binds as one element; split so it is never treated as a single host
$Hosts = @($Hosts | ForEach-Object { [string]$_ -split ',' } | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })

$probe = @'
$c = Get-CimInstance Win32_Processor | Select-Object -First 1
$o = Get-CimInstance Win32_OperatingSystem
$d = Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Sort-Object FreeSpace -Descending | Select-Object -First 1
$addr = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.*' } | Select-Object -First 1
$ip = $addr.IPAddress
$static = $false
# static-ness must be read from the interface that OWNS the address, not the first adapter:
# a wired DHCP adapter next to a static Wi-Fi one otherwise reports the wrong answer.
$static = $false
try { if ($addr) { $static = ((Get-NetIPInterface -InterfaceIndex $addr.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).Dhcp -eq 'Disabled') } } catch { }
$measure = { param($n) $jobs = 1..$n | ForEach-Object { Start-Job { $sw=[Diagnostics.Stopwatch]::StartNew(); $k=0; while ($sw.ElapsedMilliseconds -lt 2000) { $k++ }; $k } }; $jobs | Wait-Job | Out-Null; $t = ($jobs | ForEach-Object { Receive-Job $_ } | Measure-Object -Sum).Sum; $jobs | Remove-Job -Force; $t }
$one = & $measure 1
$par = & $measure ([int]$c.NumberOfLogicalProcessors)
[pscustomobject]@{
  host = $env:COMPUTERNAME; cores = $c.NumberOfCores; logical = $c.NumberOfLogicalProcessors
  cpu = $c.Name.Trim(); ramGB = [math]::Round($o.TotalVisibleMemorySize/1MB,1); freeRamGB = [math]::Round($o.FreePhysicalMemory/1MB,1)
  shareDiskGB = [math]::Round($d.FreeSpace/1GB,1); ip = $ip; staticIp = $static
  scaling = [math]::Round($par / [math]::Max($one,1), 2)
} | ConvertTo-Json -Compress
'@

$result = @()
$tmp = Join-Path $env:TEMP 'assess-probe.ps1'
Set-Content -LiteralPath $tmp -Value $probe -Encoding ascii
if ($Local) {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $tmp 2>&1 | Out-String
    $line = ($out -split "`r?`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
    if ($line) { $result += ($line | ConvertFrom-Json) }
}
foreach ($h in $Hosts) {
    & scp -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 $tmp ("${h}:C:/ProgramData/fleet-assess-probe.ps1") 2>&1 | Out-Null
    $remoteProbe = 'C:/ProgramData/fleet-assess-probe.ps1'
    $remoteCmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File ' + $remoteProbe
    $out = & ssh -o BatchMode=yes -o ConnectTimeout=15 $h $remoteCmd 2>&1 | Out-String
    $line = ($out -split "`r?`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
    if ($line) { $result += ($line | ConvertFrom-Json) } else { Write-Output ('  ' + $h + ': unreachable or probe failed') }
}
if (-not $result.Count) { Write-Output 'no stations measured'; exit 1 }

Write-Output 'ASSESSMENT'
$result | ForEach-Object { '  {0,-14} cores={1,-3} threads={2,-3} ram={3,-5}GB free={4,-6}GB share-disk={5,-7}GB static={6,-5} scaling@threads={7}x' -f $_.host, $_.cores, $_.logical, $_.ramGB, $_.freeRamGB, $_.shareDiskGB, $_.staticIp, $_.scaling }

$coord = $result | Sort-Object @{Expression={[int]$_.staticIp};Descending=$true}, @{Expression={$_.shareDiskGB};Descending=$true}, @{Expression={$_.ramGB};Descending=$true} | Select-Object -First 1
Write-Output ''
Write-Output 'RECOMMENDATION'
Write-Output ('  coordinator : ' + $coord.host + '  (' + $coord.ip + ', ' + $coord.shareDiskGB + ' GB share disk, static=' + $coord.staticIp + ')')
Write-Output '    why: the share lives here; every worker depends on it staying reachable'

# Auditor: independence is the point. It must not audit the machine it runs on, and a
# dedicated host outside the fleet is better than any station.
if ($AuditorHost) {
    Write-Output ('  auditor     : ' + $AuditorHost + '  (operator-provided, outside the fleet)')
} else {
    $cand = $result | Where-Object { $_.host -ne $coord.host } | Sort-Object @{Expression={$_.freeRamGB};Descending=$true} | Select-Object -First 1
    if ($cand) { Write-Output ('  auditor     : ' + $cand.host + '  (no dedicated host supplied; least-loaded non-coordinator)') }
    else { Write-Output '  auditor     : none available - every host is the coordinator; supply an external host' }
}
Write-Output '    needs: read-only share access, reachability to every station, and NOT the node it audits'

foreach ($h in $result) {
    $slots = [Math]::Min($SlotCap, [Math]::Max(4, [int]$h.logical))
    $cpuOnly = [Math]::Min($SlotCap, [Math]::Max(2, [int]$h.cores))
    '  {0,-14} slots={1,-3} (interpreter-bound)   slots={2,-3} (compiled/CPU-bound)' -f $h.host, $slots, $cpuOnly
}
Write-Output ''
Write-Output '  Re-measure after deploy: run a burst sized to the slot total and read per-node'
Write-Output '  distribution, not just the drained count. scripts/audit-efficiency.ps1 reports utilisation.'
<#
  check-prerequisites.ps1 - verify a station before admitting it to the fleet.

    check-prerequisites.ps1 -Coordinator 10.0.0.10
    check-prerequisites.ps1 -Coordinator coord.example.net -Share '\\\\coord.example.net\\fleet'

  Reports each requirement from docs/fleet-minimums.md as PASS/FAIL with the measured value.
  Exit code 1 if any hard requirement fails, so it can gate automation.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string] $Coordinator,
  [string] $Share,
  [int] $MaxClockSkewSeconds = 120,
  [int] $MinCores = 2,
  [double] $MinRamGB = 4
)
$ErrorActionPreference = 'Continue'
if (-not $Share) { $Share = $Coordinator.TrimEnd('\') }
if ($Share -notlike '*\\*') { $Share = '\\' + $Coordinator + '\fleet' }

$fail = 0
function Check([string]$name, [bool]$ok, [string]$detail) {
  $tag = if ($ok) { 'PASS' } else { 'FAIL' }
  if (-not $ok) { $script:fail++ }
  '  {0}  {1,-34} {2}' -f $tag, $name, $detail
}

'PREREQUISITES for ' + $env:COMPUTERNAME + ' joining ' + $Coordinator

# 1. PowerShell
$psv = $PSVersionTable.PSVersion
Check 'PowerShell 5.1 or newer' ($psv -ge [version]'5.1') ($psv.ToString())

# 2. SMB reachable
$tcp = New-Object System.Net.Sockets.TcpClient
$smbOk = $false
try { $a = $tcp.ConnectAsync($Coordinator, 445); $smbOk = ($a.Wait(4000) -and $tcp.Connected) } catch { } finally { $tcp.Close() }
Check 'SMB 445 reachable' $smbOk $(if ($smbOk) { 'connected' } else { 'no route to ' + $Coordinator + ':445' })

# 3. share visible
$queue = Join-Path $Share 'queue'
$shareOk = $false
  try { $shareOk = Test-Path $queue -ErrorAction Stop } catch { }
  if ($false) { Test-Path $queue }
if (-not $shareOk) {
  # An interactive/management session has no SMB credential of its own; the agent creates one.
  # Use the station's stored credential so the check tests what the agent will actually see.
  $dirs = @('C:\fleet', (Join-Path $env:USERPROFILE 'fleet'), (Split-Path -Parent $PSCommandPath)) | Where-Object { $_ }
  foreach ($dir in $dirs) {
    $credF = Join-Path $dir 'coordinator.cred'
    $userF = Join-Path $dir 'coordinator.user'
    if ((Test-Path $credF) -and (Test-Path $userF)) {
      try {
        Add-Type -AssemblyName System.Security
        $u = (Get-Content $userF -Raw).Trim()
        $enc = [IO.File]::ReadAllBytes($credF)
        $pw = [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect($enc, $null, 'LocalMachine'))
        $null = net use $Share /user:$u $pw 2>&1
        $shareOk = $false
  try { $shareOk = Test-Path $queue -ErrorAction Stop } catch { }
  if ($false) { Test-Path $queue }
      } catch { }
      break
    }
  }
}
Check 'share queue visible' $shareOk $(if ($shareOk) { $queue } else { 'not accessible; check credential and share ACL' })

# 4. administrator
$isAdmin = $false
try {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $isAdmin = (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { }
Check 'administrator (provisioning)' $isAdmin $(if ($isAdmin) { 'elevated' } else { 'not elevated - required once, at provisioning' })

# 5. clock skew against the coordinator's newest heartbeat, if visible
$skewOk = $true; $skewDetail = 'no heartbeat visible to compare'
$hb = Get-ChildItem (Join-Path $Share 'results') -Recurse -File -Filter 'heartbeat*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($hb) {
  $skew = [math]::Abs(((Get-Date).ToUniversalTime() - $hb.LastWriteTime.ToUniversalTime()).TotalSeconds)
  $skewOk = ($skew -le $MaxClockSkewSeconds)
  $skewDetail = ([math]::Round($skew)).ToString() + 's vs newest heartbeat (limit ' + $MaxClockSkewSeconds + 's)'
}
Check 'clock within skew limit' $skewOk $skewDetail

# 6. resources
$c = Get-CimInstance Win32_Processor | Select-Object -First 1
$o = Get-CimInstance Win32_OperatingSystem
$ramGB = [math]::Round($o.TotalVisibleMemorySize/1MB,1)
Check ('cores >= ' + $MinCores) ($c.NumberOfCores -ge $MinCores) ($c.NumberOfCores.ToString() + ' cores / ' + $c.NumberOfLogicalProcessors + ' threads')
Check ('RAM >= ' + $MinRamGB + ' GB') ($ramGB -ge $MinRamGB) ($ramGB.ToString() + ' GB')

# 7. scheduled tasks (agent supervision)
$tasksOk = $false
try { $tasksOk = ((& schtasks /query /fo LIST 2>&1 | Out-String).Length -gt 0) } catch { }
Check 'scheduled tasks readable' $tasksOk $(if ($tasksOk) { 'ok' } else { 'schtasks failed - cannot run the agent at startup' })

'---'
if ($fail -eq 0) { 'RESULT: PASS - station may join the fleet'; exit 0 }
else { 'RESULT: FAIL - ' + $fail + ' requirement(s) not met'; exit 1 }
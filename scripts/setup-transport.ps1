<#
  setup-transport.ps1 - build the fleet transport on a station. Run as admin, on the station.

    -Role coordinator  -SharePath D:\fleet -Accounts 'fleet-worker-b','fleet-worker-c'
    -Role worker       -CoordinatorUnc \\10.0.0.10\fleet -Node node-b -Slots 8

  Check-then-act: a rerun repairs rather than duplicates. Encodes what the 2026-11-27 lab proved:

  - claim markers need a directory the worker account can WRITE (queue/ itself refuses creates, and a
    marker that cannot be created makes the worker skip every task silently);
  - parallelism comes from runspaces inside ONE agent process, because a child process does not
    inherit its parent's network session;
  - the coordinator works from its LOCAL path, because SMB loopback to a share on the same machine
    is refused;
  - an escaped UNC that collapses to one backslash yields 'The network name cannot be found', so the
    path is rebuilt from character codes rather than trusted from the shell.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory)][ValidateSet('coordinator','worker')][string] $Role,
  [string] $SharePath = 'D:\fleet',
  [string[]] $Accounts = @(),
  [string] $CoordinatorUnc,
  [string] $Node,
  [int] $Slots = 8,
  [string] $ShareName = 'fleet',
  [int] $ReaperMinutes = 5
)
$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $PSCommandPath
# accounts may arrive comma-joined from a shell; split on commas so a single string
# is never mistaken for an account name (AddAccessRule then throws IdentityNotMapped)
$Accounts = @($Accounts | ForEach-Object { [string]$_ -split ',' } | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
$BS = [string][char]92
function Say($m) { Write-Output ('== ' + $m) }
function Normalize-Unc([string]$u) {
  if (-not $u) { return $u }
  if ($u -match '^[A-Za-z]:') { return $u }
  $host_ = ($u -replace '^[\\/]+','') -split '[\\/]' | Select-Object -First 1
  $share = (($u -replace '^[\\/]+','') -split '[\\/]') | Select-Object -Skip 1 -First 1
  return ($BS + $BS + $host_ + $BS + $share)
}

if ($Role -eq 'coordinator') {
  Say 'share and directories'
  New-Item -ItemType Directory -Force -Path $SharePath | Out-Null
  foreach ($d in @('queue','claimed','results','locks','findings')) { New-Item -ItemType Directory -Force -Path (Join-Path $SharePath $d) | Out-Null }
  if (-not (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)) {
    if ($Accounts.Count) { New-SmbShare -Name $ShareName -Path $SharePath -FullAccess 'Administrators' -ChangeAccess $Accounts -ErrorAction Stop | Out-Null }
    else { New-SmbShare -Name $ShareName -Path $SharePath -FullAccess 'Administrators' -ErrorAction Stop | Out-Null }
    Write-Output ('  created share ' + $ShareName)
  } else { Write-Output ('  share ' + $ShareName + ' exists') }

  Say 'locks ACL - the worker accounts must be able to create markers here'
  foreach ($acct in $Accounts) {
    $p = Join-Path $SharePath 'locks'
    $acl = Get-Acl $p
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($acct,'Modify','ContainerInherit,ObjectInherit','None','Allow')))
    Set-Acl -Path $p -AclObject $acl
    Write-Output ('  granted Modify on locks: ' + $acct)
  }

  Say 'coordinator works from the local path'
  Set-Content -LiteralPath (Join-Path $SharePath 'coordinator.unc') -Value $SharePath -Encoding ascii -NoNewline
  Write-Output ('  coordinator.unc = ' + $SharePath)

  Say 'reaper task (claim ageing, dead tasks, result pruning)'
  $reaper = Join-Path $here 'Invoke-FleetReaper.ps1'
  if (Test-Path $reaper) {
    Copy-Item $reaper (Join-Path $SharePath 'Invoke-FleetReaper.ps1') -Force
    $tr = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ' + (Join-Path $SharePath 'Invoke-FleetReaper.ps1')
    & schtasks /create /tn FleetReaper /tr $tr /sc minute /mo $ReaperMinutes /ru SYSTEM /rl highest /f 2>&1 | Out-Null
    Write-Output ('  FleetReaper registered every ' + $ReaperMinutes + ' min')
  } else { Write-Output '  Invoke-FleetReaper.ps1 not beside this script - skipped' }
  exit 0
}

if (-not $Node) { throw '-Node is required for a worker' }
if (-not $CoordinatorUnc) { throw '-CoordinatorUnc is required for a worker' }
$CoordinatorUnc = Normalize-Unc $CoordinatorUnc
$wdir = if (Test-Path 'C:\fleet\node.txt') { 'C:\fleet' } else { 'C:\Users\' + $env:USERNAME + '\fleet' }
New-Item -ItemType Directory -Force -Path $wdir,(Join-Path $wdir 'logs') | Out-Null

Say 'identity files'
Set-Content -LiteralPath (Join-Path $wdir 'node.txt') -Value $Node -Encoding ascii -NoNewline
Set-Content -LiteralPath (Join-Path $wdir 'coordinator.unc') -Value $CoordinatorUnc -Encoding ascii -NoNewline
Write-Output ('  unc = ' + $CoordinatorUnc)
if (-not (Test-Path (Join-Path $wdir 'coordinator.cred'))) {
  Write-Output '  NOTE: coordinator.user and coordinator.cred (DPAPI LocalMachine, this machine) must be provisioned separately'
}

Say 'deploy agent'
Copy-Item (Join-Path $here 'FleetAgent.ps1') (Join-Path $wdir 'FleetAgent.ps1') -Force
Write-Output ('  ' + (Join-Path $wdir 'FleetAgent.ps1'))

Say 'register the agent task'
$tr = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ' + (Join-Path $wdir 'FleetAgent.ps1') + ' -Slots ' + $Slots
& schtasks /end /tn FleetAgent 2>&1 | Out-Null
& schtasks /create /tn FleetAgent /tr $tr /sc onstart /ru SYSTEM /rl highest /f 2>&1 | Out-Null
& schtasks /run /tn FleetAgent 2>&1 | Out-Null

Say 'verify'
Start-Sleep -Seconds 15
$alive = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -match 'FleetAgent' }).Count
Write-Output ('  agent processes: ' + $alive)
Get-Content (Join-Path $wdir 'logs\agent.log') -Tail 3 -ErrorAction SilentlyContinue | ForEach-Object { '  ' + $_.Trim() }
if ($alive -lt 1) { Write-Output '  FAILED: agent not running'; exit 1 }
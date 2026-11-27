<#
  watch-fleet.ps1 - live view of the fleet, refreshed from the coordinator over SSH.

    .\watch-fleet.ps1                 # 3 second refresh
    .\watch-fleet.ps1 -Seconds 1      # faster
    .\watch-fleet.ps1 -Once           # single snapshot (for logging)

  Requires: ssh configured for the coordinator (see ~/.ssh/config). No new ports, no share
  credential: the read-only inspector runs on the coordinator, where the share is local.
#>
[CmdletBinding()]
param([string] $Coordinator = 'mdmfury', [int] $Seconds = 3, [switch] $Once)
$ErrorActionPreference = 'Continue'
$probe = 'C:/Users/Maarten/fleet/inspect-share.ps1'

function Snapshot {
    $ts = (Get-Date).ToString('HH:mm:ss')
    $out = & ssh -o BatchMode=yes -o ConnectTimeout=8 $Coordinator "powershell -NoProfile -ExecutionPolicy Bypass -File $probe" 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -or -not $out.Trim()) {
        return @("[" + $ts + "]  UNREACHABLE: could not read the coordinator")
    }
    $lines = @("[" + $ts + "]  fleet  " + $Coordinator)
    $lines += ($out -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { '  ' + $_.Trim() })
    return $lines
}

if ($Once) { Snapshot | ForEach-Object { Write-Host $_ }; exit 0 }

Write-Host 'Fleet watch - Ctrl+C to stop' -ForegroundColor Cyan
$prev = @()
while ($true) {
    $snap = Snapshot
    Clear-Host
    Write-Host ('Fleet watch  ' + (Get-Date).ToString('HH:mm:ss') + '   Ctrl+C to stop') -ForegroundColor Cyan
    Write-Host ''
    $snap | ForEach-Object { Write-Host $_ }
    Start-Sleep -Seconds $Seconds
}
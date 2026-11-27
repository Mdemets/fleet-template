<#
  guard-stop.ps1 - halt fleet actions when a STOP file is present.

  The operator stops the fleet's automation by creating one file. Any script that changes state
  calls this first; if it exits 1, the action is abandoned and reported, never silently skipped.

    guard-stop.ps1                 # exit 1 when a STOP file exists
    guard-stop.ps1 -Status         # report where it looked and whether it found one
#>
[CmdletBinding()]
param([switch] $Status)
$ErrorActionPreference = 'Continue'
$candidates = @(
    (Join-Path $PSScriptRoot 'STOP'),
    'C:\fleet\STOP',
    (Join-Path $env:USERPROFILE 'fleet\STOP'),
    'D:\fleet\STOP'
)
$hit = @($candidates | Where-Object { Test-Path -LiteralPath $_ })
if ($Status) {
    foreach ($c in $candidates) { '  {0}  {1}' -f $(if (Test-Path -LiteralPath $c) { 'STOP' } else { '    ' }), $c }
    if ($hit.Count) { 'STOPPED - ' + $hit[0] } else { 'clear - no STOP file' }
    exit $(if ($hit.Count) { 1 } else { 0 })
}
if ($hit.Count) { Write-Output ('STOP FILE PRESENT: ' + $hit[0]); exit 1 }
exit 0
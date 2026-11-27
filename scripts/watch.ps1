param(
  [int]$EverySec = 120,
  [int]$Iterations = 240,
  [string]$Channel = $env:FLEET_CHANNEL,
  [string]$Peers = $env:FLEET_PEERS
)
# One line per sample: local procs, each peer's procs, inbox note count.
# The point is that it keeps writing while you are not looking.
if (-not (Test-Path $Channel)) { throw "channel not found: $Channel" }
$log = Join-Path $Channel 'watch.log'
for ($i = 0; $i -lt $Iterations; $i++) {
  $t = Get-Date -Format 'HH:mm:ss'
  $local = (Get-Process cargo,rustc -ErrorAction SilentlyContinue | Measure-Object).Count
  $line = "$t local=$local"
  if ($Peers) {
    foreach ($p in $Peers -split ',') {
      $parts = $p -split '='
      $name = $parts[0]
      $target = $parts[1]
      $n = 'unreachable'
      try {
        $m = ssh -o ConnectTimeout=6 -o BatchMode=yes $target '(Get-Process cargo -ErrorAction SilentlyContinue | Measure-Object).Count' 2>$null
        if ($m) { $n = ($m | Select-Object -Last 1).Trim() }
      } catch { $n = 'ssh-fail' }
      $line = $line + " $name=$n"
    }
  }
  $notes = (Get-ChildItem (Join-Path $Channel 'inbox') -Filter '*.md' -ErrorAction SilentlyContinue | Measure-Object).Count
  $line = $line + " notes=$notes"
  Add-Content -Path $log -Value $line
  Start-Sleep -Seconds $EverySec
}

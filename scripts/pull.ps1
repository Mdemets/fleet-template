param(
  [string]$Channel = $env:FLEET_CHANNEL,
  [string]$Share
)
# Mirror new notes from the shared inbox into the local channel.
$inbox = Join-Path $Channel 'inbox'
New-Item -ItemType Directory -Force -Path $inbox | Out-Null
if (-not $Share) { Write-Output 'pull: no -Share given, nothing to do'; exit 0 }
if (-not (Test-Path $Share)) { Write-Output "pull failed: share unreachable: $Share"; exit 1 }
Get-ChildItem $Share -Filter '*.md' -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
  $dest = Join-Path $inbox $_.Name
  if (-not (Test-Path $dest) -or (Get-Item $dest).Length -ne $_.Length) {
    Copy-Item $_.FullName $dest -Force
    Write-Output ('new: ' + $_.Name)
  }
}

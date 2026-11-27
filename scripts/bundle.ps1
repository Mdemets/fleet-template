param(
  [Parameter(Mandatory=$true)][string]$Base,
  [Parameter(Mandatory=$true)][string]$Branch,
  [Parameter(Mandatory=$true)][string]$Out,
  [string]$Share
)
# Cut a ref-named bundle, verify it names the branch, write the commit next to it.
# A bundle without its ref name costs a peer a round trip. A bundle without its
# commit pin cannot be compared to anything.
git bundle create $Out "$Base..$Branch" | Out-Host
$heads = git bundle list-heads $Out
if (-not ($heads -match [regex]::Escape($Branch))) {
  Write-Output "bundle verify FAILED: $Branch not in heads"
  Write-Output $heads
  exit 1
}
$commit = (git rev-parse $Branch).Trim()
$pin = $Out -replace '\.bundle$', '-commit.txt'
Set-Content -Path $pin -Value $commit -NoNewline
Write-Output "bundle ok: refs/heads/$Branch = $commit"
if ($Share -and (Test-Path $Share)) {
  Copy-Item $Out (Join-Path $Share (Split-Path $Out -Leaf)) -Force
  Copy-Item $pin (Join-Path $Share (Split-Path $pin -Leaf)) -Force
}

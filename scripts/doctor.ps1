param(
  [string]$Manifest = (Join-Path $PSScriptRoot '..\config\env-manifest.example.json')
)
# Read-only drift check. Lanes run this first and fail closed.
$fail = 0
function Check($name, $expected, $actual) {
  if ($expected -and ($actual -notlike ('*' + $expected + '*'))) {
    Write-Output ("DRIFT  " + $name + ": expected " + $expected + ", found " + $actual)
    $script:fail = 1
  } else {
    Write-Output ("ok     " + $name + ": " + $actual)
  }
}
$m = Get-Content -Raw $Manifest | ConvertFrom-Json
$rustc = (rustc --version) -join ' '
Check 'rustc' $m.pinned.rustToolchain $rustc
$drv = ((nvidia-smi --query-gpu=driver_version --format=csv,noheader) | Select-Object -First 1) -join ' '
Check 'gpu driver' $m.pinned.gpuDriver $drv
$dxil = Get-ChildItem -Path $PSScriptRoot '..' -Recurse -Filter 'dxil.dll' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($dxil) {
  $hash = (Get-FileHash $dxil.FullName -Algorithm SHA256).Hash.ToLower()
  Check 'dxil.dll' $m.pinned.dxilDllSha256 $hash
} else {
  Write-Output 'DRIFT  dxil.dll: not found (server-side validation would silently skip)'
  $fail = 1
}
if (-not $env:FLEET_CHANNEL -or -not (Test-Path $env:FLEET_CHANNEL)) {
  Write-Output 'DRIFT  FLEET_CHANNEL missing or unreachable'
  $fail = 1
} else {
  Write-Output ('ok     channel: ' + $env:FLEET_CHANNEL)
}
if ($fail -ne 0) { Write-Output 'doctor: FAILED - environment drifted; do not report results from this box'; exit 1 }
Write-Output 'doctor: clean'

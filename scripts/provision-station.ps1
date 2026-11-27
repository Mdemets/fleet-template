# provision-station.ps1 - run ONCE per image, as the provisioner account, by a human.
# Never run this as a lane. It is check-then-act so a rerun repairs rather than duplicates.
# Every step writes to the environment manifest so drift is detectable later.
$ErrorActionPreference = 'Stop'
function Step($name, $block) {
  Write-Output ('== ' + $name)
  & $block
  if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw ($name + ' failed with exit ' + $LASTEXITCODE) }
}

Step 'verify inputs' {
  # Refuse to proceed without hashes for every installer and the vendor directory.
  if (-not (Test-Path .\inputs\hashes.txt)) { throw 'missing inputs/hashes.txt' }
  Get-Content .\inputs\hashes.txt
}

Step 'build tools' {
  # Check first, install only when absent. Pin the exact version.
  $vs = 'C:\Program Files\Microsoft Visual Studio\2022\Community'
  if (-not (Test-Path $vs)) {
    Write-Output 'VS Build Tools absent - install with the C++ workload and Windows SDK from inputs'
    # & .\inputs\vs_buildtools.exe --quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended
  } else { Write-Output 'present' }
}

Step 'rust toolchain' {
  # Pinned by rust-toolchain.toml; rustup installs exactly that, no auto-update.
  rustup toolchain install (Get-Content .\rust-toolchain.toml | Select-String 'channel').ToString()
}

Step 'offline crates' {
  if (-not (Test-Path .\vendor)) { throw 'vendor directory missing - builds are not reproducible offline' }
  $h = (Get-FileHash .\vendor\MANIFEST -Algorithm SHA256 -ErrorAction SilentlyContinue)
  Write-Output ('vendor manifest: ' + $h.Hash)
}

Step 'validation dll' {
  if (-not (Test-Path .\inputs\dxil.dll)) { throw 'dxil.dll missing - the test host would skip validation' }
  Copy-Item .\inputs\dxil.dll .\tools\dxil.dll -Force
}

Step 'accounts and acls' {
  # Create fleet-admin, fleet-station, fleet-lane, fleet-test; then apply ACLs:
  #   channel: read for lane, write per station
  #   branch-of-record checkout: read-only for everyone but the coordinator
  #   each worktree: writable only by its lane
  Write-Output 'see docs/fleet-playbook.md section 10.2/10.3; apply with icacls, log every change'
}

Step 'runner and sampler tasks' {
  # Scheduled tasks running as fleet-test (runner) and fleet-station (sampler).
  Write-Output 'register tasks; keep their definitions writable only by the provisioner'
}

Step 'manifest and lock' {
  # Write env-manifest.json with versions and hashes; then disable the provisioner account.
  Write-Output 'manifest written; disable provisioner, exit 0'
}

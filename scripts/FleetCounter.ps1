
$ErrorActionPreference='Continue'
$script:CounterFile = 'D:\fleet\status\created.json'
$script:LockFile = 'D:\fleet\status\created.lock'

function Add-Created {
  param([int]$n = 1, [string]$source = 'unknown')
  for ($try = 0; $try -lt 20; $try++) {
    try {
      $fs = [IO.File]::Open($script:LockFile, 'OpenOrCreate', 'ReadWrite', 'None')
      try {
        $total = 0; $by = @{}
        if (Test-Path $script:CounterFile) {
          try {
            $j = Get-Content $script:CounterFile -Raw | ConvertFrom-Json
            $total = [int]$j.total
            if ($j.bySource) { $j.bySource.PSObject.Properties | ForEach-Object { $by[$_.Name] = [int]$_.Value } }
          } catch { }
        }
        $total += $n
        if (-not $by.ContainsKey($source)) { $by[$source] = 0 }
        $by[$source] += $n
        @{ total = $total; bySource = $by; updated = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:CounterFile -Encoding utf8
      } finally { $fs.Close() }
      return $total
    } catch { Start-Sleep -Milliseconds 50 }
  }
  return -1
}

function Get-Created {
  if (-not (Test-Path $script:CounterFile)) { return 0 }
  try { return [int]((Get-Content $script:CounterFile -Raw | ConvertFrom-Json).total) } catch { return 0 }
}

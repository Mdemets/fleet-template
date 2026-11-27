param(
  [string]$From = $env:FLEET_STATION,
  [string]$Subject = 'note',
  [string]$Text = '',
  [string]$Channel = $env:FLEET_CHANNEL
)
# Numbered, attributable notes. A post that did not happen must say so.
$inbox = Join-Path $Channel 'inbox'
if (-not (Test-Path $inbox)) { Write-Output "post failed: no inbox at $inbox"; exit 1 }
$files = @(Get-ChildItem $inbox -Filter '*.md' -ErrorAction SilentlyContinue)
$max = 1
foreach ($f in $files) {
  $n = 0
  if ([int]::TryParse(($f.Name -split '-')[0], [ref]$n)) { if ($n -ge $max) { $max = $n + 1 } }
}
$slug = (($Subject -replace '[^A-Za-z0-9]+', '-').Trim('-').ToLower())
if ($slug -eq '') { $slug = 'note' }
$name = '{0:d4}-from-{1}-{2}.md' -f $max, $From.ToLower(), $slug
$nl = [Environment]::NewLine
$body = (@(('# {0:d4} - from {1}: {2}' -f $max, $From, $Subject), '', ('_' + (Get-Date -Format o) + ' from ' + $env:COMPUTERNAME + '_'), '', $Text) -join $nl)
try {
  [IO.File]::WriteAllText((Join-Path $inbox $name), $body, (New-Object System.Text.UTF8Encoding($false)))
  Write-Output "posted: $name"
} catch {
  Write-Output ('post failed: ' + $_.Exception.Message)
  exit 1
}

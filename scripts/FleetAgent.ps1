# FleetAgent.ps1 - one process per station owning the share session, fanning work out to
# runspaces. Child processes do not inherit a network session (three attempts proved it),
# but runspaces live inside this process and use its session.
param([int]$Slots = 8)
$ErrorActionPreference = 'Continue'

$here = Split-Path -Parent $PSCommandPath
$logDir = Join-Path $here 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'agent.log'
function Alog([string]$m) { try { Add-Content -LiteralPath $log -Value ((Get-Date).ToUniversalTime().ToString('HH:mm:ssZ') + '  ' + $m) } catch { } }

$node = (Get-Content -LiteralPath (Join-Path $here 'node.txt') -Raw).Trim()
$unc  = (Get-Content -LiteralPath (Join-Path $here 'coordinator.unc') -Raw).Trim()
$localShare = ($unc -match '^[A-Za-z]:')

if (-not $localShare -and -not (Test-Path (Join-Path $unc 'queue'))) {
    Add-Type -AssemblyName System.Security
    $user = (Get-Content -LiteralPath (Join-Path $here 'coordinator.user') -Raw).Trim()
    $enc  = [IO.File]::ReadAllBytes((Join-Path $here 'coordinator.cred'))
    $pw   = [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect($enc, $null, 'LocalMachine'))
    $out = net use $unc /user:$user $pw 2>&1
    Alog ('session rc=' + $LASTEXITCODE + ' ' + (($out | Out-String).Trim() -replace $pw,'***'))
}
Alog ('agent start node=' + $node + ' unc=' + $unc + ' slots=' + $Slots)

$qdir    = Join-Path $unc 'queue'
$locks   = Join-Path $unc 'locks'
$myClaim = Join-Path $unc ('claimed\' + $node)
$myRes   = Join-Path $unc ('results\' + $node)
foreach ($d in @($myClaim, $myRes, $locks)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }

$pool = [runspacefactory]::CreateRunspacePool(1, $Slots)
$pool.Open()
Alog ('runspace pool open, max=' + $Slots)

$active = @{}
function Complete-Task($key) {
    $j = $active[$key]
    $active.Remove($key)
    $timedOut = $false
    try {
        if (-not $j.Handle.AsyncWaitHandle.WaitOne(200)) {
            $j.Ps.Stop()
            $timedOut = $true
        }
        $outText = ''; $errText = ''
        try { $r = $j.Ps.EndInvoke($j.Handle); $outText = (($r | Out-String)) } catch { $errText = [string]$_.Exception.Message }
        if (-not $errText) { $errText = (($j.Ps.Streams.Error | Out-String)) }
        $res = [ordered]@{
            id = $j.Id; node = $node; kind = 'powershell'
            claimedAt = $j.ClaimedAt; finishedAt = (Get-Date).ToUniversalTime().ToString('o')
            exitCode = $(if ($timedOut) { -1 } elseif ($errText.Trim()) { 1 } else { 0 })
            timedOut = $timedOut; stdout = $outText; stderr = $errText; error = $(if ($timedOut) { 'timed out' } else { $null })
        }
        [IO.File]::WriteAllText((Join-Path $myRes ('result-' + $j.Id + '.json')), ($res | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding($false)))
        Remove-Item -LiteralPath $j.Claim -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $j.ClaimFile -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $j.Mark -Force -ErrorAction SilentlyContinue
    } catch { Alog ('complete failed ' + $j.Id + ': ' + $_.Exception.Message) }
}

while ($true) {
    try {
        foreach ($k in @($active.Keys)) { if ($active[$k].Handle.IsCompleted) { Complete-Task $k } }

        $capacity = $Slots - $active.Count
        if ($capacity -gt 0 -and (Test-Path $qdir)) {
            $files = @(Get-ChildItem -LiteralPath $qdir -Filter 'task-*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -First $capacity)
            foreach ($f in $files) {
                $mark = Join-Path $locks ($f.Name + '.claim')
                try { $mk = [IO.File]::Open($mark, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None); $mk.Close() } catch { continue }
                $dest = Join-Path $myClaim $f.Name
                try { Move-Item -LiteralPath $f.FullName -Destination $dest -ErrorAction Stop } catch { Remove-Item $mark -Force -ErrorAction SilentlyContinue; continue }
                $id = ($f.BaseName -replace '^task-','')
                $claimedAt = (Get-Date).ToUniversalTime().ToString('o')
                $claimRec = Join-Path (Join-Path $myRes 'claims') ($id + '.json')
                New-Item -ItemType Directory -Force -Path (Split-Path $claimRec) | Out-Null
[IO.File]::WriteAllText($claimRec, (@{ id = $id; node = $node; claimedAt = $claimedAt } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
                try {
                    $task = Get-Content -LiteralPath $dest -Raw | ConvertFrom-Json
                    $ps = [powershell]::Create()
                    $ps.RunspacePool = $pool
                    [void]$ps.AddScript([string]$task.payload.script)
                    $handle = $ps.BeginInvoke()
                    $active[$id] = [pscustomobject]@{ Ps = $ps; Handle = $handle; Id = $id; ClaimedAt = $claimedAt; Claim = $claimRec; ClaimFile = $dest; Mark = $mark }
                    Alog ('start ' + $id)
                } catch { Alog ('start failed ' + $id + ': ' + $_.Exception.Message) }
            }
        }
    } catch { Alog ('loop error: ' + $_.Exception.Message) }

    try { @{ ts = (Get-Date).ToUniversalTime().ToString('o'); node = $node; active = $active.Count } | ConvertTo-Json -Compress | Set-Content -LiteralPath (Join-Path $myRes 'heartbeat.json') -Encoding ascii -Force } catch { }
    if ($active.Count -gt 0) { Start-Sleep -Milliseconds 100 } else { Start-Sleep -Milliseconds 800 }
}
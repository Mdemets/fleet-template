param(
    [string]$Root = 'D:/fleet',
    [int]$GraceSeconds = 300,
    [int]$MaxAttempts = 3,
    [switch]$Install,
    [int]$IntervalMinutes = 5,
    [int]$KeepDoneDays = 30,
    [int]$KeepResultDays = 90
)

$ErrorActionPreference = 'Stop'

$queue   = Join-Path $Root 'queue'
$claimed = Join-Path $Root 'claimed'
$results = Join-Path $Root 'results'
$logFile = Join-Path $Root 'reaper.log'

function Write-Reap([string]$msg) {
    $line = '{0}  {1}' -f (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'), $msg
    try { Add-Content -LiteralPath $logFile -Value $line -ErrorAction Stop } catch { }
}

if ($Install) {
    $arg = '-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $PSScriptRoot 'Invoke-FleetReaper.ps1') + '"'
    $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
    $trg = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
    Register-ScheduledTask -TaskName 'FleetReaper' -Action $act -Trigger $trg -Settings $set -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
    Write-Host "Installed FleetReaper, every $IntervalMinutes minutes as SYSTEM"
    return
}

if (-not (Test-Path -LiteralPath $claimed)) { Write-Reap 'no claimed directory'; exit 0 }

$resultIds = @{}
if (Test-Path -LiteralPath $results) {
    Get-ChildItem -LiteralPath $results -Recurse -File -Filter 'result-*.json' -ErrorAction SilentlyContinue | ForEach-Object {
        $resultIds[($_.BaseName -replace '^result-', '')] = $_.FullName
    }
}

$now = (Get-Date).ToUniversalTime()
$requeued = 0; $completed = 0; $deadCount = 0

foreach ($nodeDir in @(Get-ChildItem -LiteralPath $claimed -Directory -ErrorAction SilentlyContinue)) {
    $node = $nodeDir.Name
    foreach ($f in @(Get-ChildItem -LiteralPath $nodeDir.FullName -File -Filter 'task-*.json' -ErrorAction SilentlyContinue)) {
        try { $task = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json } catch { Write-Reap "unreadable claim $($f.Name) in $node"; continue }

        $id = $f.BaseName -replace '^task-', ''
        if ($task.id) { $id = [string]$task.id }

        $lease = 600
        if ($task.timeoutSeconds) { $lease = [int]$task.timeoutSeconds }

        # D1: age the claim, not the task. Move-Item preserves the task's LastWriteTime, so a
        # backlogged task used to look stale the instant it was claimed and was requeued while
        # still running. Prefer an explicit claim time; fall back to the file timestamp.
        $claimedAt = $f.LastWriteTime.ToUniversalTime()
        # The claim marker is created at claim time and removed at completion, so its timestamp
        # is the most reliable claim age. The results sidecar remains only as a legacy fallback.
        $markFile = Join-Path (Join-Path $Root 'locks') ($f.Name + '.claim')
        if (Test-Path -LiteralPath $markFile) {
            $claimedAt = (Get-Item -LiteralPath $markFile).LastWriteTime.ToUniversalTime()
        }
        $claimRec = Join-Path $results ($node + '\claims\' + $id + '.json')
        if (-not (Test-Path -LiteralPath $markFile) -and (Test-Path -LiteralPath $claimRec)) {
            try {
                $rec = Get-Content -LiteralPath $claimRec -Raw | ConvertFrom-Json
                if ($rec.claimedAt) { $claimedAt = [datetime]::Parse([string]$rec.claimedAt).ToUniversalTime() }
            } catch { }
        } elseif ($task.PSObject.Properties['claimedAt'] -and $task.claimedAt) {
            try { $claimedAt = [datetime]::Parse([string]$task.claimedAt).ToUniversalTime() } catch { }
        }
        $age = [int](($now - $claimedAt).TotalSeconds)
        if ($age -le ($lease + $GraceSeconds)) { continue }

        $stageDir = Join-Path $nodeDir.FullName 'done'
        if ($resultIds.ContainsKey($id)) {
            if (-not (Test-Path -LiteralPath $stageDir)) { New-Item -ItemType Directory -Path $stageDir -Force | Out-Null }
            Move-Item -LiteralPath $f.FullName -Destination (Join-Path $stageDir $f.Name) -Force
            Write-Reap "done   $id (claimed on $node, result present, age ${age}s)"
            $completed++
            continue
        }

        $attempts = 0
        if ($task.PSObject.Properties['attempts']) { $attempts = [int]$task.attempts }
        $attempts++

        if ($attempts -gt $MaxAttempts) {
            $deadDir = Join-Path $nodeDir.FullName 'dead'
            if (-not (Test-Path -LiteralPath $deadDir)) { New-Item -ItemType Directory -Path $deadDir -Force | Out-Null }
            Move-Item -LiteralPath $f.FullName -Destination (Join-Path $deadDir $f.Name) -Force
            Write-Reap "dead   $id (claimed on $node, attempt $attempts exceeds $MaxAttempts, age ${age}s)"
            $deadCount++
            continue
        }

        $task | Add-Member -NotePropertyName attempts -NotePropertyValue $attempts -Force
        # D12: write without a BOM
        [IO.File]::WriteAllText($f.FullName, ($task | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $f.FullName -Destination (Join-Path $queue "task-$id.json") -Force
        Write-Reap "retry  $id (claimed on $node, age ${age}s, attempt $attempts of $MaxAttempts)"
        $requeued++
    }
}

# D10: nothing was ever pruned. Keep the stages small; results outlive them.
$pruned = 0
$cutStage = $now.AddDays(-$KeepDoneDays)
foreach ($stage in @('done', 'dead')) {
    Get-ChildItem -LiteralPath $claimed -Recurse -Directory -Filter $stage -ErrorAction SilentlyContinue | ForEach-Object {
        Get-ChildItem -LiteralPath $_.FullName -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTimeUtc -lt $cutStage } | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue; $pruned++
        }
    }
}
$cutResults = $now.AddDays(-$KeepResultDays)
Get-ChildItem -LiteralPath $results -Recurse -File -Filter 'result-*.json' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTimeUtc -lt $cutResults } | ForEach-Object {
    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue; $pruned++
}

Write-Reap "sweep complete: retried=$requeued done=$completed dead=$deadCount pruned=$pruned"
Write-Host "sweep: retried=$requeued done=$completed dead=$deadCount pruned=$pruned"

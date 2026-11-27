$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security

$Root   = 'C:/fleet'
$logDir = Join-Path $Root 'logs'

function Write-Log([string]$msg) {
    $line = '{0}  {1}' -f (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'), $msg
    try { Add-Content -LiteralPath (Join-Path $logDir 'worker.log') -Value $line -ErrorAction Stop } catch { }
}

function New-Result {
    param($Id, $Node, $Kind, $ClaimedAt, $Code, $TimedOut, $OutFile, $ErrFile, $Err)
    $so = ''; $se = ''
    try { $so = [string](Get-Content -LiteralPath $OutFile -Raw -ErrorAction SilentlyContinue) } catch { }
    try { $se = [string](Get-Content -LiteralPath $ErrFile -Raw -ErrorAction SilentlyContinue) } catch { }
    $soCut = $so.Length -gt 8000; if ($soCut) { $so = $so.Substring(0, 8000) }
    $seCut = $se.Length -gt 8000; if ($seCut) { $se = $se.Substring(0, 8000) }
    [pscustomobject]@{
        id              = [string]$Id
        node            = [string]$Node
        kind            = [string]$Kind
        claimedAt       = [string]$ClaimedAt
        finishedAt      = (Get-Date).ToUniversalTime().ToString('o')
        exitCode        = [int]$Code
        timedOut        = [bool]$TimedOut
        stdout          = $so
        stderr          = $se
        stdoutTruncated = $soCut
        stderrTruncated = $seCut
        error           = $Err
    }
}

$lockPath = Join-Path $Root 'worker.lock'
try {
    $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
} catch { exit 0 }

$node = (Get-Content -LiteralPath (Join-Path $Root 'node.txt')).Trim()
$user = (Get-Content -LiteralPath (Join-Path $Root 'coordinator.user')).Trim()
$unc  = (Get-Content -LiteralPath (Join-Path $Root 'coordinator.unc')).Trim()
$enc  = [IO.File]::ReadAllBytes((Join-Path $Root 'coordinator.cred'))
$plainPw = [Text.Encoding]::UTF8.GetString([Security.Cryptography.ProtectedData]::Unprotect($enc, $null, 'LocalMachine'))

$qdir    = Join-Path $unc 'queue'
$qOwn    = Join-Path $qdir $node
$myClaim = Join-Path $unc ('claimed\' + $node)
$myRes   = Join-Path $unc ('results\' + $node)
$authMarker = Join-Path $myRes 'auth-failure.json'
$heartbeat  = Join-Path $myRes 'heartbeat.json'

# R2/D2: a dead credential cannot fix itself. Cooldown keeps the 5-minute task trigger
# from generating enough attempts to lock the account.
if (Test-Path -LiteralPath $authMarker) {
    $ageMin = ((Get-Date) - (Get-Item -LiteralPath $authMarker).LastWriteTime).TotalMinutes
    if ($ageMin -lt 15) {
        Write-Log ('auth cooldown active (' + [int]$ageMin + 'm) - exiting without attempting')
        exit 0
    }
}

function Stop-Auth([int]$code) {
    try {
        @{ ts = (Get-Date).ToUniversalTime().ToString('o'); node = $node; rc = $code } |
            ConvertTo-Json -Compress | Set-Content -LiteralPath $authMarker -Encoding ascii -Force
    } catch { }
    Write-Log ('auth failed rc=' + $code + ' - stopping, not retrying')
    exit 1
}

function Connect-Fleet {
    try { Remove-SmbMapping -RemotePath $unc -Force -ErrorAction SilentlyContinue | Out-Null } catch { }
    $mapped = $false
    try {
        New-SmbMapping -RemotePath $unc -UserName $user -Password $plainPw -ErrorAction Stop | Out-Null
        $mapped = $true
    } catch {
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        net use $unc /delete *> $null
        $out = net use $unc /user:$user $plainPw 2>&1
        $rc = $LASTEXITCODE
        $ErrorActionPreference = $prev
        if ($rc -ne 0) {
            if ($rc -in 86, 1326, 1909) { Stop-Auth $rc }
            throw ('net use failed: ' + (($out | Out-String).Trim()))
        }
        $mapped = $true
    }
    if ($mapped -and (Test-Path -LiteralPath $authMarker)) {
        Remove-Item -LiteralPath $authMarker -Force -ErrorAction SilentlyContinue
    }
}

Write-Log "worker start node=$node remote=$unc"

$backoff = 30
while ($true) {
    try {
        if (-not (Test-Path -LiteralPath $qdir)) { Connect-Fleet }

        $files = @()
        foreach ($d in @($qOwn, $qdir)) {
            $files += @(Get-ChildItem -LiteralPath $d -Filter 'task-*.json' -File -ErrorAction SilentlyContinue)
        }
        $files = @($files | Sort-Object LastWriteTime)
        $taken = 0
        foreach ($f in $files) {
            if ($taken -ge 1 -and $f.DirectoryName -eq $qdir) { break }
            $dest = Join-Path $myClaim $f.Name
            # Claim atomically: an exclusive create decides the winner before any move, so a peer
# that also resolved this file cannot execute it a second time.
$claimMark = Join-Path (Join-Path $unc 'locks') ($f.Name + '.claim')
try {
    $mk = [IO.File]::Open($claimMark, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $mk.Close()
} catch { continue }
try { Move-Item -LiteralPath $f.FullName -Destination $dest -ErrorAction Stop } catch { Remove-Item -LiteralPath $claimMark -Force -ErrorAction SilentlyContinue; continue }
Remove-Item -LiteralPath $claimMark -Force -ErrorAction SilentlyContinue
            # D1: the claim's age must be the claim's, not the task's. Move preserves the
            # task's LastWriteTime, so a backlogged task looks stale the instant it is claimed.
            # Setting a file timestamp on this share is not permitted for the worker account
            # (it fails silently), so record claimedAt inside the claim JSON instead - the
            # reaper prefers it and falls back to the file timestamp.
            try { (Get-Item -LiteralPath $dest).LastWriteTime = Get-Date } catch { }
            # The worker may rename into claimed/ but not modify the claim itself (no write-data
            # right there), so the claim time is recorded where results are written instead.
            # The reaper reads this sidecar first.
            $taken++

            $started = (Get-Date).ToUniversalTime().ToString('o')
            # D8: strip the task- prefix, or an id-less payload writes a result the reaper
            # can never match and the task runs twice.
            $id = ($f.BaseName -replace '^task-', '')
            $claimRec = Join-Path (Join-Path $myRes 'claims') "$id.json"
            try {
                New-Item -ItemType Directory -Force -Path (Split-Path $claimRec) | Out-Null
                [IO.File]::WriteAllText($claimRec, (@{ id = $id; node = $node; claimedAt = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
            } catch { Write-Log ('claim record failed: ' + $_.Exception.Message) }
            $outFile = Join-Path $logDir "$id.out"
            $errFile = Join-Path $logDir "$id.err"
            try {
                $task = Get-Content -LiteralPath $dest -Raw | ConvertFrom-Json
                if ($task.id) { $id = [string]$task.id }
                $kind = 'powershell'
                if ($task.kind) { $kind = [string]$task.kind }
                if ($kind -ne 'powershell') {
                    $result = New-Result -Id $id -Node $node -Kind $kind -ClaimedAt $started -Code -2 -TimedOut $false -OutFile $outFile -ErrFile $errFile -Err ("unsupported kind '" + $kind + "'")
                } else {
                    $timeout = 600
                    if ($task.timeoutSeconds) { $timeout = [int]$task.timeoutSeconds }
                    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-Command',[string]$task.payload.script) -RedirectStandardOutput $outFile -RedirectStandardError $errFile -PassThru -WindowStyle Hidden
                    $timedOut = $false
                    if (-not $p.WaitForExit($timeout * 1000)) {
                        # D4: kill the tree; killing the wrapper leaves the payload running
                        & taskkill /PID $p.Id /T /F *> $null
                        $timedOut = $true; $code = -1
                    } else { $code = $p.ExitCode }
                    $result = New-Result -Id $id -Node $node -Kind $kind -ClaimedAt $started -Code $code -TimedOut $timedOut -OutFile $outFile -ErrFile $errFile -Err $null
                }
            } catch {
                $result = New-Result -Id $id -Node $node -Kind '' -ClaimedAt $started -Code -1 -TimedOut $false -OutFile $outFile -ErrFile $errFile -Err $_.Exception.Message
            }

            $tmp   = Join-Path $myRes ".$id.tmp"
            $final = Join-Path $myRes "result-$id.json"
            # D12: no BOM - other JSON consumers choke on it
            [IO.File]::WriteAllText($tmp, ($result | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding($false)))
            Move-Item -LiteralPath $tmp -Destination $final -Force
            $audit = @{ ts = (Get-Date).ToUniversalTime().ToString('o'); node = $node; event = 'finish'; id = $id; exit = $result.exitCode } | ConvertTo-Json -Compress
            Add-Content -LiteralPath (Join-Path $myRes 'audit.jsonl') -Value $audit
            Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $claimRec -Force -ErrorAction SilentlyContinue
            Write-Log "task $id exit=$($result.exitCode) timedOut=$($result.timedOut)"
        }
        $backoff = 30
    } catch {
        Write-Log "loop error: $($_.Exception.Message)"
        Start-Sleep -Seconds $backoff
        $backoff = [Math]::Min($backoff * 2, 300)
        continue
    }

    # D3: a health signal the coordinator can actually read
    try {
        @{ ts = (Get-Date).ToUniversalTime().ToString('o'); node = $node } |
            ConvertTo-Json -Compress | Set-Content -LiteralPath $heartbeat -Encoding ascii -Force
    } catch { }

    if ($taken -eq 0) { Start-Sleep -Seconds (Get-Random -Minimum 10 -Maximum 20) } else { Start-Sleep -Milliseconds 50 }
}
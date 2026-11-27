# 007 - Worker hardening: process tree, credentials, and the small items

Status: accepted and applied 2026-11-27 10:20Z.`n`nVerified: id-less task now writes result-pnoid1.json (D8); results carry stdoutTruncated (D7); a task exceeding a 5s timeout reports timedOut with no surviving child (D4); JSON parses without a BOM (D12). Prune runs (pruned=0, nothing old enough). Kind check and credential mapping are in place but not individually exercised.

## D4 - timeout must kill the tree, not the wrapper

    if (-not $p.WaitForExit($timeout * 1000)) {
        & taskkill /PID $p.Id /T /F *> $null     # /T = children
        $timedOut = $true; $code = -1
    }

Killing only the wrapper leaves the payload running while the reaper requeues the task.

## D5 - keep the password off the command line

    $sec  = ConvertTo-SecureString $plainPw -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($user, $sec)
    New-SmbMapping -RemotePath $unc -Credential $cred | Out-Null

net use with the password as an argument exposes it in the process command line.

## D8 - strip the prefix from the id

    $id = $f.BaseName -replace '^task-', ''

Today an id-less task writes result-task-<id>.json, which the reaper can never match: it requeues
and the task runs twice.

## D7 - say when output was cut

    $soCut = $so.Length -gt 8000; if ($soCut) { $so = $so.Substring(0,8000) }
    ... stdoutTruncated = $soCut; stderrTruncated = $seCut

## D9 - reject unknown kinds

    if ($task.kind -and $task.kind -ne 'powershell') {
        $result.error = "unsupported kind '$($task.kind)'"; $code = -2
    }

## D10 - prune by age

Reaper: delete done/ and dead/ files older than 30 days, results older than 90.

## D12 - JSON without a BOM

    [IO.File]::WriteAllText($tmp, ($result | ConvertTo-Json -Depth 3), (New-Object Text.UTF8Encoding($false)))

## Risk

Low individually; together they touch the whole worker loop, so land them behind one verification
run: a smoke task that sleeps past its timeout, plus one that exits 0, plus one with an id-less
payload.

## Revert

Per item; none of them changes the on-disk protocol.


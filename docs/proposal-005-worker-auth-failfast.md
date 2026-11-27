# 005 - Worker must fail fast on auth errors and stop hammering

Status: accepted and applied 2026-11-27 10:20Z.`n`nApplied: 86/1326/1909 stop the worker and write an auth-failure marker; a 15 minute cooldown prevents the 5-minute trigger from re-attempting. Not exercised against a live bad credential - deliberately, since testing it means locking an account.

## Why

The worker retries every 30s on any error. Against a 10-attempt / 10-minute lockout policy, one bad
credential locks the account in about six minutes, and the retries then hold it locked. This is what
turned a stale in-memory password into a dead node.

## Patch - classify the failure instead of retrying everything

    # after net use fails, look at the Win32 error
    $code = $LASTEXITCODE
    if ($code -in 86,1326,1909) {
        # bad password / logon failure / locked out: retrying cannot help and locks the account
        $marker = Join-Path $myRes 'auth-failure.json'
        @{ ts=(Get-Date).ToUniversalTime().ToString('o'); node=$node; rc=$code } |
            ConvertTo-Json -Compress | Set-Content -LiteralPath $marker -Encoding ascii
        Write-Log "auth failed rc=$code - stopping, not retrying"
        exit 1
    }
    # anything else: exponential backoff 30,60,120,300 (cap)

## Cooldown on startup (required, or the 5-minute trigger re-hammers)

    # at start, before connecting
    $m = Join-Path $myRes 'auth-failure.json'
    if (Test-Path -LiteralPath $m) {
        if (((Get-Date) - (Get-Item -LiteralPath $m).LastWriteTime).TotalMinutes -lt 15) {
            Write-Log 'auth cooldown active - exiting without attempting'
            exit 0
        }
    }

Four attempts per hour instead of twelve, which stays under a 10-attempt threshold.

## Also

Clear the marker after a successful connect, so a recovered worker does not sit in cooldown.

## Risk

Medium: a worker that hits a genuine transient auth blip now waits 15 minutes instead of retrying.
That is the intended trade - a locked account costs far more than a quarter hour.

## Revert

Restore the unconditional retry; delete the marker handling.


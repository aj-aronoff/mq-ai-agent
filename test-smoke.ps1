# ============================================================
# test-smoke.ps1
# Smoke test for the MQ AI Agent demo pipeline.
# Validates the post-run state of QMS1, tickets, and data.
#
# Usage:
#   .\test-smoke.ps1             # run after .\run-all.ps1
#
# Exit codes:
#   0 = all assertions passed
#   1 = one or more assertions failed
# ============================================================

$ErrorActionPreference = "Continue"

if ($PSScriptRoot -and $PSScriptRoot -ne "") {
    $ScriptDir = $PSScriptRoot
} else {
    $ScriptDir = (Get-Location).Path
}

$MQ_BIN   = "C:\Program Files\IBM\MQ\bin"
$QMGR     = "QMS1"
$PASS     = 0
$FAIL     = 0

function Assert-Pass { param([string]$Msg) Write-Host "  [PASS] $Msg"; $script:PASS++ }
function Assert-Fail { param([string]$Msg) Write-Host "  [FAIL] $Msg"; $script:FAIL++ }

function Assert-True {
    param([bool]$Condition, [string]$Msg)
    if ($Condition) { Assert-Pass $Msg } else { Assert-Fail $Msg }
}

function Get-QueueDepth {
    param([string]$Queue)
    $out = "DISPLAY QLOCAL($Queue) CURDEPTH`nEND" |
           & "$MQ_BIN\runmqsc.exe" $QMGR 2>&1 | Out-String
    if ($out -match 'CURDEPTH\((\d+)\)') { return [int]$Matches[1] }
    return -1
}

function Test-ValidJson {
    param([string]$Path)
    try {
        $null = Get-Content $Path -Raw | ConvertFrom-Json
        return $true
    } catch { return $false }
}

Write-Host ""
Write-Host "============================================================"
Write-Host "  MQ AI Agent -- Smoke Test"
Write-Host "============================================================"
Write-Host ""

# ---- 1. Queue manager running --------------------------------
Write-Host "[1] Queue Manager"
$dspmq = & "$MQ_BIN\dspmq.exe" 2>&1 | Out-String
Assert-True ($dspmq -match "QMNAME\($QMGR\)") "QMS1 exists"
Assert-True ($dspmq -match "STATUS\(Running\)") "QMS1 is running"
Write-Host ""

# ---- 2. Queue depths -----------------------------------------
Write-Host "[2] Queue Depths"
$appdataDepth  = Get-QueueDepth "ACME.APPDATA.QUEUE"
$commerceDepth = Get-QueueDepth "ACME.COMMERCE.QUEUE"
Assert-True ($appdataDepth -eq 850)  "ACME.APPDATA.QUEUE  CURDEPTH = 850  (got $appdataDepth)"
Assert-True ($commerceDepth -eq 3200) "ACME.COMMERCE.QUEUE CURDEPTH = 3200 (got $commerceDepth)"
Write-Host ""

# ---- 3. All ten queues defined --------------------------------
Write-Host "[3] Queue Definitions"
$queues = @(
    "ACME.APPDATA.QUEUE", "ACME.COMMERCE.QUEUE", "ACME.ALERTS.QUEUE",
    "ACME.ANALYTICS.QUEUE", "ACME.ARCHIVE.QUEUE", "ACME.AUDIT.QUEUE",
    "ACME.BACKUP.QUEUE", "ACME.CACHE.QUEUE", "ACME.CUSTOMER.QUEUE",
    "ACME.EVENTS.QUEUE"
)
$allQueues = "DISPLAY QLOCAL(*)`nEND" | & "$MQ_BIN\runmqsc.exe" $QMGR 2>&1 | Out-String
foreach ($q in $queues) {
    Assert-True ($allQueues -match [regex]::Escape($q)) "$q defined"
}
Write-Host ""

# ---- 4. MAXDEPTH values --------------------------------------
Write-Host "[4] MAXDEPTH Values"
$appMax = "DISPLAY QLOCAL(ACME.APPDATA.QUEUE) MAXDEPTH`nEND" |
           & "$MQ_BIN\runmqsc.exe" $QMGR 2>&1 | Out-String
$comMax = "DISPLAY QLOCAL(ACME.COMMERCE.QUEUE) MAXDEPTH`nEND" |
           & "$MQ_BIN\runmqsc.exe" $QMGR 2>&1 | Out-String
Assert-True ($appMax  -match 'MAXDEPTH\(1000\)') "ACME.APPDATA.QUEUE  MAXDEPTH = 1000"
Assert-True ($comMax  -match 'MAXDEPTH\(4000\)') "ACME.COMMERCE.QUEUE MAXDEPTH = 4000"
Write-Host ""

# ---- 5. Ticket files exist and are valid JSON ----------------
Write-Host "[5] Ticket Files"
$ticketDir = "$ScriptDir\tickets"
$expectedTickets = @(
    "ticket-ACME.APPDATA.QUEUE.json",
    "ticket-ACME.COMMERCE.QUEUE.json"
)
foreach ($t in $expectedTickets) {
    $path = "$ticketDir\$t"
    Assert-True (Test-Path $path) "$t exists"
    if (Test-Path $path) {
        Assert-True (Test-ValidJson $path) "$t is valid JSON"
    }
}
Write-Host ""

# ---- 6. diagnostic_instruction present in every ticket -------
Write-Host "[6] diagnostic_instruction Field"
Get-ChildItem "$ticketDir\ticket-*.json" -ErrorAction SilentlyContinue | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    Assert-True ($content -match '"diagnostic_instruction"') "$($_.Name) has diagnostic_instruction"
    Assert-True ($content -match '"remediation_status"') "$($_.Name) has remediation_status"
}
Write-Host ""

# ---- 7. Audit stub files exist --------------------------------
Write-Host "[7] Audit Stub Files"
Get-ChildItem "$ticketDir\ticket-*.json" -ErrorAction SilentlyContinue | ForEach-Object {
    $base = $_.BaseName -replace '^ticket-', ''
    $auditPath = "$ticketDir\audit-${base}.json"
    Assert-True (Test-Path $auditPath) "audit-${base}.json exists"
    if (Test-Path $auditPath) {
        Assert-True (Test-ValidJson $auditPath) "audit-${base}.json is valid JSON"
    }
}
Write-Host ""

# ---- 8. Seed data files exist --------------------------------
Write-Host "[8] Seed Data Files"
$dataDir = "$ScriptDir\data"
Assert-True (Test-Path "$dataDir\ACME.APPDATA.QUEUE.txt")  "ACME.APPDATA.QUEUE.txt exists"
Assert-True (Test-Path "$dataDir\ACME.COMMERCE.QUEUE.txt") "ACME.COMMERCE.QUEUE.txt exists"
if (Test-Path "$dataDir\ACME.APPDATA.QUEUE.txt") {
    $lines = (Get-Content "$dataDir\ACME.APPDATA.QUEUE.txt").Count
    Assert-True ($lines -eq 850)  "ACME.APPDATA.QUEUE.txt has 850 lines (1 per message)"
}
if (Test-Path "$dataDir\ACME.COMMERCE.QUEUE.txt") {
    $lines = (Get-Content "$dataDir\ACME.COMMERCE.QUEUE.txt").Count
    Assert-True ($lines -eq 3200) "ACME.COMMERCE.QUEUE.txt has 3200 lines (1 per message)"
}
Write-Host ""

# ---- 9. MQ-Ops mode file exists ------------------------------
Write-Host "[9] MQ-Ops Mode"
Assert-True (Test-Path "$ScriptDir\.bob\custom_modes.yaml") ".bob/custom_modes.yaml exists"
Assert-True (Test-Path "$ScriptDir\.bob\rules-mq-ops\01-evaluate-diagnosis.md") "Rule 1 exists"
Assert-True (Test-Path "$ScriptDir\.bob\rules-mq-ops\02-pros-cons-advisory.md") "Rule 2 exists"
Assert-True (Test-Path "$ScriptDir\.bob\rules-mq-ops\03-reversibility.md")      "Rule 3 exists"
Assert-True (Test-Path "$ScriptDir\.bob\rules-mq-ops\04-validation-plan.md")    "Rule 4 exists"
Write-Host ""

# ---- Summary -------------------------------------------------
Write-Host "============================================================"
$total = $PASS + $FAIL
Write-Host "  Results: $PASS passed, $FAIL failed ($total total)"
Write-Host "============================================================"
Write-Host ""

if ($FAIL -gt 0) {
    Write-Host "[HINT] If queue depths are 0: run .\run-all.ps1 first (or clear queues and re-run)."
    Write-Host "[HINT] If ticket files missing: run wsl -- bash ./03-scan-queues.sh"
    Write-Host "[HINT] If audit stubs missing:  run wsl -- bash ./04-enhance-tickets.sh"
    Write-Host ""
    exit 1
}

exit 0
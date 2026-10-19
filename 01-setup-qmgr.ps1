# ============================================================
# 01-setup-qmgr.ps1
# Creates QMS1 queue manager (if needed), starts it and its
# listener on port 1414, then applies qms1-setup.mqsc.
# DEFINE ... REPLACE is safe to re-run: it updates queue
# attributes without touching messages already on the queue.
# Run from PowerShell with Administrator privileges.
# ============================================================

$ErrorActionPreference = "Stop"

$QMGR    = "QMS1"
$MQ_BIN  = "C:\Program Files\IBM\MQ\bin"

if ($PSScriptRoot -and $PSScriptRoot -ne "") {
    $ScriptDir = $PSScriptRoot
} else {
    $ScriptDir = (Get-Location).Path
}
$MQSC_FILE = Join-Path $ScriptDir "qms1-setup.mqsc"

Write-Host ""
Write-Host "============================================================"
Write-Host "  MQ Demo Setup"
Write-Host "============================================================"
Write-Host "[INFO] MQ bin  : $MQ_BIN"
Write-Host "[INFO] Script  : $ScriptDir"
Write-Host "[INFO] MQSC    : $MQSC_FILE"
Write-Host "[INFO] QMGR    : $QMGR"
Write-Host ""

# ---- Sanity checks ------------------------------------------
if (-not (Test-Path (Join-Path $MQ_BIN "crtmqm.exe"))) {
    Write-Host "[ERROR] crtmqm.exe not found in $MQ_BIN"
    Write-Host "        Check that IBM MQ is installed and MQ_BIN is correct."
    exit 1
}
if (-not (Test-Path $MQSC_FILE)) {
    Write-Host "[ERROR] MQSC file not found: $MQSC_FILE"
    Write-Host "        Make sure qms1-setup.mqsc is in the same folder as this script."
    exit 1
}
Write-Host "[OK]   Sanity checks passed."
Write-Host ""

# ---- Helper: run an MQ exe, show output, return exit code ---
function Invoke-MQExe {
    param(
        [string]$Exe,
        [string[]]$Arguments
    )
    $fullPath = Join-Path $MQ_BIN $Exe
    Write-Host "       > $Exe $Arguments"
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $output = & $fullPath @Arguments 2>&1
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $prev
    foreach ($line in $output) { Write-Host "         $line" }
    return $rc
}

# ---- Step 1: Create queue manager ---------------------------
Write-Host "[STEP 1] Checking for existing queue manager $QMGR ..."

$ErrorActionPreference = "Continue"
$dspmqLines = & (Join-Path $MQ_BIN "dspmq.exe") 2>&1
$ErrorActionPreference = "Stop"

$dspmqText = ($dspmqLines | ForEach-Object { "$_" }) -join "`n"
Write-Host "         dspmq output: $dspmqText"

$escapedPattern = [regex]::Escape("QMNAME($QMGR)")
if ($dspmqText -match $escapedPattern) {
    Write-Host "[INFO]   $QMGR already exists - skipping crtmqm."
} else {
    Write-Host "[INFO]   $QMGR not found - creating ..."
    $rc = Invoke-MQExe "crtmqm.exe" @($QMGR)
    if ($rc -ne 0) {
        Write-Host "[ERROR]  crtmqm exited with code $rc"
        exit 1
    }
    Write-Host "[OK]     Queue manager $QMGR created."
}
Write-Host ""

# ---- Step 2: Start queue manager ----------------------------
Write-Host "[STEP 2] Starting queue manager $QMGR ..."
$rc = Invoke-MQExe "strmqm.exe" @($QMGR)
if ($rc -eq 0) {
    Write-Host "[OK]     $QMGR started."
} elseif ($rc -eq 5 -or $rc -eq 119) {
    Write-Host "[INFO]   $QMGR is already running (rc=$rc) - continuing."
} else {
    Write-Host "[ERROR]  strmqm exited with code $rc"
    exit 1
}
Write-Host ""

# ---- Step 3: Start listener on port 1414 --------------------
Write-Host "[STEP 3] Starting TCP listener on port 1414 ..."
$lsnrFile = Join-Path $env:TEMP "mq-listener.mqsc"
Set-Content -Path $lsnrFile -Value "DEFINE LISTENER(LISTENER.TCP) TRPTYPE(TCP) PORT(1414) REPLACE" -Encoding ASCII
Add-Content -Path $lsnrFile -Value "START LISTENER(LISTENER.TCP)" -Encoding ASCII
Add-Content -Path $lsnrFile -Value "END" -Encoding ASCII

$ErrorActionPreference = "Continue"
$lsnrOut = Get-Content $lsnrFile | & (Join-Path $MQ_BIN "runmqsc.exe") $QMGR 2>&1
$lsnrRc  = $LASTEXITCODE
$ErrorActionPreference = "Stop"

foreach ($line in $lsnrOut) { Write-Host "         $line" }
# RC 10 = warnings only (e.g. listener already active) - not a failure
if ($lsnrRc -eq 0 -or $lsnrRc -eq 10) {
    Write-Host "[OK]     Listener step complete."
} else {
    Write-Host "[ERROR]  runmqsc exited $lsnrRc for listener step"
    exit 1
}
Write-Host ""

# ---- Step 4: Apply queue definitions ------------------------
Write-Host "[STEP 4] Applying queue definitions from qms1-setup.mqsc ..."
Write-Host "         (DEFINE ... REPLACE preserves existing messages)"

$ErrorActionPreference = "Continue"
$mqscOut = Get-Content $MQSC_FILE | & (Join-Path $MQ_BIN "runmqsc.exe") $QMGR 2>&1
$mqscRc  = $LASTEXITCODE
$ErrorActionPreference = "Stop"

foreach ($line in $mqscOut) { Write-Host "         $line" }
if ($mqscRc -ne 0) {
    Write-Host "[WARN]   runmqsc exited $mqscRc for queue definitions - check output above."
} else {
    Write-Host "[OK]     Queue definitions applied."
}
Write-Host ""

# ---- Verify -----------------------------------------------
Write-Host "[VERIFY] Queue manager status:"
$ErrorActionPreference = "Continue"
& (Join-Path $MQ_BIN "dspmq.exe") 2>&1 | ForEach-Object { Write-Host "         $_" }
$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "============================================================"
Write-Host "  [DONE] $QMGR is ready."
Write-Host "  Next step:  wsl -- bash ./02-load-messages.sh"
Write-Host "============================================================"
Write-Host ""
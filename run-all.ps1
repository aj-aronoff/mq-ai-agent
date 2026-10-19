# ============================================================
# run-all.ps1
# Master script: runs all four demo steps in order.
# Run from PowerShell with Administrator privileges.
#
# Usage:
#   .\run-all.ps1            # steps 1-4 only (setup, load, scan, enhance)
#   .\run-all.ps1 --auto     # steps 1-4 PLUS for each ticket:
#                            #   - invoke Bob (MQ-Ops mode) for diagnosis
#                            #   - record the response in the audit file
#                            #   - show proposed MQSC and ask for approval
#                            #   - execute if approved
# ============================================================

$ErrorActionPreference = "Stop"

# ---- Parse flags --------------------------------------------
$AutoMode = $args -contains "--auto"

if ($PSScriptRoot -and $PSScriptRoot -ne "") {
    $ScriptDir = $PSScriptRoot
} else {
    $ScriptDir = (Get-Location).Path
}

# Convert Windows path to WSL path (C:\foo\bar -> /mnt/c/foo/bar)
function To-WslPath {
    param([string]$WinPath)
    $p = $WinPath -replace '\\', '/'
    if ($p -match '^([A-Za-z]):(.*)') {
        return '/mnt/' + $Matches[1].ToLower() + $Matches[2]
    }
    return $p
}

$WslScriptDir = To-WslPath $ScriptDir

function Banner {
    param([string]$Msg)
    Write-Host ""
    Write-Host ("=" * 60)
    Write-Host "  $Msg"
    Write-Host ("=" * 60)
}

function Run-WslScript {
    param([string]$Script, [string[]]$ScriptArgs = @())
    $wslPath = "$WslScriptDir/$Script"
    $argStr = $ScriptArgs -join " "
    Write-Host "[RUN] wsl bash $wslPath $argStr"
    if ($ScriptArgs.Count -gt 0) {
        wsl -- bash "$wslPath" @ScriptArgs
    } else {
        wsl -- bash "$wslPath"
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] $Script failed with exit code $LASTEXITCODE"
        exit 1
    }
}

# ---- Step 1: Setup queue manager ----------------------------
Banner "STEP 1 - Setup queue manager QMS1"
& "$ScriptDir\01-setup-qmgr.ps1"
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Step 1 failed."
    exit 1
}

# ---- Step 2: Load messages ----------------------------------
Banner "STEP 2 - Load messages onto ACME queues"
Run-WslScript "02-load-messages.sh"

# ---- Step 3: Scan queues ------------------------------------
Banner "STEP 3 - Scan queues and generate tickets"
Run-WslScript "03-scan-queues.sh"

# ---- Step 4: Enhance tickets --------------------------------
Banner "STEP 4 - Enhance tickets with diagnostic instruction"
Run-WslScript "04-enhance-tickets.sh"

# ---- Steps 5-7: Auto diagnosis and remediation (--auto only) ---
if ($AutoMode) {

    Banner "AUTO MODE - Diagnosing all tickets via Bob (MQ-Ops)"

    # Check bob is available
    $BobAvailable = $null
    try {
        $BobAvailable = Get-Command "bob" -ErrorAction SilentlyContinue
    } catch {}

    if (-not $BobAvailable) {
        Write-Host "[ERROR] 'bob' command not found. Install BobShell and authenticate first."
        Write-Host "        See: https://bob.ibm.com/docs/shell/getting-started/install-and-setup"
        exit 1
    }

    # Find all enhanced ticket files
    $TicketFiles = Get-ChildItem "$ScriptDir\tickets" -Filter "ticket-*.json" -ErrorAction SilentlyContinue
    if (-not $TicketFiles -or $TicketFiles.Count -eq 0) {
        Write-Host "[WARN] No ticket files found in $ScriptDir\tickets\ - nothing to diagnose."
    }

    foreach ($TicketFile in $TicketFiles) {
        $TicketPath = $TicketFile.FullName
        $WslTicketPath = To-WslPath $TicketPath

        # Read diagnostic_instruction from ticket
        $TicketJson = Get-Content $TicketPath -Raw
        $Instruction = ""
        if ($TicketJson -match '"diagnostic_instruction"\s*:\s*"([^"]+)"') {
            $Instruction = $Matches[1]
        }

        if (-not $Instruction) {
            Write-Host "[WARN] No diagnostic_instruction in $($TicketFile.Name) - skipping."
            continue
        }

        # ---- Step 5: Invoke Bob non-interactively ---------------
        Banner "STEP 5 - Diagnose: $Instruction"

        $ResponseFile = "$ScriptDir\tickets\bob-response-$($TicketFile.BaseName -replace 'ticket-','').txt"
        Write-Host "[INFO] Invoking Bob (MQ-Ops mode) ..."
        Write-Host "       Instruction: $Instruction"
        Write-Host "       Response -> : $ResponseFile"
        Write-Host ""

        # Build the full prompt with ticket context
        $TicketContext = $TicketJson -replace '"', '\"'
        $Prompt = "$Instruction`n`nTicket context:`n$TicketJson"

        # Run Bob non-interactively; capture output to response file
        $ErrorActionPreference = "Continue"
        bob --chat-mode=mq-ops -p "$Prompt" > "$ResponseFile" 2>&1
        $BobRc = $LASTEXITCODE
        $ErrorActionPreference = "Stop"

        if ($BobRc -ne 0 -or -not (Test-Path $ResponseFile) -or (Get-Item $ResponseFile).Length -eq 0) {
            Write-Host "[ERROR] Bob invocation failed (exit $BobRc) or produced no output."
            Write-Host "        Check BobShell authentication: bob --version"
            exit 1
        }

        Write-Host ""
        Write-Host "--- Bob Diagnosis ---"
        Get-Content $ResponseFile
        Write-Host "--- End Diagnosis ---"
        Write-Host ""

        # ---- Step 6: Record diagnosis in audit file -------------
        Banner "STEP 6 - Record diagnosis audit for $($TicketFile.Name)"
        $WslResponsePath = To-WslPath $ResponseFile
        Run-WslScript "04b-record-diagnosis.sh" @($WslTicketPath, $WslResponsePath)

        # ---- Step 7: Remediate (with human approval gate) -------
        Banner "STEP 7 - Remediation advisory for $($TicketFile.Name)"
        Write-Host "[INFO] Reviewing MQSC remediation options..."
        Write-Host "       You will be shown proposed commands and asked to approve."
        Write-Host ""

        # 05-remediate.sh needs interactive stdin for the y/N prompt
        # Pass it through WSL directly so the user can type
        $wslTicket = To-WslPath $TicketPath
        wsl -- bash "$WslScriptDir/05-remediate.sh" "$wslTicket"
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[WARN] Remediation step exited with code $LASTEXITCODE for $($TicketFile.Name)"
        }
    }

    Banner "AUTO MODE COMPLETE"
    Write-Host ""
    Write-Host "Results:"
    Write-Host "  Tickets    : $ScriptDir\tickets\ticket-*.json"
    Write-Host "  Audit logs : $ScriptDir\tickets\audit-*.json"
    Write-Host "  Bob resp.  : $ScriptDir\tickets\bob-response-*.txt"
    Write-Host "  MQSC files : $ScriptDir\tickets\remediation-*.mqsc"
    Write-Host ""

} else {

    Banner "ALL STEPS COMPLETE"
    Write-Host ""
    Write-Host "Tickets are in   : $ScriptDir\tickets\"
    Write-Host "Audit stubs in   : $ScriptDir\tickets\audit-*.json"
    Write-Host "Seed data is in  : $ScriptDir\data\"
    Write-Host ""
    Write-Host "MANUAL DIAGNOSIS (default mode):"
    Write-Host "  1. Paste a diagnostic_instruction into Bob (use MQ-Ops mode):"
    Write-Host "       Diagnose ACME.COMMERCE.QUEUE on QMS1"
    Write-Host "  2. Save Bob's response to a .txt file, then record it:"
    Write-Host "       wsl -- bash ./04b-record-diagnosis.sh tickets/ticket-ACME.COMMERCE.QUEUE.json response.txt"
    Write-Host "  3. Run remediation (shows commands, asks for approval):"
    Write-Host "       wsl -- bash ./05-remediate.sh tickets/ticket-ACME.COMMERCE.QUEUE.json"
    Write-Host ""
    Write-Host "AUTOMATED DIAGNOSIS (re-run with --auto flag):"
    Write-Host "  .\run-all.ps1 --auto"
    Write-Host "  Bob is invoked automatically for each ticket in MQ-Ops mode."
    Write-Host ""
}
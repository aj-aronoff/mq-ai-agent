# MQ AI Agent — Local Demo Environment

A local replica of the ACME queue environment for demoing the IBM MQ AI ticket-triage agent.

---

## Prerequisites

- Windows 11 with IBM MQ 10.x installed (`C:\Program Files\IBM\MQ`)
- WSL (Windows Subsystem for Linux) installed
- PowerShell run as **Administrator** for script 1

---

## Files

### Demo pipeline

| File | Purpose |
|------|---------|
| `qms1-setup.mqsc` | MQSC commands that define all ten ACME queues |
| `01-setup-qmgr.ps1` | Creates QMS1, starts it and its listener, applies the MQSC |
| `02-load-messages.sh` | Loads realistic JSON messages onto the two busy queues |
| `03-scan-queues.sh` | Scans QMS1 and writes a JSON ticket per problem queue |
| `04-enhance-tickets.sh` | Adds `diagnostic_instruction` to each ticket and writes an audit stub |
| `04b-record-diagnosis.sh` | Fills the audit stub with the Bob response after diagnosis |
| `05-remediate.sh` | Extracts MQSC commands from an audit file, prompts for approval, executes |
| `run-all.ps1` | Master script — runs all four steps in order |
| `test-smoke.ps1` | Smoke test — validates QMS1 state, queue depths, ticket files, and audit stubs after a full run |

### Supporting files

| File | Purpose |
|------|---------|
| `hackathon-evaluation.md` | Draft hackathon evaluation notes |
| `hackathon-evaluation-official.md` | Official hackathon evaluation write-up |
| `mq-ai-agent-improvement-plan.md` | Approved improvement plan (audit logging + MQSC remediation) |
| `MQ-AI-Agent-Ticket-Pipeline.pptx` | Full-length slide deck for the ticket pipeline demo |
| `MQ-AI-Agent-Ticket-Pipeline-3min.pptx` | 3-minute lightning version of the slide deck |
| `Mq-ai-agent-diagnose-ACME.APPDATA.QUEUE` | Saved Bob diagnosis session for ACME.APPDATA.QUEUE |
| `Mq-ai-agent-diagnose-ACME.COMMERCE.QUEUE` | Saved Bob diagnosis session for ACME.COMMERCE.QUEUE |
| `prompt-build-mq-demo.txt` | Prompt used to scaffold the demo environment |
| `prompt-history.md` | Log of prompts used during development |
| `notes.md` | Miscellaneous project notes |

---

## Demo run order

Run these **one at a time** so you can narrate each step, or use `run-all.ps1` to do it all at once.

### Step 1 — Create the queue manager and queues
```powershell
# Run PowerShell as Administrator
.\01-setup-qmgr.ps1
```
Creates QMS1 (safe to re-run), starts the queue manager and TCP listener on port 1414, and defines all ten `ACME.*` queues.

---

### Step 2 — Load messages
```powershell
wsl -- bash ./02-load-messages.sh
```
Puts **850 messages** on `ACME.APPDATA.QUEUE` (max depth 1 000) and **3 200 messages** on `ACME.COMMERCE.QUEUE` (max depth 4 000). Each message is a small JSON payload that looks like real application traffic.

To load a custom queue or count:
```bash
./02-load-messages.sh ACME.ALERTS.QUEUE 50
```

---

### Step 3 — Scan queues and generate tickets
```powershell
wsl -- bash ./03-scan-queues.sh
```
Walks every local queue on QMS1 (skipping `SYSTEM.*`). Any queue with messages sitting on it but no active reader gets a JSON ticket written to `./tickets/`. Console shows a one-line summary per problem queue with severity.

**Severity thresholds:**

| Severity | Condition |
|----------|-----------|
| LOW | < 10 % full |
| MEDIUM | 10 – 80 % full |
| HIGH | > 80 % full |

---

### Step 4 — Enhance tickets
```powershell
wsl -- bash ./04-enhance-tickets.sh
```
Reads each ticket from `./tickets/` and adds:
```json
"diagnostic_instruction": "Diagnose ACME.COMMERCE.QUEUE on QMS1"
```
This is the exact string the MQ AI Agent parses to begin its diagnosis.

This step also writes a stub audit file alongside each ticket:
```
tickets/audit-ACME.COMMERCE.QUEUE.json
```

To enhance a single ticket:
```bash
./04-enhance-tickets.sh tickets/ticket-ACME.COMMERCE.QUEUE.json
```

---

### Step 4b — Record Bob's diagnosis (audit logging)

After handing the `diagnostic_instruction` to Bob and receiving a diagnosis, save the response to a plain-text file and run:

```powershell
wsl -- bash ./04b-record-diagnosis.sh tickets/ticket-ACME.COMMERCE.QUEUE.json response.txt
```

This fills the audit stub with the timestamp and Bob's response text, producing a completed audit record.

#### Audit file schema

| Field | Type | Description |
|-------|------|-------------|
| `audit_version` | string | Schema version (`"1.0"`) |
| `ticket_id` | string | Ticket ID from the source ticket |
| `queue_name` | string | Queue that was diagnosed |
| `queue_manager` | string | Queue manager name |
| `diagnostic_instruction` | string | Instruction sent to the AI agent |
| `session_source` | string | How the session was run (`"IDE"`) |
| `diagnosis_timestamp` | string \| null | ISO 8601 UTC timestamp set at record time |
| `bob_response` | string \| null | Full text of Bob's diagnosis response |

#### Example completed audit record

```json
{
  "audit_version": "1.0",
  "ticket_id": "TKT-20261017002034-ACME.COMMERCE.QUEUE",
  "queue_name": "ACME.COMMERCE.QUEUE",
  "queue_manager": "QMS1",
  "diagnostic_instruction": "Diagnose ACME.COMMERCE.QUEUE on QMS1",
  "session_source": "IDE",
  "diagnosis_timestamp": "2026-10-17T10:35:00Z",
  "bob_response": "Queue ACME.COMMERCE.QUEUE on QMS1 is at 80% depth..."
}
```

---

### Step 5 (optional) — Remediate

After recording a Bob diagnosis with `04b-record-diagnosis.sh`, run:

```powershell
wsl -- bash ./05-remediate.sh tickets/ticket-ACME.APPDATA.QUEUE.json
```

The script:
1. Reads `bob_response` from the corresponding `audit-<QUEUE>.json`
2. Extracts lines that begin with a known MQSC verb (`ALTER`, `CLEAR`, `START`, `STOP`, `DEFINE`, `REFRESH`, `RESET`, `DISPLAY`)
3. Writes them to `tickets/remediation-<QUEUE>.mqsc` and displays the file
4. Prompts `Approve and execute? [y/N]:` — **default is NO**; only exact lowercase `y` proceeds
5. On approval: runs `runmqsc.exe QMS1 < remediation-<QUEUE>.mqsc`, updates the ticket `remediation_status` to `APPLIED`, and records `remediation_timestamp` + `remediation_outcome` in the audit file
6. On rejection: sets ticket `remediation_status` to `REJECTED` and exits without touching QMS1

Example output (approval path):

```
============================================================
  Proposed MQSC remediation for ACME.APPDATA.QUEUE
============================================================

ALTER QLOCAL(ACME.APPDATA.QUEUE) GET(ENABLED)
END

  File: tickets/remediation-ACME.APPDATA.QUEUE.mqsc
============================================================

Approve and execute? [y/N]: y

[OK] Remediation applied to QMS1 at 2026-10-17T10:40:00Z
     Ticket  : tickets/ticket-ACME.APPDATA.QUEUE.json
     Audit   : tickets/audit-ACME.APPDATA.QUEUE.json
     MQSC    : tickets/remediation-ACME.APPDATA.QUEUE.mqsc
```

If no MQSC commands are found in the diagnosis, the script prints `[INFO] No MQSC commands found in diagnosis - nothing to remediate.` and exits cleanly.

---

## Run everything at once

```powershell
# PowerShell as Administrator
.\run-all.ps1
```

---

## Output

| Directory | Contents |
|-----------|---------|
| `tickets/` | One `ticket-<QUEUE>.json` per problem queue |
| `tickets/` | One `audit-<QUEUE>.json` stub per enhanced ticket (completed after diagnosis) |
| `tickets/` | One `remediation-<QUEUE>.mqsc` per remediated queue (created by Step 5) |
| `data/` | Seed `.jsonl` files (one per loaded queue) for reference |

---

## Example enhanced ticket

```json
{
  "ticket_id": "TKT-20250101120000-ACME.COMMERCE.QUEUE",
  "queue_manager": "QMS1",
  "queue_name": "ACME.COMMERCE.QUEUE",
  "scan_time": "2025-01-01T12:00:00Z",
  "current_depth": 3200,
  "max_depth": 4000,
  "percent_full": 80,
  "open_input_count": 0,
  "open_output_count": 0,
  "severity": "MEDIUM",
  "status": "OPEN",
  "remediation_status": "PENDING",
  "remediation_mqsc": null,
  "diagnostic_instruction": "Diagnose ACME.COMMERCE.QUEUE on QMS1"
}
```

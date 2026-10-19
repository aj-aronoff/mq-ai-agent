# MQ AI Agent — Ticket Pipeline

## Project Description

An automated MQ monitoring pipeline that detects silent queues, generates structured tickets, and enhances them with exact diagnostic instructions for the IBM MQ AI Agent. When a queue has messages but no consumer, the system creates a ticket, enriches it, and passes it to the live MQ AI Agent for diagnosis. The agent returns actionable recommendations — including MQSC remediation commands — while keeping humans in control of every change. Built entirely with IBM Bob on Windows 11 + WSL.

---

## Team

**IBM MQ Simulation Lab for common Problems**

---

## Track

**Theme 2: Experienced Developers — Modernize What Matters**

---

## Tech Stack

- IBM MQ 10.x (Windows)
- IBM MQ AI Agent (live, early access via IBM)
- IBM Bob (AI coding assistant — scripted the entire pipeline)
- PowerShell + Bash (WSL)
- JSON ticket format
- MQSC

---

## Improvements Made

Built on the base IBM MQ local queue manager setup. Key improvements added during the hackathon:

1. **Automated ticket pipeline** — scan, generate, and enhance tickets in one pass (`run-all.ps1`)
2. **Audit logging** (`04b-record-diagnosis.sh`) — records the MQ AI Agent's full diagnosis response alongside each ticket with a timestamp
3. **MQSC remediation script** (`05-remediate.sh`) — extracts MQSC commands from the diagnosis, presents them for human approval, and executes on confirmation
4. **Smoke test** (`test-smoke.ps1`) — validates the full post-run state of QMS1, queue depths, ticket files, and audit stubs

---

## Demo Videos

| Video | Description |
|-------|-------------|
| `2026-10-09 21-06-57 complete.mp4` | Full demo — queue manager setup, ticket pipeline, live MQ AI Agent diagnosis |
| `File-2026-10-09 18-04-36 3 minutes.txt` | 3-minute pitch video transcript |
| `File-2026-10-09 21-06-57 complete.txt` | Full demo video transcript |

> Both videos are pre-recorded. The 3-minute version is the official hackathon submission video.

---

## Pitch Deck

| File | Description |
|------|-------------|
| `MQ-AI-Agent-Ticket-Pipeline.pdf` | Full pitch deck (PDF) |
| `MQ-AI-Agent-Ticket-Pipeline-3min.pdf` | 3-minute lightning version (PDF) |
| `MQ-AI-Agent-Ticket-Pipeline.pptx` | Full pitch deck (editable PowerPoint) |
| `MQ-AI-Agent-Ticket-Pipeline-3min.pptx` | 3-minute lightning version (editable PowerPoint) |

---

## Prerequisites

- Windows 11 with IBM MQ 10.x installed (`C:\Program Files\IBM\MQ`)
- WSL (Windows Subsystem for Linux) installed
- PowerShell run as **Administrator** for script 1
- Access to the **IBM MQ AI Agent** — this is an early-access IBM product; Steps 4b and 5 require a live agent session and cannot be run without it. Contact IBM to request access.

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
| `run-all.ps1` | Master script — runs all five steps in order |
| `test-smoke.ps1` | Smoke test — validates QMS1 state, queue depths, ticket files, and audit stubs |

### Supporting files

| File | Purpose |
|------|---------|
| `MQ-AI-Agent-Ticket-Pipeline.pdf` | Full pitch deck (PDF) |
| `MQ-AI-Agent-Ticket-Pipeline-3min.pdf` | 3-minute pitch deck (PDF) |
| `MQ-AI-Agent-Ticket-Pipeline.pptx` | Full pitch deck (PowerPoint) |
| `MQ-AI-Agent-Ticket-Pipeline-3min.pptx` | 3-minute pitch deck (PowerPoint) |
| `2026-10-09 21-06-57 complete.mp4` | Full demo video |
| `File-2026-10-09 18-04-36 3 minutes.txt` | 3-minute video transcript |
| `File-2026-10-09 21-06-57 complete.txt` | Full demo video transcript |
| `hackathon-evaluation.md` | Draft hackathon evaluation notes |
| `hackathon-evaluation-official.md` | Official hackathon evaluation write-up |
| `mq-ai-agent-improvement-plan.md` | Approved improvement plan (audit logging + MQSC remediation) |
| `Mq-ai-agent-diagnose-ACME.APPDATA.QUEUE` | Saved Bob diagnosis session for ACME.APPDATA.QUEUE |
| `Mq-ai-agent-diagnose-ACME.COMMERCE.QUEUE` | Saved Bob diagnosis session for ACME.COMMERCE.QUEUE |
| `prompt-build-mq-demo.txt` | Prompt used to scaffold the demo environment |
| `prompt-history.md` | Log of prompts used during development |
| `notes.md` | Miscellaneous project notes |
| `Project-Description.txt` | Hackathon project description (≤100 words) |
| `.gitattributes` | Git line-ending rules (all files normalised to LF) |

---

## Running the Demo

Run these **one at a time** so you can narrate each step, or use `run-all.ps1` to do it all at once.

### Step 1 — Create the queue manager and queues

> **Requires PowerShell run as Administrator**

```powershell
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

Walks every local queue on QMS1 (skipping `SYSTEM.*`). Any queue with messages but no active reader gets a JSON ticket written to `./tickets/`. Console shows a one-line summary per problem queue with severity.

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

### Step 4b — Record the MQ AI Agent's diagnosis (audit logging)

After passing the `diagnostic_instruction` to the MQ AI Agent and receiving a diagnosis, save the response to a plain-text file and run:

```powershell
wsl -- bash ./04b-record-diagnosis.sh tickets/ticket-ACME.COMMERCE.QUEUE.json response.txt
```

This fills the audit stub with the timestamp and the agent's response text, producing a completed audit record.

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
| `bob_response` | string \| null | Full text of the agent's diagnosis response |

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

After recording a diagnosis with `04b-record-diagnosis.sh`, run:

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

## Testing

Run the smoke test after `run-all.ps1` to validate the full pipeline:

```powershell
.\test-smoke.ps1
```

The smoke test checks:

| # | Check |
|---|-------|
| 1 | QMS1 exists and is running |
| 2 | `ACME.APPDATA.QUEUE` depth = 850, `ACME.COMMERCE.QUEUE` depth = 3 200 |
| 3 | All ten `ACME.*` queues are defined |
| 4 | `ACME.APPDATA.QUEUE` MAXDEPTH = 1 000, `ACME.COMMERCE.QUEUE` MAXDEPTH = 4 000 |
| 5 | Ticket files exist and are valid JSON |
| 6 | Every ticket has `diagnostic_instruction` and `remediation_status` fields |
| 7 | Audit stub files exist and are valid JSON |
| 8 | Seed data files exist with the correct message counts |
| 9 | `.bob/custom_modes.yaml` and all four MQ-Ops rules files exist |

Exit code `0` = all assertions passed. Exit code `1` = one or more failures (hints printed to console).

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

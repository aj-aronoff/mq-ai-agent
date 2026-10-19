# Prompt History

---

## 2025 — Session 1

### Prompt 1
**File:** `prompt-build-mq-demo.txt`
**Summary:** Build a local IBM MQ demo environment with four independent scripts:
1. Create queue manager QMS1 and 10 ACME.* local queues (idempotent)
2. Load messages onto queues (850 → ACME.APPDATA.QUEUE, 3200 → ACME.COMMERCE.QUEUE)
3. Scan all non-SYSTEM, non-model/alias/remote queues and generate JSON tickets for queues with depth > 0 and no readers
4. Enhance tickets by adding a `Diagnose <queue> on <qmgr>` instruction field

Plus a master shell script to run all four, and a README with ordered demo steps.

### Clarifying Answers (Prompt 1)
- **Platform:** Windows 11 x64, IBM MQ 10.0.0.0 at `C:\Program Files\IBM\MQ`. Scripts run as Bash inside WSL (invoked from PowerShell).
- **Message format:** Small JSON payload. Demo video target is ≤ 3 minutes.
- **Severity thresholds:** LOW < 10%, MEDIUM 10–80%, HIGH > 80%.
- **Queue depths:** `ACME.APPDATA.QUEUE` MAXDEPTH=1000 (load 850 msgs), `ACME.COMMERCE.QUEUE` MAXDEPTH=4000 (load 3200 msgs).
- **Output dirs:** JSON tickets → `tickets/`, initial seed data → `data/`.



---

### Prompt 2 — Script debugging: 01-setup-qmgr.ps1 did not create queue manager
**User reported:** Running `.\01-setup-qmgr.ps1` failed silently — queue manager was not created.
**Investigation:** User ran `crtmqm QMS1` manually and it succeeded. Root causes identified:
- `2>$null` on `dspmq` suppressed errors silently
- `Select-String` on a mixed `String`/`ErrorRecord` array missed the match
- `Write-Error` under `$ErrorActionPreference = "Stop"` threw opaque terminating errors
- `strmqm` returns RC 5 when already running, which was treated as failure
- `$ErrorActionPreference = "Stop"` around native `.exe` calls turned stderr into terminating errors

**Fix:** Script rewritten with explicit error handling, `[regex]::Escape()` for literal match, all native exe calls wrapped in `Continue`/`Stop` guards, RC 5 handled for `strmqm`.

---

### Prompt 3 — Parse errors in 01-setup-qmgr.ps1
**User reported:** PowerShell parse errors: `'define' keyword not supported`, `Unexpected token`, `missing terminator`.
**Root cause:** Em-dash characters in string literals were stored as corrupted multi-byte sequences. PowerShell's parser misread them as syntax, causing cascading failures.
**Fix:** File rewritten using `[System.IO.File]::WriteAllText` with explicit ASCII encoding. Listener MQSC moved to a temp file instead of a piped string.

---

### Prompt 4 — Full audit of all scripts
**User requested:** Check all scripts for issues.
**Issues found and fixed:**

| Script | Issues Fixed |
|--------|-------------|
| `02-load-messages.sh` | `amqsput` -> full WSL path `amqsput.exe`; fragile awk replaced with pure bash arithmetic; CRLF line endings fixed |
| `03-scan-queues.sh` | `runmqsc -e` flag removed; `extract()` moved out of loop; here-doc replaced with `printf`; em-dashes removed; CRLF fixed |
| `04-enhance-tickets.sh` | `sed \n` not portable on WSL - replaced with `head -n -1` + `printf`; em-dashes removed; CRLF fixed |
| `run-all.ps1` | `$PSScriptRoot` fallback added; `To-WslPath` helper converts `C:\foo` to `/mnt/c/foo`; `Write-Error` replaced with `Write-Host + exit 1` |

**Verification:** Both `.ps1` files pass PowerShell parser. All three `.sh` files pass `bash -n` with exit 0. All `.sh` files confirmed LF-only line endings.

---


### Prompt 5 — Switch message loader from amqsput to dmpmqmsg (attempt)
**User requested:** Replace `amqsput` with `dmpmqmsg`. User will clear the two queues manually first.
**Finding:** `dmpmqmsg.exe` is at `C:\Program Files\IBM\MQ\bin64\dmpmqmsg.exe` (not `bin`).
**Attempt:** Pre-generate plain text file, call `dmpmqmsg -o<QUEUE> -m<QMGR> -f<file> -dA -q`.
**Problem 1:** `dmpmqmsg.exe` is a Windows binary — cannot open WSL `/mnt/c/...` paths. Fixed with `to_win_path()` sed converter.
**Problem 2:** `-dA` is an output/display flag only — not valid for loading. `dmpmqmsg` load requires its own binary file format, not plain text.
**Resolution:** Reverted to `amqsput.exe` from `bin64` (not `bin`). Used `amqsput` with full file piped as stdin (all messages in one call using blank-line separators).

---

### Prompt 5b — SIGPIPE on large amqsput load
**User reported:** Exit code 141 (SIGPIPE) when loading 3200 messages in one `amqsput` call.
**Root cause:** `amqsput.exe` closes stdin before reading all input when the payload is large; `set -euo pipefail` caused abort.
**Fix:** Removed `set -euo pipefail`; split load into batches of 250 messages per `amqsput` call using temp files; check success by grepping for `AMQSPUT0 end` in output.

---

### Prompt 5c — DEFINE ... REPLACE idempotency confirmed
**User requested:** Use `REPLACE` on every MQSC line so the script is safe to re-run regardless.
**Concern:** Does `DEFINE QLOCAL ... REPLACE` wipe messages on an existing queue?
**Test:** Live test on QMS1 — ran `DEFINE QLOCAL(ACME.APPDATA.QUEUE) MAXDEPTH(1000) REPLACE` with 4 messages on the queue. CURDEPTH remained 4 after the command.
**Conclusion:** `REPLACE` updates queue attributes only; messages are preserved. `qms1-setup.mqsc` is fully idempotent and safe to run at any time.

---

### Prompt 5d — Seed file reuse optimisation
**User requested:** If seed files already exist in `data/`, skip generation and amqsput entirely.
**Implementation:** `load_queue()` checks for `data/<QUEUE>.txt`; validates line count (2 lines per message); if correct prints `[SKIP]` and loads from existing file; if wrong line count regenerates; if missing generates fresh.
**Result:** Re-runs skip generation entirely, going straight to batched loading.

---

### Prompt 6 — First end-to-end agent diagnosis
**User action:** Copied `diagnostic_instruction` from `ticket-ACME.COMMERCE.QUEUE.json` into the MQ AI Agent:
```
Diagnose ACME.COMMERCE.QUEUE on QMS1
```

**Agent diagnosis output (summary):**
- Current depth: 3200 (80% of MAXDEPTH 4000)
- QDPHIEV: DISABLED — no high-depth alert firing
- Oldest message age: ~4.4 days (382,893 seconds) — significant backlog
- All 3200 messages uncommitted — open transaction blocking consumers
- 1 input handler, 1 output handler — limited parallelism

**Key issues identified by agent:**
1. Queue at high-depth threshold with alerting disabled
2. Very old messages indicating a backlog
3. All messages in an uncommitted transaction
4. Only one producer and one consumer

**Recommended actions from agent:**
- Check producing app for hung syncpoint transaction
- Verify consuming app is committing GETs
- Resolve stuck transaction via DISPLAY TRANSACTION / rollback / CLEAR QLOCAL
- Enable QDPHIEV or lower QDEPTHHI
- Add more consumers
- Continue monitoring CURDEPTH, MSGAGE, UNCOM

**Status:** Demo end-to-end flow working. All four scripts ran successfully via `run-all.ps1`.

---

### Prompt 7 — Second end-to-end agent diagnosis
**User action:** Pasted `diagnostic_instruction` from `ticket-ACME.APPDATA.QUEUE.json` into the MQ AI Agent:
```
Diagnose ACME.APPDATA.QUEUE on QMS1
```

**Agent diagnosis output (summary):**
- Current depth: 850/1000 (85% — above QDEPTHHI=80 threshold)
- GET=DISABLED — no consumer can retrieve messages (IPPROCS=0)
- OPPROCS=0 — no active producers
- MONQ=OFF — runtime metrics not collected (MSGAGE=-1)
- QDPHIEV and QDPLOEV both DISABLED — no depth alerts firing
- UNCOM=0 — no uncommitted transaction (different from COMMERCE queue)

**Key issues identified by agent:**
1. GET disabled — administrative lock-out preventing consumers
2. No active producers or consumers
3. Monitoring and alerting both off

**Recommended actions from agent:**
- ALTER QLOCAL(ACME.APPDATA.QUEUE) GET(ENABLED)
- Start/reconnect consumer applications
- Enable MONQ and QDPHIEV

**Demo value:** Two distinct failure patterns demonstrated:
- COMMERCE: hung uncommitted transaction (application bug)
- APPDATA: GET=DISABLED with no readers (administrative issue)

---

### Prompt 8 -- Sub-Task 1: BobShell Audit Logging
**User requested:** Implement Sub-Task 1 from `mq-ai-agent-improvement-plan.md` -- BobShell Audit Logging.

**Changes made:**

| File | Change |
|------|--------|
| `04-enhance-tickets.sh` | Extended `enhance_ticket()` to write a stub `audit-<QUEUE>.json` alongside each ticket after adding the `diagnostic_instruction` field. Stub includes all schema fields with `diagnosis_timestamp: null` and `bob_response: null`. Also extracts `ticket_id` for inclusion in the audit stub. |
| `04b-record-diagnosis.sh` | New script. Accepts a ticket JSON file and a plain-text Bob response file. Derives the audit file path, reads the stub, fills in `diagnosis_timestamp` (current UTC ISO 8601) and `bob_response` (text escaped for JSON), and writes the completed audit record. No `set -euo pipefail` (not needed -- no Windows exe calls). |
| `run-all.ps1` | Completion banner updated to show `tickets/audit-*.json` path and the command to record a diagnosis with `04b-record-diagnosis.sh`. |
| `README.md` | Files table updated; Step 4 updated to mention audit stub output; new Step 4b section added with schema table, usage, and example completed audit record. Output table updated. |
| `prompt-history.md` | This entry. |
| `mq-ai-agent-improvement-plan.md` | Sub-Task 1 status updated to `[x] done`. |

**Conventions followed:**
- Both `.sh` files written via `[System.IO.File]::WriteAllText` with UTF-8 no-BOM encoding and LF-only line endings.
- All strings ASCII-safe (no em-dashes, smart quotes, or Unicode).
- Audit stub written with `printf` statements (same pattern as ticket field injection).
- `04b-record-diagnosis.sh` uses `grep -oP` to extract fields from the stub, `awk` + `sed` to escape the response for JSON embedding.
- Both `.sh` files pass `bash -n` syntax check.

---

---

### Prompt 9 -- Sub-Task 2: 05-remediate.sh MQSC Extraction and Execution
**User requested:** Implement Sub-Task 2 from `mq-ai-agent-improvement-plan.md` -- MQSC remediation script.

**Changes made:**

| File | Change |
|------|--------|
| `03-scan-queues.sh` | Added `"remediation_status": "PENDING"` and `"remediation_mqsc": null` as the last two fields before `}` in every ticket JSON it writes. Changed `"status": "OPEN"` line to have a trailing comma to support the new fields. |
| `05-remediate.sh` | New script. Accepts a ticket JSON file, derives the audit file path, reads `bob_response`, converts `\n` escape sequences back to real newlines, then greps for lines beginning with a known MQSC verb (ALTER, CLEAR, START, STOP, DEFINE, REFRESH, RESET, DISPLAY). If no commands found, exits cleanly. Otherwise writes `tickets/remediation-<QUEUE>.mqsc`, displays the file, and prompts `Approve and execute? [y/N]:` (default NO). On `y`: runs `runmqsc.exe QMS1`, updates ticket `remediation_status` to APPLIED and `remediation_mqsc` to the filename, appends `remediation_timestamp` and `remediation_outcome` to the audit file. On any other input: sets `remediation_status` to REJECTED and exits 0 without touching QMS1. |
| `run-all.ps1` | Completion banner extended with an "OPTIONAL: Remediation (Step 5)" block showing the `05-remediate.sh` command and a note that explicit `y` is required. |
| `README.md` | Files table updated with `05-remediate.sh` row; new Step 5 (optional) section added with description, numbered flow, and example output; Output table updated with `remediation-<QUEUE>.mqsc`; example enhanced ticket JSON updated to include `remediation_status` and `remediation_mqsc` fields. |
| `prompt-history.md` | This entry. |
| `mq-ai-agent-improvement-plan.md` | Sub-Task 2 status updated to `[x] done`. |

**Conventions followed:**
- `05-remediate.sh` written via `[System.IO.File]::WriteAllText` with UTF-8 no-BOM encoding and LF-only line endings.
- All strings ASCII-safe (no em-dashes, smart quotes, or Unicode).
- `bob_response` extraction uses `grep -oP` pattern matching the JSON string value; `printf '%b'` converts `\n` literal sequences to real newlines before grepping for MQSC verbs.
- Ticket field updates use `sed` in-place substitution (status transitions PENDING->APPLIED / PENDING->REJECTED).
- Audit file remediation fields appended using `head -n -1` + `sed` comma + `printf` (same pattern as `04-enhance-tickets.sh`).
- No `set -euo pipefail` (Windows `.exe` calls return non-zero on normal MQ responses).
- Human approval gate defaults to NO -- only exact lowercase `y` proceeds.
- Both `05-remediate.sh` and `03-scan-queues.sh` pass `bash -n` syntax check with LF-only line endings confirmed.

### Prompt 10 — MQ-Ops Custom Bob Mode
**User requested:** Create a custom Bob mode for MQ operations with four change-advisory rules.

**Files created:**
- `.bob/custom_modes.yaml` — `mq-ops` mode: slug, roleDefinition (IBM MQ SRE persona), customInstructions (5-section structured output), groups (read, execute, mcp, skill)
- `.bob/rules-mq-ops/01-evaluate-diagnosis.md` — Cross-check attributes, classify root cause, state confidence level before proceeding
- `.bob/rules-mq-ops/02-pros-cons-advisory.md` — Pros/cons per command with specific rules for ALTER GET, CLEAR QLOCAL, MAXDEPTH, START/STOP CHANNEL, QDPHIEV
- `.bob/rules-mq-ops/03-reversibility.md` — REVERSIBLE / PARTIALLY REVERSIBLE / IRREVERSIBLE classification with undo command for every proposed change
- `.bob/rules-mq-ops/04-validation-plan.md` — Immediate checks, short-term checks, failure indicators, rollback trigger and command for every change

**Mode behaviour:** Structures every response as: Summary / Issues Found / Change Advisory / MQSC Remediation Commands (fenced mqsc block) / Next Steps.

---

### Prompt 11 -- run-all.ps1 --auto flag
**User requested:** A flag on run-all.ps1 that runs the full automated loop: generate enhanced ticket, show diagnostics, record response, validate, and remediate -- only when the flag is passed.

**Implementation:** Added `--auto` switch to `run-all.ps1`.

**Default behaviour (no flag):** Steps 1-4 only. Banner shows manual diagnosis instructions.

**--auto behaviour:** Steps 1-4 then for each ticket-*.json in tickets/:
- Step 5: Invoke Bob non-interactively via `bob --chat-mode=mq-ops -p "<instruction + ticket context>"`, save response to `tickets/bob-response-<QUEUE>.txt`, display to console
- Step 6: Call `04b-record-diagnosis.sh` to write completed `audit-<QUEUE>.json`
- Step 7: Call `05-remediate.sh` which shows proposed MQSC and requires explicit `y` approval before executing

**Safeguards:**
- Checks `bob` command exists before proceeding; exits with install instructions if not
- Bob exit code and response file size checked; exits on failure
- `05-remediate.sh` human approval gate preserved -- `--auto` never executes MQSC without `y`
- Skips tickets with no `diagnostic_instruction` field

---

### Prompt 12 -- MQSC fenced block extraction and smoke test
**User requested:** Fix MQSC extraction to use the fenced mqsc block, and add a smoke test.

**05-remediate.sh updated:**
- Primary extraction: parses content between opening ` ```mqsc ` line and closing ` ``` ` line using a stateful while/read loop (portable, no sed multi-line tricks)
- Fallback: if no fenced block found (e.g. default agent mode used instead of mq-ops), falls back to grep-based verb matching with a `[INFO]` warning
- Source noted in remediation file banner: "Source: fenced mqsc block in audit file"

**test-smoke.ps1 created (38 assertions):**
- [1] QMS1 exists and is running (dspmq)
- [2] APPDATA depth = 850, COMMERCE depth = 3200
- [3] All 10 ACME queues defined
- [4] MAXDEPTH = 1000 (APPDATA) and 4000 (COMMERCE)
- [5] ticket-ACME.APPDATA.QUEUE.json and ticket-ACME.COMMERCE.QUEUE.json exist and are valid JSON
- [6] Every ticket has diagnostic_instruction and remediation_status fields
- [7] Every ticket has a matching audit-*.json stub (valid JSON)
- [8] Seed data .txt files exist with correct line counts (850x2=1700, 3200x2=6400)
- [9] .bob/custom_modes.yaml and all 4 rules-mq-ops files exist

**First run result:** 30 passed, 8 failed -- all failures expected (stale queue state from earlier debug sessions, tickets predate new fields). Test infrastructure confirmed working.

**To get 38/38:** clear queues and run `.\run-all.ps1` for a clean end-to-end run.

---

### Prompt 13 -- Design decision: remote QM remediation out of scope
**User stated:** Not connecting to a remote queue manager was a deliberate design decision, not a gap. The scope was fully satisfied by diagnosing and remediating a local queue manager. Remote QM requires TLS certificates, SVRCONN channel config, and security policy -- concerns explicitly deferred post-hackathon.

**Updated in:** `hackathon-evaluation-official.md`
- Criterion 2 "What would reach 5.0" reworded: remote QM removed as a gap, replaced with explicit design decision note
- Remaining Recommendations table updated: remote QM row changed from "Gap" to "Design decision: out of scope"
- Final Assessment updated to reference the deliberate scope boundary

---

#!/usr/bin/env bash
# ============================================================
# 03-scan-queues.sh
# Scans all local queues on QMS1. For each queue where
# CURDEPTH > 0 and IPPROCS = 0, writes a JSON ticket to
# ./tickets/.
#
# Severity thresholds (% full):
#   LOW    < 10%
#   MEDIUM 10-80%
#   HIGH   > 80%
#
# Usage:  wsl -- bash ./03-scan-queues.sh
# ============================================================

set -euo pipefail

QMGR="QMS1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TICKETS_DIR="$SCRIPT_DIR/tickets"
MQ_BIN="/mnt/c/Program Files/IBM/MQ/bin"
RUNMQSC="$MQ_BIN/runmqsc.exe"

mkdir -p "$TICKETS_DIR"

# Sanity check
if [[ ! -x "$RUNMQSC" ]]; then
  echo "[ERROR] runmqsc.exe not found at: $RUNMQSC"
  echo "        Check that IBM MQ is installed at C:\\Program Files\\IBM\\MQ"
  exit 1
fi

SCAN_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PROBLEM_COUNT=0

# ---------- helper: run MQSC, suppress MQ banner -------------
run_mqsc() {
  printf '%s\nEND\n' "$1" | "$RUNMQSC" "$QMGR" 2>/dev/null
}

# ---------- extract a named attribute from MQSC output -------
# Usage: extract_attr "CURDEPTH" "$raw_output"
extract_attr() {
  local attr=$1
  local text=$2
  echo "$text" | grep -oP "${attr}\(\K[^)]+" | head -1 || echo "0"
}

echo "[INFO] Scanning queues on $QMGR at $SCAN_TIME ..."
echo ""

# ---------- get list of all QLOCAL names ---------------------
# DISPLAY QLOCAL(*) with no attributes gives one QUEUE(name) line per queue
QUEUE_RAW=$(run_mqsc "DISPLAY QLOCAL(*)")

QUEUE_LIST=$(echo "$QUEUE_RAW" | grep -oP 'QUEUE\(\K[^)]+' | grep -v '^SYSTEM\.' | sort)

if [[ -z "$QUEUE_LIST" ]]; then
  echo "[INFO] No local queues found on $QMGR (excluding SYSTEM.*)."
  exit 0
fi

# ---------- scan each queue ----------------------------------
while IFS= read -r QUEUE; do
  [[ -z "$QUEUE" ]] && continue

  RAW=$(run_mqsc "DISPLAY QLOCAL($QUEUE) CURDEPTH MAXDEPTH IPPROCS OPPROCS")

  CURDEPTH=$(extract_attr "CURDEPTH" "$RAW")
  MAXDEPTH=$(extract_attr "MAXDEPTH" "$RAW")
  IPPROCS=$(extract_attr "IPPROCS"  "$RAW")
  OPPROCS=$(extract_attr "OPPROCS"  "$RAW")

  # Skip queues that are empty or have active readers
  if [[ "$CURDEPTH" -eq 0 ]] || [[ "$IPPROCS" -gt 0 ]]; then
    continue
  fi

  PROBLEM_COUNT=$(( PROBLEM_COUNT + 1 ))

  # % full (integer; guard against zero MAXDEPTH)
  if [[ "$MAXDEPTH" -gt 0 ]]; then
    PCT=$(( CURDEPTH * 100 / MAXDEPTH ))
  else
    PCT=0
  fi

  # Severity
  if [[ "$PCT" -gt 80 ]]; then
    SEVERITY="HIGH"
  elif [[ "$PCT" -ge 10 ]]; then
    SEVERITY="MEDIUM"
  else
    SEVERITY="LOW"
  fi

  TICKET_ID="TKT-$(date -u +%Y%m%d%H%M%S)-${QUEUE}"
  TICKET_FILE="$TICKETS_DIR/ticket-${QUEUE}.json"

  # Write ticket using printf to avoid here-doc issues with special chars
  printf '{\n' > "$TICKET_FILE"
  printf '  "ticket_id": "%s",\n'        "$TICKET_ID"   >> "$TICKET_FILE"
  printf '  "queue_manager": "%s",\n'    "$QMGR"        >> "$TICKET_FILE"
  printf '  "queue_name": "%s",\n'       "$QUEUE"       >> "$TICKET_FILE"
  printf '  "scan_time": "%s",\n'        "$SCAN_TIME"   >> "$TICKET_FILE"
  printf '  "current_depth": %s,\n'      "$CURDEPTH"    >> "$TICKET_FILE"
  printf '  "max_depth": %s,\n'          "$MAXDEPTH"    >> "$TICKET_FILE"
  printf '  "percent_full": %s,\n'       "$PCT"         >> "$TICKET_FILE"
  printf '  "open_input_count": %s,\n'   "$IPPROCS"     >> "$TICKET_FILE"
  printf '  "open_output_count": %s,\n'  "$OPPROCS"     >> "$TICKET_FILE"
  printf '  "severity": "%s",\n'         "$SEVERITY"    >> "$TICKET_FILE"
  printf '  "status": "OPEN",\n'                        >> "$TICKET_FILE"
  printf '  "remediation_status": "PENDING",\n'         >> "$TICKET_FILE"
  printf '  "remediation_mqsc": null\n'                 >> "$TICKET_FILE"
  printf '}\n'                                          >> "$TICKET_FILE"

  echo "  [$SEVERITY] $QUEUE - depth ${CURDEPTH}/${MAXDEPTH} (${PCT}%) - ticket: $(basename "$TICKET_FILE")"

done <<< "$QUEUE_LIST"

echo ""
if [[ "$PROBLEM_COUNT" -eq 0 ]]; then
  echo "[OK] No problem queues found. All clear."
  exit 0
else
  echo "[DONE] $PROBLEM_COUNT problem queue(s) found. Tickets written to $TICKETS_DIR/."
  echo "       Run 04-enhance-tickets.sh next."
fi
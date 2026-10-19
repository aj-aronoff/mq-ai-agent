#!/usr/bin/env bash
# ============================================================
# 05-remediate.sh
# Extracts MQSC commands from a Bob diagnosis audit file,
# presents them for human approval, and executes them against
# QMS1 via runmqsc.exe if approved.
#
# MQSC is extracted from a fenced ```mqsc ... ``` block in
# Bob's response (produced by the mq-ops custom mode).
# Falls back to grep-based verb matching if no fenced block
# is found (e.g. when using default agent mode).
#
# Usage:
#   wsl -- bash ./05-remediate.sh tickets/ticket-ACME.APPDATA.QUEUE.json
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TICKETS_DIR="$SCRIPT_DIR/tickets"
MQ_BIN="/mnt/c/Program Files/IBM/MQ/bin"
RUNMQSC="$MQ_BIN/runmqsc.exe"
QMGR="QMS1"

# ---- argument check -----------------------------------------
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <ticket.json>"
  exit 1
fi

ticket_file="$1"

if [[ ! -f "$ticket_file" ]]; then
  echo "[ERROR] Ticket file not found: $ticket_file"
  exit 1
fi

# ---- derive paths -------------------------------------------
ticket_dir="$(dirname "$ticket_file")"
ticket_base="$(basename "$ticket_file")"
queue_name="${ticket_base#ticket-}"
queue_name="${queue_name%.json}"

audit_file="$ticket_dir/audit-${queue_name}.json"
mqsc_file="$ticket_dir/remediation-${queue_name}.mqsc"

if [[ ! -f "$audit_file" ]]; then
  echo "[ERROR] Audit file not found: $audit_file"
  echo "        Run 04b-record-diagnosis.sh first to record Bob's diagnosis."
  exit 1
fi

# ---- read bob_response from audit JSON ----------------------
# bob_response is stored as a JSON string with literal \n for newlines.
bob_response_raw=$(grep -oP '"bob_response"\s*:\s*"\K[^"]*(?="\s*$)' "$audit_file" || true)

if [[ -z "$bob_response_raw" ]] || [[ "$bob_response_raw" == "null" ]]; then
  echo "[ERROR] bob_response is empty or null in $audit_file"
  echo "        Run 04b-record-diagnosis.sh to record the diagnosis first."
  exit 1
fi

# Convert \n escape sequences to real newlines
bob_response=$(printf '%b' "$bob_response_raw")

# ---- extract MQSC from fenced block -------------------------
# Primary: extract content between ```mqsc and closing ```
# The mq-ops custom mode always produces this block.
mqsc_commands=""
in_block=0
while IFS= read -r line; do
  if [[ "$line" =~ ^\`\`\`mqsc[[:space:]]*$ ]]; then
    in_block=1
    continue
  fi
  if [[ $in_block -eq 1 ]] && [[ "$line" =~ ^\`\`\`[[:space:]]*$ ]]; then
    in_block=0
    continue
  fi
  if [[ $in_block -eq 1 ]]; then
    mqsc_commands="${mqsc_commands}${line}"$'\n'
  fi
done <<< "$bob_response"

# Strip trailing newline
mqsc_commands="${mqsc_commands%$'\n'}"

# ---- fallback: grep for MQSC verbs --------------------------
if [[ -z "$mqsc_commands" ]]; then
  echo "[INFO] No fenced mqsc block found - falling back to verb matching."
  mqsc_commands=$(echo "$bob_response" | \
    grep -E '^[[:space:]]*(ALTER|CLEAR|START|STOP|DEFINE|REFRESH|RESET)[[:space:]]' || true)
fi

if [[ -z "$mqsc_commands" ]]; then
  echo "[INFO] No MQSC commands found in diagnosis - nothing to remediate."
  exit 0
fi

# ---- write remediation file ---------------------------------
{
  echo "$mqsc_commands"
  echo "END"
} > "$mqsc_file"

echo ""
echo "============================================================"
echo "  Proposed MQSC remediation for $queue_name"
echo "  Source: fenced mqsc block in audit file"
echo "============================================================"
echo ""
cat "$mqsc_file"
echo ""
echo "  File: $mqsc_file"
echo "============================================================"
echo ""

# ---- human approval gate ------------------------------------
printf 'Approve and execute? [y/N]: '
read -r answer

if [[ "$answer" != "y" ]]; then
  tmp=$(mktemp)
  sed 's/"remediation_status": "PENDING"/"remediation_status": "REJECTED"/' "$ticket_file" > "$tmp"
  mv "$tmp" "$ticket_file"
  echo ""
  echo "[INFO] Remediation rejected - no changes made to $QMGR."
  exit 0
fi

# ---- execute via runmqsc ------------------------------------
echo ""
echo "[INFO] Executing MQSC against $QMGR ..."
echo ""

if [[ ! -x "$RUNMQSC" ]]; then
  echo "[ERROR] runmqsc.exe not found at: $RUNMQSC"
  exit 1
fi

mqsc_output=$("$RUNMQSC" "$QMGR" < "$mqsc_file" 2>&1 || true)

echo "$mqsc_output"
echo ""

# ---- update ticket ------------------------------------------
tmp=$(mktemp)
sed 's/"remediation_status": "PENDING"/"remediation_status": "APPLIED"/' "$ticket_file" > "$tmp"
mv "$tmp" "$ticket_file"

tmp=$(mktemp)
sed "s|\"remediation_mqsc\": null|\"remediation_mqsc\": \"$(basename "$mqsc_file")\"|" "$ticket_file" > "$tmp"
mv "$tmp" "$ticket_file"

# ---- update audit file --------------------------------------
remediation_timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

outcome_escaped=$(echo "$mqsc_output" \
  | tr -d '\r' \
  | sed 's/\\/\\\\/g' \
  | sed 's/"/\\"/g' \
  | awk '{printf "%s\\n", $0}' \
  | sed 's/\\n$//')

tmp=$(mktemp)
head -n -1 "$audit_file" | sed '$ s/$/,/' > "$tmp"
printf '  "remediation_timestamp": "%s",\n' "$remediation_timestamp" >> "$tmp"
printf '  "remediation_outcome": "APPLIED: %s"\n' "$outcome_escaped" >> "$tmp"
printf '}\n' >> "$tmp"
mv "$tmp" "$audit_file"

echo "[OK] Remediation applied to $QMGR at $remediation_timestamp"
echo "     Ticket  : $ticket_file"
echo "     Audit   : $audit_file"
echo "     MQSC    : $mqsc_file"
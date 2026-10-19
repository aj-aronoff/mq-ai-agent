#!/usr/bin/env bash
# ============================================================
# 04b-record-diagnosis.sh
# Fills in a stub audit-<QUEUE>.json with the Bob response.
#
# Usage:
#   wsl -- bash ./04b-record-diagnosis.sh <ticket.json> <response.txt>
#
# Arguments:
#   <ticket.json>   Path to the enhanced ticket file.
#   <response.txt>  Path to a plain-text file containing the
#                   Bob diagnosis response to record.
#
# The script derives the audit file path from the ticket path
# (tickets/audit-<QUEUE>.json), reads the stub, fills in
# diagnosis_timestamp (current UTC) and bob_response (contents
# of <response.txt>), then writes the completed audit record.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <ticket.json> <response.txt>"
  exit 1
fi

ticket_file="$1"
response_file="$2"

if [[ ! -f "$ticket_file" ]]; then
  echo "[ERROR] Ticket file not found: $ticket_file"
  exit 1
fi

if [[ ! -f "$response_file" ]]; then
  echo "[ERROR] Response file not found: $response_file"
  exit 1
fi

# Derive audit file path from ticket path
ticket_dir="$(dirname "$ticket_file")"
ticket_base="$(basename "$ticket_file")"
queue_name="${ticket_base#ticket-}"
queue_name="${queue_name%.json}"
audit_file="$ticket_dir/audit-${queue_name}.json"

if [[ ! -f "$audit_file" ]]; then
  echo "[ERROR] Audit stub not found: $audit_file"
  echo "        Run 04-enhance-tickets.sh first."
  exit 1
fi

# Check if already completed
if grep -q '"diagnosis_timestamp": "' "$audit_file"; then
  echo "[WARN] Audit file already has a diagnosis_timestamp: $audit_file"
  echo "       Overwriting with new values."
fi

# Read existing fields from stub
audit_version=$(grep -oP '"audit_version"\s*:\s*"\K[^"]+' "$audit_file" || echo "1.0")
ticket_id=$(grep -oP '"ticket_id"\s*:\s*"\K[^"]+' "$audit_file" || true)
queue=$(grep -oP '"queue_name"\s*:\s*"\K[^"]+' "$audit_file" || true)
qmgr=$(grep -oP '"queue_manager"\s*:\s*"\K[^"]+' "$audit_file" || true)
instruction=$(grep -oP '"diagnostic_instruction"\s*:\s*"\K[^"]+' "$audit_file" || true)
session_source=$(grep -oP '"session_source"\s*:\s*"\K[^"]+' "$audit_file" || echo "IDE")

# Current UTC timestamp in ISO 8601
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Read response text and escape it for JSON:
#   - backslash -> \\
#   - double-quote -> \"
#   - newline -> \n
#   - tab -> \t
#   - carriage return -> removed
bob_response=$(cat "$response_file" \
  | tr -d '\r' \
  | sed 's/\\/\\\\/g' \
  | sed 's/"/\\"/g' \
  | awk '{printf "%s\\n", $0}' \
  | sed 's/\\n$//')

# Write completed audit record
tmp=$(mktemp)
printf '{\n' > "$tmp"
printf '  "audit_version": "%s",\n' "$audit_version" >> "$tmp"
printf '  "ticket_id": "%s",\n' "$ticket_id" >> "$tmp"
printf '  "queue_name": "%s",\n' "$queue" >> "$tmp"
printf '  "queue_manager": "%s",\n' "$qmgr" >> "$tmp"
printf '  "diagnostic_instruction": "%s",\n' "$instruction" >> "$tmp"
printf '  "session_source": "%s",\n' "$session_source" >> "$tmp"
printf '  "diagnosis_timestamp": "%s",\n' "$timestamp" >> "$tmp"
printf '  "bob_response": "%s"\n' "$bob_response" >> "$tmp"
printf '}\n' >> "$tmp"

mv "$tmp" "$audit_file"

echo "[OK] Audit record written: $audit_file"
echo "     Queue   : $queue"
echo "     Recorded: $timestamp"
#!/usr/bin/env bash
# ============================================================
# 04-enhance-tickets.sh
# Reads every JSON ticket in ./tickets/ and adds a
# "diagnostic_instruction" field in the form:
#
#   Diagnose <queue_name> on <queue_manager>
#
# It also writes a stub audit-<QUEUE>.json alongside each
# ticket for later completion by 04b-record-diagnosis.sh.
#
# Usage:
#   wsl -- bash ./04-enhance-tickets.sh              # all tickets
#   wsl -- bash ./04-enhance-tickets.sh <file.json>  # one ticket
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TICKETS_DIR="$SCRIPT_DIR/tickets"

enhance_ticket() {
  local file=$1

  if [[ ! -f "$file" ]]; then
    echo "[WARN] File not found: $file - skipping."
    return
  fi

  # Already enhanced?
  if grep -q '"diagnostic_instruction"' "$file"; then
    echo "[SKIP] $(basename "$file") already enhanced."
    return
  fi

  # Extract fields
  local queue
  local qmgr
  local ticket_id
  queue=$(grep -oP '"queue_name"\s*:\s*"\K[^"]+' "$file" || true)
  qmgr=$(grep -oP '"queue_manager"\s*:\s*"\K[^"]+' "$file" || true)
  ticket_id=$(grep -oP '"ticket_id"\s*:\s*"\K[^"]+' "$file" || true)

  if [[ -z "$queue" || -z "$qmgr" ]]; then
    echo "[WARN] Could not read queue_name or queue_manager from $file - skipping."
    return
  fi

  local instruction="Diagnose ${queue} on ${qmgr}"

  # Build valid JSON:
  #   1. Remove the closing } line
  #   2. Add a comma to the now-last field line
  #   3. Append the new field and closing }
  local tmp
  tmp=$(mktemp)
  # Strip the last line (closing brace), add comma to new last line, append new field
  head -n -1 "$file" | sed '$ s/$/,/' > "$tmp"
  printf '  "diagnostic_instruction": "%s"\n' "$instruction" >> "$tmp"
  printf '}\n' >> "$tmp"
  mv "$tmp" "$file"

  echo "[OK]   $(basename "$file") -> \"$instruction\""

  # Write stub audit file
  local audit_file
  audit_file="$(dirname "$file")/audit-${queue}.json"

  if [[ -f "$audit_file" ]]; then
    echo "[SKIP] $(basename "$audit_file") already exists."
    return
  fi

  printf '{\n' > "$audit_file"
  printf '  "audit_version": "1.0",\n' >> "$audit_file"
  printf '  "ticket_id": "%s",\n' "$ticket_id" >> "$audit_file"
  printf '  "queue_name": "%s",\n' "$queue" >> "$audit_file"
  printf '  "queue_manager": "%s",\n' "$qmgr" >> "$audit_file"
  printf '  "diagnostic_instruction": "%s",\n' "$instruction" >> "$audit_file"
  printf '  "session_source": "IDE",\n' >> "$audit_file"
  printf '  "diagnosis_timestamp": null,\n' >> "$audit_file"
  printf '  "bob_response": null\n' >> "$audit_file"
  printf '}\n' >> "$audit_file"

  echo "[OK]   $(basename "$audit_file") stub written."
}

# ---------- main ---------------------------------------------
if [[ $# -eq 1 ]]; then
  enhance_ticket "$1"
elif [[ $# -eq 0 ]]; then
  if [[ ! -d "$TICKETS_DIR" ]]; then
    echo "[ERROR] Tickets directory not found: $TICKETS_DIR"
    echo "        Run 03-scan-queues.sh first."
    exit 1
  fi

  shopt -s nullglob
  files=("$TICKETS_DIR"/ticket-*.json)

  if [[ ${#files[@]} -eq 0 ]]; then
    echo "[INFO] No ticket files found in $TICKETS_DIR."
    echo "       Run 03-scan-queues.sh first."
    exit 0
  fi

  echo "[INFO] Enhancing ${#files[@]} ticket(s) ..."
  echo ""
  for f in "${files[@]}"; do
    enhance_ticket "$f"
  done
else
  echo "Usage: $0 [ticket-file.json]"
  exit 1
fi

echo ""
echo "[DONE] Enhancement complete."
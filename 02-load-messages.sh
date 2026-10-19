#!/usr/bin/env bash
# ============================================================
# 02-load-messages.sh
# Generates JSON messages and loads them onto ACME queues.
# Uses amqsput.exe (IBM MQ bin64) - one call per message.
#
# amqsput reads ONE message from stdin then exits.
# We call it once per message using process substitution.
# Progress is shown every 50 messages.
#
# Usage:
#   wsl -- bash ./02-load-messages.sh                        # default demo load
#   wsl -- bash ./02-load-messages.sh ACME.ALERTS.QUEUE 50   # custom queue + count
# ============================================================

QMGR="QMS1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="$SCRIPT_DIR/data"
MQ_BIN64="/mnt/c/Program Files/IBM/MQ/bin64"
AMQSPUT="$MQ_BIN64/amqsput.exe"

mkdir -p "$DATA_DIR"

if [[ ! -x "$AMQSPUT" ]]; then
  echo "[ERROR] amqsput.exe not found at: $AMQSPUT"
  exit 1
fi

# ---------- one message per generator call -------------------

gen_appdata() {
  local seq=$1
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  printf '{"event":"APP_DATA","sequence":%d,"timestamp":"%s","appId":"ACME-CORE","payload":{"recordId":"REC-%06d","status":"PENDING","region":"US-EAST","size":%d}}' \
    "$seq" "$ts" "$seq" $(( (seq * 7 % 4096) + 256 ))
}

gen_commerce() {
  local seq=$1
  local ts
  ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local statuses=("PLACED" "CONFIRMED" "PROCESSING" "AWAITING_PAYMENT")
  local status=${statuses[$((seq % 4))]}
  local dollars=$(( (seq * 13 % 999) + 1 ))
  local cents=$(( seq * 7 % 100 ))
  printf '{"event":"COMMERCE_ORDER","sequence":%d,"timestamp":"%s","orderId":"ORD-%08d","customerId":"CUST-%05d","amount":%d.%02d,"currency":"USD","status":"%s","channel":"WEB"}' \
    "$seq" "$ts" "$seq" "$((seq % 10000))" "$dollars" "$cents" "$status"
}

# ---------- load queue: one amqsput call per message ---------
load_queue() {
  local queue=$1
  local count=$2
  local gen_fn=$3
  local data_file="$DATA_DIR/${queue}.txt"
  local loaded=0

  # Generate or reuse seed file (one JSON per line, no blank lines)
  if [[ -f "$data_file" ]]; then
    local existing_lines
    existing_lines=$(wc -l < "$data_file")
    if (( existing_lines == count )); then
      echo "[SKIP] Seed file already exists for $queue ($count messages) - reusing."
    else
      echo "[WARN] Seed file exists but has $existing_lines lines (expected $count). Regenerating..."
      rm -f "$data_file"
    fi
  fi

  if [[ ! -f "$data_file" ]]; then
    echo "[INFO] Generating $count messages for $queue ..."
    > "$data_file"
    local i=1
    while (( i <= count )); do
      $gen_fn "$i" >> "$data_file"
      printf '\n' >> "$data_file"
      (( i++ ))
    done
    echo "[OK]   Seed file written: $data_file"
  fi

  echo "[INFO] Loading $count messages into $queue on $QMGR ..."

  # Read each line from the seed file and put it as one message
  local line_num=0
  while IFS= read -r msg; do
    [[ -z "$msg" ]] && continue
    # pipe message to amqsput; suppress banner output
    echo "$msg" | "$AMQSPUT" "$queue" "$QMGR" > /dev/null 2>&1
    local rc=$?
    if [[ $rc -ne 0 ]]; then
      echo "[ERROR] amqsput failed (rc=$rc) on message $((loaded+1)) for $queue"
      exit 1
    fi
    loaded=$(( loaded + 1 ))
    if (( loaded % 50 == 0 )); then
      echo "  ... $loaded / $count"
    fi
  done < "$data_file"

  echo "[OK]   $count messages loaded onto $queue"
}

# ---------- main ---------------------------------------------
if [[ $# -eq 2 ]]; then
  QUEUE=$1
  COUNT=$2
  echo "[INFO] Custom load: $COUNT messages onto $QUEUE on $QMGR"
  if [[ "$QUEUE" == *"COMMERCE"* ]]; then
    load_queue "$QUEUE" "$COUNT" "gen_commerce"
  else
    load_queue "$QUEUE" "$COUNT" "gen_appdata"
  fi
elif [[ $# -eq 0 ]]; then
  load_queue "ACME.APPDATA.QUEUE"   850  "gen_appdata"
  load_queue "ACME.COMMERCE.QUEUE" 3200  "gen_commerce"
else
  echo "Usage: $0 [QUEUE_NAME COUNT]"
  exit 1
fi

echo ""
echo "[DONE] Message load complete. Run 03-scan-queues.sh next."
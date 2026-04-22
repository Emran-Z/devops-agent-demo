#!/usr/bin/env bash
# trigger-leak.sh — generate load against POST /api/process to accelerate
# the memory leak on the buggy app version.
#
# Usage:
#   ./scripts/trigger-leak.sh <EC2_IP> [requests_per_second] [duration_seconds]
#
# Examples:
#   ./scripts/trigger-leak.sh 54.123.45.67           # default: 5 rps for 600 s
#   ./scripts/trigger-leak.sh 54.123.45.67 10 300    # 10 rps for 5 min
#
# Each request causes the buggy app to append ~2 MB to an unbounded list.
# At 5 rps the process adds ~600 MB/min, exhausting 1 GB in ~90 seconds.
# Use a lower rate (2–3 rps) for a more gradual, visible climb over 5–10 min.

set -euo pipefail

EC2_IP="${1:?Usage: $0 <EC2_IP> [rps] [duration_secs]}"
RPS="${2:-5}"
DURATION="${3:-600}"
PORT="${PORT:-5000}"
BASE_URL="http://${EC2_IP}:${PORT}"

PAYLOAD='{"value": 42, "label": "demo-load-test"}'

echo "========================================================"
echo "  Target  : ${BASE_URL}/api/process"
echo "  Rate    : ${RPS} req/s"
echo "  Duration: ${DURATION} s"
echo "  Est. memory added per minute: ~$((RPS * 60 * 2)) MB"
echo "========================================================"
echo "Ctrl-C to stop early."
echo ""

DELAY=$(awk "BEGIN { printf \"%.4f\", 1/${RPS} }")

SENT=0
START=$(date +%s)
END=$(( START + DURATION ))

while [ "$(date +%s)" -lt "$END" ]; do
    RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "${BASE_URL}/api/process" \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        --max-time 5 || echo "ERR")

    SENT=$(( SENT + 1 ))

    if (( SENT % 10 == 0 )); then
        ELAPSED=$(( $(date +%s) - START ))
        # Also fetch /metrics to show live memory
        MEM=$(curl -s --max-time 3 "${BASE_URL}/metrics" \
            | python3 -c "import sys,json; d=json.load(sys.stdin); print(f\"rss={d['process_rss_mb']} MB  sys={d['system_used_pct']}%  cache={d.get('leak_cache_size','n/a')} entries\")" \
            2>/dev/null || echo "metrics unavailable")
        echo "[${ELAPSED}s] sent=${SENT}  last_status=${RESPONSE}  ${MEM}"
    fi

    sleep "$DELAY"
done

echo ""
echo "Done. Sent ${SENT} requests in ${DURATION} s."

#!/bin/bash
CONTAINER="lab052-log-aggregation-broken"
PASS=0
FAIL=0

check() {
    local description="$1"; local result="$2"
    if [[ "$result" == "0" ]]; then
        echo -e "  ✅  $description"
        ((PASS++))
    else
        echo -e "  ❌  $description"
        ((FAIL++))
    fi
}

echo "Running validation checks..."
echo ""

# --- Check 1: Container is running ---
docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"
check "Container ${CONTAINER} is running" "$?"

if [[ "$FAIL" -gt 0 ]]; then
    echo ""
    echo "Container is not running. Start it with: docker compose up -d"
    exit 1
fi

# --- Check 2: Rsyslog daemon is running ---
docker exec "$CONTAINER" pgrep rsyslog &>/dev/null
check "Rsyslog daemon is running" "$?"

# --- Check 3: Forwarding config is syntactically correct and points to 5514 ---
# Match an active (non-commented) forwarding line ending in :5514
docker exec "$CONTAINER" grep -E '^[[:space:]]*\*\.\*[[:space:]]+@@?[^[:space:]]+:5514[[:space:]]*$' \
    /etc/rsyslog.d/50-forwarding.conf &>/dev/null
check "Forwarding config has an active rule pointing to port 5514" "$?"

# --- Check 4: No active forwarding rule still points to the broken port 5515 ---
# Pass if no uncommented line references :5515
if docker exec "$CONTAINER" grep -E '^[[:space:]]*[^#].*:5515' \
    /etc/rsyslog.d/50-forwarding.conf &>/dev/null; then
    check "No active forwarding rule still references the broken port 5515" "1"
else
    check "No active forwarding rule still references the broken port 5515" "0"
fi

# --- Check 5: Aggregator endpoint is listening on UDP 5514 ---
# Try ss first (modern), fall back to netstat (legacy), then to /proc/net/udp (always available).
# /proc/net/udp lists ports in hex — 5514 = 0x158A.
docker exec "$CONTAINER" bash -c '
    if command -v ss >/dev/null 2>&1; then
        ss -ulnp 2>/dev/null | grep -q ":5514"
    elif command -v netstat >/dev/null 2>&1; then
        netstat -ulnp 2>/dev/null | grep -q ":5514"
    else
        # /proc/net/udp: 2nd column is local_address:port in hex. 5514 dec = 158A hex.
        awk "{print \$2}" /proc/net/udp | grep -qi ":158A"
    fi
'
check "Aggregator is listening on UDP port 5514" "$?"

# --- Check 6: End-to-end log forwarding works ---
# Use a unique marker so we can't be fooled by stale log lines from a previous run.
MARKER="validation-$(date +%s)-$RANDOM"
docker exec "$CONTAINER" logger -t lab052-validate "$MARKER"

# Retry up to 5 times with 1s sleep — handles slow flushes more reliably than a single sleep
ARRIVED=1
for i in 1 2 3 4 5; do
    sleep 1
    if docker exec "$CONTAINER" grep -q "$MARKER" /var/log/aggregated.log 2>/dev/null; then
        ARRIVED=0
        break
    fi
done
check "Test log message arrived at the aggregation endpoint" "$ARRIVED"

echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
    echo "✅  Lab passed — log pipeline is working end-to-end."
    exit 0
else
    echo "❌  Lab failed — $FAIL check(s) still need to be addressed."
    exit 1
fi

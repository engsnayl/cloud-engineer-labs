#!/bin/bash
CONTAINER="lab052-log-aggregation-broken"
PASS=0
FAIL=0
check() {
    local description="$1"; local result="$2"
    if [[ "$result" == "0" ]]; then echo -e "  ✅  $description"; ((PASS++))
    else echo -e "  ❌  $description"; ((FAIL++)); fi
}
echo "Running validation checks..."
echo ""

docker exec "$CONTAINER" pgrep rsyslog &>/dev/null
check "Rsyslog daemon is running" "$?"

docker exec "$CONTAINER" grep -q "5514" /etc/rsyslog.d/50-forwarding.conf 2>/dev/null
check "Forwarding config points to correct port (5514)" "$?"

# Generate a test log and check it arrives
docker exec "$CONTAINER" logger -t test "validation-check-$(date +%s)"
sleep 2
docker exec "$CONTAINER" grep -q "validation-check\|myapp" /var/log/aggregated.log 2>/dev/null
check "Logs arriving at aggregation endpoint" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

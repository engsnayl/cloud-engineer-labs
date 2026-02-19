#!/bin/bash
CONTAINER="lab050-app-500-errors"
PASS=0
FAIL=0
check() {
    local description="$1"; local result="$2"
    if [[ "$result" == "0" ]]; then echo -e "  ✅  $description"; ((PASS++))
    else echo -e "  ❌  $description"; ((FAIL++)); fi
}
echo "Running validation checks..."
echo ""

docker exec "$CONTAINER" test -f /tmp/incident-report.txt
check "Incident report exists at /tmp/incident-report.txt" "$?"

docker exec "$CONTAINER" grep -qi "pool\|connection\|database" /tmp/incident-report.txt 2>/dev/null
check "Report identifies database connection pool as root cause" "$?"

docker exec "$CONTAINER" grep -qi "payment" /tmp/incident-report.txt 2>/dev/null
check "Report identifies /api/payments as affected endpoint" "$?"

docker exec "$CONTAINER" curl -s http://localhost:8080/api/health 2>/dev/null | grep -q "OK"
check "Application is still running" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

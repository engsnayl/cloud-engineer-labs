#!/bin/bash
CONTAINER="lab051-memory-leak-detection"
PASS=0
FAIL=0
check() {
    local description="$1"; local result="$2"
    if [[ "$result" == "0" ]]; then echo -e "  ✅  $description"; ((PASS++))
    else echo -e "  ❌  $description"; ((FAIL++)); fi
}
echo "Running validation checks..."
echo ""

docker exec "$CONTAINER" bash -c "! kill -0 \$(cat /tmp/leaky.pid) 2>/dev/null"
check "Leaking process has been killed" "$?"

docker exec "$CONTAINER" bash -c "kill -0 \$(cat /tmp/legit-app.pid) 2>/dev/null"
check "Legitimate application still running" "$?"

docker exec "$CONTAINER" test -f /tmp/incident-report.txt
check "Incident report created" "$?"

docker exec "$CONTAINER" grep -qi "memory\|leak\|cache\|growing" /tmp/incident-report.txt 2>/dev/null
check "Report identifies memory leak" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

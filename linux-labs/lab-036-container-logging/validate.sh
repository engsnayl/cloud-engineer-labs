#!/bin/bash
# =============================================================================
# Validation Criteria (from CHALLENGE.md):
#   - `docker logs` shows application output
#   - Application is still running and responding
#   - No large log files inside the container
#   - Container is running with appropriate log options
# =============================================================================
CONTAINER="lab036-container-logging"
PASS=0
FAIL=0
check() {
    local description="$1"; local result="$2"
    if [[ "$result" == "0" ]]; then echo -e "  ✅  $description"; ((PASS++))
    else echo -e "  ❌  $description"; ((FAIL++)); fi
}
echo "Running validation checks..."
echo ""

docker logs "$CONTAINER" 2>&1 | grep -qi "request\|starting\|app"
check "docker logs shows application output" "$?"

docker exec "$CONTAINER" curl -s http://localhost:8080 2>/dev/null | grep -q "OK"
check "Application still responding" "$?"

# Check no large log files inside container
big_logs=$(docker exec "$CONTAINER" find /var/log -name "app.log" -size +1M 2>/dev/null | wc -l)
[[ "$big_logs" -eq 0 ]]
check "No oversized log files inside container" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

#!/bin/bash
# =============================================================================
# Validation: Lab 019 - Container Won't Start
# =============================================================================

PASS=0
FAIL=0

check() {
    local description="$1"
    local result="$2"
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

# Check if payment-service container is running
docker ps --filter "name=payment-service" --format '{{.Status}}' | grep -q "Up"
check "payment-service container is running" "$?"

# Check logs have no errors
docker logs payment-service 2>&1 | grep -qi "error\|traceback\|exception"
[[ $? -ne 0 ]]
check "Container logs show no errors" "$?"

# Check service responds
docker exec payment-service curl -s http://localhost:5000 2>/dev/null | grep -q "Payment Service"
check "Service responds on port 5000" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"

[[ "$FAIL" -eq 0 ]]

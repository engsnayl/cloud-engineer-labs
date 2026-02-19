#!/bin/bash
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

ready=$(kubectl get deployment critical-service -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ "$ready" -ge 1 ]] 2>/dev/null
check "critical-service has ready replicas" "$?"

pending=$(kubectl get pods -l app=critical-service --field-selector=status.phase=Pending 2>/dev/null | grep -c "Pending")
[[ "$pending" -eq 0 ]]
check "No pods stuck in Pending" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

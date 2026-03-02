#!/bin/bash
# =============================================================================
# Validation Criteria (from CHALLENGE.md):
#   See validate.sh for specific checks.
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

# Check new-service is deployed
kubectl get deployment new-service -n production &>/dev/null
check "new-service deployment exists" "$?"

ready=$(kubectl get deployment new-service -n production -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
[[ "$ready" -ge 1 ]] 2>/dev/null
check "new-service has ready replicas" "$?"

# Legacy service still running
kubectl get deployment legacy-service -n production -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -qE "[1-9]"
check "legacy-service still has ready replicas" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

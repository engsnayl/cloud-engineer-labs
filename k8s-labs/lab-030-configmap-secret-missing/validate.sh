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

kubectl get configmap app-config &>/dev/null
check "ConfigMap 'app-config' exists" "$?"

kubectl get configmap app-config -o jsonpath='{.data.database_host}' 2>/dev/null | grep -q "."
check "ConfigMap has 'database_host' key" "$?"

kubectl get secret app-secrets &>/dev/null
check "Secret 'app-secrets' exists" "$?"

kubectl get secret app-secrets -o jsonpath='{.data.db-password}' 2>/dev/null | base64 -d | grep -q "."
check "Secret has 'db-password' key with value" "$?"

pod_status=$(kubectl get pod -l app=webapp -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
[[ "$pod_status" == "Running" ]]
check "webapp pod is Running (got: $pod_status)" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

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

kubectl auth can-i list pods --namespace monitoring --as system:serviceaccount:monitoring:monitoring-sa 2>/dev/null | grep -q "yes"
check "monitoring-sa can list pods in monitoring namespace" "$?"

kubectl auth can-i get pods --namespace monitoring --as system:serviceaccount:monitoring:monitoring-sa 2>/dev/null | grep -q "yes"
check "monitoring-sa can get pods in monitoring namespace" "$?"

kubectl auth can-i watch pods --namespace monitoring --as system:serviceaccount:monitoring:monitoring-sa 2>/dev/null | grep -q "yes"
check "monitoring-sa can watch pods in monitoring namespace" "$?"

role_ns=$(kubectl get role pod-reader -n monitoring -o jsonpath='{.metadata.namespace}' 2>/dev/null)
[[ "$role_ns" == "monitoring" ]]
check "Role is in the monitoring namespace" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

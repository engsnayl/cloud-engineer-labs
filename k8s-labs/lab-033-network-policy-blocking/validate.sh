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

kubectl get networkpolicy db-restrict -n production &>/dev/null
check "NetworkPolicy db-restrict exists" "$?"

# Check that the policy allows 'role: api'
kubectl get networkpolicy db-restrict -n production -o yaml 2>/dev/null | grep -q "role: api"
check "NetworkPolicy allows traffic from role: api" "$?"

# Check that the policy still restricts to port 5432
kubectl get networkpolicy db-restrict -n production -o yaml 2>/dev/null | grep -q "5432"
check "NetworkPolicy restricts to port 5432" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

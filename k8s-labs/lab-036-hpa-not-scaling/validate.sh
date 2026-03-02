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

kubectl get hpa web-tier-hpa &>/dev/null
check "HPA web-tier-hpa exists" "$?"

targets=$(kubectl get hpa web-tier-hpa -o jsonpath='{.status.currentMetrics[0].resource.current.averageUtilization}' 2>/dev/null)
[[ -n "$targets" && "$targets" != "<unknown>" ]]
check "HPA shows current metrics (not unknown)" "$?"

requests=$(kubectl get deployment web-tier -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null)
[[ -n "$requests" ]]
check "Deployment has CPU resource requests set" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

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

kubectl get ingress app-ingress &>/dev/null
check "Ingress resource exists" "$?"

backend_name=$(kubectl get ingress app-ingress -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}' 2>/dev/null)
[[ "$backend_name" == "frontend" ]]
check "Root path routes to 'frontend' service (got: $backend_name)" "$?"

api_port=$(kubectl get ingress app-ingress -o jsonpath='{.spec.rules[0].http.paths[1].backend.service.port.number}' 2>/dev/null)
[[ "$api_port" == "80" ]]
check "API path uses correct port 80 (got: $api_port)" "$?"

root_port=$(kubectl get ingress app-ingress -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.port.number}' 2>/dev/null)
[[ "$root_port" == "80" ]]
check "Root path uses correct port 80 (got: $root_port)" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

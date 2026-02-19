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

endpoints=$(kubectl get endpoints backend-api -o jsonpath='{.subsets[0].addresses}' 2>/dev/null)
[[ -n "$endpoints" ]]
check "backend-api service has endpoints" "$?"

ep_count=$(kubectl get endpoints backend-api -o jsonpath='{.subsets[0].addresses}' 2>/dev/null | grep -o "ip" | wc -l)
[[ "$ep_count" -ge 2 ]] 2>/dev/null
check "Service has 2+ endpoints (matching replicas)" "$?"

target_port=$(kubectl get svc backend-api -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null)
[[ "$target_port" == "80" ]]
check "Service targetPort matches container port (80)" "$?"

kubectl run curl-test --image=curlimages/curl --rm -i --restart=Never -- curl -s http://backend-api 2>/dev/null | grep -q "nginx\|Welcome"
check "Can curl backend-api service from within cluster" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

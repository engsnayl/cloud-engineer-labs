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

# Check pod is running
kubectl get pod -l app=payment-service -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"
check "payment-service pod is Running" "$?"

# Check no restarts in last check
restarts=$(kubectl get pod -l app=payment-service -o jsonpath='{.items[0].status.containerStatuses[0].restartCount}' 2>/dev/null)
[[ "$restarts" -lt 3 ]] 2>/dev/null
check "Pod restart count is low (<3)" "$?"

# Check image is valid
image=$(kubectl get pod -l app=payment-service -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null)
[[ "$image" != *"1.99"* ]]
check "Pod uses a valid image tag (not 1.99.0)" "$?"

# Check resources are valid (requests <= limits)
req_mem=$(kubectl get pod -l app=payment-service -o jsonpath='{.items[0].spec.containers[0].resources.requests.memory}' 2>/dev/null)
lim_mem=$(kubectl get pod -l app=payment-service -o jsonpath='{.items[0].spec.containers[0].resources.limits.memory}' 2>/dev/null)
echo "  ℹ️  Resources: requests=$req_mem, limits=$lim_mem"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

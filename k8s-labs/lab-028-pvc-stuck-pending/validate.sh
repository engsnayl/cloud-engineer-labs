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

pvc_status=$(kubectl get pvc db-pvc -o jsonpath='{.status.phase}' 2>/dev/null)
[[ "$pvc_status" == "Bound" ]]
check "PVC db-pvc is Bound (got: $pvc_status)" "$?"

pod_status=$(kubectl get pod database -o jsonpath='{.status.phase}' 2>/dev/null)
[[ "$pod_status" == "Running" ]]
check "Database pod is Running (got: $pod_status)" "$?"

storage_class=$(kubectl get pvc db-pvc -o jsonpath='{.spec.storageClassName}' 2>/dev/null)
[[ "$storage_class" == "fast-storage" ]]
check "PVC uses correct StorageClass (got: $storage_class)" "$?"

access_mode=$(kubectl get pvc db-pvc -o jsonpath='{.spec.accessModes[0]}' 2>/dev/null)
[[ "$access_mode" == "ReadWriteOnce" ]]
check "PVC uses ReadWriteOnce access mode (got: $access_mode)" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

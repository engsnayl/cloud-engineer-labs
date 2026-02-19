#!/bin/bash
PASS=0
FAIL=0
check() {
    local description="$1"; local result="$2"
    if [[ "$result" == "0" ]]; then echo -e "  ✅  $description"; ((PASS++))
    else echo -e "  ❌  $description"; ((FAIL++)); fi
}
echo "Running validation checks..."
echo ""

# Docker checks
test -f solution/docker/frontend/Dockerfile
check "Frontend Dockerfile exists" "$?"

test -f solution/docker/backend/Dockerfile
check "Backend Dockerfile exists" "$?"

test -f solution/docker/frontend/nginx.conf
check "Nginx config exists" "$?"

# K8s manifest checks
for f in namespace frontend-deployment frontend-service backend-deployment \
         backend-service backend-configmap database-statefulset database-service \
         database-secret ingress network-policy; do
    test -f "solution/k8s/${f}.yaml"
    check "K8s manifest: ${f}.yaml exists" "$?"
done

# Check secret is base64 encoded
if test -f solution/k8s/database-secret.yaml; then
    grep -q "kind: Secret" solution/k8s/database-secret.yaml
    check "Database secret is kind: Secret" "$?"
fi

# Check network policy targets database
if test -f solution/k8s/network-policy.yaml; then
    grep -q "NetworkPolicy" solution/k8s/network-policy.yaml
    check "Network policy resource exists" "$?"
fi

# Check README
test -f solution/README.md
check "Architecture README exists" "$?"

# If cluster is available, check resources
if kubectl cluster-info &>/dev/null; then
    echo ""
    echo "Cluster checks:"
    kubectl get pods -n multi-tier-app 2>/dev/null | grep -q "Running"
    check "Pods are running in namespace" "$?"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

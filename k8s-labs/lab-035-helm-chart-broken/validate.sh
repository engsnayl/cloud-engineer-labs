#!/bin/bash
# =============================================================================
# Validation Criteria (from CHALLENGE.md):
#   - `helm template webapp ./webapp-chart` renders without errors
#   - Chart installs successfully with `helm install`
#   - Deployment creates running pods
#   - Service exposes the application correctly
# =============================================================================
PASS=0
FAIL=0
check() {
    local description="$1"; local result="$2"
    if [[ "$result" == "0" ]]; then echo -e "  ✅  $description"; ((PASS++))
    else echo -e "  ❌  $description"; ((FAIL++)); fi
}
echo "Running validation checks..."
echo ""

# Check helm template renders cleanly
helm template webapp ./webapp-chart &>/dev/null
check "helm template renders without errors" "$?"

# Check Chart.yaml has required fields
grep -q "^name:" webapp-chart/Chart.yaml 2>/dev/null
check "Chart.yaml has name field" "$?"

grep -q "apiVersion: v2" webapp-chart/Chart.yaml 2>/dev/null
check "Chart.yaml uses apiVersion v2" "$?"

# Check no spaces in label values
grep "appLabel" webapp-chart/values.yaml | grep -qv " "
label_val=$(grep "appLabel" webapp-chart/values.yaml | sed 's/.*: *//' | tr -d '"')
echo "$label_val" | grep -qv " "
check "appLabel has no spaces" "$?"

# Check service port is integer
grep "port:" webapp-chart/values.yaml | head -1 | grep -qvE '"[0-9]+"'
check "Service port is integer (not string)" "$?"

# If cluster available, check actual install
if kubectl cluster-info &>/dev/null; then
    helm list | grep -q webapp
    check "Chart is installed (helm release exists)" "$?"
    
    kubectl get pods -l app -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"
    check "Pods are running" "$?"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

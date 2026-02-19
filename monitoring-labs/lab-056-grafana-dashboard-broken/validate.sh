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

# Check Grafana is accessible
curl -s http://localhost:3000/api/health 2>/dev/null | grep -q "ok"
check "Grafana is healthy" "$?"

# Check data source URL
grep -q "http://prometheus:9090" provisioning/datasources/prometheus.yml 2>/dev/null
check "Data source URL points to prometheus:9090 (not localhost)" "$?"

# Check PromQL fixes in dashboard
dashboard="provisioning/dashboards/app-dashboard.json"

grep -q '"rate(' "$dashboard" 2>/dev/null && ! grep -q '"rates(' "$dashboard" 2>/dev/null
check "Request rate uses 'rate' not 'rates'" "$?"

grep -q 'status=\\"500\\"' "$dashboard" 2>/dev/null || grep -q 'status="500"' "$dashboard" 2>/dev/null
check "Error rate uses double quotes for label matcher" "$?"

grep -q "0.95" "$dashboard" 2>/dev/null
check "Histogram quantile uses 0.95 (not 95)" "$?"

grep -q "active_connections" "$dashboard" 2>/dev/null
check "Active connections metric name is correct (plural)" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

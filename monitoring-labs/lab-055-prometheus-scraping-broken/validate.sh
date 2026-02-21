#!/bin/bash
# =============================================================================
# Validation Criteria (from CHALLENGE.md):
#   - Prometheus is running and accessible
#   - All three scrape targets are UP
#   - Metrics are being collected (up metric returns results)
#   - Configuration passes validation
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

# Check Prometheus is responding
curl -s http://localhost:9090/-/healthy 2>/dev/null | grep -q "OK\|Healthy"
check "Prometheus is healthy" "$?"

# Check targets are up
targets=$(curl -s http://localhost:9090/api/v1/targets 2>/dev/null)
up_count=$(echo "$targets" | python3 -c "import sys,json; d=json.load(sys.stdin); print(sum(1 for t in d.get('data',{}).get('activeTargets',[]) if t['health']=='up'))" 2>/dev/null)
[[ "$up_count" -ge 3 ]] 2>/dev/null
check "All 3 targets are UP (got: ${up_count:-0})" "$?"

# Check scrape interval is reasonable
grep -E "scrape_interval: (10|15|30|60)s" prometheus.yml &>/dev/null
check "Scrape interval is reasonable (10-60s)" "$?"

# Check metrics path
grep -q "metrics_path: '/metrics'" prometheus.yml 2>/dev/null || ! grep -q "metrics_path:" prometheus.yml 2>/dev/null
check "Metrics path is correct (/metrics)" "$?"

# Check app metrics are being collected
curl -s "http://localhost:9090/api/v1/query?query=up" 2>/dev/null | grep -q '"value"'
check "Metrics are being collected (up metric has data)" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

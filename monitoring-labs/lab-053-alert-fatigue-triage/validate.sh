#!/bin/bash
CONTAINER="lab053-alert-fatigue-triage"
PASS=0
FAIL=0
check() {
    local description="$1"; local result="$2"
    if [[ "$result" == "0" ]]; then echo -e "  ✅  $description"; ((PASS++))
    else echo -e "  ❌  $description"; ((FAIL++)); fi
}
echo "Running validation checks..."
echo ""

docker exec "$CONTAINER" test -f /opt/monitoring/alerts-fixed.json
check "Fixed alert config exists" "$?"

# Check CPU threshold is reasonable (>70%)
docker exec "$CONTAINER" python3 -c "
import json
with open('/opt/monitoring/alerts-fixed.json') as f:
    data = json.load(f)
alerts = {a['name']: a for a in data['alerts']}
cpu = alerts.get('cpu_high', alerts.get('cpu_above_1_percent', {}))
assert cpu.get('threshold', 0) >= 70, 'CPU threshold too low'
print('ok')
" 2>/dev/null | grep -q "ok"
check "CPU alert threshold is reasonable (>=70%)" "$?"

# Check not everything is critical
docker exec "$CONTAINER" python3 -c "
import json
with open('/opt/monitoring/alerts-fixed.json') as f:
    data = json.load(f)
severities = set(a['severity'] for a in data['alerts'])
assert len(severities) > 1, 'Multiple severity levels needed'
print('ok')
" 2>/dev/null | grep -q "ok"
check "Multiple severity levels used (not all critical)" "$?"

# Check alert count is reduced
alert_count=$(docker exec "$CONTAINER" python3 -c "
import json
with open('/opt/monitoring/alerts-fixed.json') as f:
    data = json.load(f)
print(len(data['alerts']))
" 2>/dev/null)
[[ "$alert_count" -lt 10 ]] 2>/dev/null
check "Alert count is reasonable (got: $alert_count)" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

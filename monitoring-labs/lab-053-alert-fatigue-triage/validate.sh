#!/bin/bash
CONTAINER="lab053-alert-fatigue-triage"
PASS=0
FAIL=0

check() {
    local description="$1"; local result="$2"
    if [[ "$result" == "0" ]]; then
        echo -e "  ✅  $description"; ((PASS++))
    else
        echo -e "  ❌  $description"; ((FAIL++))
    fi
}

echo "Running validation checks..."
echo ""

# 1. File exists
docker exec "$CONTAINER" test -f /opt/monitoring/alerts-fixed.json
check "Fixed alert config exists at /opt/monitoring/alerts-fixed.json" "$?"

# 2. File is valid JSON
docker exec "$CONTAINER" python3 -c "
import json, sys
try:
    with open('/opt/monitoring/alerts-fixed.json') as f:
        json.load(f)
except Exception as e:
    sys.exit(1)
" 2>/dev/null
check "Fixed alert config is valid JSON" "$?"

# 3. Has an 'alerts' array
docker exec "$CONTAINER" python3 -c "
import json, sys
with open('/opt/monitoring/alerts-fixed.json') as f:
    data = json.load(f)
assert isinstance(data.get('alerts'), list) and len(data['alerts']) > 0
" 2>/dev/null
check "Config contains a non-empty 'alerts' array" "$?"

# 4. Total alert count between 4 and 9 (must be reduced from 10, but not collapsed to 1)
alert_count=$(docker exec "$CONTAINER" python3 -c "
import json
with open('/opt/monitoring/alerts-fixed.json') as f:
    data = json.load(f)
print(len(data['alerts']))
" 2>/dev/null)
[[ "$alert_count" -ge 4 && "$alert_count" -le 9 ]] 2>/dev/null
check "Alert count is between 4 and 9 (got: $alert_count)" "$?"

# 5. Every alert has the required fields
docker exec "$CONTAINER" python3 -c "
import json, sys
with open('/opt/monitoring/alerts-fixed.json') as f:
    data = json.load(f)
required = {'name', 'threshold', 'severity'}
for a in data['alerts']:
    assert required.issubset(a.keys()), f'Alert missing fields: {a}'
" 2>/dev/null
check "Every alert has name, threshold, and severity fields" "$?"

# 6. CPU threshold is sensible (>=70%)
docker exec "$CONTAINER" python3 -c "
import json, sys
with open('/opt/monitoring/alerts-fixed.json') as f:
    data = json.load(f)
cpu_alerts = [a for a in data['alerts'] if 'cpu' in a['name'].lower()]
assert cpu_alerts, 'No CPU alert found'
assert all(a['threshold'] >= 70 for a in cpu_alerts), 'CPU threshold below 70'
" 2>/dev/null
check "CPU alert threshold is >=70%" "$?"

# 7. Memory threshold is sensible (>=70%)
docker exec "$CONTAINER" python3 -c "
import json, sys
with open('/opt/monitoring/alerts-fixed.json') as f:
    data = json.load(f)
mem_alerts = [a for a in data['alerts'] if 'memory' in a['name'].lower() or 'mem' in a['name'].lower()]
assert mem_alerts, 'No memory alert found'
assert all(a['threshold'] >= 70 for a in mem_alerts), 'Memory threshold below 70'
" 2>/dev/null
check "Memory alert threshold is >=70%" "$?"

# 8. Multiple severity levels — and 'warning' specifically must be present
docker exec "$CONTAINER" python3 -c "
import json, sys
with open('/opt/monitoring/alerts-fixed.json') as f:
    data = json.load(f)
severities = set(a['severity'].lower() for a in data['alerts'])
assert len(severities) >= 2, f'Need at least 2 severity levels, got: {severities}'
assert 'warning' in severities, f\"'warning' severity required, got: {severities}\"
" 2>/dev/null
check "Uses multiple severity levels including 'warning'" "$?"

# 9. Not everything is critical (max 60% of alerts can be critical)
docker exec "$CONTAINER" python3 -c "
import json, sys
with open('/opt/monitoring/alerts-fixed.json') as f:
    data = json.load(f)
total = len(data['alerts'])
critical = sum(1 for a in data['alerts'] if a['severity'].lower() == 'critical')
assert critical / total <= 0.6, f'{critical}/{total} alerts are critical (max 60%)'
" 2>/dev/null
check "No more than 60% of alerts are 'critical'" "$?"

# 10. Single-event noise alerts have been addressed — i.e. if an alert exists for log errors
#     or pod-pending or packet loss, its threshold must be meaningfully raised above 1.
docker exec "$CONTAINER" python3 -c "
import json, sys
with open('/opt/monitoring/alerts-fixed.json') as f:
    data = json.load(f)
# These alert *types* in the original were single-event noise (threshold=1).
# If the engineer kept any of them, the threshold must be >1.
noisy_keywords = ['log_error', 'pod_pending', 'packet_loss', 'container_restart']
for a in data['alerts']:
    if any(k in a['name'].lower() for k in noisy_keywords):
        assert a['threshold'] > 1, f\"{a['name']} kept original noisy threshold of {a['threshold']}\"
" 2>/dev/null
check "Single-event noisy alerts removed or thresholds raised" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

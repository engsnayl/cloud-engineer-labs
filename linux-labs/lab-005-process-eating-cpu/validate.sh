#!/bin/bash
# =============================================================================
# Validation Criteria (from CHALLENGE.md):
#   - No process consuming >50% CPU
#   - The rogue `stress` process is not running
#   - The legitimate app process (python3) is still running
#   - System load average is below 2.0
# =============================================================================
# =============================================================================
# Validation: Lab 005 - Process Eating CPU
# =============================================================================

CONTAINER="lab005-process-eating-cpu"
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

# Check 1: No stress-ng or analytics-worker running
docker exec "$CONTAINER" bash -c "! pgrep -f 'analytics-worker|stress-ng'" &>/dev/null
check "Rogue process (analytics-worker/stress-ng) is not running" "$?"

# Check 2: Legitimate app is still running
docker exec "$CONTAINER" pgrep -f "python3 /opt/app.py" &>/dev/null
check "Legitimate app process (python3 app.py) is still running" "$?"

# Check 3: No process using >50% CPU
high_cpu=$(docker exec "$CONTAINER" ps aux --no-headers | awk '{if ($3 > 50.0) print $0}' | wc -l)
[[ "$high_cpu" -eq 0 ]]
check "No process consuming >50% CPU" "$?"

# Check 4: Load average is reasonable
load=$(docker exec "$CONTAINER" cat /proc/loadavg | awk '{print $1}')
result=$(echo "$load < 2.0" | bc -l 2>/dev/null || echo "0")
[[ "$result" == "1" ]]
check "System load average below 2.0 (current: $load)" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"

[[ "$FAIL" -eq 0 ]]

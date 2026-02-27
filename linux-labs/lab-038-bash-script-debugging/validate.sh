#!/bin/bash
# =============================================================================
# Validation: Bash Script Debugging
# =============================================================================

CONTAINER="lab038-scripting"

echo "Running bash script validation..."
echo ""

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

# Check 1: shellcheck passes with no errors
docker exec "$CONTAINER" shellcheck /opt/scripts/healthcheck.sh &>/dev/null
check "Script passes shellcheck" "$?"

# Check 2: Script runs without errors
docker exec "$CONTAINER" bash /opt/scripts/healthcheck.sh &>/dev/null
check "Script executes successfully" "$?"

# Check 3: Report file was created
docker exec "$CONTAINER" bash -c 'ls /var/reports/health-*.txt 2>/dev/null | head -1 | grep -q "health"'
check "Health report file was generated" "$?"

# Check 4: Report contains disk usage section
docker exec "$CONTAINER" bash -c 'cat /var/reports/health-*.txt 2>/dev/null | grep -q "Disk Usage"'
check "Report contains disk usage section" "$?"

# Check 5: Report contains memory section
docker exec "$CONTAINER" bash -c 'cat /var/reports/health-*.txt 2>/dev/null | grep -q "Memory Usage"'
check "Report contains memory section" "$?"

# Check 6: Report contains error count
docker exec "$CONTAINER" bash -c 'cat /var/reports/health-*.txt 2>/dev/null | grep -q "errors in current log"'
check "Report contains error log analysis" "$?"

# Check 7: Log rotation executed (old files removed)
docker exec "$CONTAINER" bash -c 'find /var/log/app -name "*.log" -mtime +7 | wc -l | grep -q "^0$"'
check "Old log files were rotated (>7 days removed)" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

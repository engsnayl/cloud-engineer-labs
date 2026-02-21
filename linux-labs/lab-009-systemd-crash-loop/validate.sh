#!/bin/bash
# =============================================================================
# Validation Criteria (from CHALLENGE.md):
#   - api-gateway.service is active (running)
#   - Service has been running for at least 5 seconds without restarting
#   - The unit file has correct ExecStart path
#   - The service responds on its port
# =============================================================================
# =============================================================================
# Validation: Lab 009 - Systemd Crash Loop
# =============================================================================

CONTAINER="lab009-systemd-crash-loop"
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

# Check 1: Service is active
docker exec "$CONTAINER" systemctl is-active api-gateway.service &>/dev/null
check "api-gateway.service is active (running)" "$?"

# Check 2: ExecStart points to correct file
docker exec "$CONTAINER" grep -q "api-gateway.py" /etc/systemd/system/api-gateway.service &>/dev/null
check "Unit file ExecStart references correct filename" "$?"

# Check 3: Service responds
docker exec "$CONTAINER" curl -s http://localhost:3000 &>/dev/null
check "Service responds on port 3000" "$?"

# Check 4: Service has been running >5 seconds (not crash-looping)
runtime=$(docker exec "$CONTAINER" bash -c "systemctl show api-gateway.service --property=ActiveEnterTimestamp | cut -d= -f2" 2>/dev/null)
if [[ -n "$runtime" ]]; then
    start_epoch=$(docker exec "$CONTAINER" date -d "$runtime" +%s 2>/dev/null || echo "0")
    now_epoch=$(docker exec "$CONTAINER" date +%s)
    diff=$((now_epoch - start_epoch))
    [[ "$diff" -gt 5 ]]
    check "Service running for >5 seconds (not crash-looping)" "$?"
else
    check "Service running for >5 seconds (not crash-looping)" "1"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"

[[ "$FAIL" -eq 0 ]]

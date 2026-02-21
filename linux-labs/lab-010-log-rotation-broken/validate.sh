#!/bin/bash
# =============================================================================
# Validation Criteria (from CHALLENGE.md):
#   - No log file in /var/log/app/ is larger than 10MB
#   - Logrotate config for the app exists and is valid
#   - `logrotate -d /etc/logrotate.d/app` runs without errors
#   - At least one rotated log file exists (e.g., app.log.1)
# =============================================================================
# =============================================================================
# Validation: Lab 010 - Log Rotation Broken
# =============================================================================

CONTAINER="lab010-log-rotation-broken"
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

# Check 1: No log file >10MB
big_files=$(docker exec "$CONTAINER" find /var/log/app/ -name "*.log" -size +10M 2>/dev/null | wc -l)
[[ "$big_files" -eq 0 ]]
check "No active log files larger than 10MB" "$?"

# Check 2: Logrotate config is valid
docker exec "$CONTAINER" logrotate -d /etc/logrotate.d/app &>/dev/null
check "Logrotate config passes validation (logrotate -d)" "$?"

# Check 3: Config points to correct path
docker exec "$CONTAINER" grep -q "/var/log/app/" /etc/logrotate.d/app &>/dev/null
check "Logrotate config targets /var/log/app/" "$?"

# Check 4: At least one rotated log exists
rotated=$(docker exec "$CONTAINER" find /var/log/app/ -name "*.log.1*" -o -name "*.log.*.gz" 2>/dev/null | wc -l)
[[ "$rotated" -gt 0 ]]
check "At least one rotated log file exists" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"

[[ "$FAIL" -eq 0 ]]

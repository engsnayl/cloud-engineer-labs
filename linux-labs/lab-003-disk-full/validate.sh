#!/bin/bash
# =============================================================================
# Validation Criteria (from CHALLENGE.md):
#   - Disk usage is below 70%
#   - No single log file is larger than 10MB
#   - A logrotate configuration exists for the application logs
#   - The application log directory exists and is writable
# =============================================================================
# =============================================================================
# Validation: Lab 003 - Disk Full
# =============================================================================

CONTAINER="lab003-disk-full"
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

# Check 1: No single log file over 10MB
large_files=$(docker exec "$CONTAINER" find /var/log/myapp -type f -size +10M 2>/dev/null | wc -l)
[[ "$large_files" -eq 0 ]]
check "No log files larger than 10MB in /var/log/myapp" "$?"

# Check 2: Logrotate config exists for myapp
docker exec "$CONTAINER" test -f /etc/logrotate.d/myapp
check "Logrotate configuration exists for /var/log/myapp" "$?"

# Check 3: App log directory exists and is writable
docker exec "$CONTAINER" test -w /var/log/myapp
check "Application log directory exists and is writable" "$?"

# Check 4: No deleted files still held open (the sneaky one)
held_open=$(docker exec "$CONTAINER" bash -c 'find /proc/*/fd -ls 2>/dev/null | grep deleted | wc -l')
[[ "$held_open" -eq 0 ]]
check "No deleted files still held open by processes" "$?"

# Check 5: Temp files cleaned up
old_temps=$(docker exec "$CONTAINER" find /tmp/reports -name "*.tmp" -type f 2>/dev/null | wc -l)
[[ "$old_temps" -eq 0 ]]
check "Old temp files in /tmp/reports cleaned up" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"

[[ "$FAIL" -eq 0 ]]

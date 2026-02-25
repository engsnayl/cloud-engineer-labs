#!/bin/bash
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

# Check 1: Application log is gone or under 1MB
LOG_SIZE=$(docker exec "$CONTAINER" bash -c 'if [ -f /var/log/myapp/application.log ]; then stat -c%s /var/log/myapp/application.log 2>/dev/null; else echo 0; fi')
[[ "$LOG_SIZE" -lt 1048576 ]]
check "Application log cleaned up (was ~8MB, now under 1MB)" "$?"

# Check 2: Old debug logs removed
OLD_DEBUG=$(docker exec "$CONTAINER" bash -c 'ls /var/log/myapp/debug.log.* 2>/dev/null | wc -l')
[[ "$OLD_DEBUG" -le 1 ]]
check "Old rotated debug logs cleaned up (5 files, now ≤1)" "$?"

# Check 3: Old backup archives cleaned up (at most 1 kept)
OLD_BACKUPS=$(docker exec "$CONTAINER" bash -c 'ls /opt/backups/*.tar.gz 2>/dev/null | wc -l')
[[ "$OLD_BACKUPS" -le 1 ]]
check "Old backup archives cleaned up (7 files, now ≤1)" "$?"

# Check 4: Temp report files cleaned up
TEMP_FILES=$(docker exec "$CONTAINER" bash -c 'ls /tmp/reports/*.tmp 2>/dev/null | wc -l')
[[ "$TEMP_FILES" -eq 0 ]]
check "Stale temp files in /tmp/reports/ removed" "$?"

# Check 5: Application data still exists (didn't delete the wrong things!)
docker exec "$CONTAINER" test -f /var/lib/myapp/config.json
check "Application config preserved (/var/lib/myapp/config.json exists)" "$?"

# Check 6: Application database still exists
docker exec "$CONTAINER" test -f /var/lib/myapp/data/reports.db
check "Application database preserved (/var/lib/myapp/data/reports.db exists)" "$?"

# Check 7: App directory is writable
docker exec "$CONTAINER" bash -c 'touch /var/lib/myapp/test-write && rm /var/lib/myapp/test-write'
check "Application directory is writable" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"

[[ "$FAIL" -eq 0 ]]

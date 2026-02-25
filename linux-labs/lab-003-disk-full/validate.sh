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
LOG_SIZE=$(docker exec "$CONTAINER" bash -c 'if [ -f /data/logs/application.log ]; then stat -c%s /data/logs/application.log 2>/dev/null; else echo 0; fi')
[[ "$LOG_SIZE" -lt 1048576 ]]
check "Application log cleaned up (was ~10MB, now under 1MB)" "$?"

# Check 2: Old debug logs removed
OLD_DEBUG=$(docker exec "$CONTAINER" bash -c 'ls /data/logs/debug.log.* 2>/dev/null | wc -l')
[[ "$OLD_DEBUG" -le 1 ]]
check "Old rotated debug logs cleaned up (5 files, now ≤1)" "$?"

# Check 3: Old backup archives cleaned up (at most 1 kept)
OLD_BACKUPS=$(docker exec "$CONTAINER" bash -c 'ls /data/backups/*.tar.gz 2>/dev/null | wc -l')
[[ "$OLD_BACKUPS" -le 1 ]]
check "Old backup archives cleaned up (7 files, now ≤1)" "$?"

# Check 4: Temp report files cleaned up
TEMP_FILES=$(docker exec "$CONTAINER" bash -c 'ls /data/tmp/*.tmp 2>/dev/null | wc -l')
[[ "$TEMP_FILES" -eq 0 ]]
check "Stale temp files in /data/tmp/ removed" "$?"

# Check 5: Application data still exists (didn't delete the wrong things!)
docker exec "$CONTAINER" test -f /data/myapp/config.json
check "Application config preserved (/data/myapp/config.json exists)" "$?"

# Check 6: Application database still exists
docker exec "$CONTAINER" test -f /data/myapp/data/reports.db
check "Application database preserved (/data/myapp/data/reports.db exists)" "$?"

# Check 7: App directory is writable
docker exec "$CONTAINER" bash -c 'touch /data/myapp/test-write && rm /data/myapp/test-write'
check "Application directory is writable" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"

[[ "$FAIL" -eq 0 ]]

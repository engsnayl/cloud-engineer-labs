#!/bin/bash
# =============================================================================
# Validation: Lab 006 - Cron Not Running
# =============================================================================

CONTAINER="lab006-cron-not-running"
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

# Check 1: Cron daemon is running
docker exec "$CONTAINER" pgrep cron &>/dev/null
check "Cron daemon is running" "$?"

# Check 2: Backup script is executable
docker exec "$CONTAINER" test -x /opt/scripts/backup.sh
check "Backup script is executable" "$?"

# Check 3: Crontab has valid entry (5 fields, not 6)
docker exec "$CONTAINER" bash -c "crontab -l 2>/dev/null | grep -E '^[0-9*]+ [0-9*]+ [0-9*]+ [0-9*]+ [0-9*]+ /opt/scripts/backup.sh'" &>/dev/null
check "Crontab has valid 5-field backup entry" "$?"

# Check 4: Backup file exists (run the script to test)
docker exec "$CONTAINER" bash -c "/opt/scripts/backup.sh && test -f /var/backups/db-backup.sql"
check "Backup script runs and creates output file" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"

[[ "$FAIL" -eq 0 ]]

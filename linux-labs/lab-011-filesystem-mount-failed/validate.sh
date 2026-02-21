#!/bin/bash
# =============================================================================
# Validation Criteria (from CHALLENGE.md):
#   - /data is mounted
#   - Files exist in /data (at least db-data.conf)
#   - /etc/fstab has a valid entry for /data
#   - `df /data` shows it's on a separate filesystem
# =============================================================================
# =============================================================================
# Validation: Lab 011 - Filesystem Mount Failed
# =============================================================================

CONTAINER="lab011-filesystem-mount-failed"
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

# Check 1: /data is mounted
docker exec "$CONTAINER" mountpoint -q /data 2>/dev/null
check "/data is a mounted filesystem" "$?"

# Check 2: Data files exist
docker exec "$CONTAINER" test -f /data/db-data.conf
check "Database config file exists in /data" "$?"

# Check 3: fstab has a valid entry for /data
docker exec "$CONTAINER" grep -q "/data" /etc/fstab &>/dev/null
check "/etc/fstab contains entry for /data" "$?"

# Check 4: Mount is actually on a separate filesystem
data_dev=$(docker exec "$CONTAINER" df /data 2>/dev/null | tail -1 | awk '{print $1}')
root_dev=$(docker exec "$CONTAINER" df / 2>/dev/null | tail -1 | awk '{print $1}')
[[ "$data_dev" != "$root_dev" ]]
check "/data is on a separate filesystem from /" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"

[[ "$FAIL" -eq 0 ]]

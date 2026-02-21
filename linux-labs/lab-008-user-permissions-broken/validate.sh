#!/bin/bash
# =============================================================================
# Validation Criteria (from CHALLENGE.md):
#   - `appuser` can write files to `/opt/data/`
#   - `appuser` can read `/etc/app/config.yml`
#   - `/opt/data` is owned by the `appgroup` group
#   - `appuser` is a member of `appgroup`
# =============================================================================
# =============================================================================
# Validation: Lab 008 - User Permissions Broken
# =============================================================================

CONTAINER="lab008-user-permissions-broken"
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

# Check 1: appuser can write to /opt/data
docker exec "$CONTAINER" su - appuser -c "touch /opt/data/test-write && rm /opt/data/test-write" &>/dev/null
check "appuser can write to /opt/data" "$?"

# Check 2: appuser can read config
docker exec "$CONTAINER" su - appuser -c "cat /etc/app/config.yml" &>/dev/null
check "appuser can read /etc/app/config.yml" "$?"

# Check 3: /opt/data group is appgroup
group=$(docker exec "$CONTAINER" stat -c "%G" /opt/data 2>/dev/null)
[[ "$group" == "appgroup" ]]
check "/opt/data group ownership is appgroup (got: $group)" "$?"

# Check 4: appuser is member of appgroup
docker exec "$CONTAINER" id appuser 2>/dev/null | grep -q "appgroup"
check "appuser is a member of appgroup" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"

[[ "$FAIL" -eq 0 ]]

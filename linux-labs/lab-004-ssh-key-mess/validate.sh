#!/bin/bash
# =============================================================================
# Validation: Lab 004 - SSH Key Mess
# =============================================================================

CONTAINER="lab004-ssh-key-mess"
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

# Check 1: .ssh directory permissions are 700
perms=$(docker exec "$CONTAINER" stat -c "%a" /home/deploy/.ssh 2>/dev/null)
[[ "$perms" == "700" ]]
check ".ssh directory has 700 permissions (got: $perms)" "$?"

# Check 2: authorized_keys permissions are 600
perms=$(docker exec "$CONTAINER" stat -c "%a" /home/deploy/.ssh/authorized_keys 2>/dev/null)
[[ "$perms" == "600" ]]
check "authorized_keys has 600 permissions (got: $perms)" "$?"

# Check 3: Correct ownership
owner=$(docker exec "$CONTAINER" stat -c "%U" /home/deploy/.ssh 2>/dev/null)
[[ "$owner" == "deploy" ]]
check ".ssh owned by deploy user (got: $owner)" "$?"

# Check 4: PubkeyAuthentication enabled in sshd_config
docker exec "$CONTAINER" grep -qE "^PubkeyAuthentication yes" /etc/ssh/sshd_config 2>/dev/null
check "PubkeyAuthentication enabled in sshd_config" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"

[[ "$FAIL" -eq 0 ]]

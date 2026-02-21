#!/bin/bash
# =============================================================================
# Validation Criteria (from CHALLENGE.md):
#   - Application process is listening on port 8080
#   - Health check process is listening on port 8081
#   - `curl localhost:8080` returns HTTP 200
#   - `curl localhost:8081` returns HTTP 200
#   - iptables INPUT chain default policy is DROP (security maintained)
# =============================================================================
# =============================================================================
# Validation: Lab 007 - Firewall Blocking
# =============================================================================

CONTAINER="lab007-firewall-blocking"
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

# Check 1: App responds on 8080
docker exec "$CONTAINER" curl -s -o /dev/null -w "%{http_code}" http://localhost:8080 2>/dev/null | grep -q "200"
check "Application responds HTTP 200 on port 8080" "$?"

# Check 2: Health check responds on 8081
docker exec "$CONTAINER" curl -s -o /dev/null -w "%{http_code}" http://localhost:8081 2>/dev/null | grep -q "200"
check "Health check responds HTTP 200 on port 8081" "$?"

# Check 3: Default INPUT policy is still DROP
docker exec "$CONTAINER" iptables -L INPUT | head -1 | grep -q "DROP"
check "INPUT chain default policy is DROP (security maintained)" "$?"

# Check 4: Loopback traffic is allowed
docker exec "$CONTAINER" iptables -L INPUT -n | grep -q "lo"
check "Loopback interface traffic is allowed" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"

[[ "$FAIL" -eq 0 ]]

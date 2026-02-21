#!/bin/bash
# =============================================================================
# Validation Criteria (from CHALLENGE.md):
#   - Redis process is running and listening on port 6379
#   - `nc -zv redis-server 6379` connects successfully from the app container
#   - /etc/hosts correctly resolves redis-server
#   - Application can reach Redis
# =============================================================================
CONTAINER="lab013-tcp-connection-timeout"
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

docker exec "$CONTAINER" pgrep redis-server &>/dev/null
check "Redis process is running" "$?"

docker exec "$CONTAINER" redis-cli -p 6379 ping 2>/dev/null | grep -q "PONG"
check "Redis responds to PING on port 6379" "$?"

docker exec "$CONTAINER" bash -c "getent hosts redis-server | grep -q '127.0.0.1'" &>/dev/null
check "redis-server resolves to 127.0.0.1" "$?"

docker exec "$CONTAINER" nc -zv -w2 redis-server 6379 &>/dev/null
check "TCP connection to redis-server:6379 succeeds" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

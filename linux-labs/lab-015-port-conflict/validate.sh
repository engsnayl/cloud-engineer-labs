#!/bin/bash
CONTAINER="lab015-port-conflict"
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

docker exec "$CONTAINER" pgrep -f "python3 /opt/api.py" &>/dev/null
check "API service (api.py) is running" "$?"

docker exec "$CONTAINER" curl -s http://localhost:8080 2>/dev/null | grep -q "API OK"
check "curl localhost:8080 returns 'API OK'" "$?"

docker exec "$CONTAINER" bash -c "! pgrep -f 'Stale process'" &>/dev/null
check "Stale process is no longer running" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

#!/bin/bash
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

# Check all containers running
cd /opt/fullstack-app
running=$(docker compose ps --format '{{.Status}}' 2>/dev/null | grep -c "Up")
[[ "$running" -ge 3 ]]
check "All three services are running" "$?"

# Check web responds
curl -s http://localhost:80 2>/dev/null | grep -q "ok"
check "Web service returns response via nginx" "$?"

# Check API is reachable
docker compose exec -T api curl -s http://localhost:5000 2>/dev/null | grep -q "ok"
check "API service responds on port 5000" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

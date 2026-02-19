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

docker image inspect webapp:fixed &>/dev/null
check "Image 'webapp:fixed' exists" "$?"

docker ps --filter "name=webapp" --format '{{.Status}}' | grep -q "Up"
check "webapp container is running" "$?"

docker exec webapp curl -s http://localhost:8080 2>/dev/null | grep -q "ok"
check "App responds on port 8080" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

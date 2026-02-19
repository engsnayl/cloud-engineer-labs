#!/bin/bash
PASS=0
FAIL=0
check() {
    local description="$1"; local result="$2"
    if [[ "$result" == "0" ]]; then echo -e "  ✅  $description"; ((PASS++))
    else echo -e "  ❌  $description"; ((FAIL++)); fi
}
echo "Running validation checks..."
echo ""

docker image inspect webapp:optimised &>/dev/null
check "Image 'webapp:optimised' exists" "$?"

size=$(docker image inspect webapp:optimised --format '{{.Size}}' 2>/dev/null)
size_mb=$((size / 1048576))
[[ "$size_mb" -lt 100 ]] 2>/dev/null
check "Image size is under 100MB (got: ${size_mb}MB)" "$?"

docker ps --filter "name=webapp-opt" --format '{{.Status}}' | grep -q "Up"
check "Container is running" "$?"

docker exec webapp-opt curl -s http://localhost:8080 2>/dev/null | grep -q "optimised"
check "Application responds correctly" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

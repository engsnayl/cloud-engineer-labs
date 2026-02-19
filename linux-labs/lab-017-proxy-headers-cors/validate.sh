#!/bin/bash
CONTAINER="lab017-proxy-headers-cors"
PASS=0
FAIL=0
check() {
    local description="$1"; local result="$2"
    if [[ "$result" == "0" ]]; then echo -e "  ✅  $description"; ((PASS++))
    else echo -e "  ❌  $description"; ((FAIL++)); fi
}
echo "Running validation checks..."
echo ""

docker exec "$CONTAINER" nginx -t &>/dev/null
check "Nginx config passes syntax check" "$?"

# Check CORS header on GET
docker exec "$CONTAINER" curl -sI http://localhost/api/ 2>/dev/null | grep -qi "access-control-allow-origin"
check "GET response includes Access-Control-Allow-Origin" "$?"

# Check OPTIONS returns 204 or 200 with CORS
status=$(docker exec "$CONTAINER" curl -s -o /dev/null -w "%{http_code}" -X OPTIONS http://localhost/api/ 2>/dev/null)
[[ "$status" == "204" || "$status" == "200" ]]
check "OPTIONS pre-flight returns 200/204 (got: $status)" "$?"

# Check backend receives proper headers
response=$(docker exec "$CONTAINER" curl -s -H "X-Forwarded-For: 1.2.3.4" http://localhost/api/ 2>/dev/null)
echo "$response" | grep -qv "Host:missing"
check "Backend receives Host header" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

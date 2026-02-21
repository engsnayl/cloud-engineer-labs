#!/bin/bash
# =============================================================================
# Validation Criteria (from CHALLENGE.md):
#   - Nginx is running as a reverse proxy
#   - Upstream config has all three backends
#   - `curl localhost` returns responses from different backends
#   - Nginx config passes syntax check
# =============================================================================
CONTAINER="lab016-load-balancer-routing"
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

docker exec "$CONTAINER" pgrep nginx &>/dev/null
check "Nginx is running" "$?"

# Check that we get responses from multiple backends
responses=""
for i in $(seq 1 6); do
    r=$(docker exec "$CONTAINER" curl -s http://localhost 2>/dev/null)
    responses="$responses $r"
done
echo "$responses" | grep -q "8001" && echo "$responses" | grep -q "8002"
check "Traffic distributed to multiple backends" "$?"

docker exec "$CONTAINER" grep -c "server 127.0.0.1:80" /etc/nginx/sites-enabled/loadbalancer 2>/dev/null | grep -qE "[3-9]"
check "Upstream block has 3+ backends configured" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

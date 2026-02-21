#!/bin/bash
# =============================================================================
# Validation Criteria (from CHALLENGE.md):
#   - Nginx process is running
#   - Nginx is enabled in systemd
#   - `curl localhost` returns HTTP 200
#   - Nginx config passes `nginx -t`
# =============================================================================
# =============================================================================
# Validation: Lab 001 - Nginx Down
# =============================================================================

CONTAINER="lab001-nginx-down"
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

# Check 1: Nginx config syntax is valid
docker exec "$CONTAINER" nginx -t &>/dev/null
check "Nginx config syntax is valid (nginx -t)" "$?"

# Check 2: Nginx process is running
docker exec "$CONTAINER" pgrep nginx &>/dev/null
check "Nginx process is running" "$?"

# Check 3: Nginx responds on port 80
docker exec "$CONTAINER" curl -s -o /dev/null -w "%{http_code}" http://localhost:80 2>/dev/null | grep -q "200"
check "Nginx returns HTTP 200 on port 80" "$?"

# Check 4: Log directory has correct permissions
docker exec "$CONTAINER" test -w /var/log/nginx
check "Nginx log directory is writable" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"

[[ "$FAIL" -eq 0 ]]

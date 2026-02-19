#!/bin/bash
CONTAINER="lab014-ssl-certificate-expired"
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

docker exec "$CONTAINER" pgrep nginx &>/dev/null
check "Nginx is running" "$?"

docker exec "$CONTAINER" nginx -t &>/dev/null
check "Nginx config passes syntax check" "$?"

docker exec "$CONTAINER" curl -sk https://localhost:443 2>/dev/null | grep -q "Dashboard"
check "HTTPS on port 443 returns dashboard page" "$?"

# Check cert is not expired
docker exec "$CONTAINER" bash -c "openssl x509 -in /etc/nginx/ssl/server.crt -noout -checkend 0" &>/dev/null
check "SSL certificate is not expired" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

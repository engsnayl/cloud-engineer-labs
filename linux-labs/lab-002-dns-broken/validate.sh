#!/bin/bash
# =============================================================================
# Validation: Lab 002 - DNS Broken
# =============================================================================

CONTAINER="lab002-dns-broken"
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

# Check 1: resolv.conf has a valid nameserver (valid IP format)
docker exec "$CONTAINER" grep -qE '^nameserver [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' /etc/resolv.conf
check "/etc/resolv.conf contains a valid nameserver" "$?"

# Check 2: External DNS resolution actually works
docker exec "$CONTAINER" dig +short google.com 2>/dev/null | grep -qE '^[0-9]'
check "External DNS resolution works (dig google.com)" "$?"

# Check 3: payments-api.internal resolves to the correct IP
docker exec "$CONTAINER" getent hosts payments-api.internal 2>/dev/null | grep -q "10.0.1.50"
check "payments-api.internal resolves to 10.0.1.50" "$?"

# Check 4: nsswitch.conf includes dns in the hosts line
docker exec "$CONTAINER" grep -E '^hosts:.*dns' /etc/nsswitch.conf &>/dev/null
check "/etc/nsswitch.conf includes dns lookup for hosts" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"

[[ "$FAIL" -eq 0 ]]

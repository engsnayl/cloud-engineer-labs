#!/bin/bash
# =============================================================================
# Validation: Lab 012 - Swap and Memory Pressure
# =============================================================================

CONTAINER="lab012-swap-memory-pressure"
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

# Check 1: Swap is enabled
swap_total=$(docker exec "$CONTAINER" bash -c "free | grep Swap | awk '{print \$2}'" 2>/dev/null)
[[ "$swap_total" -gt 0 ]] 2>/dev/null
check "Swap is enabled (total: ${swap_total}KB)" "$?"

# Check 2: Memory leak process not running
docker exec "$CONTAINER" bash -c "! pgrep -f 'data.append'" &>/dev/null
check "Memory-leaking process is not running" "$?"

# Check 3: Legitimate app still running
docker exec "$CONTAINER" pgrep -f "python3 /opt/app.py" &>/dev/null
check "Legitimate application is still running" "$?"

# Check 4: Memory usage below 80%
mem_pct=$(docker exec "$CONTAINER" bash -c "free | grep Mem | awk '{printf "%.0f", \$3/\$2 * 100}'" 2>/dev/null)
[[ "$mem_pct" -lt 80 ]] 2>/dev/null
check "Memory usage below 80% (current: ${mem_pct}%)" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"

[[ "$FAIL" -eq 0 ]]

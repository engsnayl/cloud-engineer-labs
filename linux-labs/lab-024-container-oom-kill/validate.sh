#!/bin/bash
# =============================================================================
# Validation Criteria (from CHALLENGE.md):
#   - data-processor container is running
#   - Container has not been OOM killed
#   - Container has a memory limit set (not unlimited)
#   - Memory limit is >= 256MB
# =============================================================================
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

docker ps --filter "name=data-processor" --format '{{.Status}}' | grep -q "Up"
check "data-processor container is running" "$?"

oom=$(docker inspect data-processor --format '{{.State.OOMKilled}}' 2>/dev/null)
[[ "$oom" == "false" ]]
check "Container has not been OOM killed" "$?"

mem_limit=$(docker inspect data-processor --format '{{.HostConfig.Memory}}' 2>/dev/null)
[[ "$mem_limit" -gt 0 ]] 2>/dev/null
check "Container has a memory limit set" "$?"

[[ "$mem_limit" -ge 268435456 ]] 2>/dev/null
check "Memory limit is >= 256MB" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

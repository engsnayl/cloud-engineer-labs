#!/bin/bash
# =============================================================================
# Validation Criteria (from CHALLENGE.md):
#   - Both containers are on the same Docker network
#   - Frontend can resolve backend-api by hostname
#   - Frontend can curl backend-api on port 3000
#   - A custom bridge network (not default) is being used
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

# Check 1: Both containers running
docker ps --filter "name=backend-api" --format '{{.Status}}' | grep -q "Up"
check "backend-api container is running" "$?"

docker ps --filter "name=frontend-web" --format '{{.Status}}' | grep -q "Up"
check "frontend-web container is running" "$?"

# Check 2: Containers share a network
backend_nets=$(docker inspect backend-api --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null)
frontend_nets=$(docker inspect frontend-web --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' 2>/dev/null)
common=$(comm -12 <(echo "$backend_nets" | tr ' ' '\n' | sort) <(echo "$frontend_nets" | tr ' ' '\n' | sort) | grep -v '^$' | head -1)
[[ -n "$common" ]]
check "Containers share a common network" "$?"

# Check 3: Frontend can reach backend
docker exec frontend-web bash -c "curl -s http://backend-api:3000" 2>/dev/null | grep -q "backend-api"
check "Frontend can reach backend-api:3000" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

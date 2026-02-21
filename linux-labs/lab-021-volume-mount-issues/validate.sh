#!/bin/bash
# =============================================================================
# Validation Criteria (from CHALLENGE.md):
#   - Database container is running with a named volume mounted
#   - Data file exists inside the container at /data/customers.db
#   - Container restart preserves the data
#   - `docker volume ls` shows the named volume
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

docker ps --filter "name=database" --format '{{.Status}}' | grep -q "Up"
check "Database container is running" "$?"

docker exec database test -f /data/customers.db 2>/dev/null
check "Data file exists at /data/customers.db" "$?"

docker exec database cat /data/customers.db 2>/dev/null | grep -q "Alice"
check "Data file contains customer records" "$?"

docker inspect database --format '{{range .Mounts}}{{.Name}}{{end}}' 2>/dev/null | grep -q "db-data"
check "Container has db-data volume mounted" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

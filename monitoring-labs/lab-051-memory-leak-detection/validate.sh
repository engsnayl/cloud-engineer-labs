#!/bin/bash
CONTAINER="lab051-memory-leak-detection"
PASS=0
FAIL=0

check() {
    local description="$1"; local result="$2"
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

# 1. Container must be running
docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"
check "Container is running" "$?"

# 2. The leaking process must be dead
docker exec "$CONTAINER" bash -c "! kill -0 \$(cat /tmp/leaky.pid) 2>/dev/null"
check "Leaking process has been killed" "$?"

# 3. The legitimate application must still be alive
docker exec "$CONTAINER" bash -c "kill -0 \$(cat /tmp/legit-app.pid) 2>/dev/null"
check "Legitimate application still running" "$?"

# 4. No rogue python3 process consuming high memory should remain.
# We check that no python3 process has RSS > 50MB. The legit sleep loop
# uses ~10MB; the leaker grows past 50MB within seconds. If anything is
# still over 50MB, either the leaker wasn't killed or a new one started.
HIGH_MEM_PY=$(docker exec "$CONTAINER" bash -c "ps -eo rss,comm | awk '\$2 ~ /python/ && \$1 > 51200 {print}' | wc -l")
[[ "$HIGH_MEM_PY" == "0" ]]
check "No python3 process consuming excessive memory" "$?"

# 5. Incident report must exist
docker exec "$CONTAINER" test -f /tmp/incident-report.txt
check "Incident report created at /tmp/incident-report.txt" "$?"

# 6. Report must have meaningful content (not just a single word)
REPORT_SIZE=$(docker exec "$CONTAINER" bash -c "wc -c < /tmp/incident-report.txt 2>/dev/null || echo 0")
[[ "$REPORT_SIZE" -ge 200 ]]
check "Report has substantive content (>=200 chars)" "$?"

# 7. Report must mention at least 2 of the relevant concepts.
# We require breadth — a real report explains both the symptom AND the cause.
KEYWORD_COUNT=$(docker exec "$CONTAINER" bash -c "grep -ioE 'memory|leak|cache|growing|growth|unbounded|eviction|dictionary|rss' /tmp/incident-report.txt 2>/dev/null | sort -u | wc -l")
[[ "$KEYWORD_COUNT" -ge 2 ]]
check "Report identifies the leak with multiple relevant terms (>=2)" "$?"

# 8. Report should mention some form of resolution or prevention
docker exec "$CONTAINER" grep -qiE "kill|terminat|stop|fix|resolv|prevent|eviction|limit|monitor" /tmp/incident-report.txt 2>/dev/null
check "Report describes resolution or prevention" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [[ "$FAIL" -eq 0 ]]; then
    echo ""
    echo "✅ Lab complete — leak identified, terminated, and documented."
    exit 0
else
    echo ""
    echo "❌ Lab not yet complete — see failed checks above."
    exit 1
fi

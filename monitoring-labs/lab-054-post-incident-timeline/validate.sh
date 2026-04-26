#!/bin/bash
CONTAINER="lab054-post-incident-timeline"
PASS=0
FAIL=0
check() {
    local description="$1"; local result="$2"
    if [[ "$result" == "0" ]]; then echo -e "  ✅  $description"; ((PASS++))
    else echo -e "  ❌  $description"; ((FAIL++)); fi
}
echo "Running validation checks..."
echo ""

docker exec "$CONTAINER" test -f /tmp/post-incident-report.txt
check "Post-incident report exists" "$?"

# Substantive content — guards against trivially-passing one-line reports
LINES=$(docker exec "$CONTAINER" wc -l < /tmp/post-incident-report.txt 2>/dev/null | tr -d ' ')
[[ "${LINES:-0}" -ge 20 ]]
check "Report has substantive content (≥20 lines)" "$?"

docker exec "$CONTAINER" grep -qi "disk\|space\|WAL\|wal" /tmp/post-incident-report.txt 2>/dev/null
check "Report identifies disk space / WAL as root cause" "$?"

docker exec "$CONTAINER" grep -qi "02:00\|timeline" /tmp/post-incident-report.txt 2>/dev/null
check "Report includes timeline with timestamps" "$?"

docker exec "$CONTAINER" grep -qi "payment\|impact\|503\|failed" /tmp/post-incident-report.txt 2>/dev/null
check "Report documents impact on services" "$?"

docker exec "$CONTAINER" grep -qi "resol\|fix\|restart\|cleanup\|archive" /tmp/post-incident-report.txt 2>/dev/null
check "Report describes how the incident was resolved" "$?"

docker exec "$CONTAINER" grep -qi "prevent\|action\|recurrence\|future" /tmp/post-incident-report.txt 2>/dev/null
check "Report includes action items to prevent recurrence" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

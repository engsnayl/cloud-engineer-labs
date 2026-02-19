#!/bin/bash
CONTAINER="lab018-tcpdump-packet-capture"
PASS=0
FAIL=0
check() {
    local description="$1"; local result="$2"
    if [[ "$result" == "0" ]]; then echo -e "  ✅  $description"; ((PASS++))
    else echo -e "  ❌  $description"; ((FAIL++)); fi
}
echo "Running validation checks..."
echo ""

# Check rogue exfil process is gone
docker exec "$CONTAINER" bash -c "! pgrep -f 'EXFIL\|9999.*connect'" &>/dev/null
check "Rogue exfiltration process is stopped" "$?"

# Check listener on 9999 is gone
docker exec "$CONTAINER" bash -c "! ss -tlnp | grep 9999" &>/dev/null
check "No process listening on port 9999" "$?"

# Check legitimate service still running
docker exec "$CONTAINER" curl -s http://localhost:8080 2>/dev/null | grep -q "OK"
check "Legitimate web service still running on 8080" "$?"

# Check incident report exists
docker exec "$CONTAINER" test -f /tmp/incident-report.txt
check "Incident report created at /tmp/incident-report.txt" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

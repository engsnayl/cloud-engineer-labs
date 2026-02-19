#!/bin/bash
PASS=0
FAIL=0
check() {
    local description="$1"; local result="$2"
    if [[ "$result" == "0" ]]; then echo -e "  ✅  $description"; ((PASS++))
    else echo -e "  ❌  $description"; ((FAIL++)); fi
}
echo "Running validation checks..."
echo ""

test -x switch.sh 2>/dev/null
check "switch.sh is executable" "$?"

grep -q "health\|curl\|wget" switch.sh 2>/dev/null
check "Switch script includes health checking" "$?"

grep -q "nginx.*reload\|nginx.*-s" switch.sh 2>/dev/null
check "Switch script reloads nginx" "$?"

grep -q "blue\|green" switch.sh 2>/dev/null
check "Script references blue/green environments" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

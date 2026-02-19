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

grep -q "health\|HEALTH\|curl.*health\|curl.*localhost" deploy.sh 2>/dev/null
check "Deploy script includes health check" "$?"

grep -qi "rollback\|PREVIOUS\|previous\|revert" deploy.sh 2>/dev/null
check "Deploy script includes rollback mechanism" "$?"

grep -qv "latest" deploy.sh 2>/dev/null | grep -q "VERSION\|version\|\$1\|\$TAG"
check "Deploy script uses versioned tags (not just latest)" "0"

grep -q "\$1\|\$VERSION\|\$TAG" deploy.sh 2>/dev/null
check "Deploy script accepts version as parameter" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

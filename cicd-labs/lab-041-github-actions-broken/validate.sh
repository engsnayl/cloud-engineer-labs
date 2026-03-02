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

WORKFLOW=".github/workflows/ci.yml"

# Check no spaces in job names
grep -E "^  [a-z][a-z0-9_-]+:" "$WORKFLOW" &>/dev/null
check "Job names use valid characters (no spaces)" "$?"

# Check GITHUB_ENV usage
grep -q "GITHUB_ENV" "$WORKFLOW"
check "Environment variables use GITHUB_ENV" "$?"

# Check deploy has conditional
grep -A2 "Deploy" "$WORKFLOW" | grep -q "if:"
check "Deploy step has conditional (not running on PRs)" "$?"

# Check job dependency matches
needs_job=$(grep "needs:" "$WORKFLOW" | head -1 | awk '{print $2}')
grep -q "^  ${needs_job}:" "$WORKFLOW"
check "Job dependency name matches actual job" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

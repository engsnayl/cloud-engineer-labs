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

# Check 1: No spaces in ANY job name
# Looks for lines at job indentation level that contain a space before the colon
if grep -E "^  [a-z].* .*:" "$WORKFLOW" &>/dev/null; then
    check "Job names use valid characters (no spaces)" "1"
else
    check "Job names use valid characters (no spaces)" "0"
fi

# Check 2: GITHUB_ENV usage
grep -q "GITHUB_ENV" "$WORKFLOW"
check "Environment variables use GITHUB_ENV" "$?"

# Check 3: Deploy job has if: condition at job level (not step level)
# Looks for if: within the deploy job block, before the steps: keyword
grep -A5 "^  deploy:" "$WORKFLOW" | grep -q "if:"
check "Deploy job has if: condition (not running on PRs)" "$?"

# Check 4: Job dependency references match actual job names
needs_job=$(grep "needs:" "$WORKFLOW" | head -1 | awk '{print $2}')
grep -q "^  ${needs_job}:" "$WORKFLOW"
check "Job dependency name matches actual job" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

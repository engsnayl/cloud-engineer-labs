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

WORKFLOW=".github/workflows/terraform.yml"

grep -q "terraform init" "$WORKFLOW" 2>/dev/null
check "Pipeline includes terraform init" "$?"

grep -q "terraform plan" "$WORKFLOW" 2>/dev/null
check "Pipeline includes terraform plan" "$?"

grep -q "terraform validate\|terraform fmt" "$WORKFLOW" 2>/dev/null
check "Pipeline includes validation/formatting check" "$?"

grep -q "github.ref.*main\|github.event_name.*push" "$WORKFLOW" 2>/dev/null
check "Apply is conditional (not running on PRs)" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

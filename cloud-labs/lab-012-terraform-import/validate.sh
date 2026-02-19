#!/bin/bash
echo "Running terraform validation..."
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
terraform validate &>/dev/null
check "Terraform configuration is valid" "$?"
terraform plan -detailed-exitcode &>/dev/null
plan_exit=$?
[[ "$plan_exit" -ne 1 ]]
check "Terraform plan completes without errors" "$?"
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

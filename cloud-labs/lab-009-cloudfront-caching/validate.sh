#!/bin/bash
# =============================================================================
# Validation: Cloud Lab — Terraform Plan Check
# =============================================================================

echo "Running terraform validation..."
echo ""

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

# Check 1: terraform validate passes
terraform validate &>/dev/null
check "Terraform configuration is valid" "$?"

# Check 2: terraform plan doesn't error
terraform plan -detailed-exitcode &>/dev/null
plan_exit=$?
# Exit code 0 = no changes, 1 = error, 2 = changes present
[[ "$plan_exit" -ne 1 ]]
check "Terraform plan completes without errors" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

#!/bin/bash
# =============================================================================
# Lab 071 — Validate Script
# Checks that all three resources have been successfully imported into state.
# =============================================================================

echo ""
echo "Running Lab 071 validation..."
echo ""

PASS=0
FAIL=0

check() {
  local description="$1"
  local result="$2"
  if [[ "$result" == "0" ]]; then
    echo "  ✅  $description"
    ((PASS++))
  else
    echo "  ❌  $description"
    ((FAIL++))
  fi
}

# --- Check 1: Terraform config is valid ---
terraform validate &>/dev/null
check "Terraform configuration is valid" "$?"

# --- Check 2: State file exists ---
[[ -f terraform.tfstate ]]
check "Terraform state file exists (import has been run)" "$?"

# --- Check 3: VPC is in state ---
terraform state list 2>/dev/null | grep -q "aws_vpc.main"
check "aws_vpc.main is imported into state" "$?"

# --- Check 4: Subnet is in state ---
terraform state list 2>/dev/null | grep -q "aws_subnet.public"
check "aws_subnet.public is imported into state" "$?"

# --- Check 5: Security group is in state ---
terraform state list 2>/dev/null | grep -q "aws_security_group.web"
check "aws_security_group.web is imported into state" "$?"

# --- Check 6: Plan shows no errors (exit code 0 = no changes, 2 = changes pending — both are non-error) ---
terraform plan -detailed-exitcode &>/dev/null
plan_exit=$?
[[ "$plan_exit" -ne 1 ]]
check "Terraform plan completes without errors" "$?"

# --- Check 7: Plan shows no pending changes (exit code 0 = clean) ---
terraform plan -detailed-exitcode &>/dev/null
[[ "$?" -eq 0 ]]
check "Terraform plan shows no changes (config matches imported state)" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  echo "Hint: If checks 3-5 are failing, you haven't imported the resources yet."
  echo "      Run: terraform import aws_vpc.main <vpc-id>"
  echo "      IDs are in .lab-resource-ids if you ran setup.sh"
  echo ""
  echo "Hint: If check 7 is failing, your main.tf config doesn't match the"
  echo "      real resource attributes. Run 'terraform plan' to see the diff."
  echo ""
fi

[[ "$FAIL" -eq 0 ]]

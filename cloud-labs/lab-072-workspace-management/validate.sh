#!/bin/bash
# =============================================================================
# Lab 072 — Terraform Workspace Confusion
# Validation Script
# =============================================================================

set -uo pipefail

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

echo "Running terraform validation..."
echo ""

# -----------------------------------------------------------------------------
# Check 1: terraform validate passes
# -----------------------------------------------------------------------------
terraform validate &>/dev/null
check "Terraform configuration is valid" "$?"

# -----------------------------------------------------------------------------
# Check 2: terraform.workspace is referenced in main.tf
# -----------------------------------------------------------------------------
grep -q "terraform\.workspace" main.tf
check "main.tf references terraform.workspace" "$?"

# -----------------------------------------------------------------------------
# Check 3: locals block maps workspace to config
# -----------------------------------------------------------------------------
grep -q "local\.config\[terraform\.workspace\]" main.tf
check "locals map uses terraform.workspace as lookup key" "$?"

# -----------------------------------------------------------------------------
# Check 4: Environment tag is not hardcoded
# -----------------------------------------------------------------------------
! grep -qE 'Environment\s*=\s*"(staging|production)"' main.tf
check "Environment tag is not hardcoded" "$?"

# -----------------------------------------------------------------------------
# Check 5: instance_type in resource blocks is not hardcoded
# Extracts resource blocks only so the locals map definition doesn't trip this
# -----------------------------------------------------------------------------
resource_block=$(awk '/^resource /,/^}/' main.tf)
! echo "$resource_block" | grep -qE 'instance_type\s*=\s*"t3\.'
check "instance_type in resource blocks is not hardcoded" "$?"

# -----------------------------------------------------------------------------
# Check 6-9: Production workspace plan content
# -----------------------------------------------------------------------------
terraform workspace select production &>/dev/null
prod_plan=$(terraform plan -no-color 2>/dev/null)

echo "$prod_plan" | grep -q 'instance_type\s*=\s*"t3\.large"'
check "Production workspace plans t3.large instance type" "$?"

echo "$prod_plan" | grep -q 'min_size\s*=\s*2'
check "Production workspace plans min_size = 2" "$?"

echo "$prod_plan" | grep -q 'max_size\s*=\s*10'
check "Production workspace plans max_size = 10" "$?"

echo "$prod_plan" | grep -q '"Environment".*=.*"production"'
check "Production workspace plans Environment tag = production" "$?"

# -----------------------------------------------------------------------------
# Check 10-13: Staging workspace plan content
# -----------------------------------------------------------------------------
terraform workspace select staging &>/dev/null
staging_plan=$(terraform plan -no-color 2>/dev/null)

echo "$staging_plan" | grep -q 'instance_type\s*=\s*"t3\.micro"'
check "Staging workspace plans t3.micro instance type" "$?"

echo "$staging_plan" | grep -q 'min_size\s*=\s*1'
check "Staging workspace plans min_size = 1" "$?"

echo "$staging_plan" | grep -q 'max_size\s*=\s*2'
check "Staging workspace plans max_size = 2" "$?"

echo "$staging_plan" | grep -q '"Environment".*=.*"staging"'
check "Staging workspace plans Environment tag = staging" "$?"

# -----------------------------------------------------------------------------
# Return to default workspace
# -----------------------------------------------------------------------------
terraform workspace select default &>/dev/null

# -----------------------------------------------------------------------------
# Results
# -----------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

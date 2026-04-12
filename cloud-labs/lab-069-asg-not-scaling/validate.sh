#!/bin/bash
# =============================================================================
# Validation: Lab 069 — ASG Not Scaling
# =============================================================================
echo "Validating Lab 069..."
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

# Check 1: terraform validate passes (syntax sanity)
terraform validate &>/dev/null
check "Terraform configuration is syntactically valid" "$?"

# Check 2: max_size has been raised above 1
# Pull the max_size value from the aws_autoscaling_group block
max_size=$(awk '/resource "aws_autoscaling_group"/,/^}/' main.tf \
    | grep -E '^\s*max_size\s*=' \
    | head -1 \
    | grep -oE '[0-9]+')

if [[ -n "$max_size" && "$max_size" -gt 1 ]]; then
    check "ASG max_size raised above 1 (found: $max_size)" "0"
else
    check "ASG max_size raised above 1 (found: ${max_size:-none})" "1"
fi

# Check 3: adjustment_type is ChangeInCapacity, not ExactCapacity
adjustment_type=$(awk '/resource "aws_autoscaling_policy"/,/^}/' main.tf \
    | grep -E '^\s*adjustment_type\s*=' \
    | head -1 \
    | grep -oE '"[^"]+"' \
    | tr -d '"')

if [[ "$adjustment_type" == "ChangeInCapacity" ]]; then
    check "Scaling policy adjustment_type set to ChangeInCapacity" "0"
else
    check "Scaling policy adjustment_type set to ChangeInCapacity (found: ${adjustment_type:-none})" "1"
fi

# Check 4: max_size strictly greater than desired_capacity (real headroom)
desired=$(awk '/resource "aws_autoscaling_group"/,/^}/' main.tf \
    | grep -E '^\s*desired_capacity\s*=' \
    | head -1 \
    | grep -oE '[0-9]+')

if [[ -n "$max_size" && -n "$desired" && "$max_size" -gt "$desired" ]]; then
    check "ASG has headroom (max_size > desired_capacity)" "0"
else
    check "ASG has headroom (max_size=${max_size:-?}, desired=${desired:-?})" "1"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

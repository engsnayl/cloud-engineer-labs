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

# --- Terraform-level checks ---
# Note: terraform plan will not catch the runtime bugs in this lab.
# These checks confirm the file is syntactically valid and plannable.

terraform validate &>/dev/null
check "Terraform configuration is valid" "$?"

terraform plan -detailed-exitcode &>/dev/null
plan_exit=$?
[[ "$plan_exit" -ne 1 ]]
check "Terraform plan completes without errors" "$?"

# --- Phase 1: Task definition content checks ---

grep -qE 'network_mode[[:space:]]*=[[:space:]]*"awsvpc"' main.tf
check "network_mode is set to awsvpc (Fargate requirement)" "$?"

grep -qE '^[[:space:]]*execution_role_arn[[:space:]]*=' main.tf
check "execution_role_arn is set (uncommented)" "$?"

grep -qE '^[[:space:]]*cpu[[:space:]]*=[[:space:]]*"?[0-9]+"?' main.tf
check "cpu is set at task definition level" "$?"

grep -qE '^[[:space:]]*memory[[:space:]]*=[[:space:]]*"?[0-9]+"?' main.tf
check "memory is set at task definition level" "$?"

# --- Phase 2: Image and networking checks ---

! grep -q 'image[[:space:]]*=[[:space:]]*"payment-api:latest"' main.tf
check "container image is no longer the placeholder payment-api:latest" "$?"

grep -q 'aws_internet_gateway' main.tf
check "Internet Gateway resource defined" "$?"

grep -q 'aws_nat_gateway' main.tf
check "NAT Gateway resource defined" "$?"

grep -q 'aws_eip' main.tf
check "Elastic IP for NAT Gateway defined" "$?"

grep -qE 'aws_route_table[^_]' main.tf
check "Route table resources defined" "$?"

grep -q 'aws_route_table_association' main.tf
check "Route table associations defined" "$?"

# --- Phase 3: Production-readiness checks ---

grep -q 'portMappings' main.tf
check "portMappings defined in container definition" "$?"

grep -q 'logConfiguration' main.tf
check "logConfiguration defined in container definition" "$?"

grep -q 'aws_cloudwatch_log_group' main.tf
check "CloudWatch log group resource defined" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

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

terraform validate &>/dev/null
check "Terraform configuration is valid" "$?"

terraform plan -detailed-exitcode &>/dev/null
plan_exit=$?
[[ "$plan_exit" -ne 1 ]]
check "Terraform plan completes without errors" "$?"

# --- Task definition content checks ---
# terraform plan will not catch missing portMappings or logConfiguration,
# so we grep main.tf directly for the required fixes.

grep -qE 'network_mode[[:space:]]*=[[:space:]]*"awsvpc"' main.tf
check "network_mode is set to awsvpc (Fargate requirement)" "$?"

grep -qE '^[[:space:]]*execution_role_arn[[:space:]]*=' main.tf
check "execution_role_arn is set (uncommented)" "$?"

grep -qE '^[[:space:]]*cpu[[:space:]]*=[[:space:]]*"?[0-9]+"?' main.tf
check "cpu is set at task definition level" "$?"

grep -qE '^[[:space:]]*memory[[:space:]]*=[[:space:]]*"?[0-9]+"?' main.tf
check "memory is set at task definition level" "$?"

grep -q 'portMappings' main.tf
check "portMappings defined in container definition" "$?"

grep -q 'logConfiguration' main.tf
check "logConfiguration defined in container definition" "$?"

grep -q 'aws_cloudwatch_log_group' main.tf
check "CloudWatch log group resource defined" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

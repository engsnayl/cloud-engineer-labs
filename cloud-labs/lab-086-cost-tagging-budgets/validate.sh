#!/bin/bash
# Validates all 5 bug fixes for Lab 086 — Cost Tagging & Budgets
# Tests actual config state, not just terraform syntax

echo "Running Lab 086 validation..."
echo ""

PASS=0; FAIL=0

check() {
    local d="$1" r="$2"
    if [[ "$r" == "0" ]]; then
        echo -e "  ✅  $d"
        ((PASS++))
    else
        echo -e "  ❌  $d"
        ((FAIL++))
    fi
}

# --- Baseline: Terraform must be syntactically valid ---
terraform validate &>/dev/null
check "Terraform configuration is valid" "$?"

terraform plan -detailed-exitcode &>/dev/null
plan_exit=$?
[[ "$plan_exit" -ne 1 ]]
check "Terraform plan completes without errors" "$?"

# --- Bug 1: default_tags must be set in provider block ---
grep -Pzo '(?s)provider\s+"aws"\s*\{[^}]*default_tags\s*\{' main.tf &>/dev/null
check "Provider has default_tags block configured" "$?"

# Confirm default_tags contains the expected keys
for tag in Environment Project Team CostCentre ManagedBy; do
    grep -Pzo "(?s)default_tags\s*\{[^}]*${tag}\s*=" main.tf &>/dev/null
    check "default_tags includes ${tag}" "$?"
done

# --- Bug 2: Individual resources must reference local.common_tags ---
# VPC
grep -Pzo '(?s)resource\s+"aws_vpc"\s+"main"\s*\{[^}]*tags\s*=\s*local\.common_tags' main.tf &>/dev/null
check "aws_vpc.main has tags = local.common_tags" "$?"

# Subnet
grep -Pzo '(?s)resource\s+"aws_subnet"\s+"public"\s*\{[^}]*tags\s*=\s*local\.common_tags' main.tf &>/dev/null
check "aws_subnet.public has tags = local.common_tags" "$?"

# S3 bucket
grep -Pzo '(?s)resource\s+"aws_s3_bucket"\s+"app_assets"\s*\{[^}]*tags\s*=\s*local\.common_tags' main.tf &>/dev/null
check "aws_s3_bucket.app_assets has tags = local.common_tags" "$?"

# --- Bug 3: Budget must have at least one notification block ---
grep -Pzo '(?s)resource\s+"aws_budgets_budget"\s+"monthly"\s*\{.*?notification\s*\{' main.tf &>/dev/null
check "aws_budgets_budget.monthly has notification block" "$?"

# Confirm notification has an email subscriber
grep -Pzo '(?s)notification\s*\{[^}]*subscriber_email_addresses' main.tf &>/dev/null
check "Budget notification has subscriber_email_addresses" "$?"

# Check for both 80% and 100% thresholds (progressive alerting)
grep -Pzo '(?s)notification\s*\{[^}]*threshold\s*=\s*80' main.tf &>/dev/null
check "Budget has 80% threshold notification" "$?"

grep -Pzo '(?s)notification\s*\{[^}]*threshold\s*=\s*100' main.tf &>/dev/null
check "Budget has 100% threshold notification" "$?"

# --- Bug 4: Billing alarm threshold must be non-zero and match budget ---
alarm_threshold=$(grep -Pzo '(?s)resource\s+"aws_cloudwatch_metric_alarm"\s+"billing"\s*\{[^}]*threshold\s*=\s*\K\d+' main.tf 2>/dev/null | tr -d '\0')

if [[ -n "$alarm_threshold" && "$alarm_threshold" != "0" ]]; then
    check "Billing alarm threshold is non-zero (got: $alarm_threshold)" "0"
else
    check "Billing alarm threshold is non-zero (got: ${alarm_threshold:-unset})" "1"
fi

# Confirm alarm threshold matches budget limit (10000)
if [[ "$alarm_threshold" == "10000" ]]; then
    check "Billing alarm threshold matches budget limit (10000)" "0"
else
    check "Billing alarm threshold matches budget limit (expected 10000, got $alarm_threshold)" "1"
fi

# --- Bug 5: SNS topic must be tagged ---
grep -Pzo '(?s)resource\s+"aws_sns_topic"\s+"billing_alerts"\s*\{[^}]*tags\s*=\s*local\.common_tags' main.tf &>/dev/null
check "aws_sns_topic.billing_alerts has tags = local.common_tags" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [[ "$FAIL" -eq 0 ]]; then
    exit 0
else
    exit 1
fi

#!/bin/bash
# Validates all 6 bug fixes for Lab 086 — Cost Tagging & Budgets
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
grep -Pzo '(?s)resource\s+"aws_vpc"\s+"main"\s*\{[^}]*tags\s*=\s*local\.common_tags' main.tf &>/dev/null
check "aws_vpc.main has tags = local.common_tags" "$?"

grep -Pzo '(?s)resource\s+"aws_subnet"\s+"public"\s*\{[^}]*tags\s*=\s*local\.common_tags' main.tf &>/dev/null
check "aws_subnet.public has tags = local.common_tags" "$?"

# S3 bucket — use awk-style block extraction since S3 name has ${...} interpolation
awk '/resource "aws_s3_bucket" "app_assets"/,/^}/' main.tf | grep -q "tags[[:space:]]*=[[:space:]]*local\.common_tags"
check "aws_s3_bucket.app_assets has tags = local.common_tags" "$?"

# --- Bug 3: Budget must have at least one notification block ---
grep -Pzo '(?s)resource\s+"aws_budgets_budget"\s+"monthly"\s*\{.*?notification\s*\{' main.tf &>/dev/null
check "aws_budgets_budget.monthly has notification block" "$?"

grep -Pzo '(?s)notification\s*\{[^}]*subscriber_email_addresses' main.tf &>/dev/null
check "Budget notification has subscriber_email_addresses" "$?"

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

if [[ "$alarm_threshold" == "10000" ]]; then
    check "Billing alarm threshold matches budget limit (10000)" "0"
else
    check "Billing alarm threshold matches budget limit (expected 10000, got $alarm_threshold)" "1"
fi

# --- Bug 5: SNS topic must be tagged ---
grep -Pzo '(?s)resource\s+"aws_sns_topic"\s+"billing_alerts"\s*\{[^}]*tags\s*=\s*local\.common_tags' main.tf &>/dev/null
check "aws_sns_topic.billing_alerts has tags = local.common_tags" "$?"

# --- Bug 6: Billing alarm must target us-east-1 (where AWS/Billing metrics publish) ---
# Using AWS provider v6 per-resource region attribute (more reliable than aliased provider
# for aws_cloudwatch_metric_alarm — known issue #7371, #1553 in terraform-provider-aws).
grep -Pzo '(?s)resource\s+"aws_cloudwatch_metric_alarm"\s+"billing"\s*\{[^}]*region\s*=\s*"us-east-1"' main.tf &>/dev/null
check "Billing alarm has region = \"us-east-1\" attribute" "$?"

# Live state checks: only run if AWS credentials are available
if aws sts get-caller-identity &>/dev/null; then
    # Check alarm exists in us-east-1
    alarm_in_use=$(aws cloudwatch describe-alarms \
        --alarm-names monthly-billing-alarm \
        --region us-east-1 \
        --query 'MetricAlarms[*].AlarmName' \
        --output text 2>/dev/null)

    if [[ -n "$alarm_in_use" ]]; then
        check "[LIVE] Billing alarm deployed in us-east-1" "0"
    else
        check "[LIVE] Billing alarm deployed in us-east-1 (not found — did you apply?)" "1"
    fi

    # Check alarm is NOT in eu-west-2
    alarm_in_euw2=$(aws cloudwatch describe-alarms \
        --alarm-names monthly-billing-alarm \
        --region eu-west-2 \
        --query 'MetricAlarms[*].AlarmName' \
        --output text 2>/dev/null)

    if [[ -z "$alarm_in_euw2" ]]; then
        check "[LIVE] Billing alarm not in eu-west-2" "0"
    else
        check "[LIVE] Billing alarm still in eu-west-2" "1"
    fi
else
    echo "  ℹ️   AWS credentials not configured — skipping live state checks"
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"

if [[ "$FAIL" -eq 0 ]]; then
    exit 0
else
    exit 1
fi

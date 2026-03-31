#!/bin/bash

# =============================================================================
# Lab 091 Validation — ClickOps Reverse Engineering
# =============================================================================

PASS=0
FAIL=0
TOTAL=0

REGION="eu-west-2"
TAG_KEY="Project"
TAG_VALUE="clickops-lab-091"

check() {
    local description="$1"
    local result="$2"
    ((TOTAL++))
    if [[ "$result" == "0" ]]; then
        echo -e "  \033[32m✅  $description\033[0m"
        ((PASS++))
    else
        echo -e "  \033[31m❌  $description\033[0m"
        ((FAIL++))
    fi
}

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Lab 091: ClickOps Reverse Engineering — Validation    ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

MAIN="main.tf"

if [[ ! -f "$MAIN" ]]; then
    echo "  ❌  main.tf not found — have you written your Terraform code yet?"
    exit 1
fi

# -------------------------------------------------------------------------
# 1. Terraform files exist and are valid
# -------------------------------------------------------------------------
echo "── Terraform Code ──"

terraform validate &>/dev/null
check "terraform validate passes" "$?"

# -------------------------------------------------------------------------
# 2. State file exists with imported resources
# -------------------------------------------------------------------------
echo ""
echo "── Terraform State ──"

if [[ -f "terraform.tfstate" ]]; then
    check "terraform.tfstate exists" "0"
else
    check "terraform.tfstate exists" "1"
fi

# Count resources in state
STATE_COUNT=$(terraform state list 2>/dev/null | wc -l)
if [[ "$STATE_COUNT" -ge 7 ]]; then
    check "At least 7 resources imported into state (found $STATE_COUNT)" "0"
else
    check "At least 7 resources imported into state (found $STATE_COUNT)" "1"
fi

# -------------------------------------------------------------------------
# 3. Key resources are in state
# -------------------------------------------------------------------------
echo ""
echo "── Resource Coverage ──"

terraform state list 2>/dev/null | grep -q 'aws_vpc\.'
check "VPC imported" "$?"

terraform state list 2>/dev/null | grep -q 'aws_subnet\.'
check "At least one subnet imported" "$?"

terraform state list 2>/dev/null | grep -q 'aws_internet_gateway\.'
check "Internet Gateway imported" "$?"

terraform state list 2>/dev/null | grep -q 'aws_security_group\.'
check "Security Group imported" "$?"

terraform state list 2>/dev/null | grep -q 'aws_s3_bucket\.'
check "S3 Bucket imported" "$?"

terraform state list 2>/dev/null | grep -q 'aws_iam_role\.'
check "IAM Role imported" "$?"

terraform state list 2>/dev/null | grep -q 'aws_route_table\.'
check "Route Table imported" "$?"

# -------------------------------------------------------------------------
# 4. Plan shows no changes (code matches reality)
# -------------------------------------------------------------------------
echo ""
echo "── Code-Reality Alignment ──"

PLAN_OUTPUT=$(terraform plan -no-color -detailed-exitcode 2>&1)
PLAN_EXIT=$?

if [[ "$PLAN_EXIT" -eq 0 ]]; then
    check "terraform plan shows NO changes (code matches reality)" "0"
elif [[ "$PLAN_EXIT" -eq 2 ]]; then
    CHANGES=$(echo "$PLAN_OUTPUT" | grep -oP '\d+ to change' | grep -oP '\d+')
    ADDS=$(echo "$PLAN_OUTPUT" | grep -oP '\d+ to add' | grep -oP '\d+')
    DESTROYS=$(echo "$PLAN_OUTPUT" | grep -oP '\d+ to destroy' | grep -oP '\d+')
    check "terraform plan shows NO changes (found: +${ADDS:-0} ~${CHANGES:-0} -${DESTROYS:-0} — adjust your .tf code)" "1"
else
    check "terraform plan shows NO changes (plan errored — check your code)" "1"
fi

# -------------------------------------------------------------------------
# 5. Resources match what was created
# -------------------------------------------------------------------------
echo ""
echo "── Reality Check (AWS CLI) ──"

ACTUAL_VPC=$(aws ec2 describe-vpcs \
    --filters "Name=tag:$TAG_KEY,Values=$TAG_VALUE" \
    --region "$REGION" \
    --query 'Vpcs[0].VpcId' \
    --output text 2>/dev/null)

STATE_VPC=$(terraform state show 'aws_vpc.main' 2>/dev/null | grep '^  id' | awk '{print $3}' | tr -d '"' || \
    terraform state show 'aws_vpc.startup' 2>/dev/null | grep '^  id' | awk '{print $3}' | tr -d '"' || true)

if [[ -n "$ACTUAL_VPC" && "$ACTUAL_VPC" != "None" && "$ACTUAL_VPC" == "$STATE_VPC" ]]; then
    check "VPC in state matches actual AWS VPC ($ACTUAL_VPC)" "0"
elif [[ -n "$ACTUAL_VPC" && "$ACTUAL_VPC" != "None" ]]; then
    check "VPC in state matches actual AWS VPC (state has '$STATE_VPC', AWS has '$ACTUAL_VPC')" "1"
else
    check "VPC in state matches actual AWS VPC (could not find VPC in AWS — was setup.sh run?)" "1"
fi

# -------------------------------------------------------------------------
# Results
# -------------------------------------------------------------------------
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ "$FAIL" -eq 0 ]]; then
    echo ""
    echo "  ✅  ALL $TOTAL CHECKS PASSED"
    echo ""
    echo "  Excellent — you've successfully reverse-engineered"
    echo "  a ClickOps environment and brought it under IaC."
    echo "  This is one of the most common consulting engagements"
    echo "  in cloud engineering."
    echo ""
    echo "  Don't forget to run ./teardown.sh to destroy resources."
    echo ""
else
    echo ""
    echo "  ⚠️   $PASS of $TOTAL checks passed ($FAIL remaining)"
    echo ""
    echo "  Keep going — review HINTS.md if you're stuck."
    echo "  The goal is terraform plan showing 'No changes.'"
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

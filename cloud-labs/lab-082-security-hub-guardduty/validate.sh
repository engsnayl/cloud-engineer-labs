#!/bin/bash
# =============================================================================
# Validation: Lab 082 — Security Hub & GuardDuty Misconfigured
# =============================================================================
# This script verifies that the security monitoring pipeline is correctly
# configured end-to-end. It queries AWS directly rather than just checking
# Terraform syntax, because all five bugs in this lab produce valid HCL.
# =============================================================================

echo "Running Lab 082 validation..."
echo ""

PASS=0
FAIL=0
REGION="${AWS_REGION:-eu-west-2}"

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

# -----------------------------------------------------------------------------
# Prerequisite: Terraform must have been applied
# -----------------------------------------------------------------------------
if [[ ! -f terraform.tfstate ]] && [[ ! -d .terraform ]]; then
    echo "  ⚠️   No Terraform state found. Run 'terraform apply' first."
    exit 1
fi

# -----------------------------------------------------------------------------
# Check 1: Terraform syntax is valid (kept for baseline)
# -----------------------------------------------------------------------------
terraform validate &>/dev/null
check "Terraform configuration is syntactically valid" "$?"

# -----------------------------------------------------------------------------
# Check 2: GuardDuty detector exists AND is enabled
# -----------------------------------------------------------------------------
DETECTOR_ID=$(aws guardduty list-detectors \
    --region "$REGION" \
    --query 'DetectorIds[0]' \
    --output text 2>/dev/null)

if [[ -z "$DETECTOR_ID" ]] || [[ "$DETECTOR_ID" == "None" ]]; then
    check "GuardDuty detector exists" "1"
    check "GuardDuty detector is ENABLED" "1"
    check "GuardDuty Kubernetes audit logs enabled" "1"
else
    check "GuardDuty detector exists" "0"

    DETECTOR_STATUS=$(aws guardduty get-detector \
        --detector-id "$DETECTOR_ID" \
        --region "$REGION" \
        --query 'Status' \
        --output text 2>/dev/null)

    [[ "$DETECTOR_STATUS" == "ENABLED" ]]
    check "GuardDuty detector is ENABLED (not just deployed)" "$?"

    K8S_STATUS=$(aws guardduty get-detector \
        --detector-id "$DETECTOR_ID" \
        --region "$REGION" \
        --query 'DataSources.Kubernetes.AuditLogs.Status' \
        --output text 2>/dev/null)

    [[ "$K8S_STATUS" == "ENABLED" ]]
    check "GuardDuty Kubernetes audit logs are ENABLED" "$?"
fi

# -----------------------------------------------------------------------------
# Check 3: Security Hub is subscribed to GuardDuty findings
# -----------------------------------------------------------------------------
GUARDDUTY_PRODUCT_ARN="arn:aws:securityhub:${REGION}::product/aws/guardduty"

aws securityhub list-enabled-products-for-import \
    --region "$REGION" \
    --query "ProductSubscriptions[?contains(@, 'guardduty')]" \
    --output text 2>/dev/null | grep -q "guardduty"
check "Security Hub is subscribed to GuardDuty findings" "$?"

# -----------------------------------------------------------------------------
# Check 4: EventBridge rule filters on CRITICAL and HIGH severity
# -----------------------------------------------------------------------------
EVENT_PATTERN=$(aws events describe-rule \
    --name "security-hub-critical-findings" \
    --region "$REGION" \
    --query 'EventPattern' \
    --output text 2>/dev/null)

if [[ -z "$EVENT_PATTERN" ]] || [[ "$EVENT_PATTERN" == "None" ]]; then
    check "EventBridge rule 'security-hub-critical-findings' exists" "1"
    check "EventBridge rule filters on CRITICAL severity" "1"
    check "EventBridge rule filters on HIGH severity" "1"
    check "EventBridge rule does NOT filter only on INFORMATIONAL" "1"
else
    check "EventBridge rule 'security-hub-critical-findings' exists" "0"

    echo "$EVENT_PATTERN" | grep -q '"CRITICAL"'
    check "EventBridge rule filters on CRITICAL severity" "$?"

    echo "$EVENT_PATTERN" | grep -q '"HIGH"'
    check "EventBridge rule filters on HIGH severity" "$?"

    # The original bug: only INFORMATIONAL was matched
    if echo "$EVENT_PATTERN" | grep -q '"INFORMATIONAL"' && \
       ! echo "$EVENT_PATTERN" | grep -q '"CRITICAL"'; then
        check "EventBridge rule does NOT filter only on INFORMATIONAL" "1"
    else
        check "EventBridge rule does NOT filter only on INFORMATIONAL" "0"
    fi
fi

# -----------------------------------------------------------------------------
# Check 5: SNS topic policy allows EventBridge to publish
# -----------------------------------------------------------------------------
SNS_TOPIC_ARN=$(aws sns list-topics \
    --region "$REGION" \
    --query "Topics[?contains(TopicArn, 'security-alerts')].TopicArn | [0]" \
    --output text 2>/dev/null)

if [[ -z "$SNS_TOPIC_ARN" ]] || [[ "$SNS_TOPIC_ARN" == "None" ]]; then
    check "SNS topic 'security-alerts' exists" "1"
    check "SNS topic policy allows events.amazonaws.com" "1"
    check "SNS topic policy does NOT use s3.amazonaws.com principal" "1"
else
    check "SNS topic 'security-alerts' exists" "0"

    SNS_POLICY=$(aws sns get-topic-attributes \
        --topic-arn "$SNS_TOPIC_ARN" \
        --region "$REGION" \
        --query 'Attributes.Policy' \
        --output text 2>/dev/null)

    echo "$SNS_POLICY" | grep -q "events.amazonaws.com"
    check "SNS topic policy allows events.amazonaws.com" "$?"

    # The original bug: s3.amazonaws.com was the principal
    if echo "$SNS_POLICY" | grep -q "s3.amazonaws.com" && \
       ! echo "$SNS_POLICY" | grep -q "events.amazonaws.com"; then
        check "SNS topic policy does NOT use wrong service principal" "1"
    else
        check "SNS topic policy does NOT use wrong service principal" "0"
    fi
fi

# -----------------------------------------------------------------------------
# Results
# -----------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
    echo "🎉 All checks passed — the security pipeline is correctly configured."
    echo ""
    echo "Optional: generate a sample finding to verify end-to-end delivery:"
    echo "  aws guardduty create-sample-findings \\"
    echo "    --detector-id $DETECTOR_ID \\"
    echo "    --finding-types Backdoor:EC2/C\\&CActivity.B!DNS \\"
    echo "    --region $REGION"
fi

[[ "$FAIL" -eq 0 ]]

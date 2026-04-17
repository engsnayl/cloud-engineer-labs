#!/bin/bash
# =============================================================================
# Lab 079 — CloudWatch Alarms Misconfigured
# validate.sh — Verify all four bugs are actually fixed in AWS
# =============================================================================
# This script checks real deployed AWS resource values via the CLI.
# It will FAIL on the broken config and PASS only when all four bugs are fixed.
# Run after: terraform apply
# =============================================================================

REGION="eu-west-2"
PASS=0
FAIL=0

echo ""
echo "=============================================="
echo "  Lab 079 — Validation"
echo "=============================================="
echo ""

check() {
  local description="$1"
  local result="$2"  # 0 = pass, non-zero = fail
  if [[ "$result" == "0" ]]; then
    echo "  ✅  $description"
    ((PASS++))
  else
    echo "  ❌  $description"
    ((FAIL++))
  fi
}

# -----------------------------------------------------------------------------
# Pre-flight: confirm Terraform state and AWS access
# -----------------------------------------------------------------------------
echo "Pre-flight checks..."

terraform validate &>/dev/null
check "Terraform configuration is valid" "$?"

if ! aws sts get-caller-identity --region "$REGION" &>/dev/null; then
  echo "  ❌  Cannot reach AWS — check credentials and region"
  exit 1
fi
echo "  ✅  AWS credentials valid"
echo ""

# -----------------------------------------------------------------------------
# Fetch alarm configs from AWS
# -----------------------------------------------------------------------------
echo "Fetching alarm configurations from AWS..."

CPU_ALARM=$(aws cloudwatch describe-alarms \
  --alarm-names "high-cpu" \
  --region "$REGION" \
  --output json 2>/dev/null)

STATUS_ALARM=$(aws cloudwatch describe-alarms \
  --alarm-names "status-check-failed" \
  --region "$REGION" \
  --output json 2>/dev/null)

CPU_COUNT=$(echo "$CPU_ALARM" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('MetricAlarms',[])))" 2>/dev/null)
STATUS_COUNT=$(echo "$STATUS_ALARM" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('MetricAlarms',[])))" 2>/dev/null)

if [[ "$CPU_COUNT" -lt 1 ]]; then
  echo "  ❌  Alarm 'high-cpu' not found in $REGION — has terraform apply been run?"
  exit 1
fi
if [[ "$STATUS_COUNT" -lt 1 ]]; then
  echo "  ❌  Alarm 'status-check-failed' not found in $REGION — has terraform apply been run?"
  exit 1
fi

echo "  ✅  Both alarms found in AWS"
echo ""

# -----------------------------------------------------------------------------
# Helper: extract fields
# -----------------------------------------------------------------------------
cpu_field() {
  echo "$CPU_ALARM" | python3 -c "import sys,json; d=json.load(sys.stdin)['MetricAlarms'][0]; print($1)" 2>/dev/null
}

status_field() {
  echo "$STATUS_ALARM" | python3 -c "import sys,json; d=json.load(sys.stdin)['MetricAlarms'][0]; print($1)" 2>/dev/null
}

# -----------------------------------------------------------------------------
# Bug 1: CPU alarm comparison operator
# -----------------------------------------------------------------------------
echo "Bug 1 — CPU alarm comparison operator..."

CPU_OPERATOR=$(cpu_field "d['ComparisonOperator']")
[[ "$CPU_OPERATOR" == "GreaterThanThreshold" ]]
check "high-cpu uses GreaterThanThreshold (not LessThanThreshold)" "$?"

# -----------------------------------------------------------------------------
# Bug 2: CPU alarm has alarm actions
# -----------------------------------------------------------------------------
echo ""
echo "Bug 2 — CPU alarm notification target..."

CPU_ACTIONS=$(cpu_field "len(d.get('AlarmActions', []))")
[[ "$CPU_ACTIONS" -gt 0 ]]
check "high-cpu has at least one alarm_action configured" "$?"

CPU_ACTION_ARN=$(cpu_field "d.get('AlarmActions', [''])[0]" 2>/dev/null)
[[ "$CPU_ACTION_ARN" == arn:aws:sns:* ]]
check "high-cpu alarm_action points to an SNS topic (arn:aws:sns:...)" "$?"

# -----------------------------------------------------------------------------
# Bug 3: CPU alarm has dimensions
# -----------------------------------------------------------------------------
echo ""
echo "Bug 3 — CPU alarm dimensions..."

CPU_DIM_COUNT=$(cpu_field "len(d.get('Dimensions', []))")
[[ "$CPU_DIM_COUNT" -gt 0 ]]
check "high-cpu has at least one dimension defined" "$?"

CPU_DIM_NAME=$(cpu_field "d['Dimensions'][0]['Name']" 2>/dev/null)
[[ "$CPU_DIM_NAME" == "InstanceId" ]]
check "high-cpu dimension key is 'InstanceId'" "$?"

CPU_DIM_VALUE=$(cpu_field "d['Dimensions'][0]['Value']" 2>/dev/null)
[[ "$CPU_DIM_VALUE" == i-* ]]
check "high-cpu InstanceId value looks like a real instance ID (i-...)" "$?"

[[ "$CPU_DIM_VALUE" != "i-placeholder" ]]
check "high-cpu InstanceId is not the placeholder string 'i-placeholder'" "$?"

# Cross-check: does this instance actually exist?
INSTANCE_STATE=$(aws ec2 describe-instances \
  --instance-ids "$CPU_DIM_VALUE" \
  --region "$REGION" \
  --query "Reservations[0].Instances[0].State.Name" \
  --output text 2>/dev/null)
[[ "$INSTANCE_STATE" == "running" ]]
check "high-cpu InstanceId references a running EC2 instance" "$?"

# -----------------------------------------------------------------------------
# Bug 4: Status check alarm period
# -----------------------------------------------------------------------------
echo ""
echo "Bug 4 — Status check alarm period..."

STATUS_PERIOD=$(status_field "d['Period']")
[[ "$STATUS_PERIOD" -le 60 ]]
check "status-check-failed uses period <= 60 seconds (was 3600)" "$?"

# Bonus: check status alarm dimension is also fixed
STATUS_DIM_VALUE=$(status_field "d['Dimensions'][0]['Value']" 2>/dev/null)

[[ "$STATUS_DIM_VALUE" == i-* ]]
check "status-check-failed InstanceId looks like a real instance ID" "$?"

[[ "$STATUS_DIM_VALUE" != "i-placeholder" ]]
check "status-check-failed InstanceId is not the placeholder 'i-placeholder'" "$?"

# -----------------------------------------------------------------------------
# Results
# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
echo "  Results: $PASS passed, $FAIL failed"
echo "=============================================="
echo ""

if [[ "$FAIL" -eq 0 ]]; then
  echo "  All checks passed. Lab 079 complete."
  echo ""
  exit 0
else
  echo "  $FAIL check(s) still failing. Review the output above"
  echo "  and check your main.tf — then re-run: terraform apply"
  echo ""
  exit 1
fi

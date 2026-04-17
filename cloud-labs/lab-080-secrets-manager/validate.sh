#!/bin/bash

echo ""
echo "=========================================="
echo "  Lab 080 — Validating your solution"
echo "=========================================="
echo ""

PASS=0
FAIL=0
REGION="eu-west-1"
SECRET_ID="production/db-password"

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

# ── 1. Terraform config is valid ───────────────────────────────────────────────
terraform validate > /dev/null 2>&1
check "Terraform configuration is valid" "$?"

# ── 2. Terraform plan shows no errors and nothing left to change ───────────────
# Exit code 0 = success, nothing to change
# Exit code 2 = success, changes pending (means apply hasn't been run yet)
# Exit code 1 = error
terraform plan -detailed-exitcode > /dev/null 2>&1
plan_exit=$?
if [[ "$plan_exit" -eq 0 ]]; then
  check "Terraform plan: no pending changes (apply was run)" "0"
elif [[ "$plan_exit" -eq 2 ]]; then
  check "Terraform plan: changes are pending — have you run terraform apply?" "1"
else
  check "Terraform plan completes without errors" "1"
fi

# ── 3. Secret exists in AWS ────────────────────────────────────────────────────
aws secretsmanager describe-secret \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  > /dev/null 2>&1
check "Secret '$SECRET_ID' exists in AWS" "$?"

# ── 4. Rotation is enabled on the secret ──────────────────────────────────────
ROTATION_ENABLED=$(aws secretsmanager describe-secret \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --query 'RotationEnabled' \
  --output text 2>/dev/null)

if [[ "$ROTATION_ENABLED" == "True" ]]; then
  check "Rotation is enabled on the secret" "0"
else
  check "Rotation is enabled on the secret (got: $ROTATION_ENABLED)" "1"
fi

# ── 5. Rotation Lambda ARN is attached to the secret ──────────────────────────
LAMBDA_ARN=$(aws secretsmanager describe-secret \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --query 'RotationLambdaARN' \
  --output text 2>/dev/null)

if [[ -n "$LAMBDA_ARN" && "$LAMBDA_ARN" != "None" ]]; then
  check "Rotation Lambda is attached (ARN: $LAMBDA_ARN)" "0"
else
  check "Rotation Lambda is attached to the secret" "1"
fi

# ── 6. Lambda function exists ─────────────────────────────────────────────────
aws lambda get-function \
  --function-name "db-password-rotation" \
  --region "$REGION" \
  > /dev/null 2>&1
check "Lambda function 'db-password-rotation' exists" "$?"

# ── 7. Lambda has a resource-based policy allowing Secrets Manager to invoke it
POLICY_OK=$(aws lambda get-policy \
  --function-name "db-password-rotation" \
  --region "$REGION" \
  --query 'Policy' \
  --output text 2>/dev/null | grep -c "secretsmanager.amazonaws.com" || true)

if [[ "$POLICY_OK" -ge 1 ]]; then
  check "Lambda resource policy allows secretsmanager.amazonaws.com to invoke it" "0"
else
  check "Lambda resource policy allows secretsmanager.amazonaws.com to invoke it" "1"
fi

# ── 8. Rotation schedule is set ───────────────────────────────────────────────
ROTATION_DAYS=$(aws secretsmanager describe-secret \
  --secret-id "$SECRET_ID" \
  --region "$REGION" \
  --query 'RotationRules.AutomaticallyAfterDays' \
  --output text 2>/dev/null)

if [[ -n "$ROTATION_DAYS" && "$ROTATION_DAYS" != "None" ]]; then
  check "Rotation schedule configured (every $ROTATION_DAYS days)" "0"
else
  check "Rotation schedule configured (automatically_after_days)" "1"
fi

# ── Results ───────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "  Results: $PASS passed, $FAIL failed"
echo "=========================================="
echo ""

[[ "$FAIL" -eq 0 ]]

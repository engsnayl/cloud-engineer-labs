#!/bin/bash
set -e

echo ""
echo "=========================================="
echo "  Lab 080 — Secrets Manager Rotation"
echo "  Setting up lab environment..."
echo "=========================================="
echo ""

# ── 1. Region guard ────────────────────────────────────────────────────────────
EXPECTED_REGION="eu-west-1"
ACTUAL_REGION=$(aws configure get region 2>/dev/null || echo "")

if [[ "$ACTUAL_REGION" != "$EXPECTED_REGION" ]]; then
  echo "⚠️  AWS CLI default region is '$ACTUAL_REGION', expected '$EXPECTED_REGION'."
  echo "   Run: aws configure set region eu-west-1"
  exit 1
fi

# ── 2. Create a placeholder rotation.zip ───────────────────────────────────────
# The Lambda resource in the solution references rotation.zip.
# A real rotation function would contain the four-step rotation logic.
# This placeholder satisfies Terraform's source_code_hash requirement
# so the lab can be applied without a real deployment package.

echo "Creating placeholder rotation.zip..."

mkdir -p /tmp/lambda-placeholder
cat > /tmp/lambda-placeholder/index.py << 'PYEOF'
import boto3
import json

def handler(event, context):
    """
    Placeholder rotation handler.
    A real implementation would handle four steps:
      createSecret, setSecret, testSecret, finishSecret
    See: https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotating-secrets-lambda-function-overview.html
    """
    step = event.get("Step")
    print(f"Rotation step invoked: {step}")
    return {"statusCode": 200, "body": json.dumps({"step": step})}
PYEOF

(cd /tmp/lambda-placeholder && zip -q rotation.zip index.py)
cp /tmp/lambda-placeholder/rotation.zip ./rotation.zip
rm -rf /tmp/lambda-placeholder

echo "  ✅  rotation.zip created"

# ── 3. Terraform init ──────────────────────────────────────────────────────────
echo ""
echo "Running terraform init..."
terraform init -upgrade -input=false > /dev/null 2>&1
echo "  ✅  Terraform initialised"

# ── 4. Apply the broken starting state ────────────────────────────────────────
# This creates the secret in AWS exactly as a real engineer would find it:
# the secret exists, credentials are stored, but rotation is not configured.

echo ""
echo "Applying starting state (secret only, no rotation)..."
terraform apply -auto-approve -input=false > /dev/null 2>&1
echo "  ✅  Secret created in AWS"

# ── 5. Confirm state ──────────────────────────────────────────────────────────
echo ""
echo "Confirming secret exists and rotation is disabled..."

ROTATION_STATUS=$(aws secretsmanager describe-secret \
  --secret-id production/db-password \
  --region eu-west-1 \
  --query 'RotationEnabled' \
  --output text 2>/dev/null || echo "None")

if [[ "$ROTATION_STATUS" == "False" || "$ROTATION_STATUS" == "None" ]]; then
  echo "  ✅  Secret exists — rotation is NOT enabled (this is the broken state)"
else
  echo "  ⚠️  Unexpected rotation status: $ROTATION_STATUS"
fi

# ── 6. Prompt ─────────────────────────────────────────────────────────────────
echo ""
echo "=========================================="
echo "  Lab environment ready."
echo ""
echo "  You have inherited a secret that hasn't"
echo "  rotated in 90 days. A rotation policy"
echo "  was reportedly configured — but something"
echo "  isn't right."
echo ""
echo "  Open the CHALLENGE.md to get started."
echo "=========================================="
echo ""

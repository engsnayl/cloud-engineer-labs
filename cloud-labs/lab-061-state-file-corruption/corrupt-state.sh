#!/bin/bash
# corrupt-state.sh
#
# Simulates what happens when an engineer makes three changes directly
# in the AWS console, bypassing Terraform entirely.
#
# What this script does (as AWS CLI calls — exactly what the console does
# under the hood):
#
#   1. Changes the S3 bucket tags from staging/ops to production/engineering
#   2. Enables bucket versioning
#   3. Deletes the security group
#
# After this script runs, Terraform's state file is out of date.
# Run: terraform plan
# You'll see drift — Terraform wants to undo or re-apply changes it
# doesn't know about.

set -e

REGION="eu-west-1"

echo ""
echo "================================================"
echo " Simulating manual AWS console changes..."
echo "================================================"
echo ""

# ── Read resource IDs from Terraform state ────────────────────────────────────

echo "Reading resource IDs from Terraform state..."

BUCKET_NAME=$(terraform state show aws_s3_bucket.data 2>/dev/null | grep '^\s*bucket\s*=' | head -1 | awk -F'"' '{print $2}')
SG_ID=$(terraform state show aws_security_group.app 2>/dev/null | grep '^\s*id\s*=' | head -1 | awk -F'"' '{print $2}')

if [ -z "$BUCKET_NAME" ]; then
  echo "ERROR: Could not read bucket name from Terraform state."
  echo "Make sure you have run 'terraform apply' before running this script."
  exit 1
fi

if [ -z "$SG_ID" ]; then
  echo "ERROR: Could not read security group ID from Terraform state."
  echo "Make sure you have run 'terraform apply' before running this script."
  exit 1
fi

echo "  Bucket : $BUCKET_NAME"
echo "  SG ID  : $SG_ID"
echo ""

# ── Change 1: Update S3 bucket tags ──────────────────────────────────────────

echo "[1/3] Someone retagged the S3 bucket in the console..."
echo "      Changing tags from staging/ops → production/engineering"

aws s3api put-bucket-tagging \
  --bucket "$BUCKET_NAME" \
  --tagging 'TagSet=[{Key=Environment,Value=production},{Key=Team,Value=engineering}]' \
  --region "$REGION"

echo "      Done."
echo ""

# ── Change 2: Enable bucket versioning ───────────────────────────────────────

echo "[2/3] Someone enabled versioning on the bucket in the console..."
echo "      Setting versioning: Disabled → Enabled"

aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled \
  --region "$REGION"

echo "      Done."
echo ""

# ── Change 3: Delete the security group ──────────────────────────────────────

echo "[3/3] Someone deleted the security group in the console..."
echo "      Deleting SG: $SG_ID"

aws ec2 delete-security-group \
  --group-id "$SG_ID" \
  --region "$REGION"

echo "      Done."
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────

echo "================================================"
echo " Three manual changes have been made in AWS."
echo " Terraform's state file is now out of date."
echo ""
echo " Run: terraform plan"
echo ""
echo " You should see:"
echo "   ~ S3 bucket tags — Terraform wants to revert"
echo "     them back to staging/ops"
echo "   ~ Versioning — Terraform wants to disable it"
echo "   x Security group — error reading a resource"
echo "     that no longer exists"
echo "================================================"
echo ""

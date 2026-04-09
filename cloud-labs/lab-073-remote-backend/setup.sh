#!/bin/bash
# =============================================================================
# Lab 073 — Remote Backend Configuration
# Setup Script
#
# What this does:
#   1. Creates the S3 bucket that will eventually hold remote state
#   2. Enables versioning on the bucket
#   3. Drops a realistic-looking local terraform.tfstate file into the lab
#      directory — simulating the state that "was on the lost laptop"
#
# What this does NOT do:
#   - Create the DynamoDB table (that's your job in the lab)
#   - Configure the backend block (that's your job in the lab)
#   - Run terraform init or apply (you do that during the lab)
#
# Run this once, immediately after cd-ing into the lab directory.
# =============================================================================

set -e

REGION="eu-west-2"
BUCKET_NAME="terraform-state-lab"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "=============================================="
echo " Lab 073 — Setup"
echo "=============================================="
echo ""

# --- Step 1: Create the S3 bucket -------------------------------------------

echo "[1/3] Creating S3 bucket: $BUCKET_NAME in $REGION..."

# eu-west-2 requires a LocationConstraint (us-east-1 is the only region that doesn't)
aws s3api create-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$REGION" \
  --create-bucket-configuration LocationConstraint="$REGION" \
  2>&1

echo "      Done."

# --- Step 2: Enable versioning on the bucket ---------------------------------

echo "[2/3] Enabling versioning on $BUCKET_NAME..."

aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled \
  2>&1

echo "      Done."

# --- Step 3: Drop a stub terraform.tfstate file ------------------------------

echo "[3/3] Writing stub terraform.tfstate to lab directory..."

cat > "$SCRIPT_DIR/terraform.tfstate" <<'EOF'
{
  "version": 4,
  "terraform_version": "1.10.5",
  "serial": 3,
  "lineage": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "outputs": {},
  "resources": [
    {
      "mode": "managed",
      "type": "aws_s3_bucket",
      "name": "terraform_state",
      "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
      "instances": [
        {
          "schema_version": 0,
          "attributes": {
            "bucket": "terraform-state-lab",
            "region": "eu-west-2",
            "arn": "arn:aws:s3:::terraform-state-lab",
            "id": "terraform-state-lab"
          }
        }
      ]
    }
  ],
  "check_results": null
}
EOF

echo "      Done."

echo ""
echo "=============================================="
echo " Setup complete."
echo ""
echo " What was created:"
echo "   - S3 bucket:          $BUCKET_NAME (eu-west-2, versioning enabled)"
echo "   - terraform.tfstate:  stub state file in this directory"
echo ""
echo " What still needs doing (your lab work):"
echo "   - Uncomment the DynamoDB table in main.tf"
echo "   - Add the encryption resource"
echo "   - Add the public access block"
echo "   - Add the backend block"
echo "   - Run: terraform init"
echo "   - Run: terraform apply"
echo "   - Run: terraform init -migrate-state"
echo "=============================================="
echo ""

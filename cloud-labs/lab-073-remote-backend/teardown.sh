#!/bin/bash
# =============================================================================
# Lab 073 — Remote Backend Configuration
# Teardown Script
#
# What this does:
#   1. Reconfigures Terraform to use a local backend (so we can run destroy
#      without needing the remote backend to still exist)
#   2. Runs terraform destroy to remove all AWS resources
#   3. Deletes all objects and versions from the S3 bucket (required before
#      the bucket itself can be deleted)
#   4. Deletes the S3 bucket
#   5. Cleans up local Terraform files
#
# Run this from the lab directory after completing the lab.
# =============================================================================

set -e

BUCKET_NAME="terraform-state-lab"
REGION="eu-west-2"

echo ""
echo "=============================================="
echo " Lab 073 — Teardown"
echo "=============================================="
echo ""

# --- Step 1: Pull the remote state down locally so we can destroy ------------

echo "[1/5] Pulling remote state to local before backend removal..."

terraform state pull > terraform.tfstate.backup
echo "      State backed up to terraform.tfstate.backup"

# --- Step 2: Temporarily reconfigure to local backend so destroy can run -----

echo "[2/5] Reconfiguring Terraform to use local backend..."

# Write a temporary override file that forces local backend
cat > override.tf <<'EOF'
terraform {
  backend "local" {
    path = "terraform.tfstate.backup"
  }
}
EOF

terraform init -migrate-state -force-copy
echo "      Done. Terraform is now using local state."

# --- Step 3: Destroy all resources -------------------------------------------

echo "[3/5] Running terraform destroy..."
echo "      This will remove: S3 bucket config, DynamoDB table, encryption"
echo "      and public access block resources."
echo ""

terraform destroy -auto-approve
echo "      Resources destroyed."

# --- Step 4: Empty and delete the S3 bucket ----------------------------------
# S3 buckets with versioning cannot be deleted until all versions are removed.

echo "[4/5] Emptying and deleting S3 bucket: $BUCKET_NAME..."

# Delete all current object versions
aws s3api list-object-versions \
  --bucket "$BUCKET_NAME" \
  --query 'Versions[].{Key:Key,VersionId:VersionId}' \
  --output json 2>/dev/null | \
  jq -c '.[] // empty' | \
  while read -r obj; do
    KEY=$(echo "$obj" | jq -r '.Key')
    VERSION=$(echo "$obj" | jq -r '.VersionId')
    aws s3api delete-object \
      --bucket "$BUCKET_NAME" \
      --key "$KEY" \
      --version-id "$VERSION" \
      --region "$REGION" > /dev/null
  done

# Delete all delete markers
aws s3api list-object-versions \
  --bucket "$BUCKET_NAME" \
  --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
  --output json 2>/dev/null | \
  jq -c '.[] // empty' | \
  while read -r obj; do
    KEY=$(echo "$obj" | jq -r '.Key')
    VERSION=$(echo "$obj" | jq -r '.VersionId')
    aws s3api delete-object \
      --bucket "$BUCKET_NAME" \
      --key "$KEY" \
      --version-id "$VERSION" \
      --region "$REGION" > /dev/null
  done

# Now delete the bucket itself
aws s3api delete-bucket \
  --bucket "$BUCKET_NAME" \
  --region "$REGION"

echo "      Bucket deleted."

# --- Step 5: Clean up local files --------------------------------------------

echo "[5/5] Cleaning up local Terraform files..."

rm -f override.tf
rm -f terraform.tfstate.backup
rm -f terraform.tfstate
rm -f terraform.tfstate.backup.*.backup
rm -rf .terraform
rm -f .terraform.lock.hcl

echo "      Done."

echo ""
echo "=============================================="
echo " Teardown complete."
echo ""
echo " All AWS resources removed:"
echo "   - S3 bucket ($BUCKET_NAME) deleted"
echo "   - DynamoDB table (terraform-locks) destroyed"
echo "   - All Terraform local files cleaned up"
echo ""
echo " Your main.tf is unchanged — the lab is ready"
echo " to be reset to broken state and committed."
echo "=============================================="
echo ""

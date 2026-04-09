#!/bin/bash
# =============================================================================
# Lab 073 — Remote Backend Configuration
# Validator Script
# =============================================================================

PASS=0
FAIL=0
BUCKET_NAME="terraform-state-340752829546"
REGION="eu-west-2"
TABLE_NAME="terraform-locks"

echo ""
echo "=============================================="
echo " Lab 073 — Validation"
echo "=============================================="
echo ""

check() {
    local description="$1"
    local result="$2"
    local detail="$3"
    if [[ "$result" == "0" ]]; then
        echo -e "  ✅  $description"
        ((PASS++))
    else
        echo -e "  ❌  $description"
        [[ -n "$detail" ]] && echo -e "       → $detail"
        ((FAIL++))
    fi
}

# --- Check 1: Backend block exists in main.tf --------------------------------

echo "[ Configuration Checks ]"

grep -q 'backend "s3"' main.tf 2>/dev/null
check "Backend block configured as S3 in main.tf" "$?" \
    "No 'backend \"s3\"' block found in main.tf — is it still commented out?"

# --- Check 2: Backend references correct bucket ------------------------------

grep -q "terraform-state-340752829546" main.tf 2>/dev/null
check "Backend block references correct bucket name" "$?" \
    "Bucket name terraform-state-340752829546 not found in main.tf"

# --- Check 3: DynamoDB table referenced in backend block ---------------------

grep -q 'dynamodb_table' main.tf 2>/dev/null
check "DynamoDB table referenced in backend block" "$?" \
    "No dynamodb_table argument found in main.tf"

# --- Check 4: Encryption resource exists in main.tf --------------------------

grep -q 'aws_s3_bucket_server_side_encryption_configuration' main.tf 2>/dev/null
check "Encryption resource present in main.tf" "$?" \
    "aws_s3_bucket_server_side_encryption_configuration not found in main.tf"

# --- Check 5: Public access block resource exists in main.tf -----------------

grep -q 'aws_s3_bucket_public_access_block' main.tf 2>/dev/null
check "Public access block resource present in main.tf" "$?" \
    "aws_s3_bucket_public_access_block not found in main.tf"

# --- Check 6: No local state file present ------------------------------------

echo ""
echo "[ State Migration Checks ]"

[[ ! -f "terraform.tfstate" ]]
check "No local terraform.tfstate file present (state has been migrated)" "$?" \
    "terraform.tfstate still exists locally — did you run terraform init -migrate-state?"

# --- Check 7: State file exists in S3 ----------------------------------------

aws s3api head-object \
    --bucket "$BUCKET_NAME" \
    --key "production/terraform.tfstate" \
    --region "$REGION" \
    &>/dev/null
check "State file exists in S3 at production/terraform.tfstate" "$?" \
    "State file not found in s3://$BUCKET_NAME/production/terraform.tfstate"

# --- Check 8: DynamoDB table exists in AWS -----------------------------------

echo ""
echo "[ Live Infrastructure Checks ]"

aws dynamodb describe-table \
    --table-name "$TABLE_NAME" \
    --region "$REGION" \
    &>/dev/null
check "DynamoDB table '$TABLE_NAME' exists in AWS" "$?" \
    "Table not found — did terraform apply complete successfully?"

# --- Check 9: DynamoDB hash key is LockID ------------------------------------

HASH_KEY=$(aws dynamodb describe-table \
    --table-name "$TABLE_NAME" \
    --region "$REGION" \
    --query "Table.KeySchema[?KeyType=='HASH'].AttributeName" \
    --output text 2>/dev/null)

[[ "$HASH_KEY" == "LockID" ]]
check "DynamoDB table hash key is 'LockID'" "$?" \
    "Hash key is '$HASH_KEY' — must be exactly 'LockID' for Terraform locking to work"

# --- Check 10: S3 bucket encryption enabled ----------------------------------

SSE=$(aws s3api get-bucket-encryption \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    --query "ServerSideEncryptionConfiguration.Rules[0].ApplyServerSideEncryptionByDefault.SSEAlgorithm" \
    --output text 2>/dev/null)

[[ "$SSE" == "aws:kms" || "$SSE" == "AES256" ]]
check "S3 bucket encryption enabled ($SSE)" "$?" \
    "No encryption found on bucket $BUCKET_NAME"

# --- Check 11: S3 public access block enabled --------------------------------

PUBLIC_ACCESS=$(aws s3api get-public-access-block \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    --query "PublicAccessBlockConfiguration.BlockPublicPolicy" \
    --output text 2>/dev/null)

[[ "$PUBLIC_ACCESS" == "True" ]]
check "S3 public access block enabled on state bucket" "$?" \
    "Public access block not enabled on $BUCKET_NAME"

# --- Check 12: Terraform plan is clean ---------------------------------------

echo ""
echo "[ Terraform Checks ]"

terraform validate &>/dev/null
check "Terraform configuration is valid" "$?"

terraform plan -detailed-exitcode &>/dev/null
plan_exit=$?
[[ "$plan_exit" -ne 1 ]]
check "Terraform plan completes with no errors" "$?" \
    "terraform plan errored — check your configuration"

[[ "$plan_exit" -eq 0 ]]
check "Terraform plan shows no pending changes" "$?" \
    "There are still pending changes — did terraform apply complete successfully?"

# --- Summary -----------------------------------------------------------------

echo ""
echo "=============================================="
echo " Results: $PASS passed, $FAIL failed"
echo "=============================================="
echo ""

[[ "$FAIL" -eq 0 ]]

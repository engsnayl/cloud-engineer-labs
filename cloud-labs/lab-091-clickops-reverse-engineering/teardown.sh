#!/bin/bash

# =============================================================================
# Lab 091 Teardown — Destroys all ClickOps resources
# =============================================================================

set -e

RESOURCE_FILE=".lab091-resources"

if [[ ! -f "$RESOURCE_FILE" ]]; then
    echo "  ❌  No resource file found. Did you run setup.sh first?"
    echo "      If resources were created manually, you'll need to"
    echo "      clean them up via the AWS console or CLI."
    exit 1
fi

source "$RESOURCE_FILE"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Lab 091: Tearing down ClickOps environment...         ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# If Terraform state exists, try terraform destroy first
if [[ -f "terraform.tfstate" ]]; then
    echo "  Terraform state found — attempting terraform destroy..."
    terraform destroy -auto-approve 2>/dev/null || true
    echo ""
fi

# Clean up in reverse order of creation
echo "  [1/8] Detaching IAM policy..."
aws iam detach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess \
    --region "$REGION" 2>/dev/null || true

echo "  [2/8] Deleting IAM role..."
aws iam delete-role \
    --role-name "$ROLE_NAME" \
    --region "$REGION" 2>/dev/null || true

echo "  [3/8] Emptying and deleting S3 bucket..."
aws s3 rm "s3://$BUCKET_NAME" --recursive --region "$REGION" 2>/dev/null || true
# Delete versioned objects too
aws s3api list-object-versions \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    --query 'Versions[].{Key:Key,VersionId:VersionId}' \
    --output text 2>/dev/null | while read -r key version; do
    aws s3api delete-object \
        --bucket "$BUCKET_NAME" \
        --key "$key" \
        --version-id "$version" \
        --region "$REGION" 2>/dev/null || true
done
aws s3api list-object-versions \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
    --output text 2>/dev/null | while read -r key version; do
    aws s3api delete-object \
        --bucket "$BUCKET_NAME" \
        --key "$key" \
        --version-id "$version" \
        --region "$REGION" 2>/dev/null || true
done
aws s3api delete-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" 2>/dev/null || true

echo "  [4/8] Deleting security group..."
aws ec2 delete-security-group \
    --group-id "$SG_ID" \
    --region "$REGION" 2>/dev/null || true

echo "  [5/8] Disassociating and deleting route table..."
ASSOC_ID=$(aws ec2 describe-route-tables \
    --route-table-ids "$RTB_ID" \
    --region "$REGION" \
    --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' \
    --output text 2>/dev/null || true)
if [[ -n "$ASSOC_ID" && "$ASSOC_ID" != "None" ]]; then
    aws ec2 disassociate-route-table \
        --association-id "$ASSOC_ID" \
        --region "$REGION" 2>/dev/null || true
fi
aws ec2 delete-route-table \
    --route-table-id "$RTB_ID" \
    --region "$REGION" 2>/dev/null || true

echo "  [6/8] Detaching and deleting Internet Gateway..."
aws ec2 detach-internet-gateway \
    --internet-gateway-id "$IGW_ID" \
    --vpc-id "$VPC_ID" \
    --region "$REGION" 2>/dev/null || true
aws ec2 delete-internet-gateway \
    --internet-gateway-id "$IGW_ID" \
    --region "$REGION" 2>/dev/null || true

echo "  [7/8] Deleting subnets..."
aws ec2 delete-subnet \
    --subnet-id "$PUB_SUBNET_ID" \
    --region "$REGION" 2>/dev/null || true
aws ec2 delete-subnet \
    --subnet-id "$PRIV_SUBNET_ID" \
    --region "$REGION" 2>/dev/null || true

echo "  [8/8] Deleting VPC..."
aws ec2 delete-vpc \
    --vpc-id "$VPC_ID" \
    --region "$REGION" 2>/dev/null || true

# Clean up local files
rm -f "$RESOURCE_FILE"
rm -f terraform.tfstate terraform.tfstate.backup
rm -rf .terraform .terraform.lock.hcl

echo ""
echo "  ✅  All resources destroyed. Lab environment clean."
echo ""

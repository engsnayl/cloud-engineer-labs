#!/bin/bash

# =============================================================================
# Lab 091 Setup — Simulates a ClickOps Engineer
# =============================================================================
# This script creates real AWS resources as if someone clicked through the
# console over time. DO NOT read this script before attempting the lab.
# =============================================================================

set -e

REGION="eu-west-2"
TAG_KEY="Project"
TAG_VALUE="clickops-lab-091"
TAG_SPEC="ResourceType=RESOURCE_TYPE,Tags=[{Key=$TAG_KEY,Value=$TAG_VALUE},{Key=Name,Value=NAME_PLACEHOLDER}]"

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║   Lab 091: Setting up ClickOps environment...           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "  Creating AWS resources in $REGION..."
echo "  (This simulates what the previous engineer built)"
echo ""

# -------------------------------------------------------------------------
# 1. VPC
# -------------------------------------------------------------------------
echo "  [1/8] Creating VPC..."
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block 10.50.0.0/16 \
    --region "$REGION" \
    --query 'Vpc.VpcId' \
    --output text)

aws ec2 create-tags \
    --resources "$VPC_ID" \
    --tags Key="$TAG_KEY",Value="$TAG_VALUE" Key=Name,Value="startup-vpc" \
    --region "$REGION"

aws ec2 modify-vpc-attribute \
    --vpc-id "$VPC_ID" \
    --enable-dns-hostnames '{"Value": true}' \
    --region "$REGION"

# -------------------------------------------------------------------------
# 2. Subnets
# -------------------------------------------------------------------------
echo "  [2/8] Creating subnets..."
PUB_SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block 10.50.1.0/24 \
    --availability-zone "${REGION}a" \
    --region "$REGION" \
    --query 'Subnet.SubnetId' \
    --output text)

aws ec2 create-tags \
    --resources "$PUB_SUBNET_ID" \
    --tags Key="$TAG_KEY",Value="$TAG_VALUE" Key=Name,Value="startup-public" \
    --region "$REGION"

PRIV_SUBNET_ID=$(aws ec2 create-subnet \
    --vpc-id "$VPC_ID" \
    --cidr-block 10.50.2.0/24 \
    --availability-zone "${REGION}a" \
    --region "$REGION" \
    --query 'Subnet.SubnetId' \
    --output text)

aws ec2 create-tags \
    --resources "$PRIV_SUBNET_ID" \
    --tags Key="$TAG_KEY",Value="$TAG_VALUE" Key=Name,Value="startup-private" \
    --region "$REGION"

# -------------------------------------------------------------------------
# 3. Internet Gateway
# -------------------------------------------------------------------------
echo "  [3/8] Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway \
    --region "$REGION" \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)

aws ec2 create-tags \
    --resources "$IGW_ID" \
    --tags Key="$TAG_KEY",Value="$TAG_VALUE" Key=Name,Value="startup-igw" \
    --region "$REGION"

aws ec2 attach-internet-gateway \
    --internet-gateway-id "$IGW_ID" \
    --vpc-id "$VPC_ID" \
    --region "$REGION"

# -------------------------------------------------------------------------
# 4. Route Table
# -------------------------------------------------------------------------
echo "  [4/8] Configuring routing..."
RTB_ID=$(aws ec2 create-route-table \
    --vpc-id "$VPC_ID" \
    --region "$REGION" \
    --query 'RouteTable.RouteTableId' \
    --output text)

aws ec2 create-tags \
    --resources "$RTB_ID" \
    --tags Key="$TAG_KEY",Value="$TAG_VALUE" Key=Name,Value="startup-public-rt" \
    --region "$REGION"

aws ec2 create-route \
    --route-table-id "$RTB_ID" \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id "$IGW_ID" \
    --region "$REGION" > /dev/null

aws ec2 associate-route-table \
    --route-table-id "$RTB_ID" \
    --subnet-id "$PUB_SUBNET_ID" \
    --region "$REGION" > /dev/null

# -------------------------------------------------------------------------
# 5. Security Group
# -------------------------------------------------------------------------
echo "  [5/8] Creating security group..."
SG_ID=$(aws ec2 create-security-group \
    --group-name "startup-web-sg" \
    --description "Web server access" \
    --vpc-id "$VPC_ID" \
    --region "$REGION" \
    --query 'GroupId' \
    --output text)

aws ec2 create-tags \
    --resources "$SG_ID" \
    --tags Key="$TAG_KEY",Value="$TAG_VALUE" Key=Name,Value="startup-web-sg" \
    --region "$REGION"

aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 \
    --region "$REGION" > /dev/null

aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0 \
    --region "$REGION" > /dev/null

aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 \
    --region "$REGION" > /dev/null

# -------------------------------------------------------------------------
# 6. S3 Bucket
# -------------------------------------------------------------------------
echo "  [6/8] Creating S3 bucket..."
BUCKET_NAME="startup-assets-$(date +%s)"

aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION" > /dev/null

aws s3api put-bucket-tagging \
    --bucket "$BUCKET_NAME" \
    --tagging "TagSet=[{Key=$TAG_KEY,Value=$TAG_VALUE},{Key=Name,Value=startup-assets}]" \
    --region "$REGION"

aws s3api put-bucket-versioning \
    --bucket "$BUCKET_NAME" \
    --versioning-configuration Status=Enabled \
    --region "$REGION"

# -------------------------------------------------------------------------
# 7. IAM Role
# -------------------------------------------------------------------------
echo "  [7/8] Creating IAM role..."

cat > /tmp/lab091-trust-policy.json << 'TRUST'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
TRUST

aws iam create-role \
    --role-name startup-web-role \
    --assume-role-policy-document file:///tmp/lab091-trust-policy.json \
    --tags Key="$TAG_KEY",Value="$TAG_VALUE" \
    --region "$REGION" > /dev/null 2>&1

aws iam attach-role-policy \
    --role-name startup-web-role \
    --policy-arn arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess \
    --region "$REGION" 2>/dev/null

# -------------------------------------------------------------------------
# 8. Save resource IDs (for teardown only — NOT for the student)
# -------------------------------------------------------------------------
echo "  [8/8] Saving state for teardown..."

cat > .lab091-resources << EOF
VPC_ID=$VPC_ID
PUB_SUBNET_ID=$PUB_SUBNET_ID
PRIV_SUBNET_ID=$PRIV_SUBNET_ID
IGW_ID=$IGW_ID
RTB_ID=$RTB_ID
SG_ID=$SG_ID
BUCKET_NAME=$BUCKET_NAME
ROLE_NAME=startup-web-role
REGION=$REGION
EOF

rm -f /tmp/lab091-trust-policy.json

echo ""
echo "  ✅  Environment created."
echo ""
echo "  Your mission: discover what was built, document it,"
echo "  write Terraform code to describe it, and import it."
echo ""
echo "  Start with:"
echo "    aws ec2 describe-vpcs --filters \"Name=tag:Project,Values=clickops-lab-091\" --region eu-west-2"
echo ""
echo "  Good luck."
echo ""

#!/bin/bash
# =============================================================================
# Lab 071 — Setup Script
# Creates AWS resources manually (simulating ClickOps) OUTSIDE Terraform.
# These are the resources you'll be importing in the lab.
# =============================================================================

set -e

REGION="eu-west-2"

echo ""
echo "=============================================="
echo "  Lab 071 — Creating manual AWS resources"
echo "=============================================="
echo ""

# --- VPC ---
echo "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc \
  --cidr-block 10.0.0.0/16 \
  --region "$REGION" \
  --query 'Vpc.VpcId' \
  --output text)

aws ec2 modify-vpc-attribute \
  --vpc-id "$VPC_ID" \
  --enable-dns-hostnames "{\"Value\":true}" \
  --region "$REGION"

aws ec2 create-tags \
  --resources "$VPC_ID" \
  --tags Key=Name,Value=production-vpc \
  --region "$REGION"

echo "  ✅  VPC created: $VPC_ID"

# --- Subnet ---
echo "Creating subnet..."
SUBNET_ID=$(aws ec2 create-subnet \
  --vpc-id "$VPC_ID" \
  --cidr-block 10.0.1.0/24 \
  --region "$REGION" \
  --query 'Subnet.SubnetId' \
  --output text)

aws ec2 create-tags \
  --resources "$SUBNET_ID" \
  --tags Key=Name,Value=public-subnet \
  --region "$REGION"

echo "  ✅  Subnet created: $SUBNET_ID"

# --- Security Group ---
echo "Creating security group..."
SG_ID=$(aws ec2 create-security-group \
  --group-name web-sg \
  --description "Web security group" \
  --vpc-id "$VPC_ID" \
  --region "$REGION" \
  --query 'GroupId' \
  --output text)

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp --port 80 \
  --cidr 0.0.0.0/0 \
  --region "$REGION"

aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp --port 443 \
  --cidr 0.0.0.0/0 \
  --region "$REGION"

aws ec2 create-tags \
  --resources "$SG_ID" \
  --tags Key=Name,Value=web-sg \
  --region "$REGION"

echo "  ✅  Security group created: $SG_ID"

# --- Write IDs to file so you can reference them during the lab ---
cat > .lab-resource-ids << EOF
VPC_ID=$VPC_ID
SUBNET_ID=$SUBNET_ID
SG_ID=$SG_ID
EOF

echo ""
echo "=============================================="
echo "  Resources created. IDs saved to .lab-resource-ids"
echo ""
echo "  VPC:            $VPC_ID"
echo "  Subnet:         $SUBNET_ID"
echo "  Security Group: $SG_ID"
echo ""
echo "  These exist in AWS but Terraform has no state file."
echo "  Your job is to import them."
echo "=============================================="
echo ""

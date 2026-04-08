#!/bin/bash
# =============================================================================
# Lab 071 — Teardown Script
# Destroys the manually-created AWS resources and resets lab state.
# Run this after completing the lab to avoid ongoing AWS charges.
# =============================================================================

set -e

REGION="eu-west-1"

echo ""
echo "=============================================="
echo "  Lab 071 — Tearing down AWS resources"
echo "=============================================="
echo ""

# Load the IDs saved by setup.sh
if [[ ! -f .lab-resource-ids ]]; then
  echo "ERROR: .lab-resource-ids not found."
  echo "Either setup.sh was not run, or you're in the wrong directory."
  exit 1
fi

source .lab-resource-ids

# --- Security Group (must go before VPC) ---
echo "Deleting security group $SG_ID..."
aws ec2 delete-security-group \
  --group-id "$SG_ID" \
  --region "$REGION"
echo "  ✅  Security group deleted"

# --- Subnet ---
echo "Deleting subnet $SUBNET_ID..."
aws ec2 delete-subnet \
  --subnet-id "$SUBNET_ID" \
  --region "$REGION"
echo "  ✅  Subnet deleted"

# --- VPC ---
echo "Deleting VPC $VPC_ID..."
aws ec2 delete-vpc \
  --vpc-id "$VPC_ID" \
  --region "$REGION"
echo "  ✅  VPC deleted"

# --- Reset Terraform state ---
echo "Removing Terraform state..."
rm -f terraform.tfstate terraform.tfstate.backup .terraform.lock.hcl
rm -f .lab-resource-ids
echo "  ✅  State cleared"

echo ""
echo "=============================================="
echo "  Teardown complete. Lab is reset."
echo "  Run setup.sh to start again from scratch."
echo "=============================================="
echo ""

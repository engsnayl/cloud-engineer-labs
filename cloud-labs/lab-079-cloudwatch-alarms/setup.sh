#!/bin/bash
# =============================================================================
# Lab 079 — CloudWatch Alarms Misconfigured
# setup.sh — Deploy broken infrastructure to simulate a real incident scenario
# =============================================================================
# Run this once after cd-ing into the lab directory.
# It will initialise Terraform and apply the broken main.tf, creating:
#   - An EC2 instance (t2.micro, Amazon Linux 2)
#   - An SNS topic (with no subscriptions)
#   - Two misconfigured CloudWatch alarms (all four bugs pre-baked in)
#
# This replicates the state an engineer would find when arriving at this ticket.
# Do NOT fix anything before running setup.sh — it intentionally deploys broken config.
# =============================================================================

set -e

echo ""
echo "=============================================="
echo "  Lab 079 — Setup: Deploying broken config"
echo "=============================================="
echo ""

# Confirm AWS credentials are available
echo "Checking AWS credentials..."
if ! aws sts get-caller-identity --region eu-west-1 &>/dev/null; then
  echo ""
  echo "ERROR: AWS credentials not found or not working."
  echo "Make sure your AWS CLI is configured (aws configure) before running setup."
  exit 1
fi

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "  ✅  Authenticated as account: $ACCOUNT_ID (eu-west-1)"
echo ""

# Initialise Terraform
echo "Initialising Terraform..."
terraform init -upgrade -input=false &>/dev/null
echo "  ✅  Terraform initialised"
echo ""

# Apply the broken configuration
echo "Applying broken infrastructure (this takes 1-2 minutes)..."
echo "  → Creating EC2 instance"
echo "  → Creating SNS topic"
echo "  → Creating misconfigured CloudWatch alarms"
echo ""

terraform apply -auto-approve -input=false

echo ""
echo "=============================================="
echo "  Setup complete. Broken infrastructure live."
echo "=============================================="
echo ""
echo "You should now have:"
echo "  - 1 EC2 instance running in eu-west-1"
echo "  - 1 SNS topic (alerts)"
echo "  - 2 CloudWatch alarms, each with bugs pre-applied"
echo ""
echo "Your ticket: INC-4821"
echo "  CloudWatch alarms exist but did not fire during last night's incident."
echo "  Investigate and remediate."
echo ""
echo "Start with:"
echo "  aws cloudwatch describe-alarms --region eu-west-1"
echo ""

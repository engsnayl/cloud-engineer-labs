#!/bin/bash
# =============================================================================
# Validation: Cloud Lab 001 - VPC Troubleshooting
# Requires: AWS CLI configured, terraform state available
# =============================================================================

PASS=0
FAIL=0

check() {
    local description="$1"
    local result="$2"
    if [[ "$result" == "0" ]]; then
        echo -e "  ✅  $description"
        ((PASS++))
    else
        echo -e "  ❌  $description"
        ((FAIL++))
    fi
}

echo "Running validation checks..."
echo ""

LAB_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$LAB_DIR"

# Get resource IDs from Terraform state
INSTANCE_ID=$(terraform output -raw instance_id 2>/dev/null)
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null)

if [[ -z "$INSTANCE_ID" || -z "$VPC_ID" ]]; then
    echo "  ❌  Could not read Terraform outputs. Is the infrastructure deployed?"
    exit 1
fi

# Check 1: Instance is in the private subnet
INSTANCE_SUBNET=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].SubnetId' \
    --output text 2>/dev/null)

PRIVATE_SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=lab001-private-subnet" \
    --query 'Subnets[0].SubnetId' \
    --output text 2>/dev/null)

[[ "$INSTANCE_SUBNET" == "$PRIVATE_SUBNET_ID" ]]
check "EC2 instance is in the private subnet" "$?"

# Check 2: NAT Gateway is in the public subnet
PUBLIC_SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=lab001-public-subnet" \
    --query 'Subnets[0].SubnetId' \
    --output text 2>/dev/null)

NAT_SUBNET=$(aws ec2 describe-nat-gateways \
    --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
    --query 'NatGateways[0].SubnetId' \
    --output text 2>/dev/null)

[[ "$NAT_SUBNET" == "$PUBLIC_SUBNET_ID" ]]
check "NAT Gateway is in the public subnet" "$?"

# Check 3: Private route table points to NAT Gateway (not IGW)
PRIVATE_RT=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=lab001-private-rt" \
    --query 'RouteTables[0].Routes[?DestinationCidrBlock==`0.0.0.0/0`].NatGatewayId' \
    --output text 2>/dev/null)

[[ -n "$PRIVATE_RT" && "$PRIVATE_RT" != "None" ]]
check "Private route table default route points to NAT Gateway" "$?"

# Check 4: Security group has an egress rule
EGRESS_COUNT=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=lab001-app-*" \
    --query 'SecurityGroups[0].IpPermissionsEgress | length(@)' \
    --output text 2>/dev/null)

[[ "$EGRESS_COUNT" -gt 0 ]]
check "Security group has egress rules allowing outbound traffic" "$?"

echo ""
echo "Results: $PASS passed, $FAIL failed"

[[ "$FAIL" -eq 0 ]]

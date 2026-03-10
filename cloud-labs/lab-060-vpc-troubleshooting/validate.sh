#!/bin/bash
# validate.sh — Lab 060: VPC Troubleshooting

PASS=0
FAIL=0

check() {
  local description="$1"
  local result="$2"
  if [ "$result" = "true" ]; then
    echo "  ✅  $description"
    ((PASS++))
  else
    echo "  ❌  $description"
    ((FAIL++))
  fi
}

# Get Terraform outputs
INSTANCE_ID=$(terraform output -raw instance_id 2>/dev/null)
VPC_ID=$(terraform output -raw vpc_id 2>/dev/null)

if [ -z "$INSTANCE_ID" ] || [ -z "$VPC_ID" ]; then
  echo "  ❌  Could not read Terraform outputs. Have you run terraform apply?"
  exit 1
fi

# ------------------------------------------------------------------
# Check 1: EC2 instance is in the private subnet (10.0.2.0/24)
# ------------------------------------------------------------------
INSTANCE_SUBNET=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].SubnetId" \
  --output text 2>/dev/null)

PRIVATE_SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=cidr-block,Values=10.0.2.0/24" \
  --query "Subnets[0].SubnetId" \
  --output text 2>/dev/null)

if [ "$INSTANCE_SUBNET" = "$PRIVATE_SUBNET_ID" ]; then
  check "EC2 instance is in the private subnet" "true"
else
  check "EC2 instance is in the private subnet" "false"
fi

# ------------------------------------------------------------------
# Check 2: NAT Gateway is in the public subnet (10.0.1.0/24)
# ------------------------------------------------------------------
PUBLIC_SUBNET_ID=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=cidr-block,Values=10.0.1.0/24" \
  --query "Subnets[0].SubnetId" \
  --output text 2>/dev/null)

NAT_SUBNET=$(aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
  --query "NatGateways[0].SubnetId" \
  --output text 2>/dev/null)

if [ "$NAT_SUBNET" = "$PUBLIC_SUBNET_ID" ]; then
  check "NAT Gateway is in the public subnet" "true"
else
  check "NAT Gateway is in the public subnet" "false"
fi

# ------------------------------------------------------------------
# Check 3: Private route table default route points to NAT Gateway
# ------------------------------------------------------------------
PRIVATE_RT=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.subnet-id,Values=$PRIVATE_SUBNET_ID" \
  --query "RouteTables[0].RouteTableId" \
  --output text 2>/dev/null)

NAT_GW_ID=$(aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available" \
  --query "NatGateways[0].NatGatewayId" \
  --output text 2>/dev/null)

ROUTE_TARGET=$(aws ec2 describe-route-tables \
  --route-table-ids "$PRIVATE_RT" \
  --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].NatGatewayId" \
  --output text 2>/dev/null)

if [ "$ROUTE_TARGET" = "$NAT_GW_ID" ]; then
  check "Private route table default route points to NAT Gateway" "true"
else
  check "Private route table default route points to NAT Gateway" "false"
fi

# ------------------------------------------------------------------
# Check 4: Security group has egress rules
# ------------------------------------------------------------------
SG_ID=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query "Reservations[0].Instances[0].SecurityGroups[0].GroupId" \
  --output text 2>/dev/null)

EGRESS_COUNT=$(aws ec2 describe-security-groups \
  --group-ids "$SG_ID" \
  --query "length(SecurityGroups[0].IpPermissionsEgress)" \
  --output text 2>/dev/null)

if [ "$EGRESS_COUNT" -gt 0 ] 2>/dev/null; then
  check "Security group has egress rules allowing outbound traffic" "true"
else
  check "Security group has egress rules allowing outbound traffic" "false"
fi

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo "╔══════════════════════════════════════╗"
  echo "║  ✅  ALL CHECKS PASSED — WELL DONE!  ║"
  echo "╚══════════════════════════════════════╝"
else
  echo "╔══════════════════════════════════════╗"
  echo "║  ❌  SOME CHECKS FAILED — TRY AGAIN  ║"
  echo "╚══════════════════════════════════════╝"
fi

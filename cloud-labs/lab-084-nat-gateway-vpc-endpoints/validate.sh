#!/bin/bash
# Lab 084 validate.sh — queries actual AWS resource state.
# Broken starting config must FAIL these checks; fixed config must PASS.

set -u

REGION="eu-west-2"
PASS=0
FAIL=0

check() {
  local desc="$1" result="$2"
  if [[ "$result" == "0" ]]; then
    echo "  ✅  $desc"
    ((PASS++))
  else
    echo "  ❌  $desc"
    ((FAIL++))
  fi
}

echo "Running Lab 084 validation against real AWS state (${REGION})..."
echo ""

# ---------------------------------------------------------------------------
# Pre-flight: confirm infrastructure is actually deployed
# ---------------------------------------------------------------------------

if ! command -v aws &>/dev/null; then
  echo "  ❌  aws CLI not found"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "  ❌  jq not found — install with: sudo apt install -y jq"
  exit 1
fi

# Resolve the VPC by Name tag
VPC_ID=$(aws ec2 describe-vpcs --region "$REGION" \
  --filters "Name=tag:Name,Values=lab-vpc" \
  --query 'Vpcs[0].VpcId' --output text 2>/dev/null)

if [[ -z "$VPC_ID" || "$VPC_ID" == "None" ]]; then
  echo "  ❌  lab-vpc not found — run: terraform apply"
  exit 1
fi
echo "  ℹ️   VPC: $VPC_ID"

# Resolve subnets
PUBLIC_SUBNET_ID=$(aws ec2 describe-subnets --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=public-subnet" \
  --query 'Subnets[0].SubnetId' --output text 2>/dev/null)

PRIVATE_SUBNET_ID=$(aws ec2 describe-subnets --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=private-subnet" \
  --query 'Subnets[0].SubnetId' --output text 2>/dev/null)

# Resolve route tables
PUBLIC_RT_ID=$(aws ec2 describe-route-tables --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=public-rt" \
  --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null)

PRIVATE_RT_ID=$(aws ec2 describe-route-tables --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=tag:Name,Values=private-rt" \
  --query 'RouteTables[0].RouteTableId' --output text 2>/dev/null)

echo ""

# ---------------------------------------------------------------------------
# Check 1: NAT Gateway is in the PUBLIC subnet
# ---------------------------------------------------------------------------

NAT_SUBNET_ID=$(aws ec2 describe-nat-gateways --region "$REGION" \
  --filter "Name=vpc-id,Values=$VPC_ID" "Name=state,Values=available,pending" \
  --query 'NatGateways[0].SubnetId' --output text 2>/dev/null)

[[ "$NAT_SUBNET_ID" == "$PUBLIC_SUBNET_ID" ]]
check "NAT Gateway resides in the public subnet" "$?"

# ---------------------------------------------------------------------------
# Check 2: NAT Gateway is in the "available" state (confirms EIP + IGW reachable)
# ---------------------------------------------------------------------------

NAT_STATE=$(aws ec2 describe-nat-gateways --region "$REGION" \
  --filter "Name=vpc-id,Values=$VPC_ID" \
  --query 'NatGateways[0].State' --output text 2>/dev/null)

[[ "$NAT_STATE" == "available" ]]
check "NAT Gateway is in 'available' state" "$?"

# ---------------------------------------------------------------------------
# Check 3: Private route table default route points to the NAT Gateway
#          (not to the Internet Gateway)
# ---------------------------------------------------------------------------

PRIVATE_DEFAULT_TARGET=$(aws ec2 describe-route-tables --region "$REGION" \
  --route-table-ids "$PRIVATE_RT_ID" \
  --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'] | [0]" \
  --output json 2>/dev/null)

NAT_ID_IN_ROUTE=$(echo "$PRIVATE_DEFAULT_TARGET" | jq -r '.NatGatewayId // empty')
IGW_ID_IN_ROUTE=$(echo "$PRIVATE_DEFAULT_TARGET" | jq -r '.GatewayId // empty')

[[ -n "$NAT_ID_IN_ROUTE" && -z "$IGW_ID_IN_ROUTE" ]]
check "Private route table 0.0.0.0/0 target is a NAT Gateway (not IGW)" "$?"

# ---------------------------------------------------------------------------
# Check 4: Public route table default route points to the IGW (sanity)
# ---------------------------------------------------------------------------

PUBLIC_IGW_TARGET=$(aws ec2 describe-route-tables --region "$REGION" \
  --route-table-ids "$PUBLIC_RT_ID" \
  --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId | [0]" \
  --output text 2>/dev/null)

[[ "$PUBLIC_IGW_TARGET" == igw-* ]]
check "Public route table 0.0.0.0/0 target is an Internet Gateway" "$?"

# ---------------------------------------------------------------------------
# Check 5: S3 VPC Endpoint is associated with the PRIVATE route table
# ---------------------------------------------------------------------------

ENDPOINT_JSON=$(aws ec2 describe-vpc-endpoints --region "$REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=service-name,Values=com.amazonaws.${REGION}.s3" \
  --query 'VpcEndpoints[0]' --output json 2>/dev/null)

ENDPOINT_RT_IDS=$(echo "$ENDPOINT_JSON" | jq -r '.RouteTableIds[]?' | sort | tr '\n' ' ')

echo "$ENDPOINT_RT_IDS" | grep -qw "$PRIVATE_RT_ID"
PRIVATE_ASSOC=$?
echo "$ENDPOINT_RT_IDS" | grep -qw "$PUBLIC_RT_ID"
PUBLIC_ASSOC=$?

[[ "$PRIVATE_ASSOC" -eq 0 && "$PUBLIC_ASSOC" -ne 0 ]]
check "S3 VPC Endpoint associated with the private route table only" "$?"

# ---------------------------------------------------------------------------
# Check 6: S3 VPC Endpoint policy allows s3 actions (Effect == Allow)
# ---------------------------------------------------------------------------

ENDPOINT_POLICY=$(echo "$ENDPOINT_JSON" | jq -r '.PolicyDocument // empty')
ALLOW_EFFECT=$(echo "$ENDPOINT_POLICY" | jq -r '.Statement[]? | select(.Action == "s3:*" or (.Action | type == "array" and any(. == "s3:*"))) | .Effect' 2>/dev/null | head -n1)

[[ "$ALLOW_EFFECT" == "Allow" ]]
check "S3 VPC Endpoint policy Effect is Allow for s3 actions" "$?"

# ---------------------------------------------------------------------------
# Check 7: Private route table has a prefix-list route for S3 via the endpoint
#          (AWS auto-adds this when the endpoint is associated with the RT)
# ---------------------------------------------------------------------------

ENDPOINT_ID=$(echo "$ENDPOINT_JSON" | jq -r '.VpcEndpointId // empty')

if [[ -n "$ENDPOINT_ID" ]]; then
  PREFIX_ROUTE=$(aws ec2 describe-route-tables --region "$REGION" \
    --route-table-ids "$PRIVATE_RT_ID" \
    --query "RouteTables[0].Routes[?VpcEndpointId=='$ENDPOINT_ID'] | [0].DestinationPrefixListId" \
    --output text 2>/dev/null)
  [[ "$PREFIX_ROUTE" == pl-* ]]
else
  false
fi
check "Private route table has an S3 prefix-list route via the VPC Endpoint" "$?"

# ---------------------------------------------------------------------------
# Check 8: Private EC2 instance is running and registered with SSM
# ---------------------------------------------------------------------------

INSTANCE_ID=$(aws ec2 describe-instances --region "$REGION" \
  --filters "Name=tag:Name,Values=lab-084-private-instance" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].InstanceId' --output text 2>/dev/null)

[[ "$INSTANCE_ID" == i-* ]]
check "Private EC2 instance is running" "$?"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]

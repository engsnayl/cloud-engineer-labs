# Solution Walkthrough — NAT Gateway & VPC Endpoints

## The Problem

An EC2 instance in a private subnet has no internet or S3 connectivity. There are **four bugs**:

1. **NAT Gateway in the wrong subnet** — the NAT Gateway is placed in the private subnet. It must be in the public subnet because it needs a route to the Internet Gateway to translate private-to-public traffic.
2. **Private route table points to IGW instead of NAT** — the private subnet's default route goes directly to the Internet Gateway. Private instances don't have public IPs, so IGW can't route their traffic. It should point to the NAT Gateway.
3. **VPC Endpoint on the wrong route table** — the S3 VPC Endpoint is associated with the public route table, but the instances that need S3 access are in the private subnet.
4. **VPC Endpoint policy denies everything** — the endpoint policy has `Effect: Deny` for all S3 actions, blocking all traffic through the endpoint.

## Step-by-Step Solution

### Step 1: Move NAT Gateway to public subnet

```hcl
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id  # Was: aws_subnet.private.id
}
```

### Step 2: Fix private route to use NAT Gateway

```hcl
route {
  cidr_block     = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.main.id  # Was: gateway_id = aws_internet_gateway.main.id
}
```

Note the attribute change: `nat_gateway_id` not `gateway_id`.

### Step 3: Associate VPC Endpoint with private route table

```hcl
route_table_ids = [aws_route_table.private.id]  # Was: aws_route_table.public.id
```

### Step 4: Fix VPC Endpoint policy to Allow

```hcl
policy = jsonencode({
  Version = "2012-10-17"
  Statement = [{
    Effect    = "Allow"  # Was: Deny
    Principal = "*"
    Action    = "s3:*"
    Resource  = "*"
  }]
})
```

## Key Concepts Learned

- **NAT Gateways live in public subnets** — they need internet access via the IGW to translate private traffic. The flow is: private instance → NAT Gateway (in public subnet) → IGW → internet.
- **Private subnets route through NAT, not IGW** — use `nat_gateway_id` in route tables, not `gateway_id`.
- **VPC Endpoints bypass NAT** — Gateway endpoints (S3, DynamoDB) add routes directly to the route table. Traffic to S3 stays within the AWS network, reducing costs and improving latency.
- **VPC Endpoint policies are another access control layer** — they can restrict which S3 buckets or actions are allowed through the endpoint, adding defence in depth.
- **Route table associations matter** — a VPC Endpoint only affects subnets whose route tables are associated with it.

## Common Mistakes

- **NAT Gateway in private subnet** — most common VPC mistake. The NAT Gateway needs internet access itself.
- **Using gateway_id for NAT** — Terraform uses `nat_gateway_id` for NAT Gateways and `gateway_id` for Internet Gateways. Using the wrong one causes confusing errors.
- **Forgetting VPC Endpoint route table association** — the endpoint exists but doesn't affect the right subnets.
- **Not using VPC Endpoints for S3** — all S3 traffic going through NAT Gateway costs money (data processing charges). VPC Endpoints for S3 are free and faster.

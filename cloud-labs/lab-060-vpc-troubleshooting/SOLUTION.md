# Solution Walkthrough — VPC Networking (EC2 Can't Reach Internet)

## The Problem

An EC2 instance in a VPC can't reach the internet. The VPC has a public subnet, a private subnet, an Internet Gateway, and a NAT Gateway — but the networking is misconfigured in **four ways**:

1. **NAT Gateway is in the private subnet** — a NAT Gateway must be in the public subnet (the one with an Internet Gateway route). A NAT Gateway in the private subnet has no internet path itself, so it can't forward traffic for private instances.
2. **Private route table points to the IGW instead of the NAT Gateway** — the private subnet's route table sends `0.0.0.0/0` traffic to the Internet Gateway, not the NAT Gateway. Private instances shouldn't route directly through the IGW (that makes them effectively public).
3. **Security group has no egress rules** — AWS security groups have an implicit deny. Without an explicit egress rule, the instance can't make any outbound connections — no DNS lookups, no HTTP requests, nothing.
4. **EC2 instance is in the public subnet** — the instance should be in the private subnet (for security), but it's launched in the public subnet instead.

## Thought Process

When an EC2 instance can't reach the internet, an experienced cloud engineer traces the traffic path hop by hop:

1. **Instance → Subnet** — which subnet is the instance in? Is it the right one?
2. **Subnet → Route Table** — what route table is associated with that subnet? Does it have a `0.0.0.0/0` route?
3. **Route Table → Gateway** — does the default route point to the right gateway? (IGW for public subnets, NAT Gateway for private subnets)
4. **NAT Gateway → Public Subnet** — is the NAT Gateway in a subnet that has internet access? (It must be in the public subnet)
5. **Security Group** — does the security group allow outbound traffic? Check egress rules.
6. **NACLs** — are there any Network ACL rules blocking traffic? (Not an issue in this lab, but always check in production)

## Step-by-Step Solution

### Step 1: Review the Terraform and identify the bugs

```bash
terraform init
terraform plan
```

**What this does:** Initializes Terraform and shows the planned resources. Review the plan output and compare it against the intended architecture: private instance → NAT Gateway → Internet Gateway → internet.

### Step 2: Fix Bug 1 — Move NAT Gateway to the public subnet

In `main.tf`, find the NAT Gateway resource:

```hcl
# BROKEN: NAT Gateway is in the private subnet
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.private.id    # Wrong!
}
```

Change to:

```hcl
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id     # Fixed!
  tags          = { Name = "lab001-nat-gw" }
  depends_on    = [aws_internet_gateway.main]
}
```

**Why this matters:** A NAT Gateway translates private IPs to its own public IP for outbound traffic. For this to work, the NAT Gateway itself needs internet access — which means it must be in a subnet that routes to the Internet Gateway (the public subnet). A NAT Gateway in the private subnet has no internet route, so it can't forward traffic anywhere.

### Step 3: Fix Bug 2 — Private route table should point to NAT Gateway

Find the private route table:

```hcl
# BROKEN: Private route uses IGW instead of NAT
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id    # Wrong!
  }
}
```

Change to:

```hcl
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id     # Fixed!
  }
  tags = { Name = "lab001-private-rt" }
}
```

**Why this matters:** The private route table must send internet-bound traffic to the NAT Gateway, not the Internet Gateway. If you route directly to the IGW, the instances effectively become public (they'd need public IPs to work, which defeats the purpose of a private subnet). The NAT Gateway handles the address translation: private IP → NAT's public IP → internet.

Note the attribute change: `gateway_id` is for Internet Gateways, `nat_gateway_id` is for NAT Gateways. Using the wrong attribute type causes a Terraform error.

### Step 4: Fix Bug 3 — Add egress rules to the security group

Find the security group:

```hcl
# BROKEN: No egress rule
resource "aws_security_group" "app" {
  name_prefix = "lab001-app-"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  # Missing egress!
}
```

Add an egress rule:

```hcl
resource "aws_security_group" "app" {
  name_prefix = "lab001-app-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for application instance"

  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "lab001-app-sg" }
}
```

**Why this matters:** AWS security groups are stateful (return traffic for an allowed connection is automatically allowed), but they don't have a default "allow all outbound" rule when defined in Terraform. The AWS console adds a default egress rule when you create a security group manually, but Terraform's `aws_security_group` resource does not. Without an egress rule, the instance can't initiate any outbound connections — no DNS, no HTTP, no package updates.

The rule uses `protocol = "-1"` (all protocols), `from_port = 0`, `to_port = 0`, and `0.0.0.0/0` — this allows all outbound traffic. In production, you'd restrict this to specific ports and destinations.

### Step 5: Fix Bug 4 — Move the instance to the private subnet

Find the instance resource:

```hcl
# BROKEN: Instance in public subnet
resource "aws_instance" "app" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public.id    # Wrong!
}
```

Change to:

```hcl
resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private.id    # Fixed!
  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = <<-EOF
    #!/bin/bash
    echo "App server ready" > /tmp/status
  EOF

  tags = { Name = "lab001-app-server" }
}
```

**Why this matters:** The scenario requires the instance to be in the private subnet — it should reach the internet through the NAT Gateway, not directly via the IGW. Placing an application server in the public subnet exposes it to inbound internet traffic (if it has a public IP), which violates the security requirement.

### Step 6: Apply and verify

```bash
terraform plan
terraform apply
```

**What this does:** Shows the changes and applies them. Verify that:
- The NAT Gateway is created in the public subnet
- The private route table routes through the NAT Gateway
- The security group has an egress rule
- The EC2 instance is in the private subnet

### Step 7: Run validation

```bash
./validate.sh
```

**What this does:** Uses AWS CLI to verify all four fixes: instance placement, NAT Gateway placement, route table configuration, and security group egress rules.

## Docker Lab vs Real Life

- **NACLs (Network ACLs):** This lab doesn't include NACL issues, but in production, NACLs are another layer that can block traffic. NACLs are stateless (unlike security groups), so you need both inbound and outbound rules, plus ephemeral port ranges for return traffic.
- **VPC Flow Logs:** In production, enable VPC Flow Logs to see exactly which traffic is being accepted or rejected. This is invaluable for debugging connectivity issues.
- **Multiple availability zones:** Production VPCs have subnets in at least 2 AZs for high availability. Each AZ needs its own NAT Gateway (single NAT Gateway = single point of failure).
- **Transit Gateway:** In production, multiple VPCs connect through AWS Transit Gateway instead of direct VPC peering. This simplifies routing for large organizations.
- **Restricted egress:** The "allow all outbound" egress rule used here is common for simplicity. In production, security-conscious environments restrict egress to specific ports (443 for HTTPS, 53 for DNS) and use VPC endpoints for AWS services to keep traffic off the public internet.

## Key Concepts Learned

- **NAT Gateways must be in public subnets** — they need internet access (via IGW) to translate and forward traffic from private instances
- **Private route tables use `nat_gateway_id`, not `gateway_id`** — these are different Terraform attributes for different gateway types
- **Terraform security groups don't have a default egress rule** — unlike the AWS console, Terraform doesn't automatically allow outbound traffic. You must define egress rules explicitly.
- **The traffic path is: Instance → Route Table → NAT → IGW → Internet** — every hop in this chain must be correctly configured. One broken link = no connectivity.
- **Instance placement matters for security** — public subnet instances get public IPs and direct internet access. Private subnet instances are hidden behind NAT, accessible only for outbound traffic.

## Common Mistakes

- **Confusing `gateway_id` and `nat_gateway_id`** — using `gateway_id` for a NAT Gateway causes a Terraform error. Internet Gateways use `gateway_id`, NAT Gateways use `nat_gateway_id`.
- **Forgetting the egress rule in Terraform** — this is one of the most common AWS Terraform mistakes. The console adds a default "allow all outbound" rule, but Terraform doesn't. Many engineers only notice when their instances can't reach anything.
- **Putting the NAT Gateway in the private subnet** — this is counter-intuitive. "NAT is for private instances, so put it in the private subnet" is wrong. The NAT Gateway needs internet access itself, so it goes in the public subnet.
- **Not adding `depends_on` for the NAT Gateway** — the NAT Gateway needs the Internet Gateway to exist first. Without `depends_on = [aws_internet_gateway.main]`, Terraform might create the NAT Gateway before the IGW, causing a creation failure.
- **Forgetting that security groups are stateful** — you need an egress rule for the initial outbound connection. But you don't need an ingress rule for the return traffic — security groups automatically allow return traffic for established connections.

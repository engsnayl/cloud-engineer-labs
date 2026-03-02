# Solution Walkthrough — EC2 Can't Reach Internet (VPC Networking)

## The Problem

An EC2 instance in a private subnet can't reach the internet for package updates. The VPC has the right components (Internet Gateway, NAT Gateway, route tables, subnets), but they're wired together incorrectly. There are **four bugs**:

1. **NAT Gateway is in the private subnet** — a NAT Gateway needs to be in the public subnet (the one with an IGW route) so it can forward traffic to the internet. In the private subnet, the NAT Gateway itself has no internet access.
2. **Private route table points to IGW instead of NAT Gateway** — the private subnet's default route sends traffic directly to the Internet Gateway. Private instances should route through the NAT Gateway instead.
3. **Security group has no egress rules** — without an explicit egress rule, the instance can't make any outbound connections. AWS security groups deny all traffic by default (when managed by Terraform).
4. **Instance is in the public subnet instead of private** — the instance should be in the private subnet, routing through the NAT Gateway. Being in the public subnet defeats the purpose of the private-subnet architecture.

## Thought Process

When an EC2 instance can't reach the internet, trace the traffic path:

1. **Instance → Subnet** — which subnet is the instance in? Is it correct?
2. **Subnet → Route Table** — does the associated route table have a `0.0.0.0/0` route?
3. **Route Table → Gateway** — does the default route point to the right gateway type? (NAT for private, IGW for public)
4. **NAT Gateway placement** — is the NAT Gateway in a subnet with internet access?
5. **Security Group** — do the egress rules allow outbound traffic?

## Step-by-Step Solution

### Step 1: Fix Bug 1 — Move NAT Gateway to public subnet

```hcl
# BROKEN
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.private.id    # Wrong!
}

# FIXED
resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id     # NAT Gateway in public subnet
  tags = { Name = "lab-nat" }
}
```

**Why this matters:** A NAT Gateway translates private IPs to its own Elastic IP for outbound internet traffic. To do this, the NAT Gateway itself needs internet access — which only exists in the public subnet (the one with an IGW route). A NAT Gateway in the private subnet can't reach the internet, so it can't forward anything.

### Step 2: Fix Bug 2 — Private route table should use NAT Gateway

```hcl
# BROKEN
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id    # Wrong — points to IGW!
  }
}

# FIXED
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id     # Points to NAT Gateway
  }
  tags = { Name = "private-rt" }
}
```

**Why this matters:** The route table attribute changes from `gateway_id` (for Internet Gateways) to `nat_gateway_id` (for NAT Gateways). These are different Terraform attributes because they reference different AWS resource types. Using `gateway_id` with a NAT Gateway reference would cause a Terraform error.

The traffic flow becomes: Private instance → Private route table → NAT Gateway (in public subnet) → Public route table → IGW → Internet.

### Step 3: Fix Bug 3 — Add egress rules to security group

```hcl
# BROKEN — no egress rule
resource "aws_security_group" "app" {
  name   = "app-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }
  # Missing egress!
}

# FIXED — add egress rule
resource "aws_security_group" "app" {
  name   = "app-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "app-sg" }
}
```

**Why this matters:** Terraform's `aws_security_group` resource does NOT automatically create the default "allow all outbound" rule that the AWS console adds. Without an egress rule, the security group blocks all outbound traffic — the instance can't even make DNS queries, let alone HTTP requests.

### Step 4: Fix Bug 4 — Move instance to private subnet

```hcl
# BROKEN
resource "aws_instance" "app" {
  ami           = "ami-0c76bd4bd302b30ec"
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public.id     # Wrong — should be private!
}

# FIXED
resource "aws_instance" "app" {
  ami                    = "ami-0c76bd4bd302b30ec"
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private.id    # Private subnet
  vpc_security_group_ids = [aws_security_group.app.id]
  tags = { Name = "app-server" }
}
```

**Why this matters:** The whole point of the private subnet + NAT Gateway architecture is to give instances outbound internet access without exposing them to inbound internet traffic. An instance in the public subnet gets a public IP and is directly reachable from the internet — a security risk for application servers.

### Step 5: Validate

```bash
terraform validate
terraform plan
```

**What this does:** Confirms all four fixes produce a valid configuration.

## Docker Lab vs Real Life

- **Multiple AZs:** Production architectures deploy NAT Gateways in each AZ. A single NAT Gateway is a single point of failure — if its AZ goes down, all private instances lose internet access.
- **NAT Gateway costs:** NAT Gateways charge per hour (~$0.045/hr) plus per-GB processed (~$0.045/GB). For high-traffic workloads, this can be significant. Some teams use NAT instances (EC2-based) for cost savings, or VPC endpoints to avoid NAT entirely for AWS service traffic.
- **VPC endpoints:** Instead of routing S3/DynamoDB/SQS traffic through the NAT Gateway (and paying per-GB), use VPC endpoints. Gateway endpoints (S3, DynamoDB) are free. Interface endpoints cost per hour but keep traffic within the AWS network.
- **NACLs:** Network ACLs add another layer. They're stateless (unlike security groups), so you need both inbound and outbound rules, including ephemeral port ranges (1024-65535) for return traffic.
- **Flow Logs:** VPC Flow Logs capture traffic metadata (source, destination, port, action) for debugging and compliance. Always enable them in production.

## Key Concepts Learned

- **NAT Gateways go in public subnets** — they need an internet route (IGW) to forward traffic from private instances
- **Private route tables use `nat_gateway_id`** — not `gateway_id`, which is for Internet Gateways
- **Terraform security groups need explicit egress rules** — the console adds a default "allow all outbound" rule, but Terraform does not
- **Private subnet + NAT = outbound only** — instances can reach the internet but the internet can't reach them directly
- **Trace the full path when debugging** — Instance → Route Table → NAT/IGW → Internet. Every hop must be correct.

## Common Mistakes

- **Putting NAT Gateway in the private subnet** — this is the most common VPC mistake. The name "NAT" suggests it's for private subnets, but it goes IN the public subnet to SERVE the private subnet.
- **Using `gateway_id` for NAT Gateway references** — Terraform will error because `gateway_id` expects an Internet Gateway. Use `nat_gateway_id` for NAT Gateways.
- **Forgetting egress rules in Terraform** — works fine in the console but breaks in Terraform. This catches many engineers the first time they write a security group in code.
- **Not considering the cost of NAT Gateways** — NAT Gateways bill per GB of data processed. High-traffic workloads can generate surprise costs. Use VPC endpoints for AWS service traffic to reduce NAT costs.
- **Single NAT Gateway for all AZs** — if the NAT Gateway's AZ fails, all private instances in other AZs lose internet. Production needs one NAT Gateway per AZ.

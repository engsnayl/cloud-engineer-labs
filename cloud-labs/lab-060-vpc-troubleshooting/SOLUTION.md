# Lab 060 — VPC Troubleshooting: EC2 Can't Reach the Internet

## ⚠️ IMPORTANT: Tear Down When Done

This lab creates real AWS resources that cost money — specifically a NAT Gateway (~$0.045/hr) and an Elastic IP. Always run `terraform destroy` when you finish the lab.

---

## TLDR — Plain English Summary

You've got an EC2 instance sitting inside AWS that can't reach the internet. AWS gives you a lot of networking knobs to turn, and four of them have been turned the wrong way.

Think of it like this: your server is in a back office (private subnet) and needs to send traffic out through a postroom (NAT Gateway) which sits in the front lobby (public subnet) which has a door to the street (Internet Gateway). In this broken setup:

1. The postroom has been put in the back office — it has no door to the street itself, so it can't forward anyone's mail
2. The back office's address book is sending mail directly to the street door instead of the postroom
3. The server has been told it can receive post, but it's never been told it's allowed to send any
4. The server isn't even in the back office — it's been put in the front lobby by mistake

Your job is to find and fix all four of these in the Terraform.

---

## The Four Bugs

| # | What's Wrong | Where | What It Should Be |
|---|---|---|---|
| 1 | NAT Gateway is in the private subnet | `aws_nat_gateway.main` | Must be in the public subnet |
| 2 | Private route table points to the IGW | `aws_route_table.private` | Must point to the NAT Gateway |
| 3 | Security group has no egress rule | `aws_security_group.app` | Needs an explicit outbound rule |
| 4 | EC2 instance is in the public subnet | `aws_instance.app` | Must be in the private subnet |

---

## How to Think Through This — The Diagnostic Approach

When an EC2 instance can't reach the internet, a cloud engineer traces the traffic path hop by hop — from the instance outward to the internet. Every hop in the chain must be correctly configured. One broken link = no connectivity.

The path should be:

```
EC2 Instance → Route Table → NAT Gateway → Internet Gateway → Internet
```

Work through it in this order:

1. **Where is the instance?** — Which subnet is it in? Is that right for the intended architecture?
2. **What route table governs that subnet?** — Does it have a `0.0.0.0/0` default route? Where does it point?
3. **Is that gateway in the right place?** — If it points to a NAT Gateway, is the NAT Gateway itself in a public subnet?
4. **Does the security group allow outbound traffic?** — Check egress rules. No egress = no outbound connections.

---

## Step-by-Step Solution

### Step 1: Initialise Terraform and review the plan

```bash
terraform init
terraform plan
```

**What these do:**

| Command | What it does |
|---|---|
| `terraform init` | Downloads the AWS provider plugin, sets up the `.terraform` directory, prepares the working directory |
| `terraform plan` | Reads your `.tf` files and shows what AWS resources would be created, changed, or destroyed — without actually doing anything |

Read the plan output carefully. It tells you exactly what Terraform intends to build. Use it to mentally trace the traffic path before applying anything.

---

### Step 2: Find the bugs — read the Terraform files

```bash
cat main.tf
```

You're looking for four things by reading the resource blocks:

- Where is `subnet_id` set on `aws_nat_gateway.main`? Is it referencing the public or private subnet?
- What does `aws_route_table.private` point to? `gateway_id` (IGW) or `nat_gateway_id` (NAT)?
- Does `aws_security_group.app` have an `egress` block?
- Where is `subnet_id` set on `aws_instance.app`?

**How do you know which subnet is which?**

Look at the subnet resource blocks in `main.tf`. The public subnet has `map_public_ip_on_launch = true` — that's the giveaway. The private subnet doesn't have that attribute. You don't need to run any AWS CLI commands to figure this out — the answer is right there in the same file.

```hcl
# This one is public — map_public_ip_on_launch = true gives it away
resource "aws_subnet" "public" {
  ...
  map_public_ip_on_launch = true
}

# This one is private — no public IP mapping
resource "aws_subnet" "private" {
  ...
}
```

The Terraform resource names (`aws_subnet.public` and `aws_subnet.private`) also tell you directly — you reference them as `aws_subnet.public.id` and `aws_subnet.private.id`.

---

### Step 3: Fix Bug 1 — NAT Gateway must be in the public subnet

**Why it's wrong:** A NAT Gateway's job is to receive traffic from private instances and forward it to the internet on their behalf. To do that, the NAT Gateway itself needs internet access — which means it must sit in a subnet that has a route to the Internet Gateway (the public subnet). A NAT Gateway in the private subnet has no internet path, so it can't forward anything.

**Where to look:** Find `aws_nat_gateway.main` in `main.tf`

**Broken:**
```hcl
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.private.id    # Wrong — no internet access here
  tags          = { Name = "lab001-nat-gw" }
  depends_on    = [aws_internet_gateway.main]
}
```

**Fixed:**
```hcl
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id     # Fixed — public subnet has IGW access
  tags          = { Name = "lab001-nat-gw" }
  depends_on    = [aws_internet_gateway.main]
}
```

**What `depends_on` does here:** Tells Terraform to create the Internet Gateway before the NAT Gateway. Without this, Terraform might try to create the NAT Gateway first, which would fail because the IGW doesn't exist yet.

---

### Step 4: Fix Bug 2 — Private route table must point to the NAT Gateway

**Why it's wrong:** The private route table currently sends all outbound traffic (`0.0.0.0/0`) directly to the Internet Gateway. That's wrong for two reasons: private instances don't have public IPs so the IGW can't route their traffic, and it defeats the purpose of having a private subnet. Private instances must route through the NAT Gateway instead.

**Where to look:** Find `aws_route_table.private` in `main.tf`

**Broken:**
```hcl
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id    # Wrong — IGW is for public subnets
  }
}
```

**Fixed:**
```hcl
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id     # Fixed — private subnets route via NAT
  }
  tags = { Name = "lab001-private-rt" }
}
```

**Important — attribute name change:**

| Attribute | Used for |
|---|---|
| `gateway_id` | Internet Gateways only |
| `nat_gateway_id` | NAT Gateways only |

Using `gateway_id` and pointing it at a NAT Gateway ID will cause a Terraform error. They are different attributes for different resource types.

---

### Step 5: Fix Bug 3 — Security group needs an egress rule

**Why it's wrong:** AWS security groups don't automatically allow outbound traffic when defined in Terraform. The AWS Console adds a default "allow all outbound" rule when you create a security group manually — but Terraform doesn't. Without an explicit egress rule, the instance cannot initiate any outbound connection: no DNS lookups, no HTTP requests, no package updates, nothing.

**Where to look:** Find `aws_security_group.app` in `main.tf` — look for a missing `egress` block

**Broken:**
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
  # No egress rule — all outbound traffic is blocked
}
```

**Fixed:**
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

**Egress rule breakdown:**

| Field | Value | What it means |
|---|---|---|
| `from_port` | `0` | Start of port range — 0 means all |
| `to_port` | `0` | End of port range — 0 means all |
| `protocol` | `"-1"` | All protocols (TCP, UDP, ICMP, etc.) |
| `cidr_blocks` | `["0.0.0.0/0"]` | Allow to any destination IP |

In production you'd restrict this — for example port 443 only for HTTPS, port 53 for DNS. This "allow all" rule is fine for a lab.

---

### Step 6: Fix Bug 4 — Instance must be in the private subnet

**Why it's wrong:** The whole point of a public/private subnet architecture is to keep application servers hidden from direct internet access. An instance in the public subnet gets a public IP and is directly reachable from the internet. The instance should be in the private subnet, where it can only reach the internet outbound via the NAT Gateway.

**Where to look:** Find `aws_instance.app` in `main.tf`

**Broken:**
```hcl
resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id    # Wrong — exposed to internet
  vpc_security_group_ids = [aws_security_group.app.id]
  ...
}
```

**Fixed:**
```hcl
resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private.id    # Fixed — hidden behind NAT
  vpc_security_group_ids = [aws_security_group.app.id]
  ...
}
```

**How to confirm the fix worked after apply:** Check the `instance_private_ip` output. If the IP is in the `10.0.2.x` range, the instance is in the private subnet (`10.0.2.0/24`). If it's in `10.0.1.x`, it's still in the public subnet.

---

### Step 7: Apply the fixes

```bash
terraform plan
terraform apply
```

**What to look for in the plan output:**

| Resource | Expected change |
|---|---|
| `aws_nat_gateway.main` | `subnet_id` changes from private subnet ID to public subnet ID — will be destroyed and recreated |
| `aws_route_table.private` | Route changes from `gateway_id` to `nat_gateway_id` — updated in place |
| `aws_security_group.app` | Egress rule added — updated in place |
| `aws_instance.app` | `subnet_id` changes from public to private — will be destroyed and recreated |

**Note:** NAT Gateways take 1-2 minutes to provision and destroy. This is normal AWS behaviour — don't cancel the apply.

---

### Step 8: Validate

```bash
lab validate 060
```

All four checks should pass:
- ✅ EC2 instance is in the private subnet
- ✅ NAT Gateway is in the public subnet
- ✅ Private route table default route points to NAT Gateway
- ✅ Security group has egress rules allowing outbound traffic

---

### Step 9: Tear it all down

```bash
terraform destroy
```

Type `yes` when prompted. Wait for confirmation that all 12 resources are destroyed. Check your AWS Console afterwards to confirm no lingering resources (especially NAT Gateways and Elastic IPs — these cost money even when idle).

**What `terraform destroy` does:**

| Command | What it does |
|---|---|
| `terraform destroy` | Reads your state file, identifies all resources Terraform manages, and deletes them all from AWS in the correct dependency order |

---

## Real-World Context

- **VPC Flow Logs:** In production, enable VPC Flow Logs so you can see exactly which traffic is accepted or rejected. This is the first thing you'd turn to when debugging connectivity issues at scale.
- **Multiple AZs:** Production VPCs have subnets in at least 2 availability zones for resilience. Each AZ needs its own NAT Gateway — a single NAT Gateway is a single point of failure.
- **NACLs:** This lab doesn't include Network ACL issues, but in production these are another layer that can block traffic. Unlike security groups, NACLs are stateless — you need explicit inbound and outbound rules, including ephemeral port ranges for return traffic.
- **Restricted egress:** "Allow all outbound" is common in development. Production environments often restrict egress to specific ports (443, 53) and use VPC Endpoints to keep traffic to AWS services off the public internet entirely.
- **IAM Instance Profiles:** Production EC2 instances typically use IAM roles (via instance profiles) rather than static credentials. The instance gets temporary credentials automatically via the metadata service.

---

## Key Concepts

- **NAT Gateways must be in the public subnet** — they need internet access (via IGW) to translate and forward traffic from private instances
- **Private route tables use `nat_gateway_id`, not `gateway_id`** — these are different Terraform attributes for different gateway types
- **Terraform security groups don't get a default egress rule** — unlike the AWS Console, Terraform requires you to define egress rules explicitly
- **The full traffic path is: Instance → Route Table → NAT Gateway → Internet Gateway → Internet** — every hop must be correctly wired
- **Instance placement determines exposure** — public subnet = public IP + direct internet access; private subnet = hidden behind NAT, outbound only

---

## Common Mistakes

- **Confusing `gateway_id` and `nat_gateway_id`** — using `gateway_id` with a NAT Gateway ID causes a Terraform error. They're not interchangeable.
- **Forgetting the egress rule** — one of the most common AWS Terraform mistakes. The Console adds it automatically; Terraform doesn't.
- **NAT Gateway in the private subnet** — counter-intuitive but wrong. "NAT is for private instances so put it in the private subnet" — no. It needs internet access itself, so it goes in the public subnet.
- **Checking instance IP to confirm subnet placement** — look at the IP range in the output. `10.0.1.x` = public subnet, `10.0.2.x` = private subnet in this lab.

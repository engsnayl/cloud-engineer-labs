# Solution Walkthrough — VPC Peering Traffic Blocked

## The Problem

Two VPCs need to communicate via VPC peering. The peering connection shows "active," but no traffic flows between them. Applications in VPC-A can't reach the database in VPC-B. There are **three bugs**:

1. **Overlapping CIDR blocks** — both VPCs use `10.0.0.0/16`. VPC peering requires non-overlapping CIDRs. With identical CIDRs, the route table can't distinguish between "traffic to my VPC" and "traffic to the peer VPC" — all `10.0.x.x` traffic stays local.
2. **Missing route table entries** — even with a peering connection, traffic doesn't flow unless both VPCs have route table entries pointing to the peer VPC's CIDR through the peering connection. The route tables have no peering routes.
3. **Security groups don't allow cross-VPC traffic** — the DB security group allows traffic from `10.0.0.0/16`, which is ambiguous when both VPCs use the same CIDR. After fixing the CIDR overlap, the security group needs to reference the correct (app VPC) CIDR.

## Thought Process

When VPC peering traffic doesn't flow, an experienced cloud engineer checks:

1. **CIDR overlap** — peered VPCs must have non-overlapping CIDR blocks. `10.0.0.0/16` on both sides means routes can't distinguish local from peer traffic.
2. **Route tables** — both VPCs need routes pointing the peer's CIDR to the peering connection. Without routes, traffic has no path to the peer.
3. **Security groups** — security groups must explicitly allow traffic from the peer VPC's CIDR range.
4. **Peering connection status** — the peering connection must be in "active" state. Pending-acceptance peerings don't route traffic.

## Step-by-Step Solution

### Step 1: Fix Bug 1 — Change DB VPC CIDR to avoid overlap

```hcl
# BROKEN — same CIDR as app VPC
resource "aws_vpc" "db" {
  cidr_block = "10.0.0.0/16"    # Overlaps with app VPC!
  tags = { Name = "db-vpc" }
}

# FIXED — unique CIDR
resource "aws_vpc" "db" {
  cidr_block = "10.1.0.0/16"    # No overlap
  tags = { Name = "db-vpc" }
}
```

**Why this matters:** VPC peering only works between VPCs with non-overlapping CIDR blocks. If both VPCs use `10.0.0.0/16`, a packet destined for `10.0.2.50` is ambiguous — is it the local VPC or the peer? The route table can't resolve this, so all traffic stays local. Changing the DB VPC to `10.1.0.0/16` makes the ranges distinct.

### Step 2: Update the DB subnet to use the new CIDR range

```hcl
# BROKEN — subnet in old CIDR range
resource "aws_subnet" "db" {
  vpc_id     = aws_vpc.db.id
  cidr_block = "10.0.2.0/24"    # Must be within 10.1.0.0/16 now
}

# FIXED
resource "aws_subnet" "db" {
  vpc_id     = aws_vpc.db.id
  cidr_block = "10.1.1.0/24"
}
```

### Step 3: Fix Bug 2 — Add route table entries for peering

```hcl
# App VPC route table — route to DB VPC via peering
resource "aws_route_table" "app" {
  vpc_id = aws_vpc.app.id

  route {
    cidr_block                = "10.1.0.0/16"
    vpc_peering_connection_id = aws_vpc_peering_connection.app_to_db.id
  }
}

# DB VPC route table — route to App VPC via peering
resource "aws_route_table" "db" {
  vpc_id = aws_vpc.db.id

  route {
    cidr_block                = "10.0.0.0/16"
    vpc_peering_connection_id = aws_vpc_peering_connection.app_to_db.id
  }
}
```

**Why this matters:** A VPC peering connection is like a cable between two VPCs — but without route table entries, traffic has no path to use it. Each VPC needs a route that says "to reach the other VPC's CIDR, send traffic through the peering connection." Routes must be added on **both sides** — app VPC needs a route to the DB VPC CIDR, and vice versa.

### Step 4: Add route table associations

```hcl
resource "aws_route_table_association" "app" {
  subnet_id      = aws_subnet.app.id
  route_table_id = aws_route_table.app.id
}

resource "aws_route_table_association" "db" {
  subnet_id      = aws_subnet.db.id
  route_table_id = aws_route_table.db.id
}
```

### Step 5: Fix Bug 3 — Update security groups for cross-VPC traffic

```hcl
# App security group — allow all outbound
resource "aws_security_group" "app" {
  name   = "app-sg"
  vpc_id = aws_vpc.app.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# DB security group — allow from app VPC CIDR
resource "aws_security_group" "db" {
  name   = "db-sg"
  vpc_id = aws_vpc.db.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]    # App VPC CIDR
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

**Why this matters:** After fixing the CIDR overlap, `10.0.0.0/16` now unambiguously refers to the app VPC. The DB security group allows PostgreSQL traffic (port 5432) only from the app VPC's CIDR range.

### Step 6: Validate

```bash
terraform validate
terraform plan
```

## Docker Lab vs Real Life

- **Transit Gateway:** In production with many VPCs, use AWS Transit Gateway instead of direct peering. Peering is point-to-point — 10 VPCs would need 45 peering connections. Transit Gateway provides hub-and-spoke connectivity.
- **Cross-account peering:** VPC peering works across AWS accounts. The peering connection requires acceptance from the peer account (can't auto-accept cross-account).
- **Cross-region peering:** VPC peering supports cross-region connections. Traffic is encrypted in transit and stays on the AWS backbone network.
- **DNS resolution:** Enable DNS resolution for the peering connection so instances can resolve each other's private DNS hostnames: `aws_vpc_peering_connection_options` with `allow_remote_vpc_dns_resolution = true`.
- **CIDR planning:** Production environments use IP Address Management (IPAM) to plan non-overlapping CIDRs across all VPCs. Poor CIDR planning causes problems that are expensive to fix later (requires recreating VPCs).

## Key Concepts Learned

- **Peered VPCs must have non-overlapping CIDRs** — overlapping CIDRs make routing ambiguous. Plan CIDR blocks carefully before creating VPCs.
- **Routes must be added on both sides** — each VPC needs a route to the peer's CIDR via the peering connection. Without bidirectional routes, traffic can't flow.
- **Security groups must allow cross-VPC traffic** — peering provides the network path, but security groups control access. Both must be correct.
- **VPC peering is non-transitive** — if VPC-A peers with VPC-B, and VPC-B peers with VPC-C, VPC-A cannot reach VPC-C through VPC-B. Each pair needs its own peering connection.
- **`vpc_peering_connection_id` in route tables** — this is how route tables direct traffic through the peering connection, similar to how `nat_gateway_id` directs through NAT.

## Common Mistakes

- **Overlapping CIDRs** — this is the #1 VPC peering mistake. Once a VPC is created with a CIDR, changing it requires recreating the VPC and all its resources. Plan carefully.
- **Routes only on one side** — adding a route in the app VPC but not the DB VPC means traffic can reach the DB but responses can't come back. Always add routes in both VPCs.
- **Forgetting to update security groups** — peering provides connectivity, but security groups still control access. After peering, update SG rules to allow the peer's CIDR.
- **Not accepting the peering connection** — cross-account peering requires explicit acceptance. The connection stays in "pending-acceptance" until accepted, and no traffic flows.
- **Assuming peering is transitive** — VPC-A → VPC-B → VPC-C doesn't work. If A needs to reach C, you need a direct A-C peering connection (or Transit Gateway).

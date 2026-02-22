# Solution Walkthrough — Database Unreachable (RDS Security Group Issues)

## The Problem

An EC2 application instance can't connect to an RDS MySQL database on port 3306. Both are in the same VPC, but the security groups and configuration are preventing connectivity. There are **three bugs**:

1. **DB security group allows traffic from the wrong CIDR** — the ingress rule allows `10.0.99.0/24`, but the application subnet is `10.0.1.0/24`. No traffic from the app instance matches the allowed CIDR, so all connection attempts are silently dropped.
2. **DB security group has no egress rule** — without an egress rule, the database can't send response traffic back to the application. Even though security groups are stateful (return traffic is normally allowed), Terraform-managed security groups without explicit egress rules block all outbound traffic.
3. **RDS is publicly accessible** — `publicly_accessible = true` gives the RDS instance a public DNS name and makes it reachable from outside the VPC. For a database that only needs to serve internal application traffic, this is a security risk.

## Thought Process

When an application can't reach its database, an experienced cloud engineer checks:

1. **Security groups** — does the DB security group allow inbound traffic from the application? Check the source (CIDR or security group reference), port, and protocol.
2. **Network path** — are the app and database in the same VPC? Are they in subnets that can route to each other?
3. **Database configuration** — is the DB publicly accessible? Is it in the correct subnet group?
4. **Connection parameters** — is the application using the right hostname, port, username, and password?

## Step-by-Step Solution

### Step 1: Fix Bug 1 — Allow traffic from the correct source

The best practice for security group rules is to reference the application's security group ID instead of a CIDR block. This way, if the app moves to a different subnet, the rule still works:

```hcl
# BROKEN
resource "aws_security_group" "db" {
  name   = "db-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.99.0/24"]    # Wrong CIDR!
  }
}

# FIXED — use security group reference instead of CIDR
resource "aws_security_group" "db" {
  name   = "db-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }
}
```

**Why this matters:** Using `security_groups` instead of `cidr_blocks` is the AWS best practice for inter-resource security group rules. It means "allow traffic from any instance that has the `app-sg` security group attached." This is more robust than CIDR-based rules because:
- It works regardless of which subnet the app is in
- It automatically applies to new app instances
- It's more readable — "allow from the app security group" is clearer than "allow from 10.0.1.0/24"

### Step 2: Fix Bug 2 — Add egress rule to DB security group

```hcl
resource "aws_security_group" "db" {
  name   = "db-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

**Why this matters:** While AWS security groups are stateful (return traffic for established connections is automatically allowed), Terraform-managed security groups that lack any egress rules can behave unexpectedly. Adding an explicit egress rule ensures the database can send responses back. This is a standard best practice for all Terraform-managed security groups.

### Step 3: Fix Bug 3 — Disable public accessibility

```hcl
# BROKEN
resource "aws_db_instance" "main" {
  # ...
  publicly_accessible = true    # Security risk!
}

# FIXED
resource "aws_db_instance" "main" {
  identifier             = "app-db"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  db_name                = "appdb"
  username               = "admin"
  password               = "changeme123"
  publicly_accessible    = false    # No public access
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
}
```

**Why this matters:** `publicly_accessible = true` does two things:
1. Assigns a public DNS name to the RDS instance
2. Makes the instance reachable from outside the VPC (if the security group allows it)

For a database serving only internal traffic, this is unnecessary and dangerous. If the security group accidentally allows `0.0.0.0/0`, the database becomes accessible from the entire internet. Setting `publicly_accessible = false` ensures the database is only reachable from within the VPC.

### Step 4: Validate

```bash
terraform validate
terraform plan
```

**What this does:** Confirms the configuration is valid and the plan looks correct.

## Docker Lab vs Real Life

- **Secrets management:** The `password = "changeme123"` in plain text is a lab simplification. In production, use AWS Secrets Manager with `manage_master_user_password = true` (RDS manages and rotates the password) or reference a Secrets Manager secret.
- **Multi-AZ deployment:** Production RDS instances use `multi_az = true` for high availability. This creates a synchronous standby replica in a different AZ that automatically takes over during failures.
- **Encryption:** Production databases should have `storage_encrypted = true` and use a KMS key. The `password` should never be in plain text in Terraform — use variables with `sensitive = true` or Secrets Manager.
- **Enhanced monitoring:** Enable `monitoring_interval` and `performance_insights_enabled` for production databases to diagnose performance issues.
- **Deletion protection:** Production databases should have `deletion_protection = true` to prevent accidental deletion via `terraform destroy` or console actions.

## Key Concepts Learned

- **Use security group references instead of CIDR blocks** — `security_groups = [aws_security_group.app.id]` is more robust and maintainable than hardcoding CIDR blocks
- **Databases should not be publicly accessible** — set `publicly_accessible = false` for any database that only serves internal traffic
- **Terraform security groups need explicit egress rules** — add an egress block to ensure response traffic can flow
- **RDS needs a subnet group with at least 2 AZs** — even for single-AZ deployments, AWS requires the subnet group to span at least 2 availability zones
- **Security group source CIDR must match the actual subnet** — `10.0.99.0/24` doesn't match traffic from `10.0.1.0/24`. Always verify the CIDR matches the source subnet.

## Common Mistakes

- **Using the wrong CIDR in security group rules** — this is the #1 cause of "can't connect to database" issues. Always double-check that the allowed CIDR matches the source subnet.
- **Forgetting to add the DB security group to the RDS instance** — the `vpc_security_group_ids` parameter must reference the correct security group. An RDS instance without a security group (or with the default VPC security group) may not allow the intended traffic.
- **Making RDS publicly accessible "for testing"** — this often gets forgotten and left in production. Always default to `publicly_accessible = false` and use VPN or bastion hosts for remote access.
- **Storing passwords in plain text in Terraform** — use `sensitive = true` on variables, or better yet, use AWS Secrets Manager with `manage_master_user_password = true`.
- **Not checking the subnet group configuration** — the DB subnet group must contain subnets in the same VPC as the application. Cross-VPC connectivity requires VPC peering or Transit Gateway.

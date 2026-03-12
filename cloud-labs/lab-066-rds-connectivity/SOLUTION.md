# Lab 066 — Solution Walkthrough: Database Unreachable (RDS Security Group Issues)

---

## TLDR — Plain English Summary

Imagine your application is trying to knock on the database's door, but three things are going wrong:

1. **The bouncer has the wrong guest list.** The database security group only lets in traffic from IP range `10.0.99.0/24`, but your app lives at `10.0.1.0/24`. It's like your app is knocking on the right door but it's not on the list — so the knock is silently ignored.

2. **The database can't talk back.** Even if traffic gets in, the database has no rule allowing it to send a response. Without an egress rule in Terraform, response packets can't leave. It's like the database picks up the phone but can't speak — the line goes dead.

3. **The database has a public-facing door that should be locked.** `publicly_accessible = true` gives the RDS instance a public DNS name and exposes it to the internet. For a database that should only ever talk to your internal app, this is a security risk — and in this lab it actually prevents the instance from being created at all.

**To fix it:** Disable public accessibility first (so the instance can be created), then point the security group at the correct source using a security group reference instead of a wrong CIDR, then add the missing egress rule.

---

## The Three Bugs at a Glance

| # | Bug | Impact |
|---|-----|--------|
| 1 | DB security group ingress allows wrong CIDR (`10.0.99.0/24` instead of `10.0.1.0/24`) | App traffic is silently dropped — connection never reaches the DB |
| 2 | DB security group has no egress rule | DB can receive traffic but can't send responses back |
| 3 | `publicly_accessible = true` on the RDS instance | Prevents instance creation entirely in a VPC without an internet gateway |

---

## Important: Apply Order Matters

**Fix Bug 3 first.** In this lab, `publicly_accessible = true` causes `terraform apply` to fail immediately with:

```
InvalidVPCNetworkStateFault: Cannot create a publicly accessible DBInstance.
The specified VPC has no internet gateway attached.
```

The VPC has no internet gateway (correctly, for a private DB), so AWS refuses to create the instance at all. You cannot get into a broken-but-running state until this is fixed. In a real environment with an IGW present this would succeed silently — making it a hidden security risk rather than an obvious error. Here it fails loudly, which is actually helpful.

Fix `publicly_accessible = false` in `main.tf` first, then apply to get the infrastructure up before working through Bugs 1 and 2.

---

## Step-by-Step Investigative Learning Pathway

---

### Bug 3 (Fix First): RDS Instance Set to Publicly Accessible

#### The Symptom
`terraform apply` fails immediately with `InvalidVPCNetworkStateFault`. AWS won't create a publicly accessible RDS instance in a VPC that has no internet gateway.

#### The Investigation

**Step 1: Find the RDS instance resource in main.tf**

Look for the `aws_db_instance` resource. Scan for the `publicly_accessible` argument.

**Step 2: Why is this wrong?**

`publicly_accessible = true` does two things:
1. Assigns a public DNS name to the RDS instance
2. Makes the instance reachable from outside the VPC if any security group allows it

For a database that only needs to talk to an internal app server, this is unnecessary exposure. In a real environment with an IGW, this would succeed silently — and potentially expose your database to the internet if a security group was ever misconfigured to allow `0.0.0.0/0`.

**Step 3: Will changing this break anything?**

Only if something outside the VPC is currently connecting directly to the database — which should never be the case for a properly designed internal application. All internal app to DB connections via private IP are unaffected.

#### The Fix

```hcl
# BROKEN
resource "aws_db_instance" "main" {
  publicly_accessible = true    # Prevents creation in a VPC without IGW
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
  publicly_accessible    = false
  skip_final_snapshot    = true
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
}
```

#### aws_db_instance Key Fields

| Field | Value | What it means |
|-------|-------|---------------|
| `identifier` | `"app-db"` | Unique name for this RDS instance in your AWS account |
| `engine` | `"mysql"` | The database engine to run |
| `engine_version` | `"8.0"` | Specific MySQL version |
| `instance_class` | `"db.t3.micro"` | Compute size — small, burstable |
| `allocated_storage` | `20` | Storage in gigabytes |
| `publicly_accessible` | `false` | No public DNS name — DB is VPC-only |
| `skip_final_snapshot` | `true` | Don't create a snapshot on destroy (fine for labs, not production) |
| `db_subnet_group_name` | (reference) | Which subnets RDS can use — must span 2+ AZs |
| `vpc_security_group_ids` | (reference) | Attaches the DB security group to control who can connect |

---

### Bug 1: Wrong CIDR in the Security Group Ingress Rule

#### The Symptom
After the infrastructure is up, connection attempts to the database time out rather than getting an explicit rejection. Timeout behaviour is the key clue — it means a security group is silently dropping packets, not actively refusing them.

#### The Investigation

**Step 1: Where do you start?**

Security groups are almost always the first thing to check when an app can't reach a database in AWS. Go to your Terraform config and find the `aws_security_group` resource attached to your RDS instance. Look at the `ingress` block.

**Step 2: What are you looking for?**

Three things need to match:
- `from_port` / `to_port` → should be `3306` (MySQL)
- `protocol` → should be `"tcp"`
- The *source* → this is where the bug is

**Step 3: How do you spot the bug?**

Check the `cidr_blocks` value in the ingress rule:

```hcl
cidr_blocks = ["10.0.99.0/24"]
```

Now ask: where does my application actually live? Check the `aws_subnet` resource definitions in your config, or pull it directly from state:

```bash
terraform state show aws_subnet.app | grep cidr
```

You'll find the app subnet is `10.0.1.0/24`. These are completely different ranges — traffic from your app doesn't match the allowed CIDR and is silently dropped.

**Step 4: What's the fix — and is there a better approach than CIDRs?**

You could swap `10.0.99.0/24` for `10.0.1.0/24` and that would work. But the better real-world approach is to reference the security group directly:

```hcl
security_groups = [aws_security_group.app.id]
```

This says "allow traffic from any instance with the app security group attached." If the app ever moves to a different subnet, the rule still works automatically.

#### The Fix

```hcl
# BROKEN
ingress {
  from_port   = 3306
  to_port     = 3306
  protocol    = "tcp"
  cidr_blocks = ["10.0.99.0/24"]    # Wrong CIDR — app is at 10.0.1.0/24
}

# FIXED
ingress {
  from_port       = 3306
  to_port         = 3306
  protocol        = "tcp"
  security_groups = [aws_security_group.app.id]    # Reference the app SG directly
}
```

#### Ingress Rule Fields

| Field | Value | What it means |
|-------|-------|---------------|
| `from_port` | `3306` | Start of the allowed port range |
| `to_port` | `3306` | End of the allowed port range — same value means exactly port 3306 |
| `protocol` | `"tcp"` | MySQL uses TCP |
| `security_groups` | (reference) | Allow traffic from any instance with this security group attached |

---

### Bug 2: No Egress Rule on the DB Security Group

#### The Symptom
Even after fixing the ingress CIDR, connections may still fail or behave inconsistently. AWS security groups are stateful — return traffic is normally allowed automatically — but Terraform-managed security groups without any egress block can behave unexpectedly and block all outbound traffic.

#### The Investigation

**Step 1: Check whether there's an egress block at all**

Look at the `aws_security_group` resource for your database. If there's no `egress` block, that's the problem. Unlike the AWS console (which adds an allow-all egress rule by default), Terraform requires you to define this explicitly.

**Step 2: What should the egress rule look like?**

For a database, egress doesn't need to be restrictive — it just needs to exist so response traffic can flow back to the application:

```hcl
egress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}
```

#### Egress Rule Fields

| Field | Value | What it means |
|-------|-------|---------------|
| `from_port` | `0` | Combined with protocol `-1`, means any port |
| `to_port` | `0` | Combined with protocol `-1`, means any port |
| `protocol` | `"-1"` | AWS shorthand for "all protocols" |
| `cidr_blocks` | `["0.0.0.0/0"]` | Allow responses to any destination |

#### The Fix

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

---

## Validate and Apply

Once all fixes are in place:

```bash
terraform validate
terraform plan
terraform apply
```

#### Command Breakdown

| Command | What it does |
|---------|--------------|
| `terraform validate` | Checks HCL syntax — catches typos and structural errors before touching AWS |
| `terraform plan` | Shows exactly what Terraform would change — read this before applying |
| `terraform apply` | Makes the changes real in AWS |

**What to look for in `terraform plan`:**
- `aws_security_group` should show the wrong CIDR ingress replaced with a security group reference, and a new egress block added
- `aws_db_instance` should show `publicly_accessible` changing from `true` to `false`

---

## Finding the RDS Endpoint (No Outputs File)

This lab has no `outputs.tf`, so `terraform output` returns nothing useful. Pull the endpoint directly from state:

```bash
terraform state show aws_db_instance.main | grep endpoint
```

#### Command Breakdown

| Part | What it does |
|------|--------------|
| `terraform state show` | Reads the current state of a specific resource |
| `aws_db_instance.main` | The resource name — matches what's defined in `main.tf` |
| `grep endpoint` | Filters output to lines containing "endpoint" |

The endpoint value includes the port (`hostname:3306`) — strip the `:3306` suffix when passing to connection tools.

In a real deployment you'd always expose the RDS endpoint as a Terraform output so application configs can reference it. The absence of `outputs.tf` here is a gap worth flagging in any real infrastructure repo.

---

## Testing Connectivity

This lab runs from the Pi as the host — there's no EC2 app instance. The RDS instance is in a private VPC with no internet gateway, so the Pi cannot resolve or reach the private RDS endpoint from outside the VPC. Use the validate script:

```bash
./validate.sh
```

**If you want to test TCP connectivity from inside a VPC in future labs**, use netcat:

```bash
# Install once — available globally thereafter (apt installs system-wide, not per-directory)
sudo apt install netcat-openbsd -y

nc -zv <rds-endpoint> 3306
```

#### nc Command Breakdown

| Part | What it does |
|------|--------------|
| `nc` | Netcat — raw TCP connection tool |
| `-z` | Zero I/O mode — just check if the port is open, don't send data |
| `-v` | Verbose — explicitly reports success or failure |
| `<rds-endpoint>` | DNS hostname of the RDS instance |
| `3306` | The MySQL port to test |

**What the response tells you:**
- `Connection timed out` → packets silently dropped — classic security group block
- `Connection refused` → port actively rejected — DB not listening, or different block type
- `open` → connection succeeded

If `nc` isn't available (e.g. minimal containers, Alpine images), use this pure-bash fallback — no external tools required:

```bash
timeout 5 bash -c 'echo > /dev/tcp/<host>/3306' && echo "Connected" || echo "Failed"
```

---

## Lab vs Real Life

| Lab Simplification | Production Reality |
|--------------------|--------------------|
| `password = "changeme123"` in plain text | Use `manage_master_user_password = true` — RDS manages rotation via Secrets Manager |
| Single-AZ deployment | `multi_az = true` for a synchronous standby replica that auto-promotes on failure |
| No encryption | `storage_encrypted = true` with a KMS key |
| No deletion protection | `deletion_protection = true` to prevent accidental `terraform destroy` |
| No monitoring | `monitoring_interval` and `performance_insights_enabled = true` |

---

## Key Concepts from This Lab

- **Fix `publicly_accessible` first** — in a VPC without an IGW this blocks infrastructure creation entirely; in a VPC with an IGW it's a silent security risk instead
- **Security group source CIDR must match the actual source subnet** — `10.0.99.0/24` silently drops all traffic from `10.0.1.0/24`; always verify the CIDR matches where traffic actually comes from
- **Security group references beat CIDRs** — `security_groups = [aws_security_group.app.id]` is more robust and readable than hardcoding a subnet CIDR
- **Terraform security groups need explicit egress rules** — unlike the AWS console default, Terraform requires this to be defined explicitly
- **Timeout vs refused is diagnostic** — timeout means silent drop (security group); refused means active rejection (port not listening)
- **No outputs.tf? Use terraform state show** — `terraform state show aws_db_instance.main | grep endpoint` pulls connection details directly from state

---

## Common Mistakes to Watch For

- **Wrong CIDR in the ingress rule** — the number one cause of "can't connect to database" in AWS; always verify the CIDR matches the actual source subnet
- **No egress block on Terraform-managed security groups** — the AWS console adds allow-all egress by default; Terraform does not
- **Leaving `publicly_accessible = true` "for testing"** — gets forgotten and ends up in production; always default to `false`
- **Forgetting to attach the security group to the RDS instance** — `vpc_security_group_ids` must reference the correct SG
- **Passwords in plain text in Terraform** — use `sensitive = true` on variables at minimum, or Secrets Manager for production

---

## Pi / K3s Lab Notes

This is a Terraform/AWS lab — no Pi-specific caveats apply. All changes are in AWS infrastructure.

Note: `nc` (netcat) is not installed on the Pi by default. Run `sudo apt install netcat-openbsd -y` once to make it available globally for future connectivity testing across all labs. `apt` installs system-wide — not scoped to a directory.

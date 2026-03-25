# Lab 066 — Solution Walkthrough: Database Unreachable (RDS Security Group Issues)

---

## TLDR — Plain English Summary

You've been handed a ticket: the application can't connect to the database. Both live in the same VPC. Nothing else is known.

When you try to stand up the infrastructure, AWS immediately throws an error — the database won't even create. That error is your first clue and points you directly at the first thing to fix. Once infrastructure is up, the connectivity fault is still there — and tracking it down means reading security group rules carefully and knowing what "normal" looks like so you can spot what's wrong.

There are three things broken in total. You won't know that at the start — you'll find them one at a time as you work through the investigation.

---

## The Ticket

> **Application cannot connect to RDS database on port 3306. Both are deployed in the same VPC. Connection attempts are failing.**

That's all you have. You don't know why. You don't know where the fault is. You start by trying to deploy the infrastructure and see what happens.

---

## Phase 1: Stand Up the Infrastructure

### Step 1: Initialise and apply

You've been given a Terraform config. First thing — try to deploy it and see what happens.

```bash
terraform init
terraform apply
```

You'll be asked to confirm. Type `yes`.

**What you see:**

```
Error: creating RDS DB Instance (app-db): InvalidVPCNetworkStateFault:
Cannot create a publicly accessible DBInstance. The specified VPC has
no internet gateway attached.
```

The apply fails immediately. The database won't even create.

---

### Step 2: Read the error — what is it actually telling you?

Don't skip past this. The error message is specific:

- **`publicly accessible DBInstance`** — Terraform is trying to create a database that's reachable from the public internet
- **`VPC has no internet gateway attached`** — the VPC is private; there's no route out to the internet

AWS is refusing to create a publicly accessible database in a VPC that has no internet gateway. Those two things are incompatible.

**The question to ask yourself:** should this database be publicly accessible at all?

The answer is no. This database exists to serve an internal application. It should only ever be reachable from within the VPC. Making it publicly accessible is both unnecessary and a security risk.

---

### Step 3: Find the setting and fix it

Open `main.tf` and find the `aws_db_instance` resource. Look for `publicly_accessible`:

```bash
vi main.tf
```

You'll see:

```hcl
publicly_accessible = true
```

Change it to:

```hcl
publicly_accessible = false
```

Save and exit (`:wq`).

#### What does `publicly_accessible` actually control?

| Setting | What it does |
|---------|--------------|
| `true` | Assigns a public DNS name to the RDS instance; makes it reachable from outside the VPC if security groups allow |
| `false` | No public DNS name; DB is only reachable from within the VPC |

---

### Step 4: Apply again

```bash
terraform apply
```

This time the infrastructure builds. The VPC, subnets, security groups, and RDS instance all create successfully. RDS takes 4-5 minutes.

**You now have a running database — but the connectivity problem from the ticket is still there.** The infrastructure is up; now the investigation begins.

---

## Phase 2: Investigate the Connectivity Fault

### Step 5: Establish what you know before touching anything

Before you start changing things, take stock of what's been deployed. Look at the Terraform config and understand the setup:

- There's a VPC (`10.0.0.0/16`)
- There's an app subnet (`10.0.1.0/24`)
- There's a database sitting in its own subnets
- There are two security groups — one for the app (`app-sg`), one for the database (`db-sg`)
- The database has `db-sg` attached via `vpc_security_group_ids`

The application connects to the database on port 3306 (MySQL). For that to work, the database's security group must allow inbound traffic from the application on port 3306.

**This is where you start: the database security group.**

---

### Step 6: Read the database security group

In `main.tf`, find the `aws_security_group` resource named `"db"`. Read it carefully:

```hcl
resource "aws_security_group" "db" {
  name   = "db-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["10.0.99.0/24"]
  }
}
```

Walk through this line by line:

- `from_port = 3306`, `to_port = 3306`, `protocol = "tcp"` — correct, MySQL uses TCP on 3306
- `cidr_blocks = ["10.0.99.0/24"]` — this is the source. Only traffic from `10.0.99.0/24` is allowed in

**Now ask: where does the application actually live?**

---

### Step 7: Find the app subnet CIDR and compare

Look back at the Terraform config. Find the app subnet:

```hcl
resource "aws_subnet" "app" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  ...
}
```

Or pull it directly from state to be certain:

```bash
terraform state show aws_subnet.app | grep cidr
```

The app subnet is `10.0.1.0/24`.

**Now compare:**

| What the security group allows | Where the app actually is |
|-------------------------------|--------------------------|
| `10.0.99.0/24` | `10.0.1.0/24` |

These are completely different ranges. `10.0.99.x` and `10.0.1.x` have nothing in common — traffic from the app instance simply doesn't match the allowed CIDR. The security group silently drops every connection attempt. This is why connection attempts time out rather than getting an explicit refusal — the packets are dropped without response.

**This is Bug 1. You've found it by reading and comparing, not by guessing.**

---

### Step 8: How to read a CIDR so you can spot this at a glance

A CIDR like `10.0.1.0/24` breaks down like this:

```
10  .  0  .  1  .  0  /24
|      |     |     |
Fixed  Fixed Fixed  Variable (hosts 0-255)
```

The `/24` means the first 24 bits — the first three octets — are fixed. Only the last octet varies. So `10.0.1.0/24` covers `10.0.1.0` through `10.0.1.255`.

`10.0.99.0/24` covers `10.0.99.0` through `10.0.99.255`.

These ranges don't overlap at all. If you look at two `/24` addresses and the third octet is different, they are completely separate subnets. Traffic from one will never match a rule written for the other.

**Private IP ranges worth memorising:**
- `10.0.0.0/8` — the large private range AWS VPCs typically use
- `172.16.0.0/12`
- `192.168.0.0/16`

---

### Step 9: Fix the ingress rule — and use the better approach

You could just swap `10.0.99.0/24` for `10.0.1.0/24`. That would work. But there's a better pattern: reference the application's security group directly instead of its subnet CIDR.

**Why is this better?**

If you use a CIDR, the rule breaks the moment the app moves to a different subnet. If you reference the security group, the rule says "allow traffic from any instance with the app security group attached" — it works regardless of which subnet the app is in, and it's more readable.

Open `main.tf` and change the db security group ingress:

```hcl
# BROKEN — wrong CIDR, and fragile
ingress {
  from_port   = 3306
  to_port     = 3306
  protocol    = "tcp"
  cidr_blocks = ["10.0.99.0/24"]
}

# FIXED — correct source, more robust
ingress {
  from_port       = 3306
  to_port         = 3306
  protocol        = "tcp"
  security_groups = [aws_security_group.app.id]
}
```

#### Ingress rule fields explained

| Field | Value | What it means |
|-------|-------|---------------|
| `from_port` | `3306` | Start of the allowed port range |
| `to_port` | `3306` | End — same as from_port means exactly port 3306 only |
| `protocol` | `"tcp"` | MySQL uses TCP |
| `security_groups` | (reference) | Allow traffic from any instance with this SG attached |

---

### Step 10: Look at the security group again — is there anything else missing?

Now that you've fixed the ingress rule, read the whole security group again:

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
}
```

There's an ingress rule — but no egress rule.

**Does that matter?**

AWS security groups are stateful. In theory, return traffic for an established connection is automatically allowed. But in practice, Terraform-managed security groups without any egress block can behave unexpectedly and block all outbound traffic. The AWS console adds an allow-all egress rule by default when you create a security group. Terraform does not — if you don't define it, it doesn't exist.

Compare the app security group in the same config:

```hcl
resource "aws_security_group" "app" {
  name   = "app-sg"
  vpc_id = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

The app security group has an egress rule. The db security group doesn't. That inconsistency is a signal — the db security group is incomplete.

**This is Bug 2. You found it by reading carefully and comparing against what a complete security group looks like.**

---

### Step 11: Add the egress rule

Add an egress block to the db security group in `main.tf`:

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

#### Egress rule fields explained

| Field | Value | What it means |
|-------|-------|---------------|
| `from_port` | `0` | Combined with protocol `-1`: any port |
| `to_port` | `0` | Combined with protocol `-1`: any port |
| `protocol` | `"-1"` | AWS shorthand for all protocols |
| `cidr_blocks` | `["0.0.0.0/0"]` | Allow responses to any destination |

---

## Phase 3: Apply the Fixes and Validate

### Step 12: Review your changes before applying

Before you apply, it's good practice to validate and plan:

```bash
terraform validate
terraform plan
```

#### Command breakdown

| Command | What it does |
|---------|--------------|
| `terraform validate` | Checks HCL syntax — catches typos and structural errors before touching AWS |
| `terraform plan` | Shows exactly what Terraform would change — read this before applying |

**What to look for in the plan:**
- `aws_security_group.db` should show the ingress source changing from a CIDR to a security group reference, and a new egress block being added
- Nothing else should be changing — if you see unexpected changes, investigate before applying

### Step 13: Apply and run the validate script

```bash
terraform apply
./validate.sh
```

All checks should pass.

---

## Useful Commands for This Type of Fault

**Find the RDS endpoint when there's no outputs.tf:**
```bash
terraform state show aws_db_instance.main | grep endpoint
```

| Part | What it does |
|------|--------------|
| `terraform state show` | Reads the current state of a specific resource |
| `aws_db_instance.main` | The resource name — matches what's in main.tf |
| `grep endpoint` | Filters to just the endpoint lines |

Note: the endpoint includes the port (`hostname:3306`) — strip the `:3306` when passing to connection tools.

**Test TCP connectivity to a database port (from inside the VPC):**
```bash
nc -zv <rds-endpoint> 3306
```

| Part | What it does |
|------|--------------|
| `nc` | Netcat — raw TCP connection tool (`sudo apt install netcat-openbsd -y` on Pi) |
| `-z` | Zero I/O — just check if the port is open, don't send data |
| `-v` | Verbose — explicitly reports success or failure |

**What the response tells you:**
- `Connection timed out` → packets silently dropped — security group blocking traffic, no rule matches
- `Connection refused` → port actively rejected — DB not listening, or a different type of block
- `open` → success

**If nc isn't available (minimal containers, Alpine images):**
```bash
timeout 5 bash -c 'echo > /dev/tcp/<host>/3306' && echo "Connected" || echo "Failed"
```

Pure bash — no external tools needed.

**If your terminal stops showing what you type:**
```bash
stty sane
```
Resets terminal echo settings — happens when a command is killed mid-execution.

---

## Lab vs Real Life

| Lab Simplification | Production Reality |
|--------------------|--------------------|
| `password = "changeme123"` in plain text | Use `manage_master_user_password = true` — RDS manages rotation via Secrets Manager |
| Single-AZ deployment | `multi_az = true` — synchronous standby in a different AZ, auto-promotes on failure |
| No storage encryption | `storage_encrypted = true` with a KMS key |
| No deletion protection | `deletion_protection = true` — prevents accidental `terraform destroy` |
| No monitoring | `monitoring_interval` and `performance_insights_enabled = true` |
| No outputs.tf | Always expose the RDS endpoint as a Terraform output so app configs can reference it |

---

## What You Found and Why

Looking back once the investigation is complete:

| Bug | How you found it | Why it caused the symptom |
|-----|-----------------|--------------------------|
| `publicly_accessible = true` | Terraform apply failed with an explicit AWS error | VPC has no IGW — AWS refuses to create a public-facing DB in a private VPC |
| Wrong CIDR in ingress rule (`10.0.99.0/24`) | Read the SG, compared source CIDR against actual app subnet CIDR | Traffic from app silently dropped — no rule match |
| Missing egress rule | Read the whole SG, noticed no egress block, compared against app SG which had one | DB can't send response traffic back |

**The pattern that finds bugs like these every time:**
1. Try to deploy — read any errors carefully, they usually point directly at the problem
2. Read the security group rules — check source, port, protocol
3. Compare the source against where traffic is actually coming from
4. Check both ingress and egress — an incomplete security group is a common fault
5. Compare against working resources in the same config — inconsistencies are signals

---

## Pi / K3s Lab Notes

This is a Terraform/AWS lab — no Pi-specific caveats apply. All changes are in AWS infrastructure.

`nc` (netcat) is not installed on the Pi by default. Install once with `sudo apt install netcat-openbsd -y` — `apt` installs system-wide, not per-directory, so it's available everywhere after that.

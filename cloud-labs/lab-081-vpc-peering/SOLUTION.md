# Lab 081 — VPC Peering Traffic Blocked

## TLDR (Plain English)

Two private networks on AWS (VPC-A for the app, VPC-B for the database) are supposed to talk to each other through a "peering connection." The peering connection is set up, but traffic still can't get through.

Three things are wrong:

1. **Both networks use the same address range.** Imagine two offices both numbering their desks 1–100. If you say "send the package to desk 42," nobody knows which office you mean. Peering refuses to work when the address ranges overlap.
2. **Nobody told the networks how to find each other.** Even with a cable between the two offices, there's no sign saying "for desks in the other building, go through this cable." These signs are called **routes**, and they're missing from both route tables.
3. **The database's firewall doesn't know about the app's address range.** Even once the networks can see each other, the database's firewall rule is written vaguely — it needs to name the app network specifically.

**The fix, in order:** give the DB VPC a different address range (`10.1.0.0/16`), update its subnet to match, add routes in both route tables pointing to the peering connection, associate the route tables with their subnets, and update the DB firewall to allow traffic from the app's address range.

---

## The Ticket

> **SRE-4471** — "App team reports their service can't reach the shared database after our VPC peering migration. Peering connection shows **active** in console. Traffic isn't flowing. Terraform config is in `terraform-labs/lab-081-vpc-peering/`. Please investigate and fix."

You're a cloud engineer. You've been handed this ticket and nothing else. Let's walk through how you'd actually solve it.

---

## Background Theory (just enough to follow along)

Before we start, four concepts you'll need:

- **VPC (Virtual Private Cloud)** — an isolated private network in AWS. Each VPC has a CIDR block, which is its range of IP addresses (e.g. `10.0.0.0/16` = 65,536 addresses from `10.0.0.0` to `10.0.255.255`).
- **VPC Peering** — a direct network connection between two VPCs. Like a cable between two buildings: traffic can flow, but only if both sides know about the cable and agree to route traffic through it.
- **Route Table** — a set of rules inside a VPC that says "to reach X destination, send traffic to Y gateway/connection." Without a route entry, traffic has nowhere to go.
- **Security Group** — a stateful firewall attached to resources. Controls which sources/ports can reach the resource. A route lets traffic *arrive*; a security group decides whether to *accept* it.

All three have to be right for cross-VPC traffic to work. Any one broken and nothing flows.

---

## Step 0 — Set up the workspace

You've been given a path. Go there and get Terraform ready.

```bash
cd ~/cloud-engineer-labs/terraform-labs/lab-081-vpc-peering
terraform init
```

**Command breakdown:**

| Piece | What it does |
|---|---|
| `cd ~/cloud-engineer-labs/terraform-labs/lab-081-vpc-peering` | Move into the lab directory. `~` is your home directory. |
| `terraform init` | Downloads the AWS provider plugin and sets up the `.terraform/` working directory. Required once per repo clone before any other Terraform command will work. |

> **Why does `init` matter?** Terraform itself is just the engine. To talk to AWS (or any cloud), it needs a *provider* — basically a driver. `init` reads your `.tf` files, sees `provider "aws"`, and downloads the AWS plugin. Skip this and every other command fails with `Could not load plugin`.

---

## Step 1 — Read the ticket, then read the config

You've got a vague symptom ("traffic isn't flowing") and a config directory. There's no deployed infrastructure to poke at yet — your investigation starts with the source of truth: the Terraform files.

```bash
ls
cat main.tf
```

What am I looking for on first read?

1. **What resources exist?** — VPCs, subnets, peering connection, route tables, security groups.
2. **How do they connect to each other?** — does the topology look like it *should* work?
3. **Anything obviously missing?** — an empty route table, a security group with no rules, etc.

After reading `main.tf`, I can sketch the topology in my head:

```
┌─────────────────┐                           ┌─────────────────┐
│   VPC "app"     │                           │   VPC "db"      │
│   10.0.0.0/16   │◄─── peering connection ──►│   10.0.0.0/16   │
│                 │                           │                 │
│   subnet        │                           │   subnet        │
│   10.0.1.0/24   │                           │   10.0.2.0/24   │
│                 │                           │                 │
│   app-sg        │                           │   db-sg         │
│   (egress all)  │                           │   (ingress 5432)│
└─────────────────┘                           └─────────────────┘
```

Three things jump out immediately:

- **Both VPCs have the same CIDR** — `10.0.0.0/16`. That's suspicious. Can peered VPCs have overlapping ranges?
- **Both route tables exist but have no `route { ... }` block inside them.** They're empty shells.
- **Neither route table has an `aws_route_table_association` resource** — meaning even if I add routes, the subnets aren't pointed at these route tables.

Three red flags from one read. Let's verify my first hunch before changing anything.

---

## Step 2 — Diagnose Bug 1: Overlapping CIDR blocks

**What I see:** Both `aws_vpc.app` and `aws_vpc.db` declare `cidr_block = "10.0.0.0/16"`.

**What I need to know:** Is this actually a problem, or am I wrong?

**Where do I look?** AWS documentation is authoritative here. The rule: *peered VPCs must have non-overlapping CIDR blocks.* AWS refuses to route between identical ranges because it can't tell which VPC you mean.

**The reasoning:** Imagine a packet heading to `10.0.2.50`. The kernel checks its route table. "Is `10.0.2.50` in my local VPC? Yes, `10.0.0.0/16` covers it. Stay local." The peering route never gets considered, because the local route always wins. Overlapping CIDRs turn peering into dead weight.

**How do I fix it?** Change one VPC's CIDR so the ranges don't overlap. Convention: keep the app VPC on `10.0.0.0/16`, move the DB VPC to `10.1.0.0/16`.

But — there's a knock-on effect. The DB *subnet* is `10.0.2.0/24`, which is inside the OLD DB VPC range. If I change the VPC to `10.1.0.0/16` without updating the subnet, Terraform will error because the subnet no longer fits inside its parent VPC. So I need to update both.

**The change:**

```hcl
# Before
resource "aws_vpc" "db" {
  cidr_block = "10.0.0.0/16"
  tags = { Name = "db-vpc" }
}

resource "aws_subnet" "db" {
  vpc_id     = aws_vpc.db.id
  cidr_block = "10.0.2.0/24"
}

# After
resource "aws_vpc" "db" {
  cidr_block = "10.1.0.0/16"
  tags = { Name = "db-vpc" }
}

resource "aws_subnet" "db" {
  vpc_id     = aws_vpc.db.id
  cidr_block = "10.1.1.0/24"
}
```

> **Real-world note:** In a deployed environment, you can't just change a VPC's CIDR — AWS requires destroying and recreating the VPC and every resource inside it. This is why CIDR planning at the start of a project matters so much. In this lab we haven't applied yet, so the change is free.

---

## Step 3 — Diagnose Bug 2: Missing peering routes

**What I see:** Both `aws_route_table.app` and `aws_route_table.db` are declared with just `vpc_id` and nothing else — no `route { ... }` blocks inside.

**What that means:** A route table is a list of "to reach X, send traffic to Y" rules. AWS automatically includes one default rule (the VPC's own CIDR, routed locally) but nothing else. So the current tables effectively say: "for local VPC traffic, stay local. For anything else, drop it."

The peering connection exists, but with no route pointing at it, it's like a cable plugged in at both ends with the lights off.

**How do I know what route to add?**

1. **Destination CIDR** — the *other* VPC's range. App VPC needs a route to `10.1.0.0/16` (DB VPC). DB VPC needs a route to `10.0.0.0/16` (app VPC).
2. **Target** — the peering connection, referenced as `aws_vpc_peering_connection.app_to_db.id`.

**Both sides, or just one?** Both. TCP is bidirectional — the app sends a request, the database sends a response. If only the app VPC has a route, the request gets there but the response can't come back. Half-routed peering is a classic source of "it works but then hangs forever" bugs.

**The change:**

```hcl
resource "aws_route_table" "app" {
  vpc_id = aws_vpc.app.id

  route {
    cidr_block                = "10.1.0.0/16"
    vpc_peering_connection_id = aws_vpc_peering_connection.app_to_db.id
  }
}

resource "aws_route_table" "db" {
  vpc_id = aws_vpc.db.id

  route {
    cidr_block                = "10.0.0.0/16"
    vpc_peering_connection_id = aws_vpc_peering_connection.app_to_db.id
  }
}
```

### Step 3b — A second issue hiding inside Bug 2: no route table associations

Even with routes added, there's a subtle second problem: creating a route table doesn't automatically attach it to any subnet. If the subnets aren't *associated* with these route tables, they fall back to the VPC's default (main) route table, which has no peering routes either.

**How would I notice this in a real investigation?** After deploying, I'd run:

```bash
aws ec2 describe-route-tables --filters Name=vpc-id,Values=<vpc-id>
```

and see two route tables per VPC — the "main" one (with associations) and my custom one (with routes but no associations). That mismatch is the smell.

**The fix:**

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

> **Why is this a separate resource?** Terraform mirrors AWS's own API. In AWS, a route table and its association to a subnet are two different API calls. Terraform follows suit. It's also more flexible — one route table can be associated with many subnets via multiple association resources.

---

## Step 4 — Diagnose Bug 3: Security group CIDR ambiguity

**What I see:** `aws_security_group.db` has an ingress rule allowing port 5432 from `cidr_blocks = ["10.0.0.0/16"]`.

**What's wrong?** Back when both VPCs used `10.0.0.0/16`, this CIDR was *technically* the app VPC's range — but also the DB VPC's own range. After the Bug 1 fix, the DB VPC is now `10.1.0.0/16`, and `10.0.0.0/16` now cleanly refers to the app VPC. So this one might look like it works now — but let's reason about it properly.

**The question:** Should the DB security group ingress reference the app VPC's CIDR?

**Answer:** Yes. The whole point of the peering is "let the app reach the database." The DB security group's job is to allow PostgreSQL (5432) *from* the app VPC. After fixing Bug 1, `10.0.0.0/16` is now the app VPC range, which is what we want.

So this rule was broken by *coincidence of overlap* in the original config, not by an explicit wrong value. Once Bug 1 is fixed, the existing value happens to be correct — but it's worth reviewing to confirm, not assuming.

**What I'd double-check:** I want the DB security group to explicitly allow the *app* VPC's CIDR, and nothing from its own VPC by accident. Let me confirm the ingress rule still reads `10.0.0.0/16` (the new, unambiguous app VPC) and move on.

```hcl
resource "aws_security_group" "db" {
  name   = "db-sg"
  vpc_id = aws_vpc.db.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]    # App VPC CIDR — now unambiguous after Bug 1 fix
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
```

I also added an egress rule so the DB can send responses back. Without explicit egress, Terraform's default is... actually, AWS *does* allow all egress by default on a new SG, but Terraform's `aws_security_group` resource **strips the default egress rule** unless you declare it explicitly. That's a well-known Terraform gotcha. Add it to be safe.

---

## Step 5 — Validate the changes

Save the file. Run Terraform's own validation, then the lab's validator.

```bash
terraform validate
terraform plan
./validate.sh
```

**Command breakdown:**

| Command | What it checks |
|---|---|
| `terraform validate` | Syntax is valid HCL, resource types exist, references resolve. Does NOT check semantics (e.g. CIDR overlap, missing routes — AWS-level constraints). |
| `terraform plan` | Shows what Terraform would create/update/destroy on the next `apply`. Useful to review intent before committing. |
| `./validate.sh` | Lab-specific checks that catch the semantic bugs Terraform itself won't — CIDR uniqueness across VPCs, peering routes present on both sides, route table associations, security group CIDR correctness. |

If `validate.sh` reports `Results: 7 passed, 0 failed`, the config is good.

---

## Step 6 — (Optional) Deploy and verify end-to-end

In a real investigation you'd now:

```bash
terraform apply
```

And then confirm the fix with the AWS CLI:

```bash
# Peering connection is active
aws ec2 describe-vpc-peering-connections \
  --filters Name=status-code,Values=active

# Both route tables have the peering route
aws ec2 describe-route-tables \
  --filters Name=vpc-id,Values=<app-vpc-id>

aws ec2 describe-route-tables \
  --filters Name=vpc-id,Values=<db-vpc-id>
```

For this lab we're not deploying — the learning goal is to reason about the config. Skip to cleanup.

---

## Cleanup

Terraform owns everything it created. Destroy it with one command.

```bash
terraform destroy
```

> **⚠️ Always run `terraform destroy` at the end of every Terraform lab.** Even if you didn't `apply` in this one, make `destroy` a muscle-memory end-of-lab step. VPCs, NAT gateways, EIPs, and RDS instances in particular can quietly run up significant bills if left behind. `destroy` reads the state file and removes every resource Terraform created, in reverse dependency order.

If you didn't `apply` (as in this lab), `terraform destroy` will simply report "No changes" and exit cleanly. No harm done.

---

## Lab vs Real Life

- **Transit Gateway for scale.** Peering is point-to-point. 3 VPCs = 3 peering connections; 10 VPCs = 45. Past roughly 4–5 VPCs, switch to AWS Transit Gateway — hub-and-spoke, one central routing domain.
- **Cross-account peering.** Works, but the peer account must explicitly accept the request (no auto-accept across accounts for security reasons).
- **Cross-region peering.** Supported. Traffic stays on the AWS backbone, encrypted in transit. Costs more than same-region.
- **IPAM for CIDR planning.** Production orgs use AWS IP Address Manager (IPAM) to allocate non-overlapping CIDRs across dozens of VPCs. Reactively fixing CIDR overlap after VPCs are populated with workloads is painful — think VPC recreation, IP changes, DNS updates.
- **DNS resolution over peering.** By default, instances in peered VPCs resolve each other's private DNS names to *public* IPs. Enable `allow_remote_vpc_dns_resolution = true` via `aws_vpc_peering_connection_options` to resolve to private IPs instead.
- **Peering is non-transitive.** A ↔ B and B ↔ C does NOT give you A ↔ C. Each pair needs its own peering (or use Transit Gateway).

---

## Key Concepts Learned

- **Non-overlapping CIDRs are a hard requirement for peering.** Plan before you create VPCs.
- **Connectivity is a three-layer problem.** The connection (peering), the routes (route tables), and the permissions (security groups) all have to be right. Any one wrong = no traffic.
- **Routes are bidirectional.** Every connection needs a route on both sides, or responses can't return.
- **Route tables need associations.** Creating a route table isn't enough; subnets must be associated with it, or they fall back to the VPC's main route table.
- **Terraform doesn't check semantics.** `terraform validate` happily passes on broken topologies. AWS-level rules (CIDR overlap, missing routes) only surface at `apply` time or later.
- **`aws_security_group` strips default egress.** Always declare egress explicitly in Terraform-managed SGs.

---

## Common Mistakes

- **Routes only on one side.** Request flows out, response can't come back. Looks like hangs/timeouts.
- **Forgetting route table associations.** The custom route table exists with correct routes, but the subnet uses the VPC's main route table instead. Silent failure.
- **Assuming peering status = connectivity.** "Active" only means AWS accepted the connection. Routes and SGs still need to be right.
- **Reusing CIDR ranges across environments.** Dev `10.0.0.0/16`, staging `10.0.0.0/16`, prod `10.0.0.0/16` — impossible to peer any of them together later.
- **Expecting transitive peering.** Classic wrong assumption. Each pair of VPCs needs its own connection.

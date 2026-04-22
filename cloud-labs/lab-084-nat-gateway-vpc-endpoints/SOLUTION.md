# Lab 084 — Private Subnet Can't Reach AWS Services (NAT Gateway & VPC Endpoints)

## TLDR (plain English)

A private EC2 instance can't reach the internet or S3. Four things are wrong with the VPC networking:

1. **The NAT Gateway is in the wrong subnet.** It's been placed in the private subnet, but a NAT Gateway only works if it sits in a public subnet (because it needs its own path to the Internet Gateway).
2. **The private subnet's default route points to the Internet Gateway directly.** Private instances have no public IPs, so the IGW has nothing to route their traffic to. The default route should point at the NAT Gateway instead.
3. **The S3 VPC Endpoint is attached to the wrong route table.** It's on the public route table, but the instances that need S3 are in the private subnet.
4. **The S3 VPC Endpoint policy is set to Deny.** Even if the routing were right, this would block all S3 traffic through the endpoint.

Fix: move the NAT Gateway to the public subnet, change the private route table's default route to target the NAT Gateway (not the IGW), move the endpoint's route-table association from public to private, and flip the policy from Deny to Allow. Re-apply. SSM into the instance, `curl https://www.google.com` returns `HTTP 200`, `aws s3 ls` succeeds. Done.

---

## The Ticket

> **INCIDENT-NET-002**: Application in private subnet (`10.0.2.0/24`) cannot pull packages or access S3. `curl https://www.google.com` hangs. `aws s3 ls` hangs. Platform team says NAT Gateway and S3 VPC Endpoint are deployed. Find out why traffic isn't flowing and restore connectivity.

You're on-call. You've been handed a Terraform repo that defines the environment. The application team is blocked. The platform team insists "everything is deployed". Your job is to confirm the fault, find the root causes, and fix them.

You do **not** yet know there are four bugs. You do not yet know what they are. You approach this like a real incident.

---

## Step 1 — Arrive at the scene, establish what's deployed

### 1a. What does the Terraform repo look like?

```bash
cd ~/cloud-engineer-labs/cloud-labs/lab-084-nat-gateway-vpc-endpoints
ls -la
```

You see `main.tf`, `CHALLENGE.md`, `validate.sh`. No pre-baked fixes, no hints.

### 1b. Apply the Terraform so you can see what's actually deployed

Before you can diagnose anything, the infrastructure needs to exist. If the lab has already been applied, skip this.

```bash
terraform init
terraform apply -auto-approve
```

This takes roughly 2-3 minutes — the NAT Gateway and Interface endpoints are the slow resources. When it finishes, grab the outputs:

```bash
terraform output
```

You'll see something like:

```
bucket_name = "lab-084-test-e3f399a9"
instance_id = "i-000512fa3d9212270"
region      = "eu-west-2"
```

**Why grab these first?** Because the fastest way to confirm the fault is to go to the instance itself and reproduce it. You're not going to open `main.tf` yet — an engineer on-call should always confirm the symptoms before theorising about causes.

---

## Step 2 — Reproduce the fault from inside the private instance

### 2a. Connect via SSM Session Manager

The instance is in a private subnet. It has no public IP, no SSH key, no bastion. The only way in is AWS Systems Manager Session Manager, which reaches the instance through the SSM agent running on it — not through SSH.

```bash
INSTANCE_ID=$(terraform output -raw instance_id)
aws ssm start-session --target "$INSTANCE_ID" --region eu-west-2
```

**Command breakdown:**

| Part | Meaning |
|------|---------|
| `aws ssm start-session` | Opens an interactive shell through AWS Systems Manager — no SSH, no port 22, no public IP required |
| `--target "$INSTANCE_ID"` | The EC2 instance ID you want to connect to |
| `--region eu-west-2` | AWS region the instance lives in |

**Expect a `TargetNotConnected` error the first time.** This is common and diagnostic:

```
aws: [ERROR]: An error occurred (TargetNotConnected) when calling the StartSession
operation: i-000512fa3d9212270 is not connected.
```

The SSM agent on the instance tried to register with the SSM service at boot, kept failing, and eventually backed off. A fresh boot fixes it:

```bash
terraform taint aws_instance.private
terraform apply -auto-approve
```

Takes ~30 seconds. Then verify the agent has registered this time:

```bash
aws ssm describe-instance-information \
  --region eu-west-2 \
  --query 'InstanceInformationList[*].[InstanceId,PingStatus,PlatformName]' \
  --output table
```

You want `PingStatus` = `Online`. Then retry the session.

> **Concept aside — why SSM works on a broken-NAT instance:** The lab provisions three **SSM Interface VPC Endpoints** (`ssm`, `ssmmessages`, `ec2messages`) in the private subnet. The agent reaches the SSM service through those endpoints directly, bypassing the (broken) NAT path. This is genuinely how production-grade VPCs are built: never trust NAT for management-plane access, because if NAT breaks you lose your way in. More on this in the PPT.

### 2b. Try to reach the internet

Inside the SSM session:

```bash
curl -m 5 https://www.google.com
```

The `-m 5` caps the timeout at 5 seconds so you don't wait forever. You'll see:

```
curl: (28) Connection timed out after 5000 milliseconds
```

Internet egress is broken. SYN packets went out, nothing came back.

### 2c. Try to reach S3

Do **not** run this naively — the AWS CLI will hang for minutes before timing out. Wrap it:

```bash
timeout 10 aws s3 ls s3://lab-084-test-e3f399a9 2>&1
```

It'll hang for the full 10 seconds then get killed by the `timeout` command. No error message at all. That **absence** of a response is itself diagnostic: if the VPC endpoint were in the path and the endpoint policy denied, S3 would return a fast AccessDenied. A total hang means the packets aren't reaching S3 or the endpoint at all.

> **Concept aside — timeouts vs AccessDenied:** this is one of the most useful signal patterns in AWS troubleshooting.
>
> | Symptom | Tells you |
> |---------|-----------|
> | Call hangs with no response | Network problem — VPC / routing / security groups / endpoints |
> | Call returns an error fast (`AccessDenied`, `Forbidden`) | Network is fine — the problem is IAM / bucket policy / endpoint policy |
>
> You'll use this constantly. Internalise it.

### 2d. Confirm the instance's own networking is fine

```bash
ip route
cat /etc/resolv.conf
exit
```

You'll see:

```
default via 10.0.2.1 dev ens5 proto dhcp src 10.0.2.60 metric 512
10.0.0.2 via 10.0.2.1 dev ens5 proto dhcp src 10.0.2.60 metric 512
10.0.2.0/24 dev ens5 proto kernel scope link src 10.0.2.60 metric 512
...
nameserver 10.0.0.2
```

- `default via 10.0.2.1` — the instance's default route points to the VPC router at the private subnet's `.1` address. Correct.
- `nameserver 10.0.0.2` — AmazonProvidedDNS (the `.2` reserved address in every VPC). DNS is working.

The instance is doing everything it should. The fault is in the VPC layer — route tables, NAT Gateway, or VPC Endpoint configuration.

---

## Step 3 — Investigate the NAT Gateway path

### 3a. The theory

Expected path for internet traffic from a private instance:

```
private instance → private route table → NAT Gateway (in public subnet) → public route table → Internet Gateway → internet
```

Five things have to be right:

1. Private subnet is associated with a route table
2. That route table has a default route (`0.0.0.0/0`) pointing to a NAT Gateway
3. The NAT Gateway exists and is `available`
4. The NAT Gateway is in a **public** subnet (because it needs outbound internet access itself)
5. The public route table has a default route to the IGW

### 3b. Where is the NAT Gateway actually placed?

```bash
aws ec2 describe-nat-gateways \
  --region eu-west-2 \
  --filter "Name=state,Values=available" \
  --query 'NatGateways[*].[NatGatewayId,SubnetId,State]' \
  --output table
```

**Command breakdown:**

| Part | Meaning |
|------|---------|
| `describe-nat-gateways` | Lists all NAT Gateways in the region |
| `--filter "Name=state,Values=available"` | Only show ones that are live (not deleted/pending) |
| `--query 'NatGateways[*].[NatGatewayId,SubnetId,State]'` | JMESPath: for each NAT Gateway, pull just ID, subnet, state |
| `--output table` | Pretty ASCII-table output instead of JSON |

Output:

```
--------------------------------------------------------------------
|                        DescribeNatGateways                       |
+------------------------+----------------------------+------------+
|  nat-03f60dffa771094be |  subnet-0a744366e682c636c  |  available |
+------------------------+----------------------------+------------+
```

Note the SubnetId. Now check: is that subnet public or private?

### 3c. Check whether the NAT's subnet is public

Two complementary checks. First the fastest — the Name tag and `MapPublicIpOnLaunch`:

```bash
aws ec2 describe-subnets \
  --region eu-west-2 \
  --subnet-ids subnet-0a744366e682c636c \
  --query 'Subnets[0].[SubnetId,CidrBlock,Tags[?Key==`Name`].Value|[0],MapPublicIpOnLaunch]' \
  --output table
```

Output:

```
------------------------------
|       DescribeSubnets      |
+----------------------------+
|  subnet-0a744366e682c636c  |
|  10.0.2.0/24               |
|  private-subnet            |
|  False                     |
+----------------------------+
```

Then the ground-truth check — does the subnet's route table have an IGW route?

```bash
aws ec2 describe-route-tables \
  --region eu-west-2 \
  --filters "Name=association.subnet-id,Values=subnet-0a744366e682c636c" \
  --query 'RouteTables[0].Routes[*].[DestinationCidrBlock,GatewayId,NatGatewayId]' \
  --output table
```

Output:

```
--------------------------------------------------
|               DescribeRouteTables              |
+--------------+-------------------------+-------+
|  10.0.0.0/16 |  local                  |  None |
|  0.0.0.0/0   |  igw-05539e7acec235298  |  None |
+--------------+-------------------------+-------+
```

> **Concept aside — "ground truth vs labels":** tags can lie. In real environments, you'll find subnets tagged `public` that have no IGW route, or "prod" security groups used in staging. The only authoritative definition of a public subnet is: has a `0.0.0.0/0 → igw-...` route. Always check behaviour, not just labels.

**Both checks agree:** the NAT Gateway is in `10.0.2.0/24`, tagged `private-subnet`, with `MapPublicIpOnLaunch=False`. The route table associated with that subnet does have an IGW route — but that's a second and separate problem we'll come back to. The NAT Gateway shouldn't be there regardless.

### 3d. Why is that wrong, in plain terms?

A NAT Gateway needs two things:
- A **public IP address** (the Elastic IP — it has one)
- A **route to an Internet Gateway** so it can send its translated traffic out

That route comes from the route table of whichever subnet it's placed in. In a properly-configured VPC, a private subnet's route table does NOT have an IGW route — because if it did, the subnet wouldn't be private. So a NAT Gateway placed in a private subnet has no way to reach the internet. It has a public IP and nowhere to send traffic. Dead end.

**This is bug #1.** Fix — in `main.tf`, find `aws_nat_gateway "main"`:

```hcl
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.private.id   # <-- change to aws_subnet.public.id
  ...
}
```

Don't re-apply yet — we might find more bugs on the same path.

### 3e. What does the private route table's default route target?

We partially saw this above. Let's look at the private route table directly by name:

```bash
aws ec2 describe-route-tables \
  --region eu-west-2 \
  --filters "Name=tag:Name,Values=private-rt" \
  --query 'RouteTables[0].Routes[*].[DestinationCidrBlock,GatewayId,NatGatewayId,VpcEndpointId]' \
  --output table
```

You see a `0.0.0.0/0` row with the `GatewayId` column populated with `igw-...`. The private subnet's default route points **directly at the Internet Gateway**.

**Why is that wrong?** An Internet Gateway routes traffic for instances that have **public IP addresses**. It does Source NAT using the instance's own public IP. The private instance has no public IP (`MapPublicIpOnLaunch=False`), so when IGW receives its traffic, there's no mapping and it drops the packet. No response comes back. This matches exactly what we saw with `curl` timing out.

**This is bug #2.** Fix — in `aws_route_table "private"`:

```hcl
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id   # <-- change whole block
  }
  ...
}
```

Change to:

```hcl
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
```

**The attribute rename matters:**

| Attribute | Used for |
|-----------|----------|
| `gateway_id` | Internet Gateway, Virtual Private Gateway, Carrier Gateway |
| `nat_gateway_id` | NAT Gateway |
| `vpc_endpoint_id` | (not set manually — AWS adds the prefix-list route automatically when you associate an endpoint with a route table) |
| `transit_gateway_id` | Transit Gateway |

Terraform will reject `gateway_id = aws_nat_gateway.main.id` as a type mismatch because a NAT Gateway isn't a "gateway" in the `gateway_id` sense. Common gotcha.

---

## Step 4 — Investigate the S3 VPC Endpoint path

Internet egress is two bugs' worth of diagnosis. S3 has its own path — the VPC Endpoint.

### 4a. The theory for Gateway endpoints

An S3 VPC Endpoint is a **Gateway endpoint** (not an Interface endpoint — see the PPT for the distinction). Gateway endpoints work by adding a route to the route tables you associate them with. That route uses a **prefix list** (`pl-...`) matching all S3 IP ranges, targeted at the endpoint.

For the private instance to reach S3 via the endpoint:
1. The endpoint must be associated with the **private** route table
2. The endpoint policy must allow the S3 actions the caller needs

### 4b. Which route table is the endpoint associated with?

Look at the public route table:

```bash
aws ec2 describe-route-tables \
  --region eu-west-2 \
  --filters "Name=tag:Name,Values=public-rt" \
  --query 'RouteTables[0].Routes[*].[DestinationCidrBlock,GatewayId,NatGatewayId]' \
  --output table
```

Output:

```
---------------------------------------------------
|               DescribeRouteTables               |
+--------------+--------------------------+-------+
|  10.0.0.0/16 |  local                   |  None |
|  0.0.0.0/0   |  igw-05539e7acec235298   |  None |
|  None        |  vpce-0f00e6680c66ea9e6  |  None |
+--------------+--------------------------+-------+
```

The third row — where the destination is `None` (a prefix list, not a CIDR) and the target is `vpce-0f00e6680c66ea9e6` — is the S3 prefix-list route. And it's sitting in the **public** route table.

> **Concept aside — the overloaded `GatewayId` field:** AWS stores the endpoint ID in the `GatewayId` field for prefix-list routes, not a separate `VpcEndpointId`. That field can hold `local`, an IGW ID, a VGW ID, or a VPC Endpoint ID depending on the route type. If you ever write inventory or validation scripts, be ready for this — parsing route objects naively catches a lot of people out.

**This is bug #3.** The private subnet's route table has no prefix-list route for S3, so the private instance has no way to reach S3 via the endpoint.

Fix — in `aws_vpc_endpoint "s3"`:

```hcl
route_table_ids = [aws_route_table.public.id]   # <-- change
```

to:

```hcl
route_table_ids = [aws_route_table.private.id]
```

### 4c. Inspect the endpoint policy

First grab the endpoint ID from the route table row above, then query the policy:

```bash
aws ec2 describe-vpc-endpoints \
  --region eu-west-2 \
  --vpc-endpoint-ids vpce-0f00e6680c66ea9e6 \
  --query 'VpcEndpoints[0].PolicyDocument' \
  --output text | jq .
```

**Command breakdown:**

| Part | Meaning |
|------|---------|
| `--vpc-endpoint-ids vpce-...` | The endpoint ID from the route table row |
| `--query 'VpcEndpoints[0].PolicyDocument'` | Pull just the policy JSON string |
| `--output text` | Emit it as a raw string (otherwise JSON would escape all the inner quotes) |
| `\| jq .` | Pretty-print the resulting JSON |

Output:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Deny",
      "Principal": "*",
      "Action": "s3:*",
      "Resource": "*"
    }
  ]
}
```

> **Concept aside — read policies backwards:** the default top-to-bottom reading (Effect → Principal → Action → Resource) leaves you hanging. Reading backwards — Action → Resource → Principal → Effect — produces the natural sentence "this action, on this resource, by this principal, is allowed/denied." Matches how you actually reason about access control.

Reading this one backwards:

| Order | Field | Value | Plain English |
|-------|-------|-------|---------------|
| 1 | Action | `s3:*` | Every S3 API call |
| 2 | Resource | `*` | Against any S3 resource |
| 3 | Principal | `*` | By anyone |
| 4 | Effect | `Deny` | Is denied |

Every S3 action, everywhere, by anyone, denied. Even if routing were perfect, this would kill all S3 traffic through the endpoint.

**This is bug #4.** Fix:

```hcl
Effect = "Deny"   # <-- change to "Allow"
```

---

## Step 5 — Apply all four fixes and re-validate

### 5a. Review the plan

```bash
terraform plan
```

Expected summary: `Plan: 1 to add, 2 to change, 1 to destroy`. Specifically:

- `aws_nat_gateway.main` — **replaced** (NAT Gateways can't have their subnet changed in-place; destroy + create, ~2 min)
- `aws_route_table.private` — modified in place (route block changes)
- `aws_vpc_endpoint.s3` — modified in place (route_table_ids and policy both update without replacement)

If you see anything else being touched — subnets, IAM roles, the VPC itself, the instance — stop and investigate before applying.

### 5b. Apply

```bash
terraform apply -auto-approve
```

Takes ~2-3 minutes. NAT Gateway destroy + create is the slow part.

### 5c. Reproduce the test from inside the instance

```bash
INSTANCE_ID=$(terraform output -raw instance_id)
BUCKET=$(terraform output -raw bucket_name)
aws ssm start-session --target "$INSTANCE_ID" --region eu-west-2
```

Inside the session (substitute your bucket name):

```bash
curl -m 10 -s -o /dev/null -w "HTTP %{http_code} in %{time_total}s\n" https://www.google.com
aws s3 ls s3://lab-084-test-e3f399a9
aws s3 cp /etc/hostname s3://lab-084-test-e3f399a9/test.txt
aws s3 ls s3://lab-084-test-e3f399a9
exit
```

Expected:

```
HTTP 200 in 0.067331s
<empty listing, no error>
upload: ../../etc/hostname to s3://lab-084-test-e3f399a9/test.txt
2026-04-22 14:23:01          3 test.txt
```

- `curl` returns HTTP 200 fast — NAT path works
- `aws s3 ls` returns empty with no error — endpoint reachable, policy permits list, bucket exists and is empty
- `aws s3 cp` uploads a small file (the instance's hostname) — endpoint permits PutObject
- `aws s3 ls` now shows the uploaded file — full round trip confirmed

### 5d. Run the validator

```bash
./validate.sh
```

All 8 checks pass. If any fail, the check description tells you exactly which piece of AWS state didn't match — fix that resource and re-run.

---

## Key concepts learned

- **NAT Gateways live in public subnets.** They need their own route to an Internet Gateway to send translated traffic out. A NAT Gateway in a private subnet is a dead end.
- **Private subnets route through NAT, not IGW.** An Internet Gateway only routes traffic for instances with public IPs. Private instances don't have public IPs, so IGW drops their packets.
- **`nat_gateway_id` vs `gateway_id` in Terraform route blocks.** Different attributes for different resource types. Using the wrong one produces confusing errors.
- **VPC Endpoints bypass NAT for their target service.** S3 and DynamoDB Gateway endpoints add a prefix-list route directly into the associated route table, keeping traffic on the AWS backbone.
- **Route table associations determine reach.** A VPC Endpoint only affects traffic in subnets whose route tables are associated with it.
- **Endpoint policies are a defence-in-depth layer.** They filter which API calls go through the endpoint, independent of IAM. An explicit Deny here will block traffic even if IAM allows it.
- **Read policies backwards:** Action → Resource → Principal → Effect. Makes the intent clearer.
- **Timeouts vs AccessDenied:** different diagnostic signals for network vs authorisation problems.
- **`terraform taint` (or `apply -replace=...`):** forces a destroy+recreate when a resource's creation-time setup is stuck.
- **The overloaded `GatewayId` field:** the same field holds IGW, VGW, and VPC Endpoint IDs in route objects. Don't assume schemas — dump the JSON.

---

## Lab vs Real Life

- **Real VPCs use multiple Availability Zones.** This lab uses a single AZ for simplicity. In production you'd put a NAT Gateway in each public subnet across AZs — otherwise a single-AZ NAT outage takes down all private egress in the region.
- **Real endpoint policies are scoped, not `*`.** In production, limit `Resource` to specific bucket ARNs and `Action` to the specific S3 operations the application needs. Wildcards are fine for a lab but a poor default in real life.
- **Real production outages don't always have SSM working.** This lab provisions SSM Interface endpoints precisely so you retain management access when NAT is broken. Not every VPC is built this way — if yours isn't and NAT dies, you'd diagnose from the VPC side using VPC Flow Logs, Reachability Analyzer, or by temporarily adding a bastion.
- **Real teams use Reachability Analyzer.** AWS has a built-in tool (`aws ec2 create-network-insights-path`) that traces a theoretical packet's path through your VPC and tells you exactly where it drops. Worth knowing.
- **Real incidents involve tickets, runbooks, and comms.** In this lab you're solo. Real incident response would loop in the platform team, post updates in Slack, and document the root cause for a post-mortem.

---

## Cleanup / reset

When done, destroy everything to avoid NAT Gateway and EIP charges:

```bash
terraform destroy -auto-approve
```

This lab is re-runnable: destroy, then `terraform apply -auto-approve` recreates the broken starting state (since the bugs live in `main.tf` and Terraform produces whatever the file says).

To reset mid-run without destroying (e.g. you want to start over):

```bash
git checkout main.tf            # revert any edits
terraform apply -auto-approve   # snap infrastructure back to broken state
```

**Do not leave the NAT Gateway running overnight.** At roughly $0.05/hour per NAT Gateway plus data processing, plus $0.01/hour per Interface endpoint × 3, an unattended lab becomes real money over a week.

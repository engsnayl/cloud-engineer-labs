# Solution — Lab 092: Live Right-Sizing with AWS Compute Optimizer

---

## TLDR (Plain English)

In Lab 090 you spotted over-provisioning by reading Terraform code. That is a valid real-world skill. But there is a second, equally important question: how do you *prove* the right-sizing decision is correct? The answer is data. AWS has a free tool called Compute Optimizer that watches your running instances, analyses their actual CPU, memory, disk, and network usage over the past 14 days, and tells you exactly which ones are too big — and what to change them to.

This lab deploys real over-provisioned instances, seeds two weeks of simulated low-utilisation data into CloudWatch, and lets Compute Optimizer do what it would do in a real job. You then read the output, interpret it, and apply a change. By the end you have experienced the full real-world right-sizing workflow — not just the theory.

The one shortcut: we seed simulated CloudWatch data rather than waiting 14 days for real traffic. The tool, the output, and the decisions are all real. The underlying metric values are synthetic — but realistic.

---

## Important Before You Start — Architecture Note

The `main.tf` in this lab uses `m5.2xlarge` and `m5.xlarge` instance types — both x86_64 (Intel). The AMI is fetched dynamically with a `data "aws_ami"` block. If you see an error like `InvalidAMIID.NotFound` or `InvalidAMIAttributeItemValue` on apply, it usually means the AMI architecture filter returned an ARM image that is incompatible with x86 instance types.

If this happens, run `terraform apply` again — or run:

```bash
aws ec2 describe-images \
  --region eu-west-2 \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-*-x86_64" "Name=state,Values=available" \
  --query "sort_by(Images, &CreationDate)[-1].ImageId" \
  --output text
```

Then temporarily hardcode that AMI ID in `main.tf` to bypass the data source.

---

## Step 1 — Read the Lab Brief and Understand What You Are Being Asked to Do

You have been given a lab. Resist the urge to immediately run commands. Read the `CHALLENGE.md` first.

```bash
cat CHALLENGE.md
```

The brief tells you:
- What gets deployed and why it is over-provisioned
- What the learning objective is
- The order of operations: deploy → seed → wait → read → apply → destroy

This matters because there is a genuine wait in the middle of this lab. Compute Optimizer takes up to 12 hours to process CloudWatch data. This is a come-back-tomorrow lab, not a one-sitting lab. Plan accordingly.

---

## Step 2 — Initialise and Deploy the Infrastructure

Move into the lab directory and initialise Terraform:

```bash
cd ~/cloud-engineer-labs/terraform-aws/lab-092
terraform init
```

**Command Breakdown — `terraform init`:**

| Part | What It Does |
|------|-------------|
| `terraform` | The Terraform CLI |
| `init` | Downloads the AWS provider plugin, sets up the working directory, prepares the backend. Must be run once before any other Terraform command |

Review what will be created before applying:

```bash
terraform plan
```

Read the plan output. You should see 9 resources being created: 1 VPC, 1 subnet, 1 internet gateway, 1 route table, 1 route table association, 1 security group, 2 prod web instances, 1 dev web instance, 2 dev worker instances.

Look at the instance types in the plan output:

```
+ resource "aws_instance" "prod_web" {
    + instance_type = "m5.2xlarge"
    ...
```

Note this. `m5.2xlarge` is 8 vCPU and 32GB RAM. This is what you are deploying deliberately — it is the over-provisioned starting state.

Now apply:

```bash
terraform apply
```

Type `yes` when prompted. The apply takes 1–2 minutes.

**Command Breakdown — `terraform apply`:**

| Part | What It Does |
|------|-------------|
| `terraform` | The Terraform CLI |
| `apply` | Creates, modifies, or destroys real AWS resources to match the `.tf` configuration. Changes are irreversible without a subsequent `destroy` |
| Interactive `yes` prompt | Forces you to acknowledge that real infrastructure is being created — cannot be bypassed unless you pass `-auto-approve` (avoid this in learning contexts) |

---

## Step 3 — Verify the Instances Are Running

Once apply completes, Terraform prints your outputs. You will see instance IDs — note them. These are the IDs everything else in this lab depends on.

Confirm the instances are running:

```bash
aws ec2 describe-instances \
  --region eu-west-2 \
  --filters "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].{ID:InstanceId,Type:InstanceType,Name:Tags[?Key=='Name']|[0].Value}" \
  --output table
```

**Command Breakdown — `aws ec2 describe-instances`:**

| Part | What It Does |
|------|-------------|
| `aws ec2 describe-instances` | Lists EC2 instances and their full configuration |
| `--filters "Name=instance-state-name,Values=running"` | Only return instances currently in the `running` state |
| `--query "Reservations[].Instances[].{...}"` | JMESPath expression — extracts just the fields we care about from the JSON response. The `Tags[?Key=='Name']` part digs into the tags array to find the `Name` tag value |
| `--output table` | Formats as a human-readable table instead of raw JSON |

You should see 5 rows — all showing `m5.2xlarge` or `m5.xlarge`. These are the over-provisioned types.

---

## Step 4 — Look at CloudWatch Right Now (Before Seeding)

Before running the seeder, check what CloudWatch actually shows for one of your instances. This is an important diagnostic step — you want to understand what "no data" looks like before you understand what "14 days of data" looks like.

Get the first prod web instance ID from Terraform:

```bash
terraform output -json prod_web_instance_ids | python3 -c "import sys,json; print(json.load(sys.stdin)[0])"
```

Save it to a variable:

```bash
INSTANCE_ID=$(terraform output -json prod_web_instance_ids | python3 -c "import sys,json; print(json.load(sys.stdin)[0])")
```

Now query CloudWatch for the past 14 days:

```bash
aws cloudwatch get-metric-statistics \
  --region eu-west-2 \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --start-time $(date -u -d '14 days ago' '+%Y-%m-%dT%H:%M:%S') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%S') \
  --period 3600 \
  --statistics Average \
  --output table
```

You will get an empty `Datapoints` list, or at most a few minutes of data from since you just created the instance. This is the problem. Without history, Compute Optimizer returns `NOT_ENOUGH_DATA` and cannot make recommendations.

**Command Breakdown — `aws cloudwatch get-metric-statistics`:**

| Part | What It Does |
|------|-------------|
| `--namespace AWS/EC2` | EC2 metrics live in this namespace. CloudWatch uses namespaces to separate metrics from different services |
| `--metric-name CPUUtilization` | The specific metric — CPU as a percentage of available capacity |
| `--dimensions Name=InstanceId,Value=$INSTANCE_ID` | Scopes the query to one specific instance |
| `--start-time / --end-time` | The time window. `$(date -u -d '14 days ago' ...)` generates an ISO8601 timestamp dynamically |
| `--period 3600` | Groups data into 1-hour buckets (3600 seconds). Use 86400 for daily buckets |
| `--statistics Average` | Returns the mean value within each bucket |

---

## Step 5 — Seed 14 Days of Simulated Metrics

Run the seeding script:

```bash
chmod +x scripts/seed-metrics.sh
./scripts/seed-metrics.sh
```

Watch the output. The script will:

1. Read your actual instance IDs from Terraform outputs (so it always uses the right IDs, even after a destroy/re-apply)
2. Verify those instances exist in AWS
3. Push 336 hourly data points per instance (14 days × 24 hours), backdated using real CloudWatch timestamps
4. Opt your account in to Compute Optimizer
5. Run a verification check to confirm CloudWatch received the data

**Why backdated timestamps work:**

CloudWatch's `put-metric-data` API accepts timestamps up to 14 days in the past. When you post a data point with a timestamp of two weeks ago, CloudWatch stores it in the correct position in the time series. Compute Optimizer then reads that history as if the data had been collected over the past fortnight. This is a documented and legitimate use of the API — AWS Training environments use the same technique.

**What the CPU profiles represent:**

| Instance | Profile | What It Simulates |
|----------|---------|-------------------|
| `prod-web-1`, `prod-web-2` | 5–12% CPU with business-hours variation | A web server for a small company — the machine is there, it handles traffic, but it is a fraction of what `m5.2xlarge` can do |
| `dev-web` | 2–7% CPU, drops to ~1% overnight | A dev server that developers occasionally use during working hours |
| `dev-worker-1`, `dev-worker-2` | 3–8% CPU | Background workers running lightweight tasks |

All profiles stay well below the 40% ceiling AWS defines as the threshold for right-sizing candidates.

Once the script finishes, verify the data landed:

```bash
aws cloudwatch get-metric-statistics \
  --region eu-west-2 \
  --namespace AWS/EC2 \
  --metric-name CPUUtilization \
  --dimensions Name=InstanceId,Value=$INSTANCE_ID \
  --start-time $(date -u -d '14 days ago' '+%Y-%m-%dT%H:%M:%S') \
  --end-time $(date -u '+%Y-%m-%dT%H:%M:%S') \
  --period 3600 \
  --statistics Average Maximum \
  --output table
```

You should now see approximately 336 rows. The Average column will show values between 3% and 12%. The Maximum will not exceed about 15%.

This is what over-provisioning looks like in CloudWatch. A machine capable of sustained 8-core workloads, ticking along at 5–8% all day. The evidence is visible, quantifiable, and time-stamped.

---

## Step 6 — Wait for Compute Optimizer

This is the genuine wait. Compute Optimizer processes CloudWatch data in batches and typically generates initial recommendations within a few hours — sometimes up to 12.

Check progress at any time:

```bash
./scripts/check-recommendations.sh
```

If recommendations are not ready yet, the script will tell you clearly and suggest when to check again.

**What is happening inside Compute Optimizer while you wait:**

Compute Optimizer's machine learning model is:
- Reading the CloudWatch metric time series for each instance
- Calculating peak, average, and percentile utilisation across the full 14-day window
- Comparing actual utilisation against the capacity of the current instance type
- Looking at multiple dimensions: CPU, network I/O, disk I/O (and memory if the CloudWatch agent is installed)
- Generating up to three ranked alternative instance types for each over-provisioned instance
- Calculating a performance risk score for each recommendation — the probability that the smaller instance would be unable to meet the workload's peak demands

**While you wait — check enrolment status:**

```bash
aws compute-optimizer get-enrollment-status \
  --region eu-west-2
```

**Command Breakdown — `aws compute-optimizer get-enrollment-status`:**

| Part | What It Does |
|------|-------------|
| `aws compute-optimizer` | The Compute Optimizer CLI sub-command group |
| `get-enrollment-status` | Returns whether the current account has opted in to Compute Optimizer |

Expected output:

```json
{
    "status": "Active",
    "statusReason": "",
    "memberAccountsEnrolled": false
}
```

`Active` means Compute Optimizer is running and analysing your account. `statusReason` will be empty unless there is a problem.

---

## Step 7 — Read and Interpret the Recommendations

When `check-recommendations.sh` shows results, you will see a table similar to:

```
Instance ID          Finding            Current Type   Recommended  Est. Saving/mo
--------------------------------------------------------------------------------
i-0abc123def456789   OVER_PROVISIONED   m5.2xlarge     t3.medium    $87.40
i-0def456ghi789012   OVER_PROVISIONED   m5.2xlarge     t3.medium    $87.40
i-0ghi789jkl012345   OVER_PROVISIONED   m5.xlarge      t3.small     $43.20
i-0jkl012mno345678   OVER_PROVISIONED   m5.xlarge      t3.small     $43.20
i-0mno345pqr678901   OVER_PROVISIONED   m5.xlarge      t3.small     $43.20
```

Work through each column and ask yourself what it means:

**Finding: OVER_PROVISIONED**

Compute Optimizer has determined that the current instance type provides significantly more capacity than this workload has needed over the past 14 days. Based on observed utilisation, the workload could run on a smaller instance without compromising performance.

Does this match what you seeded? Yes — you deliberately seeded utilisation well below 40%. Compute Optimizer is confirming what the CloudWatch data shows.

**Current Type → Recommended Type**

`m5.2xlarge` → `t3.medium`: An 8-core fixed-performance machine → a 2-core burstable machine. The `t3` family accumulates CPU credits during low-utilisation periods and uses them when traffic spikes. For a web server that sits idle most of the day with occasional bursts, this is the correct model.

`m5.xlarge` → `t3.small`: Same logic at a smaller scale.

**Estimated Saving**

These are Compute Optimizer's estimates based on On-Demand pricing. The actual saving depends on whether you use Reserved Instances or Savings Plans. Use this number as a directional guide rather than a precise forecast.

**Get the full detail for one instance:**

```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
INSTANCE_ID=$(terraform output -raw dev_web_instance_id)

aws compute-optimizer get-ec2-instance-recommendations \
  --instance-arns "arn:aws:ec2:eu-west-2:${ACCOUNT_ID}:instance/${INSTANCE_ID}" \
  --region eu-west-2
```

In the JSON output, look for:

- `utilizationMetrics` — the actual CPU/network/disk values Compute Optimizer used to build the recommendation
- `recommendationOptions` — up to three alternatives, ranked by projected performance
- `recommendationOptions[].performanceRisk` — a score from 0 to 5. Lower is safer. A score of 0 means high confidence the smaller instance can handle this workload
- `recommendationOptions[].projectedUtilizationMetrics` — what CPU utilisation would look like on the recommended instance type

**Command Breakdown — `aws compute-optimizer get-ec2-instance-recommendations`:**

| Part | What It Does |
|------|-------------|
| `get-ec2-instance-recommendations` | Returns Compute Optimizer's analysis and recommendations for the specified instances |
| `--instance-arns` | The Amazon Resource Name(s) of the instances to query. Must be the full ARN in `arn:aws:ec2:region:account-id:instance/i-xxx` format |
| `--region` | The region where the instances are deployed |

---

## Step 8 — Apply One Recommendation

In production you would apply changes via Terraform (update `instance_type` in `main.tf` and run `terraform apply`). Here we apply one change manually via the CLI to demonstrate the hands-on workflow. This mirrors what you would do in an emergency or when Terraform is not available.

We will right-size the `dev-web` instance — a safe choice because it is a dev environment, lower risk than production.

Get the instance ID:

```bash
DEV_WEB_ID=$(terraform output -raw dev_web_instance_id)
echo "Target instance: $DEV_WEB_ID"
```

Confirm its current type:

```bash
aws ec2 describe-instances \
  --region eu-west-2 \
  --instance-ids "$DEV_WEB_ID" \
  --query "Reservations[0].Instances[0].InstanceType" \
  --output text
```

Expected: `m5.xlarge`. If you see something else, double-check the output.

Stop the instance:

```bash
aws ec2 stop-instances \
  --instance-ids "$DEV_WEB_ID" \
  --region eu-west-2
```

Wait for it to fully stop before changing the type:

```bash
aws ec2 wait instance-stopped \
  --instance-ids "$DEV_WEB_ID" \
  --region eu-west-2
echo "Instance stopped."
```

**Why wait?** AWS will reject the type change if the instance has not finished stopping. The `wait` command polls the API every 15 seconds until the `stopped` state is confirmed, then exits. This prevents race conditions.

Change the instance type:

```bash
aws ec2 modify-instance-attribute \
  --instance-id "$DEV_WEB_ID" \
  --instance-type '{"Value": "t3.small"}' \
  --region eu-west-2
```

**Command Breakdown — `aws ec2 modify-instance-attribute`:**

| Part | What It Does |
|------|-------------|
| `modify-instance-attribute` | Changes a single attribute of an EC2 instance that is in the `stopped` state |
| `--instance-id` | Which instance to modify |
| `--instance-type '{"Value": "t3.small"}'` | The target instance type, expressed as JSON. The `Value` key is required by the API |
| Why JSON? | `modify-instance-attribute` expects a structured argument because instance type is a complex attribute with a value and optional other properties |

Restart the instance:

```bash
aws ec2 start-instances \
  --instance-ids "$DEV_WEB_ID" \
  --region eu-west-2

aws ec2 wait instance-running \
  --instance-ids "$DEV_WEB_ID" \
  --region eu-west-2
echo "Instance running."
```

Verify the change:

```bash
aws ec2 describe-instances \
  --region eu-west-2 \
  --instance-ids "$DEV_WEB_ID" \
  --query "Reservations[0].Instances[0].{Type:InstanceType,State:State.Name}" \
  --output table
```

Expected output:

```
--------------------------
|   DescribeInstances    |
+----------+-------------+
|  State   |    Type     |
+----------+-------------+
|  running |  t3.small   |
+----------+-------------+
```

The instance is now right-sized. Compute Optimizer will eventually reclassify it as `OPTIMIZED` once it sees the new type running with the same utilisation pattern.

---

## Step 9 — Run the Validator

```bash
./validate.sh
```

The validator checks:
1. All 5 instances are present in AWS
2. CloudWatch has 14+ days of metric data for each instance
3. Compute Optimizer is enrolled
4. At least one instance has been changed to a `t3` family type

If Check 5 still shows a warning (Compute Optimizer not yet generated recommendations), that is expected. The validator accounts for this and will not fail the lab because of the wait.

---

## Step 10 — Destroy the Infrastructure

This is not optional. These are real instances billing real money.

```bash
terraform destroy
```

Type `yes` when prompted.

Verify everything is gone:

```bash
aws ec2 describe-instances \
  --region eu-west-2 \
  --filters \
    "Name=tag:Lab,Values=092" \
    "Name=instance-state-name,Values=running,stopped,pending" \
  --query "Reservations[].Instances[].{ID:InstanceId,State:State.Name}" \
  --output table
```

The table should be empty.

**Command Breakdown — `terraform destroy`:**

| Part | What It Does |
|------|-------------|
| `terraform` | The Terraform CLI |
| `destroy` | Reads the Terraform state file to determine what was created by this configuration, then deletes all of it from AWS in dependency order |
| Why use Terraform rather than deleting manually? | Terraform knows the correct destruction order. If you deleted resources manually in the wrong order — e.g. deleting a VPC before its instances — AWS would refuse. Terraform handles this automatically |

---

## Lab vs Real Life

| Lab Shortcut | Real-Life Practice |
|--------------|--------------------|
| Seeded simulated CPU data | Wait 14+ days for real CloudWatch data before making any right-sizing decision |
| Applied one change manually via CLI | Use Terraform to make changes — update `instance_type` in `main.tf` and run `terraform apply` so the change is tracked in version control |
| Changed a dev instance immediately | In production, apply changes during a scheduled maintenance window with a change request raised beforehand |
| Relied on CPU metrics only | Install the CloudWatch agent on each instance to also collect memory, disk, and network metrics — Compute Optimizer produces better recommendations when all dimensions are available |
| Validated by looking at instance type | After right-sizing in production, monitor CloudWatch for at least two weeks — look for CPU credit exhaustion (for `t3` instances), increased latency, or error rates that might indicate the new size is too small |
| Destroyed after lab | In production, right-sizing does not mean destroy — it means stop, resize, restart. No data is lost |

---

## Key Interview Talking Points

If a hiring manager asks how you approach right-sizing:

> "The process I follow is: first make sure observability is in place — at minimum CloudWatch for CPU, and the CloudWatch agent for memory. Then wait for enough data to accumulate — AWS recommends at least two weeks. I then use Compute Optimizer to get data-driven recommendations rather than guessing. Before applying anything I look at the performance risk score alongside the recommended type — that tells me how confident the model is that the smaller instance can handle peak load. I apply changes in stages — one instance, monitor for a week, then roll out. And I always make the change through Terraform so it is tracked in version control, not manually via the console."

That answer demonstrates tooling knowledge, process rigour, risk awareness, and infrastructure-as-code discipline — the four things a cloud engineering interviewer is listening for.

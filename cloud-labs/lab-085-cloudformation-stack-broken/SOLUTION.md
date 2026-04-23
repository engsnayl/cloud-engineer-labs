# Solution Walkthrough — CloudFormation Stack Failed

## TLDR (Plain English)

A colleague wrote a CloudFormation template for a tiny web app (VPC, subnet, security group, EC2 instance running Apache). When they tried to deploy it, the stack failed to create. There are **three real bugs** in the template, and each one teaches you a different class of CloudFormation failure:

1. **A syntax bug** that `validate-template` catches before AWS even tries to deploy — wrong intrinsic function (`!Ref` where `!Sub` was needed for string interpolation).
2. **A missing required property** that only the downstream AWS service (EC2) knows about — the `WebInstance` resource has no `ImageId`, so EC2 rejects it at creation time.
3. **A bad attribute name in the Outputs section** — `!GetAtt WebInstance.IpAddress` doesn't exist; the correct name is `PublicIp`. This one is particularly nasty because CloudFormation creates **all** your resources successfully first, **then** resolves Outputs, **then** rolls everything back when the Outputs section fails.

The fix is editing `template.yaml` to correct these three issues, adding an SSM parameter to dynamically look up the latest Amazon Linux 2023 AMI, and redeploying. Along the way you'll learn how CloudFormation's validation-vs-deployment-vs-outputs lifecycle actually behaves, and how it differs from Terraform.

---

## The Ticket

```
INCIDENT-CFN-001
CloudFormation stack "lab-085" stuck in CREATE_FAILED.
Team needs this environment for testing by end of day.
Template has errors that need fixing.
```

You've been assigned. You've used Terraform before, but this is your first CloudFormation template. You have no information about what's wrong — just the filename `template.yaml` and an expectation that it should deploy.

---

## Step-by-Step Investigation

### Step 1 — Get the lay of the land

First thing any engineer does on a new ticket: look at what's actually in the directory.

```bash
ls -la
```

| Component | What it does |
|---|---|
| `ls` | List directory contents |
| `-l` | Long format (permissions, owner, size, timestamp) |
| `-a` | Show hidden files too (anything starting with `.`) |

You'll see `template.yaml`, `CHALLENGE.md`, `HINTS.md`, `SOLUTION.md`, `validate.sh`. In a real ticket you'd have only the template — the rest are lab scaffolding. Your job is the template.

Now read the template to understand the *intent* before you try to debug it:

```bash
cat template.yaml
```

Skim — don't deep-dive yet. Get the shape of what's being built: a VPC, an Internet Gateway, a public subnet, a route table, a security group, an EC2 instance with Apache UserData, and some Outputs exposing the instance ID, public IP, and VPC ID. Standard single-instance web server deployment.

### Step 2 — Validate the template before you try to deploy it

Coming from Terraform, your instinct is probably `terraform plan`. CloudFormation's closest equivalent at this stage is:

```bash
aws cloudformation validate-template --template-body file://template.yaml --region eu-west-2
```

| Component | What it does |
|---|---|
| `aws cloudformation validate-template` | Sends the template to AWS's template parser. Checks YAML/JSON syntax, overall schema structure, and intrinsic function *shape* (e.g. `!Ref` must take a single string, `!GetAtt` must take a `Resource.Attribute` pair) |
| `--template-body file://template.yaml` | Path to the template. `file://` prefix is mandatory — AWS CLI uses it to distinguish a file path from an inline JSON string |
| `--region eu-west-2` | London. Templates are uploaded to a regional endpoint, even though validation itself is region-independent |

**Expected output — first error:**

```
An error occurred (ValidationError) when calling the ValidateTemplate operation: 
Template format error: Unresolved resource dependencies [${EnvironmentName}-vpc] 
in the Resources block of the template
```

### Step 3 — Decode the error

Three things to unpack:

1. **"ValidationError"** — this is a structural complaint from AWS's template parser. You haven't touched any real infrastructure yet.
2. **"Unresolved resource dependencies"** — CloudFormation is saying "you referenced a resource but I can't find it in your template."
3. **"[${EnvironmentName}-vpc]"** — this is the string CloudFormation is trying to look up as a resource name. It's treating `${EnvironmentName}-vpc` as a literal name, not doing any substitution.

**The "aha" moment:** CloudFormation is looking for a resource literally called `${EnvironmentName}-vpc`. Why? Because `!Ref` doesn't do string interpolation — it takes a single identifier and returns its value. When you write `!Ref "${EnvironmentName}-vpc"`, CloudFormation reads it as "find a resource named `${EnvironmentName}-vpc`" — which doesn't exist.

**Where to look:** find every `!Ref` in the template and see which one wraps a string with `${...}` placeholders inside.

```bash
grep -n '!Ref' template.yaml
```

| Component | What it does |
|---|---|
| `grep` | Search for a pattern in a file |
| `-n` | Show line numbers in results |
| `'!Ref'` | The pattern to find — single-quoted so bash doesn't interpret `!` |

The offender is the one in the VPC resource's `Tags:` block:

```yaml
- Key: Name
  Value: !Ref "${EnvironmentName}-vpc"     # ← WRONG
```

### Step 4 — Fix bug 1 (the syntax error)

You need the intrinsic function that *does* perform string substitution: `!Sub`.

Open the template:

```bash
vi template.yaml
```

| Keystroke | What it does |
|---|---|
| `/` then `!Ref "${` then Enter | Search for the bug pattern |
| `r` | Replace the single character under cursor |
| `i` | Enter insert mode (to make broader edits) |
| `Esc` | Exit insert mode |
| `:wq` Enter | Write and quit |

Change:

```yaml
Value: !Ref "${EnvironmentName}-vpc"
```

to:

```yaml
Value: !Sub "${EnvironmentName}-vpc"
```

**`!Ref` vs `!Sub` — the definitive breakdown:**

| Function | Takes | Returns | Example |
|---|---|---|---|
| `!Ref` | A single logical name, no quotes needed | The "default" value of that thing — resource ID for resources, parameter value for parameters | `!Ref VPC` → `vpc-0abc123...` |
| `!Sub` | A string with `${...}` placeholders | The string with placeholders substituted | `!Sub "${EnvironmentName}-vpc"` → `"lab-vpc"` |

**Terraform comparison:** `!Ref VPC` is like `aws_vpc.main.id`. `!Sub "${EnvironmentName}-vpc"` is like `"${var.environment_name}-vpc"`. Using `!Ref` for string interpolation is like trying to write `aws_vpc.main.id("${var.env}-vpc")` — nonsensical.

**Re-validate:**

```bash
aws cloudformation validate-template --template-body file://template.yaml --region eu-west-2
```

This time you'll get a JSON blob listing the template's parameters and description. Green light — the template is *structurally* valid.

### Step 5 — Understand why validation isn't enough

Here's a crucial CloudFormation lesson, and it's different from Terraform:

**`validate-template` is weak.** It checks:
- YAML/JSON parses
- Top-level schema (has `Resources:`, recognised root keys)
- Intrinsic function syntactic shape

It **does NOT** check:
- Whether resource properties are valid
- Whether `!GetAtt` attribute names exist
- Whether required properties are present
- Whether the deployment will actually work

**The only way to know for sure is to deploy.** `cfn-lint` (a third-party tool, `pip install cfn-lint`) catches more issues, but even it isn't exhaustive. In Terraform, `terraform plan` catches many of these because it pre-computes API calls. CloudFormation's equivalent is change sets, which still don't validate property-level correctness. So — we deploy and watch what happens.

### Step 6 — Try to create the stack

```bash
aws cloudformation create-stack --stack-name lab-085 --template-body file://template.yaml --region eu-west-2
```

| Component | What it does |
|---|---|
| `create-stack` | Provisions a new stack (a "stack" = a collection of AWS resources managed as one unit) |
| `--stack-name lab-085` | Name — must be unique within the region |
| `--template-body file://template.yaml` | Template path (again, `file://` prefix required) |
| `--region eu-west-2` | London |

**Response — immediate:**

```json
{
    "StackId": "arn:aws:cloudformation:eu-west-2:...:stack/lab-085/...",
    "OperationId": "..."
}
```

**Important behaviour you must internalise:** this command returns **immediately** with a `StackId`. The actual resource creation is happening asynchronously on AWS's side. This is the *opposite* of `terraform apply`, which blocks your terminal and streams progress. CloudFormation says "got it, I'm working on it" and you have to go *ask* what happened.

### Step 7 — Watch the events

You need to check what CloudFormation is doing. Three options, increasing in detail:

**Option 1 — Just the current status:**

```bash
aws cloudformation describe-stacks --stack-name lab-085 --region eu-west-2 --query 'Stacks[0].StackStatus' --output text
```

**Option 2 — The full event log (what you actually want):**

```bash
AWS_PAGER="" aws cloudformation describe-stack-events \
  --stack-name lab-085 \
  --region eu-west-2 \
  --query 'StackEvents[*].[Timestamp,LogicalResourceId,ResourceStatus,ResourceStatusReason]' \
  --output table
```

| Component | What it does |
|---|---|
| `AWS_PAGER=""` | Sets the pager to nothing for this one command. Without it, AWS CLI pipes table output through `less` and you get stuck at `(END)` |
| `describe-stack-events` | Returns the full event history — every resource creation attempt, success, failure, rollback |
| `--query 'StackEvents[*].[...]'` | JMESPath query to flatten nested JSON into just the columns we care about |
| `Timestamp,LogicalResourceId,ResourceStatus,ResourceStatusReason` | The four useful fields — time, which resource, status, and *why* (failure reasons land in ResourceStatusReason) |
| `--output table` | ASCII table rendering — far more readable than JSON |

**Option 3 — Block until done (for CI/CD):**

```bash
aws cloudformation wait stack-create-complete --stack-name lab-085 --region eu-west-2
```

This polls every ~30 seconds until the stack finishes creating or fails. Exits non-zero on failure. Don't use this for interactive debugging — it hides the events.

### Step 8 — Read the event log

Events are returned newest-first. Read them bottom-up to follow the story:

```
06:38:38  lab-085        CREATE_IN_PROGRESS         ← you ran create-stack
06:38:40  VPC            CREATE_IN_PROGRESS
06:38:41  InternetGateway CREATE_IN_PROGRESS        ← VPC + IGW in parallel
06:38:53  VPC            CREATE_COMPLETE
06:38:54  PublicSubnet, RouteTable, WebSecurityGroup all start
06:39:03  WebSecurityGroup CREATE_COMPLETE
06:39:03  WebInstance    CREATE_IN_PROGRESS
06:39:04  WebInstance    CREATE_FAILED              ← "Property ImageId cannot be empty."
06:39:04  RouteTable     CREATE_FAILED              ← "Resource creation cancelled"
06:39:05  lab-085        ROLLBACK_IN_PROGRESS       ← automatic cleanup
06:39:06+ everything DELETE_IN_PROGRESS → DELETE_COMPLETE
```

**Four lessons from this one output:**

1. **CloudFormation builds in parallel where it can.** It figures out the dependency graph from your `!Ref` and `!GetAtt` references and runs independent resources simultaneously. This is the same idea as Terraform's graph, but CloudFormation doesn't show it to you.
2. **The real error came from EC2, not CloudFormation.** The message says `Resource handler returned message: "Property ImageId cannot be empty."`. That `Resource handler` wording is CloudFormation's way of telling you a *downstream service* rejected the call. CloudFormation dutifully sent your instance spec to the EC2 API, and EC2 said no.
3. **Automatic rollback is a CloudFormation feature.** Compare to Terraform, where a failed apply leaves orphaned resources in state and you have to run `destroy` manually. CloudFormation tore down the 5 resources that did get created, without you asking.
4. **The "resource creation cancelled" message on RouteTable** isn't a separate bug — CloudFormation cancelled resources that were still in-flight when another resource's failure triggered the rollback.

### Step 9 — Fix bug 4 (the missing ImageId)

The failure message is unambiguous: `"Property ImageId cannot be empty."` Every EC2 instance needs an AMI ID.

**The question a real engineer asks:** "What AMI should I hardcode?"

**The correct answer a real engineer gives:** "I shouldn't hardcode one."

Hardcoding AMI IDs is bad practice:
- AMI IDs are **region-specific** (`ami-0123...` in London is a different image than `ami-0123...` in Dublin)
- AMIs get **deprecated** as AWS releases updates
- A hardcoded AMI is a time bomb — it works today, breaks in 18 months

**The industry-standard pattern:** use an SSM parameter that AWS maintains. AWS publishes parameters that always point to the latest AMI for each OS. For Amazon Linux 2023 on x86_64:

```
/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64
```

CloudFormation has a magic parameter type — `AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>` — that resolves SSM parameters at deploy time.

**Two edits needed in `template.yaml`:**

**Edit 1 — add a new parameter** in the `Parameters:` block:

```yaml
Parameters:
  EnvironmentName:
    Type: String
    Default: lab
    Description: Environment name prefix
  LatestAmiId:
    Type: AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>
    Default: /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64
    Description: SSM parameter for the latest Amazon Linux 2023 AMI
  InstanceType:
    Type: String
    Default: t3.micro
    ...
```

**Edit 2 — reference it** in the `WebInstance` resource. Add `ImageId: !Ref LatestAmiId` as the first property:

```yaml
WebInstance:
  Type: AWS::EC2::Instance
  Properties:
    ImageId: !Ref LatestAmiId              # ← add this
    InstanceType: !Ref InstanceType
    SubnetId: !Ref PublicSubnet
    ...
```

**Terraform comparison:** the SSM-parameter pattern is equivalent to Terraform's `data "aws_ssm_parameter" "amazon_linux"` block. Both resolve an AMI at apply time.

### Step 10 — The "can't update a ROLLBACK_COMPLETE stack" gotcha

Before you redeploy, check the stack status:

```bash
aws cloudformation describe-stacks --stack-name lab-085 --region eu-west-2 --query 'Stacks[0].StackStatus' --output text
```

Expect: `ROLLBACK_COMPLETE`.

**CloudFormation refuses to update or re-create a stack that's in `ROLLBACK_COMPLETE`.** You must delete it first and start fresh. This is genuinely different from Terraform, where you just fix the config and run `apply` again.

```bash
aws cloudformation delete-stack --stack-name lab-085 --region eu-west-2
aws cloudformation wait stack-delete-complete --stack-name lab-085 --region eu-west-2
```

| Component | What it does |
|---|---|
| `delete-stack` | Initiates asynchronous teardown. Returns immediately. CloudFormation works out reverse dependency order automatically |
| `wait stack-delete-complete` | Polls the API until the stack is gone. Blocks your terminal for 30–90 seconds. Exits non-zero if deletion fails |

After `wait` returns, verify:

```bash
aws cloudformation describe-stacks --stack-name lab-085 --region eu-west-2 --query 'Stacks[0].StackStatus' --output text
```

Expect: `An error occurred... Stack with id lab-085 does not exist` — which is what we *want* to see.

### Step 11 — Redeploy

```bash
aws cloudformation validate-template --template-body file://template.yaml --region eu-west-2
aws cloudformation create-stack --stack-name lab-085 --template-body file://template.yaml --region eu-west-2
```

Wait ~60 seconds, then check status:

```bash
aws cloudformation describe-stacks --stack-name lab-085 --region eu-west-2 --query 'Stacks[0].StackStatus' --output text
```

Expected: `ROLLBACK_IN_PROGRESS` or `ROLLBACK_COMPLETE`. Check events:

```bash
AWS_PAGER="" aws cloudformation describe-stack-events \
  --stack-name lab-085 \
  --region eu-west-2 \
  --query 'StackEvents[*].[Timestamp,LogicalResourceId,ResourceStatus,ResourceStatusReason]' \
  --output table | head -30
```

**The expected failure — this one is sneaky:**

```
06:53:07  lab-085     ROLLBACK_IN_PROGRESS  
          Requested attribute IpAddress does not exist in schema for AWS::EC2::Instance. 
          Rollback requested by user.
06:53:06  WebInstance CREATE_COMPLETE
06:53:06  lab-085     CREATE_IN_PROGRESS  Eventual consistency check initiated
```

**Read the sequence carefully:**
1. `WebInstance CREATE_COMPLETE` — the instance was actually created!
2. `lab-085 CREATE_IN_PROGRESS / Eventual consistency check initiated` — CloudFormation waiting for everything to settle
3. `lab-085 ROLLBACK_IN_PROGRESS / Requested attribute IpAddress does not exist in schema...` — then it resolved the Outputs section and **failed there**.

**This is bug 5, and it's the nastiest of the three** because:

1. All your infrastructure creates successfully.
2. Then CloudFormation resolves the Outputs section.
3. Then the Outputs fail — `IpAddress` isn't a valid attribute for `AWS::EC2::Instance`.
4. Then CloudFormation rolls back **everything**, tearing down infrastructure that worked perfectly.

**In Terraform**, a bad `output` block fails at plan time. In CloudFormation, you burn ~60 seconds of resource creation before the failure surfaces.

### Step 12 — Fix bug 5 (the wrong GetAtt attribute)

```bash
aws cloudformation delete-stack --stack-name lab-085 --region eu-west-2
aws cloudformation wait stack-delete-complete --stack-name lab-085 --region eu-west-2
```

Open the template:

```bash
vi template.yaml
```

Find in the `Outputs:` section:

```yaml
PublicIP:
  Description: Public IP address
  Value: !GetAtt WebInstance.IpAddress     # ← WRONG
```

Change `IpAddress` to `PublicIp`:

```yaml
PublicIP:
  Description: Public IP address
  Value: !GetAtt WebInstance.PublicIp      # ← correct
```

**Where do you know `PublicIp` is the right name?** The [AWS::EC2::Instance documentation](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-properties-ec2-instance.html) lists every valid GetAtt attribute:

- `AvailabilityZone`
- `InstanceId` (same as `!Ref`)
- `PrivateDnsName`, `PrivateIp`
- **`PublicDnsName`, `PublicIp`**
- `VpcId`
- etc.

There's no `IpAddress`. Real engineers bookmark the CloudFormation Resource Type Reference.

**`!Ref` vs `!GetAtt` — the definitive breakdown:**

| Function | Takes | Returns |
|---|---|---|
| `!Ref` | A logical name (resource or parameter) | The "default" identifier — for most resources that's the ID (VPC ID, instance ID, etc.) |
| `!GetAtt` | `ResourceName.AttributeName` | A named, specific attribute (PublicIp, Arn, etc.) — different attributes per resource type |

**Terraform comparison:** `!Ref aws_instance.web` is like `aws_instance.web.id`. `!GetAtt aws_instance.web.PublicIp` is like `aws_instance.web.public_ip`. The naming conventions differ — CloudFormation uses PascalCase, Terraform uses snake_case.

### Step 13 — Deploy for real

```bash
aws cloudformation validate-template --template-body file://template.yaml --region eu-west-2
aws cloudformation create-stack --stack-name lab-085 --template-body file://template.yaml --region eu-west-2
```

Wait ~60 seconds:

```bash
aws cloudformation describe-stacks --stack-name lab-085 --region eu-west-2 --query 'Stacks[0].StackStatus' --output text
```

Expected: `CREATE_COMPLETE` 🎉

### Step 14 — Verify the stack actually works

CloudFormation saying `CREATE_COMPLETE` means *resources got created*. It doesn't mean the web server inside the instance is actually serving traffic. Prove it:

**Pull the outputs:**

```bash
aws cloudformation describe-stacks --stack-name lab-085 --region eu-west-2 --query 'Stacks[0].Outputs' --output table
```

**Curl the public IP:**

```bash
curl http://<public-ip-from-outputs>
```

Expected: `<h1>Hello from lab</h1>`

That's the UserData script having executed on instance boot — `yum install httpd`, `systemctl start httpd`, and the `echo` redirect into `index.html`. The `${EnvironmentName}` placeholder got substituted to `lab` because you used `!Sub` in the UserData block.

If curl hangs, wait 30 seconds and retry — yum installs can take a minute on first boot.

---

## Cleanup — ALWAYS DO THIS

Leaving an EC2 instance running costs about $7/month. Destroy everything:

```bash
aws cloudformation delete-stack --stack-name lab-085 --region eu-west-2
aws cloudformation wait stack-delete-complete --stack-name lab-085 --region eu-west-2
```

**Verify the stack is gone:**

```bash
aws cloudformation describe-stacks --stack-name lab-085 --region eu-west-2 --query 'Stacks[0].StackStatus' --output text
```

Expected: `Stack with id lab-085 does not exist`

**Verify no instance is lingering:**

```bash
aws ec2 describe-instances --region eu-west-2 --filters "Name=tag:Name,Values=lab-web-server" --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output table
```

Expected: empty or `terminated` only. Terminated instances hang around in the API for about an hour before disappearing — they don't cost anything.

**Reset the local template to broken state for re-runnability:**

```bash
git checkout -- template.yaml
```

| Component | What it does |
|---|---|
| `git checkout --` | Discard unstaged changes to the specified file, restoring it to the last committed state |
| `template.yaml` | The file to reset |

This puts the broken template back so the lab can be re-run from scratch.

---

## Key Concepts Learned

**CloudFormation lifecycle:**
- `validate-template` is weak — only catches YAML syntax and intrinsic function shape.
- `create-stack` is asynchronous — returns a StackId immediately, deployment happens on AWS's side.
- Resources are created in parallel where dependencies allow.
- Outputs are resolved *after* all resources create — bugs there can trigger full rollback.

**CloudFormation's recovery behaviour:**
- Automatic rollback on failure — genuinely nice.
- First-time create failures leave stack in `ROLLBACK_COMPLETE`, which you must delete before retrying.
- `delete-stack` + `wait stack-delete-complete` is the CI/CD-safe pattern for synchronous teardown.

**Intrinsic functions:**
- `!Ref` — default identifier for a resource or parameter. No interpolation.
- `!Sub` — string substitution with `${...}` placeholders.
- `!GetAtt` — named attributes (PublicIp, Arn, etc.). Different per resource type.
- Know which to use for each situation. The [Resource Type Reference](https://docs.aws.amazon.com/AWSCloudFormation/latest/UserGuide/aws-template-resource-type-ref.html) is your friend.

**AMI sourcing:**
- Never hardcode AMI IDs.
- Use SSM parameters with type `AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>`.
- AWS publishes latest-AMI SSM parameters for every OS and architecture.

---

## Lab vs Real Life

**In this lab:**
- You had three distinct bugs, each surfaced at a different lifecycle stage.
- You ran everything from a single developer machine with admin AWS credentials.
- The stack had seven small resources — easy to debug.

**In the real world:**
- **Templates are enormous** — production CloudFormation stacks often have 50+ resources. Event logs become hard to parse visually. Engineers pipe them through `grep CREATE_FAILED` or use the AWS Console's Events tab which highlights failures in red.
- **`cfn-lint` is mandatory pre-commit** — nobody runs `create-stack` blind. A pre-commit hook or CI step runs `cfn-lint template.yaml` and catches 80% of bugs before they reach AWS.
- **Change sets are the professional workflow.** Instead of `create-stack` / `update-stack` directly, you `create-change-set`, review the proposed changes, then `execute-change-set`. This is CloudFormation's closest equivalent to `terraform plan`.
- **Nested stacks and modules** — real templates use `AWS::CloudFormation::Stack` to compose sub-templates, or AWS CDK to generate them programmatically. Nobody writes a 1000-line YAML file by hand.
- **Outputs are export/import boundaries** — Outputs can be exported (`Export: Name: MyVPC-Id`) and imported in other stacks via `Fn::ImportValue`. This is how teams stitch together a VPC stack, an EKS stack, and an app stack.
- **Rollback triggers** — production stacks can define `RollbackConfiguration` with CloudWatch alarms, triggering rollback if post-deploy metrics look bad (error rate spike, latency regression).
- **Stack sets** — for multi-account/multi-region deployments, you use `cloudformation create-stack-set` which fans out to an AWS Organizations hierarchy.

**Mental model shift from Terraform:**
- **State management is AWS-side.** No backend config, no S3 bucket, no DynamoDB lock table. CloudFormation holds the state for you.
- **No `plan`-equivalent for property-level issues.** Change sets show resource-level diffs but don't validate property correctness.
- **Automatic rollback is native.** Terraform leaves partial applies for you to clean up; CloudFormation cleans itself up.
- **Multi-cloud is impossible.** CloudFormation is AWS-only. Terraform works across every provider.
- **Syntax is YAML/JSON** not HCL. More verbose, less expressive for conditionals and loops — which is why AWS CDK (Python/TypeScript generating CloudFormation) exists.

---

## Re-runnable Cleanup Section

To reset this lab and run it again from scratch:

```bash
# 1. If a stack still exists, delete it
aws cloudformation delete-stack --stack-name lab-085 --region eu-west-2 2>/dev/null
aws cloudformation wait stack-delete-complete --stack-name lab-085 --region eu-west-2 2>/dev/null

# 2. Reset the broken template
git checkout -- template.yaml

# 3. Confirm you're back to broken state
grep -c '!Ref "\${' template.yaml   # should return 1 (bug 1 present)
grep -c 'ImageId' template.yaml     # should return 0 (bug 4 present — no ImageId)
grep -c 'IpAddress' template.yaml   # should return 1 (bug 5 present)
```

| Component | What it does |
|---|---|
| `2>/dev/null` | Silence stderr — the delete commands error if the stack doesn't exist, and we want to continue quietly if that's the case |
| `grep -c` | Count matches instead of printing them — useful for scripted checks |
| `'!Ref "\${'` | Escaped pattern to match the bug 1 syntax literally |

---

## `terraform destroy` Equivalent — CRITICAL REMINDER

**Before you walk away from this lab, RUN THIS:**

```bash
aws cloudformation delete-stack --stack-name lab-085 --region eu-west-2
aws cloudformation wait stack-delete-complete --stack-name lab-085 --region eu-west-2
```

A t3.micro EC2 instance running 24/7 costs roughly £6–7/month. Small, but it adds up across multiple forgotten labs. The `wait` command blocks until deletion completes — don't skip it.

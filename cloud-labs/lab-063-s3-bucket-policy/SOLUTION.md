# Lab 063 — S3 Access Denied: Bucket Policy Debugging

---

## TLDR — What's Going On In Plain English

Imagine your S3 bucket is a locked filing cabinet. Your application has a key (IAM role), and there's also a sign on the cabinet listing who's allowed to open it (bucket policy).

In this lab, the cabinet has three problems:

1. **The sign on the cabinet says "NOBODY is allowed in — full stop."** That overrules everything, including your key. This is the explicit Deny bug.
2. **One of the permissions on the sign is listed for the wrong thing.** The permission to *look at a list of files in the cabinet* (ListBucket) is written against the files themselves rather than the cabinet. AWS rejects this outright at deploy time.
3. **Your key only works on the cabinet door itself — not on the files inside.** The IAM policy only lists the bucket ARN, but Get and Put operations work on objects (files) inside, which need a different ARN pattern.

**The fix:** Correct the ListBucket resource ARN so the policy deploys, remove the blanket Deny and scope it to the app role, then make sure the IAM policy covers both the bucket and everything inside it.

---

## The Three Bugs at a Glance

| # | Bug | Location | Effect |
|---|-----|----------|--------|
| 1 | Explicit `Deny` for `Principal: "*"` on GetObject and PutObject | Bucket policy — Statement 1 | Blocks ALL access to objects for everyone |
| 2 | `s3:ListBucket` pointed at `bucket/*` (object ARN) | Bucket policy — Statement 2 | AWS rejects the entire policy at deploy time with `MalformedPolicy` |
| 3 | IAM policy `Resource` only has the bucket ARN | IAM role policy | GetObject and PutObject denied — objects not covered |

---

## The Diagnostic Pathway — How a Cloud Engineer Actually Debugs This

This section walks you through *how to think about* the problem, not just what to fix. Following this process will serve you in real environments too.

---

### Phase 1 — Try to Deploy and Read the Error

**Step 1.1: Run terraform init and apply**

```bash
terraform init
terraform apply
```

In this lab, `terraform apply` fails immediately before any resources are created:

```
│ Error: putting S3 Bucket Policy: operation error S3: PutBucketPolicy,
│ StatusCode: 400, api error MalformedPolicy: Action does not apply to
│ any resource(s) in statement
```

| Part | What it tells you |
|------|-------------------|
| `StatusCode: 400` | AWS rejected the request outright — didn't even try to apply it |
| `MalformedPolicy` | The policy document itself is structurally invalid from AWS's perspective |
| `Action does not apply to any resource(s) in statement` | One of the Action/Resource combinations is illegal |

**Step 1.2: Read the error and locate the problem in main.tf**

The error says "Action does not apply to any resource(s) in statement." That's AWS telling you that somewhere in the bucket policy, an action has been paired with a resource ARN it can never apply to.

Open `main.tf` and look at the bucket policy statements. You have two statements — one for `s3:GetObject`/`s3:PutObject`, and one for `s3:ListBucket`. Look at the `Resource` field on each one:

```hcl
Action   = ["s3:ListBucket"]
Resource = "${aws_s3_bucket.app_data.arn}/*"
```

The `/*` at the end of the ARN is the clue. In S3, ARNs come in two forms:

| ARN format | What it points to |
|------------|------------------|
| `arn:aws:s3:::bucket-name` | The bucket itself |
| `arn:aws:s3:::bucket-name/*` | Objects inside the bucket |

`s3:ListBucket` is asking "what files are in this bucket?" — that's a question about the bucket itself, not about any individual file. So it needs the bucket ARN, not the object ARN. AWS sees `ListBucket` paired with `/*` and rejects it outright because those two things can never make sense together.

> **Note:** In `main.tf` you can read the policy directly rather than querying AWS. In a real production environment where you didn't write the infrastructure yourself, you'd pull the live policy with `aws s3api get-bucket-policy --bucket your-bucket-name --output text | python3 -m json.tool` to see what's actually deployed.

**Step 1.3: Fix Bug 2 — correct the ListBucket resource ARN**

In `main.tf`, change the `Resource` line for the `ListBucket` statement:

```hcl
# BEFORE
Resource = "${aws_s3_bucket.app_data.arn}/*"

# AFTER
Resource = aws_s3_bucket.app_data.arn
```

Just remove the `/*`. The bucket ARN without the suffix points to the bucket itself, which is exactly what `ListBucket` operates on.

**Step 1.4: Apply again**

```bash
terraform apply
```

This time the apply succeeds — AWS accepts the policy because the Action/Resource pairing is now valid. The bucket, IAM role, and policies are all created.

> **Real-world note:** This is actually helpful behaviour. In production, a `MalformedPolicy` error at deploy time means your CI/CD pipeline fails fast — you catch the misconfiguration before it ever reaches a running environment.

---

### Phase 2 — Test Access and Find the Remaining Bugs

**Step 2.1: Confirm who you're running as**

```bash
aws sts get-caller-identity
```

| Part | What it tells you |
|------|-------------------|
| `Account` | Which AWS account this is running in |
| `UserId` | The unique ID of the entity making requests |
| `Arn` | The full ARN — confirms which IAM identity is active |

You need to know *who* is being denied before you can work out *why*. If the wrong role is in use, fixing the policies won't help.

**Step 2.2: Test listing the bucket**

```bash
aws s3 ls s3://your-bucket-name
```

An empty response with no error means `ListBucket` is working — Bug 2 is confirmed fixed.

**Step 2.3: Test uploading a file**

```bash
echo "test" > test.txt
aws s3 cp test.txt s3://your-bucket-name/
```

You'll see:

```
upload failed: ./test.txt to s3://your-bucket-name/test.txt An error occurred
(AccessDenied) when calling the PutObject operation: User: arn:aws:iam::...
is not authorized to perform: s3:PutObject ... with an explicit deny in a
resource-based policy
```

The key phrase is **"with an explicit deny in a resource-based policy"**. AWS isn't saying you don't have permission — it's saying something is *actively blocking* you. That distinction is important. It points directly at Bug 1 — an explicit Deny in the bucket policy.

---

### Phase 3 — Fix Bug 1: The Explicit Deny

**Step 3.1: Understand why the Deny is so destructive**

Look at the first statement in the bucket policy:

```hcl
Effect    = "Deny"
Principal = "*"
Action    = ["s3:GetObject", "s3:PutObject"]
Resource  = "${aws_s3_bucket.app_data.arn}/*"
```

`Principal = "*"` means every single entity in existence — your IAM user, the app role, another AWS account, anyone. Combined with `Deny`, this says:

> "NOBODY is allowed to GetObject or PutObject. No exceptions. Ever."

In AWS, an **explicit Deny in any policy always overrides every Allow**. It doesn't matter what any other policy says. Adding more Allow statements will never fix this — you must change or remove the Deny itself.

**Step 3.2: Fix Bug 1 — change Deny to Allow and scope to the app role**

```hcl
# BEFORE
{
  Effect    = "Deny"
  Principal = "*"
  Action    = ["s3:GetObject", "s3:PutObject"]
  Resource  = "${aws_s3_bucket.app_data.arn}/*"
}

# AFTER
{
  Effect    = "Allow"
  Principal = {
    AWS = aws_iam_role.app_role.arn
  }
  Action    = ["s3:GetObject", "s3:PutObject"]
  Resource  = "${aws_s3_bucket.app_data.arn}/*"
}
```

Two things changed: `Effect` flipped from `Deny` to `Allow`, and `Principal` changed from `"*"` (everyone) to the specific app role ARN. This means only the application role can GetObject and PutObject — not the public internet.

**Step 3.3: Apply and test again**

```bash
terraform apply
aws s3 cp test.txt s3://your-bucket-name/
```

The upload now succeeds. Note that your IAM user (`StephenNaylor`) can also upload because the explicit Deny is gone — as an admin user with your own IAM permissions, same-account rules mean either the IAM policy or bucket policy can grant you access.

---

### Phase 4 — Fix Bug 3: The IAM Policy Resource Coverage

**Step 4.1: Understand the bug**

Even though the bucket policy now allows the app role to GetObject and PutObject, the IAM policy attached to the role has its own problem. Look at the Resource field:

```hcl
Resource = aws_s3_bucket.app_data.arn
```

That resolves to `arn:aws:s3:::app-data-xxxxx` — the bucket itself. But `s3:GetObject` and `s3:PutObject` operate on objects *inside* the bucket. They need the `/*` ARN. Without it, AWS checks the resource, finds it doesn't match object-level actions, and denies them.

This is the same ARN-level mismatch as Bug 2, but in the IAM policy instead of the bucket policy — and this time AWS doesn't reject it at deploy time, it just silently denies at runtime.

**Step 4.2: Fix Bug 3 — add both ARN patterns to the IAM policy**

```hcl
# BEFORE
Resource = aws_s3_bucket.app_data.arn

# AFTER
Resource = [
  aws_s3_bucket.app_data.arn,
  "${aws_s3_bucket.app_data.arn}/*"
]
```

The first entry covers `ListBucket` (bucket-level). The second entry covers `GetObject` and `PutObject` (object-level). All three actions are now satisfied.

**Step 4.3: Apply and verify**

```bash
terraform apply
aws s3 ls s3://your-bucket-name
aws s3 cp test.txt s3://your-bucket-name/
aws s3 cp s3://your-bucket-name/test.txt ./downloaded-test.txt
```

All three should succeed. The app role can now list, upload, and download.

---

### Phase 5 — Validate

```bash
terraform validate
terraform plan
```

`terraform validate` checks syntax — does NOT contact AWS. `terraform plan` shows no changes are needed, confirming your configuration matches what's deployed.

Run the lab validator:

```bash
cd ~/cloud-engineer-labs
lab validate cloud-labs/lab-063-s3-bucket-policy
```

Both checks should pass.

---

### Phase 6 — Clean Up

```bash
# Empty the bucket first — Terraform won't delete a non-empty bucket
aws s3 rm s3://your-bucket-name --recursive
terraform destroy -auto-approve
```

| Part | What it does |
|------|--------------|
| `aws s3 rm` | Removes objects from the bucket |
| `--recursive` | Deletes all objects, not just the top level |
| `terraform destroy` | Tears down all resources created by this configuration |
| `-auto-approve` | Skips the confirmation prompt |

---

## The Complete Fixed main.tf

```hcl
# S3 Bucket Policy Lab
provider "aws" {
  region = "eu-west-2"
}

resource "aws_s3_bucket" "app_data" {
  bucket = "app-data-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_policy" "app_data" {
  bucket = aws_s3_bucket.app_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          AWS = aws_iam_role.app_role.arn
        }
        Action    = ["s3:GetObject", "s3:PutObject"]
        Resource  = "${aws_s3_bucket.app_data.arn}/*"
      },
      {
        Effect    = "Allow"
        Principal = {
          AWS = aws_iam_role.app_role.arn
        }
        Action    = ["s3:ListBucket"]
        Resource  = aws_s3_bucket.app_data.arn
      }
    ]
  })
}

resource "aws_iam_role" "app_role" {
  name = "app-s3-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "app_s3" {
  name = "app-s3-policy"
  role = aws_iam_role.app_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.app_data.arn,
        "${aws_s3_bucket.app_data.arn}/*"
      ]
    }]
  })
}

resource "random_id" "suffix" {
  byte_length = 4
}
```

---

## How This Works in a Real AWS Environment

### Using the IAM Policy Simulator

In production, before deploying a policy change, use the Policy Simulator to test whether a specific action would be allowed or denied:

```bash
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::123456789:role/app-role \
  --action-names s3:GetObject \
  --resource-arns arn:aws:s3:::my-bucket/test.txt
```

| Part | What it does |
|------|--------------|
| `simulate-principal-policy` | Simulates the full IAM evaluation logic for a given identity |
| `--policy-source-arn` | The role or user you're testing as |
| `--action-names` | The S3 action you want to check |
| `--resource-arns` | The specific resource being accessed |

The output shows `allowed` or `implicitDeny` / `explicitDeny` — and if denied, which policy caused it. This saves you from trial and error in production.

### Using CloudTrail to Diagnose Denials

CloudTrail records every API call including denied ones. When access is denied, look for `errorCode: "AccessDenied"` and `errorMessage` — which sometimes identifies which policy caused the denial. Query this via CloudWatch Insights or the CloudTrail console.

### S3 Block Public Access

Production buckets should have S3 Block Public Access enabled at both bucket and account level. This is an additional layer that can block access if misconfigured — separate from bucket policies and IAM policies.

### VPC Endpoints

For production workloads, S3 access goes through a VPC endpoint rather than the public internet. VPC endpoint policies add yet another layer of access control.

### Cross-Account Access

When the IAM role and S3 bucket are in different AWS accounts, **both** the IAM policy and the bucket policy must explicitly allow the action. In same-account scenarios (this lab), either one is sufficient — but an explicit Deny in either always blocks regardless.

---

## Key Rules to Remember

**Rule 1 — Explicit Deny always wins**
An explicit Deny in any policy (bucket policy, IAM, SCP, VPC endpoint policy) overrides all Allows. Always look for Deny statements first when debugging access issues.

**Rule 2 — S3 has two resource ARN types**
Bucket actions (`s3:ListBucket`) need `arn:aws:s3:::bucket-name`. Object actions (`s3:GetObject`, `s3:PutObject`) need `arn:aws:s3:::bucket-name/*`. Using the wrong one either causes a `MalformedPolicy` error at deploy time or silently denies at runtime.

**Rule 3 — IAM policies often need both ARN patterns**
If a policy grants both bucket-level and object-level actions, include both ARNs in the `Resource` field.

**Rule 4 — Same-account vs cross-account evaluation differs**
Same-account: either IAM or bucket policy can grant access (unless there's a Deny). Cross-account: both must grant access.

**Rule 5 — `Principal: "*"` means everyone**
With Allow, it makes the bucket public. With Deny, it blocks everyone including your own roles.

**Rule 6 — Know your error signals**
- `MalformedPolicy` at apply time → Action/Resource mismatch in the policy document
- `AccessDenied` with "explicit deny in a resource-based policy" → there is an active Deny statement, not just a missing Allow
- `AccessDenied` without that phrase → missing Allow, not an active Deny

---

## Common Mistakes

- **Adding more Allows to fix an explicit Deny** — Allows don't override Denies. You must remove or change the Deny statement itself.
- **Using `/*` for ListBucket** — the most common S3 policy mistake. ListBucket is bucket-level; it needs the bare bucket ARN.
- **One Resource ARN in an IAM policy that grants multiple action types** — if you grant both ListBucket and GetObject but only list one ARN, half the actions will be denied.
- **Confusing bucket policies with IAM policies** — bucket policies are resource-based (attached to the bucket). IAM policies are identity-based (attached to roles/users). Both are evaluated, and both can grant or deny access.
- **Forgetting to empty the bucket before destroy** — Terraform won't delete a non-empty S3 bucket. Always `aws s3 rm --recursive` first.

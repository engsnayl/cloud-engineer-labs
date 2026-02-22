# Solution Walkthrough — S3 Access Denied (Bucket Policy Debugging)

## The Problem

An application can't read from or write to its S3 bucket. Both a bucket policy and an IAM role policy are configured, but access is still denied. There are **three bugs**:

1. **Bucket policy has an explicit Deny for everyone** — the first statement in the bucket policy denies `s3:GetObject` and `s3:PutObject` for `Principal: "*"` (everyone). In AWS, an explicit Deny **always** overrides any Allow. No matter what other policies say Allow, this Deny blocks all object access.
2. **ListBucket uses the wrong resource ARN** — the `s3:ListBucket` action operates on the bucket itself, not objects. The resource should be `arn:aws:s3:::bucket-name` (no `/*`), but the policy specifies `arn:aws:s3:::bucket-name/*` (the objects path). AWS silently denies the action because the resource doesn't match.
3. **IAM policy resource is too narrow** — the IAM role policy only specifies the bucket ARN (`arn:aws:s3:::bucket`), but `s3:GetObject` and `s3:PutObject` operate on objects (`arn:aws:s3:::bucket/*`). The policy needs both ARNs — the bucket for ListBucket and the objects path for Get/Put.

## Thought Process

When S3 access is denied, an experienced cloud engineer follows this diagnostic path:

1. **Check for explicit Denies** — an explicit Deny in ANY policy (bucket policy, IAM policy, SCP, VPC endpoint policy) overrides ALL Allows. Always check for Deny statements first.
2. **Check resource ARN patterns** — S3 has two resource types: the bucket (`arn:aws:s3:::bucket`) and objects (`arn:aws:s3:::bucket/*`). Using the wrong one for an action silently fails.
3. **Check IAM policy + Bucket policy interaction** — for same-account access, the request is allowed if EITHER the IAM policy or bucket policy allows it (unless there's an explicit Deny). For cross-account access, BOTH must allow.
4. **Use CloudTrail** — CloudTrail logs show the exact error reason for each denied request, including which policy caused the denial.

## Step-by-Step Solution

### Step 1: Review the current bucket policy

Look at the first statement in the bucket policy:

```hcl
{
  Effect    = "Deny"
  Principal = "*"
  Action    = ["s3:GetObject", "s3:PutObject"]
  Resource  = "${aws_s3_bucket.app_data.arn}/*"
}
```

**The problem:** `Effect = "Deny"` with `Principal = "*"` means NOBODY can GetObject or PutObject — not even the application role. In AWS IAM evaluation, an explicit Deny always wins, regardless of any Allow statements elsewhere.

### Step 2: Fix Bug 1 — Change the first statement to Allow

Change the first bucket policy statement from Deny to Allow, and scope it to the application role:

```hcl
{
  Effect    = "Allow"
  Principal = {
    AWS = aws_iam_role.app_role.arn
  }
  Action    = ["s3:GetObject", "s3:PutObject"]
  Resource  = "${aws_s3_bucket.app_data.arn}/*"
}
```

**Why this matters:** The Deny was blocking everyone, including the application. By changing to Allow with a specific Principal, only the application role can access objects. This follows the principle of least privilege — grant access only to the identity that needs it.

### Step 3: Fix Bug 2 — ListBucket needs the bucket ARN

The second statement has the wrong resource:

```hcl
# BROKEN: ListBucket needs bucket ARN, not object ARN
Action   = ["s3:ListBucket"]
Resource = "${aws_s3_bucket.app_data.arn}/*"    # Wrong!
```

Fix it:

```hcl
Action   = ["s3:ListBucket"]
Resource = aws_s3_bucket.app_data.arn           # Correct — no /*
```

**Why this matters:** S3 actions operate on different resource types:
- **Bucket-level actions** (`s3:ListBucket`, `s3:GetBucketLocation`): resource is `arn:aws:s3:::bucket-name`
- **Object-level actions** (`s3:GetObject`, `s3:PutObject`, `s3:DeleteObject`): resource is `arn:aws:s3:::bucket-name/*`

Using `arn:aws:s3:::bucket/*` for ListBucket silently fails because AWS can't match the object-level ARN pattern to a bucket-level action.

### Step 4: Fix Bug 3 — IAM policy needs both bucket and object ARNs

The IAM role policy only specifies the bucket ARN:

```hcl
# BROKEN: Only bucket ARN — Get/Put need object ARN too
Resource = aws_s3_bucket.app_data.arn
```

Fix it:

```hcl
Resource = [
  aws_s3_bucket.app_data.arn,
  "${aws_s3_bucket.app_data.arn}/*"
]
```

**Why this matters:** The IAM policy grants `s3:GetObject`, `s3:PutObject`, and `s3:ListBucket`. ListBucket needs the bucket ARN, while Get/Put need the object ARN (`/*`). By listing both, all three actions are covered. Without the `/*` entry, Get and Put are denied because the resource ARN doesn't match objects.

### Step 5: The complete fixed main.tf

```hcl
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
```

### Step 6: Validate

```bash
terraform validate
terraform plan
```

**What this does:** Confirms the configuration is syntactically valid and produces a clean plan.

## Docker Lab vs Real Life

- **Policy Simulator:** In production, use the IAM Policy Simulator (`aws iam simulate-principal-policy`) to test whether a specific action is allowed or denied before deploying. This catches permission issues without trial and error.
- **CloudTrail logs:** CloudTrail records every API call, including denied ones. The `errorCode` field shows `AccessDenied`, and `errorMessage` sometimes indicates which policy caused the denial.
- **S3 Block Public Access:** Production buckets should have S3 Block Public Access enabled at both the bucket and account level. This adds another layer that can block access if not configured correctly.
- **VPC Endpoints:** For production workloads, access S3 through a VPC endpoint instead of the public internet. VPC endpoint policies add yet another layer of access control that can deny requests.
- **Cross-account access:** When the IAM role and S3 bucket are in different accounts, BOTH the bucket policy AND the IAM policy must explicitly allow the action. In same-account scenarios, either one is sufficient.

## Key Concepts Learned

- **Explicit Deny always wins** — in AWS IAM evaluation, a Deny in any policy overrides all Allows. Always check for Deny statements first when debugging access issues.
- **S3 has two resource types: bucket and objects** — bucket-level actions need `arn:aws:s3:::bucket`, object-level actions need `arn:aws:s3:::bucket/*`. Using the wrong ARN silently fails.
- **IAM policies often need both ARN patterns** — when a policy grants both bucket-level and object-level actions, include both ARN patterns in the Resource field.
- **Bucket policies and IAM policies work together** — for same-account access, either policy can grant access. For cross-account, both must grant access. An explicit Deny in either always blocks.
- **`Principal: "*"` means everyone** — be extremely careful with wildcard principals. Combined with Allow, it makes the bucket public. Combined with Deny, it blocks everyone including your own roles.

## Common Mistakes

- **Forgetting that Deny overrides Allow** — adding more Allow statements doesn't fix an explicit Deny. You must remove or modify the Deny statement itself.
- **Using `/*` for ListBucket** — this is the most common S3 policy mistake. ListBucket is a bucket-level operation and needs the plain bucket ARN.
- **Not including both ARN patterns in IAM policies** — if your IAM policy grants both ListBucket and GetObject but only has one Resource ARN, half the actions will be denied.
- **Confusing bucket policies with IAM policies** — bucket policies are attached to the bucket (resource-based). IAM policies are attached to roles/users (identity-based). Both are evaluated, and both can grant or deny access.
- **Using `Principal: "*"` with Allow** — this makes the bucket publicly accessible. Always use specific principals (role ARN, account ID) unless you intentionally want public access.

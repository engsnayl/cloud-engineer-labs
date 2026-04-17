# Lab 080 — Secrets Manager Rotation Not Working
## Solution Walkthrough

---

## TLDR — Plain English Summary

AWS Secrets Manager can automatically rotate your database passwords on a schedule — but it doesn't do the rotation itself. It calls a Lambda function to do the actual work. In this lab, the secret exists but rotation was never properly wired up. There are four things missing:

1. The resource that tells Secrets Manager *to* rotate, and *how often*, is missing.
2. The Lambda function that actually changes the password doesn't exist.
3. The Lambda has no IAM permissions to talk to Secrets Manager or the database.
4. Secrets Manager has no permission to invoke the Lambda.

Think of it like setting up a phone alarm but forgetting to turn the volume on, plug in the charger, or have a phone at all. The intent is there, but nothing will actually ring.

The fix is to add all four missing pieces in Terraform and apply them.

---

## Background — How Secrets Manager Rotation Actually Works

Before you touch any code, it helps to understand the rotation mechanism, because it's not obvious.

When Secrets Manager triggers a rotation, it doesn't change the password itself. Instead, it calls a Lambda function and tells it: "Go rotate this secret." The Lambda then executes **four distinct steps** in sequence:

| Step | Name | What it does |
|------|------|--------------|
| 1 | `createSecret` | Generates a new password and stores it as a pending version |
| 2 | `setSecret` | Updates the actual database with the new password |
| 3 | `testSecret` | Verifies the new password actually works |
| 4 | `finishSecret` | Promotes the new password to "current" and retires the old one |

If any step fails, Secrets Manager aborts the rotation and leaves the old password in place. This is why broken rotation can be *silent* — the secret still exists, still has a value, but the rotation never completed.

Three AWS resources must exist and be wired together for rotation to work:

```
aws_secretsmanager_secret  ──► aws_secretsmanager_secret_rotation ──► aws_lambda_function
                                                                           │
                                                               aws_lambda_permission
                                                               (allows SM to invoke it)
```

---

## The Ticket

> **Security Audit Finding — P2**
> The `production/db-password` secret in Secrets Manager has not rotated in 90 days. A rotation policy was reportedly configured but credentials remain stale. Rotation is either not enabled or not functioning. Investigate and fix.

You've been handed this ticket cold. You don't know what's in the Terraform. You don't know what's missing. You need to find out.

---

## Before You Start — Run the Lab Setup

This lab requires a real AWS secret to exist before you begin — so that when you investigate, you're looking at an actual deployed resource that isn't rotating, not just a config file.

```bash
cd ~/cloud-engineer-labs/labs/080-secrets-manager-rotation
chmod +x setup.sh
./setup.sh
```

**What `setup.sh` does:**
- Deploys the secret (`production/db-password`) to AWS with no rotation configured
- Confirms via the AWS CLI that `RotationEnabled` is `false` — this is the fault you're investigating
- Resets `main.tf` to the broken starting state
- Places `rotation.zip` (the Lambda code) in the directory — think of this as a pre-existing rotation function that was written but never deployed

Once setup completes, you'll see the ticket message and the instruction to start with `cat main.tf`. **Do not open `main.tf` before running setup** — setup writes the correct broken starting state.

---

## Step-by-Step Investigative Walkthrough

### Step 1 — Understand the environment before touching anything

Setup has already run. You're now sitting inside the lab directory with the broken state deployed to AWS. Before you touch anything, orient yourself.

```bash
ls
```

**What you're looking for:** A `main.tf`, a `rotation.zip`, and nothing else of note. No Lambda code. No rotation config.

**How would I know what to look for?**
The ticket says "rotation policy was reportedly configured." In Terraform, Secrets Manager rotation lives in `main.tf`. Lambda functions live there too. Your first job is to get eyes on the config before running anything.

```bash
cat main.tf
```

Read it fully before drawing any conclusions. You're looking for:
- An `aws_secretsmanager_secret` block — does the secret exist?
- An `aws_secretsmanager_secret_rotation` block — does rotation actually exist?
- An `aws_lambda_function` block — does the rotation function exist?
- An `aws_lambda_permission` block — can Secrets Manager call the function?

---

### Step 2 — Identify what's present and what's absent

After reading `main.tf`, you should see the secret resource exists — but the rotation-related resources are missing or commented out.

**Ask yourself:** The ticket says rotation was "configured." Is that true? Or did someone add the secret but never wire up the rotation?

**How would I know what's missing?**

The rotation mechanism requires these four resources. If any are absent, rotation cannot work:

| Resource | Purpose |
|---|---|
| `aws_secretsmanager_secret` | The secret itself (the container) |
| `aws_secretsmanager_secret_rotation` | Connects the secret to the Lambda and sets the schedule |
| `aws_lambda_function` | The function that performs the actual four rotation steps |
| `aws_lambda_permission` | Grants Secrets Manager permission to invoke the Lambda |
| `aws_iam_role` + `aws_iam_role_policy` | Grants the Lambda permission to read/write the secret |

**Check the AWS console too (optional but realistic):**

```bash
aws secretsmanager describe-secret \
  --secret-id production/db-password \
  --region eu-west-1
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `aws secretsmanager` | The AWS CLI service namespace for Secrets Manager |
| `describe-secret` | Returns metadata about a secret — including rotation configuration |
| `--secret-id production/db-password` | The name or ARN of the secret to inspect |
| `--region eu-west-1` | Target region (our standard for all AWS labs) |

**What to look for in the output:** Look for `RotationEnabled`. If it's `false` or absent, rotation has never been enabled — despite what the ticket claims. This confirms the Terraform config is incomplete.

---

### Step 3 — Fix 1: Create the rotation Lambda function

Now that you've confirmed rotation isn't wired up, you know what to build. Start with the Lambda function — you can't configure rotation without it.

**Why Lambda first?** The `aws_secretsmanager_secret_rotation` resource requires the Lambda's ARN. You can't reference something that doesn't exist yet in Terraform. Build the dependency first.

Add this to `main.tf`:

```hcl
resource "aws_lambda_function" "rotation" {
  filename         = "rotation.zip"
  function_name    = "db-password-rotation"
  role             = aws_iam_role.rotation_lambda.arn
  handler          = "index.handler"
  runtime          = "python3.11"
  timeout          = 60
  source_code_hash = filebase64sha256("rotation.zip")
}
```

**Command breakdown — what each argument means:**

| Argument | What it does |
|---|---|
| `filename` | Path to the `.zip` file containing your Lambda code |
| `function_name` | The name that appears in the AWS Lambda console |
| `role` | IAM role ARN the function assumes at runtime — this is where its permissions come from |
| `handler` | `filename.function_name` format — tells Lambda where to find the entry point. `index.handler` means: in `index.py`, call the `handler` function |
| `runtime` | Language and version for the execution environment |
| `timeout` | Max seconds before Lambda kills the invocation (rotation can be slow, 60s is safe) |
| `source_code_hash` | A hash of the zip file. If the code changes, Terraform detects it and re-deploys. Without this, Terraform won't notice code updates |

**Why `index.handler` specifically?**
The handler format is `<filename without extension>.<function name>`. A file called `index.py` with a function `def handler(event, context):` maps to `index.handler`. AWS uses this to know exactly which function to call when the Lambda is triggered.

---

### Step 4 — Fix 2: Create the Lambda IAM role and policy

The Lambda function needs two things: a role that allows it to *be* a Lambda function, and a policy that allows it to *talk to Secrets Manager and CloudWatch*.

**How would I know what permissions are needed?**
The Lambda has to perform four rotation steps — each one reads from or writes to Secrets Manager. Without the right permissions, every step fails with `AccessDeniedException`.

Add this to `main.tf`:

```hcl
resource "aws_iam_role" "rotation_lambda" {
  name = "secrets-rotation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "rotation_lambda" {
  name = "secrets-rotation-policy"
  role = aws_iam_role.rotation_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:PutSecretValue",
          "secretsmanager:UpdateSecretVersionStage",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.db_password.arn
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}
```

**Command breakdown — the IAM role:**

| Argument | What it does |
|---|---|
| `assume_role_policy` | The *trust policy* — defines who is allowed to assume this role. Here we're saying: Lambda service can use this role |
| `Principal: { Service: "lambda.amazonaws.com" }` | Only the Lambda service can assume this role (not a user, not EC2) |
| `sts:AssumeRole` | The action that lets a service "pick up" the role and use its permissions |

**Command breakdown — the Secrets Manager permissions:**

| Permission | Why it's needed |
|---|---|
| `secretsmanager:GetSecretValue` | Read the current password during `createSecret` and `testSecret` |
| `secretsmanager:PutSecretValue` | Store the newly generated password during `createSecret` |
| `secretsmanager:UpdateSecretVersionStage` | Promote the new password from "pending" to "current" in `finishSecret` |
| `secretsmanager:DescribeSecret` | Check rotation status and versioning metadata |
| `logs:CreateLogGroup/Stream/PutLogEvents` | Write to CloudWatch so you can debug rotation failures |

**Why scope the secret permissions to just this secret's ARN?**
Least-privilege principle. The Lambda only needs to touch *this one secret*, not every secret in the account. Using `aws_secretsmanager_secret.db_password.arn` ensures the policy is tightly scoped.

---

### Step 5 — Fix 3: Allow Secrets Manager to invoke the Lambda

This is the most commonly forgotten piece. The Lambda has an IAM role, but that's about what the Lambda *itself* can do. You also need to tell Lambda: "Secrets Manager is allowed to call you."

**How would I know this is needed?**
Two different permission systems are at play here:
- **IAM roles** control what the Lambda *does* once running
- **Resource-based policies** (via `aws_lambda_permission`) control *who can invoke* the Lambda

Without this, Secrets Manager triggers the rotation, tries to call the Lambda, and gets a `403 Access Denied` — the rotation silently fails.

Add this to `main.tf`:

```hcl
resource "aws_lambda_permission" "secrets_manager" {
  statement_id  = "AllowSecretsManagerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotation.function_name
  principal     = "secretsmanager.amazonaws.com"
}
```

**Command breakdown:**

| Argument | What it does |
|---|---|
| `statement_id` | A unique label for this permission statement (like a policy SID) |
| `action` | What is being permitted — `lambda:InvokeFunction` allows calling the function |
| `function_name` | Which Lambda function gets this permission attached |
| `principal` | Who is being granted the permission — `secretsmanager.amazonaws.com` is the Secrets Manager service |

**Analogy:** Think of the Lambda as a private room. The IAM role is the key the Lambda carries to open other rooms. The `aws_lambda_permission` is the sign on *your* door that says "Secrets Manager staff are allowed to knock."

---

### Step 6 — Fix 4: Enable rotation on the secret

You now have a Lambda, a role, and a permission grant. The final piece connects everything: tell Secrets Manager to use this Lambda, on this schedule, for this secret.

Add this to `main.tf`:

```hcl
resource "aws_secretsmanager_secret_rotation" "db_password" {
  secret_id           = aws_secretsmanager_secret.db_password.id
  rotation_lambda_arn = aws_lambda_function.rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }
}
```

**Command breakdown:**

| Argument | What it does |
|---|---|
| `secret_id` | Which secret to enable rotation on — references the existing secret resource |
| `rotation_lambda_arn` | The ARN of the Lambda function that will perform the rotation steps |
| `automatically_after_days = 30` | Secrets Manager will trigger rotation every 30 days automatically |

**How would I know 30 days is right?**
It's a common production standard. The security audit flagged 90 days as too long. 30 is the typical default for database credentials. Some high-security environments use 7 or even 1 day. This is a configuration decision, not a technical one.

---

### Step 7 — Validate and apply

```bash
terraform validate
terraform plan
terraform apply
```

**What to look for in `terraform plan`:**
You should see four new resources being added:
- `aws_lambda_function.rotation`
- `aws_iam_role.rotation_lambda`
- `aws_iam_role_policy.rotation_lambda`
- `aws_lambda_permission.secrets_manager`
- `aws_secretsmanager_secret_rotation.db_password`

If Terraform shows no errors and the plan looks right, apply.

**After apply — confirm rotation is now enabled:**

```bash
aws secretsmanager describe-secret \
  --secret-id production/db-password \
  --region eu-west-1 \
  | grep -i rotation
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `describe-secret` | Returns full metadata for the secret |
| `| grep -i rotation` | Pipes the output to grep, filtering for any line containing "rotation" (case insensitive) |

You should see `"RotationEnabled": true` and a `NextRotationDate` value. That confirms the fix is working.

**Optional — trigger a manual rotation to test:**

```bash
aws secretsmanager rotate-secret \
  --secret-id production/db-password \
  --region eu-west-1
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `rotate-secret` | Triggers an immediate rotation (doesn't wait for the schedule) |
| `--secret-id` | The secret to rotate |

This is how a real engineer would verify the fix — don't wait 30 days to find out the rotation function is broken.

> **Note — what you'll actually see in this lab:** Because `rotate_immediately = true` is Terraform's default for `aws_secretsmanager_secret_rotation`, a rotation attempt fires automatically the moment the resource is created during `terraform apply`. The placeholder Lambda runs but doesn't complete the four rotation steps (there's no real database to connect to), leaving the rotation in a pending state. If you then run `rotate-secret` manually, AWS will return:
> ```
> InvalidRequestException: A previous rotation isn't complete. That rotation will be reattempted.
> ```
> This is expected. It confirms Secrets Manager is trying to rotate — the wiring is correct. In a real environment with a working rotation Lambda, the first rotation would complete successfully and `rotate-secret` would work as described.

---

## Lab Notes — Environment Caveats

**No networking infrastructure in this lab — and that's intentional.**

In a real production environment, the rotation Lambda would also need VPC configuration to reach the database — subnets, security groups, and network routes so the function can connect on port 5432 or 3306. Without that, the `setSecret` step would time out.

This lab focuses on the layer *before* that: the rotation wiring. The four missing resources (rotation config, Lambda function, IAM permissions, Lambda invocation permission) are what prevent rotation from even starting. You can't debug a network path problem when the Lambda doesn't exist yet.

The `rotation.zip` deployed in this lab contains a placeholder handler — it will not successfully rotate credentials against a real database. The validator confirms that rotation is correctly configured and wired up in AWS, which is the learning objective. Networking and real rotation function logic are covered in later labs.

If you run `aws secretsmanager rotate-secret` after applying your fix, Secrets Manager will invoke the Lambda and you may see an error in CloudWatch Logs because there's no real database to connect to. This is expected — it does not indicate a problem with your Terraform configuration.

---

## Cleanup / Reset

To reset the lab so it can be run again from Step 1:

```bash
terraform destroy
```

This removes all resources. The broken `main.tf` starting state will be restored by the lab setup.

---

## Lab vs. Real Life

| Lab | Real Life |
|---|---|
| Lambda code is a placeholder zip | AWS provides managed rotation Lambdas for RDS (MySQL, PostgreSQL, etc.) — use those instead of writing your own |
| No VPC configuration needed | Production rotation Lambdas need `vpc_config` with the database's subnets and security groups to reach it on port 5432/3306 |
| Single-user rotation | Zero-downtime production environments use "alternating users" — two DB users rotate in turn so traffic is never interrupted |
| No rotation monitoring | Set up CloudWatch alarms on Secrets Manager CloudTrail events to catch silent rotation failures |
| Credentials stored in Terraform state | Use `ignore_changes = [secret_string]` after initial creation so Terraform doesn't revert rotated passwords |

---

## Common Mistakes to Avoid

**Forgetting `aws_lambda_permission`:** The Lambda exists and has the right IAM role, but Secrets Manager still can't call it. The invocation is denied silently. This is the most commonly missed resource.

**Lambda can't reach the database:** If the database is inside a VPC, the rotation Lambda must be too. Without `vpc_config`, the `setSecret` step will time out trying to connect.

**Not testing rotation manually:** Always run `rotate-secret` after applying changes. A broken rotation function causes silent failures — the secret stays unchanged and nobody knows.

**Rotation errors not monitored:** Rotation failures are logged to CloudWatch, but no alarms fire by default. You won't know rotation failed until the next audit.

**Terraform reverting rotated passwords:** If `secret_string` is in your Terraform state and you run `terraform apply` after rotation, Terraform will revert the password to the original value. Use `ignore_changes = [secret_string]`.

---

## Key Concepts Summary

- Secrets Manager **does not rotate passwords itself** — it calls a Lambda on a schedule
- Rotation requires **five resources**: the secret, the rotation config, the Lambda, the Lambda's IAM role/policy, and the Lambda permission
- The **Lambda permission** (`aws_lambda_permission`) is separate from the IAM role — it controls who can *invoke* the Lambda, not what the Lambda *does*
- `automatically_after_days` sets the **rotation frequency** — 30 days is standard
- Always **test rotation manually** with `rotate-secret` after deploying — don't assume it works

# Solution Walkthrough — Secrets Manager Rotation Not Working

## The Problem

The database password hasn't rotated in 90 days despite a rotation policy being "configured." A security audit flagged the stale credentials. The rotation isn't working because the necessary resources are missing or commented out. There are **four issues**:

1. **Rotation not enabled on the secret** — the `aws_secretsmanager_secret` resource exists, but no rotation configuration is attached.
2. **Missing rotation configuration** — the `aws_secretsmanager_secret_rotation` resource is commented out. Without it, Secrets Manager doesn't know how or when to rotate.
3. **Missing rotation Lambda function** — Secrets Manager uses a Lambda function to perform the actual rotation (generate new password, test it, update the database). No Lambda function exists.
4. **Missing Lambda permissions** — the rotation Lambda needs permissions to read/write secrets and access the database.

## Thought Process

When secret rotation fails, an experienced cloud engineer checks:

1. **Is rotation configured?** — check the `aws_secretsmanager_secret_rotation` resource. Without it, rotation never triggers.
2. **Does the rotation Lambda exist?** — Secrets Manager calls a Lambda function to perform each rotation step. The function must exist and have the correct handler.
3. **Does the Lambda have permissions?** — the rotation function needs `secretsmanager:GetSecretValue`, `secretsmanager:PutSecretValue`, `secretsmanager:UpdateSecretVersionStage`, and network access to the database.
4. **Can Secrets Manager invoke the Lambda?** — an `aws_lambda_permission` must allow `secretsmanager.amazonaws.com` to invoke the function.

## Step-by-Step Solution

### Step 1: Create the rotation Lambda function

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

**Why this matters:** Secrets Manager doesn't rotate passwords itself — it delegates to a Lambda function. The function implements four steps (called "rotation steps"):
1. **createSecret** — generates a new password and stores it as a pending version
2. **setSecret** — updates the database with the new password
3. **testSecret** — verifies the new password works
4. **finishSecret** — marks the new password as the current version

AWS provides rotation function templates for common databases (RDS MySQL, PostgreSQL, etc.) in the Secrets Manager documentation.

### Step 2: Create the Lambda IAM role and policy

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

**Why this matters:** The Lambda function needs:
- **`secretsmanager:GetSecretValue`** — reads the current password
- **`secretsmanager:PutSecretValue`** — stores the new password
- **`secretsmanager:UpdateSecretVersionStage`** — promotes the new password to "current"
- **`secretsmanager:DescribeSecret`** — checks the secret's rotation status
- **CloudWatch Logs permissions** — for debugging rotation failures

### Step 3: Allow Secrets Manager to invoke the Lambda

```hcl
resource "aws_lambda_permission" "secrets_manager" {
  statement_id  = "AllowSecretsManagerInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotation.function_name
  principal     = "secretsmanager.amazonaws.com"
}
```

**Why this matters:** Without this resource-based policy, Secrets Manager can't invoke the Lambda function. The rotation trigger fires, but the invocation is denied.

### Step 4: Enable rotation on the secret

```hcl
resource "aws_secretsmanager_secret_rotation" "db_password" {
  secret_id           = aws_secretsmanager_secret.db_password.id
  rotation_lambda_arn = aws_lambda_function.rotation.arn

  rotation_rules {
    automatically_after_days = 30
  }
}
```

**Why this matters:** This resource connects the three pieces: the secret, the Lambda function, and the rotation schedule. `automatically_after_days = 30` means Secrets Manager triggers the Lambda to rotate the password every 30 days.

### Step 5: Validate

```bash
terraform validate
terraform plan
```

## Docker Lab vs Real Life

- **RDS managed rotation:** For RDS databases, AWS provides a managed rotation Lambda that handles everything automatically. Use `aws_secretsmanager_secret_rotation` with the AWS-provided Lambda ARN instead of writing your own.
- **VPC configuration:** In production, the rotation Lambda needs VPC access to reach the database. Configure `vpc_config` on the Lambda with the database's subnets and security groups.
- **Multi-user rotation:** For zero-downtime rotation, use the "alternating users" strategy. Two database users take turns — while one is being rotated, the other serves traffic. This avoids the brief window where the old password is invalid.
- **Rotation monitoring:** Set up CloudWatch alarms on `secretsmanager.amazonaws.com` CloudTrail events to detect rotation failures. A failed rotation means the password wasn't changed, leaving stale credentials.
- **Cross-account secrets:** In multi-account setups, secrets can be shared across accounts using resource policies. The rotation Lambda must have cross-account access if the database is in a different account.

## Key Concepts Learned

- **Secrets Manager rotation requires a Lambda function** — Secrets Manager triggers the Lambda on schedule, and the Lambda performs the four rotation steps (create, set, test, finish)
- **Three resources are needed for rotation** — the secret itself, the rotation Lambda, and the `aws_secretsmanager_secret_rotation` that connects them
- **The Lambda needs `secretsmanager:*` permissions** — GetSecretValue, PutSecretValue, UpdateSecretVersionStage, and DescribeSecret are all required
- **`aws_lambda_permission` allows Secrets Manager to invoke the Lambda** — without it, the rotation trigger is denied
- **`automatically_after_days` sets the rotation frequency** — 30 days is a common production setting. Security-sensitive environments may use shorter intervals.

## Common Mistakes

- **Forgetting the Lambda permission** — the rotation Lambda exists and has the right IAM role, but Secrets Manager can't invoke it because `aws_lambda_permission` is missing.
- **Lambda can't reach the database** — if the database is in a VPC, the rotation Lambda needs VPC configuration (subnets and security groups) to connect on port 5432/3306.
- **Not testing rotation manually** — always test rotation with `aws secretsmanager rotate-secret --secret-id <id>` before relying on automatic rotation. A broken rotation function causes silent failures.
- **Rotation function errors not monitored** — rotation failures are logged to CloudWatch but don't trigger alarms by default. Set up monitoring for rotation failures.
- **Storing initial password in plain text in Terraform** — the `secret_string` in Terraform state is stored in plain text. Use `ignore_changes = [secret_string]` after the initial creation so Terraform doesn't revert rotated passwords.

# Solution Walkthrough — Lambda Can't Execute (Missing Permissions)

## The Problem

A Lambda function triggered by S3 uploads isn't working. The function exists but CloudWatch shows no invocation logs. There are **three bugs**:

1. **Trust policy allows EC2, not Lambda** — the IAM execution role's trust policy says `Principal: { Service: "ec2.amazonaws.com" }`. Lambda functions need `lambda.amazonaws.com` as the trusted service. With the wrong trust policy, Lambda can't assume the role, and the function can't execute at all.
2. **Missing CloudWatch Logs permissions** — the IAM policy only grants `s3:GetObject`. Lambda needs `logs:CreateLogGroup`, `logs:CreateLogStream`, and `logs:PutLogEvents` to write execution logs. Without these, Lambda can't create its log group or write any output, making debugging impossible.
3. **Missing S3 trigger configuration** — there's no `aws_lambda_permission` (to allow S3 to invoke the Lambda) and no `aws_s3_bucket_notification` (to configure S3 to send events). Without both, S3 doesn't know to trigger the Lambda when objects are uploaded.

## Thought Process

When a Lambda function isn't executing, an experienced cloud engineer checks:

1. **Execution role trust policy** — the role must trust `lambda.amazonaws.com`. If it trusts the wrong service, Lambda can't assume the role at all.
2. **CloudWatch Logs permissions** — every Lambda function needs logging permissions. Without them, even if the function runs, you can't see any output or errors.
3. **Trigger configuration** — two parts: (a) the Lambda resource policy must allow the triggering service to invoke it, (b) the triggering service must be configured to send events.
4. **Function configuration** — handler, runtime, and code must be correct.

## Step-by-Step Solution

### Step 1: Fix Bug 1 — Change trust policy to Lambda service

```hcl
# BROKEN
resource "aws_iam_role" "lambda_role" {
  name = "lambda-processor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }    # Wrong!
      Action    = "sts:AssumeRole"
    }]
  })
}

# FIXED
resource "aws_iam_role" "lambda_role" {
  name = "lambda-processor-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }    # Correct!
      Action    = "sts:AssumeRole"
    }]
  })
}
```

**Why this matters:** The trust policy (assume role policy) defines which AWS services can assume this role. EC2 instances use `ec2.amazonaws.com`, Lambda functions use `lambda.amazonaws.com`, ECS tasks use `ecs-tasks.amazonaws.com`, etc. If the trust policy doesn't include `lambda.amazonaws.com`, the Lambda service can't assume the role, and the function fails to start with a permission error.

### Step 2: Fix Bug 2 — Add CloudWatch Logs permissions

```hcl
# BROKEN — only S3 permissions
resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "${aws_s3_bucket.uploads.arn}/*"
    }]
  })
}

# FIXED — add CloudWatch Logs permissions
resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.uploads.arn}/*"
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

**Why this matters:** Lambda automatically tries to write execution logs to CloudWatch Logs. It needs three permissions:
- **`logs:CreateLogGroup`** — creates the log group `/aws/lambda/<function-name>` if it doesn't exist
- **`logs:CreateLogStream`** — creates a new log stream for each function invocation
- **`logs:PutLogEvents`** — writes the actual log lines (print statements, errors, etc.)

Without these, the function may execute but you'll never see any output. AWS provides a managed policy `AWSLambdaBasicExecutionRole` that includes these exact permissions.

### Step 3: Fix Bug 3 — Add S3 trigger configuration

Add both the Lambda permission and the S3 bucket notification:

```hcl
# Allow S3 to invoke the Lambda function
resource "aws_lambda_permission" "s3_trigger" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.uploads.arn
}

# Configure S3 to send events to Lambda
resource "aws_s3_bucket_notification" "uploads" {
  bucket = aws_s3_bucket.uploads.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.processor.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.s3_trigger]
}
```

**Why this matters:** S3 event triggers require TWO resources:

1. **`aws_lambda_permission`** — this is a resource-based policy on the Lambda function that allows S3 to invoke it. Without this, S3's invocation attempt is rejected with "Access Denied." The `source_arn` restricts which bucket can invoke the function.

2. **`aws_s3_bucket_notification`** — this configures S3 to actually send events. The `events` field specifies which S3 actions trigger the Lambda. `s3:ObjectCreated:*` fires on any new object (PUT, POST, COPY, multipart upload).

The `depends_on` ensures the permission is created before the notification, because S3 validates the permission when the notification is configured.

### Step 4: Validate

```bash
terraform validate
terraform plan
```

**What this does:** Confirms the configuration is valid. The plan should show the Lambda function, IAM role with correct trust policy and permissions, Lambda permission, and S3 bucket notification.

## Docker Lab vs Real Life

- **Managed policies:** In production, use the AWS-managed `AWSLambdaBasicExecutionRole` policy instead of inline policies for CloudWatch Logs permissions. It's maintained by AWS and follows best practices.
- **VPC Lambda:** If the Lambda function needs to access VPC resources (RDS, ElastiCache), it needs VPC configuration and the `AWSLambdaVPCAccessExecutionRole` managed policy. VPC Lambda adds network interface creation time to cold starts.
- **Dead letter queues:** Production Lambda functions should have a DLQ (SQS or SNS) configured for failed invocations. Without a DLQ, failed events are silently lost.
- **Reserved concurrency:** Set reserved concurrency to prevent a Lambda function from consuming all available concurrency in your account, which would throttle other functions.
- **S3 event filtering:** S3 notifications support prefix and suffix filters (`filter_prefix = "uploads/"`, `filter_suffix = ".jpg"`). In production, filter events to avoid unnecessary Lambda invocations and costs.

## Key Concepts Learned

- **Lambda execution roles need `lambda.amazonaws.com` as the trusted service** — the trust policy's Principal must match the AWS service that assumes the role. EC2 and Lambda use different service principals.
- **Every Lambda function needs CloudWatch Logs permissions** — `logs:CreateLogGroup`, `logs:CreateLogStream`, and `logs:PutLogEvents` are essential for any Lambda function to write logs.
- **S3 triggers need both a Lambda permission AND a bucket notification** — the permission allows S3 to invoke Lambda; the notification configures S3 to send events. Both are required.
- **`depends_on` ensures correct creation order** — the S3 notification validates the Lambda permission during creation. If the permission doesn't exist yet, the notification creation fails.
- **Resource-based policies vs identity-based policies** — the `aws_lambda_permission` is a resource-based policy (on the Lambda). The `aws_iam_role_policy` is an identity-based policy (on the role). Both control access but from different perspectives.

## Common Mistakes

- **Using `ec2.amazonaws.com` in Lambda execution role trust policy** — this is the exact mistake in this lab. Copy-pasting from EC2 role templates is the usual cause.
- **Forgetting CloudWatch Logs permissions** — the function might work, but without logs, you can't debug it. Always include logging permissions.
- **Creating the bucket notification before the Lambda permission** — S3 validates the permission when creating the notification. Use `depends_on` to enforce the correct order.
- **Not specifying `source_arn` on the Lambda permission** — without `source_arn`, ANY S3 bucket in the account could invoke the Lambda. Always restrict to the specific bucket.
- **Forgetting the Lambda code package** — the `filename = "lambda.zip"` must exist. In this lab, the zip file needs to be present for `filebase64sha256("lambda.zip")` to work. In production, use CI/CD to build and deploy the code package.

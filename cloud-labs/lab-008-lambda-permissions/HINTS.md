# Hints — Cloud Lab 008: Lambda Permissions

## Hint 1 — Trust policy service
The IAM role's trust policy says `ec2.amazonaws.com` but Lambda functions need `lambda.amazonaws.com`.

## Hint 2 — CloudWatch Logs
Lambda needs `logs:CreateLogGroup`, `logs:CreateLogStream`, and `logs:PutLogEvents` to write execution logs.

## Hint 3 — S3 trigger permissions
You need both an `aws_lambda_permission` (to allow S3 to invoke the function) and an `aws_s3_bucket_notification` (to configure the trigger).

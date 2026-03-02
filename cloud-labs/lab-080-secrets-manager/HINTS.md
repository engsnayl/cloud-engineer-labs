# Hints — Cloud Lab 021: Secrets Manager Rotation

## Hint 1 — Enable rotation
Uncomment the `aws_secretsmanager_secret_rotation` resource and configure it with a Lambda function ARN.

## Hint 2 — Rotation Lambda
You need a Lambda function that: 1. Gets the current secret. 2. Creates a new password. 3. Tests the new password. 4. Updates the secret. AWS provides blueprints for common databases.

## Hint 3 — IAM permissions
The rotation Lambda needs: secretsmanager:GetSecretValue, secretsmanager:PutSecretValue, secretsmanager:UpdateSecretVersionStage. Plus network access to the database.

# Secrets Manager Lab
provider "aws" {
  region = "eu-west-2"
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "production/db-password"
  # BUG 1: Rotation not enabled
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = jsonencode({
    username = "admin"
    password = "initial-password-change-me"
    host     = "db.internal"
    port     = 5432
    dbname   = "production"
  })
}

# BUG 2: Missing rotation configuration
# resource "aws_secretsmanager_secret_rotation" "db_password" {
#   secret_id           = aws_secretsmanager_secret.db_password.id
#   rotation_lambda_arn = aws_lambda_function.rotation.arn
#   rotation_rules {
#     automatically_after_days = 30
#   }
# }

# BUG 3: Missing Lambda function for rotation
# The rotation Lambda needs:
# - SecretsManager permissions
# - VPC access to reach the database
# - Correct IAM execution role

# BUG 4: Missing resource policy allowing Lambda to get the secret

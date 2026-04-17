provider "aws" {
  region = "eu-west-1"
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "production/db-password"
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

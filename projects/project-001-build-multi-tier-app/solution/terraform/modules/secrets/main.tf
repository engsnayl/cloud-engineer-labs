locals {
  base_tags = {
    Component = "secrets-management"
    Module    = "secrets"
  }

  all_tags = merge(local.base_tags, var.tags)
}

resource "aws_secretsmanager_secret" "db" {
  name                    = var.secret_name
  description             = "Database credentials for the multi-tier app. Value populated out-of-band via aws secretsmanager put-secret-value."
  recovery_window_in_days = var.recovery_window_in_days

  tags = local.all_tags
}

resource "aws_iam_user" "eso" {
  name = var.iam_user_name
  path = "/external-secrets/"

  tags = local.all_tags
}

data "aws_iam_policy_document" "eso_read_secret" {
  statement {
    sid    = "ReadOneSecret"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
    ]

    resources = [
      aws_secretsmanager_secret.db.arn,
    ]
  }
}

resource "aws_iam_policy" "eso_read_secret" {
  name        = "${var.iam_user_name}-read-secret"
  description = "Allow ESO to read the multi-tier/db secret. ARN-scoped, least privilege."
  policy      = data.aws_iam_policy_document.eso_read_secret.json

  tags = local.all_tags
}

resource "aws_iam_user_policy_attachment" "eso" {
  user       = aws_iam_user.eso.name
  policy_arn = aws_iam_policy.eso_read_secret.arn
}

resource "aws_iam_access_key" "eso" {
  user = aws_iam_user.eso.name
}

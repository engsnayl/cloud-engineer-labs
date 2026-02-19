# IAM Role Chain Lab
provider "aws" {
  region = "eu-west-2"
}

# The application's own role
resource "aws_iam_role" "app_role" {
  name = "app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# The cross-account target role
resource "aws_iam_role" "shared_services_role" {
  name = "shared-services-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = {
        # BUG 1: Trust policy references wrong role ARN
        AWS = "arn:aws:iam::123456789012:role/wrong-role-name"
      }
      Action    = "sts:AssumeRole"
      # BUG 2: Condition requires external ID but app doesn't pass one
      Condition = {
        StringEquals = {
          "sts:ExternalId" = "required-external-id-12345"
        }
      }
    }]
  })
}

# The app role needs permission to assume the target role
resource "aws_iam_role_policy" "assume_role_policy" {
  name = "assume-shared-services"
  role = aws_iam_role.app_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      # BUG 3: Wrong action — should be sts:AssumeRole
      Action   = "iam:PassRole"
      Resource = aws_iam_role.shared_services_role.arn
    }]
  })
}

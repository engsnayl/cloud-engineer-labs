# EKS IRSA Lab
provider "aws" {
  region = "eu-west-2"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  cluster_name = "lab-cluster"
  namespace    = "default"
  sa_name      = "app-service-account"

  # Simulated OIDC issuer URL (would come from aws_eks_cluster in real setup)
  oidc_issuer = "https://oidc.eks.eu-west-2.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
  oidc_issuer_stripped = replace(local.oidc_issuer, "https://", "")
}

# --- OIDC Provider ---

resource "aws_iam_openid_connect_provider" "eks" {
  url = local.oidc_issuer

  client_id_list = [
    # BUG 1: Client ID should be "sts.amazonaws.com" for EKS IRSA
    "ec2.amazonaws.com"
  ]

  thumbprint_list = ["9e99a48a9960b14926bb7f3b02e22da2b0ab7280"]
}

# --- IAM Role for the Service Account ---

resource "aws_iam_role" "app_role" {
  name = "eks-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.eks.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # BUG 2: Wrong condition key — should use the OIDC issuer URL, not "oidc.eks"
          "oidc.eks:sub" = "system:serviceaccount:${local.namespace}:${local.sa_name}"
          # BUG 3: aud condition references wrong client ID
          "oidc.eks:aud" = "ec2.amazonaws.com"
        }
      }
    }]
  })
}

# --- IAM Policy ---

resource "aws_iam_role_policy" "app_permissions" {
  name = "app-permissions"
  role = aws_iam_role.app_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        # BUG 4: Resource is "*" — should be scoped to specific bucket
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Query"
        ]
        # Same issue — should be scoped to specific table
        Resource = "*"
      }
    ]
  })
}

# --- S3 Bucket and DynamoDB Table ---

resource "aws_s3_bucket" "app_data" {
  bucket = "eks-app-data-${random_id.suffix.hex}"
}

resource "aws_dynamodb_table" "app_state" {
  name         = "app-state"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "id"

  attribute {
    name = "id"
    type = "S"
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

# --- Kubernetes Manifests (as reference — these would be kubectl applied) ---
# The following shows what the K8s service account and pod spec should look like.
# In a real setup, use the kubernetes provider or helm.

# Service Account YAML (for reference):
# apiVersion: v1
# kind: ServiceAccount
# metadata:
#   name: app-service-account
#   namespace: default
#   annotations:
#     # BUG 5: Annotation key should be eks.amazonaws.com/role-arn
#     iam.amazonaws.com/role: arn:aws:iam::ACCOUNT:role/eks-app-role

# Pod YAML (for reference):
# spec:
#   # BUG 6: serviceAccountName must match the service account name
#   serviceAccountName: default

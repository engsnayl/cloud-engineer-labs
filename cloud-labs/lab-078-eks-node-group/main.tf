# EKS Node Group Lab
provider "aws" {
  region = "eu-west-2"
}

resource "aws_eks_cluster" "main" {
  name     = "production"
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = [aws_subnet.a.id, aws_subnet.b.id]
  }
}

resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "workers"
  # BUG 1: Wrong IAM role (using cluster role instead of node role)
  node_role_arn   = aws_iam_role.cluster.arn
  subnet_ids      = [aws_subnet.a.id, aws_subnet.b.id]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  # BUG 2: Missing instance types
}

resource "aws_iam_role" "cluster" {
  name = "eks-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}

# BUG 3: Missing node IAM role entirely
# Nodes need their own role with EC2 trust policy and specific managed policies:
# - AmazonEKSWorkerNodePolicy
# - AmazonEKS_CNI_Policy
# - AmazonEC2ContainerRegistryReadOnly

resource "aws_vpc" "main" { cidr_block = "10.0.0.0/16" }
resource "aws_subnet" "a" { vpc_id = aws_vpc.main.id; cidr_block = "10.0.1.0/24"; availability_zone = "eu-west-2a" }
resource "aws_subnet" "b" { vpc_id = aws_vpc.main.id; cidr_block = "10.0.2.0/24"; availability_zone = "eu-west-2b" }

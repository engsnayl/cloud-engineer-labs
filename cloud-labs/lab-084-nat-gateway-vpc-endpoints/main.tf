# NAT Gateway & VPC Endpoints Lab

provider "aws" {
  region = "eu-west-2"
}

data "aws_availability_zones" "available" {
  state = "available"
}

# Latest Amazon Linux 2023 AMI (ARM64) — used for the test instance
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "lab-vpc" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "lab-igw" }
}

# Public subnet
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true
  tags                    = { Name = "public-subnet" }
}

# Private subnet
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]
  tags              = { Name = "private-subnet" }
}

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway
resource "aws_eip" "nat" {
  domain = "vpc"
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.private.id
  tags          = { Name = "lab-nat-gw" }
  depends_on    = [aws_internet_gateway.main]
}

# Private route table
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "private-rt" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# S3 VPC Endpoint
resource "aws_vpc_endpoint" "s3" {
  vpc_id          = aws_vpc.main.id
  service_name    = "com.amazonaws.eu-west-2.s3"
  route_table_ids = [aws_route_table.public.id]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = "*"
    }]
  })

  tags = { Name = "s3-endpoint" }
}

# ---------------------------------------------------------------------------
# Test harness: private EC2 instance + S3 bucket to reproduce the incident
# ---------------------------------------------------------------------------

# Random suffix so the S3 bucket name is globally unique
resource "random_id" "suffix" {
  byte_length = 4
}

# S3 bucket the private instance is supposed to be able to list
resource "aws_s3_bucket" "test" {
  bucket        = "lab-084-test-${random_id.suffix.hex}"
  force_destroy = true
  tags          = { Name = "lab-084-test-bucket" }
}

# IAM role allowing the instance to be managed by SSM Session Manager
resource "aws_iam_role" "ssm" {
  name = "lab-084-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Inline policy granting the instance just enough S3 access to test the
# VPC Endpoint end-to-end. Scoped to the lab bucket only.
resource "aws_iam_role_policy" "s3_test_access" {
  name = "lab-084-s3-test-access"
  role = aws_iam_role.ssm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.test.arn
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "${aws_s3_bucket.test.arn}/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ssm" {
  name = "lab-084-ssm-profile"
  role = aws_iam_role.ssm.name
}

# Security group — allow all egress so any reachability failure is routing
# or endpoint related, not SG related
resource "aws_security_group" "instance" {
  name        = "lab-084-instance-sg"
  description = "Egress for private instance"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "lab-084-instance-sg" }
}

# Private instance — the thing that's meant to reach S3 and the internet
resource "aws_instance" "private" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t4g.nano"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.ssm.name

  tags = { Name = "lab-084-private-instance" }
}

# ---------------------------------------------------------------------------
# SSM Interface Endpoints — management-plane access independent of NAT.
# These let the SSM agent register and Session Manager work even when the
# NAT / internet path is broken (which is the whole point of this lab).
# ---------------------------------------------------------------------------

resource "aws_security_group" "ssm_endpoints" {
  name        = "lab-084-ssm-endpoints-sg"
  description = "Allow HTTPS from the VPC to SSM Interface Endpoints"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "lab-084-ssm-endpoints-sg" }
}

resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.eu-west-2.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.ssm_endpoints.id]
  private_dns_enabled = true
  tags                = { Name = "ssm-endpoint" }
}

resource "aws_vpc_endpoint" "ssmmessages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.eu-west-2.ssmmessages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.ssm_endpoints.id]
  private_dns_enabled = true
  tags                = { Name = "ssmmessages-endpoint" }
}

resource "aws_vpc_endpoint" "ec2messages" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.eu-west-2.ec2messages"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private.id]
  security_group_ids  = [aws_security_group.ssm_endpoints.id]
  private_dns_enabled = true
  tags                = { Name = "ec2messages-endpoint" }
}

# Outputs the engineer will use during investigation
output "instance_id" {
  description = "Private EC2 instance ID — connect via: aws ssm start-session --target <id>"
  value       = aws_instance.private.id
}

output "bucket_name" {
  description = "S3 bucket the instance should be able to list"
  value       = aws_s3_bucket.test.bucket
}

output "region" {
  description = "AWS region"
  value       = "eu-west-2"
}

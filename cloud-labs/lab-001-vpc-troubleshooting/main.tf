# =============================================================================
# Cloud Lab 001: VPC Troubleshooting
# THIS TERRAFORM IS DELIBERATELY BROKEN — YOUR JOB IS TO FIX IT
# There are 4 bugs. Find them all.
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------- VPC ----------

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "lab001-vpc" }
}

# ---------- Subnets ----------

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = { Name = "lab001-public-subnet" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.aws_region}a"

  tags = { Name = "lab001-private-subnet" }
}

# ---------- Internet Gateway ----------

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "lab001-igw" }
}

# ---------- NAT Gateway ----------

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = { Name = "lab001-nat-eip" }
}

# BUG 1: NAT Gateway is in the PRIVATE subnet — it should be in the PUBLIC subnet
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.private.id

  tags = { Name = "lab001-nat-gw" }

  depends_on = [aws_internet_gateway.main]
}

# ---------- Route Tables ----------

# Public route table
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "lab001-public-rt" }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# Private route table
# BUG 2: Private route table points to the IGW instead of the NAT Gateway
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "lab001-private-rt" }
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}

# ---------- Security Group ----------

# BUG 3: Security group has NO egress rule — EC2 can't make outbound connections
resource "aws_security_group" "app" {
  name_prefix = "lab001-app-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for application instance"

  ingress {
    description = "SSH from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"]
  }

  # Egress rule deliberately missing

  tags = { Name = "lab001-app-sg" }
}

# ---------- EC2 Instance ----------

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# BUG 4: Instance is launched in the PUBLIC subnet instead of the PRIVATE subnet
resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.app.id]

  user_data = <<-EOF
    #!/bin/bash
    echo "App server ready" > /tmp/status
  EOF

  tags = { Name = "lab001-app-server" }
}

# ---------- Outputs ----------

output "instance_id" {
  value = aws_instance.app.id
}

output "instance_private_ip" {
  value = aws_instance.app.private_ip
}

output "vpc_id" {
  value = aws_vpc.main.id
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "eu-west-2"
}

# =============================================================================
# DATA SOURCES
# =============================================================================

# Always fetch the latest Amazon Linux 2023 AMI — avoids hardcoded AMI IDs
# that go stale or differ between accounts.
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# =============================================================================
# NETWORKING
# A minimal VPC with one public subnet. Instances get public IPs so we can
# reach them without a bastion. Private subnets and NAT are omitted — they
# add cost and complexity not needed for this lab's learning objective.
# =============================================================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "lab092-vpc"
    Lab         = "092"
    Environment = "lab"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "lab092-public-subnet"
    Lab         = "092"
    Environment = "lab"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "lab092-igw"
    Lab         = "092"
    Environment = "lab"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "lab092-public-rt"
    Lab         = "092"
    Environment = "lab"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# =============================================================================
# SECURITY GROUP
# Allows SSH for debugging. HTTP/HTTPS included to simulate a realistic web
# server environment. All outbound traffic allowed.
# =============================================================================

resource "aws_security_group" "lab" {
  name_prefix = "lab092-"
  vpc_id      = aws_vpc.main.id
  description = "Lab 092 — right-sizing exercise instances"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "lab092-sg"
    Lab         = "092"
    Environment = "lab"
  }
}

# =============================================================================
# EC2 INSTANCES — DELIBERATELY OVER-PROVISIONED
#
# These instances are intentionally too large for their stated purpose.
# The lab objective is to use Compute Optimizer to identify this and apply
# a right-sizing recommendation.
#
# DO NOT change the instance_type values — the validator checks for the
# over-provisioned types as the starting state.
#
# Note: ARM64 AMI used to match Graviton instance types available in eu-west-2.
# m5 and t3 families are x86_64. If you see AMI compatibility errors, check
# that the AMI architecture matches the instance family.
# =============================================================================

# Production web servers — m5.2xlarge is 8 vCPU / 32GB RAM.
# A small company's web servers typically run at 5–10% CPU.
# This is the most expensive waste in the deployment.
resource "aws_instance" "prod_web" {
  count         = 2
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "m5.2xlarge"

  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.lab.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 100
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name        = "prod-web-${count.index + 1}"
    Lab         = "092"
    Environment = "production"
    Role        = "web-server"
    Team        = "engineering"
  }
}

# Dev web server — m5.xlarge is 4 vCPU / 16GB RAM.
# Dev servers are used during business hours only and at low intensity.
resource "aws_instance" "dev_web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "m5.xlarge"

  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.lab.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name        = "dev-web"
    Lab         = "092"
    Environment = "development"
    Role        = "web-server"
    Team        = "engineering"
  }
}

# Dev workers — m5.xlarge for background processing.
# These run lightweight tasks and sit idle most of the day.
resource "aws_instance" "dev_worker" {
  count         = 2
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "m5.xlarge"

  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.lab.id]
  associate_public_ip_address = true

  root_block_device {
    volume_size           = 50
    volume_type           = "gp3"
    delete_on_termination = true
  }

  tags = {
    Name        = "dev-worker-${count.index + 1}"
    Lab         = "092"
    Environment = "development"
    Role        = "worker"
    Team        = "engineering"
  }
}

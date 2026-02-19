# Workspace Management Lab
provider "aws" {
  region = "eu-west-2"
}

# BUG 1: No workspace-aware configuration
# This deploys the same thing regardless of workspace
resource "aws_instance" "app" {
  # Should be t3.micro for staging, t3.large for production
  ami           = "ami-0c76bd4bd302b30ec"
  instance_type = "t3.micro"
  
  tags = {
    # BUG 2: Environment tag is hardcoded
    Name        = "app-server"
    Environment = "staging"
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "app-asg"
  # BUG 3: Same scaling for all environments
  min_size            = 1
  max_size            = 2
  desired_capacity    = 1
  vpc_zone_identifier = [aws_subnet.app.id]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }
}

resource "aws_launch_template" "app" {
  name_prefix   = "app-"
  image_id      = "ami-0c76bd4bd302b30ec"
  instance_type = "t3.micro"
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "app" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
}

# TASK: Make this workspace-aware using terraform.workspace
# and local values or variable maps

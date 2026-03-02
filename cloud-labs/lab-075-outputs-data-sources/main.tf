# Outputs and Data Sources Lab
provider "aws" {
  region = "eu-west-2"
}

# BUG 1: Hardcoded AMI that doesn't exist in eu-west-2
resource "aws_instance" "app" {
  ami           = "ami-0123456789abcdef0"
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.app.id
  tags = { Name = "app-server" }
}

# TASK: Replace hardcoded AMI with a data source
# data "aws_ami" "ubuntu" {
#   most_recent = true
#   owners      = ["099720109477"]  # Canonical
#   filter {
#     name   = "name"
#     values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
#   }
# }

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "app" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
}

# BUG 2: Missing outputs — other modules need these
# output "vpc_id" { }
# output "subnet_id" { }
# output "instance_id" { }
# output "instance_private_ip" { }

# BUG 3: This output references wrong attribute
output "app_public_ip" {
  value = aws_instance.app.private_ip  # Should be public if needed
  description = "The public IP of the app server"
}

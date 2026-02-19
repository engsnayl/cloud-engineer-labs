# Conditional Logic Lab
provider "aws" {
  region = "eu-west-2"
}

variable "environment" {
  default = "production"
}

variable "enable_monitoring" {
  default = true
}

# BUG 1: Condition is inverted — creates bastion in production, not staging
resource "aws_instance" "bastion" {
  count         = var.environment == "production" ? 1 : 0
  ami           = "ami-0c76bd4bd302b30ec"
  instance_type = "t3.micro"
  tags = { Name = "bastion-host" }
}

# BUG 2: for_each on a list without toset()
variable "subnet_cidrs" {
  default = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "app" {
  for_each   = var.subnet_cidrs  # Should be toset()
  vpc_id     = aws_vpc.main.id
  cidr_block = each.value
}

# BUG 3: Dynamic block with wrong iterator reference
resource "aws_security_group" "app" {
  name   = "app-sg"
  vpc_id = aws_vpc.main.id

  dynamic "ingress" {
    for_each = [80, 443, 8080]
    content {
      from_port   = ingress.key      # Should be ingress.value
      to_port     = ingress.key      # Should be ingress.value
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
}

# BUG 4: Wrong conditional for monitoring
resource "aws_cloudwatch_metric_alarm" "cpu" {
  count               = var.enable_monitoring ? 0 : 1  # Inverted!
  alarm_name          = "high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 120
  statistic           = "Average"
  threshold           = 80
}

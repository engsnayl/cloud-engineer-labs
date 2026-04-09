# Workspace Management Lab
provider "aws" {
  region = "eu-west-2"
}

resource "aws_instance" "app" {
  ami           = "ami-0c76bd4bd302b30ec"
  instance_type = "t3.micro"
  
  tags = {
    Name        = "app-server"
    Environment = "staging"
  }
}

resource "aws_autoscaling_group" "app" {
  name                = "app-asg"
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


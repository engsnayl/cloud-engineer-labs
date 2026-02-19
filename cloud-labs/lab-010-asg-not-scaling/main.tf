# ASG Scaling Lab
provider "aws" {
  region = "eu-west-2"
}

resource "aws_launch_template" "app" {
  name_prefix   = "app-"
  image_id      = "ami-0c76bd4bd302b30ec"
  instance_type = "t3.micro"
}

resource "aws_autoscaling_group" "app" {
  name                = "app-asg"
  # BUG 1: max_size equals min_size — can't scale up
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  vpc_zone_identifier = [aws_subnet.app.id]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  # BUG 2: Health check type should be ELB if behind a load balancer
  health_check_type = "EC2"
}

resource "aws_autoscaling_policy" "scale_up" {
  name                   = "scale-up"
  # BUG 3: Wrong scaling type
  scaling_adjustment     = 1
  adjustment_type        = "ExactCapacity"
  cooldown               = 300
  autoscaling_group_name = aws_autoscaling_group.app.name
}

resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Average"
  threshold           = 70
  alarm_actions       = [aws_autoscaling_policy.scale_up.arn]
  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.app.name
  }
}

# Supporting VPC resources
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "app" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
}

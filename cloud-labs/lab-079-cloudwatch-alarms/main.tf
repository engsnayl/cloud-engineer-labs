# Lab 079 — CloudWatch Alarms Misconfigured
# This file intentionally contains four bugs. Do not fix before running setup.sh.

provider "aws" {
  region = "eu-west-2"
}

# Fetch the latest Amazon Linux 2023 AMI for eu-west-2
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "app" {
  ami           = data.aws_ssm_parameter.al2023.value
  instance_type = "t3.micro"
  tags = { Name = "app-server" }
}

resource "aws_sns_topic" "alerts" {
  name = "ops-alerts"
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name          = "high-cpu"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
}

resource "aws_cloudwatch_metric_alarm" "status_check" {
  alarm_name          = "status-check-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 3600
  statistic           = "Maximum"
  threshold           = 0
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = {
    InstanceId = "i-placeholder"
  }
}

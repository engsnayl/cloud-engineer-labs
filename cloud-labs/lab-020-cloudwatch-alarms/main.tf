# CloudWatch Alarms Lab
provider "aws" {
  region = "eu-west-2"
}

resource "aws_sns_topic" "alerts" {
  name = "ops-alerts"
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  alarm_name          = "high-cpu"
  # BUG 1: Wrong comparison operator
  comparison_operator = "LessThanThreshold"  # Should be GreaterThan for high CPU
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  # BUG 2: No alarm actions — won't notify anyone
  # alarm_actions       = [aws_sns_topic.alerts.arn]
  
  # BUG 3: Missing dimensions — alarm applies to nothing
  # dimensions = {
  #   InstanceId = aws_instance.app.id
  # }
}

resource "aws_cloudwatch_metric_alarm" "status_check" {
  alarm_name          = "status-check-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  # BUG 4: Period too long — won't catch brief failures
  period              = 3600  # 1 hour — should be 60 seconds
  statistic           = "Maximum"
  threshold           = 0
  alarm_actions       = [aws_sns_topic.alerts.arn]
  dimensions = {
    InstanceId = "i-placeholder"
  }
}

resource "aws_instance" "app" {
  ami           = "ami-0c76bd4bd302b30ec"
  instance_type = "t3.micro"
  tags = { Name = "app-server" }
}

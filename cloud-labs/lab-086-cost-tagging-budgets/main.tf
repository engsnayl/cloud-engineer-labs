# Cost Tagging & Budgets Lab

provider "aws" {
  region = "eu-west-2"
}

locals {
  common_tags = {
    Environment = "production"
    Project     = "web-platform"
    Team        = "platform-engineering"
    CostCentre  = "CC-4521"
    ManagedBy   = "terraform"
  }
}

# Example resources that should all be tagged
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
}

resource "aws_s3_bucket" "app_assets" {
  bucket = "app-assets-${random_id.suffix.hex}"
}

resource "random_id" "suffix" {
  byte_length = 4
}

# --- Budget ---
resource "aws_budgets_budget" "monthly" {
  name         = "monthly-account-budget"
  budget_type  = "COST"
  limit_amount = "10000"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"
}

# --- CloudWatch Billing Alarm ---
resource "aws_cloudwatch_metric_alarm" "billing" {
  alarm_name          = "monthly-billing-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = 21600
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Alert when estimated charges exceed monthly budget"
  alarm_actions       = [aws_sns_topic.billing_alerts.arn]

  dimensions = {
    Currency = "USD"
  }
}

# --- SNS for Alerts ---
resource "aws_sns_topic" "billing_alerts" {
  name = "billing-alerts"
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.billing_alerts.arn
  protocol  = "email"
  endpoint  = "finance@example.com"
}

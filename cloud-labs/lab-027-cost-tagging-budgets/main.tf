# Cost Tagging & Budgets Lab
provider "aws" {
  region = "eu-west-2"

  # BUG 1: No default tags — every resource should inherit standard tags
  # Missing default_tags block
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
  # BUG 2: No tags applied — should use local.common_tags
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  # BUG 2 continued: No tags
}

resource "aws_s3_bucket" "app_assets" {
  bucket = "app-assets-${random_id.suffix.hex}"
  # BUG 2 continued: No tags
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

  # BUG 3: No notifications configured — budget exists but doesn't alert anyone
}

# --- CloudWatch Billing Alarm ---

resource "aws_cloudwatch_metric_alarm" "billing" {
  alarm_name          = "monthly-billing-alarm"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EstimatedCharges"
  namespace           = "AWS/Billing"
  period              = 21600  # 6 hours
  statistic           = "Maximum"
  # BUG 4: Threshold is $0 — will alarm immediately and constantly
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
  # BUG 5: No tags on the SNS topic either
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.billing_alerts.arn
  protocol  = "email"
  endpoint  = "finance@example.com"
}

# Security Hub & GuardDuty Lab
provider "aws" {
  region = "eu-west-2"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# --- GuardDuty ---

resource "aws_guardduty_detector" "main" {
  # BUG 1: GuardDuty is not enabled — enable must be true
  enable = false

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        # BUG 2: Kubernetes audit logs not enabled
        enable = false
      }
    }
  }

  finding_publishing_frequency = "FIFTEEN_MINUTES"
}

# --- Security Hub ---

resource "aws_securityhub_account" "main" {}

# BUG 3: GuardDuty integration not enabled in Security Hub
# Missing: aws_securityhub_product_subscription for GuardDuty

# --- EventBridge Rule for Critical Findings ---

resource "aws_cloudwatch_event_rule" "critical_findings" {
  name        = "security-hub-critical-findings"
  description = "Route critical Security Hub findings to SNS"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = [
            # BUG 4: Only matching INFORMATIONAL — should match CRITICAL and HIGH
            "INFORMATIONAL"
          ]
        }
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "sns" {
  rule      = aws_cloudwatch_event_rule.critical_findings.name
  target_id = "security-findings-sns"
  arn       = aws_sns_topic.security_alerts.arn
}

# --- SNS Topic for Alerts ---

resource "aws_sns_topic" "security_alerts" {
  name = "security-hub-critical-alerts"
}

resource "aws_sns_topic_policy" "security_alerts" {
  arn = aws_sns_topic.security_alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        # BUG 5: Wrong principal — should be events.amazonaws.com for EventBridge
        Principal = {
          Service = "s3.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.security_alerts.arn
      }
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.security_alerts.arn
  protocol  = "email"
  endpoint  = "security-team@example.com"
}

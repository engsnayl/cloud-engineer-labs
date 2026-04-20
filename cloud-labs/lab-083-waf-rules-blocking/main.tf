provider "aws" {
  region = "eu-west-2"
}

resource "aws_wafv2_ip_set" "office_ips" {
  name               = "office-ip-set"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses = [
    "10.0.0.0/8",
    "192.168.1.0/24",
    "203.0.113.50/32",
    "198.51.100.100/32",
  ]
}

resource "aws_wafv2_web_acl" "main" {
  name        = "app-waf-acl"
  scope       = "REGIONAL"
  description = "WAF ACL for main application"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit"
    priority = 1
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 100
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "ip-blocklist"
    priority = 2
    action {
      block {}
    }
    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.office_ips.arn
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "ip-blocklist"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "geo-block"
    priority = 3
    action {
      block {}
    }
    statement {
      geo_match_statement {
        country_codes = [
          "GB",
          "IE",
          "US",
        ]
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "geo-block"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "app-waf"
    sampled_requests_enabled   = true
  }
}

output "web_acl_arn" {
  value       = aws_wafv2_web_acl.main.arn
  description = "ARN of the Web ACL"
}

output "web_acl_id" {
  value       = aws_wafv2_web_acl.main.id
  description = "ID of the Web ACL"
}

output "web_acl_name" {
  value       = aws_wafv2_web_acl.main.name
  description = "Name of the Web ACL"
}

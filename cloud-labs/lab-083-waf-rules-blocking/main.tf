# WAF Rules Lab
provider "aws" {
  region = "eu-west-2"
}

resource "aws_wafv2_ip_set" "office_ips" {
  name               = "office-ip-set"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses = [
    # BUG 1: This is the office CIDR — it's in the BLOCK list instead of an allow list
    "10.0.0.0/8",
    "192.168.1.0/24",
    # Actual malicious IPs that should be blocked
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

  # Rate limiting rule
  rule {
    name     = "rate-limit"
    # BUG 2: Priority 1 means this is evaluated FIRST — blocks users before allow rules run
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        # BUG 3: Limit of 100 requests per 5 minutes is way too low for normal browsing
        # A single page load can generate 20-50 requests (images, CSS, JS, API calls)
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

  # IP blocklist rule
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

  # Geo restriction rule
  rule {
    name     = "geo-block"
    priority = 3

    action {
      block {}
    }

    statement {
      geo_match_statement {
        country_codes = [
          # BUG 4: This BLOCKS these countries — but GB and IE are where your users are!
          # Should block countries you DON'T serve, not your primary markets
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

# Route 53 Failover Lab
provider "aws" {
  region = "eu-west-2"
}

resource "aws_route53_zone" "main" {
  name = "example-internal.com"
}

resource "aws_route53_health_check" "primary" {
  # BUG 1: Health check on wrong port
  fqdn              = "primary.example-internal.com"
  port               = 8080  # App is on port 80
  type               = "HTTP"
  resource_path      = "/health"
  failure_threshold  = 3
  request_interval   = 30
}

resource "aws_route53_record" "primary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "app.example-internal.com"
  type    = "A"
  ttl     = 300

  # BUG 2: Missing failover routing policy
  # Should have: failover_routing_policy { type = "PRIMARY" }
  # set_identifier = "primary"
  # health_check_id = aws_route53_health_check.primary.id
  
  records = ["10.0.1.100"]
}

resource "aws_route53_record" "secondary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "app.example-internal.com"
  type    = "A"
  # BUG 3: Very long TTL means slow failover
  ttl     = 3600

  # BUG 4: Missing failover routing policy for secondary
  
  records = ["10.1.1.100"]
}

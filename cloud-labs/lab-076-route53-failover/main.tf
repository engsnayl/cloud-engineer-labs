# Route 53 Failover Lab
provider "aws" {
  region = "eu-west-2"
}

resource "aws_route53_zone" "main" {
  name = "example-internal.com"
}

resource "aws_route53_health_check" "primary" {
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
  records = ["10.0.1.100"]
}

resource "aws_route53_record" "secondary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "app.example-internal.com"
  type    = "A"
  ttl     = 3600
  
  records = ["10.1.1.100"]
}

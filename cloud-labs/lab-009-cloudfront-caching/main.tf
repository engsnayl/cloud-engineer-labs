# CloudFront Caching Lab
provider "aws" {
  region = "us-east-1"
}

resource "aws_s3_bucket" "website" {
  bucket = "website-${random_id.suffix.hex}"
}

resource "aws_s3_bucket_website_configuration" "website" {
  bucket = aws_s3_bucket.website.id
  index_document { suffix = "index.html" }
}

resource "aws_cloudfront_distribution" "website" {
  origin {
    # BUG 1: Using S3 bucket domain instead of website endpoint
    domain_name = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id   = "S3-website"
  }

  enabled             = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-website"

    forwarded_values {
      query_string = false
      cookies { forward = "none" }
    }

    viewer_protocol_policy = "redirect-to-https"
    # BUG 2: Very long TTL means stale content
    min_ttl     = 86400
    default_ttl = 604800
    max_ttl     = 31536000
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}

resource "random_id" "suffix" {
  byte_length = 4
}

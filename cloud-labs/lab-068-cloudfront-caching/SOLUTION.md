# Solution Walkthrough — CloudFront Serving Stale Content (Cache Issues)

## The Problem

CloudFront is serving outdated content. The S3 origin has been updated, but CloudFront keeps returning the old version. Customers are seeing an outdated pricing page even though the S3 bucket has the correct content. There are **two bugs**:

1. **Using S3 bucket domain instead of website endpoint** — the origin uses `bucket_regional_domain_name`, which is the S3 REST API endpoint. When using S3 website hosting (which is configured with `aws_s3_bucket_website_configuration`), the origin should use the website endpoint instead. The REST API endpoint doesn't process `index.html` redirects or custom error pages that the website configuration defines.
2. **Extremely long cache TTLs** — the cache TTL values are set to absurdly long durations: `min_ttl = 86400` (1 day minimum!), `default_ttl = 604800` (7 days), `max_ttl = 31536000` (1 year). This means CloudFront caches content for up to 7 days by default and won't check the origin for updates during that time. Even if you update S3 immediately, users see the old content for days.

## Thought Process

When CloudFront serves stale content, an experienced cloud engineer checks:

1. **Cache TTL values** — how long does CloudFront cache content before checking the origin for updates? The `default_ttl` is the key value — if it's set to days or weeks, that's your problem.
2. **Origin configuration** — is the origin pointing to the right endpoint? S3 REST API vs S3 website endpoint behave differently.
3. **Cache behaviors** — are there path-based cache behaviors that might cache different paths differently?
4. **Origin response headers** — does the origin send `Cache-Control` or `Expires` headers? These can override CloudFront's TTL settings.
5. **Cache invalidation** — as an immediate fix, you can invalidate the CloudFront cache to force it to fetch fresh content from the origin.

## Step-by-Step Solution

### Step 1: Fix Bug 1 — Use the S3 website endpoint for the origin

```hcl
# BROKEN — using REST API endpoint
resource "aws_cloudfront_distribution" "website" {
  origin {
    domain_name = aws_s3_bucket.website.bucket_regional_domain_name
    origin_id   = "S3-website"
  }
}

# FIXED — use website endpoint
resource "aws_cloudfront_distribution" "website" {
  origin {
    domain_name = aws_s3_bucket_website_configuration.website.website_endpoint
    origin_id   = "S3-website"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }
}
```

**Why this matters:** There are two ways to serve content from S3 through CloudFront:

1. **S3 REST API endpoint** (`bucket_regional_domain_name`) — treats S3 as a bucket. Doesn't support website features like `index.html` redirects, custom error pages, or redirect rules. Typically used with Origin Access Identity (OAI) or Origin Access Control (OAC) for private bucket access.

2. **S3 website endpoint** (`website_endpoint`) — treats S3 as a web server. Supports `index.html` as default document, custom error pages, and redirect rules. Must use `custom_origin_config` because the website endpoint is HTTP-only and is treated as a custom origin, not an S3 origin.

Since this lab uses `aws_s3_bucket_website_configuration` with `index_document`, the website endpoint is the correct origin.

### Step 2: Fix Bug 2 — Set reasonable cache TTLs

```hcl
# BROKEN — 7-day default cache!
default_cache_behavior {
  min_ttl     = 86400      # 1 day minimum — too long
  default_ttl = 604800     # 7 days — way too long
  max_ttl     = 31536000   # 1 year maximum
}

# FIXED — reasonable TTLs
default_cache_behavior {
  min_ttl     = 0          # Allow origin to set no-cache if needed
  default_ttl = 3600       # 1 hour — good balance
  max_ttl     = 86400      # 1 day maximum
}
```

**Why this matters:** TTL (Time To Live) controls how long CloudFront caches content before checking the origin for updates:

- **`min_ttl = 0`** — allows the origin to control caching via `Cache-Control: no-cache` or `max-age=0`. If the origin says "don't cache," CloudFront respects it.
- **`default_ttl = 3600`** (1 hour) — when the origin doesn't send Cache-Control headers, CloudFront caches for 1 hour. This is a reasonable balance between freshness and performance.
- **`max_ttl = 86400`** (1 day) — even if the origin says `Cache-Control: max-age=9999999`, CloudFront caps caching at 1 day. This prevents extremely stale content.

The original values were extreme: a 7-day default meant users had to wait up to a week to see updated content. For a website with pricing pages, this is unacceptable.

### Step 3: The complete fixed distribution

```hcl
resource "aws_cloudfront_distribution" "website" {
  origin {
    domain_name = aws_s3_bucket_website_configuration.website.website_endpoint
    origin_id   = "S3-website"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
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
    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  restrictions {
    geo_restriction { restriction_type = "none" }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
```

### Step 4: Invalidate the existing cache (if distribution is live)

Even after fixing the TTLs, the currently cached content still has the old TTL. Force a refresh:

```bash
aws cloudfront create-invalidation \
  --distribution-id <DISTRIBUTION_ID> \
  --paths "/*"
```

**What this does:** Tells CloudFront to immediately expire all cached content. The next request for any path will fetch fresh content from the origin. The `/*` wildcard invalidates everything. You can also invalidate specific paths like `/pricing.html`.

**Cost note:** The first 1,000 invalidation paths per month are free. After that, $0.005 per path. Using `/*` counts as 1 path.

### Step 5: Validate

```bash
terraform validate
terraform plan
```

**What this does:** Confirms the configuration is valid and the plan shows the corrected distribution.

## Docker Lab vs Real Life

- **Cache policies:** Modern CloudFront configurations use cache policies (`aws_cloudfront_cache_policy`) instead of inline `forwarded_values`. Cache policies are reusable, centrally managed, and support more features.
- **Origin Access Control (OAC):** For private S3 buckets, use OAC instead of the website endpoint. OAC allows CloudFront to access the bucket directly with signed requests, keeping the bucket completely private.
- **Multiple cache behaviors:** Production distributions often have different cache behaviors for different paths — `/api/*` with no caching, `/static/*` with long TTLs, and `/` with short TTLs.
- **Cache invalidation in CI/CD:** Production deployments automatically invalidate changed paths after deploying new content to S3. Tools like `aws s3 sync --delete` combined with `aws cloudfront create-invalidation` automate this.
- **Versioned assets:** A better alternative to cache invalidation is versioned filenames (`style.v2.css`, `app.abc123.js`). Since the URL changes, CloudFront fetches the new version automatically. This is why build tools generate hashed filenames.

## Key Concepts Learned

- **S3 website endpoint is different from S3 REST API endpoint** — the website endpoint supports `index.html` redirects and custom error pages. Use it when S3 website hosting is configured.
- **TTL values directly control content freshness** — `default_ttl` is how long CloudFront caches when the origin doesn't specify. Keep it reasonable (1 hour) for frequently updated content.
- **`min_ttl = 0` lets the origin control caching** — this allows your application to send `Cache-Control: no-cache` for specific responses, and CloudFront will respect it.
- **Cache invalidation is the emergency fix** — when you need content updated immediately, invalidate the cache. But fix the TTLs so you don't need to invalidate every time.
- **CloudFront caches at edge locations** — there are 400+ CloudFront edge locations worldwide. Each independently caches content. An invalidation must propagate to all of them (takes a few minutes).

## Common Mistakes

- **Setting extremely long TTLs for frequently updated content** — a 7-day default TTL means content updates are invisible for a week. Only use long TTLs for truly static assets (fonts, versioned JS/CSS).
- **Confusing S3 endpoints** — `bucket_regional_domain_name` (REST API) vs `website_endpoint` (website hosting). Using the wrong one breaks website features like `index.html` as the default document.
- **Not using `custom_origin_config` for website endpoints** — when using the S3 website endpoint, you must configure it as a custom origin with `http-only` protocol. The S3 website endpoint only supports HTTP.
- **Forgetting to invalidate after fixing TTLs** — fixing the TTL in Terraform only affects future caching. Currently cached content retains its original TTL. You need to invalidate to force a refresh.
- **Over-invalidating** — invalidating `/*` on every deployment is wasteful if you only changed one file. In production, invalidate specific paths or use versioned filenames to avoid needing invalidation at all.

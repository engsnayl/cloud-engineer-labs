# Hints — Cloud Lab 009: CloudFront Caching

## Hint 1 — TTL values
The default_ttl is 604800 (7 days!) — that means CloudFront won't check the origin for a week. For frequently updated content, use much shorter TTLs.

## Hint 2 — Reasonable TTLs
min_ttl: 0, default_ttl: 3600 (1 hour), max_ttl: 86400 (1 day) is reasonable for most websites.

## Hint 3 — Cache invalidation
Even with fixed TTLs, you might need to invalidate current cache. Use `aws cloudfront create-invalidation --distribution-id <id> --paths "/*"` to clear the cache.

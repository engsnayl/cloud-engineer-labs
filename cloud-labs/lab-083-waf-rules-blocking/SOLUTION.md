# Solution Walkthrough — WAF Blocking Legitimate Traffic

## The Problem

AWS WAF rules are too aggressive, blocking legitimate users. There are **four bugs**:

1. **Office IPs mixed with malicious IPs in a block list** — internal/office CIDR ranges (10.0.0.0/8, 192.168.1.0/24) are in the same IP set as malicious IPs, and the IP set is used in a block rule. All office traffic is blocked.
2. **Rate limit too low** — 100 requests per 5 minutes is far too aggressive. A single page load with images, CSS, JS, and API calls easily generates 20-50 requests. Normal browsing would hit this limit in 2-3 page loads.
3. **Rule priority order wrong** — the rate-limit block rule has priority 1 (evaluated first), meaning it blocks users before any allow rules can whitelist them. Allow rules should have higher priority (lower number) than block rules.
4. **Geo-restriction blocks your own countries** — the geo_match_statement blocks GB, IE, and US, which are where the actual users are. It should block countries you don't serve, or be inverted to use a NOT statement.

## Step-by-Step Solution

### Step 1: Separate IP sets — malicious vs trusted

Create two IP sets and use them in separate rules:

```hcl
resource "aws_wafv2_ip_set" "blocked_ips" {
  name               = "blocked-ip-set"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses = [
    "203.0.113.50/32",
    "198.51.100.100/32",
  ]
}

resource "aws_wafv2_ip_set" "trusted_ips" {
  name               = "trusted-ip-set"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses = [
    "10.0.0.0/8",
    "192.168.1.0/24",
  ]
}
```

### Step 2: Fix rate limit to a reasonable threshold

```hcl
limit = 2000  # Was: 100 — allows normal browsing patterns
```

AWS WAF rate-based rules count requests per 5-minute window. 2000 per 5 minutes (roughly 6-7 per second) is reasonable for web applications.

### Step 3: Fix rule priorities

Allow trusted IPs first (priority 1), then block malicious IPs (priority 2), then rate limit (priority 3), then geo-block (priority 4).

### Step 4: Fix geo restriction

Either block countries you DON'T serve, or use a NOT statement to only allow specific countries:

```hcl
statement {
  not_statement {
    statement {
      geo_match_statement {
        country_codes = ["GB", "IE", "US"]
      }
    }
  }
}
```

This blocks everything EXCEPT GB, IE, and US traffic.

## Key Concepts Learned

- **WAF rule priority determines evaluation order** — lower numbers are evaluated first. Structure: allow trusted traffic → block known bad → rate limit → geo-block → default action.
- **Rate limits must account for modern web applications** — a single page can generate 20-50+ HTTP requests. Set limits based on actual traffic patterns, not guesses.
- **Separate allow and block IP sets** — never mix trusted and malicious IPs. Use separate rules with appropriate actions.
- **Geo-blocking logic can be inverted** — blocking specific countries vs allowing specific countries. Use `not_statement` to invert the logic.
- **Always enable WAF logging and sampled requests** — without visibility into what's being blocked, you can't diagnose issues. Enable CloudWatch metrics and sampled requests on every rule.

## Common Mistakes

- **Testing WAF rules in production** — always deploy WAF rules in COUNT mode first to observe what would be blocked before switching to BLOCK.
- **Overly aggressive rate limits** — start high and tighten based on observed traffic patterns. Too low causes false positives.
- **Forgetting CDN impact** — if you're behind CloudFront, all traffic appears to come from CloudFront IPs. Use the `forwarded-ip` header config for accurate IP-based rules.
- **Not considering API traffic** — APIs can legitimately generate high request volumes. Consider separate rate limits for API endpoints.

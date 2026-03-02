# Solution Walkthrough — Route 53 DNS Failover Not Working

## The Problem

Route 53 should automatically switch DNS traffic from the primary region to the backup region when the primary is unhealthy, but failover isn't happening. Customers experience a full outage because DNS keeps pointing to the dead primary. There are **four bugs**:

1. **Health check on wrong port** — the health check monitors port 8080, but the application listens on port 80. The health check always fails (because nothing responds on 8080), but since it's not properly linked to the failover record, it doesn't trigger failover.
2. **Primary record missing failover routing policy** — the primary DNS record doesn't have `failover_routing_policy { type = "PRIMARY" }`, `set_identifier`, or `health_check_id`. Without these, Route 53 treats it as a simple record, not a failover record.
3. **Very long TTL on secondary record** — `ttl = 3600` (1 hour) means DNS resolvers cache the record for an hour. Even after failover triggers, clients keep using the old (failed) IP for up to an hour.
4. **Secondary record missing failover routing policy** — like the primary, the secondary record doesn't have `failover_routing_policy { type = "SECONDARY" }` or `set_identifier`.

## Thought Process

When Route 53 failover doesn't work, an experienced cloud engineer checks:

1. **Health check configuration** — is it checking the right port, path, and protocol? A health check on the wrong port always reports unhealthy (or always healthy if something else is on that port).
2. **Failover routing policy** — both the PRIMARY and SECONDARY records need `failover_routing_policy` blocks. Without them, Route 53 doesn't know the records are part of a failover pair.
3. **Health check association** — the PRIMARY record must have `health_check_id` linking it to the health check. The SECONDARY typically doesn't need one.
4. **TTL values** — short TTLs (60 seconds) ensure fast failover. Long TTLs mean clients keep using stale DNS after failover.

## Step-by-Step Solution

### Step 1: Fix Bug 1 — Health check port

```hcl
# BROKEN
resource "aws_route53_health_check" "primary" {
  fqdn              = "primary.example-internal.com"
  port              = 8080     # Wrong port!
  type              = "HTTP"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30
}

# FIXED
resource "aws_route53_health_check" "primary" {
  fqdn              = "primary.example-internal.com"
  port              = 80       # Correct — app listens on 80
  type              = "HTTP"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30
}
```

**Why this matters:** The health check sends HTTP requests to the specified port. If the application listens on port 80 but the health check hits port 8080, nothing responds, and the health check always reports unhealthy. This can cause premature failover (if it were properly linked) or mask real issues.

### Step 2: Fix Bugs 2 & 4 — Add failover routing policies to both records

```hcl
# FIXED PRIMARY record
resource "aws_route53_record" "primary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "app.example-internal.com"
  type    = "A"
  ttl     = 60

  set_identifier = "primary"

  failover_routing_policy {
    type = "PRIMARY"
  }

  health_check_id = aws_route53_health_check.primary.id
  records         = ["10.0.1.100"]
}

# FIXED SECONDARY record
resource "aws_route53_record" "secondary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "app.example-internal.com"
  type    = "A"
  ttl     = 60

  set_identifier = "secondary"

  failover_routing_policy {
    type = "SECONDARY"
  }

  records = ["10.1.1.100"]
}
```

**Why this matters:** Route 53 failover requires specific configuration on both records:
- **`failover_routing_policy { type = "PRIMARY" }`** — marks this as the preferred record. Route 53 returns this IP when the health check is healthy.
- **`failover_routing_policy { type = "SECONDARY" }`** — marks this as the backup. Route 53 only returns this IP when the primary's health check is unhealthy.
- **`set_identifier`** — required for any routing policy with multiple records of the same name and type. It uniquely identifies each record in the failover pair.
- **`health_check_id`** — links the primary record to its health check. When the health check fails, Route 53 stops returning the primary IP.

### Step 3: Fix Bug 3 — Reduce TTL

Both records now use `ttl = 60` (60 seconds) instead of 300 or 3600.

**Why this matters:** TTL determines how long DNS resolvers cache the record. With a 3600-second (1 hour) TTL, even after Route 53 fails over, clients continue using the cached primary IP for up to an hour. With a 60-second TTL, clients re-query DNS within a minute and get the secondary IP. Lower TTL = faster failover response.

### Step 4: Validate

```bash
terraform validate
terraform plan
```

## Docker Lab vs Real Life

- **Health check types:** In production, you'd use HTTPS health checks (not HTTP) and check a dedicated `/health` endpoint that verifies database connectivity, dependencies, and application health — not just "is the process running."
- **Cross-region failover:** Real failover often involves Route 53 alias records pointing to regional load balancers (ALBs) in different regions, not hardcoded IPs. This provides better scalability and allows multiple instances per region.
- **Failover testing:** Production environments should regularly test failover by intentionally failing the health check. AWS Fault Injection Simulator (FIS) can automate this.
- **Active-active vs active-passive:** This lab uses active-passive (primary/secondary) failover. Production may use active-active with weighted or latency-based routing, where both regions serve traffic simultaneously.
- **Health check costs:** Route 53 health checks have a cost per check. Basic checks are ~$0.50/month, HTTPS checks with string matching are ~$2/month each.

## Key Concepts Learned

- **Failover records need `failover_routing_policy`, `set_identifier`, and `health_check_id`** — without all three on the primary, Route 53 can't implement failover
- **Health checks must match the application** — wrong port, wrong path, or wrong protocol means the health check doesn't reflect actual application health
- **Low TTLs are essential for fast failover** — a 60-second TTL means clients update within 1 minute of failover. A 3600-second TTL means up to 1 hour of continued outage
- **Both PRIMARY and SECONDARY records are required** — they must have the same name and type, differentiated by `set_identifier` and `failover_routing_policy`
- **The secondary record doesn't need a health check** — it's the last resort. If the primary is unhealthy, traffic goes to the secondary regardless.

## Common Mistakes

- **Health check on wrong port** — this is the exact mistake in this lab. Always verify the health check port matches the application's listening port.
- **Missing `set_identifier`** — Route 53 requires a unique `set_identifier` for each record when using any routing policy (failover, weighted, latency, etc.).
- **High TTLs on failover records** — the TTL directly affects failover speed. Production failover records should use 60 seconds or less.
- **Not linking health check to the primary record** — the `health_check_id` must be on the PRIMARY record. Without it, Route 53 never knows the primary is down and never fails over.
- **Testing health checks** — always verify health checks show "Healthy" in the Route 53 console before relying on them for failover. A misconfigured health check that's always unhealthy causes constant failover.

# Hints — Cloud Lab 017: Route 53 Failover

## Hint 1 — Health check port
The health check is on port 8080 but the application listens on 80. Fix the port.

## Hint 2 — Failover routing policy
Both records need `failover_routing_policy` blocks. Primary: `type = "PRIMARY"`, Secondary: `type = "SECONDARY"`. Both need `set_identifier`.

## Hint 3 — TTL for failover
3600 seconds (1 hour) TTL means DNS caches won't update for an hour after failover. Use 60 seconds for failover records.

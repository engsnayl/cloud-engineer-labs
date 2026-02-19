# Hints — Lab 016: Load Balancer Routing

## Hint 1 — Check the upstream block
Look at `/etc/nginx/sites-enabled/loadbalancer`. How many backends are in the upstream block?

## Hint 2 — Uncomment and add missing backends
The upstream block should have all three backends: 8001, 8002, 8003. Uncomment or add the missing ones.

## Hint 3 — Reload nginx
After fixing the config: `nginx -t` to test, then `nginx -s reload` to apply.

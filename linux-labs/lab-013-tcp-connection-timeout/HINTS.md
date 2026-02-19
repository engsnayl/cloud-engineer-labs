# Hints — Lab 013: TCP Connection Timeout

## Hint 1 — Check what's listening
Use `ss -tlnp` to see what ports have services listening. Is Redis on the expected port?

## Hint 2 — Check name resolution
`getent hosts redis-server` shows what IP the hostname resolves to. Check `/etc/hosts` for incorrect entries.

## Hint 3 — Fix both issues
Redis needs to be on port 6379 (restart it: `redis-cli -p 6380 shutdown` then `redis-server --port 6379 --daemonize yes`). And `/etc/hosts` needs redis-server pointing to 127.0.0.1.

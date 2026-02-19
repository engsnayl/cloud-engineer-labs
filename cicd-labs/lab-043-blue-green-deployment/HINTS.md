# Hints — CI/CD Lab 043: Blue/Green Deployment

## Hint 1 — Nginx config switching
Create two nginx configs: one pointing to blue, one to green. The switch script copies the right one and reloads nginx.

## Hint 2 — Script flow
1. Deploy new version to inactive env. 2. Health check the inactive env directly (curl app-green:8080/health). 3. If healthy, update nginx config and reload. 4. If unhealthy, don't switch.

## Hint 3 — Nginx reload is instant
`nginx -s reload` gracefully switches with zero dropped connections.

# Hints — CI/CD Lab 042: Deployment Rollback

## Hint 1 — Version your deploys
Accept a version parameter: `VERSION=$1`. Tag images with git SHA or semver, never deploy 'latest' to production.

## Hint 2 — Health check pattern
After starting the new container, loop and check: `curl -sf http://localhost/health`. If it fails after N retries, trigger rollback.

## Hint 3 — Save the previous version
Before deploying, save: `PREVIOUS=$(docker inspect app --format '{{.Config.Image}}')`. On failure, redeploy with $PREVIOUS.

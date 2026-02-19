# Hints — Lab 031: Resource Quota Exceeded

## Hint 1 — Check current quota usage
`kubectl describe resourcequota production-quota -n production` shows limits and current usage.

## Hint 2 — Options to fix
You can: reduce the legacy-service resource requests (they're overprovisioned), reduce legacy-service replicas, or increase the quota. The best practice is right-sizing the existing services.

## Hint 3 — Right-size the legacy service
Reduce legacy-service requests to cpu: 200m, memory: 128Mi. Then try deploying new-service again.

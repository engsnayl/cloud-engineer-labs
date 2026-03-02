# Hints — ArgoCD App Out of Sync

## Hint 1
Check the source path in the ArgoCD Application — does it point to the right environment directory?

## Hint 2
For true GitOps, auto-sync needs both `prune` (remove orphaned resources) and `selfHeal` (revert manual cluster changes) enabled.

## Hint 3
Using the `latest` image tag breaks GitOps because it's mutable — the same tag can point to different images. Use immutable tags (commit SHAs or semantic versions).

## Hint 4
A memory limit of 10Mi means the container will be OOM-killed immediately on startup. Most web apps need at least 128Mi-256Mi.

## Hint 5
Liveness and readiness probes serve different purposes but often hit the same health endpoint. Make sure the liveness probe path actually exists.

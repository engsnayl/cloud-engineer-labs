# Solution Walkthrough — ArgoCD App Out of Sync

## The Problem

An ArgoCD-managed application is stuck OutOfSync with multiple configuration issues. There are **six bugs**:

1. **Wrong Git path** — ArgoCD is reading from `staging` path instead of `production`.
2. **Prune disabled** — orphaned resources in the cluster aren't cleaned up.
3. **Self-heal disabled** — manual changes in the cluster aren't reverted to match Git.
4. **Latest image tag** — mutable tag causes sync detection issues and unpredictable deployments.
5. **Memory limit too low** — 10Mi causes immediate OOM kills, making pods Degraded.
6. **Wrong liveness probe path** — `/ready` doesn't exist, causing constant restarts.

## Step-by-Step Solution

### Step 1: Fix ArgoCD app path
```yaml
path: apps/web-app/production  # Was: staging
```

### Step 2: Enable prune and selfHeal
```yaml
automated:
  prune: true      # Was: false
  selfHeal: true   # Was: false
```

### Step 3: Use immutable image tag
```yaml
image: company/web-app:v1.2.3  # Was: latest
```

### Step 4: Fix memory limit
```yaml
memory: 256Mi  # Was: 10Mi
```

### Step 5: Fix liveness probe path
```yaml
path: /healthz  # Was: /ready
```

## Key Concepts Learned

- **GitOps = Git is the single source of truth** — the cluster state should always match what's in Git. ArgoCD enforces this.
- **Prune removes drift** — without prune, deleted resources in Git still exist in the cluster.
- **SelfHeal reverts manual changes** — without selfHeal, `kubectl edit` changes persist instead of being reverted.
- **Immutable image tags are essential for GitOps** — `latest` is mutable and breaks sync detection. Use commit SHAs or semver tags.
- **Resource limits affect health status** — ArgoCD reports Degraded when pods are CrashLoopBackOff due to OOM kills.
- **Probe paths must exist** — a liveness probe hitting a non-existent path causes constant restarts, which ArgoCD reports as unhealthy.

## Common Mistakes

- **Pointing to wrong environment path** — easy to accidentally reference staging instead of production. Use separate ArgoCD Applications per environment.
- **Leaving prune disabled "for safety"** — this defeats the purpose of GitOps. Use `argocd.argoproj.io/sync-options: Prune=false` annotation on specific resources if needed.
- **Using latest in CI/CD pipelines** — always tag images with the Git commit SHA or a semantic version. Update the manifest with the new tag as part of the pipeline.
- **Mixing liveness and readiness semantics** — readiness determines if a pod receives traffic. Liveness determines if a pod should be restarted. They can share a path but serve different purposes.

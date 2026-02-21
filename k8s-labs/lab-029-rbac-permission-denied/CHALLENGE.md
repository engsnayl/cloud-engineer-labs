Title: Access Denied — RBAC Permissions Broken
Difficulty: ⭐⭐⭐ (Advanced)
Time: 15-20 minutes
Category: Kubernetes / Security
Skills: RBAC, Roles, RoleBindings, ServiceAccounts, kubectl auth can-i

## Scenario

The monitoring service account can't read pod metrics. It needs to list and get pods in the monitoring namespace but RBAC permissions are misconfigured.

> **INCIDENT-K8S-005**: Monitoring system can't scrape pod metrics. ServiceAccount 'monitoring-sa' getting 403 Forbidden when listing pods. RBAC was recently changed during a security audit.

Fix the RBAC configuration so the monitoring service account has the correct permissions.

## How to Use This Lab

1. Apply the broken manifests: `kubectl apply -f manifests/broken/`
2. Observe the failures: `kubectl get pods`, `kubectl describe pod <name>`
3. Diagnose and fix — edit the files or use kubectl directly
4. Run `validate.sh` when you think you've fixed it

**Requires:** A running Kubernetes cluster (kind, minikube, or KodeKloud Playground)

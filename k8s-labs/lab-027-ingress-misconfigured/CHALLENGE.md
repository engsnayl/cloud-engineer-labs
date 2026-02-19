Title: External Traffic Blocked — Ingress Routing Issues
Difficulty: ⭐⭐⭐ (Advanced)
Time: 15-20 minutes
Category: Kubernetes / Ingress
Skills: kubectl get ingress, ingress rules, path matching, TLS

## Scenario

External traffic can't reach the application through the Ingress. The Ingress resource is deployed but routing rules aren't working correctly.

> **INCIDENT-K8S-003**: Customer-facing app unreachable via domain. Ingress resource exists but traffic returns 404. Backend services are healthy. Ingress controller is running.

Fix the Ingress configuration to correctly route external traffic.

## How to Use This Lab

1. Apply the broken manifests: `kubectl apply -f manifests/broken/`
2. Observe the failures: `kubectl get pods`, `kubectl describe pod <name>`
3. Diagnose and fix — edit the files or use kubectl directly
4. Run `validate.sh` when you think you've fixed it

**Requires:** A running Kubernetes cluster (kind, minikube, or KodeKloud Playground)

## Validation Criteria

See validate.sh for specific checks.

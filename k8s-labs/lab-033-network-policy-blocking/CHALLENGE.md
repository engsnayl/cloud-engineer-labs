Title: Traffic Blocked — Network Policy Too Restrictive
Difficulty: ⭐⭐⭐ (Advanced)
Time: 15-20 minutes
Category: Kubernetes / Security
Skills: NetworkPolicy, pod selectors, ingress/egress rules, namespace labels

## Scenario

The API pods can't communicate with the database pods after a network policy was applied. The policy was meant to restrict external access but it's blocking internal traffic too.

> **INCIDENT-K8S-009**: API pods can't reach database pods. NetworkPolicy was applied as part of security hardening. Internal service-to-service communication is blocked. API returning 500 errors.

Fix the NetworkPolicy to allow internal communication while maintaining external restrictions.

## How to Use This Lab

1. Apply the broken manifests: `kubectl apply -f manifests/broken/`
2. Observe the failures: `kubectl get pods`, `kubectl describe pod <name>`
3. Diagnose and fix — edit the files or use kubectl directly
4. Run `validate.sh` when you think you've fixed it

**Requires:** A running Kubernetes cluster (kind, minikube, or KodeKloud Playground)

## Validation Criteria

See validate.sh for specific checks.

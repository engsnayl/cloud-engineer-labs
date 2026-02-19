Title: Auto Scaling Broken — HPA Not Working
Difficulty: ⭐⭐⭐ (Advanced)
Time: 15-20 minutes
Category: Kubernetes / Scaling
Skills: HPA, metrics-server, resource requests, kubectl top

## Scenario

The Horizontal Pod Autoscaler is supposed to scale the web tier based on CPU usage, but it shows "unknown" for current metrics and won't scale.

> **INCIDENT-K8S-008**: HPA for web-tier shows <unknown>/80% CPU target. Pods are at high CPU but HPA won't scale. Metrics appear unavailable. Application response times degrading.

Fix the HPA configuration so auto-scaling works correctly.

## How to Use This Lab

1. Apply the broken manifests: `kubectl apply -f manifests/broken/`
2. Observe the failures: `kubectl get pods`, `kubectl describe pod <name>`
3. Diagnose and fix — edit the files or use kubectl directly
4. Run `validate.sh` when you think you've fixed it

**Requires:** A running Kubernetes cluster (kind, minikube, or KodeKloud Playground)

## Validation Criteria

See validate.sh for specific checks.

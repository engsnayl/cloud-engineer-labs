Title: Pod CrashLoopBackOff — Kubernetes Debugging
Difficulty: ⭐⭐ (Intermediate)
Time: 10-15 minutes
Category: Kubernetes / Pods
Skills: kubectl describe, kubectl logs, pod spec, container args

## Scenario

The payment service pod is in CrashLoopBackOff. It keeps restarting but immediately crashes each time. The deployment was applied 30 minutes ago and hasn't been healthy since.

> **INCIDENT-K8S-001**: payment-service pod in CrashLoopBackOff. 47 restarts. Deployment was applied by the dev team's CI pipeline. They say the image is correct.

Diagnose the crash loop and fix the pod specification.

## How to Use This Lab

1. Apply the broken manifests: `kubectl apply -f manifests/broken/`
2. Observe the failures: `kubectl get pods`, `kubectl describe pod <name>`
3. Diagnose and fix — edit the files or use kubectl directly
4. Run `validate.sh` when you think you've fixed it

**Requires:** A running Kubernetes cluster (kind, minikube, or KodeKloud Playground)

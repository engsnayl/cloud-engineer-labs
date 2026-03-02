Title: Service Unreachable — Kubernetes Service Misconfigured
Difficulty: ⭐⭐ (Intermediate)
Time: 10-15 minutes
Category: Kubernetes / Networking
Skills: kubectl get svc, endpoints, label selectors, port mapping

## Scenario

The frontend pods can't reach the backend service. The Service resource exists but has no endpoints — no pods are being selected.

> **INCIDENT-K8S-002**: Frontend getting "connection refused" when calling backend-api service. Service exists but `kubectl get endpoints backend-api` shows no endpoints. Backend pods are running.

Fix the Service configuration so traffic routes to the backend pods.

## Objectives

1. Fix the `backend-api` Service so it has healthy endpoints (at least 2 matching pods)
2. The service `targetPort` must be set to `80`
3. `curl http://backend-api` from within the cluster must return a response

## How to Use This Lab

1. Apply the broken manifests: `kubectl apply -f manifests/broken/`
2. Observe the failures: `kubectl get pods`, `kubectl describe pod <name>`
3. Diagnose and fix — edit the files or use kubectl directly
4. Run `validate.sh` when you think you've fixed it

**Requires:** A running Kubernetes cluster (kind, minikube, or KodeKloud Playground)

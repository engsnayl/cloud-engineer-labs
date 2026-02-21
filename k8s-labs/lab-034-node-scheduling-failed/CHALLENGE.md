Title: Pod Unschedulable — Node Affinity and Taints
Difficulty: ⭐⭐⭐ (Advanced)
Time: 15-20 minutes
Category: Kubernetes / Scheduling
Skills: nodeSelector, taints, tolerations, affinity, kubectl describe

## Scenario

New pods are stuck in Pending state. They have node affinity rules that don't match any available nodes, and the only suitable node has a taint the pods don't tolerate.

> **INCIDENT-K8S-010**: Critical service pods stuck in Pending. Scheduler can't find suitable nodes. Node affinity and taints preventing scheduling. 3 nodes available but none match pod requirements.

Fix the scheduling constraints so pods can be placed on available nodes.

## How to Use This Lab

1. Apply the broken manifests: `kubectl apply -f manifests/broken/`
2. Observe the failures: `kubectl get pods`, `kubectl describe pod <name>`
3. Diagnose and fix — edit the files or use kubectl directly
4. Run `validate.sh` when you think you've fixed it

**Requires:** A running Kubernetes cluster (kind, minikube, or KodeKloud Playground)

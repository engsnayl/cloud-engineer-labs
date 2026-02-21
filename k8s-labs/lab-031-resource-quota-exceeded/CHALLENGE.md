Title: Can't Deploy — Resource Quota Exceeded
Difficulty: ⭐⭐ (Intermediate)
Time: 10-15 minutes
Category: Kubernetes / Resources
Skills: ResourceQuota, resource requests/limits, namespace management

## Scenario

The team can't deploy new pods — every deployment attempt is rejected with "exceeded quota". The namespace has a ResourceQuota set but current usage is near the limits.

> **INCIDENT-K8S-007**: All deployments to the 'production' namespace failing with quota exceeded. Existing services are running but can't scale or deploy updates. Need to either optimise resource usage or adjust quotas.

Resolve the quota issue so deployments can proceed.

## Objectives

1. Get the `new-service` deployment running in the `production` namespace with at least 1 ready replica
2. The existing `legacy-service` must remain running — do not delete it to free up quota

## How to Use This Lab

1. Apply the broken manifests: `kubectl apply -f manifests/broken/`
2. Observe the failures: `kubectl get pods`, `kubectl describe pod <name>`
3. Diagnose and fix — edit the files or use kubectl directly
4. Run `validate.sh` when you think you've fixed it

**Requires:** A running Kubernetes cluster (kind, minikube, or KodeKloud Playground)

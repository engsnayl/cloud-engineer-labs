Title: Storage Not Available — PVC Stuck Pending
Difficulty: ⭐⭐⭐ (Advanced)
Time: 15-20 minutes
Category: Kubernetes / Storage
Skills: PVC, PV, StorageClass, kubectl describe, volume binding

## Scenario

The database pod can't start because its PersistentVolumeClaim is stuck in Pending state. The PV exists but isn't binding to the PVC.

> **INCIDENT-K8S-004**: Database pod stuck in Pending. PVC not bound. PV was manually provisioned but the PVC can't find it. Database has been down for 2 hours.

Fix the PVC/PV configuration so the database can start.

## How to Use This Lab

1. Apply the broken manifests: `kubectl apply -f manifests/broken/`
2. Observe the failures: `kubectl get pods`, `kubectl describe pod <name>`
3. Diagnose and fix — edit the files or use kubectl directly
4. Run `validate.sh` when you think you've fixed it

**Requires:** A running Kubernetes cluster (kind, minikube, or KodeKloud Playground)

Title: Missing Config — ConfigMap and Secret Issues
Difficulty: ⭐⭐ (Intermediate)
Time: 10-15 minutes
Category: Kubernetes / Configuration
Skills: ConfigMaps, Secrets, envFrom, volumeMounts, base64

## Scenario

The application pod is crashing because it can't find its configuration. The ConfigMap and Secret it references either don't exist or have wrong keys.

> **INCIDENT-K8S-006**: App pod failing with "configmap not found" and "secret key not found". Application expects specific config keys for database connection. DevOps team forgot to create the config resources.

Create the missing ConfigMap and Secret with the correct data.

## How to Use This Lab

1. Apply the broken manifests: `kubectl apply -f manifests/broken/`
2. Observe the failures: `kubectl get pods`, `kubectl describe pod <name>`
3. Diagnose and fix — edit the files or use kubectl directly
4. Run `validate.sh` when you think you've fixed it

**Requires:** A running Kubernetes cluster (kind, minikube, or KodeKloud Playground)

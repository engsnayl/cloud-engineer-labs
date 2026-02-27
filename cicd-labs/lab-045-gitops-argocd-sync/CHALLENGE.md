Title: ArgoCD App Out of Sync — GitOps Debugging
Difficulty: ⭐⭐⭐ (Advanced)
Time: 20-25 minutes
Category: CI/CD / GitOps
Skills: ArgoCD, GitOps principles, Kubernetes manifests, sync policies, health checks

## Scenario

Your team uses ArgoCD for GitOps-based deployments. An application is stuck in "OutOfSync" and "Degraded" status. The desired state in Git doesn't match what's running in the cluster, and auto-sync isn't fixing it.

> **INCIDENT-CICD-002**: Production app showing "OutOfSync" in ArgoCD for 6 hours. Auto-sync is configured but not triggering. Manual sync attempts fail with errors. Deployment is blocked.

## Objectives

1. Fix the ArgoCD Application manifest so it references the correct Git path
2. Fix the sync policy configuration to enable auto-sync properly
3. Fix the Kubernetes deployment manifest (image tag, resource limits)
4. Fix the health check configuration so ArgoCD correctly assesses app health
5. All files must be valid YAML

## How to Use This Lab

1. Review the files — `argocd-app.yaml`, `deployment.yaml`, `service.yaml`
2. Identify the issues preventing sync
3. Fix all YAML files
4. Run `validate.sh` to check your fixes

**No containers or cloud accounts needed — analyse and fix the files directly.**

## Validation

Run `./validate.sh` to verify all files are correct.

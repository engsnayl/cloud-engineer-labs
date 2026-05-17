# Kubernetes manifests — Module 3

K3s on Raspberry Pi 5. See `SOLUTION-MODULE-03-KUBERNETES.md` at the
project root for the walkthrough.

## Apply order

Files are numerically prefixed and apply cleanly with:

    kubectl apply -f k8s/

## Cleanup

    kubectl delete namespace multi-tier

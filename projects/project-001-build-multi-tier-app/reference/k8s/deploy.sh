#!/bin/bash
# =============================================================================
# deploy.sh — Deploy the Multi-Tier Application to Kubernetes (k3s)
# =============================================================================
# This script applies all Kubernetes manifests in the correct order.
#
# WHY ORDER MATTERS:
#   Kubernetes resources have dependencies. If you apply them in the wrong
#   order, pods will crash because their dependencies don't exist yet:
#
#   1. Namespace FIRST — everything else goes in this namespace
#   2. Secrets & ConfigMaps SECOND — pods reference these at startup;
#      if they don't exist, pods fail with "CreateContainerConfigError"
#   3. Database (StatefulSet + Service) THIRD — the backend needs the DB
#      to be running before it can pass health checks
#   4. Backend (Deployment + Service) FOURTH — the frontend proxies to
#      the backend, so it should be running first
#   5. Frontend (Deployment + Service) FIFTH — depends on backend being
#      reachable (though nginx handles retries gracefully)
#   6. Ingress SIXTH — routes external traffic to services (which must exist)
#   7. NetworkPolicy LAST — it's a security layer, not a dependency;
#      applying it last ensures everything works before we restrict traffic
#
# Usage:
#   chmod +x deploy.sh    # Make it executable (only needed once)
#   ./deploy.sh           # Run the deployment
# =============================================================================

# ---------------------------------------------------------------------------
# BASH STRICT MODE
# ---------------------------------------------------------------------------
# set -e: Exit immediately if any command fails (non-zero exit code).
#   Without this, the script would continue even if kubectl fails, leading
#   to confusing errors downstream.
# set -o pipefail: If a piped command fails, the whole pipe fails.
#   Without this, "failing-command | grep something" would succeed because
#   grep succeeded, even though the first command failed.
set -e
set -o pipefail

# ---------------------------------------------------------------------------
# CONFIGURATION
# ---------------------------------------------------------------------------
# Store commonly used values in variables so they're easy to change.
NAMESPACE="multi-tier-app"

# Get the directory where this script lives, regardless of where it's called from.
# This ensures kubectl can find the YAML files even if you run the script
# from a different directory (e.g., "bash k8s/deploy.sh" from the project root).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# HELPER FUNCTIONS
# ---------------------------------------------------------------------------

# Print a formatted status message with a divider line.
# This makes the script output easy to follow.
print_status() {
    echo ""
    echo "================================================================="
    echo "  $1"
    echo "================================================================="
}

# Check if kubectl is available and can connect to a cluster.
check_prerequisites() {
    print_status "Checking prerequisites"

    # "command -v" checks if a command exists (like "which" but more portable).
    if ! command -v kubectl &> /dev/null; then
        echo "ERROR: kubectl is not installed or not in PATH"
        echo "On k3s, try: export PATH=\$PATH:/usr/local/bin"
        exit 1
    fi

    # Try to connect to the cluster. "kubectl cluster-info" shows the
    # cluster's API server URL. If this fails, kubectl can't reach the cluster.
    if ! kubectl cluster-info &> /dev/null; then
        echo "ERROR: Cannot connect to Kubernetes cluster"
        echo "Make sure k3s is running: sudo systemctl status k3s"
        exit 1
    fi

    echo "kubectl is available and cluster is reachable"
}

# ---------------------------------------------------------------------------
# STEP 1: Namespace
# ---------------------------------------------------------------------------
# The namespace must exist before we can create resources inside it.
deploy_namespace() {
    print_status "Step 1/7: Creating namespace"
    kubectl apply -f "${SCRIPT_DIR}/namespace.yaml"
    echo "Namespace '${NAMESPACE}' is ready"
}

# ---------------------------------------------------------------------------
# STEP 2: Secrets and ConfigMaps
# ---------------------------------------------------------------------------
# These must exist BEFORE pods start, because pods reference them in their
# env/envFrom/volumeMounts sections. If a referenced Secret/ConfigMap doesn't
# exist, the pod stays in "CreateContainerConfigError" status forever.
deploy_configs() {
    print_status "Step 2/7: Deploying Secrets and ConfigMaps"
    kubectl apply -f "${SCRIPT_DIR}/database-secret.yaml"
    kubectl apply -f "${SCRIPT_DIR}/database-init-configmap.yaml"
    kubectl apply -f "${SCRIPT_DIR}/backend-configmap.yaml"
    echo "Secrets and ConfigMaps created"
}

# ---------------------------------------------------------------------------
# STEP 3: Database (StatefulSet + Service)
# ---------------------------------------------------------------------------
# The database must be running and healthy before the backend starts,
# because the backend's readiness probe checks the DB connection.
deploy_database() {
    print_status "Step 3/7: Deploying PostgreSQL database"

    # Apply the headless Service first — the StatefulSet requires it.
    # (StatefulSet's serviceName field references this Service)
    kubectl apply -f "${SCRIPT_DIR}/database-service.yaml"
    kubectl apply -f "${SCRIPT_DIR}/database-statefulset.yaml"

    echo "Waiting for PostgreSQL to be ready..."

    # kubectl rollout status waits until all pods in the StatefulSet are
    # Running and Ready. --timeout=120s means give up after 2 minutes.
    # On a Pi, first-time pulls of the postgres:15 image can be slow.
    kubectl rollout status statefulset/postgres \
        -n "${NAMESPACE}" \
        --timeout=120s

    echo "PostgreSQL is ready!"
}

# ---------------------------------------------------------------------------
# STEP 4: Backend (Deployment + Service)
# ---------------------------------------------------------------------------
deploy_backend() {
    print_status "Step 4/7: Deploying backend API"
    kubectl apply -f "${SCRIPT_DIR}/backend-service.yaml"
    kubectl apply -f "${SCRIPT_DIR}/backend-deployment.yaml"

    echo "Waiting for backend pods to be ready..."
    kubectl rollout status deployment/backend \
        -n "${NAMESPACE}" \
        --timeout=120s

    echo "Backend is ready!"
}

# ---------------------------------------------------------------------------
# STEP 5: Frontend (Deployment + Service)
# ---------------------------------------------------------------------------
deploy_frontend() {
    print_status "Step 5/7: Deploying frontend"
    kubectl apply -f "${SCRIPT_DIR}/frontend-service.yaml"
    kubectl apply -f "${SCRIPT_DIR}/frontend-deployment.yaml"

    echo "Waiting for frontend pods to be ready..."
    kubectl rollout status deployment/frontend \
        -n "${NAMESPACE}" \
        --timeout=120s

    echo "Frontend is ready!"
}

# ---------------------------------------------------------------------------
# STEP 6: Ingress
# ---------------------------------------------------------------------------
# Applied after services exist, because the Ingress references them.
# If the backend/frontend services don't exist, the Ingress Controller
# logs warnings (though it won't crash — it retries).
deploy_ingress() {
    print_status "Step 6/7: Deploying Ingress"
    kubectl apply -f "${SCRIPT_DIR}/ingress.yaml"
    echo "Ingress created — external access configured"
}

# ---------------------------------------------------------------------------
# STEP 7: Network Policy
# ---------------------------------------------------------------------------
# Applied last because it restricts traffic. If applied too early and
# something goes wrong, it could block debugging traffic.
# Remember: This has no effect on k3s with Flannel (needs Calico/Cilium).
deploy_network_policy() {
    print_status "Step 7/7: Deploying NetworkPolicy"
    kubectl apply -f "${SCRIPT_DIR}/network-policy.yaml"
    echo "NetworkPolicy applied (NOTE: requires Calico/Cilium to enforce)"
}

# ---------------------------------------------------------------------------
# SUMMARY — Show the final state of all resources
# ---------------------------------------------------------------------------
show_summary() {
    print_status "Deployment Complete!"

    echo ""
    echo "--- All resources in namespace '${NAMESPACE}' ---"
    echo ""

    # kubectl get all shows pods, services, deployments, statefulsets, replicasets
    kubectl get all -n "${NAMESPACE}"

    echo ""
    echo "--- Ingress ---"
    kubectl get ingress -n "${NAMESPACE}"

    echo ""
    echo "--- Persistent Volume Claims ---"
    kubectl get pvc -n "${NAMESPACE}"

    echo ""
    echo "================================================================="
    echo "  ACCESS YOUR APPLICATION:"
    echo "  Via Ingress:     http://<your-pi-ip>/"
    echo "  Direct backend:  kubectl port-forward svc/backend 5000:5000 -n ${NAMESPACE}"
    echo "  Direct frontend: kubectl port-forward svc/frontend 8080:80 -n ${NAMESPACE}"
    echo ""
    echo "  USEFUL COMMANDS:"
    echo "  View logs:       kubectl logs -l app=backend -n ${NAMESPACE} -f"
    echo "  Describe pod:    kubectl describe pod -l app=backend -n ${NAMESPACE}"
    echo "  Shell into pod:  kubectl exec -it deploy/backend -n ${NAMESPACE} -- /bin/sh"
    echo "================================================================="
}

# ---------------------------------------------------------------------------
# MAIN — Execute all steps in order
# ---------------------------------------------------------------------------
# This is the entry point. Each function is called in dependency order.
main() {
    check_prerequisites
    deploy_namespace
    deploy_configs
    deploy_database
    deploy_backend
    deploy_frontend
    deploy_ingress
    deploy_network_policy
    show_summary
}

# Run main
main

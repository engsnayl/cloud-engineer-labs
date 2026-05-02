#!/bin/bash
# =============================================================================
# Validation Script — Project 001: Multi-Tier Application
#
# Checks that all required files exist, Terraform is formatted, Kubernetes
# manifests contain expected resource kinds, and (if a cluster is available)
# pods are running in the multi-tier-app namespace.
#
# Usage: bash validate.sh
# =============================================================================

PASS=0
FAIL=0
TOTAL=0

check() {
    local description="$1"
    local result="$2"
    ((TOTAL++))
    if [[ "$result" == "0" ]]; then
        echo -e "  ✅  $description"
        ((PASS++))
    else
        echo -e "  ❌  $description"
        ((FAIL++))
    fi
}

SOLUTION_DIR="."

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "========================================="
echo "  Terraform Checks"
echo "========================================="

# Directory structure
test -d "$SOLUTION_DIR/terraform"
check "terraform/ directory exists" "$?"

test -d "$SOLUTION_DIR/terraform/modules/networking"
check "terraform/modules/networking/ exists" "$?"

test -d "$SOLUTION_DIR/terraform/modules/security"
check "terraform/modules/security/ exists" "$?"

test -d "$SOLUTION_DIR/terraform/modules/ecr"
check "terraform/modules/ecr/ exists" "$?"

# Root module files
for f in main.tf variables.tf outputs.tf providers.tf backend.tf; do
    test -f "$SOLUTION_DIR/terraform/$f"
    check "terraform/$f exists" "$?"
done

# Module files
for mod in networking security ecr; do
    for f in main.tf variables.tf outputs.tf; do
        test -f "$SOLUTION_DIR/terraform/modules/$mod/$f"
        check "terraform/modules/$mod/$f exists" "$?"
    done
done

# Terraform formatting (only if terraform is installed)
if command -v terraform &>/dev/null; then
    terraform -chdir="$SOLUTION_DIR/terraform" fmt -check -recursive > /dev/null 2>&1
    check "terraform fmt -check passes (no formatting issues)" "$?"
else
    echo "  ⚠️   terraform not installed — skipping fmt check"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "========================================="
echo "  Docker Checks"
echo "========================================="

test -f "$SOLUTION_DIR/docker/frontend/Dockerfile"
check "Frontend Dockerfile exists" "$?"

test -f "$SOLUTION_DIR/docker/backend/Dockerfile"
check "Backend Dockerfile exists" "$?"

test -f "$SOLUTION_DIR/docker/frontend/nginx.conf"
check "Frontend nginx.conf exists" "$?"

test -f "$SOLUTION_DIR/docker/frontend/index.html"
check "Frontend index.html exists" "$?"

test -f "$SOLUTION_DIR/docker/backend/app.py"
check "Backend app.py exists" "$?"

test -f "$SOLUTION_DIR/docker-compose.yml"
check "docker-compose.yml exists" "$?"

test -f "$SOLUTION_DIR/docker/frontend/.dockerignore"
check "Frontend .dockerignore exists" "$?"

test -f "$SOLUTION_DIR/docker/backend/.dockerignore"
check "Backend .dockerignore exists" "$?"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "========================================="
echo "  Kubernetes Manifest Checks"
echo "========================================="

K8S_MANIFESTS=(
    namespace
    database-secret
    database-init-configmap
    database-pvc
    database-statefulset
    database-service
    backend-configmap
    backend-deployment
    backend-service
    frontend-deployment
    frontend-service
    ingress
    network-policy
)

for f in "${K8S_MANIFESTS[@]}"; do
    test -f "$SOLUTION_DIR/k8s/${f}.yaml"
    check "k8s/${f}.yaml exists" "$?"
done

# Content checks on key manifests
if test -f "$SOLUTION_DIR/k8s/database-secret.yaml"; then
    grep -q "kind: Secret" "$SOLUTION_DIR/k8s/database-secret.yaml"
    check "database-secret.yaml contains kind: Secret" "$?"
fi

if test -f "$SOLUTION_DIR/k8s/network-policy.yaml"; then
    grep -q "kind: NetworkPolicy" "$SOLUTION_DIR/k8s/network-policy.yaml"
    check "network-policy.yaml contains kind: NetworkPolicy" "$?"
fi

if test -f "$SOLUTION_DIR/k8s/database-statefulset.yaml"; then
    grep -q "kind: StatefulSet" "$SOLUTION_DIR/k8s/database-statefulset.yaml"
    check "database-statefulset.yaml contains kind: StatefulSet" "$?"
fi

if test -f "$SOLUTION_DIR/k8s/ingress.yaml"; then
    grep -q "kind: Ingress" "$SOLUTION_DIR/k8s/ingress.yaml"
    check "ingress.yaml contains kind: Ingress" "$?"
fi

if test -f "$SOLUTION_DIR/k8s/namespace.yaml"; then
    grep -q "multi-tier-app" "$SOLUTION_DIR/k8s/namespace.yaml"
    check "namespace.yaml references multi-tier-app" "$?"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "========================================="
echo "  CI/CD Checks"
echo "========================================="

test -f "$SOLUTION_DIR/.github/workflows/deploy.yml"
check ".github/workflows/deploy.yml exists" "$?"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "========================================="
echo "  Monitoring Checks"
echo "========================================="

test -f "$SOLUTION_DIR/monitoring/prometheus-config.yaml"
check "monitoring/prometheus-config.yaml exists" "$?"

test -f "$SOLUTION_DIR/monitoring/grafana-dashboard.json"
check "monitoring/grafana-dashboard.json exists" "$?"

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "========================================="
echo "  Documentation Checks"
echo "========================================="

test -f "$SOLUTION_DIR/README.md"
check "README.md exists" "$?"

test -f "SOLUTION-LEGACY.md"
check "SOLUTION-LEGACY.md exists (legacy walkthrough)" "$?"

test -f "README.md"
check "README.md exists (project root)" "$?"

# ─────────────────────────────────────────────────────────────────────────────
# Cluster checks (only if kubectl is available and a cluster is reachable)
if command -v kubectl &>/dev/null && kubectl cluster-info &>/dev/null 2>&1; then
    echo ""
    echo "========================================="
    echo "  Cluster Checks (live)"
    echo "========================================="

    kubectl get namespace multi-tier-app &>/dev/null
    check "Namespace multi-tier-app exists" "$?"

    kubectl get pods -n multi-tier-app 2>/dev/null | grep -q "Running"
    check "Pods are running in multi-tier-app namespace" "$?"

    kubectl get statefulset postgres -n multi-tier-app &>/dev/null 2>&1
    check "PostgreSQL StatefulSet exists" "$?"

    kubectl get deployment backend -n multi-tier-app &>/dev/null 2>&1
    check "Backend Deployment exists" "$?"

    kubectl get deployment frontend -n multi-tier-app &>/dev/null 2>&1
    check "Frontend Deployment exists" "$?"

    kubectl get ingress -n multi-tier-app &>/dev/null 2>&1
    check "Ingress exists in namespace" "$?"

    kubectl get networkpolicy -n multi-tier-app &>/dev/null 2>&1
    check "NetworkPolicy exists in namespace" "$?"
else
    echo ""
    echo "  ⚠️   No Kubernetes cluster detected — skipping live cluster checks"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "========================================="
echo "  Results"
echo "========================================="
echo ""
echo "  Total:  $TOTAL"
echo "  Passed: $PASS ✅"
echo "  Failed: $FAIL ❌"
echo ""

if [[ "$FAIL" -eq 0 ]]; then
    echo "  All checks passed!"
else
    echo "  Some checks failed. Review the output above."
fi

echo ""
exit "$FAIL"

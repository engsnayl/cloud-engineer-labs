#!/bin/bash
echo "Running GitOps validation..."
echo ""
PASS=0; FAIL=0
check() { local d="$1" r="$2"; if [[ "$r" == "0" ]]; then echo -e "  ✅  $d"; ((PASS++)); else echo -e "  ❌  $d"; ((FAIL++)); fi; }

# Check YAML validity
for f in argocd-app.yaml deployment.yaml service.yaml; do
    python3 -c "import yaml; yaml.safe_load(open('$f'))" &>/dev/null
    check "$f is valid YAML" "$?"
done

# Check ArgoCD app points to production path
grep -q "path: apps/web-app/production" argocd-app.yaml
check "ArgoCD app references production path" "$?"

# Check auto-sync is properly enabled
grep -q "prune: true" argocd-app.yaml
check "Auto-sync prune is enabled" "$?"

grep -q "selfHeal: true" argocd-app.yaml
check "Auto-sync selfHeal is enabled" "$?"

# Check image tag is not 'latest'
! grep -q "image:.*:latest" deployment.yaml
check "Image tag is not 'latest'" "$?"

# Check memory limit is reasonable (> 64Mi)
mem_limit=$(grep -A1 "limits:" deployment.yaml | grep memory | grep -oP '\d+' | head -1)
[[ -n "$mem_limit" && "$mem_limit" -ge 64 ]]
check "Memory limit is reasonable (>= 64Mi)" "$?"

echo ""; echo "Results: $PASS passed, $FAIL failed"; [[ "$FAIL" -eq 0 ]]

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

# Check memory limit is reasonable (>= 64Mi)
# Use Python for robust YAML parsing rather than fragile grep
mem_ok=$(python3 -c "
import yaml, re
with open('deployment.yaml') as f:
    d = yaml.safe_load(f)
limit = d['spec']['template']['spec']['containers'][0]['resources']['limits']['memory']
# Parse value like '256Mi', '1Gi' etc.
m = re.match(r'(\d+)(Mi|Gi|M|G)?', limit)
if not m:
    print('FAIL'); exit()
val, unit = int(m.group(1)), m.group(2) or ''
mb = val * 1024 if unit in ('Gi','G') else val
print('OK' if mb >= 64 else 'FAIL')
" 2>/dev/null)
[[ "$mem_ok" == "OK" ]]
check "Memory limit is reasonable (>= 64Mi)" "$?"

# Check liveness probe path is /healthz (not /ready)
liveness_ok=$(python3 -c "
import yaml
with open('deployment.yaml') as f:
    d = yaml.safe_load(f)
path = d['spec']['template']['spec']['containers'][0]['livenessProbe']['httpGet']['path']
print('OK' if path == '/healthz' else 'FAIL')
" 2>/dev/null)
[[ "$liveness_ok" == "OK" ]]
check "Liveness probe path is /healthz" "$?"

# Check service selector matches deployment labels (sanity check)
selector_ok=$(python3 -c "
import yaml
with open('service.yaml') as f:
    svc = yaml.safe_load(f)
with open('deployment.yaml') as f:
    dep = yaml.safe_load(f)
sel = svc['spec']['selector']
labels = dep['spec']['template']['metadata']['labels']
print('OK' if all(labels.get(k) == v for k,v in sel.items()) else 'FAIL')
" 2>/dev/null)
[[ "$selector_ok" == "OK" ]]
check "Service selector matches deployment pod labels" "$?"

echo ""; echo "Results: $PASS passed, $FAIL failed"; [[ "$FAIL" -eq 0 ]]

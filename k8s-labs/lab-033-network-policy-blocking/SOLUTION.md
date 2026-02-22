# Solution Walkthrough — Network Policy Blocking

## The Problem

After a security hardening effort, a NetworkPolicy was applied to restrict access to the database pods. The policy works — but it's **too restrictive**. It only allows traffic from pods with the label `role: admin`, but the API pods that need to reach the database have the label `role: api`. Since the API pods don't match the policy's allowed selector, their traffic to the database is blocked.

The API pods are returning 500 errors because they can't connect to the database on port 5432. The fix is to update the NetworkPolicy to also allow traffic from pods with `role: api`, while keeping the existing `role: admin` access and the port restriction.

## Thought Process

When inter-pod communication breaks after a NetworkPolicy change, an experienced Kubernetes engineer:

1. **Identify the NetworkPolicy** — `kubectl get networkpolicy -n production` lists all policies. `kubectl describe networkpolicy` shows what's allowed and what's targeted.
2. **Check which pods are affected** — the `podSelector` in the policy's `spec` determines which pods the policy applies TO (the database pods). The `ingress.from.podSelector` determines which pods are allowed to send traffic.
3. **Compare allowed labels to actual labels** — `kubectl get pods --show-labels -n production` shows what labels the API pods have. Compare with the selectors in the NetworkPolicy.
4. **Add the missing selector** — in NetworkPolicy ingress rules, each `- podSelector` entry is an OR condition. Adding another selector for `role: api` allows both admin and API pods.

## Step-by-Step Solution

### Step 1: Create the production namespace

```bash
kubectl create namespace production --dry-run=client -o yaml | kubectl apply -f -
```

**What this does:** Ensures the production namespace exists.

### Step 2: Apply the broken manifests

```bash
kubectl apply -f manifests/broken/
```

**What this does:** Creates the API deployment and the restrictive NetworkPolicy.

### Step 3: Check the current NetworkPolicy

```bash
kubectl describe networkpolicy db-restrict -n production
```

**What this does:** Shows the NetworkPolicy details. Look at:
- **PodSelector:** `app=database` — this policy applies to pods with this label (the database pods)
- **Allowing ingress from:** only pods matching `role=admin`
- **On port:** TCP 5432

The API pods have `role: api`, not `role: admin`, so their traffic is blocked.

### Step 4: Check the API pod labels

```bash
kubectl get pods -n production --show-labels
```

**What this does:** Shows all pods and their labels. You'll see the API pods have `role: api`. Since the NetworkPolicy only allows `role: admin`, the API pods are blocked.

### Step 5: Fix the NetworkPolicy

```bash
cat > manifests/broken/network-policy.yaml << 'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-restrict
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: database
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: api
    - podSelector:
        matchLabels:
          role: admin
    ports:
    - protocol: TCP
      port: 5432
EOF
```

**What this does:** Updates the NetworkPolicy to allow traffic from both `role: api` AND `role: admin` pods. The key structure to understand:

```yaml
ingress:
- from:
  - podSelector:          # OR condition 1: pods with role=api
      matchLabels:
        role: api
  - podSelector:          # OR condition 2: pods with role=admin
      matchLabels:
        role: admin
```

Each `- podSelector` under `from:` is an **OR** condition — traffic is allowed if the source matches ANY of the selectors. This means either `role: api` OR `role: admin` pods can reach the database.

The `ports` restriction stays the same — only TCP port 5432 (PostgreSQL's default port) is allowed. All other ports remain blocked.

### Step 6: Apply the fixed NetworkPolicy

```bash
kubectl apply -f manifests/broken/network-policy.yaml
```

**What this does:** Updates the NetworkPolicy. Network policies take effect immediately — there's no rolling update or pod restart needed. As soon as the policy is updated, the API pods can reach the database.

### Step 7: Verify the NetworkPolicy

```bash
kubectl describe networkpolicy db-restrict -n production
```

**What this does:** Shows the updated policy. You should now see both `role: api` and `role: admin` in the allowed ingress sources.

### Step 8: Verify the policy still restricts to port 5432

```bash
kubectl get networkpolicy db-restrict -n production -o yaml | grep -A2 "ports:"
```

**What this does:** Confirms the port restriction is still in place. Only TCP 5432 should be allowed — the security restriction is maintained while fixing the communication issue.

## Docker Lab vs Real Life

- **CNI plugin requirement:** NetworkPolicies only work if the cluster's CNI plugin supports them. Calico, Cilium, and Weave support NetworkPolicies. The default `kubenet` and some other CNIs do NOT — the policies are silently ignored. In production, always verify your CNI supports policies.
- **Default deny policies:** In production, a best practice is to start with a "default deny all" policy for each namespace, then explicitly allow only the traffic that's needed. This lab's approach (restricting specific pods) is one pattern; blanket deny + explicit allow is more secure.
- **Egress policies:** This lab only uses ingress (incoming traffic) policies. In production, you'd also configure egress (outgoing traffic) policies to prevent compromised pods from making unauthorized outbound connections (like data exfiltration).
- **Namespace selectors:** In production, you might allow traffic from pods in other namespaces using `namespaceSelector`. For example, allowing monitoring namespace pods to reach databases in the production namespace.
- **Policy testing:** Tools like `kubectl-np-viewer` or Cilium's policy editor help visualize and test NetworkPolicies before applying them. In production, always test policies in a staging environment first.

## Key Concepts Learned

- **NetworkPolicies are deny-by-default for matched pods** — once a policy selects a pod (via `podSelector`), all traffic not explicitly allowed is denied
- **Multiple `podSelector` entries under `from:` are OR conditions** — traffic is allowed if the source matches any of the selectors
- **NetworkPolicies take effect immediately** — no pod restart needed. Changes are applied as soon as the policy is updated.
- **The `podSelector` in `spec` selects which pods the policy APPLIES TO** — don't confuse this with the selectors in `ingress.from`, which define what's ALLOWED to connect
- **Port restrictions and source restrictions work together** — traffic must match both the source selector AND the port rule to be allowed

## Common Mistakes

- **Replacing the admin selector instead of adding the API selector** — you need both. Removing `role: admin` would break admin access to the database. Add the new selector alongside the existing one.
- **Confusing AND vs OR in NetworkPolicy selectors** — within a single `- from:` block, multiple `podSelector` entries are OR conditions. But if you put conditions in the SAME `podSelector.matchLabels`, they're AND conditions (the pod must have all specified labels).
- **Forgetting that NetworkPolicies need CNI support** — if you apply a policy and traffic isn't blocked, your CNI might not support NetworkPolicies. The policy exists as a resource but has no effect.
- **Not testing the policy change** — always verify that both the allowed traffic works AND the restricted traffic is still blocked after changing a policy.
- **Over-restricting with podSelector** — if you set the `spec.podSelector` to `{}` (empty), the policy applies to ALL pods in the namespace. Make sure the selector is specific enough to target only the intended pods.

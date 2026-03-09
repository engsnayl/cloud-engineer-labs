# Solution Walkthrough — Lab 037: Network Policy Blocking

---

## TLDR — Plain English Summary

A NetworkPolicy was set up to protect the database pods — only certain pods are allowed to talk to them. The problem is the policy was written too narrowly. It only lets pods labelled `role: admin` through the door, but the API pods (labelled `role: api`) also need to reach the database. They're being silently blocked, which is why the API pods are returning 500 errors.

**The fix:** Edit the NetworkPolicy to add `role: api` as another allowed source. You're not removing the `role: admin` rule — you're adding a second one alongside it. Both sets of pods will then be allowed in, and only on the correct port (5432, the PostgreSQL port). Nothing else gets through.

Steps at a glance:
1. Create the production namespace
2. Apply the broken manifests (the overly restrictive policy)
3. Inspect the policy to confirm the problem
4. Check the API pod labels to confirm the mismatch
5. Edit the NetworkPolicy to add `role: api` as an allowed source
6. Re-apply the fixed policy
7. Verify the policy now shows both allowed sources
8. Confirm the port restriction is still in place

---

## The Problem

After a security hardening effort, a NetworkPolicy was applied to restrict access to the database pods. The policy works — but it's **too restrictive**. It only allows traffic from pods with the label `role: admin`, but the API pods that need to reach the database have the label `role: api`. Since the API pods don't match the policy's allowed selector, their traffic to the database is blocked.

The API pods are returning 500 errors because they can't connect to the database on port 5432. The fix is to update the NetworkPolicy to also allow traffic from pods with `role: api`, while keeping the existing `role: admin` access and the port restriction.

---

## Thought Process

When inter-pod communication breaks after a NetworkPolicy change, an experienced Kubernetes engineer:

1. **Identify the NetworkPolicy** — list all policies in the namespace, then describe the relevant one to see what it allows and what pods it targets.
2. **Check which pods are affected** — the `podSelector` in the policy's `spec` determines which pods the policy applies TO (the database pods). The `ingress.from.podSelector` determines which pods are allowed to send traffic.
3. **Compare allowed labels to actual labels** — show pod labels and compare them with the selectors in the NetworkPolicy. Look for a mismatch.
4. **Add the missing selector** — in NetworkPolicy ingress rules, each `- podSelector` entry is an OR condition. Adding another selector for `role: api` allows both admin and API pods without removing the existing rule.

---

## Step-by-Step Solution

### Step 1: Create the production namespace

First, confirm the namespace exists (or create it if not):

```bash
kubectl get namespaces
```

| Part | Meaning |
|------|---------|
| `kubectl` | The Kubernetes command-line tool |
| `get namespaces` | Lists all namespaces in the cluster |

If `production` isn't listed, create it:

```bash
kubectl create namespace production
```

| Part | Meaning |
|------|---------|
| `kubectl` | The Kubernetes CLI |
| `create namespace` | Creates a new namespace resource |
| `production` | The name to give the new namespace |

> **Useful pattern to know:** `kubectl create namespace production --dry-run=client -o yaml | kubectl apply -f -` is a safe idempotent version (won't error if the namespace already exists). It generates the YAML without applying it (`--dry-run=client`), then pipes it to `kubectl apply` which only creates it if it's missing. Useful in scripts or CI pipelines, but the plain `create` command is fine for lab work.

---

### Step 2: Apply the broken manifests

```bash
kubectl apply -f manifests/broken/
```

| Part | Meaning |
|------|---------|
| `kubectl apply` | Creates or updates resources defined in a file or directory |
| `-f manifests/broken/` | Points to the directory containing the broken manifest files |

**What this does:** Creates the API deployment and the overly restrictive NetworkPolicy that only allows `role: admin` traffic to the database.

---

### Step 3: Check the current NetworkPolicy

```bash
kubectl describe networkpolicy db-restrict -n production
```

| Part | Meaning |
|------|---------|
| `kubectl describe` | Shows a detailed, human-readable breakdown of a resource |
| `networkpolicy` | The resource type to inspect |
| `db-restrict` | The name of the specific NetworkPolicy |
| `-n production` | Targets the `production` namespace |

**What to look for in the output:**
- **PodSelector:** `app=database` — this policy applies TO pods with this label (the database pods)
- **Allowing ingress from:** only pods matching `role=admin`
- **On port:** TCP 5432

The API pods have `role: api`, not `role: admin`, so their traffic is blocked.

---

### Step 4: Check the API pod labels

```bash
kubectl get pods -n production --show-labels
```

| Part | Meaning |
|------|---------|
| `kubectl get pods` | Lists all pods |
| `-n production` | In the `production` namespace |
| `--show-labels` | Adds a LABELS column to the output showing every label on each pod |

**What this does:** Confirms the API pods have `role: api`. Since the NetworkPolicy only allows `role: admin`, the API pods are blocked — this is the mismatch we need to fix.

---

### Step 5: Fix the NetworkPolicy

Edit the manifest file to add `role: api` as an allowed source:

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

**Command breakdown:**

| Part | Meaning |
|------|---------|
| `cat >` | Writes content to a file (overwrites if it already exists) |
| `manifests/broken/network-policy.yaml` | The file to write to |
| `<< 'EOF'` | Starts a heredoc — everything until the closing `EOF` is treated as the file content |

**Key YAML structure explained:**

```yaml
ingress:
- from:
  - podSelector:          # OR condition 1: pods with role=api can connect
      matchLabels:
        role: api
  - podSelector:          # OR condition 2: pods with role=admin can connect
      matchLabels:
        role: admin
```

Each `- podSelector` under `from:` is an **OR** condition — traffic is allowed if the source matches **any** of the selectors. So either `role: api` OR `role: admin` pods can reach the database.

The `ports` restriction stays the same — only TCP port 5432 (PostgreSQL's default port) is allowed. All other ports remain blocked.

---

### Step 6: Apply the fixed NetworkPolicy

```bash
kubectl apply -f manifests/broken/network-policy.yaml
```

| Part | Meaning |
|------|---------|
| `kubectl apply` | Creates or updates resources to match the file |
| `-f manifests/broken/network-policy.yaml` | The specific file to apply |

**What this does:** Updates the NetworkPolicy. Network policies take effect immediately — there's no rolling update or pod restart needed. As soon as the policy is updated, the API pods can reach the database.

---

### Step 7: Verify the NetworkPolicy

```bash
kubectl describe networkpolicy db-restrict -n production
```

*(Same command as Step 3 — same breakdown applies.)*

**What to look for:** You should now see both `role: api` and `role: admin` listed in the allowed ingress sources.

---

### Step 8: Verify the port restriction is still in place

```bash
kubectl get networkpolicy db-restrict -n production -o yaml | grep -A2 "ports:"
```

| Part | Meaning |
|------|---------|
| `kubectl get networkpolicy db-restrict` | Retrieves the named NetworkPolicy resource |
| `-n production` | In the `production` namespace |
| `-o yaml` | Outputs the full resource definition in YAML format |
| `\|` | Pipes the output to the next command |
| `grep -A2 "ports:"` | Finds lines containing `ports:` and shows 2 lines after each match |

**What this does:** Confirms the port restriction is still in place. Only TCP 5432 should be listed — the security restriction is maintained while fixing the communication issue.

---

## Pi / K3s Environment Notes

- **Lab 035 ResourceQuota persists in the production namespace** — the quota requires all pods to declare `resources.requests` and `resources.limits`. The lab's `api-deployment.yaml` did not include these, causing `FailedCreate` on the ReplicaSet. The manifest was updated to add `requests: cpu 100m, memory: 64Mi` / `limits: cpu 200m, memory: 128Mi` before the lab could proceed. This is a Pi environment issue, not a lab design issue. The fix was committed to git: `fix: add resource requests/limits to lab-037 api deployment`.
- **K3s uses Flannel as the default CNI** — Flannel does not enforce NetworkPolicies. In this lab environment, NetworkPolicies exist as Kubernetes resources but have no actual enforcement effect on traffic. The lab is valid for understanding the YAML structure, selector logic, and `kubectl describe` output, but live traffic blocking/allowing cannot be verified on a standard K3s setup without switching the CNI to Calico or Cilium.

---

## Real-World Context

- **CNI plugin requirement:** NetworkPolicies only work if the cluster's CNI plugin supports them. Calico, Cilium, and Weave support NetworkPolicies. The default `kubenet` and some other CNIs do NOT — the policies are silently ignored. In production, always verify your CNI supports policies.
- **Default deny policies:** In production, a best practice is to start with a "default deny all" policy for each namespace, then explicitly allow only the traffic that's needed. This lab's approach (restricting specific pods) is one pattern; blanket deny + explicit allow is more secure.
- **Egress policies:** This lab only uses ingress (incoming traffic) policies. In production, you'd also configure egress (outgoing traffic) policies to prevent compromised pods from making unauthorised outbound connections.
- **Namespace selectors:** In production, you might allow traffic from pods in other namespaces using `namespaceSelector`. For example, allowing monitoring namespace pods to reach databases in the production namespace.
- **Policy testing:** Tools like `kubectl-np-viewer` or Cilium's policy editor help visualise and test NetworkPolicies before applying them. In production, always test policies in a staging environment first.

---

## Key Concepts

- **NetworkPolicies are deny-by-default for matched pods** — once a policy selects a pod (via `podSelector`), all traffic not explicitly allowed is denied
- **Multiple `podSelector` entries under `from:` are OR conditions** — traffic is allowed if the source matches any of the selectors
- **NetworkPolicies take effect immediately** — no pod restart needed; changes apply as soon as the policy is updated
- **The `podSelector` in `spec` selects which pods the policy APPLIES TO** — don't confuse this with the selectors in `ingress.from`, which define what's ALLOWED to connect
- **Port restrictions and source restrictions work together** — traffic must match both the source selector AND the port rule to be allowed

---

## Common Mistakes

- **Replacing the admin selector instead of adding the API selector** — you need both. Removing `role: admin` would break admin access to the database.
- **Confusing AND vs OR in NetworkPolicy selectors** — within a single `- from:` block, multiple `podSelector` entries are OR conditions. But if you put multiple labels inside the SAME `podSelector.matchLabels`, they're AND conditions (the pod must have all specified labels).
- **Forgetting that NetworkPolicies need CNI support** — if you apply a policy and traffic isn't blocked, your CNI might not support NetworkPolicies. The policy exists as a resource but has no effect.
- **Not testing the policy change** — always verify that both the allowed traffic works AND the restricted traffic is still blocked after changing a policy.
- **Over-restricting with podSelector** — if you set the `spec.podSelector` to `{}` (empty), the policy applies to ALL pods in the namespace.

# Solution Walkthrough — RBAC Permission Denied

## The Problem

A monitoring service account (`monitoring-sa`) can't read pod information in the `monitoring` namespace, getting "403 Forbidden" errors. The RBAC (Role-Based Access Control) configuration has **two issues**:

1. **Role is in the wrong namespace** — the `pod-reader` Role is created in the `default` namespace, but the RoleBinding is in the `monitoring` namespace. A RoleBinding can only reference a Role in the same namespace. Since there's no `pod-reader` Role in `monitoring`, the RoleBinding effectively grants no permissions.
2. **Missing `list` verb** — even if the Role were in the correct namespace, it only grants `get` and `watch` verbs, not `list`. The monitoring system needs all three (`get`, `list`, `watch`) to enumerate and track pods. Without `list`, it can't query for all pods in the namespace.

## Thought Process

When a ServiceAccount gets 403 Forbidden errors, an experienced Kubernetes engineer checks:

1. **Test the permissions explicitly** — `kubectl auth can-i list pods -n monitoring --as system:serviceaccount:monitoring:monitoring-sa` tells you directly whether the permission is granted.
2. **Check the Role** — does it exist in the right namespace? Does it grant the right verbs on the right resources?
3. **Check the RoleBinding** — does it reference the correct Role and the correct ServiceAccount? Is it in the same namespace as the Role?
4. **Remember the namespace rule** — Roles and RoleBindings are namespace-scoped. A RoleBinding in namespace `monitoring` can only reference a Role in namespace `monitoring` (or a ClusterRole, which is cluster-scoped).

## Step-by-Step Solution

### Step 1: Create the monitoring namespace (if it doesn't exist)

```bash
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
```

**What this does:** Ensures the `monitoring` namespace exists. The `--dry-run=client -o yaml | kubectl apply` pattern is idempotent — it creates the namespace if it doesn't exist and does nothing if it already does.

### Step 2: Apply the broken manifests

```bash
kubectl apply -f manifests/broken/
```

**What this does:** Creates the ServiceAccount, Role (in wrong namespace), and RoleBinding.

### Step 3: Test the current permissions

```bash
kubectl auth can-i list pods -n monitoring --as system:serviceaccount:monitoring:monitoring-sa
kubectl auth can-i get pods -n monitoring --as system:serviceaccount:monitoring:monitoring-sa
kubectl auth can-i watch pods -n monitoring --as system:serviceaccount:monitoring:monitoring-sa
```

**What this does:** Tests each specific permission. The `--as` flag impersonates the ServiceAccount. You'll see "no" for all three — the ServiceAccount has no permissions in the monitoring namespace because the Role is in the wrong namespace.

### Step 4: Check where the Role currently lives

```bash
kubectl get role pod-reader -n default
kubectl get role pod-reader -n monitoring
```

**What this does:** Confirms the Role exists in `default` but not in `monitoring`. The RoleBinding in `monitoring` is looking for a Role named `pod-reader` in `monitoring` — which doesn't exist.

### Step 5: Delete the Role from the wrong namespace

```bash
kubectl delete role pod-reader -n default
```

**What this does:** Removes the misplaced Role from the `default` namespace. We'll recreate it in the correct namespace.

### Step 6: Create the fixed Role and RoleBinding

```bash
cat > manifests/broken/rbac.yaml << 'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: monitoring-sa
  namespace: monitoring
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: monitoring
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: monitoring-pod-reader
  namespace: monitoring
subjects:
- kind: ServiceAccount
  name: monitoring-sa
  namespace: monitoring
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
EOF
kubectl apply -f manifests/broken/rbac.yaml
```

**What this does:** Creates the RBAC resources with both fixes:

1. **Role in `monitoring` namespace** (was `default`) — now the Role and RoleBinding are in the same namespace, so the binding works
2. **Added `list` verb** (was only `get` and `watch`) — the monitoring system needs all three verbs:
   - `get` — retrieve a single pod by name
   - `list` — retrieve all pods in the namespace
   - `watch` — receive real-time updates when pods change

### Step 7: Verify the permissions are correct

```bash
kubectl auth can-i list pods -n monitoring --as system:serviceaccount:monitoring:monitoring-sa
kubectl auth can-i get pods -n monitoring --as system:serviceaccount:monitoring:monitoring-sa
kubectl auth can-i watch pods -n monitoring --as system:serviceaccount:monitoring:monitoring-sa
```

**What this does:** Tests all three permissions again. All three should now return "yes."

### Step 8: Verify the Role is in the correct namespace

```bash
kubectl get role pod-reader -n monitoring
```

**What this does:** Confirms the Role exists in the `monitoring` namespace where the RoleBinding can find it.

## Docker Lab vs Real Life

- **ClusterRole vs Role:** In production, you'd often use a ClusterRole (cluster-scoped) with a RoleBinding (namespace-scoped) instead of a Role. This pattern lets you define permissions once and bind them in multiple namespaces without duplicating the Role.
- **Least privilege:** In production, RBAC should follow the principle of least privilege — grant only the minimum permissions needed. For monitoring, `get`, `list`, and `watch` on pods is appropriate. You wouldn't add `create`, `delete`, or `patch`.
- **Aggregated ClusterRoles:** Kubernetes has built-in ClusterRoles like `view`, `edit`, and `admin` that aggregate common permissions. For monitoring, `view` might be sufficient, or you might bind the built-in `system:monitoring` role.
- **RBAC auditing:** In production, you'd use audit logging to track who accessed what. `kubectl auth can-i --list --as=...` shows all permissions for a ServiceAccount, useful for security reviews.
- **External identity providers:** In production, human users typically authenticate through an identity provider (OIDC with Google, Azure AD, AWS IAM) rather than Kubernetes ServiceAccounts. ServiceAccounts are mainly for in-cluster services.

## Key Concepts Learned

- **Roles and RoleBindings must be in the same namespace** — a RoleBinding in namespace `monitoring` can only reference a Role in namespace `monitoring` (or a ClusterRole)
- **`kubectl auth can-i` is the essential RBAC diagnostic** — it tells you directly whether a specific action is allowed for a specific identity
- **The three verbs for read-only access are `get`, `list`, `watch`** — `get` reads one resource, `list` reads all, `watch` subscribes to changes
- **ServiceAccount format for impersonation:** `system:serviceaccount:<namespace>:<name>` — this is the full identity string used in `--as` flags
- **RBAC is deny-by-default** — if no Role grants a permission, it's denied. You must explicitly grant every permission needed.

## Common Mistakes

- **Creating the Role in the wrong namespace** — this is the exact mistake in this lab. RBAC resources are namespace-scoped, and the namespace matters critically.
- **Forgetting a verb** — `get` and `list` are different permissions. An application that needs to list all pods won't work with only `get` permission.
- **Editing the RoleBinding instead of the Role** — the RoleBinding links the Role to the ServiceAccount. If the Role itself is missing or has wrong permissions, fixing the binding won't help.
- **Not testing with `kubectl auth can-i`** — many people apply RBAC changes and hope they work. Always test explicitly by impersonating the ServiceAccount.
- **Confusing Role with ClusterRole** — a Role grants permissions in a single namespace. A ClusterRole grants cluster-wide or can be bound per-namespace with a RoleBinding. Using the wrong type is a common source of confusion.

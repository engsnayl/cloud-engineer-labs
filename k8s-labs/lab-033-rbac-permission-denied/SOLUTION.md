# Lab 033 — RBAC Permission Denied: Solution Walkthrough

---

## TLDR — What's Going On and How to Fix It

A service account called `monitoring-sa` is trying to read pod information in the `monitoring` namespace but keeps getting "403 Forbidden". There are **two bugs** in the RBAC setup:

1. **The Role is in the wrong namespace.** The `pod-reader` Role was created in the `default` namespace, but the RoleBinding that grants permissions is in the `monitoring` namespace. In Kubernetes, a RoleBinding can only link to a Role in the *same* namespace. Because there's no `pod-reader` Role in `monitoring`, the RoleBinding does nothing — the service account has zero permissions.

2. **A required verb is missing.** Even if the Role were in the right namespace, it only grants `get` and `watch` access to pods — not `list`. The monitoring system needs all three: `get` (fetch one pod by name), `list` (fetch all pods), and `watch` (get live updates). Without `list`, it can't enumerate pods at all.

**The fix:** Delete the Role from `default`, recreate it in `monitoring` with all three verbs, and confirm with `kubectl auth can-i`.

---

## Background — Key Concepts

**Namespace** — a way of dividing a single cluster into separate, isolated sections. Think of it like folders on a computer. Resources in one namespace don't interfere with resources in another, even if they share the same name. Crucially for this lab, Roles only exist in the namespace they were created in — they cannot be seen or used from any other namespace.

**ServiceAccount** — an identity for a process running inside the cluster. When an in-cluster workload (like a monitoring tool) needs to talk to the Kubernetes API, it identifies itself via a ServiceAccount. Think of it like a user account, but for an application rather than a human.

**Role** — a set of permissions. It defines what actions are allowed on what resources (e.g. `get`, `list`, `watch` on `pods`). A Role on its own grants nothing to anyone — it's just a definition.

**RoleBinding** — the thing that connects a Role to an identity. It says "this ServiceAccount gets the permissions defined in this Role." The RoleBinding is where this lab's first bug lives — it's pointing at a Role in the wrong namespace.

Together these three form a complete RBAC setup:
- ServiceAccount = **who** is making the request
- Role = **what** is allowed
- RoleBinding = **linking** the who to the what

---

## The Problem

A monitoring service account (`monitoring-sa`) can't read pod information in the `monitoring` namespace, getting "403 Forbidden" errors. The RBAC configuration has **two issues**:

1. **Role is in the wrong namespace** — the `pod-reader` Role is created in the `default` namespace, but the RoleBinding is in the `monitoring` namespace. A RoleBinding can only reference a Role in the same namespace. Since there's no `pod-reader` Role in `monitoring`, the RoleBinding effectively grants no permissions.
2. **Missing `list` verb** — even if the Role were in the correct namespace, it only grants `get` and `watch` verbs, not `list`. The monitoring system needs all three (`get`, `list`, `watch`) to enumerate and track pods. Without `list`, it can't query for all pods in the namespace.

---

## Thought Process

When a ServiceAccount gets 403 Forbidden errors, an experienced Kubernetes engineer checks:

1. **Test the permissions explicitly** — `kubectl auth can-i` tells you directly whether the permission is granted, and rules out other causes of 403 errors (network policies, misconfigured services) before digging into yaml files.
2. **Check the Role** — does it exist in the right namespace? Does it grant the right verbs on the right resources?
3. **Check the RoleBinding** — does it reference the correct Role and the correct ServiceAccount? Is it in the same namespace as the Role?
4. **If confirmed as RBAC** — go to the `rbac.yaml` in the application's git repository (or pull the live config with `kubectl get role <name> -n <namespace> -o yaml`).

---

## Step-by-Step Solution

### Entry Point

The lab runner will display:

```
This is a Kubernetes lab. Apply the broken manifests then diagnose:

kubectl apply -f k8s-labs/lab-033-rbac-permission-denied/manifests/broken/
```

This is the lab directing you to set up the broken environment. Seeing errors after this step is expected — that's the lab working correctly.

---

### Step 1: Check the monitoring namespace exists

```bash
kubectl get namespaces
```

| Part | What it does |
|------|--------------|
| `kubectl get namespaces` | Lists all namespaces currently in the cluster |

If `monitoring` is listed, proceed. If not, create it:

```bash
kubectl create namespace monitoring
```

| Part | What it does |
|------|--------------|
| `kubectl create namespace` | Creates a new namespace in the cluster |
| `monitoring` | The name to give the new namespace |

> **Useful pattern to know:** The following command is idempotent — it creates the namespace if it doesn't exist and does nothing if it already does:
> ```bash
> kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
> ```
> | Part | What it does |
> |------|--------------|
> | `--dry-run=client` | Builds the resource object locally without sending it to the cluster |
> | `-o yaml` | Outputs that object as YAML |
> | `\|` | Pipes the YAML into the next command |
> | `kubectl apply -f -` | Reads YAML from stdin (`-`); `apply` won't error if the resource already exists |

---

### Step 2: Apply the broken manifests

```bash
kubectl apply -f k8s-labs/lab-033-rbac-permission-denied/manifests/broken/
```

| Part | What it does |
|------|--------------|
| `kubectl apply` | Creates or updates resources defined in a file or folder |
| `-f k8s-labs/lab-033-rbac-permission-denied/manifests/broken/` | Targets the entire `broken/` directory — applies every YAML file inside it |

You should see:

```
serviceaccount/monitoring-sa created
role.rbac.authorization.k8s.io/pod-reader created
rolebinding.rbac.authorization.k8s.io/monitoring-pod-reader created
```

This creates the ServiceAccount, the incorrectly-placed Role (in `default`), and the RoleBinding (in `monitoring`). The cluster is now in the broken state.

---

### Step 3: Test the current permissions

```bash
kubectl auth can-i list pods -n monitoring --as system:serviceaccount:monitoring:monitoring-sa
kubectl auth can-i get pods -n monitoring --as system:serviceaccount:monitoring:monitoring-sa
kubectl auth can-i watch pods -n monitoring --as system:serviceaccount:monitoring:monitoring-sa
```

| Part | What it does |
|------|--------------|
| `kubectl auth can-i` | Asks the cluster: "is this action allowed?" Returns `yes` or `no` |
| `list pods` / `get pods` / `watch pods` | The specific action being tested — verb plus resource |
| `-n monitoring` | Checks the permission in the `monitoring` namespace |
| `--as system:serviceaccount:monitoring:monitoring-sa` | Impersonates the ServiceAccount to test from its perspective |

**Breaking down the `--as` value:**

| Part | Meaning |
|------|---------|
| `system` | Kubernetes internal prefix for built-in identity types |
| `serviceaccount` | The type of identity |
| `monitoring` | The namespace the ServiceAccount lives in |
| `monitoring-sa` | The name of the ServiceAccount |

Expected output:
```
no - RBAC: role.rbac.authorization.k8s.io "pod-reader" not found
no - RBAC: role.rbac.authorization.k8s.io "pod-reader" not found
no - RBAC: role.rbac.authorization.k8s.io "pod-reader" not found
```

Kubernetes isn't just saying "no" — it's telling you exactly why: the Role can't be found. This confirms the diagnosis before you've even looked at the yaml.

---

### Step 4: Check where the Role currently lives

```bash
kubectl get role pod-reader -n default
kubectl get role pod-reader -n monitoring
```

| Part | What it does |
|------|--------------|
| `kubectl get role` | Lists Role objects (namespace-scoped RBAC permission definitions) |
| `pod-reader` | The specific Role name to look up |
| `-n default` / `-n monitoring` | Which namespace to look in |

Expected output:
```
NAME         CREATED AT
pod-reader   2026-03-09T07:21:51Z    ← exists in default

Error from server (NotFound): roles.rbac.authorization.k8s.io "pod-reader" not found    ← missing in monitoring
```

This is the smoking gun. The Role exists in `default` but the RoleBinding in `monitoring` is looking for it in `monitoring` — it can't find it.

---

### Step 5: Delete the Role from the wrong namespace

```bash
kubectl delete role pod-reader -n default
```

| Part | What it does |
|------|--------------|
| `kubectl delete role` | Removes a Role object from the cluster |
| `pod-reader` | The name of the Role to delete |
| `-n default` | Targets the `default` namespace — without this you might delete from the wrong place |

---

### Step 6: Apply the fixed manifests

Edit `k8s-labs/lab-033-rbac-permission-denied/manifests/broken/rbac.yaml` so it reads:

```yaml
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
  namespace: monitoring        # FIX 1: was "default", now "monitoring"
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]  # FIX 2: "list" added
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
```

Then apply it:

```bash
kubectl apply -f k8s-labs/lab-033-rbac-permission-denied/manifests/broken/rbac.yaml
```

| Part | What it does |
|------|--------------|
| `kubectl apply` | Creates the resource if it doesn't exist; updates it if it does |
| `-f k8s-labs/lab-033-rbac-permission-denied/manifests/broken/rbac.yaml` | The specific file to apply |

**The two fixes:**

| Fix | Before | After | Why |
|-----|--------|-------|-----|
| Role namespace | `namespace: default` | `namespace: monitoring` | Role and RoleBinding must be in the same namespace |
| Verbs | `["get", "watch"]` | `["get", "list", "watch"]` | `list` is needed to enumerate all pods in the namespace |

**What each verb does:**

| Verb | What it allows |
|------|----------------|
| `get` | Retrieve a single pod by name |
| `list` | Retrieve all pods in the namespace |
| `watch` | Stream real-time updates as pods change |

---

### Step 7: Verify the permissions are correct

```bash
kubectl auth can-i list pods -n monitoring --as system:serviceaccount:monitoring:monitoring-sa
kubectl auth can-i get pods -n monitoring --as system:serviceaccount:monitoring:monitoring-sa
kubectl auth can-i watch pods -n monitoring --as system:serviceaccount:monitoring:monitoring-sa
```

All three should now return `yes`.

---

### Step 8: Verify the Role is in the correct namespace

```bash
kubectl get role pod-reader -n monitoring
```

| Part | What it does |
|------|--------------|
| `kubectl get role pod-reader` | Looks up the Role named `pod-reader` |
| `-n monitoring` | Confirms it exists in the `monitoring` namespace |

---

## Real-World Context

- **The rbac.yaml is your first stop** — in a real incident, once `kubectl auth can-i` confirms it's an RBAC problem, the `rbac.yaml` in the application's git repository (or pulled live with `kubectl get role <name> -n <namespace> -o yaml`) is where you look. The ServiceAccount, Role, and RoleBinding are typically bundled alongside the Deployment as a complete package.
- **ClusterRole vs Role:** In production, you'd often use a ClusterRole (cluster-scoped) with a RoleBinding (namespace-scoped). This lets you define permissions once and reuse them across namespaces.
- **Least privilege:** RBAC should grant only the minimum permissions needed. For monitoring, `get`, `list`, and `watch` on pods is the right level — nothing more.
- **RBAC auditing:** `kubectl auth can-i --list --as=system:serviceaccount:monitoring:monitoring-sa -n monitoring` prints every permission the ServiceAccount has — useful for security reviews.
- **External identity providers:** In production, human users authenticate through OIDC providers (Google, Azure AD, AWS IAM). ServiceAccounts are primarily for in-cluster workloads.

---

## Key Concepts

- **Namespaces are a hard boundary for Roles** — a Role only exists in the namespace it was created in; it cannot be referenced from any other namespace
- **Roles and RoleBindings must be in the same namespace** — a RoleBinding in `monitoring` can only reference a Role in `monitoring` (or a ClusterRole)
- **`kubectl auth can-i` is the essential RBAC diagnostic** — it tells you directly whether a specific action is allowed, and often tells you exactly why it isn't
- **The three verbs for read-only access are `get`, `list`, `watch`** — `get` reads one resource, `list` reads all, `watch` subscribes to changes
- **ServiceAccount format:** `system:serviceaccount:<namespace>:<name>`
- **RBAC is deny-by-default** — if no Role explicitly grants a permission, it's denied

---

## Common Mistakes

- **Creating the Role in the wrong namespace** — the exact mistake in this lab. The namespace on the Role must match the namespace of the RoleBinding.
- **Forgetting `list`** — `get` and `list` are different permissions. An app that needs to enumerate all pods won't work with only `get`.
- **Editing the RoleBinding instead of the Role** — the RoleBinding links a Role to a ServiceAccount. If the Role is wrong or missing, fixing the binding won't help.
- **Not testing with `kubectl auth can-i`** — always verify permissions explicitly by impersonating the ServiceAccount rather than assuming the config is right.
- **Confusing Role with ClusterRole** — a Role grants permissions in one namespace only. A ClusterRole is cluster-wide.

---

## Pi / K3s Notes

*(Add any K3s-specific quirks encountered during the lab run here)*

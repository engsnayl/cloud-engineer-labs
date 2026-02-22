# Solution Walkthrough — ConfigMap and Secret Missing

## The Problem

An application pod is crashing because it references a ConfigMap and a Secret that **don't exist yet**. The Deployment manifest specifies that certain environment variables should come from `app-config` (ConfigMap) and `app-secrets` (Secret), but nobody created these resources. Kubernetes can't start the pod because it can't find the referenced configuration:

1. **ConfigMap `app-config` doesn't exist** — the pod expects `database_host` and `database_port` values from this ConfigMap.
2. **Secret `app-secrets` doesn't exist** — the pod expects a `db-password` value from this Secret.

When a pod references a ConfigMap or Secret that doesn't exist, Kubernetes keeps the pod in a "CreateContainerConfigError" state — it can't create the container because it can't inject the required environment variables.

## Thought Process

When a pod is stuck in `CreateContainerConfigError`, an experienced Kubernetes engineer immediately suspects missing ConfigMaps or Secrets:

1. **Describe the pod** — `kubectl describe pod` shows events like "configmap 'app-config' not found" or "secret 'app-secrets' not found." These messages tell you exactly what's missing.
2. **Check the pod spec** — look at `env`, `envFrom`, and `volumes` for references to ConfigMaps and Secrets. Each reference must point to an existing resource with the correct keys.
3. **Create the missing resources** — use `kubectl create configmap` and `kubectl create secret` with the right keys and values.
4. **Verify the pod recovers** — after creating the resources, Kubernetes should automatically retry starting the pod.

## Step-by-Step Solution

### Step 1: Apply the broken manifest

```bash
kubectl apply -f manifests/broken/
```

**What this does:** Creates the Deployment. The pod will immediately enter an error state because the ConfigMap and Secret it references don't exist.

### Step 2: Check the pod status

```bash
kubectl get pods -l app=webapp
```

**What this does:** Shows the pod status. You'll see `CreateContainerConfigError` or similar — the pod can't start because the configuration is missing.

### Step 3: Describe the pod to see what's missing

```bash
kubectl describe pod -l app=webapp
```

**What this does:** Shows detailed pod information including Events. Look at the Events section — you'll see messages like "Error: configmap 'app-config' not found" and "Error: secret 'app-secrets' not found." These tell you exactly what to create.

### Step 4: Check the pod spec to see what keys are needed

```bash
kubectl get deployment webapp -o yaml | grep -A5 "configMapKeyRef\|secretKeyRef"
```

**What this does:** Extracts the ConfigMap and Secret references from the Deployment. You'll see three environment variables:
- `DB_HOST` from ConfigMap `app-config`, key `database_host`
- `DB_PORT` from ConfigMap `app-config`, key `database_port`
- `DB_PASSWORD` from Secret `app-secrets`, key `db-password`

### Step 5: Create the ConfigMap

```bash
kubectl create configmap app-config \
    --from-literal=database_host=db.internal.svc.cluster.local \
    --from-literal=database_port=5432
```

**What this does:** Creates a ConfigMap named `app-config` with two key-value pairs. The `--from-literal` flag sets each key directly from the command line:
- `database_host` — the DNS name of the database service inside the cluster
- `database_port` — the PostgreSQL default port

ConfigMaps store non-sensitive configuration data as plain text. They're the standard way to inject configuration into pods without hardcoding values in the container image.

### Step 6: Create the Secret

```bash
kubectl create secret generic app-secrets \
    --from-literal=db-password=supersecretpassword
```

**What this does:** Creates a Secret named `app-secrets` with the database password. The `generic` type is for arbitrary key-value pairs. Kubernetes automatically base64-encodes the value when storing it.

Secrets are similar to ConfigMaps but are intended for sensitive data. They're base64-encoded (not encrypted by default), stored separately, and can be restricted by RBAC policies.

### Step 7: Verify the resources were created

```bash
kubectl get configmap app-config
kubectl get secret app-secrets
```

**What this does:** Confirms both resources exist.

### Step 8: Check that the pod recovers

```bash
kubectl get pods -l app=webapp -w
```

**What this does:** Watches the pod status in real time (the `-w` flag means "watch"). Kubernetes should automatically detect that the missing resources now exist, retry creating the container, and transition the pod to "Running." Press Ctrl+C to stop watching once you see "Running."

### Step 9: Verify the environment variables are injected

```bash
kubectl exec -it $(kubectl get pod -l app=webapp -o jsonpath='{.items[0].metadata.name}') -- env | grep -E "DB_HOST|DB_PORT|DB_PASSWORD"
```

**What this does:** Runs `env` inside the pod and filters for the database-related variables. You should see all three values injected correctly from the ConfigMap and Secret.

## Docker Lab vs Real Life

- **Secret encryption:** In this lab, Secrets are only base64-encoded, not encrypted. In production, you'd enable encryption at rest for Secrets in etcd (`EncryptionConfiguration`), or use an external secrets manager like HashiCorp Vault, AWS Secrets Manager, or the External Secrets Operator.
- **GitOps and secrets:** ConfigMaps can be safely stored in Git. Secrets should NOT be committed to Git in plain text. Use sealed-secrets, SOPS, or external secrets operators to manage secrets in GitOps workflows.
- **ConfigMap/Secret updates:** When you update a ConfigMap or Secret, pods using `envFrom` or `env.valueFrom` do NOT automatically pick up the changes — you need to restart the pods. However, ConfigMaps mounted as volumes do get updated (after a delay).
- **Immutable ConfigMaps/Secrets:** In production, you can mark ConfigMaps and Secrets as `immutable: true` to prevent accidental changes and improve performance (Kubernetes doesn't need to watch for updates).
- **Namespace separation:** In production, ConfigMaps and Secrets are namespace-scoped. Each namespace (dev, staging, production) has its own set with environment-specific values.

## Key Concepts Learned

- **Pods fail with `CreateContainerConfigError` when ConfigMaps or Secrets are missing** — Kubernetes can't inject the environment variables if the source doesn't exist
- **`kubectl describe pod` shows exactly which ConfigMap/Secret is missing** — always check the Events section first
- **ConfigMaps store non-sensitive config, Secrets store sensitive data** — both are injected into pods as environment variables or files, but Secrets have additional access controls
- **`kubectl create configmap --from-literal` is the quick way to create ConfigMaps** — no YAML file needed for simple key-value pairs
- **Pods automatically retry when missing resources are created** — you don't need to restart the pod manually; Kubernetes will retry and start it once the dependencies exist

## Common Mistakes

- **Creating the ConfigMap/Secret with wrong key names** — the pod spec references specific keys (like `database_host`, not `db_host`). If the key doesn't match exactly, Kubernetes treats it as missing.
- **Creating resources in the wrong namespace** — ConfigMaps and Secrets are namespace-scoped. If the pod is in `default` and the ConfigMap is in `monitoring`, the pod can't access it.
- **Putting sensitive data in ConfigMaps** — passwords, API keys, and tokens should always be in Secrets, not ConfigMaps. ConfigMaps are visible to anyone who can read them.
- **Forgetting to base64-encode Secret values in YAML** — when creating Secrets from YAML, values in the `data` field must be base64-encoded. Use `stringData` instead for plain text values, or use `kubectl create secret` which handles encoding automatically.
- **Assuming Secrets are encrypted** — Kubernetes Secrets are only base64-encoded by default, which is NOT encryption. Anyone with read access to the Secret can decode the values. Enable etcd encryption and restrict RBAC access for real security.

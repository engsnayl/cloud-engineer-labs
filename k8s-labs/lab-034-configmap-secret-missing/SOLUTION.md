# Lab 034 — Solution Walkthrough: ConfigMap and Secret Missing

---

## TLDR — Plain English Summary

Imagine you've hired a new employee and told them: "Your login details are in the blue folder on the desk, and your computer password is in the safe." But nobody actually put anything in the blue folder or the safe. The employee can't start work — they're just stood there waiting.

That's exactly what's happening here. The application pod has been told: "Get your database address from a ConfigMap called `app-config`, and get your password from a Secret called `app-secrets`." But neither of those resources was ever created. Kubernetes can't start the container because it can't find the configuration it was told to look for — the pod just sits there in an error state called `CreateContainerConfigError`.

**The fix:** create the missing ConfigMap and Secret as YAML files, apply them to Kubernetes, and the pod will automatically recover.

---

## Understanding the Fix Before You Start

Before jumping into commands, it's worth understanding what's actually happening when you "create a ConfigMap."

Kubernetes has an internal database called **etcd**. Everything that exists in your cluster — Deployments, pods, ConfigMaps, Secrets — lives as an object in that database. When you write a YAML file and run `kubectl apply -f`, you're not telling Kubernetes to "use this file." You're sending an instruction that says "create an object that looks like this." Once Kubernetes reads it and stores the object in etcd, the file itself is no longer needed. The pod never touches your YAML file — it talks to the Kubernetes API, which reads from etcd.

So the workflow is always:
1. **Write a YAML file** — this is your instruction letter
2. **Apply it with `kubectl apply -f`** — Kubernetes reads it and creates the object in etcd
3. **The pod reads from etcd via the API** — it never knows or cares about your file

This also means it doesn't matter where your YAML files live on disk — Kubernetes just needs you to point it at them. The convention of keeping them in a `manifests/` folder is purely for the benefit of humans reading the repo, not for Kubernetes.

**One more important point:** you fix this by creating *new* files for the ConfigMap and Secret. You do **not** edit the Deployment YAML. The Deployment defines what the app is and how it runs — it stays the same across every environment. The ConfigMap and Secret are separate resources that the Deployment *references*. Keeping them separate means the same Deployment can run in dev, staging, and production with different configuration values each time. The Deployment just says "go and find something called `app-config`" — it doesn't contain the values itself.

---

## The Problem

An application pod is crashing because it references a ConfigMap and a Secret that **don't exist**. The Deployment manifest specifies that certain environment variables should come from `app-config` (ConfigMap) and `app-secrets` (Secret), but neither has ever been created. Kubernetes can't start the container because it can't inject the required environment variables:

1. **ConfigMap `app-config` doesn't exist** — the pod expects `database_host` and `database_port` values from this ConfigMap
2. **Secret `app-secrets` doesn't exist** — the pod expects a `db-password` value from this Secret

---

## Thought Process

When a pod is stuck in `CreateContainerConfigError`, an experienced Kubernetes engineer immediately suspects missing ConfigMaps or Secrets:

1. **Describe the pod** — `kubectl describe pod` shows events telling you exactly what's missing
2. **Check the Deployment spec** — look at the `env` section to see what keys are expected and from which resources
3. **Create the missing resources as YAML files** — write the files, apply them to Kubernetes
4. **Verify the pod recovers** — Kubernetes automatically retries once the missing resources exist

---

## Step-by-Step Solution

### Step 1: Apply the broken manifest

```bash
kubectl apply -f manifests/broken/
```

| Part | What it does |
|------|-------------|
| `kubectl` | The Kubernetes command-line tool |
| `apply` | Creates or updates resources from a file — declarative, Kubernetes figures out what needs to change |
| `-f manifests/broken/` | Points to a directory; applies every YAML file found inside it |

The pod will immediately enter an error state because the ConfigMap and Secret it references don't exist yet.

---

### Step 2: Check the pod status

```bash
kubectl get pods -l app=webapp
```

| Part | What it does |
|------|-------------|
| `kubectl get pods` | Lists all pods in the current namespace |
| `-l app=webapp` | Filters by label — only shows pods tagged with `app=webapp` (the `-l` flag means "label selector") |

You'll see `CreateContainerConfigError` — the pod can't start because its configuration is missing.

---

### Step 3: Describe the pod to find out what's missing

```bash
kubectl describe pod -l app=webapp
```

| Part | What it does |
|------|-------------|
| `kubectl describe pod` | Shows detailed information about a pod — much more than `get pods` |
| `-l app=webapp` | Selects the pod by label |

Look at the **Events** section at the bottom of the output. You'll see something like:

```
Warning  Failed  Error: configmap "app-config" not found
```

**Important — Kubernetes reports errors sequentially.** It checks dependencies one at a time and stops at the first thing it can't find. At this point it complains about the missing ConfigMap only — it hasn't even checked the Secret yet. Don't assume the Secret is fine just because it's not mentioned. Once you create the ConfigMap, Kubernetes will retry and then report the missing Secret. Both need to be created — check the full Deployment spec in the next step to identify everything that's missing before you start.

---

### Step 4: Check the Deployment to confirm what keys are expected

```bash
kubectl get deployment webapp -o yaml | grep -A5 "configMapKeyRef\|secretKeyRef"
```

| Part | What it does |
|------|-------------|
| `kubectl get deployment webapp` | Fetches the Deployment named `webapp` |
| `-o yaml` | Outputs the full resource definition in YAML format |
| `\|` | Pipe — passes the output into the next command |
| `grep -A5` | Finds matching lines and prints the 5 lines **after** each match (`-A` = After) |
| `"configMapKeyRef\|secretKeyRef"` | Search pattern — the `\|` means OR, so it finds either term |

You'll see the three environment variables the pod expects:
- `DB_HOST` from ConfigMap `app-config`, key `database_host`
- `DB_PORT` from ConfigMap `app-config`, key `database_port`
- `DB_PASSWORD` from Secret `app-secrets`, key `db-password`

> **The key names must match exactly.** If the pod expects `database_host` and your ConfigMap has `db_host`, Kubernetes still treats it as missing. This is a common mistake.

---

### Step 5: Create the YAML files for the missing resources

Navigate to the broken manifests folder — this is where the Deployment lives, and it's where your new files should sit alongside it:

```bash
cd k8s-labs/lab-034-configmap-secret-missing/manifests/broken/
```

Create two empty files:

```bash
touch configmap.yaml
touch secret.yaml
```

| Part | What it does |
|------|-------------|
| `touch` | Creates an empty file if it doesn't exist (or updates the timestamp if it does) |

Now open and write the ConfigMap:

```bash
nano configmap.yaml
```

Type in the following:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  database_host: "db.internal.svc.cluster.local"
  database_port: "5432"
```

Press `Ctrl+X`, then `Y`, then `Enter` to save and exit.

---

**Line-by-line explanation of the ConfigMap YAML:**

| Line | What it means |
|------|--------------|
| `apiVersion: v1` | Which version of the Kubernetes API to use — ConfigMaps are a core resource so they use `v1` |
| `kind: ConfigMap` | The type of resource you're creating |
| `metadata:` | Information about the resource itself (not its contents) |
| `name: app-config` | The name Kubernetes stores this under — must match exactly what the Deployment references |
| `data:` | The actual key-value pairs this ConfigMap holds |
| `database_host: "db.internal.svc.cluster.local"` | A key called `database_host` with the DNS name of the database service inside the cluster |
| `database_port: "5432"` | A key called `database_port` — quoted as a string because YAML would otherwise treat it as a number |

ConfigMaps store **non-sensitive** configuration as plain text. They're the standard way to inject config into pods without hardcoding values into the container image. Think of them as a settings file that lives in Kubernetes rather than on disk.

---

Now open and write the Secret:

```bash
nano secret.yaml
```

Type in the following:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
type: Opaque
stringData:
  db-password: "supersecretpassword"
```

Press `Ctrl+X`, then `Y`, then `Enter` to save and exit.

---

**Line-by-line explanation of the Secret YAML:**

| Line | What it means |
|------|--------------|
| `apiVersion: v1` | Core Kubernetes API — same as ConfigMap |
| `kind: Secret` | The type of resource |
| `metadata:` | Resource metadata |
| `name: app-secrets` | Must match exactly what the Deployment references |
| `type: Opaque` | The Secret type — `Opaque` means arbitrary key-value pairs (as opposed to `tls` or `docker-registry` which have specific formats) |
| `stringData:` | Lets you write plain text values — Kubernetes handles the base64 encoding for you |
| `db-password: "supersecretpassword"` | The key and value the pod is expecting |

> **`stringData:` vs `data:`:** Secrets have two ways to define values. `data:` requires you to manually base64-encode everything first. `stringData:` accepts plain text and Kubernetes encodes it automatically. Always use `stringData:` when writing Secrets by hand — it's cleaner and less error-prone.

> **Secrets are not encrypted by default.** The base64 encoding is just a format — anyone with access to the Secret can decode it instantly. In production you'd enable etcd encryption at rest, or use an external secrets manager like AWS Secrets Manager or HashiCorp Vault. For this lab, plain Secrets are fine.

---

### Step 6: Apply both files to Kubernetes

From inside the `manifests/broken/` directory, run:

```bash
kubectl apply -f .
```

| Part | What it does |
|------|-------------|
| `kubectl apply` | Sends the YAML instructions to Kubernetes |
| `-f .` | The `.` means "current directory" — applies every YAML file found here |

You should see:

```
deployment.apps/webapp unchanged
configmap/app-config created
secret/app-secrets created
```

This is exactly what you want:
- `unchanged` — the Deployment already existed and nothing about it changed, so Kubernetes left it alone
- `created` — Kubernetes read your YAML files, created the objects in etcd, and they're now available to the pod

The YAML files on disk have done their job. From this point on, the pod talks to the Kubernetes API — not to your files.

---

### Step 7: Watch the pod recover

```bash
kubectl get pods -l app=webapp -w
```

| Part | What it does |
|------|-------------|
| `kubectl get pods -l app=webapp` | Lists pods with the `app=webapp` label |
| `-w` | Watch mode — keeps running and prints updates as the pod status changes (like `tail -f` for pod status) |

Kubernetes automatically detects the missing resources now exist and retries starting the container. You should see the status move to `Running` without touching the pod at all. Press `Ctrl+C` to stop watching.

---

### Step 8: Verify the environment variables are injected

```bash
kubectl exec -it $(kubectl get pod -l app=webapp -o jsonpath='{.items[0].metadata.name}') -- env | grep -E "DB_HOST|DB_PORT|DB_PASSWORD"
```

This is a longer command — let's break it into two parts:

**Inner command** (runs first, inside `$(...)`):

```bash
kubectl get pod -l app=webapp -o jsonpath='{.items[0].metadata.name}'
```

| Part | What it does |
|------|-------------|
| `kubectl get pod -l app=webapp` | Finds the pod with the `app=webapp` label |
| `-o jsonpath='{.items[0].metadata.name}'` | Extracts just the pod's name — `items[0]` is the first result, `.metadata.name` is the name field |

**Outer command:**

```bash
kubectl exec -it <pod-name> -- env | grep -E "DB_HOST|DB_PORT|DB_PASSWORD"
```

| Part | What it does |
|------|-------------|
| `kubectl exec` | Runs a command inside a running container |
| `-it` | Interactive + TTY — standard flags for running commands inside a container |
| `--` | Separator — everything after this is the command to run inside the container, not flags for `kubectl` |
| `env` | Prints all environment variables inside the container |
| `\| grep -E "DB_HOST\|DB_PORT\|DB_PASSWORD"` | Filters output to show only these three variables (`-E` enables extended regex, `\|` means OR) |

You should see all three variables with their correct values — pulled from the ConfigMap and Secret objects now living in etcd.

---

## Lab vs Real Life

| Lab behaviour | Production reality |
|---------------|-------------------|
| Secrets written as plain text in `stringData:` | Never commit plain Secrets to Git. Use sealed-secrets, SOPS, or an external secrets manager (AWS Secrets Manager, HashiCorp Vault) |
| Files created manually with `touch` and `nano` on the Pi | Files written in VS Code locally, committed to Git, applied automatically by a CI/CD pipeline |
| Applied directly by running `kubectl apply` manually | In GitOps, Git is the source of truth — `kubectl apply` is triggered by a pipeline, not run by hand |
| Updating a ConfigMap doesn't restart the pod | Pods using `env.valueFrom` don't pick up ConfigMap changes automatically — you need to restart them. Pods using volume mounts do update after a short delay |
| Single namespace | In production, each environment (dev, staging, prod) has its own namespace with its own ConfigMaps and Secrets containing environment-specific values |

---

## Key Concepts Learned

- **The YAML file is just an instruction letter** — once applied, Kubernetes stores the object in etcd and the file is no longer needed. The pod reads from etcd via the API, never from your file
- **`CreateContainerConfigError` means a referenced ConfigMap or Secret is missing** — Kubernetes can't inject environment variables from something that doesn't exist
- **Kubernetes reports errors sequentially** — it will only tell you about the first missing resource. Fix the ConfigMap error and a Secret error may appear next. Always check the full Deployment spec to identify everything that's missing before you start creating resources
- **The fix lives in new files, not in the Deployment** — the Deployment references resources, it never contains them. ConfigMaps and Secrets are separate objects managed independently
- **Key names must match exactly** — `database_host` and `db_host` are different keys. One character wrong and Kubernetes treats it as missing
- **Pods recover automatically** — once the missing resources are created, Kubernetes retries without you needing to restart anything manually
- **`stringData:` is cleaner than `data:` for writing Secrets by hand** — plain text in, Kubernetes handles the encoding

---

## Common Mistakes

- **Wrong key names** — the pod spec references specific keys (`database_host`, `db-password`). If your key doesn't match exactly, Kubernetes still treats it as missing
- **Assuming only one thing is missing** — because Kubernetes reports errors one at a time, you might fix the ConfigMap and be surprised when a Secret error appears. Always check the full Deployment spec upfront
- **Editing the Deployment to add the values** — the Deployment references resources, it doesn't contain them. Keep them separate
- **Wrong namespace** — ConfigMaps and Secrets are namespace-scoped. A pod in `default` can't read a ConfigMap in `monitoring`
- **Putting sensitive data in ConfigMaps** — passwords and tokens belong in Secrets. ConfigMaps are readable by anyone with access to the namespace
- **Using `data:` instead of `stringData:` in Secret YAML** — values under `data:` must be manually base64-encoded. Use `stringData:` for plain text
- **Assuming base64 = encryption** — it isn't. It's just encoding. Anyone with `kubectl get secret` access can decode the values instantly

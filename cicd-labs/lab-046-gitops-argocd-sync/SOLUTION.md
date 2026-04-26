# Solution Walkthrough — ArgoCD App Out of Sync

## TLDR (Plain English)

You've been handed a ticket: a production app managed by ArgoCD has been showing "OutOfSync" and "Degraded" for six hours. ArgoCD is the tool that watches a Git repo and makes sure your Kubernetes cluster always matches what's in Git — that's GitOps in a nutshell.

Six things are wrong across three YAML files:

1. The ArgoCD app is pointing at the **wrong folder** in Git (it's reading `staging` but should be reading `production`).
2. **Auto-cleanup is switched off** — when things get deleted from Git, they don't get deleted from the cluster.
3. **Auto-correction is switched off** — when someone manually edits the cluster, ArgoCD doesn't pull it back into line.
4. The app's container image is tagged **`latest`** — which is a moving target and breaks the whole "Git is truth" idea.
5. The container has been given **only 10 megabytes of memory** to run in — it dies instantly when it tries to start.
6. The **liveness probe** (Kubernetes' way of checking if the app is alive) is hitting a URL path that doesn't exist, so Kubernetes keeps killing and restarting the pod.

The fix is to edit three YAML files: `argocd-app.yaml`, `deployment.yaml`, and `service.yaml` (though service.yaml turns out to be fine). You won't need any cluster access for this — it's a static manifest review. The whole job is reading what's there, working out what's wrong, and editing files.

---

## You've Just Picked Up The Ticket

> **INCIDENT-CICD-002**: Production app showing "OutOfSync" in ArgoCD for 6 hours. Auto-sync is configured but not triggering. Manual sync attempts fail with errors. Deployment is blocked.

You don't know what's broken yet. Nobody's left you helpful comments. You've been pointed at the manifests directory and that's it. Let's work through this the way you would on a real Monday morning.

### Step 0: Get your bearings

Before changing anything, see what you're dealing with.

```bash
ls
```

You should see three files:

```
argocd-app.yaml
deployment.yaml
service.yaml
```

Three files, three potential problem surfaces. The ticket mentions ArgoCD, so the natural place to start is `argocd-app.yaml` — that's the file that tells ArgoCD what to do.

**How would I know that?** The naming convention. ArgoCD's `Application` custom resource is conventionally named after the thing it manages, with `argocd-app` or just `application` being the typical filename. The other two are standard Kubernetes resources (`Deployment` and `Service`).

---

## Investigation: argocd-app.yaml

```bash
cat argocd-app.yaml
```

Read it slowly. Don't skim. Every line in an ArgoCD Application matters because it tells the controller exactly what to do.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: web-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/company/k8s-manifests.git
    path: apps/web-app/staging
    targetRevision: main
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: false
      selfHeal: false
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### Bug 1: Wrong Git path

**1. What did I observe?**

Look at these two lines together:

```yaml
    path: apps/web-app/staging
...
  destination:
    namespace: production
```

The `source.path` says `staging`. The `destination.namespace` says `production`. That's a mismatch — the ArgoCD app is pulling staging manifests into the production namespace.

**2. Why is this wrong?**

In GitOps, you typically have a folder per environment (`apps/web-app/staging`, `apps/web-app/production`, etc.) so each environment can have its own image tags, replica counts, and resource limits. If your production ArgoCD Application reads from `staging`, you'll deploy staging's config into prod — wrong replica counts, wrong image, possibly wrong everything.

**3. Where do I look to confirm?**

In a real scenario you'd `git clone` the repo at `https://github.com/company/k8s-manifests.git` and check that `apps/web-app/production/` exists. Here we're just doing manifest analysis, so we trust the convention: a path called `staging` exists alongside one called `production`, and we want the latter for a production-bound app.

**4. How do I know what the right value is?**

Two clues:
- The `destination.namespace` is `production` — your source folder should match.
- The `metadata.name` is `web-app` and lives in `argocd` namespace — this is *the* production application, not a staging clone.

**5. The fix:**

```yaml
path: apps/web-app/production
```

---

### Bug 2: Prune is disabled

**1. What did I observe?**

```yaml
  syncPolicy:
    automated:
      prune: false
```

Auto-sync is on (the `automated:` block exists), but `prune` is off.

**2. Why is this wrong?**

`prune` means "if a resource was removed from Git, remove it from the cluster too". With `prune: false`, deleted manifests in Git leave behind orphaned resources in the cluster. Over time, your cluster drifts further and further from Git, which defeats the entire point of GitOps.

The ticket says auto-sync isn't fixing things — `prune: false` is part of why. ArgoCD won't clean up drift it's allowed to detect.

**3. Where do I look to confirm?**

It's right there in the `syncPolicy.automated` block. There's no other place this gets configured.

**4. How do I know what the right value is?**

For a properly automated GitOps setup, `prune: true` is the standard. The exception is when you have stateful resources you absolutely don't want auto-deleted — and even then you'd use the `Prune=false` *annotation* on those specific resources, not disable prune globally.

**5. The fix:**

```yaml
prune: true
```

---

### Bug 3: SelfHeal is disabled

**1. What did I observe?**

```yaml
      selfHeal: false
```

Right next to the prune setting.

**2. Why is this wrong?**

`selfHeal` is what makes ArgoCD revert manual changes. Without it, if someone runs `kubectl edit deployment web-app` and bumps the replica count, ArgoCD sees the drift but does nothing. Git no longer reflects reality — the cluster does.

This is the second half of why auto-sync isn't fixing the OutOfSync state. ArgoCD detects the drift but isn't allowed to correct it.

**3. Where do I look to confirm?**

Same block as prune. It's a peer setting.

**4. How do I know what the right value is?**

For automated GitOps, `selfHeal: true` is what you want. If you don't want this, you may as well not have automated sync at all — you'd just be using ArgoCD as a deployment tool, not a GitOps controller.

**5. The fix:**

```yaml
selfHeal: true
```

---

## Investigation: deployment.yaml

```bash
cat deployment.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-app
  namespace: production
  labels:
    app: web-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: web-app
  template:
    metadata:
      labels:
        app: web-app
    spec:
      containers:
        - name: web-app
          image: company/web-app:latest
          ports:
            - containerPort: 8080
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 10Mi
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /ready
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 20
```

### Bug 4: `latest` image tag

**1. What did I observe?**

```yaml
image: company/web-app:latest
```

**2. Why is this wrong?**

In GitOps, Git is the source of truth. The manifest in Git should describe *exactly* what's running — including the precise version. The `latest` tag breaks this because:

- It's mutable — `company/web-app:latest` today is a different image than `company/web-app:latest` next week.
- ArgoCD compares Git to cluster state by inspecting manifests. If the manifest just says `latest`, ArgoCD has no way to detect that the underlying image changed in the registry.
- Rollbacks become impossible — you can't `git revert` to a previous version because the version isn't in Git.

**3. Where do I look to confirm?**

Just the `image:` line. There's no command needed.

**4. How do I know what the right value is?**

In a real workflow, your CI pipeline would build an image, tag it with the Git commit SHA (or a semver tag), push to the registry, and then update the manifest in Git with that exact tag. So the right value depends on your last successful CI build.

For this lab, any specific immutable tag works. Common conventions:
- `v1.2.3` (semver)
- `sha-abc123def` (Git commit SHA)
- `2025-04-26-abc123` (date + SHA)

**5. The fix:**

```yaml
image: company/web-app:v1.2.3
```

---

### Bug 5: Memory limit too low

**1. What did I observe?**

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 10Mi
```

The request is 128Mi. The limit is 10Mi. That's a contradiction on its own — the limit is *lower* than the request.

**2. Why is this wrong?**

Two problems:

- **Request > Limit is invalid.** Kubernetes requires that `limit >= request`. The pod will fail scheduling or be immediately killed.
- **10Mi is absurdly low.** A typical web app needs at minimum 64–128Mi just for the runtime (JVM, Python interpreter, Node.js heap, etc.). Container starts → exceeds 10Mi within milliseconds → kernel OOM-kills it → Kubernetes restarts it → repeat. Pod ends up in `CrashLoopBackOff`.

**3. Where do I look to confirm?**

In a real cluster you'd run `kubectl describe pod <name>` and see `OOMKilled` in the recent events. You'd also see the container restart count climbing fast. Here we're just reading the manifest.

**4. How do I know what the right value is?**

For a typical web app, sensible defaults are:
- `request: 128Mi` — enough for the app to start cleanly
- `limit: 256Mi` to `512Mi` — gives headroom for spikes without letting one pod consume all node memory

In production you'd derive this from observability data — Prometheus/Grafana memory usage graphs from the last few weeks. For now, anything `>= 128Mi` is reasonable. We'll go with `256Mi`.

**5. The fix:**

```yaml
limits:
  cpu: 500m
  memory: 256Mi
```

---

### Bug 6: Wrong liveness probe path

**1. What did I observe?**

Look at the two probes side by side:

```yaml
readinessProbe:
  httpGet:
    path: /healthz
    port: 8080
livenessProbe:
  httpGet:
    path: /ready
    port: 8080
```

The readiness probe hits `/healthz`. The liveness probe hits `/ready`. They're using the *opposite* paths from what their names suggest, and we have no evidence the app exposes a `/ready` endpoint at all.

**2. Why is this wrong?**

A few things to unpack here.

The two probes have different jobs:

- **Readiness probe** — "Is this pod ready to receive traffic?" If it fails, Kubernetes removes the pod from the Service's endpoint list (no traffic), but doesn't kill it.
- **Liveness probe** — "Is this pod alive at all?" If it fails, Kubernetes kills the container and restarts it.

If the liveness probe hits a path that doesn't exist on the app, every probe attempt returns 404 → Kubernetes thinks the pod is dead → kills it → restarts → repeat. CrashLoopBackOff territory.

We can be reasonably confident `/healthz` exists because the readiness probe is using it (and presumably someone tested that at some point). We have no such evidence for `/ready`.

**3. Where do I look to confirm?**

In a real scenario:
- `kubectl describe pod <name>` would show "Liveness probe failed: HTTP probe failed with statuscode: 404"
- `kubectl logs <pod>` might show 404s in the access log for `/ready`
- You'd check the application source code to see which endpoints actually exist

For this lab, we infer from the existing readiness probe: `/healthz` is known to work, `/ready` is not.

**4. How do I know what the right value is?**

Two reasonable approaches:

- **Use the same path for both** — `/healthz` works fine for both readiness and liveness if the app has one health endpoint. This is common and simple.
- **Use separate paths** — some apps expose distinct `/ready` and `/healthz` endpoints. If yours does, use them — but only if you've confirmed they exist.

Safest fix here: align the liveness probe with the working readiness probe path.

**5. The fix:**

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
```

---

## Investigation: service.yaml

```bash
cat service.yaml
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: web-app
  namespace: production
spec:
  selector:
    app: web-app
  ports:
    - protocol: TCP
      port: 80
      targetPort: 8080
  type: ClusterIP
```

**Quick sanity check:**
- Selector `app: web-app` — matches the deployment's pod labels ✓
- `targetPort: 8080` — matches the container's `containerPort: 8080` ✓
- Service port 80 → container port 8080 — sensible HTTP setup ✓

This file is fine. It's a good habit to verify it anyway, because in real life the bugs you weren't told about are the ones that bite you.

---

## Validation

```bash
./validate.sh
```

You should see all checks passing:

```
Running GitOps validation...

  ✅  argocd-app.yaml is valid YAML
  ✅  deployment.yaml is valid YAML
  ✅  service.yaml is valid YAML
  ✅  ArgoCD app references production path
  ✅  Auto-sync prune is enabled
  ✅  Auto-sync selfHeal is enabled
  ✅  Image tag is not 'latest'
  ✅  Memory limit is reasonable (>= 64Mi)
  ✅  Liveness probe path is /healthz

Results: 9 passed, 0 failed
```

---

## Command Breakdown — What We Used

### `cat <file>`

Just dumps the entire contents of a file to your terminal. For YAML files this is perfect — they're human-readable, and you want to see the whole thing in context to spot mismatches between sections.

| Component | Meaning |
|-----------|---------|
| `cat` | Concatenate (and print) — older Unix utility, prints file contents to stdout |
| `<file>` | Path to the file |

### `ls`

Lists files in the current directory.

| Component | Meaning |
|-----------|---------|
| `ls` | List directory contents |

### `./validate.sh`

Runs the validation script in the current directory.

| Component | Meaning |
|-----------|---------|
| `./` | "In the current directory" — required because for security reasons your shell won't run scripts from `.` unless you explicitly say so |
| `validate.sh` | The script filename |

### Real-world commands you'd use (but don't need here)

| Command | What it does |
|---------|--------------|
| `kubectl get applications -n argocd` | Lists all ArgoCD Applications and their sync/health status |
| `kubectl describe application web-app -n argocd` | Detailed view including last sync result and any errors |
| `argocd app get web-app` | Same info via the ArgoCD CLI — usually nicer formatted |
| `argocd app sync web-app` | Manually trigger a sync |
| `kubectl describe pod <name> -n production` | Shows OOMKilled events, probe failures, restart counts |
| `kubectl logs <pod> -n production --previous` | Logs from the previous (crashed) container instance |

---

## Key Concepts Recap

**GitOps in one sentence:** Git is the single source of truth for what should be running in your cluster, and a controller (ArgoCD, Flux) continuously makes the cluster match Git.

**The three things that make it work:**

1. **Declarative manifests** — the desired state is described in YAML, not as a sequence of commands.
2. **Continuous reconciliation** — the controller checks Git vs. cluster regularly and corrects drift.
3. **Pull-based deployment** — the controller runs *in* the cluster and pulls from Git, rather than your CI pushing kubectl commands at the cluster.

**Why `prune` and `selfHeal` matter:**

| Setting | If `false` | If `true` |
|---------|-----------|-----------|
| `prune` | Deleted-from-Git resources stay in cluster | Cluster stays clean |
| `selfHeal` | Manual `kubectl edit` changes persist | Manual changes get reverted |

Together they're the difference between "ArgoCD as a deployment tool" and "ArgoCD as a GitOps controller".

**Why `latest` breaks GitOps:**

The whole point of GitOps is that `git log` tells you what's running. With `latest`, the manifest in Git says nothing about which version is deployed — the registry decides. You've broken the audit trail and made rollback impossible.

**Liveness vs. readiness probes:**

| Probe | Question | Failure consequence |
|-------|----------|---------------------|
| Readiness | "Should I send traffic?" | Pod removed from Service endpoints |
| Liveness | "Is the process alive?" | Pod gets killed and restarted |

A misconfigured *readiness* probe means traffic stops. A misconfigured *liveness* probe means CrashLoopBackOff. The latter is much more visible and disruptive.

---

## Common Mistakes To Avoid

- **Pointing to the wrong environment path.** Easy mistake when copy-pasting an Application manifest between environments. One Application per environment, named accordingly (`web-app-staging`, `web-app-production`).
- **Leaving `prune: false` "for safety".** This sounds prudent but defeats the point of GitOps. If you have specific resources that shouldn't be auto-pruned, use the per-resource annotation `argocd.argoproj.io/sync-options: Prune=false` rather than disabling prune globally.
- **Using `latest` in CI/CD.** Always tag with the Git commit SHA or semver. The CI pipeline should also commit the new tag back to the manifest repo as part of the deploy step.
- **Mixing liveness and readiness semantics.** They can share an endpoint, but understand which is which. A flapping liveness probe causes restarts; a flapping readiness probe causes traffic gaps.
- **Setting limits below requests.** Kubernetes requires `limit >= request`. The pod won't even schedule.

---

## Reset / Repeat the Lab

To run this lab again from scratch, restore the broken files:

```bash
git checkout -- argocd-app.yaml deployment.yaml service.yaml
```

This pulls the original (broken) versions back from Git so the lab is repeatable. Don't commit your fixes if you want to redo this exercise.

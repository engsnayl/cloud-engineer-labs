# Lab 032 — PVC Stuck Pending: Solution Walkthrough

---

## TLDR — Plain English Summary

Imagine you've booked a storage unit, but when you arrive with your stuff, the key doesn't work. You check the booking and realise three things went wrong: you booked a unit that fits two vans but only one van is allowed, you booked a 20 cubic metre space but only a 10 cubic metre one is available, and you booked at the wrong storage facility entirely.

That's exactly what's happening here. A database pod needs storage (a PVC — a storage request), but it can't connect to the available storage (a PV — the actual storage space) because of **three mismatches**:

1. **The wrong access mode** — the storage request says "multiple nodes can use this at once" (`ReadWriteMany`), but the actual storage only supports "one node at a time" (`ReadWriteOnce`).
2. **The size is too big** — the request asks for 20Gi but the available storage only has 10Gi.
3. **The wrong storage class** — the request specifies `standard` storage but the available PV is `fast-storage`. Kubernetes will only match them if the label is identical.

Because none of these align, Kubernetes refuses to connect them, and the PVC stays stuck in "Pending" forever — which means the database pod that needs that storage also can't start.

**The fix:** You can't edit a PVC's core fields in place (Kubernetes won't allow it). So you delete the broken PVC, write a corrected one that matches the PV exactly on all three points, and recreate it. The PVC binds immediately, and the pod can start.

---

## The Problem in Detail

A database pod can't start because its PersistentVolumeClaim (PVC) is stuck in "Pending" state — it can't bind to the available PersistentVolume (PV). A PV named `db-pv` exists and has data, but the PVC can't use it because of **three mismatches**:

| | PVC (what was requested) | PV (what's available) |
|---|---|---|
| **Access Mode** | `ReadWriteMany` | `ReadWriteOnce` |
| **Storage Size** | `20Gi` | `10Gi` |
| **StorageClass** | `standard` | `fast-storage` |

Since the PVC can't bind, the database pod stays in Pending state forever — it can't start without its storage.

---

## Thought Process

When a PVC is stuck in Pending, an experienced Kubernetes engineer checks:

1. **`kubectl describe pvc`** — the Events section tells you exactly why binding failed. Look for messages about "no persistent volumes available" with details about what didn't match.
2. **Compare PVC to available PVs** — use `kubectl get pv` to see what's available, then compare access modes, capacity, and StorageClass between the PVC and PV.
3. **Remember: PVCs are immutable for key fields** — you can't edit the access mode or StorageClass of an existing PVC. You must delete and recreate it.
4. **Three things must match for binding:** access mode, StorageClass, and the PV must have at least as much capacity as the PVC requests.

---

## Step-by-Step Solution

### Step 1: Apply the broken manifests

```bash
kubectl apply -f k8s-labs/lab-032-pvc-stuck-pending/manifests/broken/
```

**What this does:** Sends all the YAML files in the `manifests/broken/` folder to Kubernetes to create the resources (the PV, PVC, and database pod). The pod will immediately get stuck in Pending because the PVC can't bind to the PV.

**Command breakdown:**
| Part | What it does |
|---|---|
| `kubectl` | The command-line tool for talking to your Kubernetes cluster |
| `apply` | "Create or update these resources to match what's in the file(s)" |
| `-f` | "I'm pointing you at a file or directory" (short for `--filename`) |
| `manifests/broken/` | The folder path containing the YAML files to apply |

---

### Step 2: Check PVC status

```bash
kubectl get pvc db-pvc
```

**What this does:** Asks Kubernetes for the current status of the PVC named `db-pvc`. You'll see `Pending` in the STATUS column, and the VOLUME column will be empty — confirming it hasn't bound to any PV yet.

**Command breakdown:**
| Part | What it does |
|---|---|
| `kubectl` | The Kubernetes CLI |
| `get` | "Show me the current state of a resource" |
| `pvc` | The resource type — PersistentVolumeClaim |
| `db-pvc` | The specific name of the PVC you want to inspect |

---

### Step 3: Describe the PVC to find out why it's pending

```bash
kubectl describe pvc db-pvc
```

**What this does:** Shows a detailed breakdown of the PVC including its spec and, crucially, the **Events** section at the bottom. This is where Kubernetes writes a plain-English explanation of why binding failed — something like "no persistent volumes available for this claim and its NFS storage class." This is almost always your first port of call when something's stuck.

**Command breakdown:**
| Part | What it does |
|---|---|
| `kubectl` | The Kubernetes CLI |
| `describe` | "Give me the full details for this resource, including events" |
| `pvc` | The resource type |
| `db-pvc` | The specific PVC to describe |

---

### Step 4: Compare the PV and PVC side by side

```bash
kubectl get pv db-pv -o yaml
kubectl get pvc db-pvc -o yaml
```

**What this does:** Outputs the full YAML definition for both the PV and PVC. You can scroll through these to spot the mismatches. You're specifically looking at `accessModes`, `capacity`/`requests.storage`, and `storageClassName`.

**Command breakdown:**
| Part | What it does |
|---|---|
| `kubectl` | The Kubernetes CLI |
| `get` | "Show me the state of this resource" |
| `pv` / `pvc` | Resource type — PersistentVolume or PersistentVolumeClaim |
| `db-pv` / `db-pvc` | The specific resource name |
| `-o yaml` | "Output in YAML format" (instead of the default summary table) — gives you the full definition |

What you'll see:
- **PV:** `accessModes: ReadWriteOnce`, `capacity: 10Gi`, `storageClassName: fast-storage`
- **PVC:** `accessModes: ReadWriteMany`, `requests: 20Gi`, `storageClassName: standard`

All three differ — that's why binding fails.

---

### Step 5: Delete the broken PVC

```bash
kubectl delete pvc db-pvc
```

**What this does:** Removes the pending PVC from the cluster. Key fields like `accessModes` and `storageClassName` cannot be edited on an existing PVC — Kubernetes simply won't allow it. So we delete it and will recreate it correctly. The PV (`db-pv`) is unaffected — it's a completely separate resource.

**Command breakdown:**
| Part | What it does |
|---|---|
| `kubectl` | The Kubernetes CLI |
| `delete` | "Remove this resource from the cluster" |
| `pvc` | The resource type |
| `db-pvc` | The specific PVC to delete |

---

### Step 6: Delete the pending pod

```bash
kubectl delete pod database
```

**What this does:** Removes the database pod that was stuck waiting for the PVC. We need to do this because the pod was created with a reference to the PVC — once we recreate the PVC with the correct settings and it binds, we'll recreate the pod fresh so it picks up the newly bound volume properly.

**Command breakdown:**
| Part | What it does |
|---|---|
| `kubectl` | The Kubernetes CLI |
| `delete` | "Remove this resource from the cluster" |
| `pod` | The resource type |
| `database` | The name of the specific pod to delete |

---

### Step 7: Create the fixed PVC

```bash
cat > k8s-labs/lab-032-pvc-stuck-pending/manifests/broken/pvc.yaml << 'EOF'
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: db-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: fast-storage
EOF
kubectl apply -f k8s-labs/lab-032-pvc-stuck-pending/manifests/broken/pvc.yaml
```

**What this does:** Writes a corrected PVC definition to the `pvc.yaml` file and then applies it to the cluster. This new PVC matches the PV on all three criteria, so Kubernetes will bind them immediately.

**`cat > ... << 'EOF'` breakdown:**
| Part | What it does |
|---|---|
| `cat` | A command that reads and outputs text |
| `>` | "Redirect the output into this file" (overwrites if it already exists) |
| `manifests/broken/pvc.yaml` | The file to write to |
| `<< 'EOF'` | Starts a "heredoc" — everything between here and the closing `EOF` is treated as the file content. The quotes around `EOF` prevent any variable substitution. |
| `EOF` (at the end) | Marks the end of the heredoc content |

**YAML field breakdown:**
| Field | Value | Why |
|---|---|---|
| `accessModes: ReadWriteOnce` | One node can mount this read-write | Matches the PV; most database storage uses this |
| `storage: 10Gi` | Requests exactly 10Gi | Matches the PV capacity — a PVC can't request more than the PV has |
| `storageClassName: fast-storage` | The storage class label | Must exactly match the PV's `storageClassName` |

---

### Step 8: Verify the PVC is now Bound

```bash
kubectl get pvc db-pvc
```

**What this does:** Checks the PVC status again. This time you should see `Bound` in the STATUS column and `db-pv` in the VOLUME column — confirming the PVC has successfully connected to the PV.

---

### Step 9: Recreate the database pod

```bash
kubectl apply -f k8s-labs/lab-032-pvc-stuck-pending/manifests/broken/db-pod.yaml
```

**What this does:** Recreates the database pod using the original pod manifest. Since the PVC is now bound, the pod can mount the volume and start up successfully.

---

### Step 10: Verify the pod is running

```bash
kubectl get pod database
```

**What this does:** Confirms the database pod has moved from `Pending` to `Running` with its persistent storage successfully mounted.

---

### Step 11: Run lab validation

```bash
lab validate 032
```

**What this does:** Runs the lab's automated validation checks to confirm everything is in the expected state. All checks should pass before moving on.

---

### Step 12: Reset the lab environment

Run this after completing the lab so it can be repeated from Step 1 immediately with no leftover resources:

```bash
kubectl delete pod database --ignore-not-found
kubectl delete pvc db-pvc --ignore-not-found
kubectl delete pv db-pv --ignore-not-found
```

**What this does:** Removes all three resources created by this lab. The `--ignore-not-found` flag means the command won't error if a resource is already gone — safe to run at any time.

Confirm everything is clean:

```bash
kubectl get pod database; kubectl get pvc db-pvc; kubectl get pv db-pv
```

All three should return `NotFound`. The cluster is now back to factory settings for this lab.

---

## Real World vs. Lab Environment

- **Dynamic provisioning:** In production, you rarely create PVs manually. Instead, you use a StorageClass with a provisioner (like AWS EBS or GCE PD) that automatically creates PVs whenever a PVC is submitted. You just specify the StorageClass name and size in your PVC — the provisioner handles the rest.
- **Multiple StorageClasses:** Production clusters often have several: `gp3` for general purpose, `io2` for high IOPS databases, `sc1` for cold/archive storage. The name in your PVC determines what tier you get.
- **Volume expansion:** Modern StorageClasses support growing a PVC after creation (size increases only). This requires `allowVolumeExpansion: true` on the StorageClass.
- **StatefulSets:** For databases in production, you'd use a StatefulSet rather than a bare Pod. StatefulSets maintain stable identities across restarts and automatically create PVCs for each replica — the standard pattern for any stateful workload.
- **Backups:** PVs need backup strategies. On cloud providers this typically means VolumeSnapshot resources in Kubernetes, or application-level tools like `pg_dump` for PostgreSQL.

---

## Key Concepts Learned

- **Three things must match for PVC-to-PV binding:** access mode, StorageClass, and the PV must have at least as much capacity as the PVC requests
- **`kubectl describe pvc` is your first stop** — the Events section gives specific failure reasons in plain English
- **PVCs are largely immutable** — you cannot change `accessModes` or `storageClassName` on an existing PVC; you must delete and recreate
- **Access modes explained:**
  - `ReadWriteOnce` — one node can mount the volume read-write (most common for databases)
  - `ReadOnlyMany` — many nodes can mount read-only
  - `ReadWriteMany` — many nodes can mount read-write (requires specific storage backends; most block storage like EBS doesn't support this)
- **StorageClass as a filter** — Kubernetes only considers PVs with a matching StorageClass when binding

---

## Common Mistakes

- **Trying to edit the PVC in place** — `kubectl edit pvc` will not let you change access modes or StorageClass. Delete and recreate.
- **Requesting more storage than the PV has** — a PVC requesting `20Gi` will never bind to a `10Gi` PV, even if everything else matches.
- **Deleting the PV instead of the PVC** — if the PV has `persistentVolumeReclaimPolicy: Delete`, removing the PV destroys the underlying data. Always fix the PVC to match the PV.
- **Mixing up access modes** — `ReadWriteMany` sounds more permissive and flexible, but most block storage backends (including AWS EBS) don't support it. Default to `ReadWriteOnce` for databases.
- **Forgetting to delete the stuck pod** — after fixing the PVC, you may need to delete and recreate the pod for it to pick up the now-bound PVC correctly.

---

*Lab 032 | Kubernetes Troubleshooting Series | cloud-engineer-labs*

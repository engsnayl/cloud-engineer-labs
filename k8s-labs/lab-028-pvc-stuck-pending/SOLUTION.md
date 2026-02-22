# Solution Walkthrough — PVC Stuck Pending

## The Problem

A database pod can't start because its PersistentVolumeClaim (PVC) is stuck in "Pending" state — it can't bind to the available PersistentVolume (PV). A PV named `db-pv` exists and has data, but the PVC can't use it because of **three mismatches** between the PVC and the PV:

1. **Wrong access mode** — the PVC requests `ReadWriteMany` (can be mounted by multiple nodes simultaneously), but the PV only supports `ReadWriteOnce` (single node). The PV can't satisfy what the PVC is asking for.
2. **Size request exceeds PV capacity** — the PVC requests `20Gi`, but the PV only has `10Gi` of capacity. Kubernetes won't bind a PVC to a PV that's too small to satisfy the request.
3. **Wrong StorageClass** — the PVC specifies `storageClassName: standard`, but the PV has `storageClassName: fast-storage`. Kubernetes only matches PVCs to PVs with the same StorageClass.

Since the PVC can't bind, the database pod stays in Pending state forever — it can't start without its storage.

## Thought Process

When a PVC is stuck in Pending, an experienced Kubernetes engineer checks:

1. **`kubectl describe pvc`** — the Events section tells you exactly why binding failed. Look for messages about "no persistent volumes available" with details about what didn't match.
2. **Compare PVC to available PVs** — use `kubectl get pv` to see what's available, then compare access modes, capacity, and StorageClass between the PVC and PV.
3. **Remember: PVCs are immutable for key fields** — you can't edit the access mode or StorageClass of an existing PVC. You must delete and recreate it.
4. **Three things must match for binding:** access mode, StorageClass, and the PV must have at least as much capacity as the PVC requests.

## Step-by-Step Solution

### Step 1: Apply the broken manifests (if not already applied)

```bash
kubectl apply -f manifests/broken/
```

**What this does:** Creates the PV, PVC, and database pod. The pod will stay in Pending because the PVC can't bind.

### Step 2: Check PVC status

```bash
kubectl get pvc db-pvc
```

**What this does:** Shows the PVC status. You'll see "Pending" in the STATUS column — confirming it hasn't bound to any PV.

### Step 3: Describe the PVC to see why it's pending

```bash
kubectl describe pvc db-pvc
```

**What this does:** Shows detailed information including Events. You'll see messages explaining that no PV matches the PVC's requirements. The events typically say something like "no persistent volumes available for this claim."

### Step 4: Compare the PV and PVC

```bash
kubectl get pv db-pv -o yaml
kubectl get pvc db-pvc -o yaml
```

**What this does:** Shows both resources side by side so you can spot the mismatches:
- PV: `accessModes: ReadWriteOnce`, `capacity: 10Gi`, `storageClassName: fast-storage`
- PVC: `accessModes: ReadWriteMany`, `requests: 20Gi`, `storageClassName: standard`

All three are different — that's why binding fails.

### Step 5: Delete the broken PVC

```bash
kubectl delete pvc db-pvc
```

**What this does:** Removes the pending PVC. Key fields like access mode and StorageClass can't be edited on an existing PVC, so we must delete and recreate it. The PV is unaffected — it's a separate resource.

### Step 6: Delete the pending pod

```bash
kubectl delete pod database
```

**What this does:** Removes the pod that was stuck waiting for the PVC. We'll recreate it after the PVC is fixed and bound.

### Step 7: Create the fixed PVC

```bash
cat > manifests/broken/pvc.yaml << 'EOF'
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
kubectl apply -f manifests/broken/pvc.yaml
```

**What this does:** Creates a new PVC that matches the PV on all three criteria:
- **`ReadWriteOnce`** (matches PV's access mode) — the volume can be mounted read-write by a single node
- **`storage: 10Gi`** (matches PV's capacity) — requesting exactly what the PV offers
- **`storageClassName: fast-storage`** (matches PV's StorageClass) — Kubernetes will only bind PVCs and PVs with the same StorageClass

### Step 8: Verify the PVC is now Bound

```bash
kubectl get pvc db-pvc
```

**What this does:** Shows the PVC status. It should now show "Bound" and display the PV name `db-pv` in the VOLUME column.

### Step 9: Recreate the database pod

```bash
kubectl apply -f manifests/broken/db-pod.yaml
```

**What this does:** Creates the database pod, which references the now-bound PVC. Since the PVC is bound, the pod can mount the volume and start successfully.

### Step 10: Verify the pod is running

```bash
kubectl get pod database
```

**What this does:** Confirms the database pod is in "Running" state with the persistent storage mounted.

## Docker Lab vs Real Life

- **Dynamic provisioning:** In production, you rarely create PVs manually. Instead, you use a StorageClass with a provisioner (like AWS EBS, GCE PD, or the local CSI driver) that automatically creates PVs when PVCs are created. The PVC just specifies the StorageClass and size, and the provisioner handles the rest.
- **Storage classes:** Production clusters have multiple StorageClasses for different performance tiers: `gp3` for general purpose, `io2` for high IOPS, `sc1` for cold storage on AWS. The StorageClass name in the PVC determines what type of storage is provisioned.
- **Volume expansion:** Modern StorageClasses support volume expansion. If a PVC needs more space, you can edit its size (increase only) and Kubernetes expands the underlying volume. This requires `allowVolumeExpansion: true` on the StorageClass.
- **StatefulSets:** For databases in production, you'd use a StatefulSet instead of a bare Pod. StatefulSets provide stable identities and automatically create PVCs for each replica. This is the standard pattern for stateful applications.
- **Backup:** Persistent volumes need backup strategies. On cloud providers, you'd use volume snapshots (VolumeSnapshot resources in Kubernetes) or application-level backups (like `pg_dump` for PostgreSQL).

## Key Concepts Learned

- **PVC-to-PV binding requires three things to match:** access mode, StorageClass, and sufficient capacity
- **`kubectl describe pvc` explains why binding failed** — the Events section gives specific reasons
- **PVCs are largely immutable** — you can't change access modes or StorageClass on an existing PVC. You must delete and recreate.
- **Access modes:** `ReadWriteOnce` (single node), `ReadOnlyMany` (many nodes read-only), `ReadWriteMany` (many nodes read-write). `ReadWriteOnce` is most common for databases.
- **StorageClass acts as a filter** — Kubernetes only considers PVs with a matching StorageClass when binding a PVC

## Common Mistakes

- **Trying to edit the PVC in place** — `kubectl edit pvc` won't let you change access modes or StorageClass. You must delete and recreate.
- **Requesting more storage than the PV has** — a PVC requesting 20Gi will never bind to a 10Gi PV, even if everything else matches.
- **Deleting the PV instead of the PVC** — if the PV has `persistentVolumeReclaimPolicy: Delete`, deleting the PV destroys the underlying storage data. Always fix the PVC to match the PV, not the other way around.
- **Mixing up access modes** — `ReadWriteMany` sounds more flexible, but most storage backends (like EBS) don't support it. Use `ReadWriteOnce` for databases unless you specifically need multi-node writes.
- **Forgetting to delete the stuck pod** — the pod was created with a direct reference to the PVC. After fixing the PVC, you may need to delete and recreate the pod for it to pick up the now-bound PVC.

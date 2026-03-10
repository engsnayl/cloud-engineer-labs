# Lab 038 — Node Scheduling Failed: Solution Walkthrough

---

## TLDR — What's Going On and How to Fix It

Your pods are stuck in **Pending** — they've been created, but Kubernetes can't find anywhere to put them.

There are two things blocking them:

1. **The pod is asking for a node label that doesn't exist.** The deployment says "only run on nodes with `disk-type=nvme`." No node in your cluster has that label. So the scheduler looks at every node, finds zero matches, and gives up.

2. **The pod doesn't have permission to run on tainted nodes.** One or more nodes have a taint — think of it as a "keep out unless invited" sign. The pod hasn't been invited (no matching toleration), so those nodes are off-limits too.

The fix is to remove the bad `nodeSelector` from the deployment, and add a toleration so the pod is allowed onto the tainted node. Once you do that, the scheduler can find valid nodes and the pods go from Pending to Running.

---

## The Problem in Detail

When pods are stuck in Pending, an experienced Kubernetes engineer follows this path:

1. **Read the Events** — `kubectl describe pod <name>` shows the scheduler's reasoning. Messages like "0/3 nodes are available: 3 node(s) didn't match Pod's node affinity/selector" tell you exactly what's wrong.
2. **Check node labels** — `kubectl get nodes --show-labels` shows what labels actually exist. Compare these with what the pod's `nodeSelector` requires.
3. **Check node taints** — `kubectl describe node <name> | grep Taint` shows taints. If a taint exists and the pod doesn't have a matching toleration, the scheduler skips that node.
4. **Decide whether to change the pod or the node** — you can label the node to match the selector, remove the selector, add a toleration, or remove the taint. The right choice depends on your cluster's intent.

---

## Step-by-Step Solution

### Step 1: Apply the broken manifests

```bash
kubectl apply -f manifests/broken/
```

**What this does:** Creates the `critical-service` deployment with the broken scheduling constraints. The pods will immediately enter Pending state.

| Part | Meaning |
|------|---------|
| `kubectl` | The Kubernetes command-line tool |
| `apply` | Create or update resources from a file (declarative — Kubernetes works out what needs changing) |
| `-f` | "From file" — specifies the file or folder to apply |
| `manifests/broken/` | The folder containing the broken YAML files |

---

### Step 2: Check the pod status

```bash
kubectl get pods -l app=critical-service
```

**What this does:** Lists all pods with the label `app=critical-service`. You'll see them stuck in `Pending` — STATUS column shows Pending, READY shows `0/1`.

| Part | Meaning |
|------|---------|
| `kubectl get pods` | List pods in the current namespace |
| `-l app=critical-service` | Filter by label — only show pods where `app=critical-service` is set |

---

### Step 3: Describe a pod to see why it's not scheduling

```bash
kubectl describe pod -l app=critical-service
```

**What this does:** Shows detailed information about the pod, including the Events section at the bottom. Look for a message like:

```
Warning  FailedScheduling  0/3 nodes are available: 3 node(s) didn't match Pod's node affinity/selector
```

This confirms the `nodeSelector` is the first problem — no nodes have the required label.

| Part | Meaning |
|------|---------|
| `kubectl describe pod` | Show full details about a pod (not just the summary table) |
| `-l app=critical-service` | Filter to pods with this label (same as above) |

---

### Step 4: Check what labels nodes actually have

```bash
kubectl get nodes --show-labels
```

**What this does:** Lists all nodes along with every label assigned to them. You'll see standard labels like `kubernetes.io/hostname` and `kubernetes.io/os` — but no `disk-type=nvme`. The pod is requiring something that simply doesn't exist on any node.

| Part | Meaning |
|------|---------|
| `kubectl get nodes` | List all nodes in the cluster |
| `--show-labels` | Add an extra column showing all labels on each node |

---

### Step 5: Check for taints on the nodes

```bash
kubectl describe nodes | grep -A2 "Taints:"
```

**What this does:** Scans the full description of all nodes and pulls out each `Taints:` line plus the two lines that follow it. You may see something like `dedicated=critical:NoSchedule`, which means: "don't schedule pods here unless they explicitly tolerate this taint."

| Part | Meaning |
|------|---------|
| `kubectl describe nodes` | Show full details for every node |
| `\|` | Pipe — sends the output of the left command into the right command |
| `grep` | Search through text for a pattern |
| `-A2` | "After 2" — show the 2 lines after each match (so you see the taint value, not just the label) |
| `"Taints:"` | The text pattern to search for |

---

### Step 6: Fix the deployment — remove nodeSelector and add toleration

```bash
cat > manifests/broken/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: critical-service
spec:
  replicas: 2
  selector:
    matchLabels:
      app: critical-service
  template:
    metadata:
      labels:
        app: critical-service
    spec:
      tolerations:
      - key: "dedicated"
        operator: "Equal"
        value: "critical"
        effect: "NoSchedule"
      containers:
      - name: app
        image: nginx:1.25-alpine
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
EOF
```

**What this does:** Overwrites the deployment YAML with a corrected version. Two changes have been made:

1. **`nodeSelector: disk-type: nvme` has been removed** — since no node has this label, removing the constraint allows the pod to be scheduled on any available node.
2. **A toleration has been added** — this tells the scheduler "this pod is allowed to run on nodes with the `dedicated=critical:NoSchedule` taint." The toleration must match the taint's `key`, `value`, and `effect` exactly.

| Part | Meaning |
|------|---------|
| `cat >` | Write output to a file (overwrites if it exists) |
| `manifests/broken/deployment.yaml` | The file being overwritten |
| `<< 'EOF'` | Heredoc syntax — everything that follows (until the closing `EOF`) is treated as the file content |
| `EOF` | Marks the end of the heredoc block |

---

### Step 7: Apply the fixed deployment

```bash
kubectl apply -f manifests/broken/deployment.yaml
```

**What this does:** Updates the deployment with the corrected spec. Kubernetes creates new pods using the fixed scheduling constraints.

| Part | Meaning |
|------|---------|
| `kubectl apply` | Apply the new state from the file — Kubernetes diffs the current state and updates only what's changed |
| `-f manifests/broken/deployment.yaml` | The specific file to apply |

---

### Step 8: Verify the pods are running

```bash
kubectl get pods -l app=critical-service
```

**What this does:** Shows the pods. They should now be in `Running` state — the nodeSelector no longer blocks, and the toleration allows placement on tainted nodes.

| Part | Meaning |
|------|---------|
| `kubectl get pods` | List pods |
| `-l app=critical-service` | Filter to only the critical-service pods |

---

## Alternative Approach: Label the Node Instead

If you want to keep the `nodeSelector` (because the app genuinely needs NVMe storage), you can label a node instead of removing the selector:

```bash
kubectl label node <node-name> disk-type=nvme
```

| Part | Meaning |
|------|---------|
| `kubectl label node` | Add or update a label on a node |
| `<node-name>` | The actual name of the node (get this from `kubectl get nodes`) |
| `disk-type=nvme` | The label key and value to apply |

**When to use this:** If the `nodeSelector` is intentional (the workload really does need specific hardware), label the appropriate node. If it was accidentally copied from another deployment, remove it from the pod spec.

---

## Real-World Context

- **nodeSelector vs nodeAffinity:** In production, you'd use `nodeAffinity` rather than `nodeSelector`. Node affinity supports "preferred" rules (soft constraints — try here, but not required) in addition to "required" rules (hard constraints). `nodeSelector` only does hard constraints.
- **Taints and tolerations in practice:** Production clusters commonly taint nodes to reserve them for specific workloads. GPU nodes are tainted so only ML workloads land there. Control plane nodes are tainted to keep application workloads off them.
- **Pod topology spread:** Production deployments also use `topologySpreadConstraints` to spread pods across availability zones for high availability.
- **Resource pressure:** In this lab, the only issue is labels and taints. In production, pods can also be Pending due to insufficient CPU or memory on available nodes — always check `kubectl describe node` for resource pressure too.

---

## Key Concepts

- **`nodeSelector` is a hard filter** — if no node has the required label, the pod stays Pending forever. There's no fallback.
- **Taints repel pods, tolerations allow them** — a taint says "keep pods away." A toleration says "I'm OK with this taint." Both must match on key, value, and effect.
- **`kubectl describe pod` explains scheduling failures** — the Events section tells you exactly why the scheduler couldn't place the pod.
- **You can fix from either side** — add labels/remove taints from nodes, or change selectors/add tolerations on pods.
- **Tolerations don't attract, they only allow** — a toleration doesn't mean "schedule me on tainted nodes." It means "I'm allowed to go there." The pod can still land on untainted nodes.

---

## Common Mistakes

- **Confusing nodeSelector with nodeAffinity** — `nodeSelector` is simple key-value matching only. `nodeAffinity` is more powerful with `requiredDuringScheduling` and `preferredDuringScheduling` options.
- **Mismatching toleration fields** — the toleration must match the taint's `key`, `value`, and `effect` exactly. A toleration for `dedicated=critical:NoExecute` won't match a taint of `dedicated=critical:NoSchedule` — different effect.
- **Forgetting that control plane nodes are tainted** — in most clusters, the control plane has `node-role.kubernetes.io/control-plane:NoSchedule`. Don't add a toleration for this in application workloads.
- **Using `operator: Exists` incorrectly** — `operator: Exists` matches any value for a key (omit the `value` field). `operator: Equal` requires an exact value match.
- **Not checking resource availability after fixing scheduling constraints** — even after fixing labels and taints, the pod might still be Pending if the node has insufficient CPU or memory.

---

## Pi / K3s Notes

**Single node only:** Your Raspberry Pi is the only node in the cluster, and it acts as both control plane and worker. All output will show `0/1 nodes` rather than `0/3 nodes` as you might see in a multi-node cluster example.

**Taint/toleration failure mode does not reproduce:** Running `kubectl describe nodes | grep -A2 "Taints:"` returns `Taints: <none>`. K3s deliberately removes the `node-role.kubernetes.io/control-plane:NoSchedule` taint that standard Kubernetes applies, so that workloads can run on the single node. This means Fault 2 (missing toleration) cannot be demonstrated in this environment — the only scheduling blocker you will actually observe is the `nodeSelector`.

**The toleration in the fixed manifest is still valid:** Adding a toleration for a taint that doesn't exist causes no errors — Kubernetes simply ignores it. The fix applies correctly even though the taint half of the fault isn't reproduced.

**Confirmed scheduling failure message:**
```
Warning  FailedScheduling  0/1 nodes are available: 1 node(s) didn't match Pod's node affinity/selector
```
This confirms the `nodeSelector: disk-type: nvme` was the sole active blocker — no node in the cluster has that label.

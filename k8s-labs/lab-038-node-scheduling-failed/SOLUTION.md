# Solution Walkthrough — Node Scheduling Failed

## The Problem

New pods for the `critical-service` deployment are stuck in **Pending** state and can't be scheduled to any node. There are two scheduling constraints blocking placement:

1. **`nodeSelector` requires a label no node has** — the deployment specifies `nodeSelector: disk-type: nvme`, but no node in the cluster has this label. The scheduler filters out every node because none match.
2. **Missing toleration for a node taint** — one or more nodes have a taint (`dedicated=critical:NoSchedule`), but the pod doesn't have a matching toleration. Taints repel pods that don't explicitly tolerate them.

The result: every node is either filtered out by the `nodeSelector` or repelled by the taint. The scheduler has zero candidates and the pods stay Pending indefinitely.

## Thought Process

When pods are stuck in Pending, an experienced Kubernetes engineer follows this path:

1. **Read the Events** — `kubectl describe pod <name>` shows the scheduler's reasoning. Messages like "0/3 nodes are available: 3 node(s) didn't match Pod's node affinity/selector" tell you exactly what's wrong.
2. **Check node labels** — `kubectl get nodes --show-labels` shows what labels actually exist. Compare these with what the pod's `nodeSelector` or `nodeAffinity` requires.
3. **Check node taints** — `kubectl describe node <name> | grep Taint` shows taints. If a taint exists and the pod doesn't have a matching toleration, the scheduler skips that node.
4. **Decide whether to change the pod or the node** — you can either label the node to match the selector, remove the selector, add a toleration, or remove the taint. The right choice depends on your cluster's scheduling policy.

## Step-by-Step Solution

### Step 1: Apply the broken manifests

```bash
kubectl apply -f manifests/broken/
```

**What this does:** Creates the `critical-service` deployment. The pods will immediately enter Pending state because no node satisfies the scheduling constraints.

### Step 2: Check the pod status

```bash
kubectl get pods -l app=critical-service
```

**What this does:** Shows all critical-service pods. You'll see them stuck in `Pending` — the STATUS column says Pending, and READY shows `0/1`.

### Step 3: Describe a pod to see why it's not scheduling

```bash
kubectl describe pod -l app=critical-service
```

**What this does:** Shows detailed scheduling information. The Events section at the bottom will show a message like:

```
Warning  FailedScheduling  0/3 nodes are available: 3 node(s) didn't match Pod's node affinity/selector
```

This tells you the `nodeSelector` is the first problem — no nodes have the required label.

### Step 4: Check what labels nodes actually have

```bash
kubectl get nodes --show-labels
```

**What this does:** Lists all nodes with their labels. You'll see labels like `kubernetes.io/hostname`, `kubernetes.io/os`, `node-role.kubernetes.io/control-plane`, etc. — but no `disk-type=nvme` label. The pod is requiring a label that doesn't exist on any node.

### Step 5: Check for taints on the nodes

```bash
kubectl describe nodes | grep -A2 "Taints:"
```

**What this does:** Shows all taints on all nodes. You may see a taint like `dedicated=critical:NoSchedule` on one or more nodes. This taint means: "don't schedule pods here unless they explicitly tolerate this taint."

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

**What this does:** Makes two changes to the pod spec:

1. **Removes `nodeSelector: disk-type: nvme`** — since no node has this label, removing the selector allows the pod to be scheduled on any node. Alternatively, you could label a node with `kubectl label node <name> disk-type=nvme`, but removing an unnecessary constraint is cleaner.
2. **Adds a toleration for `dedicated=critical:NoSchedule`** — this tells the scheduler: "this pod is OK with running on nodes that have the `dedicated=critical` taint." The toleration matches the taint's key, value, and effect exactly.

### Step 7: Apply the fixed deployment

```bash
kubectl apply -f manifests/broken/deployment.yaml
```

**What this does:** Updates the deployment. Kubernetes creates new pods with the corrected scheduling constraints.

### Step 8: Verify the pods are running

```bash
kubectl get pods -l app=critical-service
```

**What this does:** Shows the pods. They should now transition from Pending to Running because the scheduler can find suitable nodes — the nodeSelector no longer blocks, and the toleration allows placement on tainted nodes.

### Alternative approach: Label the node instead

If you want to keep the `nodeSelector` (maybe the app really does need NVMe storage), you can label a node instead:

```bash
kubectl label node <node-name> disk-type=nvme
```

**When to use this:** If the `nodeSelector` is intentional (the workload needs specific hardware), label the appropriate nodes. If it was an accidental constraint (copied from another deployment), remove it from the pod spec.

## Docker Lab vs Real Life

- **Node affinity vs nodeSelector:** In production, you'd use `nodeAffinity` instead of `nodeSelector`. Node affinity supports "preferred" rules (soft constraints) in addition to "required" rules (hard constraints). `nodeSelector` only supports hard constraints — either a node matches or it doesn't.
- **Taints and tolerations in practice:** Production clusters commonly taint nodes to reserve them for specific workloads. GPU nodes are tainted so only ML workloads (with matching tolerations) land there. Control plane nodes are tainted to prevent application workloads from running on them.
- **Pod topology spread:** In production, you'd also use `topologySpreadConstraints` to ensure pods are distributed across availability zones and nodes for high availability.
- **Descheduler:** In production, the descheduler can evict pods that no longer satisfy scheduling constraints (for example, if a node label is removed after scheduling).
- **Resource pressure:** In this lab, the only issue is labels and taints. In production, pods can also be Pending due to insufficient CPU, memory, or other resources on available nodes.

## Key Concepts Learned

- **`nodeSelector` is a hard filter** — if no node has the required label, the pod stays Pending forever. There's no fallback or timeout.
- **Taints repel pods, tolerations allow them** — a taint on a node says "keep pods away." A toleration on a pod says "I'm OK with this taint." Both must match (key, value, effect) for the pod to be scheduled.
- **`kubectl describe pod` explains scheduling failures** — the Events section tells you exactly why the scheduler couldn't place the pod.
- **You can fix from either side** — add labels/remove taints from nodes, or change selectors/add tolerations on pods. The right approach depends on the operational context.
- **Tolerations don't attract, they only allow** — a toleration doesn't mean "schedule me on tainted nodes." It means "I'm allowed to go there if the scheduler picks it." The pod can still land on untainted nodes.

## Common Mistakes

- **Confusing nodeSelector with nodeAffinity** — `nodeSelector` is simple key-value matching with no soft/preferred option. `nodeAffinity` is more powerful with `requiredDuringScheduling` and `preferredDuringScheduling` options.
- **Mismatching toleration fields** — the toleration must match the taint's `key`, `value`, and `effect` exactly. A toleration for `dedicated=critical:NoExecute` won't match a taint of `dedicated=critical:NoSchedule` — the effect is different.
- **Forgetting that control plane nodes are tainted** — in most clusters, the control plane node has `node-role.kubernetes.io/control-plane:NoSchedule`. Pods won't run there unless you add this toleration (which you generally shouldn't for application workloads).
- **Using `operator: Exists` incorrectly** — `operator: Exists` matches any value for a key (you omit the `value` field). `operator: Equal` requires an exact value match. Using the wrong operator can over-tolerate or under-tolerate.
- **Not checking resource availability after fixing scheduling constraints** — even after fixing labels and taints, the pod might still be Pending if the node doesn't have enough CPU or memory. Always check `kubectl describe node` for resource pressure too.

# Multi-Node K3s Cluster: Adding a Worker Node

## TLDR

We took an existing single-node K3s cluster running on a Raspberry Pi 4 and joined an old HP Pavilion laptop running Linux Mint as a second worker node. This created a two-node, mixed-architecture Kubernetes cluster (ARM64 control plane + x86_64 worker). We then deployed a two-replica nginx deployment to observe Kubernetes scheduling pods across both nodes, and simulated a node failure to watch Kubernetes self-heal by rescheduling the lost pod automatically.

---

## Why Would I Want Multiple Nodes?

This is the fundamental question, so let's answer it properly before touching any commands.

Kubernetes was designed to manage containers **across multiple machines**. That's its entire reason for existing. When you only have one node, you're using Kubernetes as a glorified Docker wrapper — it works, but you're missing the point.

Think of it this way: if you only have one shelf, you don't need a librarian to decide where books go. But if you have a thousand shelves across ten rooms, you absolutely do. Kubernetes is the librarian. With one node, it has no decisions to make.

### The three reasons production clusters have multiple nodes

**1. High Availability (self-healing)**

If a node crashes at 3am, Kubernetes notices that pods on that node are gone and spins up replacements on surviving nodes. No engineer gets paged. No manual intervention. This is the single most important feature of Kubernetes in production, and you **cannot observe it** on a single node — there's nowhere to reschedule to.

**2. Resource Distribution**

Different workloads need different things. A database wants fast disks. A web server wants lots of memory. A machine learning job wants a GPU. With multiple nodes, you can use **node selectors**, **taints**, and **affinities** to control which workloads land where. With one node, these concepts are just theory.

**3. Isolation**

In a real environment, you might want production workloads on dedicated nodes, completely separate from development tools or monitoring stacks. Taints and tolerations enforce this boundary — you mark a node as "production only" and Kubernetes refuses to schedule anything else there unless explicitly allowed.

### How does this relate to AWS autoscaling?

They're different layers, not alternatives. They usually work **together**:

| Layer | What it does | Who manages it |
|-------|-------------|----------------|
| **Cloud autoscaling** | "Do I have enough servers?" — adds/removes EC2 instances based on demand | AWS Auto Scaling Groups / Cluster Autoscaler |
| **Kubernetes scheduling** | "Where should this container run?" — places pods on available nodes | kube-scheduler |

In production: Kubernetes tries to schedule a pod → all nodes are full → it tells the cluster autoscaler "I need more capacity" → AWS spins up a new EC2 instance → the instance joins the cluster → Kubernetes schedules the pod there.

Your homelab is the Kubernetes layer only. Your Pi and laptop are fixed — they're always on or off. In AWS, that bottom layer stretches and shrinks based on demand, which is where cost efficiency comes from.

---

## What We Started With

- **Raspberry Pi 4** (ARM64/aarch64) running K3s v1.34.4+k3s1 as a single-node control plane
- The Pi has been running for 50 days
- **HP Pavilion 15 laptop** (x86_64) running Linux Mint, connected to the same local network
- SSH access to both machines from a work laptop

---

## Step 1: Confirm the Control Plane is Healthy

Before adding a worker, we need to verify the existing cluster is in good shape.

**On the Pi:**

```bash
sudo k3s kubectl get nodes
```

**Output:**

```
NAME   STATUS   ROLES           AGE   VERSION
pi     Ready    control-plane   50d   v1.34.4+k3s1
```

We're looking for `Ready` status and the `control-plane` role. If this showed `NotReady`, we'd need to troubleshoot before adding another node.

### What does "control plane" actually mean?

The control plane is the brain of the cluster. It runs several components:

| Component | What it does |
|-----------|-------------|
| **kube-apiserver** | The front door. Every `kubectl` command talks to this. It listens on port 6443. |
| **etcd** | The database. Stores all cluster state — what pods exist, what nodes are available, what deployments are defined. |
| **kube-scheduler** | The matchmaker. When a new pod needs to run, the scheduler picks which node it goes on. |
| **kube-controller-manager** | The supervisor. Constantly checks "is reality matching what was requested?" and takes corrective action. |

Worker nodes don't run any of these. They just run the **kubelet** (an agent that takes instructions from the control plane) and the actual containers.

---

## Step 2: Check the Laptop's Architecture

**On the laptop:**

```bash
uname -m
```

**Output:**

```
x86_64
```

This matters because our Pi is ARM64 and the laptop is x86_64. We're creating a **mixed-architecture cluster**. Most container images (like nginx) are built for both architectures (multi-arch images), so this usually just works. But if you tried to run an ARM-only image, Kubernetes would schedule it onto the laptop, and it would crash with an exec format error.

This is actually an interesting interview talking point — mixed-arch clusters exist in production when companies run edge devices (ARM) alongside data centre servers (x86).

---

## Step 3: Get the Join Token

For a worker node to join the cluster, it needs two things:

1. **The control plane's IP address** — so it knows where to connect
2. **A token** — so the control plane trusts it and allows it to join

**On the Pi, get the token:**

```bash
sudo cat /var/lib/rancher/k3s/server/node-token
```

**Output:**

```
K104ff68fc894460ad3ab3d14ef47c7c9843a3ee837e0dbe9a52fee15ece2940b14::server:d8665e5468f4cdae1dd76a359f6c6955
```

**Get the Pi's LAN IP:**

```bash
hostname -I
```

**Output:**

```
192.168.0.101 172.17.0.1 172.30.0.1 ...
```

The first address (`192.168.0.101`) is the LAN IP. The rest are Docker bridge networks and K3s pod networks — internal to the Pi, not relevant here.

### Command Breakdown: `hostname -I`

| Part | What it does |
|------|-------------|
| `hostname` | Shows or sets the system hostname |
| `-I` | (capital i) Lists all network IP addresses assigned to the host, excluding loopback (127.0.0.1) |

---

## Step 4: Join the Laptop as a Worker Node

**On the laptop:**

```bash
curl -sfL https://get.k3s.io | K3S_URL=https://192.168.0.101:6443 K3S_TOKEN=K104ff68fc894460ad3ab3d14ef47c7c9843a3ee837e0dbe9a52fee15ece2940b14::server:d8665e5468f4cdae1dd76a359f6c6955 sh -
```

### Command Breakdown

| Part | What it does |
|------|-------------|
| `curl -sfL https://get.k3s.io` | Downloads the K3s install script. `-s` = silent, `-f` = fail on HTTP errors, `-L` = follow redirects. |
| `\|` | Pipes the downloaded script into `sh` to execute it |
| `K3S_URL=https://192.168.0.101:6443` | Tells the installer this is an **agent** (worker), not a server. Points at the control plane's API server on port 6443. |
| `K3S_TOKEN=...` | The authentication token. Without this, the control plane would reject the join request. |
| `sh -` | Runs the piped script. The `-` tells `sh` to read from stdin. |

When `K3S_URL` is set, the installer knows to install the **agent** binary, not the full server. The agent only runs the kubelet and container runtime — no API server, no etcd, no scheduler.

**Output:**

```
[INFO]  Using v1.34.6+k3s1 as release
[INFO]  Downloading binary https://github.com/k3s-io/k3s/releases/download/v1.34.6+k3s1/k3s
[INFO]  Installing k3s to /usr/local/bin/k3s
[INFO]  Creating /usr/local/bin/k3s-agent-uninstall.sh
[INFO]  systemd: Enabling k3s-agent unit
[INFO]  systemd: Starting k3s-agent
```

Key things to notice:

- It downloaded `k3s` (the amd64 binary, since the laptop is x86_64)
- It created a **systemd service** (`k3s-agent.service`), meaning the agent starts automatically on boot
- It created an **uninstall script** at `/usr/local/bin/k3s-agent-uninstall.sh` for clean removal
- The version is v1.34.6 while the Pi runs v1.34.4 — this minor version skew is fine, Kubernetes supports it within the same minor release

---

## Step 5: Verify the Two-Node Cluster

**On the Pi** (all kubectl commands go through the control plane):

```bash
sudo k3s kubectl get nodes
```

**Output:**

```
NAME                                 STATUS   ROLES           AGE   VERSION
pi                                   Ready    control-plane   50d   v1.34.4+k3s1
stephen-hp-pavilion-15-notebook-pc   Ready    <none>          26s   v1.34.6+k3s1
```

Two nodes, both `Ready`. The laptop shows `<none>` for roles because K3s doesn't automatically label agent nodes. The Pi shows `control-plane` because it runs the API server and scheduler.

### Why do all kubectl commands run on the Pi, not the laptop?

`kubectl` talks to the **Kubernetes API server**, which only runs on the control plane (the Pi). The laptop is a worker — it receives instructions, it doesn't issue them. This is like a restaurant: the kitchen (worker) doesn't take orders from customers. The front of house (control plane) takes orders and tells the kitchen what to cook.

You *could* run kubectl from the laptop or any other machine, but you'd need to copy the kubeconfig file and point it at the Pi's IP. The commands would still be processed by the Pi's API server.

---

## Step 6: Observe Multi-Node Scheduling

Now let's see Kubernetes make scheduling decisions across two nodes.

```bash
sudo k3s kubectl create deployment nginx-test --image=nginx --replicas=2
sudo k3s kubectl get pods -o wide
```

**Output:**

```
NAME                          READY   STATUS    AGE   NODE
nginx-test-586bbf5c4c-cv5cd   1/1     Running   pi
nginx-test-586bbf5c4c-jrsq4   1/1     Running   stephen-hp-pavilion-15-notebook-pc
```

(Simplified for clarity — the actual output includes IP addresses and other columns.)

### What just happened?

1. You told Kubernetes: "I want a deployment called nginx-test with 2 replicas"
2. The **deployment controller** (part of kube-controller-manager) created a **ReplicaSet**
3. The ReplicaSet created 2 **pods**
4. The **kube-scheduler** looked at both nodes, evaluated available CPU and memory on each, and decided to place one pod on each node

**You didn't tell it where to put them.** You said *what* you wanted (2 replicas), and Kubernetes figured out *how* to achieve it. This is **declarative management** — you declare the desired state, Kubernetes makes it happen.

### Command Breakdown: `kubectl get pods -o wide`

| Part | What it does |
|------|-------------|
| `kubectl get pods` | Lists all pods in the current namespace |
| `-o wide` | Wide output format — adds extra columns including NODE (which node the pod is running on) and IP (the pod's internal IP address) |

Without `-o wide`, you wouldn't see which node each pod landed on.

---

## Step 7: Simulate a Node Failure (Self-Healing)

This is the most important demonstration. We're going to kill the laptop's K3s agent and watch Kubernetes recover.

**On the laptop:**

```bash
sudo systemctl stop k3s-agent
```

**On the Pi — check nodes:**

```bash
sudo k3s kubectl get nodes
```

**Output:**

```
NAME                                 STATUS     ROLES           AGE   VERSION
pi                                   Ready      control-plane   50d   v1.34.4+k3s1
stephen-hp-pavilion-15-notebook-pc   NotReady   <none>          11m   v1.34.6+k3s1
```

The laptop is `NotReady`. Kubernetes has detected the failure. But it doesn't react immediately — there's a **5-minute tolerance period** (called the `pod-eviction-timeout`). This exists because in production, a brief network blip shouldn't trigger unnecessary pod rescheduling. Imagine if every Wi-Fi dropout caused all your containers to restart — that would cause more disruption than the blip itself.

**After ~5 minutes, check pods:**

```bash
sudo k3s kubectl get pods -o wide
```

**Output:**

```
NAME                          READY   STATUS        NODE
nginx-test-586bbf5c4c-cv5cd   1/1     Running       pi
nginx-test-586bbf5c4c-jrsq4   1/1     Terminating   stephen-hp-pavilion-15-notebook-pc
nginx-test-586bbf5c4c-nmv5c   1/1     Running       pi
```

### What just happened — step by step

1. **The kubelet on the laptop stopped sending heartbeats** to the control plane
2. **The node controller** (part of kube-controller-manager) noticed the missing heartbeats and marked the node `NotReady`
3. **It waited ~5 minutes** (the eviction timeout) to make sure this wasn't a temporary glitch
4. **It evicted the pod** (`jrsq4`) — marked it as `Terminating`
5. **The ReplicaSet controller** noticed: "I'm supposed to have 2 running replicas, but now I only have 1"
6. **It created a new pod** (`nmv5c`) to restore the desired count
7. **The scheduler** placed the new pod on the Pi — the only available node

This is **desired state reconciliation** — the core concept of Kubernetes. You declared "I want 2 replicas." A node died. Kubernetes restored your desired state without any human intervention.

### What does NOT happen when the node comes back?

When you restart the agent (`sudo systemctl start k3s-agent`), the laptop rejoins as `Ready`. But Kubernetes **does not move pods back** to it. It only acts when something is wrong, not when something gets better. The two replicas stay on the Pi because the desired state (2 running replicas) is already satisfied.

This is worth knowing for interviews — Kubernetes is reactive to problems, not proactive about rebalancing (unless you configure a tool like the **descheduler**).

---

## Key Concepts Summary

### Desired State Reconciliation

You tell Kubernetes **what** you want. Kubernetes figures out **how** to make it happen and continuously works to maintain it. If reality drifts from the desired state (a node dies, a pod crashes, a container runs out of memory), Kubernetes takes corrective action automatically.

### Control Plane vs Worker Nodes

| | Control Plane | Worker Node |
|---|---|---|
| **Runs** | API server, scheduler, controller manager, etcd | Kubelet, container runtime, your actual workloads |
| **Purpose** | Makes decisions | Executes decisions |
| **kubectl talks to** | Yes (port 6443) | No (indirectly, via control plane) |
| **If it dies** | Cluster is unmanageable (but running pods keep running) | Pods get rescheduled elsewhere |

### The Scheduling Decision

When a new pod needs to run, the scheduler evaluates:

1. **Does the node have enough resources?** (CPU, memory)
2. **Does the node match any node selectors or affinity rules?**
3. **Is the node tainted in a way that would prevent this pod?**
4. **Which node gives the best resource balance across the cluster?**

With one node, all of these questions have the same answer. With multiple nodes, the scheduler actually has work to do.

### Mixed Architecture

Our cluster has ARM64 (Pi) and x86_64 (laptop) nodes. Container images must support the target architecture. **Multi-arch images** (like nginx) include binaries for both and Kubernetes pulls the right one automatically. Single-arch images will fail with an exec format error if scheduled to the wrong node.

---

## Cleanup

**Delete the test deployment (on the Pi):**

```bash
sudo k3s kubectl delete deployment nginx-test
```

**Bring the laptop back (if stopped), then uninstall the agent (on the laptop):**

```bash
sudo systemctl start k3s-agent
sudo /usr/local/bin/k3s-agent-uninstall.sh
```

**Remove the stale node record (on the Pi):**

```bash
sudo k3s kubectl delete node stephen-hp-pavilion-15-notebook-pc
```

The uninstall script on the laptop cleanly removes:

- The K3s agent binary
- The systemd service
- Any containers that were running
- The killall script

After cleanup, your Pi is back to being a single-node cluster, exactly as it was before.

---

## Lab vs Real Life

| In this lab | In production |
|---|---|
| 2 nodes on a home network | Hundreds or thousands of nodes across data centres |
| Manual join with a token | Nodes join via cloud autoscaling groups (Terraform, CloudFormation) |
| We stopped the agent to simulate failure | Nodes fail due to hardware issues, network partitions, kernel panics |
| 5-minute eviction timeout | Often configured shorter (30s-2min) for faster recovery |
| No persistent storage | Pods use PersistentVolumes backed by EBS, NFS, or Ceph |
| ServiceLB for external access | Cloud load balancers (ALB/NLB) or Ingress controllers |
| Mixed arch (ARM + x86) is a curiosity | Mixed arch exists in edge computing scenarios |
| We ran kubectl from the control plane | Teams use CI/CD pipelines and GitOps (ArgoCD, Flux) to manage deployments |

# Lab 078 — EKS Nodes Not Joining Cluster
## Solution Walkthrough

---

## TLDR (Plain English)

You've been handed a ticket: an EKS Kubernetes cluster has been deployed with Terraform but the worker nodes won't join. The cluster exists, but it's empty — no nodes are available to run workloads.

The root cause is an IAM mistake. Worker nodes in EKS are EC2 virtual machines. For an EC2 instance to communicate with AWS services (including the EKS control plane), it needs an IAM role that EC2 is allowed to use. The Terraform config is pointing the nodes at the *cluster's* IAM role — which was designed for EKS itself, not EC2 instances. EC2 can't assume that role, so the node group fails to create entirely.

There are three things to fix in the IAM configuration, plus the networking backbone needed completing to give nodes a route out to AWS endpoints:

1. **The node group is pointing at the wrong IAM role** — it's using the cluster role instead of a dedicated node role
2. **No node IAM role exists at all** — one needs to be created with the correct trust policy for EC2
3. **The node group is missing an `instance_types` declaration** — this should always be explicit
4. **The networking backbone was incomplete** — no Internet Gateway, route table, or public IP assignment on subnets

**The fix:** Complete the networking, create a new IAM role for EC2 nodes, attach the three AWS managed policies that EKS nodes require, and update the node group to reference the new role.

---

## Background Theory

### Why do EKS nodes need their own IAM role?

In AWS, when an EC2 instance wants to make API calls — to register itself with the EKS cluster, pull container images, or manage networking — it needs to prove who it is. It does this by assuming an IAM role. That role must explicitly trust EC2 as a service principal.

The EKS *cluster* also has an IAM role — but that one trusts `eks.amazonaws.com`, not `ec2.amazonaws.com`. The two roles serve completely different purposes:

| Role | Trusts | Used by |
|---|---|---|
| Cluster role | `eks.amazonaws.com` | The EKS control plane (Kubernetes API server) |
| Node role | `ec2.amazonaws.com` | Worker node EC2 instances |

Pointing nodes at the cluster role is like handing a staff ID badge to a delivery driver — wrong person, wrong door. AWS will reject it immediately and tell you exactly why.

### The three required managed policies for EKS nodes

Every EKS worker node role needs exactly these three AWS managed policies attached. This is documented by AWS and is the same for every EKS cluster regardless of size or configuration:

| Policy | What it does |
|---|---|
| `AmazonEKSWorkerNodePolicy` | Lets the node register with the cluster and report health status |
| `AmazonEKS_CNI_Policy` | Lets the VPC CNI plugin assign IP addresses to pods |
| `AmazonEC2ContainerRegistryReadOnly` | Lets the node pull container images from ECR |

Missing any one of them causes a different failure mode. You wouldn't necessarily discover which one is missing from an error message alone — this is standard playbook knowledge, not something AWS error messages will walk you through. When setting up any EKS node role, treat all three as a mandatory checklist.

### Why does the cluster role also need a policy?

The cluster role needs `AmazonEKSClusterPolicy` attached — without it, the EKS control plane can't manage VPC resources on your behalf. This is separate from the node policies and is easy to overlook when writing EKS Terraform from scratch.

### Why does networking matter?

EKS worker nodes need outbound internet access to reach AWS service endpoints — the EKS API (to register), ECR (to pull images), and EC2 API (to report status). Nodes in subnets with no route to the internet will spin up, try to call home, get no response, and fail. The fix is an Internet Gateway, a route table with a default route, and subnets configured to assign public IPs.

---

## Investigative Walkthrough — The Real-Time Ticket

*You arrive at your desk. There's a ticket in the queue:*

> **"INCIDENT-AWS-010: EKS cluster 'production' deployed via Terraform but worker nodes are unavailable. Investigate and resolve."**

You have no other context. Here's how you work through this.

---

### Phase 1 — Orient Yourself Before Touching Anything

**Step 1 — Check your workspace**

```bash
cd ~/cloud-engineer-labs/cloud-labs/lab-078-eks-node-group
terraform workspace show
```

| Part | What it does |
|---|---|
| `terraform workspace show` | Confirms which Terraform workspace you're in |

> **Why this matters:** Running `terraform apply` in the wrong workspace can affect the wrong environment. Always check before doing anything. In this lab `default` is correct — there's only one environment.

**Step 2 — Initialise**

```bash
terraform init
```

| Part | What it does |
|---|---|
| `terraform init` | Downloads provider plugins and sets up the backend — required before any other Terraform command |

**Step 3 — Plan before applying**

```bash
terraform plan
```

Read the plan carefully before applying anything. At this stage look for:
- What role is `node_role_arn` referencing?
- Does a separate node role resource exist in the plan?
- Is `instance_types` declared on the node group?

> **What to spot at plan stage:** If `node_role_arn` references `aws_iam_role.cluster.arn` — flag it immediately. A node group should reference a *node* role, not a cluster role. If you catch this at plan stage you've already found Bug 1 before spending anything on infrastructure.

---

### Phase 2 — First Apply and the IAM Error

**Step 4 — Apply**

```bash
terraform apply
```

| Part | What it does |
|---|---|
| `terraform apply` | Creates the infrastructure described in your `.tf` files on AWS |

> **What happens:** The EKS cluster will create successfully — it takes around 6-8 minutes, which is normal for EKS. The node group creation will then fail immediately with this error:

```
Error: creating EKS Node Group (production:workers): InvalidParameterException:
Following required service principals [ec2.amazonaws.com] were not found
in the trust relationships of nodeRole arn:aws:iam::XXXXXXXXXXXX:role/eks-cluster-role
```

This is a well-designed AWS error message — it tells you exactly what it needed (`ec2.amazonaws.com`), exactly where it looked (the trust relationships of the role), and exactly which role it checked (`eks-cluster-role`). You don't need to guess what's wrong.

**What this tells you:**
- The cluster role only trusts `eks.amazonaws.com`
- EC2 worker nodes cannot assume it
- There is no separate node role with the correct trust policy

This is Bug 1 and Bug 3 surfacing together in a single error.

> **Important:** `terraform apply` reported the cluster creation as successful but the node group as failed. This is a *partial apply* — some resources exist in AWS, some do not. Before fixing and reapplying, decide whether to fix-and-reapply or destroy and start clean.

---

### Phase 3 — Partial Apply Recovery

**Step 5 — Assess the partial state**

```bash
terraform state list
```

| Part | What it does |
|---|---|
| `terraform state list` | Lists all resources Terraform currently has recorded in its state file |

This shows you what Terraform *thinks* exists. The cluster is in state — it exists in AWS and is costing money.

**Step 6 — Decide: fix-and-reapply or destroy?**

| Scenario | Approach |
|---|---|
| Only config changes needed, no broken AWS state | Fix and reapply |
| IAM changes involved, partial state in AWS | Destroy and reapply is safer |
| Lab environment | Always destroy — you want a clean repeatable run |

For this lab, destroy first. You can use a targeted destroy to remove just the failed resource without touching the cluster:

```bash
terraform destroy -target=aws_eks_node_group.workers
```

| Part | What it does |
|---|---|
| `terraform destroy` | Destroys infrastructure managed by this Terraform configuration |
| `-target=aws_eks_node_group.workers` | Scopes the destroy to just this one resource, leaving everything else intact |

Then destroy everything else:

```bash
terraform destroy
```

---

### Phase 4 — Apply the IAM Fixes and Hit the Networking Problem

After fixing the IAM issues and reapplying, you may encounter a second failure after a much longer wait — around 30 minutes:

```
NodeCreationFailure: Instances failed to join the kubernetes cluster
```

This error is far less helpful than the IAM error. It tells you something went wrong but not what. This is where systematic diagnosis matters.

**Step 7 — Check IAM is actually correct before blaming networking**

```bash
aws iam list-attached-role-policies \
  --role-name eks-node-role \
  --output json
```

| Part | What it does |
|---|---|
| `aws iam list-attached-role-policies` | Lists all managed policies attached to a named IAM role |
| `--role-name eks-node-role` | The node role you created |
| `--output json` | Returns structured JSON output |

> **What to look for:** All three policies should appear. If all three are present, IAM is not the problem — look at networking next.

**Step 8 — Check the node group health detail**

```bash
aws eks describe-nodegroup \
  --cluster-name production \
  --nodegroup-name workers \
  --query 'nodegroup.health' \
  --output json
```

| Part | What it does |
|---|---|
| `aws eks describe-nodegroup` | Fetches metadata and health for a specific node group |
| `--cluster-name production` | The parent EKS cluster name |
| `--nodegroup-name workers` | Matches the `node_group_name` in your Terraform |
| `--query 'nodegroup.health'` | Filters the response to the health block only |

**Step 9 — Understand the networking gap**

The subnets in the original `main.tf` have no outbound route to the internet. EKS nodes need to reach the EKS API endpoint, ECR, and the EC2 API — all public AWS endpoints. Without an Internet Gateway and route table, nodes are isolated. They spin up, try to call home, get no response, and AWS marks them `NodeCreationFailure` after ~30 minutes.

The fix requires adding to `main.tf`:
- `enable_dns_support` and `enable_dns_hostnames` on the VPC
- An Internet Gateway attached to the VPC
- A route table with a `0.0.0.0/0` route pointing to the IGW
- Route table associations for both subnets
- `map_public_ip_on_launch = true` on both subnets

---

### Phase 5 — State Drift

If your SSH session drops during a long apply, you may return to find state drift — where what Terraform recorded and what actually exists in AWS have diverged. AWS may have automatically rolled back some resources while Terraform's state file still thinks they exist.

**Step 10 — Detect state drift**

```bash
aws eks list-clusters --output json
terraform state list
```

If the cluster doesn't appear in AWS but is still in `terraform state list`, your state has drifted.

**Step 11 — Reconcile with terraform refresh**

```bash
terraform refresh
```

| Part | What it does |
|---|---|
| `terraform refresh` | Queries AWS for the actual current state of every resource in the state file and updates state to match reality |

After refreshing, run `terraform destroy` to cleanly remove whatever remains before reapplying.

> **Never run `terraform apply` into a drifted state without refreshing first** — Terraform may try to create resources that already exist, or reference resources that are gone.

---

### Phase 6 — Apply the Complete Fix

Here is the complete corrected `main.tf`:

```hcl
# EKS Node Group Lab

provider "aws" {
  region = "eu-west-2"
}

# ── VPC ────────────────────────────────────────────────────────────────────
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

# ── Internet Gateway ───────────────────────────────────────────────────────
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
}

# ── Subnets ────────────────────────────────────────────────────────────────
resource "aws_subnet" "a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = true
}

resource "aws_subnet" "b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "eu-west-2b"
  map_public_ip_on_launch = true
}

# ── Route Table ────────────────────────────────────────────────────────────
resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.a.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.b.id
  route_table_id = aws_route_table.main.id
}

# ── Cluster IAM Role ───────────────────────────────────────────────────────
resource "aws_iam_role" "cluster" {
  name = "eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ── EKS Cluster ────────────────────────────────────────────────────────────
resource "aws_eks_cluster" "main" {
  name     = "production"
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = [aws_subnet.a.id, aws_subnet.b.id]
  }

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]
}

# ── Node IAM Role ──────────────────────────────────────────────────────────
resource "aws_iam_role" "node" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# ── EKS Node Group ─────────────────────────────────────────────────────────
resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "workers"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = [aws_subnet.a.id, aws_subnet.b.id]
  instance_types  = ["t3.medium"]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
  ]
}
```

**What each fix addresses:**

| Fix | Addresses | Why |
|---|---|---|
| `enable_dns_support` + `enable_dns_hostnames` on VPC | Networking | Nodes need DNS to resolve AWS service endpoints |
| Internet Gateway + Route Table + `map_public_ip_on_launch` | Networking | Nodes need outbound internet access to reach EKS API, ECR, EC2 API |
| `AmazonEKSClusterPolicy` on cluster role + `depends_on` | Missing policy | Cluster can't manage VPC resources without it; depends_on prevents race condition |
| `aws_iam_role.node` with `ec2.amazonaws.com` trust | Bug 3 | Creates the dedicated node role with correct service principal |
| Three node managed policy attachments | Bug 3 | All three are mandatory — none are optional |
| `node_role_arn = aws_iam_role.node.arn` | Bug 1 | Points node group at the node role, not the cluster role |
| `instance_types = ["t3.medium"]` | Bug 2 | Explicit over implicit — no hidden defaults |
| `depends_on` on node group | Race condition | Node group waits for all three policy attachments to propagate |

---

### Phase 7 — Validate

```bash
lab validate 078
```

All checks should pass. Then confirm nodes are registered:

```bash
aws eks update-kubeconfig --name production --region eu-west-2
kubectl get nodes
```

| Part | What it does |
|---|---|
| `aws eks update-kubeconfig` | Adds credentials for this cluster to your local `~/.kube/config` |
| `--name production` | The cluster name as declared in Terraform |
| `--region eu-west-2` | The AWS region |
| `kubectl get nodes` | Lists all nodes registered with the Kubernetes control plane |

> **Expected output:** Two nodes listed as `Ready`. This confirms worker nodes have successfully registered with the control plane and are available for workload scheduling.

---

## Cleanup

> ⚠️ **Always run `terraform destroy` when finished. EKS clusters and node groups cost money.**

```bash
terraform destroy
```

Confirm with `yes` when prompted. EKS clusters take 1-2 minutes to destroy, node groups slightly longer.

**To reset the lab to its starting broken state:**

```bash
git checkout -- main.tf
git pull
```

| Part | What it does |
|---|---|
| `git checkout -- main.tf` | Discards local changes and reverts `main.tf` to the version stored in the repo |
| `git pull` | Pulls the latest version from GitHub to ensure you have the current starting state |

---

## Two Error Messages — A Study in Contrast

This lab produces two very different failure modes depending on which bug you hit:

| Failure | Error message | How helpful? | What to do |
|---|---|---|---|
| Wrong IAM trust policy | `required service principals [ec2.amazonaws.com] were not found in the trust relationships` | Very specific — tells you exactly what's missing and where | Fix the trust policy immediately |
| Nodes can't reach AWS endpoints | `NodeCreationFailure: Instances failed to join the kubernetes cluster` | Vague — tells you something failed but not why | Check IAM first, then check networking |

The first error is caught immediately at node group creation. The second only surfaces after 30+ minutes. This contrast is worth understanding — not all AWS errors are equal. Some tell you exactly what to fix; others require systematic diagnosis.

---

## State Drift — What It Is and How to Handle It

State drift happens when what Terraform has recorded in its state file no longer matches what actually exists in AWS. Common causes in this lab:

- SSH session drops during a long apply
- AWS automatically rolls back a failed resource
- A resource is manually deleted in the AWS console

**Detecting drift:**

```bash
terraform state list        # what Terraform thinks exists
aws eks list-clusters       # what actually exists in AWS
```

**Recovering:**

```bash
terraform refresh           # update state file to match AWS reality
terraform destroy           # clean up whatever remains
```

---

## Real World vs Lab

- **Managed node groups vs self-managed:** Managed node groups are standard for most teams — AWS handles EC2 provisioning, AMI updates, and graceful draining. Self-managed gives more control but adds significant operational burden.
- **Fargate:** EKS supports AWS Fargate — no nodes at all. Each pod gets isolated compute. No node role required, but pod execution roles must be configured instead.
- **Private subnets in production:** This lab uses public subnets for simplicity. Production EKS typically uses private subnets with a NAT Gateway — nodes get no public IPs but route outbound traffic via NAT. The trade-off is cost versus security.
- **Karpenter / Cluster Autoscaler:** Production clusters use auto-scaling to add and remove nodes based on pod scheduling demand.
- **EKS Add-ons:** Real clusters need managed add-ons: CoreDNS, kube-proxy, VPC CNI, EBS CSI driver. Forgetting these is a common early mistake.
- **EKS takes time:** Cluster creation is 6-10 minutes. Node group creation is another 10-20 minutes. Total apply time of 30+ minutes is normal.

---

## Key Concepts

- **Cluster role ≠ Node role.** The cluster role trusts `eks.amazonaws.com`. The node role trusts `ec2.amazonaws.com`. They are completely separate and cannot be swapped.
- **Three managed policies are mandatory for EKS nodes.** Worker, CNI, and ECR. Each covers a different subsystem. Missing any one breaks a different part of the system.
- **`depends_on` prevents IAM race conditions.** IAM is eventually consistent. Attach policies first, create resources second.
- **Networking is not optional.** Nodes need outbound internet access to reach AWS endpoints. No Internet Gateway means no node registration regardless of how correct your IAM is.
- **State drift is a real operational concern.** `terraform refresh` reconciles Terraform state with AWS reality.
- **Not all AWS errors are equally helpful.** IAM trust errors are specific and actionable. Node join failures are vague and require systematic diagnosis.

---

## Common Mistakes

- **Using the cluster role for nodes** — the classic mistake in this lab. EKS and EC2 trust policies are not interchangeable.
- **Missing one of the three managed policies** — all three are required. Each missing policy breaks a different subsystem.
- **Missing `AmazonEKSClusterPolicy` on the cluster role** — the cluster itself can't manage VPC resources without it.
- **No `depends_on` on the node group** — causes intermittent failures if the node group is created before IAM policies propagate.
- **No Internet Gateway or route table** — nodes can't reach AWS service endpoints without outbound internet access.
- **Forgetting `terraform destroy`** — EKS clusters are expensive. Always destroy after the lab.
- **Applying into drifted state** — always `terraform refresh` after a failed or interrupted apply before doing anything else.

---

## Lab Notes — Discovered During Live Run

- The original `main.tf` was missing the entire networking backbone. This was not an intentional bug — it was an omission that only surfaced when applying against real AWS. The starting `main.tf` has been updated so the only intentional bugs are the three IAM issues.
- `AmazonEKSClusterPolicy` was also missing from the cluster role in the original file. Added to both the fixed solution and the new starting `main.tf`.
- SSH session dropped during the 33-minute failed apply, causing state drift. `terraform refresh` was used to reconcile before destroying.
- AWS automatically rolled back the EKS cluster after the node group hit `CREATE_FAILED` but left VPC, subnets, and IAM resources intact.
- First failure (IAM trust error) was caught immediately with a specific, actionable error. Second failure (networking) took 33 minutes and gave a vague error — reinforcing why networking must be correct before applying.

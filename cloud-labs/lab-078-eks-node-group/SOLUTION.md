# Solution Walkthrough — EKS Nodes Not Joining Cluster

## The Problem

An EKS cluster is running but the managed node group nodes can't join. The worker nodes stay in a NotReady state. There are **three bugs**:

1. **Node group uses the cluster IAM role** — `node_role_arn` points to the EKS cluster role (which trusts `eks.amazonaws.com`), not a separate node role (which should trust `ec2.amazonaws.com`). Worker nodes are EC2 instances — they need an EC2-compatible role.
2. **Missing instance types** — the node group doesn't specify `instance_types`. While some versions default to `t3.medium`, explicitly setting it is a best practice and avoids unexpected defaults.
3. **Missing node IAM role entirely** — there's no separate IAM role for nodes. EKS worker nodes need their own role with three specific AWS managed policies: `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, and `AmazonEC2ContainerRegistryReadOnly`.

## Thought Process

When EKS nodes aren't joining the cluster, an experienced cloud engineer checks:

1. **Node IAM role** — worker nodes need their own IAM role (separate from the cluster role) with the correct trust policy (`ec2.amazonaws.com`) and three required managed policies.
2. **Node group configuration** — `node_role_arn`, `instance_types`, and `subnet_ids` must all be correct.
3. **Network connectivity** — nodes must be in subnets that can reach the EKS API endpoint. Private subnets need NAT Gateway access.
4. **Security groups** — the cluster and node security groups must allow communication between the control plane and worker nodes.

## Step-by-Step Solution

### Step 1: Fix Bug 3 — Create the node IAM role

```hcl
resource "aws_iam_role" "node" {
  name = "eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action = "sts:AssumeRole"
    }]
  })
}
```

**Why this matters:** EKS worker nodes are EC2 instances, so their role must trust `ec2.amazonaws.com`. The cluster role trusts `eks.amazonaws.com` — a completely different service. Using the cluster role for nodes means the EC2 instances can't assume it, and they can't authenticate to the cluster.

### Step 2: Attach the three required managed policies

```hcl
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
```

**Why this matters:** Each policy serves a specific purpose:
- **`AmazonEKSWorkerNodePolicy`** — allows nodes to connect to the EKS cluster and report status. Without it, nodes can't register with the control plane.
- **`AmazonEKS_CNI_Policy`** — allows the VPC CNI plugin to manage network interfaces for pod networking. Without it, pods can't get IP addresses.
- **`AmazonEC2ContainerRegistryReadOnly`** — allows nodes to pull container images from ECR. Without it, pods using ECR images fail to start.

All three are mandatory for functional EKS nodes.

### Step 3: Fix Bugs 1 & 2 — Update node group configuration

```hcl
# BROKEN
resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "workers"
  node_role_arn   = aws_iam_role.cluster.arn    # Wrong role!
  subnet_ids      = [aws_subnet.a.id, aws_subnet.b.id]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }
  # Missing instance_types!
}

# FIXED
resource "aws_eks_node_group" "workers" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "workers"
  node_role_arn   = aws_iam_role.node.arn       # Node role!
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

**Why this matters:**
- **`node_role_arn`** now references the node-specific role instead of the cluster role
- **`instance_types`** explicitly specifies `t3.medium` — a good default for general workloads
- **`depends_on`** ensures the IAM policy attachments are complete before the node group is created. Without this, the node group might be created before the policies are attached, causing nodes to fail to join.

### Step 4: Validate

```bash
terraform validate
terraform plan
```

## Docker Lab vs Real Life

- **EKS managed node groups vs self-managed:** Managed node groups (used in this lab) are easier — AWS handles node provisioning, updates, and draining. Self-managed node groups give more control but require managing launch templates, auto-scaling groups, and node updates yourself.
- **Fargate profiles:** EKS also supports Fargate, where you don't manage nodes at all. Each pod runs in its own isolated compute environment.
- **Node group updates:** In production, use managed node group update policies to control how nodes are replaced during AMI updates (rolling, blue-green).
- **Cluster autoscaler:** Production EKS clusters use Cluster Autoscaler or Karpenter to automatically add/remove nodes based on pod scheduling demand.
- **Add-ons:** Production clusters need add-ons: CoreDNS (DNS), kube-proxy (networking), VPC CNI (pod networking), EBS CSI driver (persistent storage). Managed add-ons simplify lifecycle management.

## Key Concepts Learned

- **EKS cluster role and node role are separate** — the cluster role trusts `eks.amazonaws.com`, the node role trusts `ec2.amazonaws.com`. They have different policies and serve different purposes.
- **Three managed policies are required for EKS nodes** — `AmazonEKSWorkerNodePolicy`, `AmazonEKS_CNI_Policy`, and `AmazonEC2ContainerRegistryReadOnly`. Missing any one prevents nodes from functioning correctly.
- **`depends_on` prevents race conditions** — IAM policy attachments are eventually consistent. Without `depends_on`, the node group might be created before policies take effect.
- **Worker nodes are EC2 instances** — they need EC2-compatible IAM roles, security groups, and network configuration. Don't confuse them with the EKS control plane.
- **Instance types should be explicitly set** — relying on defaults can lead to unexpected costs or capacity issues. Choose instance types based on your workload needs.

## Common Mistakes

- **Using the cluster role for nodes** — this is the exact mistake in this lab. The cluster role trusts EKS, not EC2. Nodes can't assume it.
- **Missing managed policy attachments** — all three policies are required. Missing `AmazonEKS_CNI_Policy` causes networking failures. Missing `AmazonEC2ContainerRegistryReadOnly` prevents image pulls.
- **Not using `depends_on` for IAM** — IAM changes are eventually consistent. Creating the node group before policies are fully attached can cause transient failures.
- **Nodes in subnets without NAT access** — if nodes are in private subnets, they need NAT Gateway access to reach the EKS API endpoint and ECR.
- **Security group misconfiguration** — the cluster security group must allow ingress from node security groups on port 443 (kubelet to API server) and ports 1025-65535 (API server to kubelet).

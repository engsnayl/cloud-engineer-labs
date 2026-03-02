# Hints — Cloud Lab 019: EKS Node Group

## Hint 1 — Nodes need their own IAM role
EKS worker nodes need a separate IAM role from the cluster. The trust policy must allow ec2.amazonaws.com, not eks.amazonaws.com.

## Hint 2 — Three required managed policies for nodes
AmazonEKSWorkerNodePolicy, AmazonEKS_CNI_Policy, and AmazonEC2ContainerRegistryReadOnly must be attached to the node role.

## Hint 3 — Node group configuration
Set `node_role_arn` to the new node role, and add `instance_types = ["t3.medium"]`.

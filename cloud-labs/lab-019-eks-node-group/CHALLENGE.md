Title: EKS Nodes Not Joining — Node Group Configuration
Difficulty: ⭐⭐⭐ (Advanced)
Time: 25-30 minutes
Category: AWS / EKS
Skills: EKS, managed node groups, IAM roles, VPC configuration, kubectl

## Scenario

The EKS cluster is running but the managed node group nodes aren't joining the cluster. The worker nodes can't communicate with the control plane.

> **INCIDENT-AWS-010**: EKS cluster 'production' has 0 ready nodes. Managed node group exists but nodes are in NotReady state. Suspect IAM or networking issue.

## How to Use This Lab

1. Review the Terraform files — find and fix the bugs
2. Run `terraform init && terraform plan` to see errors
3. Fix the issues in main.tf
4. Run `terraform plan` to verify no errors remain
5. (Optional) `terraform apply` if using a real AWS account or KodeKloud Playground

**Requires:** Terraform installed. AWS credentials for apply (optional — you can learn from plan alone).

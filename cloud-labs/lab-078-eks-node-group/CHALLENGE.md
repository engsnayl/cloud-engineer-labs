Title: EKS Nodes Not Joining — Node Group Configuration
Difficulty: ⭐⭐⭐ (Advanced)
Time: 25-30 minutes
Category: AWS / EKS
Skills: EKS, managed node groups, IAM roles, VPC configuration, kubectl

## Scenario

You have been handed a ticket. An EKS cluster has been deployed via 
Terraform but the worker nodes are not joining. No workloads can be 
scheduled.

> **INCIDENT-AWS-010**: EKS cluster 'production' deployed successfully 
> but worker nodes are unavailable. Investigate and resolve.

## Background Knowledge

Before starting, make sure you are comfortable with the following:

- **EKS worker nodes are EC2 instances.** They need their own IAM role 
  with a trust policy that allows `ec2.amazonaws.com` to assume it. This 
  is separate from the EKS cluster role.
- **Three AWS managed policies are required on every EKS node role** — 
  without all three, nodes cannot function correctly:

| Policy | What it enables |
|---|---|
| `AmazonEKSWorkerNodePolicy` | Node registers with the cluster and reports health |
| `AmazonEKS_CNI_Policy` | VPC CNI plugin assigns IP addresses to pods |
| `AmazonEC2ContainerRegistryReadOnly` | Node pulls container images from ECR |

  When reviewing any EKS node configuration, treating all three of these 
  as a checklist is standard practice. A missing policy will not always 
  produce an obvious error — some failures are silent until workloads 
  start failing.

- **The cluster role and the node role are not interchangeable.** The 
  cluster role trusts `eks.amazonaws.com`. The node role trusts 
  `ec2.amazonaws.com`. Using the wrong one is a common mistake.

## Objectives

1. Identify why the node group is failing to deploy
2. Create the correct IAM role and policy configuration for EKS worker nodes
3. Ensure all three required AWS managed policies are attached to the node role
4. Update the node group to reference the correct role with explicit instance types
5. `terraform validate` must pass
6. `terraform plan` must complete without errors

## How to Use This Lab

1. Run `terraform workspace show` — confirm your workspace before touching anything
2. Run `terraform init` to initialise the configuration
3. Run `terraform plan` — read the output carefully before applying anything
4. Review `main.tf` — identify what is missing or misconfigured
5. Apply your fixes to `main.tf`
6. Run `terraform apply` to deploy and observe what AWS tells you
7. Run `lab validate 078` to confirm all checks pass
8. Run `terraform destroy` when finished — **this lab creates real AWS 
   infrastructure that incurs costs**

## Important Notes

- **Always run `terraform destroy` when finished.** EKS clusters and node 
  groups cost money. Do not leave this running.
- **EKS cluster creation takes approximately 6 minutes.** Node group 
  creation takes additional time after that. This is normal.
- **AWS will tell you exactly what is wrong with your IAM configuration** 
  if the trust policy is incorrect — read error messages carefully, they 
  are specific.
- This lab requires real AWS credentials and will create billable 
  resources. `terraform plan` alone is safe and free.

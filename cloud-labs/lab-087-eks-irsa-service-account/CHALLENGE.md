Title: EKS Pod Can't Access AWS — IRSA Misconfigured
Difficulty: ⭐⭐⭐ (Advanced)
Time: 25-30 minutes
Category: AWS / EKS / IAM
Skills: EKS, IRSA (IAM Roles for Service Accounts), OIDC, Kubernetes service accounts, IAM trust policies, Terraform

## Scenario

An application pod in EKS needs to access an S3 bucket and a DynamoDB table. The team set up IAM Roles for Service Accounts (IRSA) but the pod is getting "Access Denied" on all AWS API calls. The OIDC provider, IAM role, and Kubernetes service account all exist but aren't wired up correctly.

> **INCIDENT-EKS-001**: Application pod logs showing "Unable to locate credentials" and "AccessDeniedException" when calling S3 and DynamoDB. IRSA was configured last sprint but never tested properly.

## Objectives

1. Fix the OIDC provider thumbprint configuration
2. Fix the IAM role trust policy to correctly reference the OIDC provider
3. Fix the IAM policy to grant the correct S3 and DynamoDB permissions
4. Fix the Kubernetes service account annotation to reference the IAM role
5. Fix the pod spec to use the correct service account
6. `terraform validate` must pass
7. `terraform plan` must complete without errors

**Requires:** Terraform installed. AWS credentials for apply (optional).

## Validation

Run `./validate.sh` or manually verify with `terraform plan`.

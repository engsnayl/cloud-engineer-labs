Title: EKS Pod Can't Access AWS — IRSA Misconfigured
Difficulty: ⭐⭐⭐ (Advanced)
Time: 45-60 minutes
Category: AWS / EKS / IAM
Skills: EKS, IRSA, OIDC federation, Kubernetes service accounts, IAM trust policies, Terraform

---

## ⚠️ COST WARNING — READ BEFORE STARTING ⚠️

This lab provisions **real AWS infrastructure** including:

- An **EKS cluster** (~$0.10/hr for the control plane)
- A **NAT Gateway** (~$0.045/hr, billed 24/7 until destroyed)
- A **t3.small worker node** (~$0.021/hr)

**Expected cost for a focused 1-hour run: ~£0.15.**
**Cost if left running overnight by accident: ~£4-5.**
**Cost if forgotten for a weekend: ~£10+.**

**You MUST run `./destroy.sh` when you finish the lab.** Do not close the laptop without running it. The script verifies nothing expensive remains.

---

## Scenario

An application pod in EKS needs to access an S3 bucket and a DynamoDB table. The team set up IAM Roles for Service Accounts (IRSA) last sprint but the pod is failing on every AWS API call. The OIDC provider, IAM role, service account, and pod all exist — but the chain isn't wired up correctly end-to-end.

> **INCIDENT-EKS-001**: Application pod logs showing "Unable to locate credentials" and "AccessDeniedException" when calling S3 and DynamoDB. IRSA was configured last sprint but never tested properly. Your job: get the pod working against S3 and DynamoDB, and make sure the IAM policy follows least privilege before handing it back to the security team for audit.

## Objectives

1. Deploy the infrastructure and pod as-is to reproduce the failure
2. Investigate and diagnose why the pod cannot assume the IAM role
3. Fix the OIDC provider client ID
4. Fix the IAM role trust policy to correctly reference the real OIDC issuer URL
5. Fix the Kubernetes ServiceAccount annotation to link it to the IAM role
6. Fix the pod spec to use the correct ServiceAccount
7. Tighten the IAM policy to follow least privilege (no wildcard resources)
8. Verify the pod can successfully list the S3 bucket and read from the DynamoDB table
9. **Destroy everything with `./destroy.sh`**

## Prerequisites

- AWS CLI configured with credentials that can create EKS, IAM, VPC, S3, DynamoDB resources
- Terraform >= 1.5
- `kubectl` installed
- `jq` installed (used by validator)

## Validation

Run `./validate.sh` after you believe everything is fixed. The validator checks the full chain — Terraform state, real AWS IAM configuration, Kubernetes manifests applied to the cluster, and the pod's actual ability to call S3 and DynamoDB successfully.

## Cleanup (MANDATORY)

```
./destroy.sh
```

This deletes K8s resources, empties the S3 bucket, runs `terraform destroy`, and verifies no EKS clusters, NAT Gateways, or OIDC providers remain.

## What You'll Practise

- Reading EKS cluster configuration and OIDC issuer URLs
- Understanding how IRSA wires AWS IAM to Kubernetes ServiceAccounts via JWT tokens
- Debugging IAM trust policies with condition keys
- Applying least privilege to workload IAM roles
- End-to-end verification of cloud-to-cluster identity federation

# Solution Walkthrough — EKS IRSA Misconfigured

## The Problem

IRSA (IAM Roles for Service Accounts) is broken at multiple points. There are **six bugs**:

1. **Wrong OIDC client ID** — should be "sts.amazonaws.com", not "ec2.amazonaws.com".
2. **Wrong trust policy condition key** — should use the full OIDC issuer URL as the condition key prefix.
3. **Wrong aud condition value** — should match the client ID "sts.amazonaws.com".
4. **IAM policy too permissive** — Resource "*" violates least privilege. Should reference specific bucket and table ARNs.
5. **Wrong service account annotation key** — IRSA uses `eks.amazonaws.com/role-arn`, not `iam.amazonaws.com/role`.
6. **Pod using default service account** — must specify the IRSA-annotated service account name.

## Step-by-Step Solution

### Step 1: Fix OIDC client ID
```hcl
client_id_list = ["sts.amazonaws.com"]  # Was: ec2.amazonaws.com
```

### Step 2: Fix trust policy condition keys
```hcl
Condition = {
  StringEquals = {
    "${local.oidc_issuer_stripped}:sub" = "system:serviceaccount:${local.namespace}:${local.sa_name}"
    "${local.oidc_issuer_stripped}:aud" = "sts.amazonaws.com"
  }
}
```

### Step 3: Scope IAM policy to specific resources
```hcl
# S3 statement
Resource = [
  aws_s3_bucket.app_data.arn,
  "${aws_s3_bucket.app_data.arn}/*"
]

# DynamoDB statement
Resource = aws_dynamodb_table.app_state.arn
```

### Step 4: Fix K8s service account annotation
```yaml
annotations:
  eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/eks-app-role
```

### Step 5: Fix pod serviceAccountName
```yaml
serviceAccountName: app-service-account  # Was: default
```

## Key Concepts Learned

- **IRSA uses OIDC federation** — EKS creates an OIDC identity provider. Pods get JWT tokens that AWS STS exchanges for temporary credentials.
- **The OIDC client ID must be sts.amazonaws.com** — this is the audience that STS expects in the JWT token.
- **Trust policy conditions must use the full OIDC URL** — the condition key format is `{oidc-issuer-url}:sub` and `{oidc-issuer-url}:aud`.
- **Least privilege applies to pod IAM too** — scope permissions to exactly the resources the pod needs.
- **Both Terraform AND Kubernetes config must be correct** — IRSA spans AWS IAM (Terraform) and Kubernetes (manifests). A bug in either side breaks the chain.

## Common Mistakes

- **Using kube2iam annotation format** — older tools used `iam.amazonaws.com/role`. IRSA uses `eks.amazonaws.com/role-arn`.
- **Forgetting to restart pods after annotation changes** — existing pods don't pick up new service account annotations. Delete and recreate them.
- **Wildcard resources in pod IAM policies** — a compromised pod with Resource "*" can access everything. Always scope.
- **Not verifying the OIDC thumbprint** — a wrong thumbprint means STS won't trust tokens from the OIDC provider.

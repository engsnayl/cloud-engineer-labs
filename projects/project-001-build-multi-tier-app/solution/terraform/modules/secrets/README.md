# Secrets Module

Provisions AWS Secrets Manager infrastructure for the multi-tier application, plus a least-privilege IAM identity for External Secrets Operator (ESO) to consume that secret from inside the K3s cluster.

## What this module creates

| Resource | Name |
|---|---|
| AWS Secrets Manager secret | `multi-tier/db` (configurable) |
| IAM user | `eso-multi-tier` (configurable) |
| IAM customer-managed policy | `eso-multi-tier-read-secret` |
| IAM policy attachment | binds the policy to the user |
| IAM access key | long-lived, for ESO authentication |

## What this module deliberately does NOT do

- **It does not write the secret value.** The `aws_secretsmanager_secret` resource creates an empty container; the password is populated out-of-band via `aws secretsmanager put-secret-value`. Putting the value in Terraform code would land it in the state file in plain text and (worse) in git if anyone ever inlines tfvars.
- **It does not bootstrap the K8s Secret holding the IAM access key.** That's an imperative step done once with `kubectl create secret` against the cluster. The bootstrap creates a single chicken-and-egg credential in K8s, after which ESO handles all further secret consumption.
- **It does not use an IAM role.** On real EKS we would use IRSA (IAM Roles for Service Accounts) — the ESO pod assumes a role via the cluster's OIDC provider, no static credentials. K3s has no OIDC provider available out-of-the-box, so we use the pragmatic prod-grade fallback: dedicated IAM user with an ARN-scoped policy. When this project moves to EKS in a later module, this module will be refactored to provision an IAM role with a trust policy bound to the ESO service account.

## Inputs

| Variable | Type | Default | Notes |
|---|---|---|---|
| `secret_name` | string | `multi-tier/db` | Path-style names are conventional for grouping. Validated against AWS-allowed characters. |
| `iam_user_name` | string | `eso-multi-tier` | Self-documenting IAM identity name. |
| `recovery_window_in_days` | number | `7` | Lab default. Production should use 30. Validated to enforce AWS-permitted range (0, or 7–30). |
| `tags` | map(string) | `{}` | Merged with module base tags and provider-level default tags. |

## Outputs

| Output | Sensitive | Purpose |
|---|---|---|
| `secret_arn` | no | Audit and IAM policy scoping. |
| `secret_name` | no | Referenced by the `ExternalSecret` manifest's `remoteRef.key`. |
| `iam_user_name` | no | CLI lookups and audit. |
| `iam_user_arn` | no | Audit. |
| `access_key_id` | no | Bootstrap into `aws-creds` K8s Secret. Access key IDs are not secrets — they identify the credential, they don't grant access on their own. |
| `access_key_secret` | **yes** | The actual credential half. **Note:** `sensitive = true` suppresses CLI display only; the value is still stored in plain text in the Terraform state file. State-file security depends on the S3 backend's encryption and bucket-level IAM, not on this flag. |

## Usage from the root module

```hcl
module "secrets" {
  source = "./modules/secrets"

  # All variables have sensible defaults; override only what you need.
  # secret_name             = "multi-tier/db"
  # iam_user_name           = "eso-multi-tier"
  # recovery_window_in_days = 7
}
```

## After `terraform apply` — operator workflow

This module gets you to the point where the AWS-side infrastructure exists. The remaining steps live outside Terraform:

1. **Populate the secret value out-of-band** (one-time, manual):

```bash
   aws secretsmanager put-secret-value \
     --secret-id multi-tier/db \
     --secret-string '{"username":"postgres","password":"<your-real-password>"}'
```

   The value is a JSON document because `ExternalSecret` in K8s will reference individual keys (`username`, `password`) within it.

2. **Bootstrap the IAM access key into the cluster** as a single imperative K8s Secret (one-time):

```bash
   kubectl create namespace external-secrets
   kubectl create secret generic aws-creds \
     --namespace external-secrets \
     --from-literal=access-key-id=$(terraform output -raw access_key_id) \
     --from-literal=secret-access-key=$(terraform output -raw access_key_secret)
```

3. **Install ESO** and apply the `ClusterSecretStore` + `ExternalSecret` manifests.

## Production differences

In real production, this module would change in several ways:

- **IRSA instead of IAM user.** Provision an IAM role with a trust policy keyed on the EKS cluster's OIDC provider and the ESO service account. No access keys anywhere.
- **Customer-managed KMS key on the secret.** AWS Secrets Manager always encrypts at rest, but using a CMK enables key-level audit, key rotation, and cross-account access patterns.
- **Rotation Lambda.** A `aws_secretsmanager_secret_rotation` resource with a rotation Lambda that talks to the database to rotate the password on a schedule. ESO would automatically propagate the new value to the cluster's K8s Secret.
- **`recovery_window_in_days = 30`** rather than 7. Bigger safety net against accidental deletion.
- **Cross-account access via resource-based policy.** If the cluster lived in a different AWS account than the secret, an `aws_secretsmanager_secret_policy` resource would grant cross-account `GetSecretValue`.

These are deliberately omitted here for lab ergonomics and ARM64 environment constraints; called out in the Module 3 SOLUTION doc.

## Interview question coverage

- `aws-026` — IAM users vs roles, and the K3s-without-OIDC reasoning for using a user here.
- `aws-027` — IAM policy types; this module uses a customer-managed policy, ARN-scoped to one secret, attached via a separate attachment resource.
- `k8s-030` — Why Kubernetes Secrets being base64 (not encrypted) means the source of truth for secret values belongs outside the cluster.
- `k8s-031` — External Secrets Operator's architecture and the AWS-side infrastructure it depends on.
- `tf-003` — Module structure: `versions.tf` / `variables.tf` / `main.tf` / `outputs.tf` / `README.md` as the standard layout.
- `tf-004` — Variable validation blocks (`secret_name`, `recovery_window_in_days`) and the critical nuance that `sensitive = true` on outputs is a UX feature, not a security control — the state file still holds the value in plain text.

# Hints — EKS IRSA Misconfigured

## Hint 1
IRSA uses OIDC federation. The client_id_list for EKS OIDC providers must include "sts.amazonaws.com".

## Hint 2
The trust policy condition keys must use the full OIDC issuer URL (without https://), not abbreviated forms.

## Hint 3
The :aud condition should match the client ID in the OIDC provider — "sts.amazonaws.com".

## Hint 4
IAM policies should follow least privilege. Use specific resource ARNs instead of "*".

## Hint 5
The Kubernetes service account annotation key for IRSA is `eks.amazonaws.com/role-arn`, and the pod must specify `serviceAccountName` matching the annotated service account.

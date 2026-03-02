# Hints — Cloud Lab 005: IAM Role Chain

## Hint 1 — Role assumption needs three things
1. The calling role needs `sts:AssumeRole` permission for the target. 2. The target role's trust policy must allow the calling role. 3. Any conditions (like ExternalId) must be satisfied.

## Hint 2 — Three bugs
1. The trust policy Principal references "wrong-role-name" instead of the app role. 2. The policy on the app role uses `iam:PassRole` instead of `sts:AssumeRole`. 3. If ExternalId is required, the caller must include it (or remove the condition).

## Hint 3 — Trust policy Principal
The trust policy should reference `aws_iam_role.app_role.arn` — use Terraform's resource reference instead of a hardcoded ARN.

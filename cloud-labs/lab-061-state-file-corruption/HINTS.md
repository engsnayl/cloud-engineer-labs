# Hints — Cloud Lab 002: State Drift

## Hint 1 — Run terraform plan
`terraform plan` shows you exactly what Terraform thinks needs to change. Read each change carefully — is it a real change or drift?

## Hint 2 — Refresh state
`terraform refresh` updates the state file to match reality. This resolves drift from console changes.

## Hint 3 — Handle deleted resources
If a resource was deleted manually, you need to remove it from state: `terraform state rm aws_security_group.app` and then re-import or recreate it.

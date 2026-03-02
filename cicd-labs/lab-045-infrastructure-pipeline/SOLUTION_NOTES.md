# Correct Terraform CI/CD Pattern

## PR workflow:
1. terraform fmt -check (formatting)
2. terraform init
3. terraform validate
4. terraform plan (save output)
5. Comment plan on PR

## Merge to main workflow:
1. terraform init
2. terraform plan
3. Manual approval (or auto-approve for non-destructive)
4. terraform apply

## Safety measures:
- Never auto-approve destroys
- Require PR approval before merge
- Lock state during operations
- Keep plan artifacts for audit

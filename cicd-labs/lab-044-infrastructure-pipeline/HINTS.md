# Hints — CI/CD Lab 044: Infrastructure Pipeline

## Hint 1 — Separate PR and merge workflows
Use `if: github.event_name == 'pull_request'` for plan-only steps and `if: github.ref == 'refs/heads/main' && github.event_name == 'push'` for apply.

## Hint 2 — Always init before plan/apply
terraform init must run before any other terraform command. Add `terraform fmt -check` and `terraform validate` as early quality gates.

## Hint 3 — Never auto-approve blindly
On PRs: run plan and save output. On merge: run plan, then apply with the saved plan file (or -auto-approve for trusted pipelines).

# Hints — Cloud Lab 013: Workspace Management

## Hint 1 — Use terraform.workspace
`terraform.workspace` returns the current workspace name (e.g., "staging" or "production").

## Hint 2 — Use a locals map
```hcl
locals {
  config = {
    staging    = { instance_type = "t3.micro", min_size = 1, max_size = 2 }
    production = { instance_type = "t3.large", min_size = 2, max_size = 10 }
  }
  env = local.config[terraform.workspace]
}
```

## Hint 3 — Reference the locals
`instance_type = local.env.instance_type` and `Environment = terraform.workspace` in tags.

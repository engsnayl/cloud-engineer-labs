# Hints — Cloud Lab 003: Module Dependency

## Hint 1 — Read the error messages
`terraform init && terraform plan` shows exactly which references are broken.

## Hint 2 — Check module names
The main.tf references `module.networking` but the module is defined as `module.vpc`. Also check the output names — does the VPC module actually export `private_subnet` or is it called something else?

## Hint 3 — Check the module outputs
Look at `./modules/vpc/outputs.tf` to see the actual output names and match your references to them.

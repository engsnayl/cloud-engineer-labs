Title: Secrets Not Available — Pipeline Credential Issues
Difficulty: ⭐⭐ (Intermediate)
Time: 12-15 minutes
Category: CI/CD / Secrets
Skills: environment variables, secrets management, build args, Docker secrets

## Scenario

The deployment pipeline can't access the credentials it needs. Secrets are configured in the CI system but not being passed to the right stages.

> **INCIDENT-CICD-002**: Docker build failing because AWS credentials aren't available. ECR push failing with "no credentials". Secrets exist in GitHub but aren't reaching the build steps.

## Objectives

1. Fix the pipeline so AWS credentials are available where needed
2. Credentials must NOT be baked into the Dockerfile (no `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` in the Dockerfile)
3. Secrets must NOT be passed as Docker build arguments
4. The workflow must use standard AWS credential environment variable names

## How to Use This Lab

1. Read the CHALLENGE.md for context
2. Examine the pipeline/workflow files
3. Find and fix the bugs
4. Run validate.sh to check your fixes

**Requires:** Understanding of CI/CD concepts. Some labs can be tested with `act` (local GitHub Actions runner) or Docker.

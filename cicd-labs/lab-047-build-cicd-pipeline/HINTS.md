# Hints — Lab 047: Build a CI/CD Pipeline from Scratch

## Hint 1 — Start with the file structure
GitHub Actions workflows live in `.github/workflows/`. Create that directory first:
```
mkdir -p .github/workflows
```
Your workflow file will be `.github/workflows/ci.yml`. Start with the `name:` and `on:` triggers.

## Hint 2 — Trigger events
You need the pipeline to run on both PRs and pushes to main. The `on:` block should include both `push` (to `main`) and `pull_request` (to `main`). Think about which stages should run on PRs vs only on pushes.

## Hint 3 — Job structure
Each stage (lint, test, build, deploy, smoke-test) can be a separate job with `needs:` to chain them in order. Or you can use a single job with multiple steps. Separate jobs give you better visibility in the GitHub UI and let you parallelise where possible.

## Hint 4 — Git SHA for image tags
GitHub Actions exposes `${{ github.sha }}` as the full commit SHA. Use this to tag your Docker image instead of `latest`. Why? Because `latest` tells you nothing about which version is running.

## Hint 5 — Conditional stages
Use `if: github.event_name == 'push' && github.ref == 'refs/heads/main'` on jobs that should only run on merges to main. Lint and test should run on every PR. Deploy and smoke test should only run on main.

## Hint 6 — The deploy script
Create a `deploy.sh` that pulls the new image and restarts the container. It should accept a version/tag as a parameter — never hardcode `latest`.

## Hint 7 — Smoke test pattern
After deploying, wait a few seconds for the container to start, then `curl` the health endpoint. If it returns a non-200 status, the pipeline should fail. A simple retry loop handles startup delay.

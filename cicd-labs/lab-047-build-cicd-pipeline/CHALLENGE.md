# Lab 047: Build a CI/CD Pipeline from Scratch

**Difficulty:** ⭐⭐⭐ (Advanced)  
**Time:** 30-40 minutes  
**Category:** CI/CD / Pipeline Design  
**Skills:** GitHub Actions, Docker, CI/CD stages, linting, testing, deployment, health checks

## Scenario

You've just joined a team. The application has no CI/CD at all — developers deploy by SSH-ing into the server and running `docker pull && docker run` manually. Every deploy is a dice roll. Last Friday someone fat-fingered a tag name and brought down production for 40 minutes.

Your tech lead has asked you to build a proper pipeline.

> **TICKET-CICD-047**: Build a CI/CD pipeline for the API service. Must include: lint, test, Docker build, deploy, and a post-deploy health check. No more manual deploys. Pipeline should fail fast if code quality checks don't pass.

## What You're Given

- A working Node.js API application in the `app/` directory
- A `Dockerfile` that builds the app
- A `package.json` with lint and test scripts already configured
- **No pipeline at all** — you're building from zero

## Objectives

1. Create a GitHub Actions workflow file at `.github/workflows/ci.yml`
2. The pipeline must have these stages, in this order:
   - **Lint** — run the linter, fail the pipeline if it doesn't pass
   - **Test** — run the unit tests, fail the pipeline if any test fails
   - **Build** — build the Docker image and tag it with the git commit SHA
   - **Deploy** — deploy the container (simulate with a deploy script)
   - **Smoke Test** — hit the health endpoint after deploy, fail if unhealthy
3. The deploy and smoke test stages must **only run on pushes to main** (not on PRs)
4. The Docker image tag must use the git SHA (not `latest`)
5. The pipeline must use environment variables for configuration (not hardcoded values)

## How to Use This Lab

1. Read this CHALLENGE.md and explore the `app/` directory
2. Create the `.github/workflows/ci.yml` file from scratch
3. Create a `deploy.sh` script that handles deployment
4. Run `validate.sh` to check your pipeline structure
5. Compare with SOLUTION.md when done

**This is a BUILD lab, not a troubleshooting lab.** There's nothing broken to fix — you're creating from zero. This is the lab you describe when an interviewer asks "walk me through your CI/CD pipeline."

**Requires:** Understanding of GitHub Actions syntax, Docker, shell scripting basics.

Title: Build Broken — Dockerfile Debugging
Difficulty: ⭐⭐ (Intermediate)
Time: 10-15 minutes
Category: Docker / Build
Skills: Dockerfile syntax, layer caching, multi-stage builds, build context

## Scenario

The CI pipeline is failing because the Docker image won't build. The Dockerfile has several issues introduced during a recent refactor.

> **INCIDENT-5620**: Docker build failing in CI. Multiple errors in Dockerfile. Dev team can't deploy until this is fixed. Dockerfile was recently refactored to use a new base image.

Fix the Dockerfile so the image builds successfully and the app runs.

## Objectives

1. Attempt to build the image and read the errors
2. Fix each Dockerfile issue
3. Successfully build the image
4. Run the container and verify the app works
5. Ensure the image is reasonably sized (multi-stage build if appropriate)

## Validation Criteria

- `docker build` completes without errors
- Container runs and app responds on port 8080
- Image name is 'webapp' with tag 'fixed'
- Container stays running for >5 seconds

## What You're Practising

Debugging Docker builds is a daily task. Understanding Dockerfile syntax, layer ordering, and build context is essential for maintaining CI/CD pipelines.

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

1. Fix the Dockerfile issues and build the image as `webapp:fixed`
2. Run the container from the fixed image
3. The application must respond on port 8080

## What You're Practising

Debugging Docker builds is a daily task. Understanding Dockerfile syntax, layer ordering, and build context is essential for maintaining CI/CD pipelines.

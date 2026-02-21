Title: Can't Pull Image — Registry Authentication Issues
Difficulty: ⭐⭐ (Intermediate)
Time: 10-15 minutes
Category: Docker / Registry
Skills: docker login, image tags, registry authentication, docker pull/push, image naming

## Scenario

The deployment is failing because Docker can't pull the application image. There are issues with the image naming, tagging, and a local registry that's not configured correctly.

> **INCIDENT-5760**: Deployment failing with "image not found". Local registry is running but Docker can't pull from it. Image naming or registry configuration issue.

## Objectives

1. Identify why docker pull is failing
2. Check the local registry is running and accessible
3. Fix the image naming/tagging
4. Push the image to the local registry
5. Pull it back to verify

## What You're Practising

Understanding container registries, image naming conventions, and authentication is essential for any container workflow. ECR, Docker Hub, and private registries all follow the same patterns.

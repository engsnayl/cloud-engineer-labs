Title: Image Too Large — Multi-Stage Build Optimisation
Difficulty: ⭐⭐ (Intermediate)
Time: 12-15 minutes
Category: Docker / Build Optimisation
Skills: multi-stage builds, image layers, .dockerignore, build cache, image size

## Scenario

The production Docker image is 1.2GB for a simple Go application. The build includes all compilation tools and source code. It needs to be optimised using multi-stage builds.

> **INCIDENT-5710**: Container registry running out of space. Production images are 1.2GB each. Need to reduce image size without changing the application. Target: under 50MB.

## Objectives

1. Implement a multi-stage build to reduce the image size
2. Build the image as `webapp:optimised` — target size under 100MB
3. Run the container and verify the application responds correctly

## What You're Practising

Image size directly impacts deployment speed, registry costs, and security surface area. Multi-stage builds are the standard technique for production Docker images.

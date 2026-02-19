# Hints — CI/CD Lab 041: Secrets Injection

## Hint 1 — Never bake secrets into images
Remove ALL ARG and ENV lines for credentials from the Dockerfile. Secrets should be injected at runtime, not build time.

## Hint 2 — Standard secret names
Use ${{ secrets.AWS_ACCESS_KEY_ID }} and ${{ secrets.AWS_SECRET_ACCESS_KEY }} — these are the standard names.

## Hint 3 — Runtime injection
For DATABASE_URL: pass it as an environment variable when running the container (ECS task def, docker run -e, K8s secret). Don't put it in the image.

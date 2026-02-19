# Hints — Lab 024: Container OOM Kill

## Hint 1 — Check the evidence
`docker inspect data-processor --format '{{.State.OOMKilled}}'` shows if OOM killed. `docker inspect data-processor --format '{{.HostConfig.Memory}}'` shows the memory limit in bytes.

## Hint 2 — The limit is too small
32MB (33554432 bytes) isn't enough. The workload needs ~128MB. Recreate with a larger limit.

## Hint 3 — Recreate with proper limits
`docker rm -f data-processor && docker run -d --name data-processor --memory=256m python:3.11-slim python3 -c "..."` (use the same command but with --memory=256m or higher).

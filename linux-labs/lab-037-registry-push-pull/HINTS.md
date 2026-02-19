# Hints — Lab 037: Registry Push/Pull

## Hint 1 — Check the registry
`curl http://localhost:5000/v2/_catalog` shows what's in the registry. It's probably empty.

## Hint 2 — Tag for the registry
Docker needs the full registry path in the tag: `docker tag myapp:latest localhost:5000/myapp:latest`

## Hint 3 — Push and verify
`docker push localhost:5000/myapp:latest` pushes to the local registry. Then `docker pull localhost:5000/myapp:latest` to verify.

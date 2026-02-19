# Hints — Lab 020: Docker Networking Broken

## Hint 1 — Inspect the networks
`docker network ls` shows all networks. `docker inspect backend-api --format '{{json .NetworkSettings.Networks}}'` shows which network a container is on.

## Hint 2 — Connect to the same network
You can either create a new shared network and connect both, or connect one container to the other's network. Use `docker network connect <network> <container>`.

## Hint 3 — Quick fix
`docker network create app-net && docker network connect app-net backend-api && docker network connect app-net frontend-web` puts them both on a shared network where DNS resolution works.

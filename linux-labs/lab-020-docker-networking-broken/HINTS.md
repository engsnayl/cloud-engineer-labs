# Hints — Lab 020: Containers Can't Talk

## Hint 1 — Confirm the problem first
From inside the lab container, try: `docker exec frontend-web curl -s http://backend-api:3000`. Does it work? What error do you get? This tells you whether the issue is DNS resolution, network connectivity, or something else.

## Hint 2 — Find out what networks exist
`docker network ls` shows all Docker networks. Then check which network each container is on: `docker inspect backend-api --format '{{json .NetworkSettings.Networks}}'` and do the same for frontend-web. Are they on the same network?

## Hint 3 — Docker DNS only works on custom bridge networks
Containers can only resolve each other's names when they share the same custom bridge network (not the default `bridge`). You can connect a container to an additional network without stopping it using `docker network connect`.

## Hint 4 — One command to fix it
Create a shared network and connect both: `docker network create app-net && docker network connect app-net backend-api && docker network connect app-net frontend-web`. Then test again with curl.

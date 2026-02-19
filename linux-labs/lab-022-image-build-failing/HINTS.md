# Hints — Lab 022: Image Build Failing

## Hint 1 — Try building it
`docker build -t webapp:fixed /opt/webapp/` — read the error messages carefully. They tell you exactly what's wrong.

## Hint 2 — Fix the base image
Node 23 doesn't exist. Use a valid tag like `node:20-alpine`. Then you need to COPY the package.json and app.js before running npm install.

## Hint 3 — Correct order
COPY package.json first, then npm install, then COPY app.js. This is also the optimal layer caching order. Then run with `docker run -d --name webapp webapp:fixed`.

# Hints — Lab 019: Container Won't Start

## Hint 1 — Check the logs and inspect
`docker logs payment-service` shows why it exited. `docker inspect payment-service` shows the image configuration including the entrypoint.

## Hint 2 — Compare filenames
Look at what files exist in /opt/payment-service/ — the app file is called `app.py`. Now look at the Dockerfile — does the COPY and ENTRYPOINT reference the correct filename?

## Hint 3 — Fix, rebuild, run
Fix the Dockerfile in /opt/payment-service/, rebuild with `docker build -t payment-service /opt/payment-service/`, then run with `docker run -d --name payment-service payment-service`.

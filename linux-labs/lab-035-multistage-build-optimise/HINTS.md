# Hints — Lab 035: Multi-Stage Build

## Hint 1 — The problem
`FROM golang:1.21` includes the entire Go toolchain (~800MB). You only need the compiled binary at runtime.

## Hint 2 — Multi-stage pattern
```dockerfile
FROM golang:1.21 AS builder
WORKDIR /app
COPY . .
RUN go build -o server main.go

FROM alpine:3.18
COPY --from=builder /app/server /server
EXPOSE 8080
CMD ["/server"]
```

## Hint 3 — Build and run
`docker build -t webapp:optimised /opt/webapp/` then `docker run -d --name webapp-opt webapp:optimised`

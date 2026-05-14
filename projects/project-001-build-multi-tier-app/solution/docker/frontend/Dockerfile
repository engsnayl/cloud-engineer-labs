# syntax=docker/dockerfile:1.7

FROM alpine:3.20 AS builder
WORKDIR /build
RUN apk add --no-cache gzip
COPY index.html .
RUN gzip -k -9 index.html

FROM nginx:1.27-alpine AS runtime
RUN apk add --no-cache tini \
    && addgroup -S app -g 1000 \
    && adduser  -S app -G app -u 1000 \
    && mkdir -p /var/log/nginx /var/cache/nginx /tmp \
    && chown -R app:app /var/log/nginx /var/cache/nginx /usr/share/nginx/html /tmp

COPY --from=builder /build/index.html    /usr/share/nginx/html/index.html
COPY --from=builder /build/index.html.gz /usr/share/nginx/html/index.html.gz
COPY nginx.conf /etc/nginx/nginx.conf

USER app
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget --quiet --spider http://localhost:8080/healthz || exit 1

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["nginx", "-g", "daemon off;"]

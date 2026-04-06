# =============================================================================
# Dockerfile — Frontend (Nginx) container image definition
# =============================================================================
# This is much simpler than the backend Dockerfile because we're just
# serving static files (HTML, CSS, JS) and proxying API requests.
# There's no application runtime to install — nginx does everything.
# =============================================================================

# ---------------------------------------------------------------------------
# BASE IMAGE — nginx:1.25-alpine
# ---------------------------------------------------------------------------
# Why Alpine?
#   - Alpine Linux is a tiny Linux distribution (~5MB base). Combined with
#     nginx, the total image is only ~40MB vs ~150MB for Debian-based nginx.
#   - For a web server that just serves static files and proxies requests,
#     Alpine is perfect — we don't need extra system libraries.
#   - Unlike Python packages, nginx doesn't have musl/glibc compatibility
#     issues on Alpine, so there's no downside here.
#   - This image supports linux/arm64 (Raspberry Pi 5 compatible).
FROM nginx:1.25-alpine

# ---------------------------------------------------------------------------
# REMOVE DEFAULT NGINX CONFIGURATION
# ---------------------------------------------------------------------------
# nginx:alpine comes with a default config that serves a "Welcome to nginx!"
# page. We remove it so our custom config takes over completely.
# Without this, the default config might conflict with ours.
RUN rm /etc/nginx/conf.d/default.conf

# ---------------------------------------------------------------------------
# COPY CUSTOM NGINX CONFIGURATION
# ---------------------------------------------------------------------------
# Our nginx.conf defines:
#   - How to serve our static HTML/CSS/JS files
#   - How to reverse-proxy /api/ requests to the backend service
# We place it in conf.d/ where nginx automatically includes it.
COPY nginx.conf /etc/nginx/conf.d/

# ---------------------------------------------------------------------------
# COPY STATIC WEB FILES
# ---------------------------------------------------------------------------
# /usr/share/nginx/html is the default web root in the nginx Docker image.
# Our index.html (and any future CSS/JS files) go here.
COPY index.html /usr/share/nginx/html/

# ---------------------------------------------------------------------------
# EXPOSE PORT
# ---------------------------------------------------------------------------
# Nginx listens on port 80 (HTTP) by default, matching our server config.
# Remember: EXPOSE is documentation only — the port isn't published until
# you map it in docker-compose (e.g., ports: "8080:80").
EXPOSE 80

# ---------------------------------------------------------------------------
# STARTUP COMMAND
# ---------------------------------------------------------------------------
# "daemon off" is crucial for Docker containers!
# By default, nginx starts as a background daemon (forks to the background
# and the parent process exits). But Docker expects the main process to stay
# in the foreground — if it exits, Docker thinks the container crashed and
# stops it. "daemon off" keeps nginx in the foreground.
#
# We don't need a separate CMD here because the base nginx image already
# includes: CMD ["nginx", "-g", "daemon off;"]
# But we include it explicitly for clarity and documentation.
CMD ["nginx", "-g", "daemon off;"]

# =============================================================================
# DOCKERFILE (Frontend) — Builds the nginx container image
# =============================================================================
# This is simpler than the backend Dockerfile because nginx just needs:
#   1. The nginx configuration file (how to route requests)
#   2. The static HTML file(s) to serve
# No compilation, no dependency installation — just copy files into place.
# =============================================================================

# ---- Step 1: Start with the official nginx image ----
# "nginx:1.25-alpine" uses Alpine Linux as the base OS.
# Alpine is extremely small (~5MB) compared to Debian (~100MB+), which means:
#   - Faster image downloads
#   - Less disk space used
#   - Smaller attack surface (fewer packages = fewer potential vulnerabilities)
# The tradeoff is Alpine uses musl libc instead of glibc, which can cause
# compatibility issues with some software — but nginx works perfectly on Alpine.
FROM nginx:1.25-alpine

# ---- Step 2: Remove the default nginx configuration ----
# The default config serves a "Welcome to nginx!" page. We need to replace
# it with our custom config that includes the reverse proxy setup.
# We remove the entire default config file to avoid any conflicts.
RUN rm /etc/nginx/conf.d/default.conf

# ---- Step 3: Copy our custom nginx configuration ----
# This replaces the MAIN nginx config (not just a site config) so we have
# full control over the events{} and http{} blocks.
COPY nginx.conf /etc/nginx/nginx.conf

# ---- Step 4: Copy our static HTML file ----
# /usr/share/nginx/html/ is the default directory where nginx looks for
# files to serve. This matches the "root" directive in our nginx.conf.
COPY index.html /usr/share/nginx/html/index.html

# ---- Step 5: Document the port ----
# Nginx listens on port 80 as configured in our nginx.conf.
EXPOSE 80

# ---- Step 6: Start nginx ----
# "nginx -g 'daemon off;'" starts nginx in the FOREGROUND.
# By default, nginx runs as a background daemon (detaches from the terminal).
# But containers need the main process to stay in the foreground — if the
# main process exits, the container stops. "daemon off;" prevents that.
CMD ["nginx", "-g", "daemon off;"]

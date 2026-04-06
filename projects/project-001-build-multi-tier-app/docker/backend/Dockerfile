# =============================================================================
# Dockerfile — Backend (Python/Flask) container image definition
# =============================================================================
# A Dockerfile is a recipe that tells Docker how to build a container image.
# Each instruction (FROM, RUN, COPY, etc.) creates a "layer" in the image.
# Docker caches layers, so if a layer hasn't changed, it reuses the cache.
# This is why the ORDER of instructions matters a lot for build speed.
#
# NOTE ON MULTI-STAGE BUILDS:
#   Multi-stage builds use multiple FROM statements to separate "build" and
#   "runtime" stages. This is crucial for compiled languages (Go, Java, C++)
#   where you need a compiler to build but don't want it in the final image.
#   For our Python app, we don't need a multi-stage build because:
#     - Python is interpreted (no compilation step)
#     - python:3.11-slim is already small (~150MB vs ~900MB for full python)
#     - Our dependencies install cleanly with pip (no build tools needed)
#   If you were using numpy or other C-extension packages, you might need
#   a multi-stage build to install build tools in stage 1 and copy the
#   compiled packages to a slim stage 2.
# =============================================================================

# ---------------------------------------------------------------------------
# BASE IMAGE — python:3.11-slim
# ---------------------------------------------------------------------------
# Why python:3.11-slim?
#   - "slim" variant is based on Debian but strips out docs, man pages, and
#     rarely-needed packages. It's ~150MB vs ~900MB for the full image.
#   - It still has enough system libraries to install most Python packages.
#   - 3.11 is a stable, well-supported Python version with good performance.
#   - This image supports linux/arm64 natively (important for Raspberry Pi 5).
#
# Why not python:3.11-alpine?
#   - Alpine uses musl libc instead of glibc. Many Python packages (like
#     psycopg2) need glibc or require extra compilation steps on Alpine.
#   - Build times on Alpine are often much longer due to compiling C extensions.
#   - The size savings (~50MB) aren't worth the complexity for most apps.
FROM python:3.11-slim

# ---------------------------------------------------------------------------
# WORKING DIRECTORY
# ---------------------------------------------------------------------------
# WORKDIR sets the directory inside the container where all subsequent
# commands (RUN, COPY, CMD) will execute. If it doesn't exist, Docker
# creates it. Think of it like "cd /app" but persistent across layers.
WORKDIR /app

# ---------------------------------------------------------------------------
# COPY requirements.txt FIRST (Layer Caching Optimization)
# ---------------------------------------------------------------------------
# This is a key Docker optimization trick:
#   1. We copy ONLY requirements.txt first (not all our code)
#   2. Then we run pip install
#   3. Docker caches this layer based on requirements.txt's contents
#   4. As long as requirements.txt doesn't change, pip install is CACHED
#      even if you change your Python code (app.py, etc.)
#
# If we copied everything first (COPY . .), then ANY code change would
# invalidate the cache and force a full pip install every build.
# Dependencies rarely change, but code changes constantly — so this
# ordering saves you minutes on every build.
COPY requirements.txt .

# ---------------------------------------------------------------------------
# INSTALL DEPENDENCIES
# ---------------------------------------------------------------------------
# --no-cache-dir: Tells pip not to store downloaded packages in a cache.
#   Inside a container, the cache is useless (you won't pip install again)
#   and just wastes space in the image layer.
#
# --no-compile: Skips generating .pyc bytecode files during install.
#   Python will compile them on first run anyway, and skipping this step
#   keeps the image layer smaller.
RUN pip install --no-cache-dir --no-compile -r requirements.txt

# ---------------------------------------------------------------------------
# COPY APPLICATION CODE
# ---------------------------------------------------------------------------
# Now we copy the rest of our source code. Since this comes AFTER pip
# install, changing app.py won't trigger a re-install of dependencies.
# The "." on the left means "everything in the build context" (filtered
# by .dockerignore). The "." on the right means "into WORKDIR (/app)."
COPY . .

# ---------------------------------------------------------------------------
# EXPOSE PORT
# ---------------------------------------------------------------------------
# EXPOSE is documentation — it tells other developers (and tools like
# docker-compose) which port the container listens on. It does NOT
# actually publish the port. You still need -p 5000:5000 in docker run
# or ports: in docker-compose.yml to make it accessible from outside.
EXPOSE 5000

# ---------------------------------------------------------------------------
# STARTUP COMMAND
# ---------------------------------------------------------------------------
# CMD defines the default command when the container starts.
#
# Why gunicorn instead of "flask run"?
#   - Flask's built-in server is single-threaded and meant for development
#   - gunicorn is a production WSGI server that:
#     * Spawns multiple worker processes (--workers 2)
#     * Handles concurrent requests properly
#     * Restarts crashed workers automatically
#     * Has proper signal handling for graceful shutdown
#
# Flags explained:
#   --bind 0.0.0.0:5000  — Listen on ALL network interfaces inside the
#                           container (not just localhost). This is required
#                           for the container to receive traffic from outside.
#   --workers 2           — Spawn 2 worker processes. A common formula is
#                           (2 * CPU_cores) + 1, but on a Pi with limited
#                           RAM, 2 workers is a safe choice.
#   --timeout 120         — Kill a worker if it doesn't respond within 120s.
#                           Prevents hung requests from blocking a worker.
#   --access-logfile -    — Write access logs to stdout (the "-" means stdout).
#                           Docker captures stdout, so you can see logs with
#                           "docker logs" or in Kubernetes pod logs.
#   app:app               — "module:variable" format. It means "import the
#                           'app' variable from the 'app' module (app.py)."
#                           The first 'app' is the filename, the second is
#                           the Flask() instance variable name.
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "120", "--access-logfile", "-", "app:app"]

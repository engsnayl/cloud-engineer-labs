# =============================================================================
# DOCKERFILE (Backend) — Instructions to build the backend container image
# =============================================================================
# A Dockerfile is a recipe that tells Docker how to build a container image.
# Each line creates a "layer" — Docker caches these layers, so unchanged steps
# don't need to re-run. This makes rebuilds fast.
#
# Think of it like packing a suitcase: you start with a base (the suitcase),
# add what you need (clothes), and seal it up (the final image).
# =============================================================================

# ---- Step 1: Start with a base image ----
# "python:3.11-slim" is an official Python image based on Debian Linux.
# "slim" means it's a minimal version — smaller download, fewer unnecessary
# packages, and a smaller attack surface for security.
# Always specify a version (3.11) instead of "latest" to avoid surprises.
FROM python:3.11-slim

# ---- Step 2: Set the working directory ----
# WORKDIR sets the directory inside the container where commands will run.
# If the directory doesn't exist, Docker creates it automatically.
# All subsequent COPY, RUN, and CMD commands use this as their base path.
WORKDIR /app

# ---- Step 3: Install dependencies first (for caching) ----
# We copy ONLY requirements.txt first, then install dependencies.
# Why not copy everything at once? Because Docker caches layers.
# If your app code changes but requirements.txt doesn't, Docker reuses
# the cached layer with installed packages — saving minutes on rebuilds.
COPY requirements.txt .

# "pip install" downloads and installs the Python packages listed in requirements.txt.
# --no-cache-dir  = Don't store pip's download cache (saves space in the image).
# -r              = Read package list from a file (requirements.txt).
RUN pip install --no-cache-dir -r requirements.txt

# ---- Step 4: Copy application code ----
# Now copy the rest of the application code into the container.
# "COPY . ." means "copy everything from the build context (current directory
# on your machine) into the working directory (/app) in the container."
COPY . .

# ---- Step 5: Document the port ----
# EXPOSE doesn't actually open the port — it's documentation that tells other
# developers (and tools like Docker Compose) which port the app uses.
# The actual port mapping happens in the Kubernetes Service manifest.
EXPOSE 5000

# ---- Step 6: Define the startup command ----
# CMD is what runs when the container starts.
# We use gunicorn (a production WSGI server) instead of Flask's built-in server:
#   --bind 0.0.0.0:5000  = Listen on all interfaces, port 5000
#   --workers 2           = Run 2 worker processes to handle concurrent requests
#   --timeout 120         = Kill workers that take longer than 120 seconds
#   app:app               = "module_name:flask_app_variable"
#                           (look in app.py for the variable called "app")
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--timeout", "120", "app:app"]

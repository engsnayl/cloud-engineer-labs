# =============================================================================
# FLASK BACKEND APPLICATION
# =============================================================================
# This is the API layer of our multi-tier app. It sits between the frontend
# (nginx) and the database (PostgreSQL), handling HTTP requests and translating
# them into database queries.
#
# Flask is a lightweight Python web framework — it gives you just enough to
# build a web server without the complexity of larger frameworks like Django.
# =============================================================================

# -----------------------------------------------------------------------------
# IMPORTS — Loading the libraries we need
# -----------------------------------------------------------------------------

# "os" lets us read environment variables (like database connection details).
# Environment variables are the standard way to pass configuration into
# containers — you set them in the K8s manifest, and the app reads them here.
import os

# "datetime" is used to handle timestamp values from the database.
# PostgreSQL returns timestamps as Python datetime objects, but JSON doesn't
# know how to handle those natively, so we'll need to convert them to strings.
from datetime import datetime

# "Flask" is the web framework itself.
# "jsonify" converts Python dictionaries/lists into proper JSON HTTP responses
# (sets the Content-Type header to application/json, etc.).
# "request" gives us access to incoming HTTP request details.
from flask import Flask, jsonify, request

# "psycopg2" is the most popular PostgreSQL driver for Python.
# It lets Python talk to PostgreSQL databases — send queries, get results back.
import psycopg2

# "RealDictCursor" changes how query results are returned.
# By default, psycopg2 returns rows as tuples: (1, "Pod", "description")
# With RealDictCursor, you get dictionaries: {"id": 1, "name": "Pod", ...}
# which are much easier to convert to JSON.
from psycopg2.extras import RealDictCursor

# -----------------------------------------------------------------------------
# APP SETUP
# -----------------------------------------------------------------------------

# Create the Flask application instance.
# __name__ tells Flask where to find templates and static files (standard practice).
app = Flask(__name__)

# -----------------------------------------------------------------------------
# METRICS COUNTER — Simple observability tracking
# -----------------------------------------------------------------------------
# In production, you'd use a library like prometheus_client for proper metrics.
# This is a simplified version that counts how many times each endpoint is hit.
# The /metrics endpoint will expose these counts in a format monitoring tools
# can scrape (read periodically).
request_count = {
    "health": 0,      # How many times /api/health was called
    "data_get": 0,    # How many times /api/data was called with GET
    "data_post": 0,   # How many times /api/data was called with POST
}

# -----------------------------------------------------------------------------
# DATABASE CONNECTION HELPER
# -----------------------------------------------------------------------------
# This function creates a new connection to PostgreSQL each time it's called.
# It reads connection details from environment variables, which Kubernetes
# injects from our ConfigMap and Secret.
#
# Why a function instead of a global connection? Because database connections
# can go stale (timeout, network blip, etc.). Creating a fresh connection per
# request is simpler and more resilient for a learning project like this.
# In production, you'd use a connection pool (like psycopg2.pool) for efficiency.
def get_db_connection():
    """
    Opens a new database connection using configuration from environment variables.
    Returns a psycopg2 connection object.
    """
    conn = psycopg2.connect(
        # Each os.environ.get("KEY", "default") reads an environment variable.
        # The second argument is a fallback value if the variable isn't set
        # (useful for local development outside of Kubernetes).
        host=os.environ.get("DB_HOST", "postgres"),            # K8s Service name
        port=os.environ.get("DB_PORT", "5432"),                # PostgreSQL default port
        dbname=os.environ.get("DB_NAME", "multitierdb"),       # Our database name
        user=os.environ.get("DB_USER", "postgres"),            # From the Secret
        password=os.environ.get("DB_PASSWORD", "securepassword123"),  # From the Secret
    )
    return conn

# -----------------------------------------------------------------------------
# CUSTOM JSON SERIALIZER
# -----------------------------------------------------------------------------
# PostgreSQL returns datetime objects, but Python's json module doesn't know
# how to convert them to strings. This helper handles that conversion.
def serialize_row(row):
    """
    Converts a database row dictionary so all values are JSON-serializable.
    Specifically, converts datetime objects to ISO 8601 formatted strings.
    """
    serialized = {}
    for key, value in row.items():
        if isinstance(value, datetime):
            # ISO 8601 format: "2024-01-15T10:30:00" — the standard way to
            # represent dates/times in JSON APIs.
            serialized[key] = value.isoformat()
        else:
            serialized[key] = value
    return serialized

# =============================================================================
# API ENDPOINTS (Routes)
# =============================================================================
# Each @app.route() decorator registers a URL pattern with a handler function.
# When a request comes in matching that pattern, Flask calls the function
# and returns whatever it sends back.

# -----------------------------------------------------------------------------
# HEALTH CHECK — GET /api/health
# -----------------------------------------------------------------------------
# Health checks are how Kubernetes knows your app is working. The kubelet
# (agent on each node) periodically hits this endpoint. If it fails,
# Kubernetes can restart the pod or stop sending it traffic.
@app.route("/api/health", methods=["GET"])
def health():
    """
    Returns the health status of the backend and its database connection.
    Kubernetes liveness and readiness probes call this endpoint.
    """
    # Increment our simple metrics counter.
    request_count["health"] += 1

    try:
        # Try to connect to the database and run a trivial query.
        # "SELECT 1" is the simplest possible query — if it works,
        # the database connection is healthy.
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.close()
        conn.close()

        # If we got here, everything is working.
        return jsonify({
            "status": "healthy",
            "database": "connected",
        }), 200  # HTTP 200 = OK

    except Exception as e:
        # If the database connection failed, report unhealthy.
        # str(e) converts the error to a human-readable message.
        return jsonify({
            "status": "unhealthy",
            "database": "disconnected",
            "error": str(e),
        }), 503  # HTTP 503 = Service Unavailable

# -----------------------------------------------------------------------------
# DATA ENDPOINT — GET and POST /api/data
# -----------------------------------------------------------------------------
# This endpoint serves two purposes depending on the HTTP method:
#   GET  = Retrieve all items from the database (read)
#   POST = Add a new item to the database (write)
@app.route("/api/data", methods=["GET", "POST"])
def data():
    """
    GET:  Returns all items from the database as a JSON array.
    POST: Creates a new item. Expects JSON body with "name" and optional "description".
    """

    # --- Handle GET requests (fetch all items) ---
    if request.method == "GET":
        request_count["data_get"] += 1

        try:
            conn = get_db_connection()

            # RealDictCursor makes each row a dictionary instead of a tuple.
            # This is much easier to work with when building JSON responses.
            cur = conn.cursor(cursor_factory=RealDictCursor)

            # Fetch all rows from the items table, newest first.
            cur.execute("SELECT * FROM items ORDER BY created_at DESC")

            # fetchall() returns a list of all matching rows.
            rows = cur.fetchall()
            cur.close()
            conn.close()

            # Convert each row (handling datetime fields) and return as JSON.
            return jsonify({
                "items": [serialize_row(row) for row in rows],
                "count": len(rows),
            }), 200

        except Exception as e:
            return jsonify({"error": str(e)}), 500  # HTTP 500 = Internal Server Error

    # --- Handle POST requests (create a new item) ---
    if request.method == "POST":
        request_count["data_post"] += 1

        try:
            # request.get_json() parses the JSON body of the incoming request.
            # The caller would send something like: {"name": "New Item", "description": "Details"}
            body = request.get_json()

            # Validate that "name" was provided — it's required by our database schema.
            if not body or "name" not in body:
                return jsonify({"error": "Missing required field: name"}), 400  # HTTP 400 = Bad Request

            conn = get_db_connection()
            cur = conn.cursor(cursor_factory=RealDictCursor)

            # Use parameterized queries (%s placeholders) to prevent SQL injection.
            # NEVER build SQL strings with f-strings or concatenation — that's how
            # databases get hacked. The %s placeholders are safely escaped by psycopg2.
            # "RETURNING *" tells PostgreSQL to send back the newly created row.
            cur.execute(
                "INSERT INTO items (name, description) VALUES (%s, %s) RETURNING *",
                (body["name"], body.get("description", "")),
            )

            # Fetch the newly created row to return it in the response.
            new_item = cur.fetchone()

            # commit() saves the changes to the database. Without this, the INSERT
            # would be rolled back (undone) when the connection closes.
            conn.commit()
            cur.close()
            conn.close()

            return jsonify(serialize_row(new_item)), 201  # HTTP 201 = Created

        except Exception as e:
            return jsonify({"error": str(e)}), 500

# -----------------------------------------------------------------------------
# METRICS ENDPOINT — GET /metrics
# -----------------------------------------------------------------------------
# Exposes basic request counts in a simple format.
# In production, you'd use the prometheus_client library which outputs
# metrics in Prometheus' standard text format. This simplified version
# gives you the idea without the extra dependency.
@app.route("/metrics", methods=["GET"])
def metrics():
    """
    Returns request counts for each endpoint.
    This is a simplified metrics endpoint for observability.
    """
    return jsonify({
        "requests": request_count,
        "status": "serving",
    }), 200

# =============================================================================
# APPLICATION ENTRY POINT
# =============================================================================
# This block only runs when you execute the file directly (python app.py).
# It does NOT run when imported as a module.
if __name__ == "__main__":
    # Start the Flask development server.
    #   host="0.0.0.0" — Listen on ALL network interfaces (not just localhost).
    #                     This is required inside a container because "localhost"
    #                     inside a container is different from the host machine.
    #   port=5000       — The port our server listens on. We'll match this in
    #                     our Kubernetes Service and Deployment manifests.
    #   debug=False     — Disable debug mode in production. Debug mode auto-reloads
    #                     on code changes (handy for development, dangerous in prod).
    app.run(host="0.0.0.0", port=5000, debug=False)

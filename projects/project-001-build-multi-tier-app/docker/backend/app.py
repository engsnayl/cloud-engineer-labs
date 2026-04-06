# =============================================================================
# app.py — Backend API for the Multi-Tier Application
# =============================================================================
# This is the main application file for our backend service. It uses:
#   - Flask: A Python web framework that handles HTTP requests/responses
#   - psycopg2: A PostgreSQL database adapter for Python
#   - prometheus_client: Exposes metrics for Prometheus monitoring
#
# The app provides a REST API (Representational State Transfer) that the
# frontend calls to interact with the database. The frontend never talks
# to the database directly — that's the whole point of a multi-tier
# architecture: separation of concerns.
# =============================================================================

import os          # For reading environment variables (database config)
import time        # For measuring request duration (metrics)
import datetime    # For converting database timestamps to JSON-friendly format
import psycopg2    # PostgreSQL adapter — lets Python talk to PostgreSQL
import psycopg2.extras  # Extra utilities, including RealDictCursor

# Flask is the web framework. We import the Flask class to create our app,
# 'request' to access incoming HTTP data, and 'jsonify' to convert Python
# dicts into proper JSON HTTP responses.
from flask import Flask, request, jsonify

# prometheus_client provides tools to create and expose metrics.
# - Counter: A value that only goes UP (e.g., total requests served).
#   You can't decrement a counter — that's by design. To get "requests
#   per second," Prometheus calculates the rate of increase over time.
# - Histogram: Tracks the DISTRIBUTION of values (e.g., response times).
#   It automatically creates buckets (e.g., <10ms, <50ms, <100ms, <500ms)
#   so you can answer "what percentage of requests took under 200ms?"
# - generate_latest: Serializes all metrics into Prometheus' text format.
# - CONTENT_TYPE_LATEST: The correct Content-Type header for Prometheus.
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST


# =============================================================================
# CREATE THE FLASK APPLICATION
# =============================================================================
# Flask(__name__) creates a new Flask app. __name__ is a Python built-in that
# equals the current module name ("app" in this case). Flask uses it to know
# where to find templates, static files, etc.
app = Flask(__name__)


# =============================================================================
# PROMETHEUS METRICS DEFINITIONS
# =============================================================================
# We define metrics ONCE at module level (not inside request handlers).
# Each metric has:
#   - A name (used in Prometheus queries, e.g., "http_requests_total")
#   - A description (shows up in Prometheus UI)
#   - Labels: dimensions to slice the data by (method, endpoint, status)
#
# With labels, a single Counter can track:
#   http_requests_total{method="GET", endpoint="/api/data", status="200"} = 42
#   http_requests_total{method="POST", endpoint="/api/data", status="201"} = 7
#   http_requests_total{method="GET", endpoint="/api/health", status="500"} = 1

# Counter for total HTTP requests — only goes up.
REQUEST_COUNT = Counter(
    'http_requests_total',               # Metric name (Prometheus convention: snake_case + _total for counters)
    'Total HTTP requests',               # Human-readable description
    ['method', 'endpoint', 'status']     # Label names — we'll set values per-request
)

# Histogram for request duration in seconds.
# The default buckets are [.005, .01, .025, .05, .075, .1, .25, .5, .75, 1, 2.5, 5, 7.5, 10]
# which work well for most web APIs (most responses should be under 1 second).
REQUEST_DURATION = Histogram(
    'http_request_duration_seconds',     # Metric name (convention: unit in the name)
    'HTTP request duration in seconds',  # Description
    ['method', 'endpoint']               # Labels (no status here — we want duration regardless)
)


# =============================================================================
# DATABASE CONNECTION HELPER
# =============================================================================
# This function creates a new connection to PostgreSQL each time it's called.
# In a production app, you'd use connection pooling (e.g., psycopg2.pool or
# SQLAlchemy) to reuse connections and avoid the overhead of connecting on
# every request. For learning purposes, this simpler approach works fine.
#
# Environment variables are read with os.environ.get(), which returns a
# default value if the variable isn't set. This is how we pass config to
# containers — via environment variables, NOT hardcoded values.
def get_db_connection():
    """
    Create and return a new PostgreSQL database connection.

    Uses RealDictCursor so that query results come back as Python dicts
    (e.g., {"id": 1, "name": "Widget"}) instead of tuples ((1, "Widget")).
    This makes it much easier to convert results to JSON.
    """
    conn = psycopg2.connect(
        host=os.environ.get('DB_HOST', 'localhost'),       # Hostname of the DB server
        port=os.environ.get('DB_PORT', '5432'),            # PostgreSQL default port
        dbname=os.environ.get('DB_NAME', 'multitierdb'),   # Database name
        user=os.environ.get('DB_USER', 'postgres'),        # Database username
        password=os.environ.get('DB_PASSWORD', 'password') # Database password
    )
    # Set the connection to autocommit=False by default (psycopg2's default).
    # This means changes aren't saved until we call conn.commit().
    return conn


# =============================================================================
# ROUTE: Health Check — GET /api/health
# =============================================================================
# @app.route is a "decorator" — it tells Flask "when someone sends a GET
# request to /api/health, run this function and return the result."
#
# Health checks are essential in Kubernetes. The "readiness probe" calls this
# endpoint to know if the pod is ready to receive traffic. If the database is
# down, we return a 503 (Service Unavailable) and Kubernetes stops sending
# traffic to this pod until it recovers.
@app.route('/api/health', methods=['GET'])
def health_check():
    """Check if the application can connect to the database."""
    start_time = time.time()  # Record when the request started (for metrics)

    try:
        # Try to connect and run a simple query
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute('SELECT 1')  # Simplest possible query — just checks connectivity
        cur.close()
        conn.close()

        # Calculate how long the request took
        duration = time.time() - start_time

        # Record metrics — .labels() sets the label values, .inc() increments by 1
        REQUEST_COUNT.labels(method='GET', endpoint='/api/health', status='200').inc()
        REQUEST_DURATION.labels(method='GET', endpoint='/api/health').observe(duration)

        # jsonify() converts a Python dict to a JSON response with proper headers
        return jsonify({
            'status': 'healthy',
            'database': 'connected',
            'response_time_ms': round(duration * 1000, 2)  # Convert seconds to ms
        }), 200  # 200 = HTTP OK

    except Exception as e:
        duration = time.time() - start_time
        REQUEST_COUNT.labels(method='GET', endpoint='/api/health', status='503').inc()
        REQUEST_DURATION.labels(method='GET', endpoint='/api/health').observe(duration)

        return jsonify({
            'status': 'unhealthy',
            'database': 'disconnected',
            'error': str(e)  # Include the error message for debugging
        }), 503  # 503 = Service Unavailable


# =============================================================================
# ROUTE: Get All Items — GET /api/data
# =============================================================================
# This endpoint retrieves all items from the "items" table and returns them
# as a JSON array. The frontend calls this to populate the items list.
@app.route('/api/data', methods=['GET'])
def get_data():
    """Retrieve all items from the database, ordered by creation date."""
    start_time = time.time()

    try:
        conn = get_db_connection()
        # RealDictCursor makes each row a dict ({"id": 1, "name": "Widget"})
        # instead of a tuple ((1, "Widget")). Much easier for JSON conversion.
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        # ORDER BY created_at DESC puts newest items first
        cur.execute('SELECT id, name, description, created_at FROM items ORDER BY created_at DESC')
        rows = cur.fetchall()  # Get ALL rows as a list of dicts

        cur.close()
        conn.close()

        # Convert datetime objects to ISO 8601 strings for JSON serialization.
        # JSON doesn't have a native date type, so we use the ISO format
        # (e.g., "2025-01-15T10:30:00") which is universally understood.
        items = []
        for row in rows:
            item = dict(row)  # RealDictCursor returns RealDictRow, convert to plain dict
            if isinstance(item.get('created_at'), datetime.datetime):
                item['created_at'] = item['created_at'].isoformat()
            items.append(item)

        duration = time.time() - start_time
        REQUEST_COUNT.labels(method='GET', endpoint='/api/data', status='200').inc()
        REQUEST_DURATION.labels(method='GET', endpoint='/api/data').observe(duration)

        return jsonify(items), 200

    except Exception as e:
        duration = time.time() - start_time
        REQUEST_COUNT.labels(method='GET', endpoint='/api/data', status='500').inc()
        REQUEST_DURATION.labels(method='GET', endpoint='/api/data').observe(duration)

        return jsonify({'error': str(e)}), 500  # 500 = Internal Server Error


# =============================================================================
# ROUTE: Create New Item — POST /api/data
# =============================================================================
# POST is the HTTP method for "create a new resource." The client sends JSON
# in the request body with the item details.
@app.route('/api/data', methods=['POST'])
def create_data():
    """
    Create a new item in the database.

    Expects JSON body:
      { "name": "Item Name", "description": "Optional description" }

    'name' is required, 'description' is optional.
    """
    start_time = time.time()

    try:
        # request.get_json() parses the JSON body sent by the client.
        # If the client didn't send valid JSON, this returns None.
        data = request.get_json()

        # Validate that we got JSON and it has a 'name' field
        if not data or 'name' not in data:
            duration = time.time() - start_time
            REQUEST_COUNT.labels(method='POST', endpoint='/api/data', status='400').inc()
            REQUEST_DURATION.labels(method='POST', endpoint='/api/data').observe(duration)
            return jsonify({'error': 'name is required'}), 400  # 400 = Bad Request

        name = data['name']
        description = data.get('description', '')  # Default to empty string if not provided

        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        # PARAMETERIZED QUERY — This is critically important for security!
        # ---------------------------------------------------------------------------
        # We use %s placeholders and pass values as a tuple (name, description).
        # psycopg2 handles escaping and quoting automatically.
        #
        # NEVER do this:  f"INSERT INTO items (name) VALUES ('{name}')"
        # That's vulnerable to SQL injection — a user could send:
        #   name = "'; DROP TABLE items; --"
        # and it would delete your entire table!
        #
        # With parameterized queries, psycopg2 treats the values as DATA, not SQL.
        # Even if someone sends malicious input, it's safely escaped.
        # ---------------------------------------------------------------------------
        # RETURNING * gives us back the newly created row (with its auto-generated
        # id and created_at timestamp) so we can return it to the client.
        cur.execute(
            'INSERT INTO items (name, description) VALUES (%s, %s) RETURNING *',
            (name, description)  # Values passed as a tuple — psycopg2 escapes them
        )

        new_item = dict(cur.fetchone())  # Get the newly created row

        conn.commit()  # COMMIT the transaction — without this, the INSERT is rolled back!
        cur.close()
        conn.close()

        # Convert datetime to ISO format for JSON
        if isinstance(new_item.get('created_at'), datetime.datetime):
            new_item['created_at'] = new_item['created_at'].isoformat()

        duration = time.time() - start_time
        REQUEST_COUNT.labels(method='POST', endpoint='/api/data', status='201').inc()
        REQUEST_DURATION.labels(method='POST', endpoint='/api/data').observe(duration)

        return jsonify(new_item), 201  # 201 = Created (standard response for POST success)

    except Exception as e:
        duration = time.time() - start_time
        REQUEST_COUNT.labels(method='POST', endpoint='/api/data', status='500').inc()
        REQUEST_DURATION.labels(method='POST', endpoint='/api/data').observe(duration)

        return jsonify({'error': str(e)}), 500


# =============================================================================
# ROUTE: Prometheus Metrics — GET /metrics
# =============================================================================
# This endpoint exposes metrics in Prometheus' text-based format.
# Prometheus (running in your cluster) periodically "scrapes" (HTTP GETs)
# this endpoint to collect metrics. The format looks like:
#
#   # HELP http_requests_total Total HTTP requests
#   # TYPE http_requests_total counter
#   http_requests_total{method="GET",endpoint="/api/data",status="200"} 42.0
#
# In Kubernetes, we add annotations to the pod (prometheus.io/scrape: "true")
# so Prometheus knows to scrape this endpoint automatically.
@app.route('/metrics', methods=['GET'])
def metrics():
    """
    Expose application metrics in Prometheus text format.

    generate_latest() collects all registered metrics (our Counter and
    Histogram) and formats them as Prometheus exposition text.
    CONTENT_TYPE_LATEST is "text/plain; version=0.0.4; charset=utf-8"
    which Prometheus expects.
    """
    return generate_latest(), 200, {'Content-Type': CONTENT_TYPE_LATEST}


# =============================================================================
# DEVELOPMENT SERVER (only used when running app.py directly)
# =============================================================================
# This block runs ONLY when you execute "python app.py" directly.
# In production (Docker), gunicorn runs the app instead (see Dockerfile CMD).
# The if __name__ == '__main__' pattern is a Python convention that lets a
# file work both as an importable module and a standalone script.
if __name__ == '__main__':
    # debug=True enables auto-reload on code changes and detailed error pages.
    # host='0.0.0.0' listens on all interfaces (needed inside containers).
    # NEVER use debug=True in production — it exposes a debugger that lets
    # anyone execute arbitrary Python code on your server!
    app.run(host='0.0.0.0', port=5000, debug=True)

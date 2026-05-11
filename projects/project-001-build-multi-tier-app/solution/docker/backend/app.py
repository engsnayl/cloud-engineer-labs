"""
Multi-tier app — backend API.

Provides /api/health (liveness) and /api/data (reads from postgres).
Configuration via environment variables; logs to stdout.
"""

import logging
import os
import sys

import psycopg2
from flask import Flask, jsonify

# ── Logging ────────────────────────────────────────────────────────────────
# Stream to stdout so the container runtime (and later Kubernetes) can capture
# logs without us writing to disk inside the container.
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s — %(message)s",
    stream=sys.stdout,
)
log = logging.getLogger("backend")

# ── Config from environment ────────────────────────────────────────────────
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = int(os.environ.get("DB_PORT", "5432"))
DB_NAME = os.environ.get("DB_NAME", "postgres")
DB_USER = os.environ.get("DB_USER", "postgres")
DB_PASSWORD = os.environ.get("DB_PASSWORD", "")
APP_PORT = int(os.environ.get("APP_PORT", "5000"))

app = Flask(__name__)


def get_db_connection():
    """Open a new connection per request. Simple; not pooled; fine for this scope."""
    return psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        dbname=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD,
        connect_timeout=5,
    )


@app.route("/api/health")
def health():
    """Liveness check. Returns 200 if the process is up.

    Deliberately does NOT check the database — liveness asks 'is the process
    alive?', not 'is everything downstream working?'. Conflating the two means
    a transient DB blip kills the pod.
    """
    return jsonify(status="ok"), 200


@app.route("/api/data")
def data():
    """Read seed rows from the messages table."""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT id, content, created_at FROM messages ORDER BY id;")
        rows = cur.fetchall()
        cur.close()
        conn.close()

        messages = [
            {"id": r[0], "content": r[1], "created_at": r[2].isoformat()}
            for r in rows
        ]
        return jsonify(count=len(messages), messages=messages), 200

    except psycopg2.OperationalError as e:
        log.error("Database connection failed: %s", e)
        return jsonify(error="database unavailable"), 503


if __name__ == "__main__":
    log.info("Backend starting on port %d (DB target: %s:%d)", APP_PORT, DB_HOST, DB_PORT)
    app.run(host="0.0.0.0", port=APP_PORT)

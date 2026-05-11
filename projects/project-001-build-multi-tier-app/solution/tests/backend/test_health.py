"""
Trivial smoke test for the backend.

Imports the Flask app and asserts that /api/health returns 200 with status=ok.
Deliberately does not touch the database — this is here so the CI/CD pipeline
in a later module has something to actually run. Real test coverage is out
of scope for the platform-engineering side of this project.
"""

import os
import sys

# Add the backend code directory to the path so we can import app.py
# (real projects use a proper package layout; this is the simple version)
sys.path.insert(
    0,
    os.path.join(os.path.dirname(__file__), "..", "..", "docker", "backend"),
)

from app import app  # noqa: E402  (import after sys.path manipulation is intentional)


def test_health_endpoint_returns_ok():
    """GET /api/health should respond 200 with body {'status': 'ok'}."""
    client = app.test_client()
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}

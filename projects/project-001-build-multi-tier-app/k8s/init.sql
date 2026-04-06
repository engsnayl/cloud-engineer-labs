-- =============================================================================
-- init.sql — Database initialization script
-- =============================================================================
-- This script runs automatically when PostgreSQL starts for the FIRST TIME
-- (when the data directory is empty). It will NOT run on subsequent restarts.
--
-- Used by:
--   - docker-compose.yml: Mounted into /docker-entrypoint-initdb.d/
--   - Kubernetes: Loaded from database-init-configmap.yaml
-- =============================================================================

CREATE TABLE IF NOT EXISTS items (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    description TEXT DEFAULT '',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO items (name, description) VALUES
    ('Raspberry Pi 5', 'ARM64 single-board computer running k3s'),
    ('Docker Container', 'Lightweight, portable application package'),
    ('Kubernetes Pod', 'Smallest deployable unit in Kubernetes'),
    ('PostgreSQL', 'Open-source relational database management system'),
    ('Flask API', 'Python micro-framework powering our backend');

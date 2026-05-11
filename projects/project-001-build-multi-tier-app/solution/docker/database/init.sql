-- Multi-tier app: database initialisation
-- The postgres image runs this automatically on first startup.

CREATE TABLE IF NOT EXISTS messages (
    id          SERIAL PRIMARY KEY,
    content     TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO messages (content) VALUES
    ('Hello from the database tier'),
    ('Multi-tier app — backend connected'),
    ('Postgres 15 running on ARM64')
ON CONFLICT DO NOTHING;

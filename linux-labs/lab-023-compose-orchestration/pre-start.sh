#!/bin/bash
# Pre-start setup for lab 023: runs on the Pi host before the lab container starts.

# Fix 5: Stop host Nginx if running — it binds port 80 and conflicts with
# the Compose stack's nginx container.
sudo systemctl stop nginx 2>/dev/null || true

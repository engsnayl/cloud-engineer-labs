#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")/../../tools" && pwd)/seed-helpers.sh"

gd_init_repo

gd_commit_file README.md "# Project" "Initial commit"

# The buggy commit - typo in both file and message.
cat > lib.py <<'EOF'
def calcualte_total(items):
    return sum(item.price for item in items)
EOF
git add lib.py
git commit --quiet -m "Add calcualte_total helper"

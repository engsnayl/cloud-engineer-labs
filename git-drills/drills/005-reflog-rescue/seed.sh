#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")/../../tools" && pwd)/seed-helpers.sh"

gd_init_repo

# Build a normal little history.
gd_commit_file README.md "# Project" "Initial commit"
gd_commit_file src.py "print('hello')" "Add src.py"

# Now make the "important" commit on top.
printf 'critical changes\n' > feature.txt
git add feature.txt
git commit --quiet -m "Important work do not lose"

# ... and immediately blow it away with a hard reset back to the previous commit.
# This is the bug the learner has to recover from.
git reset --hard HEAD~1 --quiet

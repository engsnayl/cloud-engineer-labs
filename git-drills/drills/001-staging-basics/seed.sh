#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")/../../tools" && pwd)/seed-helpers.sh"

gd_init_repo

# One initial commit so HEAD exists - makes "compare to HEAD" sensible.
gd_commit_file README.md "# Project" "Initial commit"

# Now stage three files without committing.
gd_stage_file notes.txt "Important meeting notes from the architecture review."
gd_stage_file draft.txt "scratch scratch scratch ignore me"
gd_stage_file secrets.txt "DATABASE_PASSWORD=hunter2"

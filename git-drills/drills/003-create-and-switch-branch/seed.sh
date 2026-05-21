#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")/../../tools" && pwd)/seed-helpers.sh"

gd_init_repo
gd_commit_file README.md "# Project" "Initial commit"

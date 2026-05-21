#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "$0")/../../tools" && pwd)/seed-helpers.sh"

gd_init_repo

# A and B - shared history
gd_commit_file file-a.txt "A" "A: initial setup"
gd_commit_file file-b.txt "B" "B: add module skeleton"

# Branch off feature at B
git switch -c feature --quiet

# X and Y on feature (touching their own files so we won't conflict with main's commits)
gd_commit_file feature-x.txt "X" "X: feature work part one"
gd_commit_file feature-y.txt "Y" "Y: feature work part two"

# Back to main, add C and D (different files - no conflicts on rebase)
git switch main --quiet
gd_commit_file file-c.txt "C" "C: dependency bump"
gd_commit_file file-d.txt "D" "D: config tweak"

# End the seed back on feature so the user picks up there.
git switch feature --quiet

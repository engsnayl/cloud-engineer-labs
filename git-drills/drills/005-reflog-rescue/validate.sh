#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../tools" && pwd)/validate-helpers.sh"

gd_assert_on_branch "main"

# Three commits: Initial, Add src.py, Important work do not lose.
gd_assert_commit_count "HEAD" "3" "main has 3 commits (the lost one is back)"

# Exact commit message exists somewhere in the history.
gd_assert_commit_message "HEAD" "^Important work do not lose$"

# feature.txt is tracked and contains the expected line.
gd_assert_tracked "feature.txt"
gd_assert_file_contains_at_head "feature.txt" "critical changes"

# Clean tree.
gd_assert_clean_tree

gd_pass

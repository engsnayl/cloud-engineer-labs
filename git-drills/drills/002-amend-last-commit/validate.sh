#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../tools" && pwd)/validate-helpers.sh"

# Exactly two commits (initial + the amended one). No extra commit added on top.
gd_assert_commit_count "HEAD" "2" "Exactly 2 commits on main (you didn't add a new commit)"

# File contents at HEAD must have the correctly-spelled function.
gd_assert_file_contains_at_head "lib.py" "calculate_total"
gd_assert "! git show HEAD:lib.py | grep -q calcualte_total" \
    "Typo 'calcualte_total' is gone from lib.py at HEAD"

# Commit message at HEAD is corrected.
gd_assert "git log -1 --format=%s | grep -qx 'Add calculate_total helper'" \
    "HEAD commit message is 'Add calculate_total helper'"
gd_assert "! git log -1 --format=%s | grep -q calcualte_total" \
    "HEAD commit message no longer contains the typo"

# Working tree clean - no dangling staged/unstaged changes.
gd_assert_clean_tree

gd_pass

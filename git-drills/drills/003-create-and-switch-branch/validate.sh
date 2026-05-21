#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../tools" && pwd)/validate-helpers.sh"

gd_assert_branch_exists "feature/add-feature-file"
gd_assert_on_branch "feature/add-feature-file"

# Feature branch has exactly one commit ahead of main.
gd_assert_commit_count "main..feature/add-feature-file" "1" \
    "feature branch has exactly 1 commit ahead of main"

# main is unchanged - still pointing at the initial commit (1 commit total).
gd_assert_commit_count "main" "1" "main still has 1 commit (untouched)"

# feature.txt is tracked at HEAD.
gd_assert_tracked "feature.txt"
gd_assert_file_contains_at_head "feature.txt" "feature work"

# Working tree clean.
gd_assert_clean_tree

gd_pass

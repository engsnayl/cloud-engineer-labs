#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../tools" && pwd)/validate-helpers.sh"

# Still on feature
gd_assert_on_branch "feature"

# main untouched - 4 commits (A, B, C, D)
gd_assert_commit_count "main" "4" "main still has 4 commits"

# feature should now have 6 commits (A, B, C, D, X', Y')
gd_assert_commit_count "feature" "6" "feature has 6 commits (A, B, C, D, X', Y')"

# main..feature should be exactly 2 commits (X' and Y') - means rebase worked.
# If they merged, main..feature would have 1 merge commit.
gd_assert_commit_count "main..feature" "2" \
    "feature is exactly 2 commits ahead of main (rebase, not merge)"

# No merge commits anywhere on feature.
gd_assert_no_merges "feature"

# Sanity: all four files from main are present at HEAD (proves the rebase pulled in C and D).
gd_assert_file_contains_at_head "file-a.txt" "A"
gd_assert_file_contains_at_head "file-b.txt" "B"
gd_assert_file_contains_at_head "file-c.txt" "C"
gd_assert_file_contains_at_head "file-d.txt" "D"

# And feature's own files are still there.
gd_assert_file_contains_at_head "feature-x.txt" "X"
gd_assert_file_contains_at_head "feature-y.txt" "Y"

# Commit subjects on top of main should still mention the original X and Y work.
gd_assert_commit_message "main..feature" "feature work part one"
gd_assert_commit_message "main..feature" "feature work part two"

gd_pass

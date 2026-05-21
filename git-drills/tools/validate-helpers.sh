#!/usr/bin/env bash
# validate-helpers.sh - assertion helpers for drill validate scripts.
# Source this at the top of any validate.sh:
#   source "${GITDRILL_ROOT:-$HOME/cloud-engineer-labs/git-drills}/tools/validate-helpers.sh"
#
# Every check uses gd_assert. On failure it prints the reason and exits non-zero.
# Use gd_pass at the end to print a summary line.

if [[ -t 1 ]]; then
    _GD_R=$'\033[0;31m'; _GD_G=$'\033[0;32m'; _GD_Y=$'\033[0;33m'; _GD_X=$'\033[0m'
else
    _GD_R=''; _GD_G=''; _GD_Y=''; _GD_X=''
fi

GD_CHECKS_PASSED=0
GD_FAIL_REASON=""

# gd_assert <condition-as-string> <human-readable-description>
# The condition is evaluated with `eval`, so it's a normal shell test expression.
gd_assert() {
    local cond="$1" desc="$2"
    if eval "$cond"; then
        printf '  %s✓%s %s\n' "$_GD_G" "$_GD_X" "$desc"
        GD_CHECKS_PASSED=$((GD_CHECKS_PASSED + 1))
    else
        printf '  %s✗%s %s\n' "$_GD_R" "$_GD_X" "$desc"
        GD_FAIL_REASON="$desc"
        exit 1
    fi
}

# Assert a branch exists.
gd_assert_branch_exists() {
    local branch="$1"
    gd_assert "git show-ref --verify --quiet refs/heads/$branch" \
        "Branch '$branch' exists"
}

# Assert a branch does NOT exist.
gd_assert_branch_absent() {
    local branch="$1"
    gd_assert "! git show-ref --verify --quiet refs/heads/$branch" \
        "Branch '$branch' does not exist"
}

# Assert HEAD is on the given branch.
gd_assert_on_branch() {
    local branch="$1"
    local current
    current=$(git symbolic-ref --short -q HEAD || echo "DETACHED")
    gd_assert "[[ '$current' == '$branch' ]]" \
        "HEAD is on branch '$branch' (got: $current)"
}

# Assert the number of commits between two refs.
# Usage: gd_assert_commit_count <range> <expected> [description]
gd_assert_commit_count() {
    local range="$1" expected="$2" desc="${3:-Commit count in $range is $expected}"
    local actual
    actual=$(git rev-list --count "$range" 2>/dev/null || echo "ERR")
    gd_assert "[[ '$actual' == '$expected' ]]" "$desc (got: $actual)"
}

# Assert there are no merge commits in a range.
gd_assert_no_merges() {
    local range="$1"
    local merges
    merges=$(git log --merges --oneline "$range" 2>/dev/null | wc -l)
    gd_assert "[[ '$merges' -eq 0 ]]" "No merge commits in $range (found: $merges)"
}

# Assert a commit message matches a pattern somewhere in the given range.
# Usage: gd_assert_commit_message <range> <pattern>
gd_assert_commit_message() {
    local range="$1" pattern="$2"
    gd_assert "git log --format=%s '$range' 2>/dev/null | grep -q '$pattern'" \
        "Commit message matching '$pattern' found in $range"
}

# Assert NO commit message in a range matches a pattern (useful after squash/amend).
gd_assert_no_commit_message() {
    local range="$1" pattern="$2"
    gd_assert "! git log --format=%s '$range' 2>/dev/null | grep -q '$pattern'" \
        "No commit message matching '$pattern' in $range"
}

# Assert the working tree is clean (no unstaged or staged changes).
gd_assert_clean_tree() {
    gd_assert "git diff --quiet && git diff --cached --quiet" \
        "Working tree is clean (no staged or unstaged changes)"
}

# Assert there ARE staged changes (file in the index differs from HEAD).
gd_assert_staged_changes() {
    gd_assert "! git diff --cached --quiet" "There are staged changes"
}

# Assert there are NO staged changes.
gd_assert_no_staged_changes() {
    gd_assert "git diff --cached --quiet" "Index matches HEAD (nothing staged)"
}

# Assert a file is tracked by git.
gd_assert_tracked() {
    local path="$1"
    gd_assert "git ls-files --error-unmatch -- '$path' >/dev/null 2>&1" \
        "File '$path' is tracked"
}

# Assert a file is NOT tracked.
gd_assert_not_tracked() {
    local path="$1"
    gd_assert "! git ls-files --error-unmatch -- '$path' >/dev/null 2>&1" \
        "File '$path' is not tracked"
}

# Assert file content at HEAD contains a string.
gd_assert_file_contains_at_head() {
    local path="$1" needle="$2"
    gd_assert "git show HEAD:'$path' 2>/dev/null | grep -q -- '$needle'" \
        "File '$path' at HEAD contains '$needle'"
}

# Assert a tag exists.
gd_assert_tag_exists() {
    local tag="$1"
    gd_assert "git rev-parse --verify --quiet 'refs/tags/$tag' >/dev/null" \
        "Tag '$tag' exists"
}

# Assert two refs point to the same commit.
gd_assert_refs_equal() {
    local a="$1" b="$2"
    local sa sb
    sa=$(git rev-parse --verify --quiet "$a" 2>/dev/null || echo "X")
    sb=$(git rev-parse --verify --quiet "$b" 2>/dev/null || echo "Y")
    gd_assert "[[ '$sa' == '$sb' && '$sa' != 'X' ]]" \
        "Refs '$a' and '$b' point to the same commit"
}

# Assert two refs do NOT point to the same commit.
gd_assert_refs_differ() {
    local a="$1" b="$2"
    local sa sb
    sa=$(git rev-parse --verify --quiet "$a" 2>/dev/null || echo "X")
    sb=$(git rev-parse --verify --quiet "$b" 2>/dev/null || echo "Y")
    gd_assert "[[ '$sa' != '$sb' ]]" \
        "Refs '$a' and '$b' point to different commits"
}

# Final summary - call at end of validate.sh.
gd_pass() {
    printf '\n%s%d checks passed.%s\n' "$_GD_G" "$GD_CHECKS_PASSED" "$_GD_X"
    exit 0
}

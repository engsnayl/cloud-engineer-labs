#!/usr/bin/env bash
source "$(cd "$(dirname "$0")/../../tools" && pwd)/validate-helpers.sh"

# All three files should still exist in the working tree (we said not to delete them).
gd_assert "[[ -f notes.txt ]]"   "notes.txt still exists in the working tree"
gd_assert "[[ -f draft.txt ]]"   "draft.txt still exists in the working tree"
gd_assert "[[ -f secrets.txt ]]" "secrets.txt still exists in the working tree"

# notes.txt should be staged - it's new since the README-only HEAD, so it should
# appear as an "added" entry in the index.
gd_assert "git diff --cached --name-only | grep -qx 'notes.txt'" \
    "notes.txt IS staged"

# draft.txt and secrets.txt must NOT be staged.
gd_assert "! git diff --cached --name-only | grep -qx 'draft.txt'" \
    "draft.txt is NOT staged"
gd_assert "! git diff --cached --name-only | grep -qx 'secrets.txt'" \
    "secrets.txt is NOT staged"

# No commits should have been made beyond the initial one.
gd_assert_commit_count "HEAD" "1" "Still exactly 1 commit on HEAD (you didn't commit anything)"

gd_pass

#!/usr/bin/env bash
# seed-helpers.sh - shared functions for drill seed scripts.
# Source this at the top of any seed.sh: source "${GITDRILL_ROOT:-$HOME/cloud-engineer-labs/git-drills}/tools/seed-helpers.sh"

# Pin author/committer so commit hashes can be reasoned about if needed.
export GIT_AUTHOR_NAME="Drill Author"
export GIT_AUTHOR_EMAIL="author@gitdrill.local"
export GIT_COMMITTER_NAME="Drill Author"
export GIT_COMMITTER_EMAIL="author@gitdrill.local"

# Quiet down git's hint output during seeding
export GIT_ADVICE=0

# Initialise a fresh repo in the current dir with sensible defaults.
gd_init_repo() {
    git init --quiet --initial-branch=main
    git config user.name  "Drill Author"
    git config user.email "author@gitdrill.local"
    git config commit.gpgsign false
    git config advice.detachedHead false
    git config advice.statusHints false
}

# Create or overwrite a file with given content, then add+commit.
# Usage: gd_commit_file <path> <content> <commit-message>
gd_commit_file() {
    local path="$1" content="$2" msg="$3"
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
    git add "$path"
    git commit --quiet -m "$msg"
}

# Append a line to a file and commit.
gd_append_commit() {
    local path="$1" line="$2" msg="$3"
    printf '%s\n' "$line" >> "$path"
    git add "$path"
    git commit --quiet -m "$msg"
}

# Create a file but leave it staged (in the index, not committed).
gd_stage_file() {
    local path="$1" content="$2"
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
    git add "$path"
}

# Create a file in the working tree without staging it.
gd_unstaged_file() {
    local path="$1" content="$2"
    mkdir -p "$(dirname "$path")"
    printf '%s\n' "$content" > "$path"
}

# Make a "fake remote" by initialising a bare repo nearby and adding it as origin.
# Usage: gd_add_fake_remote [remote-name]
gd_add_fake_remote() {
    local name="${1:-origin}"
    local bare="../$(basename "$PWD")-${name}.git"
    git init --bare --quiet "$bare"
    git remote add "$name" "$bare"
    git push --quiet "$name" main 2>/dev/null || true
}

# Quick way to make N commits with predictable messages and content.
# Usage: gd_make_commits <count> [file] [msg-prefix]
gd_make_commits() {
    local count="$1" file="${2:-notes.txt}" prefix="${3:-commit}"
    local i
    for i in $(seq 1 "$count"); do
        printf 'line %d\n' "$i" >> "$file"
        git add "$file"
        git commit --quiet -m "${prefix} ${i}"
    done
}

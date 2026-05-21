# Solution: Create and switch to a feature branch

## TLDR

```
git switch -c feature/add-feature-file
echo "feature work" > feature.txt
git add feature.txt
git commit -m "Add feature.txt"
```

---

## Walkthrough (cold ticket)

`cd` in, get oriented:

```
git status
git log --oneline
git branch
```

You see: on branch `main`, one commit, no other branches. Clean tree.

### Step 1: Create and switch in one go

```
git switch -c feature/add-feature-file
```

The `-c` flag means "create the branch first, then switch to it". This
is the modern equivalent of `git checkout -b`. You can verify the switch
worked:

```
git branch
```

You should see an asterisk next to `feature/add-feature-file`.

Why this matters: in shared work, the most common screw-up is forgetting
to branch and committing straight to `main`. Doing the branch creation
and switch as one command is one less chance to forget.

### Step 2: Make the change

```
echo "feature work" > feature.txt
```

(Or any text editor - the content just has to be that one line.)

### Step 3: Stage, commit

```
git add feature.txt
git commit -m "Add feature.txt"
```

### Step 4: Confirm main is untouched

```
git log --oneline --all --decorate
```

You should see something like:

```
* abc1234 (HEAD -> feature/add-feature-file) Add feature.txt
* def5678 (main) Initial commit
```

Two branches, one commit ahead. Exactly the shape we want.

```
gitdrill validate
```

## Command breakdown

| Command                                  | What it does                                                                |
|------------------------------------------|-----------------------------------------------------------------------------|
| `git switch <branch>`                    | Move HEAD to an existing branch                                             |
| `git switch -c <branch>`                 | Create a new branch at the current commit AND switch to it                  |
| `git switch -c <branch> <start-point>`   | Create the branch starting from a different commit, then switch             |
| `git checkout -b <branch>`               | Older spelling of `switch -c`. Still works. `switch` is clearer.            |
| `git branch <name>`                      | Create the branch but don't switch to it                                    |
| `git branch -d <name>`                   | Delete a (merged) branch                                                    |
| `git branch -D <name>`                   | Force-delete a branch even if it has unmerged work - destructive            |

## `switch` vs `checkout`: why we prefer the newer one

`git checkout` has historically done two unrelated jobs:

  1. Move HEAD between branches/commits (the "switch" job)
  2. Restore files in the working tree from the index or a commit (the "restore" job)

This overloading caused a lot of accidental data loss - people would
type `git checkout <file>` thinking it would do one thing and it would
silently throw away their working changes.

Modern git split these into two clearer commands:

  - `git switch`   - just moves HEAD between branches
  - `git restore`  - just restores file contents

Stick with the new ones. They have safer defaults.

## Branch naming convention

`feature/add-feature-file` follows a common convention where branches
have a category prefix:

  - `feature/...` - new functionality
  - `fix/...`     - bug fixes
  - `chore/...`   - tooling, dependencies, no behaviour change
  - `hotfix/...`  - urgent production fixes

The forward-slash is allowed in branch names and gives some clients
nicer grouping in their branch lists. Not universal but widespread.

## Cleanup

`gitdrill reset` to restart, or move on to drill 004.

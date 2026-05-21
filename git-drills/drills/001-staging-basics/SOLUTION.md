# Solution: Staging basics

## TLDR

`git restore --staged draft.txt secrets.txt` removes both files from the index
without touching the working tree. `notes.txt` stays staged. Done.

---

## Walkthrough (cold ticket)

You open a terminal, `cd` in, and you have no idea what state this repo
is in. First instinct should always be the same.

```
git status
```

You see something like:

```
On branch main
Changes to be staged:
        new file:   draft.txt
        new file:   notes.txt
        new file:   secrets.txt
```

Three new files, all staged. The challenge said: leave `notes.txt` staged,
un-stage the other two, and don't lose the files from disk.

### Step 1: Understand the model before you reach for a command

There are three "places" where a file can live in git:

| Place         | What it is                                       |
|---------------|--------------------------------------------------|
| Working tree  | Actual files on disk you can edit                |
| Index (stage) | A snapshot of what the NEXT commit will contain  |
| HEAD          | The most recent commit on the current branch     |

`git add` copies from working tree → index.
`git restore --staged <file>` copies from HEAD → index (i.e. removes the
staged change), leaving the working tree alone.
`git restore <file>` copies from index → working tree (throws away unstaged edits).

The two `restore` commands look similar but do opposite-direction work.
The `--staged` flag is the one you want here because we want to keep
the files on disk.

### Step 2: Un-stage the files you don't want

```
git restore --staged draft.txt secrets.txt
```

No output is good output. Now check:

```
git status
```

You should see:

```
Changes to be staged:
        new file:   notes.txt

Untracked files:
        draft.txt
        secrets.txt
```

`notes.txt` is staged. The other two are now untracked - present on disk,
not in the index, not in any commit. Exactly what we want.

### Step 3: Validate

```
gitdrill validate
```

## Command breakdown

| Command                              | What it does                                                          |
|--------------------------------------|-----------------------------------------------------------------------|
| `git status`                         | Shows what's in the index vs working tree vs HEAD                     |
| `git restore --staged <file>`        | Removes a file from the index. Working tree is untouched.             |
| `git restore <file>` (no --staged)   | DANGEROUS in this context - would throw away unstaged edits.          |
| `git rm --cached <file>`             | Similar effect to restore --staged for new files, but the spelling is older and the semantics differ slightly for tracked files. Prefer `restore --staged`. |
| `git reset HEAD <file>`              | The old way of doing this, still works. `restore --staged` is the modern equivalent. |

## Lab vs real life

In real life this exact situation shows up most often when:

- You ran `git add .` in a hurry and pulled in something you shouldn't have
  (a `.env` file, a `node_modules/` slip-through, a debug `print(token)`).
- You're about to push and a `git status` second-glance catches it.
- A pre-commit hook flags a secret and you need to back the file out
  before re-running.

The mental discipline is: `git status` BEFORE every commit. It's
two seconds. It catches almost every "oh no I committed the
wrong thing" incident before it happens.

## Cleanup

The drill runner handles cleanup - `gitdrill reset` re-seeds the repo
from scratch if you want to do this again, and the whole working
directory lives in `/tmp` so a reboot tidies it for you.

# Solution: Amend the last commit

## TLDR

Fix the file, `git add lib.py`, then `git commit --amend -m "Add calculate_total helper"`.

---

## Walkthrough (cold ticket)

You arrive at the repo. The challenge says there's a typo. Start by
looking at what's actually there.

```
git log --oneline
```

Two commits. The latest is `Add calcualte_total helper`. Already a
clue - the message itself contains the typo.

```
cat lib.py
```

```
def calcualte_total(items):
    return sum(item.price for item in items)
```

Yep. `calcualte` is wrong, should be `calculate`. Both the code and
the commit message need fixing, and the constraint is no new commit on top.

### Step 1: Fix the file

Use your editor. `vi lib.py`, or:

```
sed -i 's/calcualte_total/calculate_total/' lib.py
```

Check:

```
cat lib.py
```

```
def calculate_total(items):
    return sum(item.price for item in items)
```

Good. Now the file is fixed in the working tree but not yet in the index
or in HEAD.

### Step 2: Stage the fix

```
git add lib.py
git status
```

The status now shows `lib.py` as a modified file in the index. If we
committed now, we'd get a NEW commit - exactly what the challenge said
not to do.

### Step 3: Amend instead of commit

`--amend` is the magic word. It tells git: "instead of making a new
commit, replace the most recent one with a new commit that includes
the current index AND lets me edit the message."

```
git commit --amend -m "Add calculate_total helper"
```

Now:

```
git log --oneline
```

Still two commits. The latest one has the corrected message AND
the file content fix folded into it.

### Step 4: Validate

```
gitdrill validate
```

## Command breakdown

| Command                                       | What it does                                                                          |
|-----------------------------------------------|---------------------------------------------------------------------------------------|
| `git commit --amend`                          | Replace the last commit with a new one made from the current index, edit message in $EDITOR |
| `git commit --amend -m "new msg"`             | Same, but skip the editor by passing the message inline                               |
| `git commit --amend --no-edit`                | Fold staged changes into the last commit, keep the existing message untouched         |
| `git commit --amend --reset-author`           | Useful if your git identity has changed since the original commit                     |

## The crucial caveat

Amending REWRITES history. The amended commit has a new SHA. The original
commit becomes unreachable (it lingers in the reflog for a while, then
gets garbage-collected).

This is fine if you haven't pushed. If you HAVE pushed, an amend means
your local branch and the remote branch have diverged, and you'd need
`git push --force-with-lease` to publish the change - which is a
collaboration hazard.

The rule of thumb: amend freely on commits that only exist locally.
Be very careful amending anything that's been pushed.

## Lab vs real life

This is one of the most common useful git operations and almost no one
teaches it. Typical real-life uses:

- Caught a typo a second after committing
- Forgot to add a file to the commit (`git add forgotten.py && git commit --amend --no-edit`)
- Pre-commit hook reformatted code - fold the formatter's changes into your commit
- Cleaning up a commit message before opening a PR

If you're new to it, get comfortable with `--amend --no-edit` first.
It's the safest variant - it just adds the staged changes into the
last commit without prompting for anything.

## Cleanup

Drill is self-contained in `/tmp`. `gitdrill reset` re-seeds.

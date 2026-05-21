# Solution: Reflog rescue

## TLDR

```
git reflog
# Find the line with "Important work do not lose" - note its SHA
git reset --hard <sha>
```

Or, if you want to bring just the lost commit back on top of where you
are now (rather than rewinding HEAD):

```
git cherry-pick <sha>
```

---

## Walkthrough (cold ticket)

`cd` in. The story: a commit existed, then a `git reset --hard` wiped
it. Start by surveying what you've got.

```
git log --oneline
```

Two commits. No sign of "Important work do not lose". The commit isn't
in the history of `main` anymore.

```
ls
```

`feature.txt` isn't there. `--hard` reset wipes the working tree too.

So the commit is unreachable from `main`. But "unreachable" in git is
not the same as "deleted". Git keeps every commit it's ever made for
a while (default ~90 days, controlled by `gc.reflogExpire` and
`gc.reflogExpireUnreachable`). We just need to find it.

### Step 1: Look at the reflog

The reflog is a per-clone log of every position HEAD has been at,
including ones the branch refs no longer point to. It's the safety net
for "I just lost something".

```
git reflog
```

You should see something like:

```
abc1234 HEAD@{0}: reset: moving to HEAD~1
def5678 HEAD@{1}: commit: Important work do not lose
abc1234 HEAD@{2}: commit: Add src.py
9999999 HEAD@{3}: commit (initial): Initial commit
```

There it is. Reading bottom up: initial commit, add src.py, then the
"Important work" commit at `HEAD@{1}`, then the reset that moved HEAD
back to the earlier commit at `HEAD@{0}`.

The SHA on the same line as `Important work do not lose` is your target.
You can refer to it either by that SHA or by `HEAD@{1}` - same thing
for now.

### Step 2: Decide how to bring it back

Two reasonable strategies:

**Option A: Rewind main to point at the lost commit.**
The lost commit was the previous tip of main, so this just undoes the
bad reset.

```
git reset --hard HEAD@{1}
```

Or equivalently with the SHA:

```
git reset --hard def5678
```

**Option B: Cherry-pick the commit on top of current HEAD.**
This makes a new commit on top of where you are now with the same
content and message. Useful if you've done other work in between
and don't want to rewind.

```
git cherry-pick def5678
```

Either approach satisfies this drill because the bad reset was the
most recent thing we did - HEAD@{0} and main are the same place. In
a more complex scenario the choice matters more.

### Step 3: Verify

```
git log --oneline
ls
cat feature.txt
```

Three commits, "Important work" on top, `feature.txt` present
with `critical changes` inside. Clean tree.

```
gitdrill validate
```

## Command breakdown

| Command                            | What it does                                                                       |
|------------------------------------|------------------------------------------------------------------------------------|
| `git reflog`                       | Show every position HEAD has been at recently. Newest first.                       |
| `git reflog show <ref>`            | Same, but for a specific branch ref's history (e.g. `git reflog show main`)        |
| `git reset --hard <commit>`        | Move current branch to `<commit>` and force working tree + index to match. Destructive to uncommitted work. |
| `git reset --soft <commit>`        | Move current branch to `<commit>` but keep index AND working tree as they are      |
| `git reset --mixed <commit>`       | Default. Move branch, keep working tree, reset index to `<commit>`                 |
| `git cherry-pick <commit>`         | Apply the changes from `<commit>` as a NEW commit on the current branch            |
| `git fsck --lost-found`            | Find dangling commits even when not in the reflog. Power-tool, rarely needed.      |

## The three flavours of reset, in one sentence

  - `--soft`  moves the branch label, leaves everything else alone (great for "unsquash my last commit").
  - `--mixed` (default) moves the branch label and rebuilds the index, leaves working tree alone.
  - `--hard`  moves the branch label AND rebuilds the index AND wipes the working tree to match. Brutal.

`--hard` is the one that gets people. It's the only one of the three
that can throw away uncommitted work. The rule of thumb: if you've
typed `--hard`, double-check before pressing Enter, and remember that
the reflog is there if you mess up.

## Lab vs real life

This is the single most valuable git trick to have in your back pocket
for interviews and for sanity. Common real-life scenarios:

  - Accidentally deleted a branch (`git reflog show <branch>` even after delete, if it's recent)
  - Bad rebase wiped out commits (`git reflog`, then `git reset --hard ORIG_HEAD`)
  - `git checkout -- file` threw away an hour of edits (these are NOT in reflog - reflog tracks commits, not working-tree state)
  - `git commit --amend` on the wrong commit (`git reflog` shows the pre-amend SHA)

The one thing reflog can't save you from: uncommitted work in the
working tree that you `git checkout`'d or `git restore`d away. That
content was never in any commit, so there's no commit to find.

## Cleanup

Drill resets via `gitdrill reset`. Reflog entries for `/tmp` repos
get cleaned up with the rest of `/tmp` anyway.

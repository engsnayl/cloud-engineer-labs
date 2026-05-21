# Solution: Rebase feature onto main

## TLDR

From `feature`:
```
git rebase main
```

That's it (assuming no conflicts - and this drill is conflict-free on purpose).

---

## Walkthrough (cold ticket)

`cd` in. First thing always:

```
git status
git log --oneline --all --decorate --graph
```

You should see something like:

```
* d4d4d4d (main) D: config tweak
* c3c3c3c        C: dependency bump
| * y2y2y2y (HEAD -> feature) Y: feature work part two
| * x1x1x1x        X: feature work part one
|/
* b2b2b2b B: add module skeleton
* a1a1a1a A: initial setup
```

The two branches diverged at B. Main moved forward to D. Feature moved
forward to Y. They share A and B.

### Step 1: Decide between merge and rebase

You have two ways to reconcile:

**Merge** (`git merge main` from feature):
- Creates a merge commit that joins the two histories
- Preserves the exact branching shape - you can see when work was done in parallel
- The history has a "diamond" in it, which some teams love and some hate

**Rebase** (`git rebase main` from feature):
- Replays your X and Y commits one at a time on top of main's current tip (D)
- The result is a clean linear history: A, B, C, D, X', Y'
- Your X and Y commits get new SHAs (hence the apostrophes - "X-prime")

The challenge said no merge commit, so we rebase.

### Step 2: Make sure you're on the branch being rebased

The branch you're standing on is the one that gets rewritten. Double-check:

```
git status
```

`On branch feature` - good.

### Step 3: Rebase

```
git rebase main
```

Git tells you something like:

```
Successfully rebased and updated refs/heads/feature.
```

Look at the graph now:

```
git log --oneline --all --decorate --graph
```

You should see a single linear chain: A, B, C, D, X', Y', with `feature`
at the top and `main` at D.

### Step 4: Validate

```
gitdrill validate
```

## Command breakdown

| Command                                 | What it does                                                                |
|-----------------------------------------|-----------------------------------------------------------------------------|
| `git rebase <upstream>`                 | Take the commits unique to the current branch, replay them on top of `<upstream>` |
| `git rebase --abort`                    | If you're mid-rebase and want to bail, this puts you back where you started |
| `git rebase --continue`                 | After resolving a conflict, tell git to keep going                          |
| `git rebase --skip`                     | Skip the current commit (use when one of your commits is now redundant)     |
| `git rebase -i <upstream>`              | Interactive rebase - reorder, squash, edit, drop commits before replay      |
| `git pull --rebase`                     | When pulling from a remote, rebase your local commits on top instead of merging |

## The crucial mental model

Rebase = **rewriting history**. Each commit on the rebased branch gets
a new SHA. The old commits are not destroyed immediately - they linger
in the reflog - but anyone else's checkout of your branch now refers
to commits that don't exist on yours.

Translation: **don't rebase commits you've already pushed to a shared branch.**

If you rebase a branch you've pushed, you'll need `git push --force-with-lease`
to publish it. That can stomp on other people's work if they've based
work on top of your old commits. `--force-with-lease` is safer than
`--force` because it refuses to overwrite if the remote has moved in
ways you weren't aware of.

Most teams settle on a rule like:

  - Rebase freely on your own personal feature branch before opening a PR
  - Never rebase `main`, `develop`, `release/*`, or any branch others may branch from

## Lab vs real life

This drill is the simplest possible rebase: no conflicts, no edits,
just a clean replay. Real life usually has conflicts. The pattern is:

  1. `git rebase main`
  2. Git pauses on the first conflicting commit, prints affected files
  3. Edit files, `git add` the resolved ones
  4. `git rebase --continue`
  5. Repeat 2-4 for each conflicting commit
  6. Done

Later drills cover conflict resolution explicitly. For now, get
comfortable with the conflict-free case so the muscle memory is there.

## Cleanup

`gitdrill reset` to retry.

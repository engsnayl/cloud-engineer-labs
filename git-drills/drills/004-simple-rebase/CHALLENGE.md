# Rebase a feature branch onto an updated main

Topic: git rebase, linear history

You're working on a `feature` branch that diverged from `main` two commits ago.
Since then, `main` has moved forward with another two commits (someone else's
work that got merged in).

Right now:

  - `main` has commits:    A → B → C → D
  - `feature` has commits: A → B → X → Y

You want feature to look as if you started it from D, so the history
looks like: A → B → C → D → X' → Y'

Do NOT use a merge commit. The goal is a linear history with your
two commits on top of the latest main.

## What you need to do

End up with:

  - HEAD still on the `feature` branch
  - `feature` containing commits A, B, C, D, then your two commits on top
  - No merge commits anywhere in `feature`
  - `main` unchanged

## What you'll practise

- `git rebase` for moving a branch's base to a newer commit
- The "rebase vs merge" mental model
- Why feature branches usually want rebase, not merge, before review

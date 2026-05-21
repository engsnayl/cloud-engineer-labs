# Create a feature branch and commit to it

Topic: git switch, git branch, branch hygiene

You're on the `main` branch and need to start a new piece of work.
The team's convention is to never commit directly to `main` - all
work happens on a feature branch.

The work itself is small: add a new file called `feature.txt`
containing the line `feature work` (no trailing whitespace, just
that one line plus a newline), then commit it.

## What you need to do

End up with:

  - A branch called `feature/add-feature-file` that exists
  - HEAD currently on that branch
  - One new commit on `feature/add-feature-file` that adds `feature.txt`
  - The `main` branch UNCHANGED - still pointing at the initial commit
  - The new file `feature.txt` tracked at HEAD on the feature branch

## What you'll practise

- Creating a branch and switching to it in one step
- Why `git switch -c` is preferred over `git checkout -b`
- Confirming you're on the right branch before committing

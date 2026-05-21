# Reflog rescue: recover a "lost" commit

Topic: git reflog, recovering from a bad reset

You just had a bad afternoon. You were on `main` working on
`feature.txt`. You made a commit with the message `Important work
do not lose`. Then, in a hurry, you ran a `git reset --hard` and
threw the commit away. The file is gone from your working tree.

It's not actually gone - git keeps unreachable commits around for a
while. You need to find it and bring it back.

## What you need to do

End up with:

  - HEAD on `main`
  - A commit on `main` with the EXACT message `Important work do not lose`
  - The file `feature.txt` tracked at HEAD, containing the line `critical changes`
  - A clean working tree

You may not look at any backup, scratch file, or hint outside the
repo itself. Use git's own machinery to find the lost commit.

## What you'll practise

- `git reflog` to see every position HEAD has been at recently
- Recovering an unreachable commit with `git reset` or `git cherry-pick`
- The reassurance that almost nothing in git is truly destroyed for ~90 days

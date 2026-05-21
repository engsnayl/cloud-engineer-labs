# Staging basics: get the right things ready to commit

Topic: git add, git restore --staged, git status

You walked into a repo where someone has been editing files but hasn't
committed anything yet. There are three files in the working tree:

  - notes.txt        contains real work you want to keep
  - draft.txt        a scratch file you do NOT want to commit
  - secrets.txt      contains a password - definitely do NOT commit

Currently, all three are staged.

## What you need to do

Get the index into a state where ONLY `notes.txt` is staged, ready to
be committed. Do not commit anything. Do not delete any files from
the working tree - just adjust what's in the index.

## What you'll practise

- Reading `git status` output carefully
- The difference between the working tree and the index ("staging area")
- Un-staging files without losing your work

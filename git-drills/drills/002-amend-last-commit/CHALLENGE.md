# Amend the last commit: fix a typo without making a new commit

Topic: git commit --amend, history rewriting basics

You just made a commit that adds a function, but you spelled the
function name wrong in BOTH the code and the commit message. You
realise this before pushing.

Look at the most recent commit. The function is called `calcualte_total`
in the file `lib.py`. It should be `calculate_total`. The commit message
also reads `Add calcualte_total helper` and should read
`Add calculate_total helper`.

## What you need to do

End up with the same NUMBER of commits as you have now, but with:

  - the function correctly named `calculate_total` in `lib.py`
  - the latest commit message corrected to `Add calculate_total helper`

Do not add a new commit on top.

## What you'll practise

- `git commit --amend` to rewrite the last commit
- Staging changes BEFORE amending so they're folded into the commit
- The rule: amending is fine before you push, dangerous after

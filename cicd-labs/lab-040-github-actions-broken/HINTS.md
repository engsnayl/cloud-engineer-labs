# Hints — CI/CD Lab 040: GitHub Actions

## Hint 1 — Job names
Job names can't have spaces. Change "build and test" to "build-and-test" or "build_and_test".

## Hint 2 — Environment variables
`echo "NODE_ENV=test"` just prints to stdout. To set a persistent env var: `echo "NODE_ENV=test" >> $GITHUB_ENV`

## Hint 3 — Conditional deploy
Add `if: github.event_name == 'push' && github.ref == 'refs/heads/main'` to the deploy step.

## Hint 4 — Fix the dependency
The `needs:` value must exactly match the job name you defined above.

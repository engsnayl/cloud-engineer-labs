# Hints — Bash Script Debugging

## Hint 1
Variable assignment in Bash has NO spaces around `=`. `VAR=value` works, `VAR = value` does not.

## Hint 2
Run `shellcheck healthcheck.sh` to find common issues. It catches unquoted variables, missing error handling, and syntax problems.

## Hint 3
`set -euo pipefail` at the top of a script makes it fail on errors (-e), undefined variables (-u), and pipe failures (-o pipefail). But be careful — `grep` returns exit code 1 when there are no matches, which triggers -e.

## Hint 4
When using `set -e`, wrap commands that might legitimately fail in `|| true` or use `if` statements.

## Hint 5
Always quote variables: `"$LOG_DIR"` not `$LOG_DIR`. Unquoted variables break with spaces in paths.

## Hint 6
Use `mkdir -p` to create directories that might not exist. The `-p` flag means "no error if existing, make parent directories as needed".

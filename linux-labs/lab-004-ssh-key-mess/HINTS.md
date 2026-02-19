# Hints — Lab 004: SSH Key Mess

## Hint 1 — Start with the SSH daemon
Check if sshd is running. Look at the sshd_config file — what authentication methods are enabled?

## Hint 2 — The permission trinity
SSH is very strict about permissions. The `.ssh` directory must be 700, `authorized_keys` must be 600, and both must be owned by the user (not root). Check all three.

## Hint 3 — Ownership matters
Use `ls -la /home/deploy/` to check who owns the `.ssh` directory. Use `chown -R deploy:deploy /home/deploy/.ssh` to fix ownership.

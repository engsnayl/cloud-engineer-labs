# Hints — Lab 008: User Permissions Broken

## Hint 1 — Check current state
Run `ls -la /opt/` and `ls -la /etc/app/` to see who owns what. Then check `id appuser` to see what groups the user belongs to.

## Hint 2 — Group membership is key
The data directory should be owned by `appgroup` so multiple services can share it. Use `chown :appgroup /opt/data` and `chmod 775 /opt/data` to allow group write access.

## Hint 3 — Don't forget to add the user to the group
`usermod -aG appgroup appuser` adds appuser to appgroup. For the config file, you can either change its group or make it world-readable (640 with appgroup, or 644).

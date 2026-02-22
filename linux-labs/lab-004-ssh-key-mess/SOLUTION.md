# Solution Walkthrough — SSH Key Mess

## The Problem

SSH (Secure Shell) key-based authentication is broken for the `deploy` user. This is the secure, passwordless way that automated systems and engineers connect to servers. There are **four issues** preventing it from working:

1. **Wrong permissions on the `.ssh` directory** — it's set to `777` (world-readable/writable) when SSH requires `700` (owner only). SSH intentionally refuses to work when permissions are too open, because it means other users on the system could tamper with your authentication files.
2. **Wrong permissions on `authorized_keys`** — it's set to `644` (world-readable) when SSH requires `600` (owner read/write only). Same security reasoning as above.
3. **Wrong ownership** — the entire `.ssh` directory is owned by `root` instead of the `deploy` user. SSH checks that the user's authentication files are actually owned by that user.
4. **Public key authentication is disabled in `sshd_config`** — the SSH server configuration has `PubkeyAuthentication no`, which means even if all the file permissions were correct, the server would still reject key-based login attempts.

## Thought Process

When SSH key auth fails, an experienced engineer thinks about it in layers:

1. **Is the SSH daemon even running?** Check with `pgrep sshd` or `service ssh status`.
2. **Is key auth enabled?** Look at `/etc/ssh/sshd_config` for `PubkeyAuthentication`. If it says `no`, nothing else matters.
3. **The permission trinity** — SSH is famously strict about permissions. You need to check three things: the `.ssh` directory (must be `700`), the `authorized_keys` file (must be `600`), and the ownership of both (must belong to the user, not root).
4. **Is the right public key in `authorized_keys`?** Make sure the key matches the private key being used to connect.

The reason SSH is so strict about permissions is security: if other users could read or modify your `authorized_keys` file, they could add their own public key and gain access to your account.

## Step-by-Step Solution

### Step 1: Check the SSH server configuration

```bash
grep -i pubkeyauthentication /etc/ssh/sshd_config
```

**What this does:** Searches the SSH daemon configuration file for the `PubkeyAuthentication` setting. The `-i` flag makes the search case-insensitive. You'll see it's set to `no`, which means the server is configured to reject all public key authentication attempts.

### Step 2: Enable public key authentication

```bash
sed -i 's/PubkeyAuthentication no/PubkeyAuthentication yes/' /etc/ssh/sshd_config
```

**What this does:** Changes `PubkeyAuthentication no` to `PubkeyAuthentication yes` in the SSH server configuration. This tells the SSH daemon to accept public key authentication. The `sed -i` command edits the file in place.

### Step 3: Check current permissions and ownership

```bash
ls -la /home/deploy/.ssh/
```

**What this does:** Lists the `.ssh` directory contents with detailed information including permissions and ownership. The `-la` flags mean "long format" and "include hidden files." You'll see that the directory is owned by `root` (should be `deploy`) and has `777` permissions (should be `700`).

### Step 4: Fix the ownership

```bash
chown -R deploy:deploy /home/deploy/.ssh
```

**What this does:** Changes the owner and group of the `.ssh` directory and everything inside it to `deploy`. The `-R` flag means "recursive" — it applies to the directory and all its contents. `deploy:deploy` means "set both the user owner and the group owner to deploy."

### Step 5: Fix the .ssh directory permissions

```bash
chmod 700 /home/deploy/.ssh
```

**What this does:** Sets the permissions on the `.ssh` directory to `700`, which means:
- **7** (owner = `deploy`): read + write + execute (enter the directory)
- **0** (group): no access at all
- **0** (others): no access at all

This is required because SSH refuses to use key files from a directory that other users can access.

### Step 6: Fix the authorized_keys file permissions

```bash
chmod 600 /home/deploy/.ssh/authorized_keys
```

**What this does:** Sets the permissions on `authorized_keys` to `600`, which means:
- **6** (owner = `deploy`): read + write
- **0** (group): no access
- **0** (others): no access

### Step 7: Restart the SSH daemon

```bash
service ssh restart
```

**What this does:** Restarts the SSH server so it picks up the configuration change we made to `sshd_config`. Configuration changes don't take effect until the daemon is restarted or reloaded.

### Step 8: Verify the fix

```bash
stat -c "%a %U" /home/deploy/.ssh
stat -c "%a %U" /home/deploy/.ssh/authorized_keys
grep PubkeyAuthentication /etc/ssh/sshd_config
```

**What this does:** Verifies all three fixes are in place. The `stat -c "%a %U"` command shows the permissions (as a number) and owner (as a name) of a file. You should see `700 deploy` for the directory, `600 deploy` for the keys file, and `PubkeyAuthentication yes` in the config.

## Docker Lab vs Real Life

- **Restarting SSH:** In this lab we use `service ssh restart`. On a modern production server, you'd use `systemctl restart sshd` (note: it's `sshd` not `ssh` on Red Hat/CentOS systems). You can also use `systemctl reload sshd` to apply config changes without dropping existing connections.
- **Debugging SSH:** On a real server, the SSH auth log at `/var/log/auth.log` (Debian/Ubuntu) or `/var/log/secure` (Red Hat/CentOS) tells you exactly why authentication failed. You can also use `ssh -vvv user@host` from the client side for detailed debugging output.
- **Key management:** In production, SSH keys are typically managed through configuration management tools (Ansible, Puppet, Chef) or centralized identity systems (AWS SSM, HashiCorp Vault), not by manually placing files on servers.
- **sshd_config changes:** On production servers, always run `sshd -t` to test the config before restarting, just like `nginx -t`. A bad sshd_config can lock you out of the server.

## Key Concepts Learned

- **SSH is deliberately strict about permissions** — this is a security feature, not a bug. If your key files are world-readable, SSH won't trust them.
- **The SSH permission requirements:** `.ssh` directory = `700`, `authorized_keys` = `600`, both owned by the user
- **`sshd_config` is the server-side configuration** — it controls what authentication methods the server accepts. Changing it requires a daemon restart.
- **Ownership and permissions are separate things** — a file can have the right permissions (`600`) but the wrong owner (`root`), or vice versa. Both must be correct.
- **Always check multiple layers** — a working SSH setup requires the daemon running, the right config, correct permissions, correct ownership, and the right key in the file

## Common Mistakes

- **Using `chmod 777` to "fix" permissions** — this is the opposite of what SSH wants. SSH needs restrictive permissions, not open ones. `777` means "everyone can read and write this," which is a security nightmare.
- **Fixing permissions but forgetting ownership** — even with `700` permissions, if `root` owns the directory, the `deploy` user can't access it.
- **Forgetting to restart sshd** — changing `sshd_config` does nothing until the daemon is restarted or reloaded. This is a common "I made the change, why isn't it working?" moment.
- **Fixing some issues but not all** — SSH requires ALL of these to be correct simultaneously. Fixing permissions without fixing ownership (or vice versa) won't help.
- **Not checking `sshd_config` at all** — many people go straight to checking file permissions and spend a long time debugging, when the real problem is that key auth is disabled server-wide.

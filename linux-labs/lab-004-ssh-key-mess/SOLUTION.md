# Lab 04 — SSH Key Mess: Solution Walkthrough

---

## TLDR Summary

SSH key-based authentication lets you log in to a server without a password — it uses a pair of cryptographic keys instead. When it breaks, it's almost always one of a small number of causes: the SSH server isn't configured to accept keys, the key files have the wrong permissions, or the files are owned by the wrong user. In this lab, all four of those problems are present at once. The SSH daemon has key auth switched off, the `.ssh` folder has permissions so open that SSH refuses to trust it, the `authorized_keys` file is readable by everyone when it should be private, and everything is owned by `root` instead of the `deploy` user. You'll work through each issue in turn — the same way an engineer would in real life: start at the server config, then check the file security layer by layer.

---

## The Four Faults

| # | What's wrong | What it should be |
|---|---|---|
| 1 | `sshd_config` has `PubkeyAuthentication no` | `PubkeyAuthentication yes` |
| 2 | `.ssh` directory permissions are `777` | Must be `700` |
| 3 | `authorized_keys` permissions are `644` | Must be `600` |
| 4 | `.ssh` directory and files owned by `root` | Must be owned by `deploy` |

---

## Where Do These Files Live and Why?

Before diving into the fix, it's worth understanding where these files are and why — so you're not just memorising paths.

### `/etc/ssh/sshd_config`

On Linux, `/etc` is the standard location for **system-wide configuration files**. This has been a convention since the earliest Unix systems. The pattern is consistent across every service:

| Service | Config location |
|---|---|
| SSH daemon | `/etc/ssh/sshd_config` |
| Nginx | `/etc/nginx/nginx.conf` |
| MySQL | `/etc/mysql/my.cnf` |

So when something system-level is broken, `/etc/<service-name>/` is always the first place to look for its config. If you genuinely don't know where a config file lives, you can find it with:

```bash
find /etc -name "sshd_config"
```

Or check the manual page: `man sshd` always lists the config file location.

### The `.ssh` directory

The `.ssh` directory lives inside the **user's home directory** — for example `/home/deploy/.ssh`. This is because everything in `.ssh` is **per-user** data. It contains that specific user's keys, trust settings, and connection config. If it lived in `/etc/ssh/`, it would be system-wide and shared. By putting it in `~/.ssh/` (where `~` means home directory), each user on the system has their own completely separate authentication setup.

The files inside `.ssh` and what they do:

| File | Purpose |
|---|---|
| `authorized_keys` | List of public keys permitted to log in *as this user* |
| `id_rsa` / `id_ed25519` | The user's own private key (used when *they* connect outward) |
| `known_hosts` | Servers this user has previously trusted |
| `config` | User-specific SSH connection shortcuts and settings |

**The dot prefix** means it's a hidden directory — `ls` without `-a` won't show it. Linux hides anything starting with `.` by convention; these are typically config files the user doesn't need to see day-to-day. The `-a` flag on `ls` is what reveals them.

### If you don't know where `.ssh` is — how to find it

```bash
find / -name ".ssh" -type d 2>/dev/null
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `find` | Search tool — walks the filesystem looking for matches |
| `/` | Start from the root — search everything |
| `-name ".ssh"` | Look for something named exactly `.ssh` |
| `-type d` | Only match directories (not files named `.ssh`) |
| `2>/dev/null` | Suppress error messages — redirects stderr (stream 2) to `/dev/null`, Linux's black hole for unwanted output. Without this, `find` floods the terminal with "Permission denied" warnings for directories it can't read. |

---

## Understanding Linux File Ownership

Every file and directory on Linux has **two** ownership attributes — a user owner and a group owner:

```
-rw-r--r--  1  root  root  99  authorized_keys
                 ↑     ↑
            user    group
            owner   owner
```

**User owner** — the individual account that owns the file.
**Group owner** — a group of users that share some level of access.

### What is a group?

Linux groups are a way of saying "these accounts belong to the same team" and granting them shared access. Common examples:

| Group | Typical members |
|---|---|
| `sudo` | Users allowed to run admin commands |
| `docker` | Users allowed to run Docker commands |
| `www-data` | The web server process |
| `deploy` | In this lab — the deploy user's personal group |

When you create a user on Linux, it **automatically creates a group with the same name**. So when the `deploy` user was created, a `deploy` group was created alongside it. That's why you see `deploy deploy` — it's not two different things, it's the user and their personal group sharing the same name. This is standard Linux behaviour.

**Is `deploy` a special or widespread group name?** No — it's just the username chosen for this lab. In real life you'd see whatever the user's name is: `ubuntu ubuntu`, `ec2-user ec2-user`, `jenkins jenkins`. The pattern of `username:username` in `chown` commands is universal.

### Why `root root` on the SSH files causes the failure

When the files show `root root`, it means they were created by the admin account and belong to the root group. The `deploy` user has no ownership claim over them. SSH sees this and refuses — it will only use authentication files that are actually owned by the user trying to log in.

**The files exist. The keys are in there. But SSH won't touch them because they belong to root, not deploy.**

---

## Why SSH Is So Strict About Permissions — StrictModes

SSH doesn't warn you about loose permissions. It **hard blocks** authentication and refuses entirely.

This is controlled by a feature called **StrictModes**, which is enabled by default. When StrictModes is on, SSH checks permissions on the relevant files *before* it even attempts authentication. If anything is too open, it rejects immediately and logs:

```
Authentication refused: bad ownership or modes for directory /home/deploy/.ssh
```

The reason for this strictness: if your `authorized_keys` file is readable or writable by other users, any of them could add their own public key and gain access to your account. SSH treats open permissions as evidence the file has been compromised.

You can disable StrictModes with `StrictModes no` in `sshd_config` — but you would **never** do this in production. Any security audit would flag it immediately.

**The SSH permission requirements:**

| What | Required permission | Why |
|---|---|---|
| `.ssh` directory | `700` — owner only | No other user should be able to enter it |
| `authorized_keys` | `600` — owner read/write only | No other user should be able to read or modify it |
| Both | Owned by the user, not root | SSH verifies the user owns their own auth files |

### Why `600` and not `700` for `authorized_keys`?

`authorized_keys` is a **plain text file**, not a script or program. It contains a list of public keys — there's nothing to execute. Execute permission (`1`) only makes sense for files that are meant to be run as programs. For a config file, it's meaningless. `600` means the owner can read and write it, and nobody else can touch it. That's all it needs.

---

## How to Read `ls -la` Output

```
drwxrwxrwx 2 root   root   4096 Mar 25 07:18 .
drwxr-x--- 3 deploy deploy 4096 Mar 25 07:18 ..
-rw-r--r-- 1 root   root     99 Mar 25 07:18 authorized_keys
```

### The `.` and `..` entries

These are not files you created — they exist in **every single directory on Linux**:

| Entry | Meaning |
|---|---|
| `.` | This directory — a reference to itself |
| `..` | The parent directory — one level up |

You use them constantly without thinking: `cd ..` goes up one level, `./script.sh` runs something in the current directory. They only appear because of the `-a` flag. Skip past them mentally and focus on the actual contents below.

### Reading the permissions string

```
d  rwx  rwx  rwx
↑   ↑    ↑    ↑
│  owner group everyone
│
d = directory, - = file
```

Each three-character block is **r** (read=4), **w** (write=2), **x** (execute/enter=1). Add them together for the numeric value:

| String | Numeric | Meaning |
|---|---|---|
| `rwx` | 7 | Read + write + execute |
| `rw-` | 6 | Read + write only |
| `r--` | 4 | Read only |
| `---` | 0 | No access |

So `drwxrwxrwx` = directory, 777 = everyone has full access. `drwx------` = directory, 700 = owner only.

---

## Step-by-Step Learning Pathway

This section walks you through how to *think* about this problem, not just what commands to run. Follow the reasoning — that's the part that transfers to real jobs.

---

### Step 1 — Is SSH key auth even turned on?

Before touching any files, check whether the SSH server is configured to accept key-based logins at all. This is the most fundamental question: you could have perfect key files and still be blocked if the server is configured to ignore them.

**Why check this first?** Because `PubkeyAuthentication no` is a master switch. If it's off, nothing else you fix will matter. An experienced engineer always checks the config layer before the file layer.

**Where to look:** `/etc/ssh/sshd_config` — the SSH daemon's server-side configuration file.

```bash
grep -i pubkeyauthentication /etc/ssh/sshd_config
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `grep` | Search tool — scans files for a matching pattern |
| `-i` | Case-insensitive — matches regardless of capitalisation |
| `pubkeyauthentication` | The string to search for |
| `/etc/ssh/sshd_config` | The SSH server configuration file |

**What you expect to find:** `PubkeyAuthentication no` — confirming key auth is disabled server-wide.

---

### Step 2 — Fix the server config

Now that you've confirmed the fault, fix it.

```bash
sed -i 's/PubkeyAuthentication no/PubkeyAuthentication yes/' /etc/ssh/sshd_config
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `sed` | Stream editor — processes and transforms text in files |
| `-i` | Edit the file in place (instead of printing output to terminal) |
| `'s/old/new/'` | Substitution syntax: find `old`, replace with `new` |
| `PubkeyAuthentication no` | The string being replaced |
| `PubkeyAuthentication yes` | The replacement string |
| `/etc/ssh/sshd_config` | The file to edit |

**Verify the change:**

```bash
grep -i pubkeyauthentication /etc/ssh/sshd_config
```

You should now see `PubkeyAuthentication yes`.

> **Important:** Config changes don't take effect until the daemon is restarted. Don't restart yet — finish diagnosing the file layer first, then do a single restart at the end.

---

### Step 3 — Find the `.ssh` directory

If you don't know where the `.ssh` directory is, find it:

```bash
find / -name ".ssh" -type d 2>/dev/null
```

This returns `/home/deploy/.ssh` — confirming the location before you start inspecting it.

---

### Step 4 — Inspect permissions and ownership

Now check the file layer. You need to see three things: permissions, user owner, and group owner.

```bash
ls -la /home/deploy/.ssh/
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `ls` | List directory contents |
| `-l` | Long format — shows permissions, ownership, size, date |
| `-a` | Include hidden entries (`.` and `..`) |
| `/home/deploy/.ssh/` | The directory to inspect |

**What you'll see that's wrong:**

| Item | Shown | Should be |
|---|---|---|
| `.ssh` directory permissions | `drwxrwxrwx` (777) | `drwx------` (700) |
| `.ssh` directory owner | `root root` | `deploy deploy` |
| `authorized_keys` permissions | `-rw-r--r--` (644) | `-rw-------` (600) |
| `authorized_keys` owner | `root root` | `deploy deploy` |

All four problems are visible in this single output. SSH is blocking because the files belong to root (not deploy) and the permissions are too open for SSH to trust them.

---

### Step 5 — Fix ownership first

Fix ownership before permissions. If `root` owns the files, ensure the `deploy` user can access them — ownership comes first.

```bash
chown -R deploy:deploy /home/deploy/.ssh
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `chown` | Change file ownership |
| `-R` | Recursive — apply to the directory and everything inside it |
| `deploy:deploy` | Set user owner to `deploy`, group owner to `deploy` |
| `/home/deploy/.ssh` | The target directory |

**Why `deploy:deploy`?** Linux files have two ownership attributes — user and group. `chown user:group` sets both at once. `deploy:deploy` is the standard pattern when a user should fully own their own files.

Verify: `ls -la /home/deploy/.ssh/` — the third and fourth columns should now show `deploy deploy` on all entries.

---

### Step 6 — Fix the `.ssh` directory permissions

```bash
chmod 700 /home/deploy/.ssh
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `chmod` | Change file permissions |
| `700` | Owner: read+write+enter. Group: none. Everyone: none. |
| `/home/deploy/.ssh` | The directory to fix |

**Understanding `700`:**

| Digit | Who | Permissions | Numeric value |
|---|---|---|---|
| `7` | Owner (deploy) | Read + Write + Execute/Enter | 4+2+1 = 7 |
| `0` | Group | No access | 0 |
| `0` | Everyone else | No access | 0 |

> Execute on a directory means the ability to enter it (`cd` into it) — not running a program.

---

### Step 7 — Fix the `authorized_keys` permissions

```bash
chmod 600 /home/deploy/.ssh/authorized_keys
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `chmod` | Change file permissions |
| `600` | Owner: read+write. Group: none. Everyone: none. |
| `/home/deploy/.ssh/authorized_keys` | The file to fix |

**Understanding `600`:**

| Digit | Who | Permissions | Numeric value |
|---|---|---|---|
| `6` | Owner (deploy) | Read + Write | 4+2 = 6 |
| `0` | Group | No access | 0 |
| `0` | Everyone else | No access | 0 |

No execute permission — `authorized_keys` is a plain text file. There's nothing to run.

---

### Step 8 — Restart the SSH daemon

Both the config and file permissions are now fixed. Restart the daemon so it picks up the `sshd_config` change.

```bash
service ssh restart
```

**Command breakdown:**

| Part | What it does |
|---|---|
| `service` | Manages system services |
| `ssh` | The SSH daemon service name on this system |
| `restart` | Stop then start the service |

> **In production:** Use `systemctl restart sshd`. On Red Hat/CentOS the service name is `sshd` not `ssh`. Use `systemctl reload sshd` to apply config changes without dropping active connections.

> **Safety tip:** In production, always run `sshd -t` to validate config syntax before restarting. A typo in `sshd_config` can prevent the daemon from starting, potentially locking you out of the server. It's the SSH equivalent of `nginx -t`.

---

### Step 9 — Verify all fixes

Don't assume it worked — verify each fix independently.

```bash
stat -c "%a %U" /home/deploy/.ssh
stat -c "%a %U" /home/deploy/.ssh/authorized_keys
grep PubkeyAuthentication /etc/ssh/sshd_config
```

**Command breakdown (`stat`):**

| Part | What it does |
|---|---|
| `stat` | Show detailed file metadata |
| `-c` | Use a custom output format |
| `"%a %U"` | `%a` = permissions as a number, `%U` = owner username |

**Expected output:**

```
700 deploy          ← .ssh directory: correct permissions and owner ✓
600 deploy          ← authorized_keys: correct permissions and owner ✓
PubkeyAuthentication yes    ← key auth enabled in sshd_config ✓
```

If any line is wrong, go back to the relevant step and re-apply.

---

## No Cleanup Required

This lab runs inside a Docker container. All changes you made exist only within the container's filesystem — when you stop and restart the lab, Docker spins up a fresh container from the original image with all four faults intact. The broken state is automatically restored with no action needed.

This is different from the Kubernetes and Terraform labs where changes persist to a real cluster or real AWS infrastructure between sessions — which is why those labs have explicit cleanup sections.

---

## Docker Lab vs Real Life

- **Restarting SSH:** This lab uses `service ssh restart`. On production servers use `systemctl restart sshd`. Service name is `sshd` (not `ssh`) on Red Hat/CentOS.
- **Debugging from the client side:** `ssh -vvv deploy@<host>` gives maximum verbosity output showing exactly where the handshake failed — which file it couldn't find, which key was rejected, whether it fell back to password auth. In this lab container, the equivalent would be `ssh -vvv deploy@localhost`.
- **Debugging from the server side:** Check `/var/log/auth.log` (Debian/Ubuntu) or `/var/log/secure` (Red Hat/CentOS) for SSH failure messages with exact reasons.
- **Key management at scale:** In production, SSH keys are managed through Ansible, Puppet, or centralised identity systems (AWS Systems Manager, HashiCorp Vault) — not placed on servers manually.
- **Config validation:** Always run `sshd -t` before restarting in production. Catches syntax errors before they cause an outage.

---

## Common Mistakes

- **Using `chmod 777` to "fix" it** — the opposite of what SSH wants. `777` means everyone can read and write, which causes SSH to refuse the files outright.
- **Fixing permissions but not ownership** — even with correct `700` permissions, if `root` owns the directory, the `deploy` user can't use it. Both must be correct simultaneously.
- **Forgetting to restart the daemon** — changing `sshd_config` does nothing until the daemon restarts. One of the most common "I made the change, why isn't it working?" moments.
- **Fixing some issues but not all** — SSH requires all layers to be correct at the same time. A partial fix still results in failure.
- **Skipping `sshd_config` entirely** — many people jump straight to file permissions and spend a long time debugging, when the actual problem is that key auth is switched off server-wide. Always start at the config layer.
- **Not knowing about StrictModes** — SSH's hard block on loose permissions is a named feature (`StrictModes`). Understanding this explains *why* SSH behaves this way, not just *what* to fix.

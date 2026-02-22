# Solution Walkthrough — User Permissions Broken

## The Problem

An application user (`appuser`) can't do its job because of **three permission-related issues**:

1. **The data directory `/opt/data` is owned by root** — the `appuser` needs to write files here (like generated reports or processed data), but it's owned by `root:root` with permissions `755`. That means only root can write to it — `appuser` can only read and enter the directory.
2. **The config file `/etc/app/config.yml` is unreadable** — it has permissions `600` and is owned by `root:root`. The `600` means only the owner (root) can read it. The application, running as `appuser`, can't read its own configuration file.
3. **`appuser` is not a member of `appgroup`** — the application is designed so that the data directory should be group-owned by `appgroup`, and all application users should be members of that group. But `appuser` was never added to `appgroup`.

This is a very realistic scenario. In production, applications typically run as non-root users for security, and getting the ownership/group/permission chain correct is critical.

## Thought Process

When an application user can't access files it needs, an experienced engineer thinks about the Linux permission model in layers:

1. **Who is the user?** Run `id appuser` to see what user ID, primary group, and supplementary groups the user has.
2. **Who owns the files?** Run `ls -la` on the directories and files in question to see ownership and permissions.
3. **Connect the dots** — for `appuser` to write to `/opt/data`, either the directory needs to be owned by `appuser`, or it needs to be group-owned by a group that `appuser` belongs to (with group write permissions), or it needs world-write permissions (bad idea).

The proper solution uses group-based access: make the directory owned by `appgroup`, add `appuser` to `appgroup`, and set group write permissions. This is the standard pattern because it allows multiple users/services to share access.

## Step-by-Step Solution

### Step 1: Check the current state of the user

```bash
id appuser
```

**What this does:** Shows `appuser`'s user ID (uid), primary group ID (gid), and all group memberships. You'll notice that `appgroup` is not listed — the user isn't a member of the group that should grant application access.

### Step 2: Check the current ownership and permissions

```bash
ls -la /opt/data
ls -la /etc/app/config.yml
```

**What this does:** Shows the ownership (user:group) and permission bits for the data directory and config file. You'll see both are owned by `root:root`. The data directory has `755` (owner can write, others can only read), and the config has `600` (only owner can read/write).

### Step 3: Add appuser to appgroup

```bash
usermod -aG appgroup appuser
```

**What this does:** Adds `appuser` to the `appgroup` group. Here's what the flags mean:
- `-a` — **a**ppend to the user's supplementary groups (without this flag, it would *replace* all groups, which could remove the user from other important groups)
- `-G appgroup` — the **G**roup to add the user to

The `-a` flag is critical — without it, `usermod -G appgroup appuser` would remove the user from every other group. This is one of the most dangerous common mistakes in Linux administration.

### Step 4: Change the group ownership of the data directory

```bash
chown :appgroup /opt/data
```

**What this does:** Changes the group owner of `/opt/data` to `appgroup`, without changing the user owner (root). The `:appgroup` syntax means "don't change the user, just change the group." Now that `appuser` is a member of `appgroup`, and the directory is group-owned by `appgroup`, we just need to make sure the group has write permission.

### Step 5: Set group write permission on the data directory

```bash
chmod 775 /opt/data
```

**What this does:** Sets the permissions so that both the owner (root) and the group (`appgroup`) can read, write, and enter the directory. The `775` breaks down as:
- **7** (owner): read + write + execute
- **7** (group): read + write + execute
- **5** (others): read + execute (no write)

The "execute" permission on a directory means the ability to enter it (`cd` into it) and access files inside it.

### Step 6: Make the config file readable by appuser

```bash
chown root:appgroup /etc/app/config.yml
chmod 640 /etc/app/config.yml
```

**What this does:** First, we change the group ownership of the config file to `appgroup` (while keeping root as the owner). Then we set permissions to `640`:
- **6** (owner/root): read + write
- **4** (group/appgroup): read only
- **0** (others): no access

This way, `appuser` (as a member of `appgroup`) can read the config, root can modify it, and nobody else can see it. This is better than `644` (world-readable) because config files often contain sensitive information like database credentials.

### Step 7: Verify all the fixes

```bash
id appuser
ls -la /opt/data
ls -la /etc/app/config.yml
su - appuser -c "touch /opt/data/test && rm /opt/data/test"
su - appuser -c "cat /etc/app/config.yml"
```

**What this does:** Verifies each fix:
1. `id appuser` — confirms `appgroup` is now in the user's groups
2. `ls -la` — confirms correct ownership and permissions
3. `su - appuser -c "touch..."` — switches to `appuser` and tests writing to the data directory
4. `su - appuser -c "cat..."` — switches to `appuser` and tests reading the config file

## Docker Lab vs Real Life

- **Group changes take effect:** In this lab environment, the group change takes effect immediately for `su - appuser`. On a real server, if the user is already logged in (e.g., via SSH), they would need to log out and back in for new group memberships to take effect. You can also use `newgrp appgroup` to activate a group in the current session.
- **Configuration management:** In production, permissions and group memberships would typically be managed by configuration management tools (Ansible, Puppet, Chef) or baked into your deployment scripts, not set manually.
- **ACLs for complex permissions:** When you need more granular control than basic user/group/other permissions, real servers often use POSIX ACLs (`setfacl`/`getfacl`). For example, if you need two different groups with different access levels to the same directory, ACLs are the way to go.
- **Service users:** In production, application users are typically "system" users created with `useradd --system` — they have no home directory, no login shell, and can't be used to log in interactively. This limits the damage if the application is compromised.

## Key Concepts Learned

- **Linux permissions have three levels:** owner, group, and others. Each level can have read (4), write (2), and execute (1) permissions, combined as a single digit.
- **Group-based access is the standard pattern** for shared resources — create a group, add the users who need access, and set the resource's group ownership.
- **`usermod -aG` is the safe way to add a group** — always use the `-a` (append) flag, or you'll accidentally remove the user from all other groups.
- **`chown :groupname` changes only the group** — the colon before the group name means "leave the user owner unchanged."
- **Config files should use `640` not `644`** — there's no reason for everyone on the system to read application configuration files, especially if they contain credentials.

## Common Mistakes

- **Forgetting the `-a` flag with `usermod -G`** — this is a devastating mistake. Without `-a`, the command replaces all group memberships instead of adding to them. The user could lose access to sudo, Docker, and other critical groups.
- **Using `chmod 777`** — this gives everyone full access and is a security anti-pattern. Use the minimum permissions needed: `775` for shared directories, `640` for config files.
- **Changing ownership to appuser instead of using groups** — if you `chown appuser:appuser /opt/data`, it works for one user, but breaks the multi-user model. Groups are designed for shared access.
- **Forgetting that directory "execute" means "enter"** — a directory with permission `774` would let the group read the file list but not actually `cd` into it or access files inside. Directories almost always need the execute bit set for any user/group that needs to work with them.
- **Not testing as the actual user** — using `su - appuser -c "command"` to test is essential. Things might look correct from root's perspective (root can access everything) but fail for the actual application user.

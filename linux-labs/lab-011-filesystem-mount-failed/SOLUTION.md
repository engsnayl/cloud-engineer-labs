# Solution Walkthrough — Filesystem Mount Failed

## The Problem

A data volume that should be mounted at `/data` is not mounted, making it look like all the data has disappeared. The data isn't actually lost — it's sitting inside a filesystem image file at `/opt/fake-volume.img` — but it's not accessible because it's not mounted. Here's what's wrong:

1. **The filesystem image isn't mounted** — the file `/opt/fake-volume.img` is an ext4 filesystem image that contains the database configuration and data files. It needs to be loop-mounted to `/data` so the system can access the files inside it.
2. **`/etc/fstab` has a wrong device path** — the fstab entry says `/dev/sdb1` should be mounted at `/data`, but `/dev/sdb1` doesn't exist. The actual filesystem is a loop image at `/opt/fake-volume.img`. This means `mount -a` (which reads fstab to mount everything) would fail, and the volume wouldn't come back after a reboot.

The `/data` directory exists but is empty — this is because when a mount point exists but nothing is mounted to it, you just see an empty directory. This can be frightening in production because it looks like data loss, but the data is actually safe inside the image file.

## Thought Process

When a mount point is empty and data appears to be missing, an experienced engineer doesn't panic. They think:

1. **Is anything mounted here?** Run `mountpoint /data` or `df /data` to check. If `/data` shows as being on the root filesystem, nothing is separately mounted there.
2. **Where is the actual data?** Look for filesystem images, LVM volumes, or block devices that should be mounted. `file /opt/fake-volume.img` will reveal it's an ext4 filesystem.
3. **What does fstab say?** Check `/etc/fstab` for the expected mount configuration. If the device path is wrong, that explains why it didn't mount.
4. **Mount it manually first, then fix fstab** — always verify the data is intact by mounting manually before editing system configuration files.

## Step-by-Step Solution

### Step 1: Check if /data is currently mounted

```bash
mountpoint /data
```

**What this does:** Tests whether `/data` is a mount point (i.e., has a separate filesystem mounted on it). It will tell you "/data is not a mountpoint," confirming that nothing is mounted there. The directory exists but it's just a regular empty directory on the root filesystem.

### Step 2: Look at the current fstab entry

```bash
grep /data /etc/fstab
```

**What this does:** Shows the fstab entry for `/data`. You'll see it references `/dev/sdb1`, which is a block device that doesn't exist on this system. This is why the mount fails — fstab is looking for a device that isn't there.

### Step 3: Identify the filesystem image

```bash
file /opt/fake-volume.img
```

**What this does:** Examines the file and tells you what type it is. It will report that this is an ext4 filesystem image. This confirms that our data is stored inside this file, and we need to loop-mount it to access the contents.

### Step 4: Mount the filesystem image manually

```bash
mount -o loop /opt/fake-volume.img /data
```

**What this does:** Mounts the filesystem image file to the `/data` directory. The `-o loop` flag tells the `mount` command that the source is a regular file (not a block device) and it should set up a "loop device" — a virtual block device that maps to the file. This is how you mount filesystem images in Linux.

### Step 5: Verify the data is there

```bash
ls -la /data/
cat /data/db-data.conf
```

**What this does:** Lists the contents of `/data` to confirm the files are now accessible. You should see `db-data.conf` and the `pgdata/` directory. Reading the config file confirms the data is intact — nothing was lost, it just wasn't mounted.

### Step 6: Fix the fstab entry

```bash
sed -i 's|/dev/sdb1    /data    ext4    defaults    0    2|/opt/fake-volume.img /data ext4 loop,defaults 0 2|' /etc/fstab
```

**What this does:** Replaces the wrong fstab entry (`/dev/sdb1`) with the correct one that points to the filesystem image file. The key changes are:
- Device: `/dev/sdb1` → `/opt/fake-volume.img` (the actual filesystem image)
- Options: `defaults` → `loop,defaults` (the `loop` option tells mount to use a loop device, which is required for mounting regular files)

The fields in an fstab entry are: `device mountpoint type options dump pass`

### Step 7: Verify fstab is correct

```bash
grep /data /etc/fstab
```

**What this does:** Shows the updated fstab entry so you can visually confirm it's correct. The entry should now reference `/opt/fake-volume.img` with the `loop` option.

### Step 8: Verify the mount is on a separate filesystem

```bash
df /data
```

**What this does:** Shows which filesystem `/data` is on. It should show the loop device (not the root filesystem), confirming that `/data` is properly mounted from the image file as a separate filesystem.

## Docker Lab vs Real Life

- **Loop devices vs block devices:** In this lab we use a filesystem image file with a loop mount. In production, you'd almost always use actual block devices — physical disks (`/dev/sda`), partitions (`/dev/sda1`), LVM logical volumes (`/dev/mapper/vg-data`), or cloud volumes (like AWS EBS at `/dev/xvdf`).
- **UUID vs device names:** In production fstab entries, you should use UUIDs instead of device names. Device names like `/dev/sdb1` can change if you add or remove disks. Use `blkid` to find the UUID, then use `UUID=abc123` in fstab. This is more reliable.
- **Filesystem checks:** The `0 2` at the end of the fstab entry controls dump backups and filesystem check order. On real servers with ext4, setting pass to `2` means `fsck` checks this filesystem on boot (after the root filesystem, which is pass `1`).
- **Mount failures on boot:** On a real server, a bad fstab entry can prevent the system from booting normally. Modern systemd drops to an emergency shell when a mount fails (unless you add `nofail` to the options). Always test fstab changes with `mount -a` before rebooting.
- **Data loss panic:** This scenario — mount point exists but is empty — is a common source of false data-loss alarms in production. Before panicking, always check if the filesystem is actually mounted. The data is usually fine, just not accessible.

## Key Concepts Learned

- **An empty mount point doesn't mean data loss** — if a filesystem isn't mounted, the mount point directory is just empty. The data is still on the block device or image file, waiting to be mounted.
- **`/etc/fstab` controls automatic mounting** — if the entry is wrong, the filesystem won't mount on boot. Always verify fstab entries match reality.
- **`mount -o loop` is how you mount filesystem image files** — a loop device creates a virtual block device that maps to a regular file.
- **`file` command identifies filesystem images** — running `file` on a `.img` file tells you what type of filesystem it contains.
- **`mountpoint` and `df` are your diagnostic tools** — use them to check whether a directory is a separate mount or just a directory on the root filesystem.

## Common Mistakes

- **Panicking and assuming data is lost** — the most important thing is to stay calm. An empty mount point almost always means the filesystem isn't mounted, not that the data was deleted.
- **Editing fstab without testing first** — always mount manually (`mount -o loop ...`) first to verify the data is accessible before making permanent fstab changes. A broken fstab can prevent the system from booting.
- **Forgetting the `loop` option in fstab** — when mounting a filesystem image file (not a block device), you must include `loop` in the options. Without it, `mount -a` won't know to set up a loop device.
- **Not verifying with `mount -a`** — after editing fstab, run `mount -a` to test that all entries can be mounted. This catches errors before the next reboot.
- **Using device names instead of UUIDs in fstab** — device names like `/dev/sdb1` can change if hardware is added or removed. In production, always use `UUID=` for reliable mounting.

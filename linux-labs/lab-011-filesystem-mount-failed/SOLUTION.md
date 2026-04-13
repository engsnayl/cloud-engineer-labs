# Lab 011 — Filesystem Mount Failed: Solution Walkthrough

---

## TLDR — What's Going On Here (Plain English)

You've been handed a ticket that says data is missing from `/data`. When you look, the directory is there but completely empty. **The data isn't gone — it just isn't connected.**

Think of it like a USB drive that hasn't been plugged in yet. The port (the `/data` folder) exists, but nothing is plugged into it. The data is sitting safely inside a file called `/opt/fake-volume.img` — a self-contained filesystem packed into a single file. The operating system just doesn't know to look there yet.

There are two things wrong:

1. **Nothing is mounted to `/data`** — the filesystem image file exists, but it hasn't been attached to the `/data` directory.
2. **`/etc/fstab` points to the wrong device** — the config file that controls what gets mounted on boot says `/dev/sdb1`, which doesn't exist on this system. So even after a reboot, this would never mount automatically.

**What you'll do:** Confirm nothing is mounted → find the image file → mount it manually → verify the data is there → fix fstab so it survives a reboot.

---

## Background Theory

Before diving into the steps, here's the foundational knowledge this lab sits on top of.

### What is a Data Volume?

A data volume is a dedicated, **separate** place to store data — independent from the main system disk where the OS lives.

Your root filesystem (`/`) is where Linux itself lives — commands, config files, logs. If you stored your database files there too, everything is tangled together on one disk. That's a problem in production because:

- If the OS disk fills up, the database crashes
- If you rebuild the server, you risk wiping the data
- You can't easily move the database to a bigger disk
- Multiple servers can't share the same disk

So instead, you mount a **separate** filesystem at a path like `/data` and tell the database "store everything here." The database doesn't know or care that it's a separate volume — it just sees `/data` as a folder. But underneath, it's completely independent storage that can be managed, resized, snapshotted, or moved on its own.

**The database doesn't back up *to* the volume — it lives *on* it.** Backups are a separate concern (snapshots, `pg_dump`, S3 exports, etc.).

In real life a data volume would typically be:
- An extra physical disk attached to the server (`/dev/sdb`, `/dev/sdb1`)
- An AWS EBS volume attached to an EC2 instance
- An LVM logical volume carved out of a storage pool (`/dev/mapper/vg-data`)

In this lab, it's a filesystem image file loop-mounted — a lab shortcut that behaves identically from the OS's perspective.

---

### What is a Mount Point?

A **mount point** is just a directory that acts as the entry point to a separate filesystem.

When you mount a filesystem to `/data`, you're telling Linux: *"make the contents of this device/file appear at this directory."* The directory itself doesn't hold the files — it's the door. The files live on the device. When nothing is mounted, the door is just an empty room.

This is why an empty `/data` is not automatically data loss. It might just mean the door is there but nothing is connected behind it.

**The USB drive analogy:** Your laptop has a USB port. The port exists whether or not a drive is plugged in. When you plug in a drive, it appears at a path like `/media/usb`. When you unplug it, that path is empty again — but the files are still on the drive. A mount point works exactly the same way.

---

### What is `/etc/fstab`?

`/etc/fstab` (filesystem table) is a configuration file that tells Linux what to mount automatically on boot, where to mount it, and with what options.

Each line in fstab is one mount entry. The fields are:

| Field | Example | Meaning |
|-------|---------|---------|
| Device | `/dev/sdb1` | What to mount — a block device, image file, UUID, or network path |
| Mount point | `/data` | Where to mount it in the filesystem tree |
| Filesystem type | `ext4` | What kind of filesystem it is |
| Options | `defaults` | Mount options (read/write, loop device, etc.) |
| Dump | `0` | Whether the `dump` backup utility should back this up (rarely used now) |
| Pass | `2` | Order for `fsck` filesystem checks on boot. `0` = skip, `1` = root first, `2` = after root |

If an fstab entry is wrong — wrong device path, wrong options, typo — the mount will fail silently on boot and the mount point will be empty. On modern systemd systems, a critically wrong fstab entry can drop you into an emergency shell and prevent the server from booting fully.

**Always test fstab changes with `mount -a` before rebooting.**

> **Production note — use UUIDs, not device names:** Device names like `/dev/sdb1` are not stable. If you add or remove a disk, the names can change. In production fstab entries you should always use `UUID=abc123...` instead. Run `blkid` to find a device's UUID.

---

### What is a Loop Device?

A **loop device** is a virtual block device that maps to a regular file instead of a physical disk.

When you run `mount -o loop file.img /data`, Linux creates a loop device (like `/dev/loop0`) that acts as a virtual disk — but instead of reading from physical hardware, it reads from the `.img` file. From the mount system's perspective, it looks and behaves exactly like a real disk.

This is why `mount` needs the `loop` option when mounting a file — without it, mount tries to treat the file as a real block device and fails. The `loop` option tells it: *"set up a virtual block device for this file first, then mount that."*

You'll also need `loop` in the fstab options if you want this to mount automatically on boot.

---

### What is `/dev/` and Device Naming?

`/dev/` is a special directory in Linux that contains **device files** — files that represent hardware attached to the system.

Common naming conventions:

| Name | What it represents |
|------|--------------------|
| `/dev/sda` | First SATA/SCSI disk |
| `/dev/sdb` | Second SATA/SCSI disk |
| `/dev/sda1` | First partition on the first disk |
| `/dev/sdb1` | First partition on the second disk |
| `/dev/loop0` | First loop device (virtual, file-backed) |
| `/dev/xvdf` | EBS volume attached to an AWS EC2 instance |
| `/dev/mapper/vg-data` | LVM logical volume |

Device names are **not guaranteed to be stable.** If you add or remove hardware, `/dev/sdb` might become `/dev/sdc`. This is why production fstab entries use UUIDs — a UUID is tied to the filesystem itself, not the device name.

---

### What is ext4?

`ext4` is a **filesystem type** — the format used to organise files and directories on a storage device.

Just like a USB drive needs to be formatted as FAT32 or exFAT before you can use it, a disk or image file needs to be formatted with a filesystem before it can store files. `ext4` (fourth extended filesystem) is the most common filesystem type on Linux. It's fast, reliable, and supports large files and volumes.

Other common Linux filesystem types:

| Type | Where you'll see it |
|------|---------------------|
| `ext4` | Standard Linux — most common |
| `xfs` | RHEL/CentOS, AWS Amazon Linux |
| `btrfs` | Modern systems, supports snapshots natively |
| `tmpfs` | Lives entirely in RAM — not persistent |
| `nfs` | Network filesystem — files live on another server |

---

### What is `lost+found`?

Every ext4 filesystem has a `lost+found` directory at its root. It's created automatically when the filesystem is formatted.

It's used by `fsck` (filesystem check) — the tool that checks and repairs filesystems on boot. If `fsck` finds orphaned files during a repair (files that exist on disk but aren't linked to any directory), it puts them in `lost+found` with a numeric name so you can recover them manually.

Seeing `lost+found` in `/data/` after mounting is completely normal — it just confirms you're looking at a genuine ext4 filesystem. It is not an error.

---

### The Most Important Production Instinct From This Lab

**An empty mount point is not data loss.**

If `/data` is empty, the first question is always: *is anything mounted here?* Check with `mountpoint /data` or `df /data`. If the answer is no — nothing is mounted — the data is almost certainly safe on a device or image file that just isn't connected yet.

Before raising a P1 incident or telling anyone data is lost, spend 30 seconds confirming the filesystem is actually mounted. This is one of the most common false alarms in production Linux environments.

---

## Your Starting Point — Reading the Ticket

You've received a ticket:

> "The `/data` volume appears to be empty. The database can't find its configuration files. Possible data loss."

You don't know what's wrong yet. Here's how to work through this in real time.

---

## Step-by-Step Investigative Learning Pathway

### Step 1 — Confirm the symptom: is anything actually mounted here?

Your first instinct should be: *is this actually data loss, or is the filesystem just not mounted?* These are completely different problems with completely different solutions.

```bash
mountpoint /data
```

| Part | What it does |
|------|-------------|
| `mountpoint` | Tests whether a path is a mount point — whether a separate filesystem is attached there |
| `/data` | The directory you're checking |

**Expected output:** `/data is not a mountpoint`

Nothing is mounted at `/data`. The directory exists but it's just an empty folder on the root filesystem. **This is almost certainly not data loss.**

---

### Step 2 — What does the system think should be mounted here?

Check `/etc/fstab` — the file that controls what gets mounted on boot.

```bash
grep /data /etc/fstab
```

| Part | What it does |
|------|-------------|
| `grep` | Searches text for a pattern |
| `/data` | The pattern you're searching for |
| `/etc/fstab` | The filesystem table — lists what should be mounted where and with what options |

**Expected output:**
```
/dev/sdb1    /data    ext4    defaults    0    2
```

The fstab says `/dev/sdb1` should be mounted at `/data`. But does that device actually exist?

---

### Step 3 — Does that device actually exist?

```bash
ls /dev/sdb1
```

| Part | What it does |
|------|-------------|
| `ls` | Lists files. If the device exists in `/dev/`, it'll appear. If not, you get an error. |
| `/dev/sdb1` | The block device path referenced in fstab |

**Expected output:** `ls: cannot access '/dev/sdb1': No such file or directory`

The device doesn't exist. That's why nothing mounted — the system looked for `/dev/sdb1` on boot, couldn't find it, and gave up. **This is your bug confirmed.** Now the question is: where is the actual data?

---

### Step 3b — Where does the application expect its data to be?

The fstab points to a device that doesn't exist. Before hunting blindly around the filesystem, ask a more useful question first: *where does the application itself think its data should be?*

In real life you'd check the application config — a Postgres config file, a `.env`, a docker-compose, a runbook. Something will tell you what path the application is expecting. Check the app environment file:

```bash
cat /etc/app.env
```

**Expected output:**
```
PGDATA=/data/pgdata
```

This tells you the database expects its data at `/data/pgdata`. You now know with certainty that `/data` should be a mounted volume containing a `pgdata/` directory — and it isn't. That confirms your fault. The ticket makes complete sense now.

> **In real life, always check application config before hunting the filesystem.** Your first moves would be: check the app's config files, check environment variables, check docker-compose or Terraform, check the runbook. Someone documented where the data lives — find that first.

---

### Step 3c — Now find the actual data source

You know `/data` should be mounted and isn't. The fstab device doesn't exist. So the volume must be somewhere else on this system — you need to find it.

Since fstab had a wrong device path rather than a missing entry entirely, the volume was likely always file-based. Search for filesystem image files:

```bash
find / -name "*.img" 2>/dev/null
```

| Part | What it does |
|------|-------------|
| `find /` | Search from the root of the filesystem downwards |
| `-name "*.img"` | Look for files with a `.img` extension |
| `2>/dev/null` | Suppress permission errors so they don't clutter your output |

**Expected output:** `/opt/fake-volume.img`

> **Why `find` here and not `lsblk`?** Because the data source in this lab is a regular file, not a block device. `lsblk` only shows block devices — it won't surface a `.img` file sitting in `/opt`. In production you'd reach for `lsblk` or `blkid` first because the data would be on a real disk. Here, `find` is the right tool precisely because the volume is file-based. This is a lab construct — in production, file-based volumes like this are rare.

---

### Step 4 — Identify what the file actually is

Before mounting anything, confirm the file is a real filesystem image.

```bash
file /opt/fake-volume.img
```

| Part | What it does |
|------|-------------|
| `file` | Inspects a file and identifies its type based on internal contents — not just the filename |
| `/opt/fake-volume.img` | The image file you found |

**Expected output:**
```
/opt/fake-volume.img: Linux rev 1.0 ext4 filesystem data ...
```

Confirmed — this is an ext4 filesystem packed into a file. Your data is inside it.

---

### Step 5 — Mount the image manually and verify the data

Always verify the data is intact by mounting manually before touching any config files.

```bash
mount -o loop /opt/fake-volume.img /data
```

| Part | What it does |
|------|-------------|
| `mount` | Attaches a filesystem to a directory |
| `-o loop` | Passes the `loop` option — tells mount the source is a regular file, not a block device. Sets up a virtual block device (loop device) that maps to the file |
| `/opt/fake-volume.img` | The filesystem image to mount |
| `/data` | The mount point |

Now verify:

```bash
ls -la /data/
ls -la /data/pgdata/
```

| Part | What it does |
|------|-------------|
| `ls -la /data/` | Confirms the volume isn't empty and the expected top-level structure is there |
| `ls -la /data/pgdata/` | Confirms the database data directory exists and has content |

**What you expect to see:** `pgdata/` is present inside `/data/`, and it contains files. You'll also see `lost+found` — this is completely normal on every ext4 filesystem. It's created automatically when the filesystem is formatted and is used by `fsck` to store orphaned files during a repair. Not a problem.

You don't need to read specific files — you just need to confirm the volume isn't empty and the structure the database expects (`/data/pgdata`) is there. That's enough to confirm the data is intact.

**The data was never gone. Confirmed.**

---

### Step 6 — Fix fstab so this survives a reboot

The mount you just did is temporary — it won't survive a reboot. Open fstab directly and fix the entry:

```bash
vi /etc/fstab
```

Find the line:
```
/dev/sdb1    /data    ext4    defaults    0    2
```

Change it to:
```
/opt/fake-volume.img    /data    ext4    loop,defaults    0    2
```

Save and quit: `Esc` → `:wq`

**The two changes you're making:**
- Device: `/dev/sdb1` → `/opt/fake-volume.img`
- Options: `defaults` → `loop,defaults` (the `loop` option is required for file-based mounts — without it, `mount -a` won't know to set up a loop device)

> **Why `vi` and not a one-liner `sed` command?** Opening the file directly means you can see the whole picture, make a precise edit, and catch anything else that looks wrong. A `sed` one-liner is fragile (spacing must match exactly), hard to remember, and easy to get wrong. `sed` earns its place when you're scripting the same change across many servers — for a manual one-off fix, just open the file.

---

### Step 7 — Verify the fstab change

```bash
grep /data /etc/fstab
```

Confirm the entry now shows `/opt/fake-volume.img` with `loop` in the options.

---

### Step 8 — Confirm it's mounted as a separate filesystem

```bash
df /data
```

| Part | What it does |
|------|-------------|
| `df` | Disk free — shows filesystem usage and which filesystem a path belongs to |
| `/data` | The path you're checking |

**Expected output:** `/data` should show a loop device (like `/dev/loop0`) as its filesystem — not the root filesystem. Confirms it's a properly mounted separate volume.

---

### Step 9 — Test fstab before relying on a reboot

```bash
umount /data
mount -a
mountpoint /data
```

| Part | What it does |
|------|-------------|
| `umount /data` | Unmounts `/data` so you can test `mount -a` brings it back |
| `mount -a` | Mounts everything in fstab that isn't already mounted — exactly what happens on boot |
| `mountpoint /data` | Confirms `/data` is a mount point again |

**Expected output:** `mount -a` runs silently with no errors. `mountpoint /data` returns `/data is a mountpoint`. Fix confirmed — the server can reboot and `/data` will mount automatically.

---

## Lab Context vs Real Life

| This Lab | Real Production |
|----------|----------------|
| Filesystem stored as a `.img` file, loop-mounted | Real block devices: `/dev/sda1`, LVM volumes, AWS EBS |
| Device path wrong in fstab | Device renamed after hardware change, UUID changed after disk replacement |
| `loop` option needed in fstab | Not needed for real block devices — `defaults` is sufficient |
| Loop device visible in `df` | Real block device or LVM path shown instead |
| Found image file with `find` | In production: check deployment docs, `blkid`, `lsblk`, team runbooks |

---

## Key Concepts Summary

- **Data volume** — dedicated separate storage for application data, independent from the OS disk
- **Mount point** — a directory that acts as the entry point to a separate filesystem. Empty when nothing is mounted — not data loss
- **`/etc/fstab`** — the filesystem table. Controls what mounts automatically on boot. Wrong entry = failed mount
- **Loop device** — a virtual block device that maps to a regular file. Required for mounting `.img` files
- **`/dev/` naming** — device names like `/dev/sdb1` are not stable. Use UUIDs in production fstab entries
- **ext4** — the most common Linux filesystem type. Every ext4 volume has a `lost+found` directory — this is normal
- **Empty mount point ≠ data loss** — always check `mountpoint` and `df` before assuming data is gone

---

## Common Mistakes

- **Panicking and assuming data loss** — stay calm. Check whether the filesystem is mounted before escalating
- **Editing fstab without testing the manual mount first** — confirm the data is accessible before making permanent changes
- **Forgetting `loop` in fstab options** — required for file-based mounts. Without it, `mount -a` fails on reboot
- **Not running `mount -a` after editing fstab** — always test before the next reboot
- **Using device names instead of UUIDs in production** — device names can change. Use `UUID=` for stable fstab entries

---

## Cleanup / Reset

To reset this lab so you can run through it again from Step 1:

```bash
# Unmount /data
umount /data

# Restore the broken fstab entry
vi /etc/fstab
# Change back to: /dev/sdb1    /data    ext4    defaults    0    2

# Confirm /data is empty again
ls /data
mountpoint /data
```

You should see `/data` is empty and `mountpoint` reports it is not a mount point — back to the broken starting state.

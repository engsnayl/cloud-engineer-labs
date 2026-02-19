# Hints — Lab 011: Filesystem Mount Failed

## Hint 1 — The data isn't lost
Run `file /opt/fake-volume.img` — you'll see it's an ext4 filesystem image. The data is inside this file, it just needs to be mounted to /data.

## Hint 2 — Mount it manually first
`mount -o loop /opt/fake-volume.img /data` will mount the volume. Check that your data appears in /data.

## Hint 3 — Fix fstab for persistence
The fstab entry points to /dev/sdb1 which doesn't exist. Replace it with the loop mount: `/opt/fake-volume.img /data ext4 loop,defaults 0 2`

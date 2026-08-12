# Installing the base OS

The shortest path from a blank disk to a bootable system. One command per
step, no options, no detours. Depth lives in the
[Gentoo Handbook](https://wiki.gentoo.org/wiki/Handbook:AMD64) and the
[Arch Installation guide](https://wiki.archlinux.org/title/Installation_guide);
this page is deliberately dumb.

When the OS boots, continue with [bootstrap-gentoo.md](bootstrap-gentoo.md)
or [bootstrap-arch.md](bootstrap-arch.md).

## Gentoo

Boot any live ISO with network (the official minimal ISO works, so does
an Arch ISO). Then, as root:

1. Find your disk: `lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID`.
   **Warning — do not paste device names from docs.** NVMe enumeration
   swaps between boots and between machines: on neverland, what these
   steps once called `/dev/nvme0n1p1`/`p3` is today the live ESP and
   Windows C:. Identify the target by size/label/UUID first; below,
   `<disk>` is the blank target and `<p1>..<p3>` its new partitions.
2. Partition: `cfdisk /dev/<disk>` — GPT; make three partitions:
   1G type "EFI System", the rest for root, optionally a data partition.
3. Make filesystems (triple-check each name against `lsblk` — mkfs on a
   wrong letter is unrecoverable):
   `mkfs.vfat -F32 /dev/<p1> && mkfs.xfs /dev/<p2>` (data partition if
   any: `mkfs.xfs /dev/<p3>`)
4. Mount root: `mkdir -p /mnt/gentoo && mount /dev/<p2> /mnt/gentoo`
5. Download the latest **amd64 openrc** stage3 from
   <https://www.gentoo.org/downloads/> into `/mnt/gentoo`.
6. Unpack it: `cd /mnt/gentoo && tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner`
7. Mount the ESP: `mkdir -p boot/efi && mount /dev/<p1> boot/efi`
8. Chroot with this repo's helper: `sh ch_gentoo.sh /mnt/gentoo`
   (get it with `git clone https://github.com/0n3W4y7ick3t/deployLinux`,
   it is in `targets/gentoo/`).
9. Inside the chroot: `emerge-webrsync && emerge --sync -q`
10. Pick the profile: `eselect profile list` then
    `eselect profile set default/linux/amd64/23.0` (plain openrc one).
11. Read the news: `eselect news read`. Some items need action.
12. Timezone — set the symlink, `emerge --config` skips an existing one:
    `ln -sf ../usr/share/zoneinfo/Asia/Tokyo /etc/localtime && echo Asia/Tokyo > /etc/timezone`
13. Locales: put `en_US.UTF-8 UTF-8`, `zh_CN.UTF-8 UTF-8` and
    `ja_JP.UTF-8 UTF-8` in `/etc/locale.gen`, then
    `locale-gen && eselect locale set en_US.utf8`
14. Write `/etc/fstab` using UUIDs from `blkid`
    (see `targets/gentoo/profiles/desktop/fstab.example`).
15. Passwords and your user — do this now, not after reboot, or you get
    a machine you cannot log into:
    `passwd`, then
    `useradd -m -G wheel,video,audio,usb,portage,input,render -s /bin/bash <name>`
    and `passwd <name>`. Switch the shell to zsh once bootstrap has
    installed it.
16. Bootloader: copy `common/refind/` from this repo onto the ESP and add
    a boot entry, or `emerge refind && refind-install`. Include the
    driver from `drivers_x64/` matching `/boot`'s filesystem.
17. `exit`, `reboot`, log in.

The kernel is not built here — `bootstrap-gentoo.md` does it from the
machine profile, because the config is profile-specific.

Done. Continue with [bootstrap-gentoo.md](bootstrap-gentoo.md).

## Arch

1. Boot the official Arch ISO.
2. Run `archinstall`.
3. The answers that matter: profile **Minimal** (no desktop — our
   bootstrap installs it), filesystem ext4, bootloader systemd-boot or
   rEFInd, network **NetworkManager**, create your user.
4. Reboot.

Prefer doing it by hand? Follow the
[Installation guide](https://wiki.archlinux.org/title/Installation_guide)
up to the first boot, nothing more is needed.

Done. Continue with [bootstrap-arch.md](bootstrap-arch.md).

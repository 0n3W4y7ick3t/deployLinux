# Maintaining a Gentoo machine

Day-2 operations for **neverland**, the Gentoo desktop. Install and first
bootstrap live in [install-os.md](install-os.md) and
[bootstrap-gentoo.md](bootstrap-gentoo.md); this page is for a machine that
already works. The X13 runs Arch and has its own, much shorter section at
the end — most of what follows (portage, kernel builds, rEFInd) simply does
not apply there.

Read [../CLAUDE.md](../CLAUDE.md) first if you are unsure why anything is
set up the way it is — particularly the no-initramfs consequences.

## Routine update

```sh
sudo emerge --sync                  # or emerge-webrsync
sudo eselect news read              # do not skip, some items need action
sudo emerge -uDN --keep-going @world
sudo emerge @preserved-rebuild
sudo emerge --depclean -p           # review before running without -p
```

`--keep-going` matters on a fleet this size: one broken leaf package
should not stop the other 900.

Then, when a package refuses to resolve, **fix it in this repo, not in
`/etc/portage`**. Add the flag to `targets/gentoo/portage/package.use/deps`
with a comment naming the consumer, then:

```sh
cd ~/akira/deployLinux && git pull
sudo GENTOO_PROFILE=desktop sh targets/gentoo/scripts/10-portage.sh
```

`10-portage.sh` skips the tree sync if it ran in the last day
(`SYNC=1` forces it).

## Kernel upgrade

The whole procedure is one script. It regenerates the config from
`config-fragment` rather than carrying `.config` forward, so the diff
stays reviewable and symbols renamed upstream do not silently persist.

```sh
sudo emerge -u sys-kernel/gentoo-sources
sudo ~/akira/deployLinux/targets/gentoo/profiles/desktop/kernel/build.sh
```

It selects the newest source tree, merges the fragment, **asserts** the
symbols that must be builtin, builds, installs, and — through
`/etc/kernel/postinst.d/90-nvidia-modules` — rebuilds `nvidia.ko` against
the new kernel. Nothing else to remember.

Then, if the kernel version changed, point rEFInd at it:

```sh
ls /boot/vmlinuz-*                  # confirm the new one is there
```

rEFInd auto-detects kernels in `/boot` and reads its options from
`/boot/refind_linux.conf`, so a version bump needs no bootloader edit.

**The previous kernel stays** as `/boot/vmlinuz-*.old` and rEFInd offers
it. Do not delete it until the new one has booted cleanly.

If `build.sh` dies on an assertion, that is the point: a required symbol
stopped applying. Read [../CLAUDE.md](../CLAUDE.md) on `select`-only
symbols before "fixing" it by deleting the assert.

### Rebuilding just the nvidia module

After a kernel change the hook does it automatically. To force it:

```sh
sudo emerge @module-rebuild
```

Verify: `modinfo -F version /lib/modules/$(uname -r)/video/nvidia.ko`

### Driver upgrades

`x11-drivers/nvidia-drivers` upgrades like any package. `kernel-open` is
mandatory on Blackwell — never turn it off. After the upgrade, reboot or:

```sh
sudo rmmod nvidia_drm nvidia_modeset nvidia_uvm nvidia && sudo modprobe nvidia_drm
```

(Only works with no GPU clients running; a reboot is usually easier.)

## Cleanup and retention

Two caches, opposite ends of the build:

| cache | what it holds | who uses it | lifetime |
| :--- | :--- | :--- | :--- |
| `/var/cache/distfiles` | upstream source tarballs (build **input**) | this machine, when recompiling | 1 month |
| `/var/cache/binpkgs` | compiled `.gpkg.tar` (build **output**) | this machine, to undo a bad build | keep |
| `/var/tmp/portage` | build directories | nobody, transient | per-merge, and a 24G tmpfs |

`FEATURES="buildpkg"` is kept purely as an undo button — after a bad
update, `emerge --usepkgonly <atom>` reinstalls the previous build
without recompiling. Prune when it gets large:

```sh
sudo eclean-dist --deep --time-limit=1m   # sources older than a month
sudo eclean-pkg --deep                    # binpkgs with no installed match
sudo emerge --depclean                    # orphans (review -p first)
sudo rm -rf /var/tmp/portage/*            # stale build dirs after a failure
```

Old kernels: remove `/boot/vmlinuz-<old>`, its `System.map`/`config`, and
`/lib/modules/<old>` — but only once the current one is proven, and keep
at least one fallback.

## Recovery

### The machine does not boot

Pick the entry rEFInd offers for the **previous** kernel (`.old`) first.
If that works, the new kernel is the problem — rebuild it and check the
assertions in `build.sh`.

If nothing boots, use a live USB. Mount by **label/UUID only** — the
NVMe device names swap between boots on this board, and an earlier
version of this very recipe pointed at what is today the NTFS DATA disk:

```sh
mount LABEL=gentoo /mnt/gentoo
mount UUID=6641-7CF6 /mnt/gentoo/boot/efi        # the shared ESP
sh /mnt/gentoo/home/leon/akira/deployLinux/targets/gentoo/ch_gentoo.sh /mnt/gentoo
source /etc/profile
```

Then re-run whatever failed. All scripts are idempotent.

### Windows will not boot: UNMOUNTABLE_BOOT_VOLUME (0xED)

Seen 2026-08: `ntfs.sys` refuses to mount C: at boot, from both rEFInd's
Windows entry and Windows Boot Manager directly. Root cause was
Linux-side: rw mounts with the in-kernel `ntfs3` driver (plus one hard
reset) left C:'s `$LogFile` journal blanked. Windows' own event log
showed a clean final shutdown — the volume was healthy until we touched
it. Playbook, from a live USB:

```sh
DEV=$(readlink -f /dev/disk/by-uuid/C3589E50BA73E9FD)   # C:, never trust nvmeXnY
sudo ntfsfix -n "$DEV"                 # dry-run diagnosis: boot sector, MFT mirror
sudo ntfsresize --info --no-action "$DEV"   # full consistency check, read-only
sudo ntfscat "$DEV" '$LogFile' | head -c 4096 | xxd | head -3   # all ff = blanked journal
# safety net before any repair (metadata-only undo image, read-only on source):
sudo ntfsclone --metadata --save-image -o /mnt/gentoo/root/lose-meta.img "$DEV"
```

The actual repair is Windows-side — Linux cannot write a Windows-native
journal: boot WinPE (`WePE64.iso` in the Ventoy menu, or the PE partition
via the firmware boot menu) and run `chkdsk C: /f`, then reboot. In the
repaired Windows: `fsutil dirty query C:` and `powercfg /h off`.
Prevention is already deployed: C: has no rw path from Gentoo (fstab ro +
`ntfs-3g` only), and `ntfs3` is banned in `/etc/modprobe.d/ntfs3.conf`
and gone from the kernel. Related: the ESP is no longer auto-fsck'd at
boot (passno 0) — run `sudo fsck.vfat -n /dev/disk/by-uuid/6641-7CF6`
by hand occasionally.

### Symptom table

| symptom | cause to check first |
| :--- | :--- |
| kernel panic, "unable to mount root" | cmdline uses `root=UUID=` — must be `PARTUUID` with no initramfs |
| no `/dev`, init fails | `CONFIG_DEVTMPFS_MOUNT` unset |
| kernel missing from the rEFInd menu | `EFI/refind/drivers/xfs_x64.efi` gone, or the kernel is not in `/boot` |
| `/boot/bzImage` instead of `vmlinuz-<ver>` | `sys-kernel/installkernel` was depcleaned |
| nvidia-drivers: "built kernel sources are required" | kernel not built yet — run `build.sh` before merging it |
| nvidia-drivers: `DRM_TTM_HELPER` not set | `DRM_QXL=m` fell out of the config |
| no network after boot | `dhcpcd` not in the default runlevel; `r8169` is a module, check `lsmod` |
| no session / logind errors | `elogind` not in the **boot** runlevel |
| microcode loaded late | `CONFIG_EXTRA_FIRMWARE` did not take — check the path exists under `/lib/firmware` |
| Japanese renders as boxes | `media-fonts/noto-cjk` missing |
| IME popup misplaced in GTK4/Qt6 | something is exporting `GTK_IM_MODULE`/`QT_IM_MODULE` — it must not be set on Wayland |
| Hyprland aborts at start, "no gpus" in `~/.cache/hyprland/session.log` | `AQ_DRM_DEVICES` contains a by-path name — it is a colon-separated list and by-path names contain colons. The pin belongs in rice's `shell/profile` (resolved at login), never in a hyprland config |
| Hyprland picks the wrong GPU | the profile export failed soft (check `echo $AQ_DRM_DEVICES`) — see rice CLAUDE.md |
| Windows BSODs 0xED after a Gentoo session | see "Windows will not boot" above; something rw-mounted C: |
| x13: boots an old kernel after `pacman -Syu` | `/boot/efi` was not mounted when `mkinitcpio -P` ran, so the UKI went to the root fs |
| x13: no wifi after a reboot | `iwd.service` disabled while NM is configured with `wifi.backend=iwd` |
| x13: wifi associates at boot but never gets a DHCP lease, only after a Windows session | Windows was *restarted* into Linux. A warm reboot leaves the WCN6855 / AP state from Windows behind; iwd associates fine, NM's DHCP gets nothing for 45 s and gives up. `nmcli connection up '<ssid>'` a few minutes later works, and a clean Linux→Linux reboot or a Windows **shut down** → power on never shows it (verified 2026-08-19). Rule: shut Windows down, don't restart it, when switching to Linux. Fast Startup is not the cause (`hiberfil.sys` absent), and neither is NM/iwd config |

## The X13 (Arch)

Nothing above applies except the NTFS rules and the general "fix it in the
repo" reflex. Day-2 there is:

```sh
sudo pacman -Syu                    # read the news at archlinux.org first
yay -Sua                            # AUR, as your user
cd ~/akira/deployLinux && git pull && sudo ./targets/arch/bootstrap.sh
```

Re-running `bootstrap.sh` is the way to restore any system file it owns; it
is idempotent and installs nothing that is already current.

**Kernel upgrades are pacman's job**, but two things must hold or the box
boots a stale kernel with fresh modules:

- `/boot/efi` mounted (from `/etc/fstab`) when `mkinitcpio -P` runs, so the
  UKI actually lands on the ESP. Check the timestamp under
  `/boot/efi/EFI/Linux/` after an upgrade.
- systemd-boot itself updated by `systemd-boot-update.service`
  (`bootctl status` shows a version mismatch when it is not).

Recovery is an Arch ISO on a USB stick, `mount UUID=… /mnt`,
`arch-chroot /mnt`. There is no `.old` kernel unless `fallback_uki` is
enabled in `/etc/mkinitcpio.d/linux.preset` or `linux-lts` is installed —
consider one of the two before an adventurous upgrade.

The X13's Windows volume is mounted **rw** by deliberate exception (see
CLAUDE.md). If Windows ever fails to boot after a Linux session, the 0xED
playbook above is the same, with the X13's own UUID.

## Services

OpenRC, managed by `40-services.sh`. Current expected set:

```
boot:     elogind
default:  dbus dhcpcd bluetooth docker keyd zram-init cronie libvirtd
```

```sh
rc-update show                      # what is enabled
rc-service <name> status|start|restart
```

`40-services.sh` also owns `/etc/sysctl.d/90-bbr.conf` (BBR + fq),
`/etc/local.d/epp.start` (EPP pinned to performance on desktops),
`/etc/cron.weekly/fstrim`, `/etc/keyd/default.conf` and
`/etc/conf.d/zram-init`. Re-running it restores any of them.

## What not to do

- Do not hand-edit `/etc/portage` — it is regenerated from this repo.
- Do not add `sys-kernel/gentoo-kernel` without also enabling dracut.
- Do not `emerge --depclean` `sys-kernel/installkernel`.
- Do not enable `GTK_IM_MODULE`/`QT_IM_MODULE` on Wayland.
- Do not touch the kali partition (label `kali`).
- Do not write to neverland's Windows C: (label `Lose`) from Linux — it is
  mounted `ro` for a reason (0xED, 2026-08) — and never use
  `mount -t ntfs3` anywhere (banned in modprobe.d on both machines; DATA is
  rw via ntfs-3g only). The X13 is the one documented exception, and only
  while its `powercfg /h off` holds.
- Do not trust `/dev/nvmeXnY` names in any command — they swap between
  boots. `blkid` first, or use `LABEL=`/`UUID=`.

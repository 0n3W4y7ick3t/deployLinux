# Maintaining a Gentoo machine

Day-2 operations for the fleet. Install and first bootstrap live in
[install-os.md](install-os.md) and [bootstrap-gentoo.md](bootstrap-gentoo.md);
this page is for a machine that already works.

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
cd /deploy/deployLinux && git pull
sudo GENTOO_PROFILE=pc sh targets/gentoo/scripts/10-portage.sh
```

`10-portage.sh` skips the tree sync if it ran in the last day
(`SYNC=1` forces it).

## Kernel upgrade

The whole procedure is one script. It regenerates the config from
`config-fragment` rather than carrying `.config` forward, so the diff
stays reviewable and symbols renamed upstream do not silently persist.

```sh
sudo emerge -u sys-kernel/gentoo-sources
sudo /deploy/deployLinux/targets/gentoo/profiles/pc/kernel/build.sh
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

If nothing boots, use a live USB:

```sh
mount /dev/nvme1n1p4 /mnt/gentoo                 # xfs root, label "gentoo"
mount /dev/nvme1n1p1 /mnt/gentoo/boot/efi        # ESP
sh /mnt/gentoo/deploy/deployLinux/targets/gentoo/ch_gentoo.sh /mnt/gentoo
source /etc/profile
```

Then re-run whatever failed. All scripts are idempotent.

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
| Hyprland picks the wrong GPU | only if a second DRM card exists; set `AQ_DRM_DEVICES` |

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
- Do not touch `/dev/nvme1n1p5` (kali) or the Windows NTFS volumes.

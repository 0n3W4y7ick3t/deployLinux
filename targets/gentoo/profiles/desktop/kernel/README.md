# pc kernel

Hardware targeted: AMD Ryzen 7 9800X3D (Zen5), NVIDIA RTX 5080, ASUS TUF
B850-PLUS WIFI (RTL8125 2.5GbE, Realtek 8922AE wifi/BT), NVMe, xfs root,
EFI boot via rEFInd.

## Policy

**Custom kernel, no initramfs.** `config-fragment` builds the root
filesystem and its disk into the image, so rEFInd loads one file and the
kernel mounts root directly.

A dist-kernel is *not* an option here without also enabling dracut:
`sys-kernel/gentoo-kernel` ships ext4/xfs as modules and cannot mount
root on its own. That combination — dist-kernel plus
`installkernel[-dracut]` — is what this repo shipped before the first
real install, and it does not boot.

Two consequences worth remembering:

- `sys-kernel/installkernel` must stay in the world file. It is not
  pulled in implicitly, and without it `make install` writes an
  unversioned bzImage and skips `/etc/kernel/postinst.d`.
- The cmdline uses `root=PARTUUID=`, never `root=UUID=`. Resolving a
  filesystem UUID needs userspace, i.e. an initramfs.

## Build and upgrade

Same command both times:

```
sudo ./build.sh          # or --jobs N
```

It runs `make defconfig`, merges `config-fragment`, `make olddefconfig`,
asserts the symbols that must be builtin, builds, and installs.

Regenerating from `defconfig` + fragment beats copying `.config` into
the new source tree. The fragment is the reviewable unit, symbols
renamed or split upstream do not silently persist, and nothing depends
on the old tree still being on disk. `CONFIG_IKCONFIG_PROC=y` is set, so
`zcat /proc/config.gz > .config` recovers a running config if needed.

Avoid `make config`: it walks every symbol in order. `make oldconfig`
prompts only for genuinely new ones, and `make olddefconfig` — what
`build.sh` uses — takes their defaults without prompting.

Keep the previous kernel's rEFInd entry until the new one boots clean.

## nvidia across kernel updates

`nvidia-drivers[modules]` registers in `/var/lib/module-rebuild/moduledb`,
and `@module-rebuild` recompiles it against whatever `/usr/src/linux`
points at. `scripts/30-gpu.sh` installs
`/etc/kernel/postinst.d/90-nvidia-modules` so `make install` triggers
that rebuild by itself.

`kernel-open` is mandatory: Blackwell has no proprietary kernel module.
`dist-kernel` is off in `package.use/nvidia` — it belongs to the
dist-kernel path we do not use.

Review `config-checklist.md` after a fragment change, especially the
"must NOT be set" nvidia notes.

## Stability first

- EXPO stays only while MEMTEST86+ passes; drop to JEDEC on any weirdness.
- `amd_pstate=active` on the cmdline; EPP is pushed to `performance`
  through `/sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference`
  by `/etc/local.d/epp.start` (written by scripts/40-services.sh).
- BBR + fq sysctls live in `/etc/sysctl.d/90-bbr.conf` (same script).

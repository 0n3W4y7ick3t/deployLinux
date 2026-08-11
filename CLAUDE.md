# CLAUDE.md

Context for anyone — human or Claude — picking this repo up cold.

## What this repo is

The **system layer** for a two-machine Linux fleet: root-owned files,
packages, services. The **user layer** (dotfiles, Hyprland config) is a
separate repo, [rice](https://github.com/0n3W4y7ick3t/rice), deployed
with yadm. Keep the split: if it lives in `$HOME`, it belongs in rice.

Two machines, both Gentoo + OpenRC + Hyprland (Wayland):

Gentoo runs on **one** machine: `pc` / **neverland** — Ryzen 9800X3D
(Zen5), RTX 5080, TUF B850-PLUS. OpenRC + Hyprland (Wayland).

**The ThinkPad X13 runs Arch** (`targets/arch`), settled 2026-08-11 after
trying the alternatives. It was a Gentoo binhost client; both the binhost
and a distcc replacement were removed. The reasoning, so nobody relitigates
it: the laptop's pain was `mesa` and `llvm/clang`, neither has a `-bin` in
::gentoo, and `mesa[radeonsi]` hard-requires `llvm[llvm_targets_AMDGPU]`
— so no amount of trimming its world file avoids them. A binhost forced
`VIDEO_CARDS`/`CPU_FLAGS_X86`/`-march` to fleet-wide
lowest-common-denominators; distcc only halved the build time and coupled
the machines on gcc version instead. Arch installs both as binaries.

Consequence: with nothing else consuming these binaries, the pc builds
`-march=native` (znver5) with the full Zen5 `CPU_FLAGS_X86`. Do not
reintroduce a lowest-common-denominator without a reason.

## Layout

```
common/          lib.sh, detect.sh, keyd config, vendored rEFInd + fonts
docs/            install-os.md, bootstrap-{gentoo,arch}.md, maintenance.md
targets/gentoo/
  provision.sh   entry point: runs scripts/ in order for a profile
  ch_gentoo.sh   chroot helper
  world          base package list (fleet-wide)
  scripts/       10-portage 15-kernel 20-world 30-gpu 40-services
                                50-virt 51-kali-vm(opt-in) 70-ollama
  portage/       make.conf.shared, package.use/, sets/, env/
  profiles/<n>/  profile.conf, make.conf.head, world-extra, fstab, kernel/
```

**Adding a machine = adding `profiles/<name>/`.** The scripts never change.

## Conventions

- Every script is POSIX `sh`, `set -eu`, idempotent, and sources
  `common/lib.sh`. Run `shellcheck` (config in `.shellcheckrc`) before
  committing.
- Portage config is **generated from this repo**, never hand-edited in
  `/etc/portage`. Fix the repo and re-run `provision.sh`.
- `package.use/deps` holds flags forced by dependency resolution, with a
  comment naming the consumer. Topical files (`virt`, `media`, `nvidia`,
  `desktop`, `pkg.use`) hold flags we actually chose. Keep them separate —
  a flag in `deps` can be deleted the day its consumer goes, and knowing
  *which* consumer is the whole point.
- Machines are told apart by **yadm class**, not hostname. Hostnames are
  free (`neverland`); `yadm config local.class pc` is what selects files.
- Commits: no `Co-Authored-By` trailer. Don't push without asking.

## Hard-won gotchas

These cost real debugging during the first end-to-end install. None of
them produce an obvious error at the point you make the mistake.

**No initramfs anywhere.** `installkernel[-dracut]`, and the kernels build
their root filesystem in. Consequences:

- The cmdline must use `root=PARTUUID=`, never `root=UUID=`. The kernel
  cannot resolve filesystem UUIDs without userspace.
- `CONFIG_DEVTMPFS_MOUNT=y` is mandatory — nothing else creates `/dev`.
- Microcode must be linked in via `CONFIG_EXTRA_FIRMWARE`
  (`amd-ucode/microcode_amd_fam1ah.bin` = family 0x1A = Zen5). Late
  loading is disabled on current kernels. `linux-firmware` therefore has
  to be installed *before* the kernel is built.
- Root fs and its controller must be `=y`, never `=m`.

**A dist-kernel does not work here** without turning dracut back on: it
ships ext4/xfs as modules. Do not add `sys-kernel/gentoo-kernel`.

**`sys-kernel/installkernel` must stay in `world`.** Not implicitly
installed since 2024-02-26. Without it `make install` writes an
unversioned `bzImage` and silently skips `/etc/kernel/postinst.d`, which
is where the nvidia module rebuild hooks in.

**Kernel builds before the world merge** (`15-kernel.sh`).
`nvidia-drivers[modules]` needs `/usr/src/linux/Module.symvers` and fails
its setup phase without it.

**`select`-only Kconfig symbols fail silently.** `HMM_MIRROR` and
`DRM_TTM_HELPER` have no prompt — a fragment cannot set them, only a
driver can `select` them. `merge_config` warns only on *conflicts* and
`olddefconfig` drops unsatisfiable symbols without a word. That is why
`profiles/pc/kernel/build.sh` **asserts** its critical symbols after
generating the config. Add new must-have symbols to that assert list.

- `DRM_TTM_HELPER` is required by nvidia-drivers on 6.11+ whenever
  `DRM_FBDEV_EMULATION` is set; `DRM_QXL=m` pulls it in inertly (it only
  binds to QEMU's virtual GPU). `DRM_AMDGPU=m` would also work and would
  drive the 9800X3D's iGPU, but makes the box multi-GPU and Hyprland then
  needs `AQ_DRM_DEVICES` pointed at the 5080.

**RTX 5080 is Blackwell**: `kernel-open` is mandatory, there is no
proprietary module. `dist-kernel` USE is off — `@module-rebuild` via the
postinst hook does the rebuilds.

**First `emerge -uDN @world` on a fresh stage3 hits a dependency cycle**
(`pillow[truetype]` → `harfbuzz` → `glib` → `docutils` → `pillow`).
`20-world.sh` breaks it with a one-shot `pillow[-truetype]`.

**fcitx5 on Wayland**: set `XMODIFIERS` only. Forcing `GTK_IM_MODULE` or
`QT_IM_MODULE` pushes GTK4/Qt6 onto the X11 path and breaks the candidate
popup. rice owns that env var — do not duplicate it here.

## neverland: disk facts

| what | value |
| :--- | :--- |
| root | `/dev/nvme1n1p4` xfs, label `gentoo` |
| root UUID | `7e1bced5-b47f-4b3e-804c-7d9704ea036c` (fstab) |
| root **PARTUUID** | `930cb6af-5985-4512-8d3c-b1bbee3f8205` (**cmdline**) |
| ESP | `/dev/nvme1n1p1` vfat `6641-7CF6` → `/boot/efi`, shared with Windows |
| NTFS `DATA` | `/dev/nvme0n1p1` `FF6EE27E8F60EAC8` → `/home/data`, noauto |
| NTFS `Lose` | `/dev/nvme1n1p3` `C3589E50BA73E9FD` → `/mnt/lose`, noauto |
| kali | `/dev/nvme1n1p5` xfs — **not ours, leave alone** |

`/boot` is a directory on the xfs root, not a partition. rEFInd reads it
using `EFI/refind/drivers/xfs_x64.efi` — if that driver goes, the kernel
vanishes from the boot menu.

## Recovering a machine that will not boot

The live USB is the way back in. From any live ISO, as root:

```sh
mount /dev/nvme1n1p4 /mnt/gentoo
mount /dev/nvme1n1p1 /mnt/gentoo/boot/efi
sh /mnt/gentoo/deploy/deployLinux/targets/gentoo/ch_gentoo.sh /mnt/gentoo
source /etc/profile
```

The repo is checked out inside the target at **`/deploy/deployLinux`**.
Re-run `./provision.sh --profile pc --hostname neverland` — every script
is idempotent, and `15-kernel.sh` skips the rebuild unless
`KERNEL_REBUILD=1`.

`/boot` keeps the previous kernel as `vmlinuz-*.old`; rEFInd will offer
it. See `docs/maintenance.md` for the full recovery matrix.

## State of the neverland deploy — 2026-08-11

First end-to-end run of this repo. ~43 bugs found and fixed, grouped into
six commits by theme — the reasoning is in those messages (`git log`),
and the parts worth not relearning are under "Hard-won gotchas" above.

**Done and verified:**

- stage3, profile `default/linux/amd64/23.0`, guru + hyproverlay synced
- `/etc/fstab` real (verified with `findmnt --verify`), timezone JST,
  locales `en_US` / `zh_CN` / `ja_JP`, hostname `neverland`
- user `leon` (uid 1000, wheel video audio usb portage input render),
  **both accounts were created with a throwaway password — change them
  before this machine is on a network**
- kernel **7.1.8-gentoo** built from `config-fragment`, installed with the
  previous build kept as `.old`; all config assertions pass
- `nvidia-drivers-610.57.04` merged, all 5 modules built
- ~940 packages installed

**Not done yet — the machine is not usable until these run:**

1. finish `20-world.sh` (hyprland stack), then `30-gpu` → `70-ollama`.
   **`40-services.sh` is the critical one**: nothing is in a runlevel yet,
   so a reboot right now gives no network, no elogind, no dbus.
2. `/boot/refind_linux.conf` — copy `profiles/pc/refind_linux.conf`.
   Without it rEFInd boots the kernel with no `root=` and it panics.
3. `emerge sys-block/zram-init` (it is in `world`, so `20-world` covers
   it); `40-services.sh` writes its conf.d and runlevel entry.
4. Reboot and work through `targets/gentoo/runbook.md` §8.

**Known post-boot tasks:**

- `yadm clone`, `yadm config local.class pc`, `yadm alt`, `yadm bootstrap`
- replace `CHANGE_ME_27INCH` in `~/.config/hypr/machine.conf` with the 27"
  panel's `description` from `hyprctl monitors`
- add Pinyin and Mozc in `fcitx5-configtool` — installed, not enabled
- `tailscale up --hostname=neverland`
- change both passwords

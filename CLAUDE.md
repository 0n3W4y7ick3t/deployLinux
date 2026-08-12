# CLAUDE.md

Context for anyone — human or Claude — picking this repo up cold.

## What this repo is

The **system layer** for a two-machine Linux fleet: root-owned files,
packages, services. The **user layer** (dotfiles, Hyprland config) is a
separate repo, [rice](https://github.com/0n3W4y7ick3t/rice), deployed
with yadm. Keep the split: if it lives in `$HOME`, it belongs in rice.

Two machines, both Gentoo + OpenRC + Hyprland (Wayland):

Gentoo runs on **one** machine: `desktop` / **neverland** — Ryzen 9800X3D
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

Consequence: with nothing else consuming these binaries, the desktop builds
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
  free (`neverland`); `yadm config local.class desktop` is what selects files.
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
`profiles/desktop/kernel/build.sh` **asserts** its critical symbols after
generating the config. Add new must-have symbols to that assert list.

- `DRM_TTM_HELPER` is required by nvidia-drivers on 6.11+ whenever
  `DRM_FBDEV_EMULATION` is set; `DRM_AMDGPU=m` provides it here (and
  drives the 9800X3D's iGPU), which makes the box multi-GPU — see the
  `AQ_DRM_DEVICES` gotcha below.

**`AQ_DRM_DEVICES` is a colon-separated list** — a `/dev/dri/by-path/...`
node name contains colons and therefore can never go in it: aquamarine
splits it into garbage, finds zero GPUs and aborts. That was the
2026-08-12 "Hyprland won't start" (4 identical crash reports in
`~/.cache/hyprland/`). `/dev/dri/cardN` is not stable across boots
either. The pin lives in rice's `shell/profile`, which resolves the
by-path link to the real `cardN` at login and exports it, fail-soft.
Do not add an `env = AQ_DRM_DEVICES,...` line to any hyprland config.

**Never write to an NTFS volume with the in-kernel `ntfs3` driver — and
never write to Windows C: from Linux at all.** ntfs3 rw mounts (plus one
hard reset) left C:'s `$LogFile` blanked, which `ntfs.sys` refuses on a
boot volume: Windows died with `UNMOUNTABLE_BOOT_VOLUME 0xED` (2026-08)
and needed a WinPE `chkdsk C: /f`. The ban is enforced three ways: fstab
mounts NTFS with `ntfs-3g` (FUSE) only and C: read-only, `/etc/modprobe.d/ntfs3.conf`
defeats even an explicit `mount -t ntfs3` (written by `40-services.sh`),
and the desktop kernel no longer builds the module (`build.sh` asserts it
stays gone, and that `FUSE_FS=y` stays). Honest caveat: *any* rw NTFS
mount empties the journal by design — Windows accepts that; it is only
ever fatal in combination with an OS volume and an unclean end. Data
volumes risk at most a chkdsk.

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

**`/dev/nvmeXnY` names are NOT stable — the two NVMe drives swap between
boots** (observed both orders). Identify disks by UUID/label/PARTUUID
only; run `blkid` or `lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID` to map them
to whatever names the current boot assigned.

Shared disk (Samsung 990 PRO 2T; ESP + Windows C: + gentoo + kali —
slots renumbered contiguously with `sgdisk -s` on 2026-08-12, so notes
older than that may say p3/p4/p5):

| what | stable identity | mount |
| :--- | :--- | :--- |
| ESP (p1, ~317M) | vfat UUID `6641-7CF6` | `/boot/efi`, shared with Windows, fsck passno 0 |
| Windows C: (p2) | ntfs label `Lose`, UUID `C3589E50BA73E9FD` | `/mnt/LOSE`, **ro**, ntfs-3g, noauto |
| root (p3) | xfs label `gentoo`, UUID `7e1bced5-b47f-4b3e-804c-7d9704ea036c` | `/`; cmdline needs **PARTUUID** `930cb6af-5985-4512-8d3c-b1bbee3f8205` |
| kali (p4) | xfs label `kali` | **not ours, leave alone** |

History: Windows' 16 MiB MSR/WinRE partition (the old p2) was deleted in
the 2026-07-15 resize that made room for Linux
(`$WINRE_BACKUP_PARTITION.MARKER` sits on C:'s root); the hole it left
was absorbed into the ESP on 2026-08-12 and the slots sorted. Windows
has no recovery partition: WinPE media is the recovery path. Everything
that boots this box references partitions by GUID (cmdline PARTUUID,
fstab UUIDs, BCD, firmware entries), so the renumbering is inert.

Second disk (2T): NTFS label `DATA`, UUID `FF6EE27E8F60EAC8` →
`/mnt/DATA`, rw via ntfs-3g, noauto.

`/boot` is a directory on the xfs root, not a partition. rEFInd reads it
using `EFI/refind/drivers/xfs_x64.efi` — if that driver goes, the kernel
vanishes from the boot menu.

## Recovering a machine that will not boot

The live USB is the way back in. From any live ISO, as root — mount by
label/UUID, never by `/dev/nvmeXnY` (the names swap between boots; the
old recipe here once pointed at what is today the NTFS DATA disk):

```sh
mount LABEL=gentoo /mnt/gentoo
mount UUID=6641-7CF6 /mnt/gentoo/boot/efi
sh /mnt/gentoo/deploy/deployLinux/targets/gentoo/ch_gentoo.sh /mnt/gentoo
source /etc/profile
```

The repo is checked out inside the target at **`/deploy/deployLinux`**.
Re-run `./provision.sh --profile desktop --hostname neverland` — every script
is idempotent, and `15-kernel.sh` skips the rebuild unless
`KERNEL_REBUILD=1`.

`/boot` keeps the previous kernel as `vmlinuz-*.old`; rEFInd will offer
it. See `docs/maintenance.md` for the full recovery matrix.

## State of the neverland deploy — 2026-08-12

The 2026-08-11 first end-to-end run (~43 bugs, six themed commits) is
complete and the machine boots into Hyprland. On 2026-08-12 two failures
were diagnosed and repaired **offline from a live USB** (Gentoo mounted
at `/mnt/gentoo` — the recovery recipe above is exactly how):

- **Windows `UNMOUNTABLE_BOOT_VOLUME 0xED`**: C:'s NTFS journal
  (`$LogFile`) was blanked to `0xFF` by Linux-side rw `ntfs3` mounts plus
  a hard reset. Windows' event log showed a clean last shutdown — the
  damage was entirely from our side. Fix: WinPE `chkdsk C: /f` (see the
  checklist below); prevention: the NTFS gotcha above (ntfs-3g only,
  C: read-only, module banned, kernel drops it).
- **Hyprland abort on start**: the `AQ_DRM_DEVICES` colon trap above.
  Fixed in rice (`shell/profile` resolves the by-path node at login);
  `start-hyprland` output now persists to `~/.cache/hyprland/session.log`.

Kernel rebuilt the same day (still `7.1.8-gentoo`; previous build kept as
`.old` in rEFInd) — `ntfs3.ko` no longer exists, nvidia modules rebuilt.
A `WePE64.iso` (repack of the WePE partition for the Ventoy menu) lives
on the Ventoy USB's `os/` folder and on `DATA/Downloads`.

**Accounts still carry the throwaway install password — change them.**

## After reboot — TODO (2026-08-12)

Work top to bottom; Windows first (its repair finishes on boot), Gentoo
second. Before rebooting: both monitor cables belong on the 5080.

1. ~~**Windows**~~ — booted clean without needing the WePE `chkdsk`.
2. ~~**In Windows**~~ — `fsutil dirty query C:` reports **NOT dirty** and
   `powercfg /h off` is done, so hibernation can no longer hand Linux a
   half-shut-down volume.
3. ~~**Gentoo**~~ — tty1 lands in Hyprland, `AQ_DRM_DEVICES` resolves to a
   real `/dev/dri/cardN`, both panels are up, and
   `~/.cache/hyprland/session.log` is being written.
4. ~~**NTFS policy live-check**~~ — passed 2026-08-12: DATA mounts `fuseblk`
   rw, LOSE `fuseblk` ro, and `mount -t ntfs3` fails with "unknown
   filesystem type 'ntfs3'".
5. ~~Delete the rescue image~~ — done 2026-08-12, by hand.
   `lose-ntfs-meta.img` is gone. What `/root/rescue-20260812/` still holds
   is 56K worth keeping: the
   `nvme0n1-gpt-{pre,post}.bak` GPT backups and `sgdisk-p-pre.txt` from the
   partition renumbering, plus `.orig` copies of fstab/profile/machine.conf
   that are all in git now. Keep the GPT backups until the partition table
   stops changing.
6. ~~**yadm, properly**~~ — done 2026-08-12. `local.class desktop`, origin is the
   rice remote, tree clean. `machine.conf` is now a `yadm alt` symlink and
   the tracked fallback is `machine.conf##default`.
7. ~~Push both repos~~ — done. `/deploy/deployLinux` still needs `git pull`.
   Pushing needs `gh auth switch -u 0n3W4y7ick3t` first: gh defaults to the
   `the other` account, which gets a 403 on these repos.
8. Change both throwaway passwords. ~~tailscale~~ (up as `neverland`) and
   ~~Pinyin~~ (fcitx5 `DefaultIM=pinyin`, Mozc alongside) are done.
9. Optional cleanup: the WePE **partition** on the Ventoy stick is now
   redundant (the ISO replaces it) — reclaim it into the exfat data
   partition whenever convenient, or keep it as a belt-and-suspenders
   boot path.

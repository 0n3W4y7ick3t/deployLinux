# CLAUDE.md

Context for anyone — human or Claude — picking this repo up cold.

## What this repo is

The **system layer** for a two-machine Linux fleet: root-owned files,
packages, services. The **user layer** (dotfiles, Hyprland config) is a
separate repo, [rice](https://github.com/0n3W4y7ick3t/rice), deployed
with yadm. Keep the split: if it lives in `$HOME`, it belongs in rice.

Two machines. Both run Hyprland on Wayland and share the rice user layer;
**everything below Hyprland differs**, and that is deliberate:

| hostname | yadm class | distro / init | hardware | bootloader |
| :--- | :--- | :--- | :--- | :--- |
| **neverland** | `desktop` | Gentoo + OpenRC | Ryzen 9800X3D (Zen5), RTX 5080, TUF B850-PLUS | rEFInd |
| **archtop** | `x13` | Arch + systemd | ThinkPad X13 Gen 4, AMD, integrated Radeon | systemd-boot + UKI |

The laptop's hostname is `archtop` and its class is `x13` — a reminder that
the two are unrelated. Everything in this repo keys off the class; the
hostname is only what tailscale and the shell prompt show.

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
common/          lib.sh, detect.sh, keyd config, issue, env.d, root-zshrc,
                 vendored rEFInd + fonts — shared by every target
docs/            install-os.md, bootstrap-{gentoo,arch}.md, maintenance.md
targets/gentoo/  neverland
  provision.sh   entry point: runs scripts/ in order for a profile
  ch_gentoo.sh   chroot helper
  world          base package list (fleet-wide)
  scripts/       10-portage 15-kernel 20-world 25-fonts 30-gpu 40-services
                                50-virt 51-kali-vm(opt-in) 70-ollama
  portage/       make.conf.shared, package.use/, sets/, env/
  profiles/<n>/  profile.conf, make.conf.head, world-extra, fstab, kernel/
targets/arch/    x13 — one detecting bootstrap.sh + flat pkgs-*.txt lists
targets/server/  headless boxes
targets/wsl2-arch/
```

**Adding a Gentoo machine = adding `profiles/<name>/`.** The scripts never
change. The Arch target has no profiles at all: `common/detect.sh` decides
GPU/CPU/chassis at run time, so adding a machine there is adding nothing.

`targets/arch/bootstrap.sh` is the systemd counterpart of
`targets/gentoo/scripts/40-services.sh` — same files, same reasons,
different mechanism (`/etc/environment` for env.d, zram-generator for
zram-init, `fstrim.timer` for cron.weekly, tmpfiles for local.d). **Change
one, check the other.**

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
  free (`neverland`, `archtop`); `yadm config local.class desktop` (or `x13`)
  is what selects files. The class was renamed `pc` → `desktop` on
  2026-08-12; `--pc` survives only as an alias in the Arch bootstrap.
- Commits: no `Co-Authored-By` trailer. Don't push without asking.

## Hard-won gotchas

These cost real debugging during the first end-to-end install. None of
them produce an obvious error at the point you make the mistake. Unless a
gotcha says otherwise it is about **neverland/Gentoo**; the NTFS,
bootloader and fcitx5 ones apply fleet-wide.

**No initramfs on neverland.** `installkernel[-dracut]`, and the kernels
build their root filesystem in. (The X13 is ordinary Arch: mkinitcpio, and
the initramfs is inside its UKI.) Consequences on the desktop:

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
defeats even an explicit `mount -t ntfs3` (written by `40-services.sh` on
Gentoo and by `targets/arch/bootstrap.sh` on Arch — Arch's stock kernel
*does* build ntfs3, so the modprobe ban is the only thing standing there),
and the desktop kernel no longer builds the module (`build.sh` asserts it
stays gone, and that `FUSE_FS=y` stays). Honest caveat: *any* rw NTFS
mount empties the journal by design — Windows accepts that; it is only
ever fatal in combination with an OS volume and an unclean end. Data
volumes risk at most a chkdsk.

**The X13 is a deliberate exception to the read-only half, and only that
half.** Its `nvme0n1p3` *is* Windows 11's C: and fstab mounts it `rw` at
`/mnt/DATA` via ntfs-3g — chosen knowingly on 2026-08-13, after the 0xED
story above was on the table. What makes it survivable, and what must stay
true: `powercfg /h off` in Windows (no `hiberfil.sys`, no fast startup, so
Linux never meets a half-shut-down volume), ntfs-3g only, ntfs3 banned,
and no hard resets out of a session that wrote to it. If Windows there
ever BSODs 0xED, this is the first suspect and the mount goes `ro`.
Do not copy the exception to neverland: C: there stays `ro`.

**Bootloaders are per-machine on purpose (settled 2026-08-13).** neverland
uses rEFInd, x13 uses systemd-boot. That is not drift — each matches its
kernel layout, and the reasoning is recorded here so nobody relitigates
it. neverland has no initramfs and `/boot` is a *directory* on the xfs
root, so the loader itself has to read xfs: rEFInd does it with
`EFI/refind/drivers/xfs_x64.efi`. systemd-boot cannot — it loads only from
the ESP or an XBOOTLDR partition, so adopting it would mean copying
`vmlinuz` and `vmlinuz.old` onto a 317M ESP shared with Windows on every
kernel build, through an `installkernel[systemd-boot]` hook, to gain
nothing. The X13 is the mirror image: mkinitcpio already builds a UKI at
`EFI/Linux/arch-linux.efi`, and systemd-boot auto-discovers it *and*
Windows' `bootmgfw.efi` with no config, keeps TPM2 measurement and boot
counting, and updates itself via `systemd-boot-update.service`. The
rEFInd that predated Arch on that ESP was removed on 2026-08-13: it was
not a pacman package, so nothing would ever have updated it, and two
loaders in `BootOrder` is a maintenance trap with no upside.
**GRUB2 was considered and rejected for both** — it can read xfs, so it
would work on neverland, but it swaps a 200KB loader that already works
for `grub-mkconfig`, os-prober and a much larger surface, and none of its
distinguishing features buy this fleet anything. Do not "unify" the two
machines on one loader; do not add a bootloader step to
`targets/arch/bootstrap.sh`.

**RTX 5080 is Blackwell**: `kernel-open` is mandatory, there is no
proprietary module. `dist-kernel` USE is off — `@module-rebuild` via the
postinst hook does the rebuilds.

**Docker cannot publish ports without `CONFIG_NETFILTER_XT_NAT`.** `NF_NAT`
is only the engine and `NFT_NAT` only the native nft expression; neither
gives `nft_compat` anything to bind `-j DNAT` to. Every `docker run -p`
then dies with "Extension DNAT revision 0 not supported, missing kernel
module?" — and `docker start` afterwards leaves the container **running
with no ports and no network at all**, which reads like a broken image
rather than a kernel gap. `build.sh` asserts it next to the libvirt
symbols. The module loads into a running kernel of the same version, so
the fix does not need a reboot.

**cronie ships `/var/spool/cron/crontabs`, but nothing fixes its parent.**
`/var/spool/cron` was left `drwxr-x--- root:cron` while `/usr/bin/crontab`
is setgid **crontab** (gid 460 — *not* cron, gid 16), so crontab cannot
traverse into its own spool. Every call then fails with
"'/var/spool/cron/crontabs' is not a directory", `crontab -l` included,
which points at the wrong thing entirely: the directory exists, the path
to it is unreadable. `40-services.sh` fixes both the parent and the mode.

**First `emerge -uDN @world` on a fresh stage3 hits a dependency cycle**
(`pillow[truetype]` → `harfbuzz` → `glib` → `docutils` → `pillow`).
`20-world.sh` breaks it with a one-shot `pillow[-truetype]`.

**libvirt's `default` network stays inactive after a fresh provision.**
`virsh net-autostart` only takes effect at the *next* libvirtd start, so a run
that enables it after libvirtd is already up leaves the network `Autostart:
yes / Active: no`. Everything looks fine until a `virt-install` dies with
`network 'default' is not active` — for `51-kali-vm.sh` that is *after* a
3.6 GB download. Both `50-virt.sh` and `51-kali-vm.sh` now check `net-info`
and `net-start` it.

**A VM you cannot see or control is the default outcome here.** Three
separate things have to be right, and none of them are on by default:
`app-emulation/virt-manager[gui]` (without it only `virt-install` is
installed — a `--graphics spice` domain has no viewer at all),
`app-emulation/libvirt[policykit]` (this is what creates the `libvirt` group
and the polkit rules; without it the rw socket is root-only `0700` and only
sudo can drive a VM), and actual group membership. `50-virt.sh`/`30-gpu.sh`
used to just `log "reminder: usermod ..."` and never do it; they now add
`${VIRT_USER:-$SUDO_USER}` to `libvirt`/`kvm`/`video`. Group changes need a
re-login.

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

## x13: disk facts

One NVMe (931.5G), three partitions, dual-boot with Windows 11:

| what | stable identity | mount |
| :--- | :--- | :--- |
| ESP (p1, 500M) | vfat UUID `CF81-B871` | `/boot/efi`, shared with Windows, passno 0 |
| root (p2, 300G) | xfs UUID `3ecf2c79-e029-4cbb-a697-661b06f53320` | `/` |
| Windows C: (p3, 631G) | ntfs label `Windows`, UUID `DF789AE0EAFFCC6C` | `/mnt/DATA`, **rw** — the documented exception above |

No swap partition (zram, like neverland). Windows here also has no
recovery partition — `$WINRE_BACKUP_PARTITION.MARKER` sits on its root,
same resize practice as the desktop — so WinPE media is again the only
recovery path.

**The ESP must stay in `/etc/fstab`.** It is where mkinitcpio writes the
UKI. If it is ever not mounted at upgrade time, `mkinitcpio -P` writes
`EFI/Linux/arch-linux.efi` into an empty directory on the xfs root, the
ESP keeps the previous kernel, and the machine boots an old kernel against
new `/usr/lib/modules` — which fails in a way that looks like anything but
a mount problem. Leaving it to systemd's gpt-auto (the state archinstall
left behind) works until it does not.

## Recovering a machine that will not boot

The live USB is the way back in. From any live ISO, as root — mount by
label/UUID, never by `/dev/nvmeXnY` (the names swap between boots; the
old recipe here once pointed at what is today the NTFS DATA disk):

```sh
mount LABEL=gentoo /mnt/gentoo
mount UUID=6641-7CF6 /mnt/gentoo/boot/efi
sh /mnt/gentoo/home/leon/akira/deployLinux/targets/gentoo/ch_gentoo.sh /mnt/gentoo
source /etc/profile
```

The only checkout inside the target is the **normal user clone**,
`~/akira/deployLinux` (`/mnt/gentoo/home/leon/akira/deployLinux` from the
live ISO). There used to be a second one at `/deploy/deployLinux`; it was
deleted on 2026-08-13 because two checkouts of the same repo drift, and
the one you are not looking at is always the one provision.sh reads — a
kernel rebuild ran from the stale copy and silently produced a kernel
without the fix that prompted it.

Re-run `./provision.sh --profile desktop --hostname neverland` from that
clone — every script is idempotent, and `15-kernel.sh` skips the rebuild
unless `KERNEL_REBUILD=1`. If `$HOME` is unreadable for any reason, clone
fresh: `git clone https://github.com/0n3W4y7ick3t/deployLinux`.

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

## neverland: 2026-08-13

The 2026-08-12 TODO list is finished — Windows boots clean and is no longer
hibernating, the NTFS policy passed its live check (`mount -t ntfs3` fails
with "unknown filesystem type"), yadm is adopted at `local.class desktop`,
the rescue image is deleted, and the install passwords are changed. Only
one optional item is left over: the WePE **partition** on the Ventoy stick
is redundant now that the ISO is in `os/`, so it can be reclaimed into the
exfat data partition whenever convenient.

The machine became a daily driver on 2026-08-13, which is what turned up
the docker and cron bugs in the gotchas above. Two conventions came out of
that day and both are load-bearing:

- **Language toolchains do not come from portage.** `world` explains the
  reasoning at the point where they used to be listed. Anything that pins
  a version per project (mise, rustup) lives in the user layer.
- **One checkout of this repo per machine.** See the recovery section.

Pushing needs `gh auth switch -u 0n3W4y7ick3t` first — gh defaults to the
other account it is logged into, which gets a 403 on these repos.

## State of the x13 deploy — 2026-08-13

Arch installed 2026-08-12 with archinstall; `targets/arch/bootstrap.sh` ran
the same evening; audited against this repo on 2026-08-13. Working: tty1 →
Hyprland 0.56.2 on eDP-1 (1920x1200@60, scale 1.25), keyd, NetworkManager
with the iwd backend, bluetooth, pipewire (socket-activated by systemd — no
`gentoo-pipewire-launcher` here), fcitx5, yadm `local.class x13` with
`machine.conf` correctly alternated.

What the audit found, and what it means for the repo:

- The Arch target only ever did packages + four services. Everything
  `40-services.sh` writes on Gentoo — the ntfs3 ban, BBR, `/etc/issue`,
  editor/browser defaults, root-on-zsh — simply did not exist here.
  `bootstrap.sh` now covers all of it; re-run it to apply.
- `/etc/NetworkManager/conf.d/wifi_backend.conf` and the iwd service were
  hand-set during install and nothing in the repo reproduced them. Now the
  laptop branch writes both.
- rice shipped two Gentoo-only lines in the *shared* `hyprland.conf` — the
  hyprexpo plugin path and `gentoo-pipewire-launcher`. The plugin one was a
  live `hyprctl configerrors` failure on this machine. Both moved to
  `machine.conf##class.desktop`.
- rEFInd from the pre-Arch install was still on the ESP behind
  systemd-boot; removed. See the bootloader gotcha.

Three bugs only surfaced when `bootstrap.sh` first ran for real, all fixed
in the script and worth knowing before writing the next one:

- **`hostname` does not exist on Arch.** It ships in `inetutils`, not base.
  Use `uname -n`.
- **A sysctl file is not enough for BBR.** neverland builds it into the
  kernel; Arch ships `tcp_bbr.ko`, and without the module the setting is a
  silent no-op — `cubic` stays, and `bbr` never even appears in
  `tcp_available_congestion_control`. Hence `modules-load.d` + `sysctl
  --system`.
- **power-profiles-daemon fights TLP.** archinstall leaves PPD installed;
  the two `Conflicts=` each other, PPD wins the restart race and SIGTERMs
  tlp mid-apply ("Job for tlp.service canceled"), leaving no power
  management at all. The laptop branch masks PPD first.

Done 2026-08-13: rEFInd out of NVRAM and off the ESP, ESP pinned in fstab,
bootstrap re-run clean (tlp active, PPD masked, BBR live, ntfs3 refused),
mozc restored in `.config/fcitx5/profile` — note the ordering trap there,
fcitx5 saves its in-memory config on SIGTERM, so `yadm checkout` has to
come *after* the kill, not before.

Verified across the 2026-08-13 02:35 reboot, which is what makes the above
more than theory: `boot-efi.mount` now reports `SourcePath=/etc/fstab`
rather than gpt-auto, `BootOrder` is `0002,0003,0001` (systemd-boot,
its fallback, Windows — no rEFInd), Windows booted and shut down cleanly
in between, `hiberfil.sys` is gone from the volume after `powercfg /h off`,
wifi came up on the iwd backend, tlp and tailscaled are active, and
`hyprctl configerrors` is empty. tailscale joined the tailnet as `archtop`.

Still open:

1. Change the throwaway install password here too.
2. Leftovers on the ESP from the pre-Arch era: `EFI/HackBGRT`, `EFI/tools`
   (Mar 2024). Harmless, delete when curious.

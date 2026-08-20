# Bootstrapping an Arch machine

From a freshly installed base Arch (see [install-os.md](install-os.md))
to the full environment. Arch is what the **X13 laptop** runs; the desktop
runs Gentoo. Everything here is one script with hardware detection.

## 1. System layer

```
git clone https://github.com/0n3W4y7ick3t/deployLinux
cd deployLinux/targets/arch
sudo ./bootstrap.sh --hostname archtop  # add --desktop to force desktop extras
```

`--hostname` is optional and free-form: machines are told apart by yadm
class, never by hostname. `--pc` still works as an alias for `--desktop`.

What detection decides (see `sh ../../common/detect.sh --report`):

| detected | installs / enables |
| :--- | :--- |
| NVIDIA GPU | `nvidia-open-dkms nvidia-utils linux-headers` + `nvidia_drm modeset=1` |
| AMD GPU | `mesa vulkan-radeon libva-mesa-driver` |
| CPU vendor | `amd-ucode` / `intel-ucode` |
| laptop chassis | `tlp iwd brightnessctl`, tlp + iwd enabled, NM's wifi backend set to iwd |
| desktop chassis (or `--desktop`) | docker, k8s tools, libvirt, tailscale, pentest basics, EPP pinned to performance |
| bluetooth controller | bluez service enabled (bluez always installed) |

Everything else is flat package lists next to the script
(`pkgs-core.txt`, `pkgs-desktop.txt`, `pkgs-desktop-extra.txt`,
`pkgs-laptop.txt`). One package per line, `#` only at the start of a line —
an inline comment would be handed to pacman as a target.
AUR packages are never installed as root — the script prints the command
to run as your user:

```
yay -S --needed - < pkgs-aur.txt
```

Unconditional system config, the systemd counterpart of
`targets/gentoo/scripts/40-services.sh` (same files, same reasons):
keyd's caps⇄esc swap, `/etc/issue`, the **ntfs3 ban**, BBR congestion
control, `/etc/environment` (EDITOR/BROWSER, generated from
`common/env.d/99local` so the two distros cannot drift), root on zsh,
`fstrim.timer`, and zram swap at RAM/3 via zram-generator.

The stock `linux` kernel covers everything the Gentoo kernel checklist
enables.

## 2. Bootloader — not our business

`bootstrap.sh` deliberately never touches it. archinstall's default on the
X13 is **systemd-boot with a mkinitcpio-generated UKI** at
`EFI/Linux/arch-linux.efi`, which is exactly right: systemd-boot
auto-discovers the UKI *and* Windows' `bootmgfw.efi`, keeps TPM2
measurement and boot counting, and updates itself through
`systemd-boot-update.service`.

Do **not** install rEFInd here. It is neverland-only, and for a reason
that does not apply to a UKI machine — see the bootloader gotcha in
[CLAUDE.md](../CLAUDE.md). Two things to keep true on an Arch box:

- the ESP must be in `/etc/fstab`, not left to gpt-auto. If it is not
  mounted when the kernel is upgraded, `mkinitcpio -P` writes the UKI into
  an empty directory on the root fs and the ESP keeps a stale kernel while
  `/usr/lib/modules` moves on.
- `/etc/mkinitcpio.d/linux.preset` ships `default_uki` only. Uncommenting
  `fallback_uki` buys a recovery entry for the price of ~100M of ESP.

## 3. NTFS

The ban from the Gentoo target applies here too and `bootstrap.sh` writes
it: `/etc/modprobe.d/ntfs3.conf` blacklists the in-kernel driver and
`install ntfs3 /bin/false` defeats an explicit `mount -t ntfs3`. Arch's
stock kernel *builds* ntfs3, so this matters more here than on a machine
whose kernel we compile. Mount NTFS with `ntfs-3g` only. The X13's
documented rw exception on its Windows volume is described in
[CLAUDE.md](../CLAUDE.md).

## 4. User layer (yadm + rice)

Same as Gentoo — see
[bootstrap-gentoo.md § 2](bootstrap-gentoo.md#2-user-layer-yadm--rice).
Short version:

```
sudo pacman -S --needed yadm
yadm clone https://github.com/0n3W4y7ick3t/rice
yadm config local.class x13   # or desktop
yadm alt && yadm bootstrap
```

## 5. First boot checklist

The shared items from
[bootstrap-gentoo.md § 3](bootstrap-gentoo.md#3-first-boot-checklist):
Hyprland on tty1, `hyprctl configerrors` (must be empty), monitor EDID
fill-in, `nvidia-smi` + modeset, docker `--gpus all`, minikube, bluetooth,
fcitx5, caps⇄esc. Arch-only additions:

- `findmnt /boot/efi` is mounted, and from fstab
- `sysctl net.ipv4.tcp_congestion_control` reports `bbr`
- `systemctl is-active tlp` and `is-enabled iwd` on a laptop
- `sudo mount -t ntfs3 …` fails

The Kali VM script is reusable as-is:
[`targets/gentoo/scripts/51-kali-vm.sh`](../targets/gentoo/scripts/51-kali-vm.sh)
runs on any libvirt host (export `GENTOO_PROFILE=desktop` to satisfy its
profile gate).

## Mail (manual, after packages)

`pkgs-desktop.txt` installs the neomutt stack (neomutt, isync, msmtp,
notmuch) and `pkgs-aur.txt` has mutt-wizard. Mail account configs
(`~/.config/mutt`, `~/.mbsyncrc`, `~/.config/msmtp/config`) are
machine-local: copy them from a working machine (strip accounts that do
not belong on this one) or regenerate with `mw -a`; passwords come from
pass. Smoke test: `mw -Y`.

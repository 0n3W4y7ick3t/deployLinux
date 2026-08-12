# arch

Arch Linux deploy. This is what the **X13 laptop** runs (settled
2026-08-11, see CLAUDE.md); the desktop runs Gentoo. The script is generic
and detects the hardware, so it works on either box without a
machine-specific variant.

**Post-install target**: it assumes a base Arch system already boots
(archinstall or manual). Then, as root:

```
./bootstrap.sh [--hostname x13] [--desktop]
```

`--pc` is still accepted as an alias for `--desktop` (the class was
renamed 2026-08).

## Detection

`bootstrap.sh` uses `common/detect.sh` (run `sh ../../common/detect.sh
--report` to see what it will decide) and adapts:

- **GPU**: NVIDIA → `nvidia-open-dkms nvidia-utils linux-headers` plus a
  modprobe conf with `nvidia_drm modeset=1`; AMD → `mesa vulkan-radeon
  libva-mesa-driver`.
- **CPU vendor**: `amd-ucode` or `intel-ucode`.
- **Chassis**: laptop → `pkgs-laptop.txt` (tlp, iwd, brightnessctl), tlp
  and iwd enabled; desktop → `pkgs-desktop-extra.txt` (docker, k8s tools,
  libvirt, tailscale...) plus the EPP performance pin. `--desktop` forces
  desktop-class when detection cannot tell.
- **Bluetooth**: bluez is always installed (both machines have BT), but
  the service is only enabled when a controller is detected.

Package sets are plain files: `pkgs-core.txt`, `pkgs-desktop.txt`,
`pkgs-desktop-extra.txt`, `pkgs-laptop.txt`, `pkgs-aur.txt` (AUR ones are
printed as a yay command to run as your user, never installed as root).
One package per line; `#` starts a comment only at the beginning of a
line, since everything else is passed straight to pacman.

## System config

Unconditional, and the systemd counterpart of
`../gentoo/scripts/40-services.sh` — same files and same reasons, only the
mechanism differs:

| what | Gentoo | Arch |
| :--- | :--- | :--- |
| editor/browser defaults | `/etc/env.d/99local` + `env-update` | `/etc/environment` (pam_env), generated from the same file |
| zram swap (RAM/3) | `zram-init` + `/etc/conf.d` | `/etc/systemd/zram-generator.conf` |
| weekly TRIM | `/etc/cron.weekly/fstrim` | `fstrim.timer` |
| EPP pin (desktop) | `/etc/local.d/epp.start` | `/etc/tmpfiles.d/epp.conf` |
| ntfs3 ban, BBR sysctl, `/etc/issue`, keyd, root-on-zsh | identical files | identical files |

## Notes

- **Bootloader**: not touched, on purpose. archinstall's systemd-boot +
  mkinitcpio UKI is the right fit for Arch, and rEFInd is neverland-only —
  the reasoning is in CLAUDE.md. Keep the ESP in `/etc/fstab`, or a kernel
  upgrade can write its UKI somewhere the firmware never looks.
- Input: keyd swaps Caps Lock and Escape system-wide
  (`common/keyd-default.conf`, enabled as a service). A board that swaps the
  pair in its own firmware needs excluding there by vendor:product id, or
  the two swaps cancel out.
- Kernel: stock `linux` + `linux-firmware` cover everything the Gentoo
  kernel checklist enables; `linux-lts` is a commented fallback in
  `pkgs-core.txt`.
- Network: NetworkManager everywhere. On a laptop iwd becomes its wifi
  backend (`/etc/NetworkManager/conf.d/wifi_backend.conf`) and is enabled
  as a service — leaving it to D-Bus activation works right up until the
  boot where it does not.
- Hostname convention: free-form (`x13`, `neverland`). Machines are told
  apart by yadm class (`desktop` / `x13`), never by hostname.
- Kali VM: `../gentoo/scripts/51-kali-vm.sh` works on any libvirt host
  with sh + virt-install (export `GENTOO_PROFILE=desktop` to satisfy its
  profile gate), reuse it as-is.
- Binhost does not apply here (Gentoo-only concept).

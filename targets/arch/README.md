# arch

Generic Arch Linux deploy, the alternative-OS path for both machines (the
PC and the X13 laptop). Gentoo stays the primary OS; this target exists
so either box can run Arch without a machine-specific script.

**Post-install target**: it assumes a base Arch system already boots
(archinstall or manual). Then, as root:

```
./bootstrap.sh [--hostname localhost] [--pc]
```

## Detection

`bootstrap.sh` uses `common/detect.sh` (run `sh ../../common/detect.sh
--report` to see what it will decide) and adapts:

- **GPU**: NVIDIA → `nvidia-open-dkms nvidia-utils linux-headers` plus a
  modprobe conf with `nvidia_drm modeset=1`; AMD → `mesa vulkan-radeon
  libva-mesa-driver`.
- **CPU vendor**: `amd-ucode` or `intel-ucode`.
- **Chassis**: laptop → `pkgs-laptop.txt` (tlp, iwd, brightnessctl) and
  tlp enabled; desktop → PC-class extras (`pkgs-pc.txt`: docker, k8s
  tools, libvirt, tailscale...). `--pc` forces PC-class when detection
  cannot tell.
- **Bluetooth**: bluez is always installed (both machines have BT), but
  the service is only enabled when a controller is detected.

Package sets are plain files: `pkgs-core.txt`, `pkgs-desktop.txt`,
`pkgs-pc.txt`, `pkgs-laptop.txt`, `pkgs-aur.txt` (AUR ones are printed
as a yay command to run as your user, never installed as root).

## Notes

- Input: keyd swaps Caps Lock and Escape system-wide
  (`common/keyd-default.conf`, enabled as a service). A board that swaps the
  pair in its own firmware needs excluding there by vendor:product id, or
  the two swaps cancel out.
- Kernel: stock `linux` + `linux-firmware` cover everything the Gentoo
  kernel checklist enables; `linux-lts` is a commented fallback in
  `pkgs-core.txt`.
- Network: NetworkManager is installed and enabled, it covers ethernet
  and wifi on both boxes. iwd is installed on laptops and can replace or
  back NetworkManager if preferred.
- Hostname convention: `localhost` everywhere, machines are told apart
  by yadm class (`desktop` / `x13`), never by hostname.
- Kali VM: `../gentoo/scripts/51-kali-vm.sh` works on any libvirt host
  with sh + virt-install (export `GENTOO_PROFILE=desktop` to satisfy its
  profile gate), reuse it as-is.
- Binhost does not apply here (Gentoo-only concept).

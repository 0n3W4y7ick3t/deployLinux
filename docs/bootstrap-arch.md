# Bootstrapping an Arch machine

From a freshly installed base Arch (see [install-os.md](install-os.md))
to the full environment. This is the alternative-OS path for both
machines; Gentoo is the primary. Everything here is one script with
hardware detection.

## 1. System layer

```
git clone https://github.com/0n3W4y7ick3t/deployLinux
cd deployLinux/targets/arch
sudo ./bootstrap.sh --hostname localhost      # add --pc to force PC extras
```

What detection decides (see `sh ../../common/detect.sh --report`):

| detected | installs / enables |
| :--- | :--- |
| NVIDIA GPU | `nvidia-open-dkms nvidia-utils linux-headers` + `nvidia_drm modeset=1` |
| AMD GPU | `mesa vulkan-radeon libva-mesa-driver` |
| CPU vendor | `amd-ucode` / `intel-ucode` |
| laptop chassis | `tlp iwd brightnessctl`, tlp enabled |
| desktop chassis (or `--pc`) | docker, k8s tools, libvirt, tailscale, pentest basics |
| bluetooth controller | bluez service enabled (bluez always installed) |

Everything else is flat package lists next to the script
(`pkgs-core.txt`, `pkgs-desktop.txt`, `pkgs-pc.txt`, `pkgs-laptop.txt`).
AUR packages are never installed as root — the script prints the command
to run as your user:

```
yay -S --needed - < pkgs-aur.txt
```

keyd swaps Caps Lock and Escape system-wide, same as on Gentoo. The stock
`linux` kernel covers everything the Gentoo kernel checklist enables.

## 2. User layer (yadm + rice)

Same as Gentoo — see
[bootstrap-gentoo.md § 2](bootstrap-gentoo.md#2-user-layer-yadm--rice).
Short version:

```
sudo pacman -S --needed yadm
yadm clone https://github.com/0n3W4y7ick3t/rice
yadm config local.class desktop   # or x13
yadm alt && yadm bootstrap
```

## 3. First boot checklist

The shared items from
[bootstrap-gentoo.md § 3](bootstrap-gentoo.md#3-first-boot-checklist):
Hyprland on tty1, `hyprctl configerrors`, monitor EDID fill-in (PC),
`nvidia-smi` + modeset, docker `--gpus all`, minikube, bluetooth, fcitx5,
caps⇄esc. The Kali
VM script is reusable as-is:
[`targets/gentoo/scripts/51-kali-vm.sh`](../targets/gentoo/scripts/51-kali-vm.sh)
runs on any libvirt host.

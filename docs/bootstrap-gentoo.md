# Bootstrapping a Gentoo machine

From a freshly installed base Gentoo (see [install-os.md](install-os.md))
to the full working environment: system layer from this repo, user layer
from [rice](https://github.com/0n3W4y7ick3t/rice) via yadm. The terse
checklist version of this page is
[targets/gentoo/runbook.md](../targets/gentoo/runbook.md).

## 0. Before you start

Know what the machine is:

```
sh common/detect.sh --report
```

For the **pc** profile, BIOS first: enable the EXPO RAM profile, Resizable
BAR, and IOMMU/SVM. EXPO is a memory overclock — run one full pass of
memtest86+ before trusting the machine; fall back to JEDEC speeds if
anything fails.

## 1. System layer

Clone the repo and provision with your machine's profile:

```
git clone https://github.com/0n3W4y7ick3t/deployLinux
cd deployLinux/targets/gentoo
./provision.sh --profile pc --hostname localhost   # or --profile x13
```

`provision.sh` warns if the detected hardware does not match the profile,
then runs the numbered scripts:

| script | does |
| :--- | :--- |
| `10-portage.sh` | assembles make.conf (profile head + shared), installs package.use/sets, enables the hyproverlay and GURU overlays, syncs |
| `20-world.sh` | installs the base world, the profile's world-extra, and the `@hyprland` set |
| `30-gpu.sh` | NVIDIA driver + modprobe config, only when an NVIDIA GPU is detected |
| `40-services.sh` | OpenRC services (elogind, dbus, bluetooth, keyd caps⇄esc swap, ...), sysctl (BBR), EPP policy, hostname |
| `50-virt.sh` / `51-kali-vm.sh` | libvirt + the opt-in Kali VM (~3.6 GiB download, checksum-verified) — only with `WANT_VIRT=1` |
| `60-binhost.sh` | binhost **server** (pc) or **client** (x13) per the profile's `BINHOST_ROLE` |
| `70-ollama.sh` | ollama in docker with GPU — only with `WANT_OLLAMA=1` |

Profile behavior lives in `profiles/<name>/profile.conf`; adding a new
machine means adding a profile directory, nothing else.

**Kernel policy**: first boot runs the dist-kernel (`gentoo-kernel`) —
broad drivers, zero fiddling. When the machine is proven, build the lean
custom kernel from `profiles/<name>/kernel/config-fragment`; each
profile's `kernel/README.md` explains its options and the upgrade flow.

**Bootloader cmdline** (rEFInd `options` line, PC):
`nvidia_drm.modeset=1 fbdev=1 amd_iommu=on iommu=pt`

## 2. User layer (yadm + rice)

```
emerge app-admin/yadm    # already in the world list
yadm clone https://github.com/0n3W4y7ick3t/rice
yadm config local.class pc      # or: x13 / wsl / server
yadm alt
yadm bootstrap
```

The class drives which alternate files materialize (monitors, machine
config); hostname is irrelevant on purpose. On a machine with multiple
GitHub identities use the SSH alias form:
`yadm clone git@github-personal:0n3W4y7ick3t/rice.git`.

## 3. First boot checklist

Log in on tty1 — Hyprland starts automatically. Then:

- `hyprctl configerrors` — must be empty; `hyprctl monitors` — sane modes.
- **PC only**: replace `CHANGE_ME_27INCH` in
  `~/.config/hypr/machine.conf` with the 27" monitor's description from
  `hyprctl monitors` (one monitor line + nine workspace pins).
- `nvidia-smi` works; `cat /sys/module/nvidia_drm/parameters/modeset` is `Y`.
- `docker run --rm hello-world`, then
  `docker run --rm --gpus all nvidia/cuda:12.9.0-base-ubuntu24.04 nvidia-smi`.
- `minikube start --driver=docker && kubectl get nodes`.
- `virsh list --all`; run `51-kali-vm.sh` when you want the lab VM.
- Binhost: on the pc `curl -s localhost/binhost/ | head`; on the x13 an
  `emerge -pv <anything>` shows `[binary]` (set the server address in
  `/etc/portage/binrepos.conf` first — Tailscale MagicDNS name preferred).
- Bluetooth pairs (`bluetoothctl`), fcitx5 types Chinese in kitty and
  Firefox, Caps Lock and Escape are swapped.

## Known placeholders

| where | what to fill |
| :--- | :--- |
| `~/.config/hypr/machine.conf` (pc) | 27" monitor EDID description |
| `/etc/portage/binrepos.conf` (x13) | the PC's Tailscale hostname |
| `targets/gentoo/portage/` CPU flags | regenerate with `cpuid2cpuflags` on the x13 |
| `targets/gentoo/portage/sets/laptop-extra` | laptop-only packages the PC should also build |

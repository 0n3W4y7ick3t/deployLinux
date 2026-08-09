# gentoo runbook

One Gentoo target for the whole fleet, driven by machine profiles under
`profiles/` plus hardware detection (`common/detect.sh`). Current
profiles:

- **pc** — AMD Ryzen 7 9800X3D (Zen5), NVIDIA RTX 5080, ASUS TUF
  B850-PLUS WIFI (RTL8125 2.5GbE primary, Realtek 8922AE wifi/BT),
  27" 4K@60 + LG OLED TV 4K@120, ext4 root + xfs data, rEFInd, binhost
  **server**.
- **x13** — ThinkPad X13 Gen4 AMD laptop, existing install, binhost
  **client**.

Everything is OpenRC + Hyprland only. keyd swaps Caps Lock and Escape
system-wide (`common/keyd-default.conf`, installed by 40-services.sh).

**Adding a new machine = adding a new `profiles/<name>/` directory**
(profile.conf, make.conf.head, world-extra, kernel/, fstab) — the
scripts stay untouched.

On any hardware, start with: `sh ../../common/detect.sh --report`.

## Fresh install (generic flow)

### 1. BIOS

- pc: EXPO **ON**, then MEMTEST86+ until PASS — **required**; drop to
  JEDEC on any instability. Resizable BAR ON. IOMMU + SVM ON.

Verify: memtest pass; later `dmesg | grep -i 'AMD-Vi'`.

### 2. Partition + filesystems

pc: NVMe with ESP vfat 1G, root ext4, rest xfs
(`profiles/pc/fstab.example`). x13: see `profiles/x13/fstab`. fstab by
UUID only.

Verify: `blkid` lists everything, note the UUIDs.

### 3. Stage3

Latest **amd64-openrc** stage3 plus its `.sha256`:

```
mount /dev/nvme0n1p2 /mnt/gentoo
cd /mnt/gentoo
wget <stage3-amd64-openrc-*.tar.xz + .sha256>
sha256sum -c stage3-*.sha256
tar xpvf stage3-*.tar.xz --xattrs-include='*.*' --numeric-owner
```

Verify: `ls /mnt/gentoo/etc/gentoo-release`.

### 4. Chroot

```
./ch_gentoo.sh /mnt/gentoo
source /etc/profile
```

Verify: `emerge --info >/dev/null && echo ok`.

### 5. Provision

Copy this repo into the chroot, then from this directory:

```
./provision.sh --profile pc --hostname localhost
```

Runs `scripts/10-portage.sh` through `70-ollama.sh` in order; virt,
binhost role and ollama are decided by the profile (`profile.conf`),
GPU steps by detection. `51-kali-vm.sh` is opt-in (big download), run it
separately on virt-enabled profiles. `--hostname` writes
/etc/conf.d/hostname (omit to keep the current name). Fleet convention:
`localhost` everywhere, machines are told apart by yadm class, never by
hostname.

gcloud is NOT in the world lists: install it from the official Google
tarball afterwards.

Overlays: 10-portage.sh enables **hyproverlay** (hyprland stack) and
**GURU**. Note `app-misc/lf`, `media-gfx/nsxiv` and `app-misc/tealdeer`
are GURU-only these days (gone from ::gentoo); the accept_keywords file
already covers them.

Verify: each script logs completion; `emerge -pvuDN @world` is calm.

### 6. Kernel

Per profile: `profiles/<name>/kernel/README.md`. The pc policy is
dist-kernel first boot (`sys-kernel/gentoo-kernel` in its world-extra),
custom fragment build later. The x13 carries its known-good
`config-6.11.6`.

Verify: kernel image under `/boot`, modules under `/lib/modules/`.

### 7. Bootloader — rEFInd

Install from `../../common/refind` into the ESP. On the pc the options
line must carry:

```
options "root=UUID=... rw nvidia_drm.modeset=1 amd_iommu=on iommu=pt"
```

Full reference cmdline in `profiles/pc/kernel/config-checklist.md`.

Verify: `efibootmgr -v` lists rEFInd, then reboot into it.

### 8. First-boot checklist (pc)

- `hyprctl configerrors` clean; `hyprctl monitors` shows 4K@60 + 4K@120
- `nvidia-smi` works
- `cat /sys/module/nvidia_drm/parameters/modeset` prints `Y`
- `docker run --rm hello-world`
- `docker run --rm --gpus all nvidia/cuda:12.6.3-base-ubuntu24.04 nvidia-smi`
- `minikube start --driver=docker && kubectl get nodes`
- `virsh list --all` answers (libvirtd up)
- binhost serving: `curl -sI http://localhost/binhost/ | head -1`
- `bluetoothctl` pairs a device
- fcitx5 switches input methods; Caps/Esc are swapped (keyd)
- VRR active on the TV (`hyprctl monitors` shows the vrr flag)
- suspend/resume survives (nvidia PreserveVideoMemoryAllocations set)

## X13: existing install (no reinstall)

The laptop keeps its Gentoo. Two steps on the machine itself:

1. `./provision.sh --profile x13` — converges make.conf onto the shared
   fragment (znver4, getbinpkg), installs the shared portage tree, sets
   the binhost client role (edit the sync-uri host in
   /etc/portage/binrepos.conf to the PC's Tailscale MagicDNS or LAN
   name), services, keyd.
2. `profiles/x13/hypr-migrate.sh` — one-time dwm/X11 → Hyprland
   migration: flips the wayland USE, emerges @hyprland, prints the
   world-cleanup (`--deselect` of X-only leaves actually present) and
   stale-$HOME steps.

Wifi stays iwd + dhcpcd (`rc-update add iwd default`, done by
40-services.sh on laptop chassis). Networks live under
`/var/lib/iwd/SSID.psk`:

```
[Security]
Passphrase=your-super-secret-password
```

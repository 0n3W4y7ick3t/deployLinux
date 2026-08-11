# gentoo runbook

One Gentoo machine, driven by a profile under `profiles/` plus hardware
detection (`common/detect.sh`):

- **pc** / **neverland** — AMD Ryzen 7 9800X3D (Zen5), NVIDIA RTX 5080,
  ASUS TUF B850-PLUS WIFI (RTL8125 2.5GbE primary, Realtek 8922AE
  wifi/BT), 27" 4K@60 + LG OLED TV 4K@120, xfs root, rEFInd.

The ThinkPad X13 runs **Arch** (`../arch/`) — mesa and llvm/clang have no
binary form in Gentoo and radeonsi hard-requires both, which is a poor
trade on a laptop.

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

pc: NVMe with a vfat ESP at /boot/efi and an xfs root
(`profiles/pc/fstab`). fstab by UUID;
the kernel cmdline needs PARTUUID instead, there being no initramfs.

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

### 4b. Timezone, locale, accounts

Do this before rebooting, or the machine boots with no way in.

```
ln -sf ../usr/share/zoneinfo/Asia/Tokyo /etc/localtime
printf "en_US.UTF-8 UTF-8\nzh_CN.UTF-8 UTF-8\nja_JP.UTF-8 UTF-8\n" >> /etc/locale.gen
locale-gen
eselect locale set en_US.utf8
passwd
useradd -m -G wheel,video,audio,usb,portage,input,render -s /bin/bash <name>
passwd <name>
```

Also read the news: `eselect news read`. Switch the login shell to zsh
after provisioning installs it.

Verify: `id <name>`, `passwd -S root` shows `P`.

### 5. Provision

Copy this repo into the chroot, then from this directory:

```
./provision.sh --profile pc --hostname neverland
```

Runs `scripts/10-portage.sh` through `70-ollama.sh` in order (the kernel
is built by `15-kernel.sh`, before the world merge, because
nvidia-drivers needs built sources); virt,
virt and ollama are decided by the profile (`profile.conf`),
GPU steps by detection. `51-kali-vm.sh` is opt-in (big download), run it
separately on virt-enabled profiles. `--hostname` writes
/etc/conf.d/hostname (omit to keep the current name); add the name to
/etc/hosts too. The pc is `neverland`. Dotfiles are selected by yadm
class, not hostname, so the two are independent.

gcloud is NOT in the world lists: install it from the official Google
tarball afterwards.

Overlays: 10-portage.sh enables **hyproverlay** (hyprland stack) and
**GURU**. Note `app-misc/lf`, `media-gfx/nsxiv` and `app-misc/tealdeer`
are GURU-only these days (gone from ::gentoo); the accept_keywords file
already covers them.

Verify: each script logs completion; `emerge -pvuDN @world` is calm.

### 6. Kernel

Already done by `15-kernel.sh` during step 5. To rebuild by hand:
`sudo profiles/pc/kernel/build.sh` — it regenerates the config from
`config-fragment`, asserts the must-be-builtin symbols, and installs.
KERNEL_REBUILD=1 forces it when sources are already built.

Verify: `/boot/vmlinuz-*` exists (versioned — if it is a bare `bzImage`,
`sys-kernel/installkernel` is missing), modules under `/lib/modules/`,
and `/lib/modules/*/video/nvidia.ko*` was rebuilt by the postinst hook.

### 7. Bootloader — rEFInd

Install from `../../common/refind` into the ESP. Copy the driver
matching `/boot`'s filesystem out of `drivers_x64/` (ext4, xfs, btrfs,
ntfs, exfat) — rEFInd reads the kernel off that filesystem itself, so an
xfs `/boot` without `xfs_x64.efi` simply never appears in the menu. This
is also what lets rEFInd boot a second distro without its own bootloader.

The cmdline goes in `/boot/refind_linux.conf`, not in refind.conf;
rEFInd autodetects the kernel and reads its options from there:

```
"Boot default"  "root=PARTUUID=<gpt-partuuid> rw nvidia_drm.modeset=1 nvidia_drm.fbdev=1 amd_iommu=on iommu=pt amd_pstate=active"
```

PARTUUID, not UUID — nothing resolves filesystem UUIDs without an
initramfs. Checked-in copy: `profiles/pc/refind_linux.conf`.

Verify: `efibootmgr -v` lists rEFInd, then reboot into it.

### 8. First-boot checklist (pc)

- `hyprctl configerrors` clean; `hyprctl monitors` shows 4K@60 + 4K@120
- `nvidia-smi` works
- `cat /sys/module/nvidia_drm/parameters/modeset` prints `Y`
- `swapon --show` lists the zram device
- `dmesg | grep -i microcode` shows an early load, not a late one
  (late loading means CONFIG_EXTRA_FIRMWARE did not take)
- `docker run --rm hello-world`
- `docker run --rm --gpus all nvidia/cuda:12.6.3-base-ubuntu24.04 nvidia-smi`
- `minikube start --driver=docker && kubectl get nodes`
- `virsh list --all` answers (libvirtd up)
- `bluetoothctl` pairs a device
- fcitx5 switches input methods (Ctrl+Space) — Pinyin and Mozc must be
  added once in `fcitx5-configtool`; needs `exec-once = fcitx5 -d` in the
  rice hyprland.conf. Caps/Esc are swapped (keyd)
- VRR active on the TV (`hyprctl monitors` shows the vrr flag)
- suspend/resume survives (nvidia PreserveVideoMemoryAllocations set)

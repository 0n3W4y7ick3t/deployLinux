# Kernel config checklist (PC)

Human-readable version of `config-fragment`, grouped with the reasoning.
The fragment is the source of truth for exact symbols.

## Platform

Why: 9800X3D power management and monitoring on the B850 board.

- `X86_AMD_PSTATE` — modern AMD frequency control; cmdline pins
  `amd_pstate=active`, EPP is then set via sysfs (see pc README).
- `PREEMPT_DYNAMIC`, `HZ_1000`, `NO_HZ_IDLE`, `HIGH_RES_TIMERS` —
  desktop latency defaults; preempt mode stays runtime-switchable.
- `MICROCODE`, `EDAC_AMD64` — microcode + RAM error reporting
  (EXPO is on, we want to see ECC/EDAC complaints).
- `SENSORS_K10TEMP`, `SENSORS_NCT6775` — CPU + board sensors,
  NCT6775 family covers the ASUS Super I/O.
- `SP5100_TCO` — AMD chipset watchdog.
- `I2C_PIIX4`, `I2C_CHARDEV` — SMBus; RGB/OpenRGB and sensors tooling.
- `ZRAM` + `CRYPTO_ZSTD` + `SWAP` — compressed swap.
- `EFI`/`EFI_STUB`/`EFIVAR_FS` — rEFInd boots the kernel EFI-stub style.
- `BLK_DEV_NVME`, `MQ_IOSCHED_DEADLINE` — NVMe root.

## Filesystems

Why: xfs and ext4 are =y, so root mounts with no initramfs;
everything else modular for occasional media/USB/NFS use. `OVERLAY_FS`
is what docker's overlay2 uses; tmpfs xattr/ACL for containers too.

## NVIDIA prerequisites

Why: closed/open nvidia modules have hard kernel deps, and we want a
framebuffer console before nvidia_drm takes over (simpledrm handoff).

- `MTRR`, `SYSVIPC`, `MMU_NOTIFIER`, `DRM`, `DRM_FBDEV_EMULATION`
- `DRM_SIMPLEDRM` + `SYSFB_SIMPLEFB` + `FRAMEBUFFER_CONSOLE` + `VT`
- `DRM_NOUVEAU` must NOT be set — conflicts with nvidia-drivers.
- `MODULE_SIG_FORCE` must NOT be set — nvidia modules are unsigned.

## KVM / VFIO

Why: libvirt/qemu with virtual networking, plus IOMMU groundwork so GPU
or USB passthrough stays possible without a rebuild. Hugepages help VM
memory. Cmdline carries `amd_iommu=on iommu=pt`.

## Containers

Why: the full docker/minikube requirement set — all namespace types,
cgroup v2 controllers, seccomp filtering, PSI for pressure metrics,
`CHECKPOINT_RESTORE` for CRIU-style tooling.

## Netfilter / networking

Why: docker (NAT, bridge netfilter, xt matches), kubernetes/minikube
(IPVS, ipset), BPF-based tooling (`BPF_SYSCALL`, `BPF_JIT`,
`NET_CLS_BPF`), and BBR + fq as the host congestion control (sysctl set
by 40-services.sh).

## Board

Why: exact hardware on the TUF B850-PLUS WIFI.

- `R8169` — RTL8125 2.5GbE, primary NIC.
- `RTW89` + `RTW89_8922AE` — Realtek 8922AE wifi (optional but built).
- `BT` + `BT_HCIBTUSB` + `BT_RTL` — Bluetooth side of the 8922AE,
  REQUIRED (BT is how peripherals connect).
- `USB4`, `USB_UAS`, `USB_XHCI_HCD`, HID, `TYPEC`/`UCSI` — board I/O.
- `SND_HDA_INTEL` + Realtek/HDMI codecs + `SND_USB_AUDIO` — onboard
  audio, TV audio over HDMI, USB DAC/headsets.

## Misc

- `WIREGUARD`, `TUN` — VPNs (tailscale, warp).
- `PACKET`, `USB_MON` — wireshark/nmap capture.
- `IKCONFIG_PROC` — running config at /proc/config.gz.
- CRC32C — required by xfs/btrfs/iscsi paths, keep accelerated.

## Deferred / optional (not in the fragment)

- `gentoo-sources` with the experimental USE flag + `MZEN5` processor
  family — later, once the box is proven stable on this config.
- `preempt=full` — runtime toggle via cmdline if desktop latency ever
  needs it; not a build-time decision.
- KVM AVIC — leave at default; revisit only for heavy VM interrupt load.

## Reference cmdline

PARTUUID, not UUID: with no initramfs there is no userspace to resolve a
filesystem UUID. `fbdev` is a `nvidia_drm` parameter and has to be
spelled out — a bare `fbdev=1` is not a kernel parameter at all.

```
root=PARTUUID=<gpt-partuuid> rw nvidia_drm.modeset=1 nvidia_drm.fbdev=1 amd_iommu=on iommu=pt amd_pstate=active
```

Lives in `/boot/refind_linux.conf`; the checked-in copy with this
machine's PARTUUID is `profiles/pc/refind_linux.conf`.

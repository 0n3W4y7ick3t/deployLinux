# pc kernel

Hardware targeted: AMD Ryzen 7 9800X3D (Zen5), NVIDIA RTX 5080, ASUS TUF
B850-PLUS WIFI (RTL8125 2.5GbE, Realtek 8922AE wifi/BT), NVMe, ext4 root
+ xfs data, EFI boot via rEFInd.

## Policy

**First boot runs the dist-kernel**: `sys-kernel/gentoo-kernel` +
`sys-kernel/linux-firmware`. Everything in `config-fragment` is enabled
out of the box there, so the machine is fully functional with zero
kernel work.

**Custom build later**, when wanted:

```
emerge sys-kernel/gentoo-sources
cd /usr/src/linux
make defconfig
scripts/kconfig/merge_config.sh -m .config /path/to/config-fragment
make olddefconfig
make -j16 && make modules_install install
```

Review `config-checklist.md` afterwards, especially the "must NOT be
set" nvidia notes.

## Upgrade flow

Dist-kernel: `emerge -u gentoo-kernel` does everything. Custom: copy the
old `.config` to the new source tree, `make olddefconfig`, skim the new
symbols, rebuild, keep the previous kernel entry in rEFInd until the new
one boots clean.

## Stability first

- EXPO stays only while MEMTEST86+ passes; drop to JEDEC on any weirdness.
- `amd_pstate=active` on the cmdline; EPP is pushed to `performance`
  through `/sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference`
  by `/etc/local.d/epp.start` (written by scripts/40-services.sh).
- BBR + fq sysctls live in `/etc/sysctl.d/90-bbr.conf` (same script).

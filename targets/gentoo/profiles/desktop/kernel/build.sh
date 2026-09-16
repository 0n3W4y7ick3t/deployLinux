#!/bin/sh
# Build and install the PC kernel from defconfig + config-fragment.
# Same script for the first build and for every upgrade afterwards.
#
# Usage: build.sh [--jobs N]
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=../../../../../common/lib.sh
. "$script_dir/../../../../../common/lib.sh"

require_root

jobs=$(nproc)
while [ $# -gt 0 ]; do
    case $1 in
    --jobs|-j)
        [ $# -ge 2 ] || die "$1 needs a value"
        jobs=$2
        shift 2
        ;;
    *) die "unknown argument: $1" ;;
    esac
done

fragment=$script_dir/config-fragment
[ -f "$fragment" ] || die "missing $fragment"

# eselect kernel points /usr/src/linux at the tree to build. Pick the
# newest gentoo-sources unless it already points somewhere.
command -v eselect >/dev/null 2>&1 || die "eselect not found"
if [ ! -e /usr/src/linux ]; then
    # highest entry is the newest source tree
    n=$(eselect kernel list | sed -nE 's/^[[:space:]]*\[([0-9]+)\].*/\1/p' | tail -1)
    [ -n "$n" ] || die "no kernel sources (emerge sys-kernel/gentoo-sources)"
    eselect kernel set "$n"
fi
src=$(readlink -f /usr/src/linux)
log "building $src with -j$jobs"

cd /usr/src/linux

# Regenerate from defconfig + fragment rather than carrying .config
# forward: the diff stays reviewable and symbols renamed upstream do not
# silently persist. /proc/config.gz (IKCONFIG_PROC) recovers a running
# config if one is ever needed.
make defconfig
scripts/kconfig/merge_config.sh -m .config "$fragment"
make olddefconfig

# A missing symbol here is an unbootable machine, not a build error.
for sym in CONFIG_XFS_FS CONFIG_EXT4_FS CONFIG_BLK_DEV_NVME \
           CONFIG_DEVTMPFS_MOUNT CONFIG_EFI_STUB CONFIG_MICROCODE; do
    grep -qx "$sym=y" .config || die "$sym is not builtin: root would not mount"
done
for sym in CONFIG_DRM_NOUVEAU CONFIG_MODULE_SIG_FORCE; do
    ! grep -qx "$sym=y" .config || die "$sym is set: breaks nvidia-drivers"
done
# select-only, so it silently stays unset if whatever pulls it in goes away
grep -qE '^CONFIG_DRM_TTM_HELPER=' .config ||
    die "CONFIG_DRM_TTM_HELPER unset: nvidia-drivers will refuse to build"
# NTFS is ntfs-3g/FUSE-only after ntfs3 blanked Windows C:'s $LogFile
# (0xED, 2026-08): FUSE must stay builtin, ntfs3 must stay gone.
grep -qx 'CONFIG_FUSE_FS=y' .config ||
    die "CONFIG_FUSE_FS is not builtin: every ntfs-3g mount would fail"
! grep -qE '^CONFIG_NTFS3_FS=[ym]' .config ||
    die "CONFIG_NTFS3_FS is set: banned after the 0xED incident"
for sym in CONFIG_LOGO CONFIG_LOGO_LINUX_CLUT224 CONFIG_FRAMEBUFFER_CONSOLE; do
    grep -qx "$sym=y" .config || die "$sym unset: no Tux at boot"
done
# libvirt's default network needs the nat chain type and a root htb qdisc;
# missing either one only shows up as a net-start failure
for sym in CONFIG_NFT_NAT CONFIG_NFT_REJECT CONFIG_NFT_MASQ \
           CONFIG_NET_SCH_HTB CONFIG_NET_SCH_SFQ \
           CONFIG_NET_CLS_U32 CONFIG_NET_CLS_FW \
           CONFIG_NET_ACT_CSUM CONFIG_NET_ACT_POLICE; do
    grep -qE "^$sym=[ym]" .config ||
        die "$sym unset: libvirt's default network will not start"
done
# docker publishes ports through iptables-nft, which needs the xt DNAT/SNAT
# targets to exist as a module. Missing -> `docker run -p` dies with
# "Extension DNAT revision 0 not supported" and the container ends up running
# with no network at all.
for sym in CONFIG_NETFILTER_XT_NAT CONFIG_NETFILTER_XT_TARGET_MASQUERADE; do
    grep -qE "^$sym=[ym]" .config ||
        die "$sym unset: docker cannot publish container ports"
done
log "config checks passed"

make "-j$jobs"
make modules_install
# installkernel writes the versioned /boot/vmlinuz-*
make install

# Out-of-tree modules (nvidia) go here, NOT in a postinst.d hook: inside
# `make install` the kernel's MAKEFLAGS/KBUILD_* leak into nvidia's nested
# build, and a failure there would abort the kernel install. Non-fatal —
# a bootable kernel with a stale nvidia.ko beats no kernel at all.
if ! emerge --quiet --jobs=1 @module-rebuild; then
    log "WARNING: @module-rebuild failed — the kernel is installed but"
    log "nvidia.ko is stale. Fix it before rebooting, or boot the .old entry."
fi

# Point rEFInd at the kernel just built. In here rather than a postinst.d
# hook for the same reason as the module rebuild above, and non-fatal for
# the same one too: booting the previous kernel is recoverable, a kernel
# install aborted halfway is not.
#
# Left to itself rEFInd boots the previously-booted OS, which right after a
# kernel upgrade is still the old kernel — the new one is reachable only by
# picking it by hand. default_selection cannot fix that on its own either:
# folding turns every kernel past the first into a sub-option, and a
# sub-option cannot be named as the default. So generate one explicit entry
# whose title never changes while the kernel it loads does, with the other
# kernels as sub-options under F2. refind.conf's default_selection names
# that title, and the menu keeps the single icon folding was there to give.
#
# dont_scan_files is written inside the generated block rather than checked
# into refind.conf, and that placement is the safety property: lose the
# block and auto-detection returns, so the worst case is an uglier menu
# rather than a machine with no Linux entry at all.
#
# The ESP is out of fstab on purpose (see the commented line there), so
# mount it only if needed and leave it as it was found.
esp_uuid=6641-7CF6
refind_begin='# BEGIN kernel-build-sh'
refind_end='# END kernel-build-sh'
refind_entry() {
    release=$(make -s kernelrelease)
    [ -n "$release" ] || return 1
    [ -f "/boot/vmlinuz-$release" ] || return 1

    # refind_linux.conf stays the single source of the cmdline; lift its
    # "Boot default" options verbatim so this entry boots byte-identically
    # to what the auto-detected one did.
    opts=$(sed -n 's/^"Boot default"[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' \
        /boot/refind_linux.conf 2>/dev/null)
    [ -n "$opts" ] || return 1

    mounted=0
    if ! mountpoint -q /boot/efi; then
        mount "UUID=$esp_uuid" /boot/efi || return 1
        mounted=1
    fi

    conf=/boot/efi/EFI/refind/refind.conf
    rc=0
    if [ -f "$conf" ]; then
        hide=''
        for k in /boot/vmlinuz-*; do
            [ -f "$k" ] || continue
            hide="${hide:+$hide,}${k##*/}"
        done

        # Follow the active theme's icon set, so this entry keeps the look of
        # the auto-detected one it replaces. A theme's icons_dir is relative
        # to EFI/refind; fall back to rEFInd's own icons if it has no gentoo.
        icon=/EFI/refind/icons/os_gentoo.png
        idir=$(sed -n 's|^[[:space:]]*icons_dir[[:space:]]\{1,\}||p' \
            /boot/efi/EFI/refind/themes/*/theme.conf 2>/dev/null | tail -1)
        if [ -n "$idir" ] && [ -f "/boot/efi/EFI/refind/$idir/os_gentoo.png" ]; then
            icon="/EFI/refind/$idir/os_gentoo.png"
        fi

        block=$(mktemp)
        {
            echo "$refind_begin"
            echo "dont_scan_files $hide"
            echo 'menuentry "Gentoo Linux" {'
            echo "    icon    $icon"
            echo '    volume  gentoo'
            echo "    loader  /boot/vmlinuz-$release"
            echo "    options \"$opts\""
            for k in /boot/vmlinuz-*; do
                [ -f "$k" ] || continue
                kb=${k##*/}
                [ "$kb" = "vmlinuz-$release" ] && continue
                echo "    submenuentry \"${kb#vmlinuz-}\" {"
                echo "        loader /boot/$kb"
                echo '    }'
            done
            echo '}'
            echo "$refind_end"
        } > "$block"

        sed -i "/^$refind_begin\$/,/^$refind_end\$/d" "$conf"
        printf '\n' >> "$conf"
        cat "$block" >> "$conf"
        rm -f "$block"
        log "refind entry -> vmlinuz-$release ($(echo "$hide" | tr ',' '\n' | wc -l) kernels)"
    else
        rc=1
    fi

    if [ "$mounted" = 1 ]; then
        umount /boot/efi || log "WARNING: ESP left mounted at /boot/efi"
    fi
    return "$rc"
}
# the || keeps set -e out of the function body, so a failure anywhere in it
# is reported rather than aborting a kernel that is already installed
refind_entry || log "WARNING: could not write the rEFInd entry — pick the new kernel by hand"

log "installed:"
ls -1 /boot/vmlinuz-* 2>/dev/null || log "WARNING: no /boot/vmlinuz-*, is sys-kernel/installkernel merged?"
log "build.sh done — check refind_linux.conf still names a kernel that exists"

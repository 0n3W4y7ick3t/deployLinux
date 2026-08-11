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

log "installed:"
ls -1 /boot/vmlinuz-* 2>/dev/null || log "WARNING: no /boot/vmlinuz-*, is sys-kernel/installkernel merged?"
log "build.sh done — check refind_linux.conf still names a kernel that exists"

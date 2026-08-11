#!/bin/sh
# Build the machine's kernel before anything that links against it.
# nvidia-drivers[modules] needs /usr/src/linux/Module.symvers, so the
# kernel cannot wait until after 20-world.sh merges it.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=../../../common/lib.sh
. "$script_dir/../../../common/lib.sh"

require_root
profile=${GENTOO_PROFILE:-}
[ -n "$profile" ] || die "GENTOO_PROFILE not set (run via provision.sh --profile <name>)"
profile_dir=$script_dir/../profiles/$profile
[ -f "$profile_dir/profile.conf" ] || die "unknown profile: $profile"

build=$profile_dir/kernel/build.sh
if [ ! -f "$build" ]; then
    log "profile $profile has no kernel/build.sh, skipping (build it by hand)"
    log "15-kernel done"
    exit 0
fi

# linux-firmware first: CONFIG_EXTRA_FIRMWARE links the microcode blob in
# at build time, so it has to be on disk before the kernel is built.
emerge --noreplace sys-kernel/gentoo-sources sys-kernel/installkernel \
    sys-kernel/linux-firmware

if [ -f /usr/src/linux/Module.symvers ] && [ "${KERNEL_REBUILD:-0}" != 1 ]; then
    log "kernel already built, skipping (KERNEL_REBUILD=1 to force)"
else
    sh "$build"
fi

log "15-kernel done"

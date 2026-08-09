#!/bin/sh
# QEMU/KVM + libvirt + virt-manager. Gated on WANT_VIRT=1 in the profile.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=../../../common/lib.sh
. "$script_dir/../../../common/lib.sh"

require_root
profile=${GENTOO_PROFILE:-}
[ -n "$profile" ] || die "GENTOO_PROFILE not set (run via provision.sh --profile <name>)"
profile_dir=$script_dir/../profiles/$profile
[ -f "$profile_dir/profile.conf" ] || die "unknown profile: $profile"
# shellcheck disable=SC1090,SC1091  # profile path is dynamic by design
. "$profile_dir/profile.conf"

if [ "${WANT_VIRT:-0}" != 1 ]; then
    log "WANT_VIRT != 1 for profile $profile, skipping"
    exit 0
fi

# USE flags come from portage/package.use/virt
emerge --noreplace app-emulation/qemu app-emulation/libvirt app-emulation/virt-manager

if rc-update show default 2>/dev/null | awk '{print $1}' | grep -qx libvirtd; then
    log "libvirtd already in default runlevel"
else
    rc-update add libvirtd default
fi

# needs a running libvirtd; skipped inside the install chroot
if rc-service libvirtd status >/dev/null 2>&1; then
    virsh net-autostart default || true
    virsh net-start default 2>/dev/null || true
else
    log "libvirtd not running, run later: virsh net-autostart default"
fi

log "reminder: usermod -aG libvirt <user>"
log "50-virt done"

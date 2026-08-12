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
    # autostart only takes effect at the next libvirtd start, so an install
    # that set it after libvirtd came up leaves the net inactive and every
    # virt-install dies with "network 'default' is not active".
    if virsh net-info default 2>/dev/null | grep -q '^Active: *no'; then
        virsh net-start default || log "WARNING: could not start the default network"
    fi
else
    log "libvirtd not running, run later: virsh net-autostart default && virsh net-start default"
fi

# groups only apply to new logins, so this needs a re-login to take effect
virt_user=${VIRT_USER:-${SUDO_USER:-}}
if [ -n "$virt_user" ]; then
    for g in libvirt kvm; do
        getent group "$g" >/dev/null 2>&1 || continue
        if id -nG "$virt_user" | tr ' ' '\n' | grep -qx "$g"; then
            log "$virt_user already in $g"
        else
            usermod -aG "$g" "$virt_user" && log "added $virt_user to $g"
        fi
    done
else
    log "no VIRT_USER/SUDO_USER, skipping group setup (usermod -aG libvirt,kvm <user>)"
fi

log "50-virt done"

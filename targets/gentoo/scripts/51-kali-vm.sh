#!/bin/sh
# OPT-IN: download the official Kali qemu image and import it as a VM.
# Multi-GB download — asks for confirmation first. Needs WANT_VIRT=1.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=../../../common/lib.sh
. "$script_dir/../../../common/lib.sh"

require_root
profile=${GENTOO_PROFILE:-}
[ -n "$profile" ] || die "GENTOO_PROFILE not set (export it or run via provision.sh)"
profile_dir=$script_dir/../profiles/$profile
[ -f "$profile_dir/profile.conf" ] || die "unknown profile: $profile"
# shellcheck disable=SC1090,SC1091  # profile path is dynamic by design
. "$profile_dir/profile.conf"

[ "${WANT_VIRT:-0}" = 1 ] || die "WANT_VIRT != 1 for profile $profile (run 50-virt.sh on a virt-enabled profile first)"

if virsh dominfo kali >/dev/null 2>&1; then
    log "VM 'kali' already exists, nothing to do"
    exit 0
fi

command -v 7z >/dev/null 2>&1 || die "7z not found (emerge app-arch/7zip)"
command -v virt-install >/dev/null 2>&1 || die "virt-install not found (run 50-virt.sh first)"

printf 'This downloads a multi-GB Kali image. Continue? [y/N] '
read -r answer
case $answer in
[yY]*) ;;
*) log "aborted"; exit 0 ;;
esac

base=https://cdimage.kali.org/current
work=/var/lib/libvirt/images/kali
mkdir -p "$work"
cd "$work"

curl -fsSL "$base/SHA256SUMS" -o SHA256SUMS
# discover the exact qemu image name from the checksum list
line=$(grep -E 'kali-linux-[^ ]*qemu-amd64\.7z$' SHA256SUMS | head -n1)
[ -n "$line" ] || die "no qemu-amd64 image found in SHA256SUMS"
sum=${line%% *}
name=$(printf '%s\n' "$line" | awk '{print $NF}')
log "image: $name"

fetch_verify "$base/$name" "$work/$name" "$sum"

qcow2=$(find "$work" -name '*.qcow2' | head -n1)
if [ -z "$qcow2" ]; then
    7z x -y "$name"
    qcow2=$(find "$work" -name '*.qcow2' | head -n1)
fi
[ -n "$qcow2" ] || die "no qcow2 found after extraction"

# virt-install dies with "network 'default' is not active" otherwise, after
# the whole multi-GB download has already succeeded
if virsh net-info default 2>/dev/null | grep -q '^Active: *no'; then
    log "starting the inactive default network"
    virsh net-start default || die "could not start the default network"
fi

virt-install --name kali --import \
    --disk "$qcow2" \
    --memory "${KALI_MEM:-16384}" --vcpus "${KALI_VCPUS:-8}" \
    --os-variant debiantesting \
    --network default --graphics spice \
    --noautoconsole

log "51-kali-vm done: virsh start kali"

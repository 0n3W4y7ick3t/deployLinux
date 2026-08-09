#!/bin/sh
# Bind-mount pseudo filesystems into a Gentoo root and chroot in.
# Usage: ch_gentoo.sh [root]   (default /mnt/gentoo)
# Safe to re-run: already-mounted paths are skipped.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=../../common/lib.sh
. "$script_dir/../../common/lib.sh"

require_root

root=${1:-/mnt/gentoo}
[ -d "$root/etc" ] || die "$root does not look like a system root"

cp --dereference /etc/resolv.conf "$root/etc/"

mountpoint -q "$root/proc" || mount -t proc /proc "$root/proc"
for d in sys dev run; do
    if ! mountpoint -q "$root/$d"; then
        mount --rbind "/$d" "$root/$d"
        mount --make-rslave "$root/$d"
    fi
done

log "entering chroot, remember to run: source /etc/profile"
exec chroot "$root" /bin/bash

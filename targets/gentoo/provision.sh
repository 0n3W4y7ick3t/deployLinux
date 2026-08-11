#!/bin/sh
# Provision a Gentoo machine from a machine profile (inside the chroot or
# on the installed system). Each numbered script is idempotent, so
# re-running after a failure is fine. 51-kali-vm.sh is opt-in and skipped.
#
# Usage: provision.sh --profile <name> [--hostname <name>]
#   --profile/-p   machine profile, a directory under profiles/
#   --hostname/-H  write <name> to /etc/conf.d/hostname
#                  (default: keep the current hostname)
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=../../common/lib.sh
. "$script_dir/../../common/lib.sh"
# shellcheck source=../../common/detect.sh
. "$script_dir/../../common/detect.sh"

require_root

profile=''
new_hostname=''
while [ $# -gt 0 ]; do
    case $1 in
    --profile|-p)
        [ $# -ge 2 ] || die "$1 needs a value"
        profile=$2
        shift 2
        ;;
    --hostname|-H)
        [ $# -ge 2 ] || die "$1 needs a value"
        new_hostname=$2
        shift 2
        ;;
    *)
        die "unknown argument: $1"
        ;;
    esac
done

[ -n "$profile" ] || die "usage: provision.sh --profile <name> [--hostname <name>] (profiles: see profiles/)"
profile_dir=$script_dir/profiles/$profile
[ -f "$profile_dir/profile.conf" ] || die "unknown profile: $profile (no $profile_dir/profile.conf)"
# shellcheck disable=SC1090,SC1091  # profile path is dynamic by design
. "$profile_dir/profile.conf"

# sanity check only, never fail: hardware might be mid-upgrade
gpu=$(detect_gpu)
chassis=$(detect_chassis)
[ "${EXPECT_GPU:-}" = "$gpu" ] || log "WARNING: profile $profile expects gpu=${EXPECT_GPU:-?}, detected: $gpu"
[ "${EXPECT_CHASSIS:-}" = "$chassis" ] || log "WARNING: profile $profile expects chassis=${EXPECT_CHASSIS:-?}, detected: $chassis"

if [ -n "$new_hostname" ]; then
    if grep -qx "hostname=\"$new_hostname\"" /etc/conf.d/hostname 2>/dev/null; then
        log "hostname already $new_hostname"
    else
        printf 'hostname="%s"\n' "$new_hostname" > /etc/conf.d/hostname
        log "hostname set to $new_hostname (applies on reboot)"
    fi
else
    log "keeping current hostname: $(hostname)"
fi

export GENTOO_PROFILE="$profile"
for s in 10-portage 15-kernel 20-world 30-gpu 40-services 50-virt 70-ollama; do
    log "=== running $s.sh (profile $profile) ==="
    sh "$script_dir/scripts/$s.sh"
done

log "provisioning done. optional: GENTOO_PROFILE=$profile scripts/51-kali-vm.sh (big download)"

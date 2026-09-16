#!/bin/sh
# Update the system and merge the base world plus the profile's extras.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=../../../common/lib.sh
. "$script_dir/../../../common/lib.sh"

require_root
profile=${GENTOO_PROFILE:-}
[ -n "$profile" ] || die "GENTOO_PROFILE not set (run via provision.sh --profile <name>)"
profile_dir=$script_dir/../profiles/$profile
[ -f "$profile_dir/profile.conf" ] || die "unknown profile: $profile"

# Fresh-stage3 cycle: pillow[truetype] -> harfbuzz[glib] -> glib ->
# docutils -> pillow. Cut it once; the --newuse pass below restores truetype.
if ! portageq has_version / dev-python/pillow; then
    log "breaking the pillow/harfbuzz/glib cycle (one-shot pillow[-truetype])"
    USE="-truetype" emerge --oneshot --quiet dev-python/pillow
fi

emerge -uDN @world

# base world + profile extras: --noreplace records atoms without
# re-merging installed ones. dev-lang/rust-bin is listed on purpose —
# never build rust from source here.
{
    grep -Ev '^[[:space:]]*(#|$)' "$script_dir/../world"
    grep -Ev '^[[:space:]]*(#|$)' "$profile_dir/world-extra"
} | xargs emerge --noreplace

# hyprland desktop stack (set installed by 10-portage.sh)
emerge --noreplace @hyprland

# wireshark's dumpcap is root:pcap 0750 with the capture caps, so a normal
# user needs the group — the kernel carries PACKET/USB_MON for exactly this.
# The group only exists once wireshark is merged, hence the getent gate.
cap_user=${VIRT_USER:-${SUDO_USER:-}}
if [ -n "$cap_user" ] && getent group pcap >/dev/null 2>&1; then
    if id -nG "$cap_user" | tr ' ' '\n' | grep -qx pcap; then
        log "$cap_user already in pcap"
    else
        usermod -aG pcap "$cap_user" && log "added $cap_user to pcap"
    fi
else
    log "no user or no pcap group, skipping (usermod -aG pcap <user>)"
fi

log "20-world done"

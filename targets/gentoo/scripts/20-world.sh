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

log "20-world done"

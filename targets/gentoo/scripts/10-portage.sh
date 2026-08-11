#!/bin/sh
# Install the repo portage config into /etc/portage and enable overlays.
# make.conf = shared fragment + the profile's machine head.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=../../../common/lib.sh
. "$script_dir/../../../common/lib.sh"

require_root
profile=${GENTOO_PROFILE:-}
[ -n "$profile" ] || die "GENTOO_PROFILE not set (run via provision.sh --profile <name>)"
profile_dir=$script_dir/../profiles/$profile
[ -f "$profile_dir/profile.conf" ] || die "unknown profile: $profile"

portage_src=$script_dir/../portage

# shared comes first so the head can append to FEATURES
cat "$portage_src/make.conf.shared" "$profile_dir/make.conf.head" > /etc/portage/make.conf
log "wrote /etc/portage/make.conf (shared + $profile head)"

for d in package.use package.accept_keywords package.env env sets; do
    mkdir -p "/etc/portage/$d"
    cp -f "$portage_src/$d/"* "/etc/portage/$d/"
done
# profile overrides land after the shared files (CPU flags are per-machine)
if [ -d "$profile_dir/package.use" ]; then
    cp -f "$profile_dir/package.use/"* /etc/portage/package.use/
fi
log "copied package.use, package.accept_keywords, package.env, env, sets"

# make sure the main tree exists before emerging anything
[ -d /var/db/repos/gentoo ] || emerge-webrsync

if ! command -v eselect >/dev/null 2>&1 || ! eselect repository help >/dev/null 2>&1; then
    emerge --noreplace app-eselect/eselect-repository
fi
for repo in hyproverlay guru; do
    if [ -d "/var/db/repos/$repo" ]; then
        log "overlay $repo already enabled"
    else
        eselect repository enable "$repo"
    fi
done
# Re-running provision.sh after a failure should not re-sync: the tree is
# minutes old and rsync.gentoo.org asks for at most one sync a day.
# SYNC=1 forces it.
stamp=/var/db/repos/gentoo/metadata/timestamp.chk
if [ "${SYNC:-0}" != 1 ] && [ -f "$stamp" ] &&
    [ "$(find "$stamp" -mmin -1440 2>/dev/null)" ]; then
    log "tree synced less than a day ago, skipping (SYNC=1 to force)"
else
    emaint sync -a
fi

log "10-portage done"

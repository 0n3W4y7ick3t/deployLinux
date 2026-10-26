#!/bin/sh
# Rootless Docker: the daemon runs as the login user (rootlesskit + dockerd)
# from the docker-rootless OpenRC service; the rootful docker service goes.
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

rc_add() {
    # rc_add <service> <runlevel>
    if rc-update show "$2" 2>/dev/null | awk '{print $1}' | grep -qx "$1"; then
        log "service $1 already in $2"
    else
        rc-update add "$1" "$2"
    fi
}

docker_user=${VIRT_USER:-${SUDO_USER:-}}
if [ -z "$docker_user" ] || ! id "$docker_user" >/dev/null 2>&1; then
    log "no VIRT_USER/SUDO_USER (or the user does not exist yet): nobody to own the daemon, skipping"
    log "  after useradd, rerun: GENTOO_PROFILE=$profile sh $script_dir/45-docker.sh"
    exit 0
fi

# rootlesskit runs the daemon in a user namespace, slirp4netns gives it a network
emerge --noreplace sys-apps/rootlesskit app-containers/slirp4netns

# subordinate ids, the same range on every machine: container uid N is host
# 100000+N-1, so bind-mounted data and restic snapshots mean the same everywhere
grep -q "^$docker_user:" /etc/subuid || usermod --add-subuids 100000-165535 "$docker_user"
grep -q "^$docker_user:" /etc/subgid || usermod --add-subgids 100000-165535 "$docker_user"

# linger: elogind then mounts /run/user/UID at its own start and never removes
# it at logout. The file is what elogind reads at start; loginctl applies it now.
install -d -m 755 /var/lib/elogind/linger
if [ ! -e "/var/lib/elogind/linger/$docker_user" ]; then
    : > "/var/lib/elogind/linger/$docker_user"
    log "linger enabled for $docker_user"
fi
loginctl enable-linger "$docker_user" 2>/dev/null || log "elogind not running (chroot?), linger applies at boot"

# the service: the init script as is, the conf.d with this user filled in (local edits to the
# conf.d do not survive a re-run, the repo is the source). Remembered when either changed: a
# restart takes every container of the user down, so it only happens for a reason.
service_changed=0
conf_tmp=$(mktemp)
sed "s/^DOCKER_ROOTLESS_USER=.*/DOCKER_ROOTLESS_USER=\"$docker_user\"/" \
    "$script_dir/../conf.d/docker-rootless" > "$conf_tmp"
if ! cmp -s "$script_dir/../init.d/docker-rootless" /etc/init.d/docker-rootless; then
    install -m 755 "$script_dir/../init.d/docker-rootless" /etc/init.d/docker-rootless
    service_changed=1
    log "installed /etc/init.d/docker-rootless"
fi
if ! cmp -s "$conf_tmp" /etc/conf.d/docker-rootless; then
    install -m 644 "$conf_tmp" /etc/conf.d/docker-rootless
    service_changed=1
    log "installed /etc/conf.d/docker-rootless (user $docker_user)"
fi
rm -f "$conf_tmp"

# the rootful daemon goes: out of the runlevel, stopped, and the docker group
# with it, so a docker call without DOCKER_HOST fails instead of reaching root
for svc in docker containerd; do
    if rc-update show default 2>/dev/null | awk '{print $1}' | grep -qx "$svc"; then
        rc-update del "$svc" default
    fi
done
# containerd is its own service, `need`ed by docker, and keeps running as root
# after docker stops
for svc in docker containerd; do
    if rc-service "$svc" status >/dev/null 2>&1; then
        rc-service "$svc" stop
    fi
done
if id -nG "$docker_user" | tr ' ' '\n' | grep -qx docker; then
    gpasswd -d "$docker_user" docker && log "removed $docker_user from docker (needs a re-login)"
fi

rc_add docker-rootless default
if ! rc-service elogind status >/dev/null 2>&1; then
    log "docker-rootless not started (chroot?), starts on boot"
elif [ "$service_changed" -eq 1 ]; then
    rc-service docker-rootless restart ||
        log "docker-rootless did not start, see /var/log/docker-rootless.log"
else
    # a no-op while it runs
    rc-service docker-rootless start ||
        log "docker-rootless did not start, see /var/log/docker-rootless.log"
fi

log "45-docker done"

#!/bin/sh
# Binhost role from the profile: server serves /var/cache/binpkgs over
# HTTP, client points portage at the PC's binhost, none skips.
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

binhost_server() {
    # buildpkg is written into make.conf via the server profile's head
    grep -q buildpkg /etc/portage/make.conf || die "FEATURES buildpkg missing, run 10-portage.sh first"

    emerge --noreplace www-servers/nginx

    mkdir -p /etc/nginx/conf.d
    cat > /etc/nginx/conf.d/binhost.conf <<'EOF'
server {
    listen 80;
    server_name _;

    location /binhost/ {
        alias /var/cache/binpkgs/;
        autoindex on;
    }
}
EOF
    # Gentoo's stock nginx.conf has no conf.d include, add one into the http block
    if ! grep -q 'conf\.d/\*\.conf' /etc/nginx/nginx.conf; then
        sed -i '/^http {/a \\tinclude /etc/nginx/conf.d/*.conf;' /etc/nginx/nginx.conf
        log "added conf.d include to nginx.conf"
    fi
    log "wrote /etc/nginx/conf.d/binhost.conf"

    if rc-update show default 2>/dev/null | awk '{print $1}' | grep -qx nginx; then
        log "nginx already in default runlevel"
    else
        rc-update add nginx default
    fi

    # laptop-extra set: packages built only for other machines (10-portage
    # copies it, guard for standalone runs)
    if [ ! -f /etc/portage/sets/laptop-extra ]; then
        mkdir -p /etc/portage/sets
        cp "$script_dir/../portage/sets/laptop-extra" /etc/portage/sets/laptop-extra
    fi

    cat > /etc/cron.weekly/binhost-build <<'EOF'
#!/bin/sh
# weekly binhost refresh: sync, rebuild world, build laptop-only packages,
# then fix the binpkg index
emerge --sync -q && emerge -uDN --buildpkg @world && emerge --buildpkg @laptop-extra 2>/dev/null; emaint binhost --fix
EOF
    chmod +x /etc/cron.weekly/binhost-build
    log "wrote /etc/cron.weekly/binhost-build"

    log "binhost server ready: packages at http://<this-host>/binhost/"
}

binhost_client() {
    mc=/etc/portage/make.conf
    [ -f "$mc" ] || die "$mc not found"

    # one-time backup of the pre-binhost make.conf
    if [ ! -f "$mc.pre-binhost" ]; then
        cp -a "$mc" "$mc.pre-binhost"
        log "backed up $mc to $mc.pre-binhost"
    fi

    # enable getbinpkg by appending to whatever FEATURES already holds
    # (already present when make.conf came from 10-portage.sh + client head)
    if grep -q 'getbinpkg' "$mc"; then
        log "FEATURES getbinpkg already set"
    else
        # shellcheck disable=SC2016  # ${FEATURES} must stay literal for make.conf
        printf '\n# use binary packages from the PC binhost\nFEATURES="${FEATURES} getbinpkg"\n' >> "$mc"
        log "added getbinpkg to FEATURES"
    fi

    # -march=native -> -march=znver4 to match the PC builder (safety net for
    # a make.conf that predates the shared fragment; on Zen4 native == znver4
    # so nothing is force-rebuilt, packages converge as updates come in)
    if grep -q -- '-march=native' "$mc"; then
        sed -i 's/-march=native/-march=znver4/' "$mc"
        log "COMMON_FLAGS: -march=native -> -march=znver4"
    fi

    binrepos=/etc/portage/binrepos.conf
    if [ -f "$binrepos" ] && grep -q 'pc-binhost' "$binrepos"; then
        log "$binrepos already configured"
    else
        cat > "$binrepos" <<'EOF'
# Replace sync-uri host with the PC's actual Tailscale MagicDNS name
# (or its LAN hostname/IP).
[pc-binhost]
priority = 10
sync-uri = http://pc.tail-example.ts.net/binhost
EOF
        log "wrote $binrepos"
    fi

    log "binhost client ready. verify with: emerge -pv --getbinpkg @world"
}

case ${BINHOST_ROLE:-none} in
server) binhost_server ;;
client) binhost_client ;;
*) log "BINHOST_ROLE=${BINHOST_ROLE:-none} for profile $profile, skipping" ;;
esac

log "60-binhost done"

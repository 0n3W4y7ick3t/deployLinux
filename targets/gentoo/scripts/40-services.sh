#!/bin/sh
# OpenRC services, sysctls, keyd, and chassis-dependent tuning.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=../../../common/lib.sh
. "$script_dir/../../../common/lib.sh"
# shellcheck source=../../../common/detect.sh
. "$script_dir/../../../common/detect.sh"

require_root
profile=${GENTOO_PROFILE:-}
[ -n "$profile" ] || die "GENTOO_PROFILE not set (run via provision.sh --profile <name>)"
profile_dir=$script_dir/../profiles/$profile
[ -f "$profile_dir/profile.conf" ] || die "unknown profile: $profile"
# shellcheck disable=SC1090,SC1091  # profile path is dynamic by design
. "$profile_dir/profile.conf"

chassis=$(detect_chassis)

rc_add() {
    # rc_add <service> <runlevel>
    if rc-update show "$2" 2>/dev/null | awk '{print $1}' | grep -qx "$1"; then
        log "service $1 already in $2"
    else
        rc-update add "$1" "$2"
    fi
}

rc_add elogind boot
rc_add dbus default
# dhcpcd everywhere, ethernet is the default path
rc_add dhcpcd default
rc_add bluetooth default
rc_add docker default
if [ "${WANT_VIRT:-0}" = 1 ]; then
    rc_add libvirtd default
fi
if [ "$chassis" = laptop ]; then
    # wifi userland (iwd comes from the laptop world-extra)
    rc_add iwd default
fi

# shared keyd remap: caps/esc swap (keyd package comes from the @hyprland set)
mkdir -p /etc/keyd
cp -f "$script_dir/../../../common/keyd-default.conf" /etc/keyd/default.conf
rc_add keyd default
rc-service keyd status >/dev/null 2>&1 || rc-service keyd start 2>/dev/null || log "keyd not started (chroot?), starts on boot"
log "installed /etc/keyd/default.conf"

cat > /etc/sysctl.d/90-bbr.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
log "wrote /etc/sysctl.d/90-bbr.conf"

# desktop only: pin EPP to performance (a laptop wants the default for battery)
if [ "$chassis" = desktop ]; then
    cat > /etc/local.d/epp.start <<'EOF'
#!/bin/sh
for f in /sys/devices/system/cpu/cpufreq/policy*/energy_performance_preference; do
    [ -w "$f" ] && echo performance > "$f"
done
EOF
    chmod +x /etc/local.d/epp.start
    log "wrote /etc/local.d/epp.start"
fi

# weekly TRIM (needs a cron daemon; alternatively run fstrim from local.d)
cat > /etc/cron.weekly/fstrim <<'EOF'
#!/bin/sh
fstrim -a
EOF
chmod +x /etc/cron.weekly/fstrim
log "wrote /etc/cron.weekly/fstrim"

log "40-services done"

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
# default, not boot: upstream only wants boot when zram backs $TMPDIR
rc_add zram-init default
rc_add dbus default
# dhcpcd everywhere, ethernet is the default path
rc_add dhcpcd default
rc_add bluetooth default
rc_add docker default
# init script is `tailscale`, not `tailscaled`
rc_add tailscale default
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

# uinput for ydotool (@hyprland set): kernel-level input injection. The rule
# opens /dev/uinput to the input group; users get input at useradd (runbook).
mkdir -p /etc/udev/rules.d
cp -f "$script_dir/../../../common/80-uinput.rules" /etc/udev/rules.d/80-uinput.rules
{ udevadm control --reload && udevadm trigger /dev/uinput; } 2>/dev/null ||
    log "udev reload skipped (chroot?), applies on boot"
log "installed /etc/udev/rules.d/80-uinput.rules"

# backslashes are pre-doubled in common/issue so agetty prints them
cp -f "$script_dir/../../../common/issue" /etc/issue
log "installed /etc/issue"

# fcitx5 needs XMODIFIERS, but rice's shell/profile already exports it and
# Hyprland inherits that (it is exec'd from the login shell on tty1), so
# setting it here too would just be a second place to keep in sync.

# Default editor/browser for every account including root. env.d, not a shell
# rc: env-update writes /etc/profile.env, which /etc/profile and
# /etc/zsh/zprofile both source, so it applies whatever the login shell is.
mkdir -p /etc/env.d
cp -f "$script_dir/../../../common/env.d/99local" /etc/env.d/99local
env-update >/dev/null 2>&1 || log "env-update failed (chroot?), runs on next boot"
log "installed /etc/env.d/99local (EDITOR/VISUAL=nvim, BROWSER=google-chrome-stable)"

# root logs in with zsh like the user does. Ship a minimal rc with it so the
# zsh-newuser-install wizard does not ambush the first root login.
if command -v zsh >/dev/null 2>&1; then
    cp -f "$script_dir/../../../common/root-zshrc" /root/.zshrc
    root_shell=$(getent passwd root | cut -d: -f7)
    if [ "$root_shell" = /bin/zsh ]; then
        log "root shell already zsh"
    else
        chsh -s /bin/zsh root && log "root shell -> /bin/zsh (was $root_shell)"
    fi
else
    log "zsh not installed, leaving root shell alone"
fi

# zram swap at ~1/3 of RAM; no machine in the fleet has a swap partition
zram_mb=$(awk '/^MemTotal:/ { printf "%d", $2 / 1024 / 3 }' /proc/meminfo)
cat > /etc/conf.d/zram-init <<EOF
num_devices=1
type0=swap
size0=$zram_mb
algo0=zstd
labl0=zram_swap
flag0=
EOF
log "wrote /etc/conf.d/zram-init (${zram_mb}M zstd swap)"

cat > /etc/sysctl.d/90-bbr.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
log "wrote /etc/sysctl.d/90-bbr.conf"

# sshd, tailnet-only. Twin of the block in targets/arch/bootstrap.sh; the
# drop-in and sysctl come from common/lib.sh so the two cannot drift. When
# the helper finds no tailscale IP it returns 1 and sshd stays untouched.
if install_sshd_tailnet; then
    sysctl -p /etc/sysctl.d/91-ssh-tailnet.conf >/dev/null 2>&1 || log "sysctl not applied (chroot?), applies on boot"
    rc_add sshd default
    # restart, not start: picks up a changed drop-in on re-runs too
    rc-service sshd restart >/dev/null 2>&1 || log "sshd not started (chroot?), starts on boot"
    log "sshd enabled, tailnet only"
fi

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

# weekly TRIM. cronie provides the daemon and /etc/cron.weekly — neither
# exists in a stage3, so this used to write into a directory that was not
# there and the job never ran even once created.
rc_add cronie default
mkdir -p /etc/cron.weekly
cat > /etc/cron.weekly/fstrim <<'EOF'
#!/bin/sh
fstrim -a
EOF
chmod +x /etc/cron.weekly/fstrim
log "wrote /etc/cron.weekly/fstrim"

# weekly portage tree sync, Sunday 21:30. A cron.d file rather than
# cron.weekly so the time is explicit (cron.weekly runs whenever cronie's
# run-parts fires). Quiet, appended to its own log; emerge --sync needs root
# because /var/db/repos/gentoo is portage:portage 755.
mkdir -p /etc/cron.d
cat > /etc/cron.d/emerge-sync <<'EOF'
SHELL=/bin/sh
PATH=/sbin:/bin:/usr/sbin:/usr/bin
30 21 * * 0 root emerge --sync -q >> /var/log/emerge-sync.log 2>&1
EOF
chmod 644 /etc/cron.d/emerge-sync
log "wrote /etc/cron.d/emerge-sync"

# user crontabs. cronie DOES ship /var/spool/cron/crontabs, but its parent
# was left drwxr-x--- root:cron here, and /usr/bin/crontab is setgid
# **crontab** (not cron) — so it cannot traverse into its own spool. Every
# crontab call then dies with "'/var/spool/cron/crontabs' is not a directory",
# including `crontab -l`, which points at the wrong thing entirely: the
# directory exists, the path to it is unreadable. Note the two groups really
# are different (cron=16 owns the daemon's dirs, crontab=460 the setgid bit).
chown root:root /var/spool/cron
chmod 755 /var/spool/cron
install -d -o root -g crontab -m 1730 /var/spool/cron/crontabs
log "ensured /var/spool/cron/crontabs (root:crontab 1730)"

# NTFS policy: ntfs-3g (FUSE) only. The in-kernel ntfs3 driver rw-mounted
# Windows C: and left its $LogFile unreplayable -> UNMOUNTABLE_BOOT_VOLUME
# 0xED (2026-08). The pc kernel no longer builds the module; this ban covers
# any machine or kernel that still ships it.
mkdir -p /etc/modprobe.d
cat > /etc/modprobe.d/ntfs3.conf <<'EOF'
# The in-kernel ntfs3 driver is banned: its rw mounts left Windows C:'s
# $LogFile unreplayable -> UNMOUNTABLE_BOOT_VOLUME 0xED (2026-08).
# ntfs-3g (FUSE) handles all NTFS; install/bin/false defeats even an
# explicit `mount -t ntfs3` or a udisks automount.
blacklist ntfs3
install ntfs3 /bin/false
EOF
log "wrote /etc/modprobe.d/ntfs3.conf (in-kernel ntfs3 banned)"

log "40-services done"

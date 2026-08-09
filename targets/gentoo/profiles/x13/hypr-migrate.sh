#!/bin/sh
# Migrate the X13 from dwm/X11 to Hyprland/wayland. One-time script.
# Run as root ON THE LAPTOP, after the binhost client role is set up
# (provision.sh --profile x13, or scripts/60-binhost.sh). Safe to re-run.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=../../../../common/lib.sh
. "$script_dir/../../../../common/lib.sh"

require_root

mc=/etc/portage/make.conf

# USE: -wayland -> wayland
if grep -q -- '-wayland' "$mc"; then
    sed -i 's/-wayland\b/wayland/' "$mc"
    log "USE: replaced -wayland with wayland"
elif grep -qw 'wayland' "$mc"; then
    log "USE already has wayland"
else
    log "WARNING: no wayland token in $mc USE, add it manually"
fi

# overlays for hyprland + guru tools
if ! command -v eselect >/dev/null 2>&1 || ! eselect repository help >/dev/null 2>&1; then
    emerge --noreplace app-eselect/eselect-repository
fi
for repo in hyproverlay guru; do
    if [ -d "/var/db/repos/$repo" ]; then
        log "overlay $repo already enabled"
    else
        eselect repository enable "$repo"
        emaint sync -r "$repo"
    fi
done

# install the wayland stack set and its USE flags, then emerge it
mkdir -p /etc/portage/sets /etc/portage/package.use
cp "$script_dir/../../portage/sets/hyprland" /etc/portage/sets/hyprland
cp "$script_dir/../../portage/package.use/desktop" /etc/portage/package.use/desktop
cp "$script_dir/../../portage/package.use/media" /etc/portage/package.use/media
emerge -uN @hyprland

# hyprland runs on elogind + dbus
rc-update show boot | grep -qw elogind || rc-update add elogind boot
rc-update show default | grep -qw dbus || rc-update add dbus default

log "emerge done. manual steps below."

cat <<'EOF'
1. Pull user configs (rice main now carries the hypr configs):
     yadm pull && yadm alt

2. Drop X-only leaves from world (review, then run):
EOF

# only deselect atoms actually present in the world file
world=/var/lib/portage/world
deselect=''
for atom in \
    x11-base/xorg-server x11-apps/xinit x11-misc/picom x11-misc/i3lock \
    x11-misc/xcape x11-misc/unclutter-xfixes media-gfx/feh x11-misc/arandr \
    x11-misc/clipmenu media-gfx/ueberzug media-gfx/maim x11-misc/slop \
    x11-misc/xdotool x11-misc/xclip x11-apps/xrandr x11-apps/xrdb \
    x11-apps/xbacklight app-i18n/ibus media-sound/bluez-alsa; do
    grep -qx "$atom" "$world" && deselect="$deselect $atom"
done
if [ -n "$deselect" ]; then
    printf '     emerge --deselect%s\n' "$deselect"
    printf '     emerge --ask --depclean\n'
else
    printf '     (none of the X-only atoms are in world, nothing to deselect)\n'
fi

cat <<'EOF'

3. Stale $HOME leftovers to remove:
     ~/.config/x11 ~/.xprofile ~/.config/picom ~/.config/xmodmap

4. Bluetooth audio now goes through pipewire[bluetooth] instead of
   bluez-alsa, no extra daemon needed.
EOF

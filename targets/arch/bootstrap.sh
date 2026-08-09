#!/bin/sh
# Generic Arch Linux deploy for both machines (PC and X13 laptop).
# Post-install: assumes a working base Arch system. Detects the hardware
# and installs/enables accordingly. Run as root, safe to re-run.
#
# Usage: bootstrap.sh [--hostname <name>] [--pc]
#   --hostname/-H  set the hostname (default: keep current)
#   --pc           force PC-class extras (auto-enabled on desktop chassis)
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=../../common/lib.sh
. "$script_dir/../../common/lib.sh"
# shellcheck source=../../common/detect.sh
. "$script_dir/../../common/detect.sh"

require_root
command -v pacman >/dev/null 2>&1 || die "pacman not found, is this Arch?"

new_hostname=''
force_pc=0
while [ $# -gt 0 ]; do
    case $1 in
    --hostname | -H)
        [ $# -ge 2 ] || die "$1 needs a value"
        new_hostname=$2
        shift 2
        ;;
    --pc)
        force_pc=1
        shift
        ;;
    *)
        die "unknown argument: $1"
        ;;
    esac
done

# strip comments/blanks from a package list file
pkgs() {
    grep -Ev '^[[:space:]]*(#|$)' "$script_dir/$1"
}

# ---- detect ----
gpu=$(detect_gpu)
cpu=$(detect_cpu_vendor)
chassis=$(detect_chassis)
bt=$(detect_bluetooth)
log "detected: gpu=$gpu cpu=$cpu chassis=$chassis bluetooth=$bt"

is_pc=$force_pc
[ "$chassis" = desktop ] && is_pc=1
is_laptop=0
[ "$chassis" = laptop ] && is_laptop=1

extra_pkgs=''
case $gpu in
nvidia) extra_pkgs="nvidia-open-dkms nvidia-utils linux-headers" ;;
amd) extra_pkgs="mesa vulkan-radeon libva-mesa-driver" ;;
*) log "gpu unknown, installing plain mesa"; extra_pkgs="mesa" ;;
esac
case $cpu in
amd) extra_pkgs="$extra_pkgs amd-ucode" ;;
intel) extra_pkgs="$extra_pkgs intel-ucode" ;;
esac

# ---- install ----
log "system update + core and desktop sets"
{
    pkgs pkgs-core.txt
    pkgs pkgs-desktop.txt
    printf '%s\n' "$extra_pkgs" | tr ' ' '\n'
    [ "$is_laptop" -eq 1 ] && pkgs pkgs-laptop.txt
    [ "$is_pc" -eq 1 ] && pkgs pkgs-pc.txt
    true
} | xargs pacman -Syu --needed --noconfirm

if [ "$gpu" = nvidia ]; then
    cat > /etc/modprobe.d/nvidia.conf <<'EOF'
options nvidia_drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF
    log "wrote /etc/modprobe.d/nvidia.conf"
fi

# shared keyd remap: caps/esc swap
mkdir -p /etc/keyd
cp -f "$script_dir/../../common/keyd-default.conf" /etc/keyd/default.conf
log "installed /etc/keyd/default.conf"

# ---- services ----
systemctl enable NetworkManager.service   # iwd alternative: see README
systemctl enable --now keyd.service 2>/dev/null || systemctl enable keyd.service
[ "$bt" = yes ] && systemctl enable bluetooth.service
[ "$is_laptop" -eq 1 ] && systemctl enable tlp.service
if [ "$is_pc" -eq 1 ]; then
    systemctl enable docker.service libvirtd.service tailscaled.service
    log "after first start, run: virsh net-autostart default"
fi

# ---- hostname ----
if [ -n "$new_hostname" ]; then
    if [ "$(hostname)" = "$new_hostname" ]; then
        log "hostname already $new_hostname"
    else
        hostnamectl set-hostname "$new_hostname"
        log "hostname set to $new_hostname"
    fi
else
    log "keeping current hostname: $(hostname)"
fi

# ---- handoff ----
yadm_class=x13
[ "$is_pc" -eq 1 ] && yadm_class=pc
log "done. AUR packages and dotfiles are piloted as your user:"
cat <<EOF
  yay -S --needed - < $script_dir/pkgs-aur.txt   # skip if no yay
  yadm clone git@github.com:0n3W4y7ick3t/rice
  yadm config local.class $yadm_class
  yadm alt
  yadm bootstrap
EOF

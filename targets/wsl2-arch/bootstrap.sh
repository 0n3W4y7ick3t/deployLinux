#!/bin/sh
# WSL2 Arch bootstrap: CLI-only packages, yay, then yadm hints.
# Safe to re-run.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=../../common/lib.sh
. "$script_dir/../../common/lib.sh"

command -v pacman >/dev/null 2>&1 || die "pacman not found, is this Arch?"

log "syncing packages from pkg.txt"
# shellcheck disable=SC2024  # input redirect, file is world-readable
sudo pacman -Syu --needed --noconfirm - < "$script_dir/pkg.txt"

if ! command -v yay >/dev/null 2>&1; then
    if [ "$(id -u)" = "0" ]; then
        # makepkg refuses to run as root
        log "skipping yay install: re-run this block as a regular user"
    else
        log "installing yay from AUR"
        tmp=$(mktemp -d)
        git clone https://aur.archlinux.org/yay.git "$tmp/yay"
        (cd "$tmp/yay" && makepkg -si --noconfirm)
        rm -rf "$tmp"
    fi
fi

command -v yadm >/dev/null 2>&1 || die "yadm missing after package sync"

log "done. dotfiles are piloted manually, run:"
cat <<'EOF'
  yadm clone git@github.com:0n3W4y7ick3t/rice
  yadm config local.class wsl
  yadm alt
  yadm bootstrap
EOF

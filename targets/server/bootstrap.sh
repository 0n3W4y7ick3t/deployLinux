#!/bin/sh
# Terminal-only bootstrap for homelab servers.
# Installs the core CLI set with whatever package manager is present,
# then prints the yadm server-class setup. Safe to re-run.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=../../common/lib.sh
. "$script_dir/../../common/lib.sh"

pm=$(detect_pm) || die "no supported package manager found (pacman/apt/emerge)"
log "using package manager: $pm"

case $pm in
pacman)
    sudo pacman -S --needed --noconfirm \
        zsh neovim tmux git fzf ripgrep fd lf bat curl yadm
    ;;
apt)
    # Debian/Ubuntu name the binaries fdfind and batcat; the rice repo
    # aliases them back to fd/bat.
    sudo apt update
    sudo apt install -y \
        zsh neovim tmux git fzf ripgrep fd-find bat curl yadm
    # lf is missing from older releases, do not fail the whole run on it
    sudo apt install -y lf || log "lf not packaged here, grab a release binary from github.com/gokcehan/lf"
    ;;
emerge)
    sudo emerge --noreplace \
        app-shells/zsh app-editors/neovim app-misc/tmux dev-vcs/git \
        app-shells/fzf sys-apps/ripgrep sys-apps/fd \
        sys-apps/bat net-misc/curl app-admin/yadm
    # lf is GURU-only now, do not fail the run if the overlay is missing
    sudo emerge --noreplace app-misc/lf \
        || log "app-misc/lf needs the GURU overlay (eselect repository enable guru)"
    ;;
esac

log "done. dotfiles (user layer) are piloted manually, run:"
cat <<'EOF'
  yadm clone git@github.com:0n3W4y7ick3t/rice
  yadm config local.class server
  yadm gitconfig core.sparseCheckout true
  cp ~/.config/yadm/sparse-checkout.server "$(yadm rev-parse --git-dir)/info/sparse-checkout"
  yadm checkout ~
  yadm alt
  yadm bootstrap
EOF

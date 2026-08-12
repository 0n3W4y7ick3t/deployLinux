#!/bin/sh
# Install the vendored FiraCode Nerd Font and its fontconfig alias.
#
# The fonts live in this repo rather than portage: they are fontfreeze-patched
# (see common/fonts/firacode-nerd/README.md) and no ebuild ships that variant.
# Nothing installed them before, so on a fresh machine waybar, wmenu-run and
# kitty all silently fell back to Liberation Sans — legible, but with wrong
# metrics and no Nerd Font glyphs at all.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=../../../common/lib.sh
. "$script_dir/../../../common/lib.sh"

require_root

src=$script_dir/../../../common/fonts/firacode-nerd
dest=/usr/share/fonts/firacode-nerd

[ -d "$src" ] || die "missing $src"

mkdir -p "$dest"
# Strip the _freeze suffix from the filename; the family name inside the font
# is "FiraCode Nerd Font Freeze" either way, and local.conf aliases it.
for f in "$src"/*_freeze.ttf; do
    [ -e "$f" ] || die "no *_freeze.ttf in $src"
    base=$(basename "$f" _freeze.ttf)
    install -m 0644 "$f" "$dest/$base.ttf"
done
log "installed $(find "$dest" -name '*.ttf' | wc -l) fonts to $dest"

install -m 0644 "$script_dir/../../../common/fonts/local.conf" /etc/fonts/local.conf
log "installed /etc/fonts/local.conf (FiraCode Nerd Font -> ...Freeze alias)"

fc-cache -f >/dev/null 2>&1 || log "fc-cache failed (chroot?), runs again on boot"

# Cheap guard: the alias is the whole point, so fail loudly if it does not
# resolve rather than leaving a desktop that looks subtly wrong.
if command -v fc-match >/dev/null 2>&1; then
    got=$(fc-match -f '%{family}' "FiraCode Nerd Font" 2>/dev/null || echo '')
    case $got in
    *FiraCode*) log "fc-match ok: FiraCode Nerd Font -> $got" ;;
    '') log "WARNING: fc-match produced nothing" ;;
    *) log "WARNING: FiraCode Nerd Font still resolves to '$got'" ;;
    esac
fi

log "25-fonts done"

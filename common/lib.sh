#!/bin/sh
# Shared helpers. Source from scripts, do not execute:
#   . "$script_dir/../../common/lib.sh"
# Deliberately init-system agnostic: no service helpers here.

log() {
    printf '>>> %s\n' "$*"
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die "must run as root"
}

# Print the first known package manager found in PATH.
detect_pm() {
    for _pm in pacman apt emerge; do
        if command -v "$_pm" >/dev/null 2>&1; then
            printf '%s\n' "$_pm"
            return 0
        fi
    done
    return 1
}

# fetch_verify <url> <dest> <sha256>
# Skips the download when dest already matches the checksum.
fetch_verify() {
    _url=$1
    _dest=$2
    _sum=$3
    if [ -f "$_dest" ] && printf '%s  %s\n' "$_sum" "$_dest" | sha256sum -c - >/dev/null 2>&1; then
        log "$_dest already present and verified"
        return 0
    fi
    curl -fL -o "$_dest" "$_url"
    printf '%s  %s\n' "$_sum" "$_dest" | sha256sum -c - || die "checksum mismatch: $_dest"
}

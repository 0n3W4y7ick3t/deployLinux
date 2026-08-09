#!/bin/sh
# Hardware detection helpers, POSIX sh.
# Source it for the functions, or run directly for a summary:
#   sh common/detect.sh --report

# prints nvidia|amd|intel|unknown
detect_gpu() {
    if command -v lspci >/dev/null 2>&1; then
        case $(lspci -d ::0300 2>/dev/null || true) in
        *NVIDIA*) printf 'nvidia\n'; return 0 ;;
        *AMD* | *ATI*) printf 'amd\n'; return 0 ;;
        *Intel*) printf 'intel\n'; return 0 ;;
        esac
    fi
    # fallback when lspci is absent: PCI vendor ids via drm
    for _v in /sys/class/drm/card[0-9]*/device/vendor; do
        [ -r "$_v" ] || continue
        case $(cat "$_v") in
        0x10de) printf 'nvidia\n'; return 0 ;;
        0x1002) printf 'amd\n'; return 0 ;;
        0x8086) printf 'intel\n'; return 0 ;;
        esac
    done
    printf 'unknown\n'
}

# prints amd|intel|unknown
detect_cpu_vendor() {
    if grep -q AuthenticAMD /proc/cpuinfo 2>/dev/null; then
        printf 'amd\n'
    elif grep -q GenuineIntel /proc/cpuinfo 2>/dev/null; then
        printf 'intel\n'
    else
        printf 'unknown\n'
    fi
}

# prints laptop|desktop|unknown (SMBIOS chassis type)
detect_chassis() {
    case $(cat /sys/class/dmi/id/chassis_type 2>/dev/null || echo 0) in
    8 | 9 | 10 | 14 | 31) printf 'laptop\n' ;;  # portable/laptop/notebook/sub-notebook/convertible
    3 | 4 | 5 | 6 | 7) printf 'desktop\n' ;;
    *) printf 'unknown\n' ;;
    esac
}

# prints yes|no
detect_bluetooth() {
    if [ -n "$(ls -A /sys/class/bluetooth 2>/dev/null)" ]; then
        printf 'yes\n'
    elif { lsusb 2>/dev/null; lspci 2>/dev/null; } | grep -qi bluetooth; then
        printf 'yes\n'
    else
        printf 'no\n'
    fi
}

# prints yes|no
detect_wifi() {
    for _w in /sys/class/net/*/wireless; do
        if [ -d "$_w" ]; then
            printf 'yes\n'
            return 0
        fi
    done
    if command -v iw >/dev/null 2>&1 && [ -n "$(iw dev 2>/dev/null)" ]; then
        printf 'yes\n'
        return 0
    fi
    printf 'no\n'
}

# CLI mode only when executed as detect.sh, never when sourced
case ${0##*/} in
detect.sh)
    case ${1:-} in
    --report)
        printf 'gpu:        %s\n' "$(detect_gpu)"
        printf 'cpu vendor: %s\n' "$(detect_cpu_vendor)"
        printf 'chassis:    %s\n' "$(detect_chassis)"
        printf 'bluetooth:  %s\n' "$(detect_bluetooth)"
        printf 'wifi:       %s\n' "$(detect_wifi)"
        ;;
    *)
        printf 'usage: sh %s --report\n' "$0" >&2
        exit 2
        ;;
    esac
    ;;
esac

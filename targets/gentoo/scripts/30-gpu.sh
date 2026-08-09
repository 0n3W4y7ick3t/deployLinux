#!/bin/sh
# GPU driver setup, driven by detection: NVIDIA needs the proprietary
# driver + module options, amdgpu is all in-kernel + mesa (nothing to do).
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=../../../common/lib.sh
. "$script_dir/../../../common/lib.sh"
# shellcheck source=../../../common/detect.sh
. "$script_dir/../../../common/detect.sh"

require_root

gpu=$(detect_gpu)
if [ "$gpu" != nvidia ]; then
    log "gpu=$gpu: no driver work needed (amdgpu/mesa come from world + VIDEO_CARDS)"
    log "30-gpu done"
    exit 0
fi

# USE (modules kernel-open dist-kernel) comes from portage/package.use/nvidia
emerge --noreplace x11-drivers/nvidia-drivers

cat > /etc/modprobe.d/nvidia.conf <<'EOF'
# modeset+fbdev: proper KMS handoff for wayland; PreserveVideoMemoryAllocations:
# required for reliable suspend/resume on wayland compositors
options nvidia_drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF
log "wrote /etc/modprobe.d/nvidia.conf"

log "reminder: rEFInd options line needs nvidia_drm.modeset=1 (see runbook)"
log "reminder: usermod -aG video <user>"
log "30-gpu done"

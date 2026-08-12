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

# USE (modules kernel-open -dist-kernel) comes from portage/package.use/nvidia
emerge --noreplace x11-drivers/nvidia-drivers

cat > /etc/modprobe.d/nvidia.conf <<'EOF'
# modeset+fbdev: proper KMS handoff for wayland; PreserveVideoMemoryAllocations:
# required for reliable suspend/resume on wayland compositors
options nvidia_drm modeset=1 fbdev=1
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF
log "wrote /etc/modprobe.d/nvidia.conf"

# Reminder only. This used to run `emerge @module-rebuild` directly, which
# broke twice over: make(1) exports MAKEFLAGS/KBUILD_* into the hook, so
# nvidia's nested build went looking for /Kbuild and died — and because
# the hook's exit status is `make install`'s, a failed module rebuild
# aborted the kernel installation itself. kernel/build.sh does the rebuild
# afterwards instead, where neither applies.
mkdir -p /etc/kernel/postinst.d
cat > /etc/kernel/postinst.d/90-nvidia-modules <<'EOF'
#!/bin/sh
# Do not emerge from here: this runs inside `make install`, whose
# environment breaks nested builds and whose exit status this becomes.
echo ">>> kernel installed — run 'emerge @module-rebuild' for nvidia.ko"
echo ">>> (profiles/desktop/kernel/build.sh already does this for you)"
exit 0
EOF
chmod +x /etc/kernel/postinst.d/90-nvidia-modules
log "wrote /etc/kernel/postinst.d/90-nvidia-modules"

log "reminder: rEFInd options line needs nvidia_drm.modeset=1 (see runbook)"
log "reminder: usermod -aG video <user>"
log "30-gpu done"

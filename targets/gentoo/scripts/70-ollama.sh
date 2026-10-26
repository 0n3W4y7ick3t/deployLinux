#!/bin/sh
# Ollama in docker with NVIDIA GPU access, on the user's rootless daemon
# (45-docker.sh). Gated on WANT_OLLAMA=1.
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=../../../common/lib.sh
. "$script_dir/../../../common/lib.sh"

require_root
profile=${GENTOO_PROFILE:-}
[ -n "$profile" ] || die "GENTOO_PROFILE not set (run via provision.sh --profile <name>)"
profile_dir=$script_dir/../profiles/$profile
[ -f "$profile_dir/profile.conf" ] || die "unknown profile: $profile"
# shellcheck disable=SC1090,SC1091  # profile path is dynamic by design
. "$profile_dir/profile.conf"

if [ "${WANT_OLLAMA:-0}" != 1 ]; then
    log "WANT_OLLAMA != 1 for profile $profile, skipping"
    exit 0
fi

emerge --noreplace app-containers/docker app-containers/docker-cli \
    app-containers/docker-compose app-containers/nvidia-container-toolkit

ollama_user=${VIRT_USER:-${SUDO_USER:-}}

# Three rootless facts, all host-wide (they also end GPU access for a rootful
# daemon, retired by 45-docker.sh). The prestart hook must not write
# device-cgroup rules it cannot own inside the user namespace. Its own NVML
# init must not switch to root:video either: the video gid is not mapped in
# that namespace and the switch ends in "nvml error: insufficient permissions";
# root:root, the daemon user itself, works. No runtime entry is needed:
# `gpus: all` is a device request that dockerd resolves through
# nvidia-container-runtime-hook on its PATH.
if command -v nvidia-ctk >/dev/null 2>&1; then
    # set -e: a failure here must not abort the whole provision run
    if ! nvidia-ctk config --set nvidia-container-cli.no-cgroups --set nvidia-container-cli.user=root:root --in-place; then
        log "nvidia-ctk failed, rerun after boot: nvidia-ctk config --set nvidia-container-cli.no-cgroups --set nvidia-container-cli.user=root:root --in-place"
    fi
else
    log "nvidia-ctk absent, rerun after boot: nvidia-ctk config --set nvidia-container-cli.no-cgroups --set nvidia-container-cli.user=root:root --in-place"
fi

# The driver's own modprobe config makes the GPU nodes root:video 0660. A
# container process never has the video gid (its gids are the daemon user's
# and the subuid range), so no container could open them. The override hands
# the nodes to that user's own group: container root is the user, and on this
# single-user machine the group is the same person video used to mean. Sorted
# after nvidia.conf, the last assignment wins; applies at the next module load.
if [ -n "$ollama_user" ]; then
    mkdir -p /etc/modprobe.d
    cat > /etc/modprobe.d/zz-nvidia-rootless.conf <<EOF
# deployLinux 70-ollama.sh: the GPU nodes belong to the rootless docker user's
# group instead of video, so container root (= that user) can open them.
options nvidia NVreg_DeviceFileGID=$(id -g "$ollama_user")
EOF
    log "wrote /etc/modprobe.d/zz-nvidia-rootless.conf (GPU nodes -> group of $ollama_user, next module load)"
else
    log "no VIRT_USER/SUDO_USER: /etc/modprobe.d/zz-nvidia-rootless.conf not written, GPU containers stay locked out"
fi

mkdir -p /opt/ollama
cat > /opt/ollama/docker-compose.yml <<'EOF'
services:
  ollama:
    image: ollama/ollama
    # without this compose names it ollama-ollama-1 and `docker exec
    # ollama` below cannot find it
    container_name: ollama
    restart: unless-stopped
    gpus: all
    ports:
      - "11434:11434"
    volumes:
      - ollama:/root/.ollama

volumes:
  ollama:
EOF
log "wrote /opt/ollama/docker-compose.yml"

# The daemon is the user's, so compose runs as that user against its socket.
# Skipped inside the install chroot, where nothing is running. /opt/ollama is
# root's and only has to be readable: compose writes nothing there.
if [ -n "$ollama_user" ] && rc-service docker-rootless status >/dev/null 2>&1; then
    ollama_uid=$(id -u "$ollama_user")
    ollama_home=$(getent passwd "$ollama_user" | cut -d: -f6)
    runuser -u "$ollama_user" -- env HOME="$ollama_home" \
        DOCKER_HOST="unix:///run/user/$ollama_uid/docker.sock" \
        docker compose -f /opt/ollama/docker-compose.yml up -d
    runuser -u "$ollama_user" -- env HOME="$ollama_home" \
        DOCKER_HOST="unix:///run/user/$ollama_uid/docker.sock" \
        docker exec ollama ollama --version || log "ollama still starting, check later: docker exec ollama ollama --version"
else
    log "docker-rootless not running, after first boot run as ${ollama_user:-your user}:"
    log "  docker compose -f /opt/ollama/docker-compose.yml up -d"
    log "  docker exec ollama ollama --version"
fi

log "70-ollama done"

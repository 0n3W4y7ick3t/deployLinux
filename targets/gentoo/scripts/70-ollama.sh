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

# Rootless: the prestart hook must not write device-cgroup rules it cannot own
# inside the user namespace, or every `--gpus` container fails to start. The
# setting is host-wide (it also ends GPU access for a rootful daemon, retired
# by 45-docker.sh). No runtime entry is needed: `gpus: all` is a device request
# that dockerd resolves through nvidia-container-runtime-hook on its PATH.
if command -v nvidia-ctk >/dev/null 2>&1; then
    # set -e: a failure here must not abort the whole provision run
    nvidia-ctk config --set nvidia-container-cli.no-cgroups --in-place ||
        log "nvidia-ctk failed, rerun after boot: nvidia-ctk config --set nvidia-container-cli.no-cgroups --in-place"
else
    log "nvidia-ctk absent, rerun after boot: nvidia-ctk config --set nvidia-container-cli.no-cgroups --in-place"
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
ollama_user=${VIRT_USER:-${SUDO_USER:-}}
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

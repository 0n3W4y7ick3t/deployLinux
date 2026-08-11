#!/bin/sh
# Ollama in docker with NVIDIA GPU access. Gated on WANT_OLLAMA=1.
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

if command -v nvidia-ctk >/dev/null 2>&1; then
    # set -e: a failure here must not abort the whole provision run
    nvidia-ctk runtime configure --runtime=docker || log "nvidia-ctk failed, rerun after boot"
else
    log "nvidia-ctk absent, rerun after boot: nvidia-ctk runtime configure --runtime=docker"
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

# pick up the runtime change; skipped inside the install chroot
if rc-service docker status >/dev/null 2>&1; then
    rc-service docker restart
    docker compose -f /opt/ollama/docker-compose.yml up -d
    docker exec ollama ollama --version
else
    log "docker not running, after first boot run:"
    log "  docker compose -f /opt/ollama/docker-compose.yml up -d"
    log "  docker exec ollama ollama --version"
fi

log "70-ollama done"

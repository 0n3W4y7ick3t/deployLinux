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

nvidia-ctk runtime configure --runtime=docker

mkdir -p /opt/ollama
cat > /opt/ollama/docker-compose.yml <<'EOF'
services:
  ollama:
    image: ollama/ollama
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

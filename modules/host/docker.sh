#!/usr/bin/env bash
# =============================================================================
# modules/host/docker.sh — Docker CE Installation
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

install_docker() {
  section "Docker Engine"
  if ! command -v docker &>/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
      | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
      docker-buildx-plugin docker-compose-plugin
    usermod -aG docker "$REAL_USER"
    log "Docker CE installed."
  else
    log "Docker present: $(docker --version)"
  fi

  if [[ ! -f /etc/docker/daemon.json ]]; then
    cat > /etc/docker/daemon.json <<DAEMON
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
DAEMON
    systemctl reload docker 2>/dev/null || true
    log "Docker daemon log rotation configured."
  fi

  ! docker compose version &>/dev/null && apt-get install -y -qq docker-compose-plugin
  systemctl enable --now docker
  log "Docker Compose: $(docker compose version)"
}

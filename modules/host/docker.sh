#!/usr/bin/env bash
# =============================================================================
# modules/host/docker.sh — Docker CE Installation
#
# LIVE AUTHORITY (P0-G): carries the monolith's exact Docker Engine logic,
# extracted verbatim from actools.sh. Sourced by actools.sh, driven by the
# `host` install stage (installer/dispatch.sh::actools::install::stage_host).
# Preserves the install-if guard, the always-ensure-docker-group step (run on
# every invocation, not only on fresh install) with its .bashrc group-activation
# heredoc, the daemon.json log-rotation config, and REAL_USER for `usermod`.
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
    log "Docker CE installed."
  else
    log "Docker present: $(docker --version)"
  fi
  # Always ensure REAL_USER is in docker group
  if ! id -nG "$REAL_USER" 2>/dev/null | grep -qw docker; then
    usermod -aG docker "$REAL_USER"
    log "$REAL_USER added to docker group."
    # Write docker group activation to .bashrc so every new session picks it up
    local bashrc="/home/${REAL_USER}/.bashrc"
    if [[ -f "$bashrc" ]] && ! grep -q "actools docker group" "$bashrc" 2>/dev/null; then
      cat >> "$bashrc" << 'BASHRC'

# actools docker group — activate docker group without re-login
if id -nG "$USER" 2>/dev/null | grep -qw docker && ! id -nG 2>/dev/null | grep -qw docker; then
  exec sg docker -c "bash --login"
fi
BASHRC
      log "Docker group activation added to ${bashrc}"
    fi
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

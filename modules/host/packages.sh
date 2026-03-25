#!/usr/bin/env bash
# =============================================================================
# modules/host/packages.sh — System Package Installation
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

install_packages() {
  section "System Packages"
  mkdir -p /var/lib/actools
  if [[ ! -f "$PKG_DONE_FLAG" ]]; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
    apt-get install -y -qq \
      curl git unzip zip jq ca-certificates gnupg lsb-release \
      ufw fail2ban rclone dnsutils logrotate
    touch "$PKG_DONE_FLAG"
    log "Packages installed."
  else
    log "Packages already installed -- skipping upgrade."
  fi
}

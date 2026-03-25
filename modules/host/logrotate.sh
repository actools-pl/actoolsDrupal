#!/usr/bin/env bash
# =============================================================================
# modules/host/logrotate.sh — Host Log Rotation
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

configure_logrotate() {
  cat > /etc/logrotate.d/actools <<LOGROTATE
${INSTALL_DIR}/logs/*/*.log
${INSTALL_DIR}/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
LOGROTATE
  log "Host log rotation configured."
}

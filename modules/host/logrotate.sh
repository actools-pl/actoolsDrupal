#!/usr/bin/env bash
# =============================================================================
# modules/host/logrotate.sh — Host Log Rotation
#
# LIVE AUTHORITY (P0-G): carries the monolith's exact host log-rotation logic,
# extracted verbatim from actools.sh. Sourced by actools.sh, driven by the
# `host` install stage (installer/dispatch.sh::actools::install::stage_host).
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

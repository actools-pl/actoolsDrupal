#!/usr/bin/env bash
# =============================================================================
# modules/host/firewall.sh — UFW + Fail2ban
#
# LIVE AUTHORITY (P0-G): carries the monolith's exact Firewall logic (UFW +
# fail2ban), extracted verbatim from actools.sh. Sourced by actools.sh, driven
# by the `host` install stage (installer/dispatch.sh::actools::install::stage_host).
# =============================================================================

configure_firewall() {
  section "Firewall"
  ufw limit 22/tcp  comment 'SSH rate-limited'  2>/dev/null || true
  ufw allow 80/tcp  comment 'HTTP Caddy ACME'   2>/dev/null || true
  ufw allow 443/tcp comment 'HTTPS'             2>/dev/null || true
  ufw allow 443/udp comment 'HTTP/3 QUIC'       2>/dev/null || true
  ufw --force enable
  systemctl enable --now fail2ban
  log "UFW + fail2ban active."
}

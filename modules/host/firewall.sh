#!/usr/bin/env bash
# =============================================================================
# modules/host/firewall.sh — UFW + Fail2ban
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
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

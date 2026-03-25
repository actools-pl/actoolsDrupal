#!/usr/bin/env bash
# =============================================================================
# modules/preflight/dns.sh — DNS Resolution Checks
# =============================================================================

check_dns() {
  section "DNS Check"
  for subdomain in "${BASE_DOMAIN}" "stg.${BASE_DOMAIN}" "dev.${BASE_DOMAIN}"; do
    getent hosts "$subdomain" >/dev/null 2>&1 \
      && log "DNS OK -- ${subdomain}" \
      || warn "DNS MISSING -- ${subdomain}. Let's Encrypt will fail until DNS propagates."
  done
}

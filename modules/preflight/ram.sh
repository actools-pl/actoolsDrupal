#!/usr/bin/env bash
# =============================================================================
# modules/preflight/ram.sh — RAM Check + Parallel Install Guard
# =============================================================================

check_ram() {
  section "RAM Check"
  TOTAL_RAM=$(free -m | awk '/Mem:/ {print $2}')
  log "Total RAM: ${TOTAL_RAM}MB"

  if [[ "${PARALLEL_INSTALL:-false}" == "true" ]] && (( TOTAL_RAM < 6000 )); then
    warn "Only ${TOTAL_RAM}MB RAM -- forcing sequential install (need 6GB+ for parallel)."
    PARALLEL_INSTALL=false
  fi

  (( TOTAL_RAM < 1024 )) && warn "Less than 1GB RAM -- install may fail on low-memory server."
}

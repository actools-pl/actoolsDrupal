#!/usr/bin/env bash
# =============================================================================
# modules/host/swap.sh — Swap File Configuration
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

configure_swap() {
  section "Swap Configuration"
  if [[ "${ENABLE_SWAP:-true}" == "true" ]]; then
    if ! swapon --show | grep -q '/'; then
      SWAP="${SWAP_SIZE:-4G}"
      log "Creating ${SWAP} swap file..."
      fallocate -l "$SWAP" /swapfile && chmod 600 /swapfile
      mkswap /swapfile && swapon /swapfile
      grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
      log "Swap active: ${SWAP}."
    else
      log "Swap already configured -- skipping."
    fi
  else
    warn "Swap disabled. XeLaTeX in worker container may OOM on large papers."
  fi
}

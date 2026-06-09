#!/usr/bin/env bash
# =============================================================================
# modules/host/swap.sh — Swap File Configuration
#
# LIVE AUTHORITY (P0-G): carries the monolith's exact Swap Configuration logic,
# extracted verbatim from actools.sh. Sourced by actools.sh, driven by the
# `host` install stage (installer/dispatch.sh::actools::install::stage_host).
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

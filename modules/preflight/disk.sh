#!/usr/bin/env bash
# =============================================================================
# modules/preflight/disk.sh — Disk Space Checks
# =============================================================================

check_disk() {
  section "Disk Check"
  AVAILABLE_KB=$(df / | awk 'NR==2 {print $4}')
  (( AVAILABLE_KB < 20971520 )) && \
    error "Only $(( AVAILABLE_KB / 1048576 ))GB free. At least 20GB required."
  log "Disk OK -- $(( AVAILABLE_KB / 1048576 ))GB free."

  DISK_USE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
  (( DISK_USE > 80 )) && warn "Disk ${DISK_USE}% full -- risk of failure during install."
}

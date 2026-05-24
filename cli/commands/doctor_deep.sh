#!/usr/bin/env bash
# =============================================================================
# cli/commands/doctor_deep.sh — Pro-gated deep doctor.
#
# Mirrors the gate pattern of modules/audit/audit.sh (audit --deep).
# This file ships in the community installer but exits with a Pro-required
# message. The actual deep-mode implementation lives in Actools Pro
# (€49/month).
#
# Exit code 2 — matches `actools audit --deep` for CI parity.
# =============================================================================

run_doctor_deep() {
  # shellcheck source=/dev/null
  source "${INSTALL_DIR}/installer/output.sh" 2>/dev/null || true

  echo
  printf '%bactools doctor --deep requires Actools Pro (€49/month)%b\n' \
    "${_COL_FAIL:-}" "${_COL_NC:-}"
  echo "  → https://actools.feesix.com/pro"
  echo
  echo "Free 'actools doctor' covers daily operational health:"
  echo "  site, TLS, containers, database, Redis, disk, backups,"
  echo "  restore-test recency, Drupal bootstrap."
  echo
  echo "Pro 'doctor --deep' adds:"
  echo "  - 30-day performance trend regression"
  echo "  - Configuration drift vs install baseline"
  echo "  - Disk, cert, and backup-volume forecasting"
  echo "  - Anomaly detection on slow.log and FPM access patterns"
  echo
  return 2
}

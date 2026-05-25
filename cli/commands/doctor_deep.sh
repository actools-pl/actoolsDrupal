#!/usr/bin/env bash
# =============================================================================
# cli/commands/doctor_deep.sh — Pro-gated deep doctor.
#
# Mirrors the gate pattern of modules/audit/audit.sh (audit --deep).
# This file ships in the community installer and exits with an
# "in development" message. The deep-mode implementation is not
# available in this edition.
#
# Exit code 2 — matches `actools audit --deep` for CI parity.
# =============================================================================

run_doctor_deep() {
  # shellcheck source=/dev/null
  source "${INSTALL_DIR}/installer/output.sh" 2>/dev/null || true

  echo
  printf '%bactools doctor --deep is not available in this edition.%b\n' \
    "${_COL_FAIL:-}" "${_COL_NC:-}"
  echo "  Deep mode is in development."
  echo
  echo "Free 'actools doctor' covers daily operational health:"
  echo "  site, TLS, containers, database, Redis, disk, backups,"
  echo "  restore-test recency, Drupal bootstrap."
  echo
  echo "Deep mode (in development) will add:"
  echo "  - 30-day performance trend regression"
  echo "  - Configuration drift vs install baseline"
  echo "  - Disk, cert, and backup-volume forecasting"
  echo "  - Anomaly detection on slow.log and FPM access patterns"
  echo
  return 2
}

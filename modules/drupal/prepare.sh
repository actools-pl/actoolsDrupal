#!/usr/bin/env bash
# =============================================================================
# modules/drupal/prepare.sh — Stage 1: Database + Filesystem
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

drupal_prepare() {
  local env="$1"
  local db_name="actools_${env}"

  section "Stage 1: Prepare — ${env}"

  wait_db
  create_db_and_user "$env"

  mkdir -p "${INSTALL_DIR}/docroot/${env}"
  mkdir -p "${INSTALL_DIR}/logs/php_${env}"

  # Pre-create DB log dir with correct ownership for MariaDB (UID 999)
  chown -R 999:999 "${INSTALL_DIR}/logs/db" 2>/dev/null || true
  touch "${INSTALL_DIR}/logs/db/slow.log" 2>/dev/null || true
  chown 999:999 "${INSTALL_DIR}/logs/db/slow.log" 2>/dev/null || true
  chmod 664 "${INSTALL_DIR}/logs/db/slow.log" 2>/dev/null || true

  log "Stage 1 complete: database and filesystem ready for ${env}."
}

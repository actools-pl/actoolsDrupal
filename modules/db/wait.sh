#!/usr/bin/env bash
# =============================================================================
# modules/db/wait.sh — MariaDB Write-Check
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

wait_db() {
  cd "$INSTALL_DIR" || exit
  log "Waiting for MariaDB (write-check)..."
  local _wp="${DB_ROOT_PASS}"
  local _tries=0
  until docker compose exec -T db mariadb -uroot -p"${_wp}" \
    -e "CREATE TABLE IF NOT EXISTS mysql.actools_write_check (id INT); DROP TABLE IF EXISTS mysql.actools_write_check;" \
    &>/dev/null 2>&1; do
    _tries=$(( _tries + 1 ))
    [[ $_tries -ge 50 ]] && error "MariaDB did not become ready within 150s."
    sleep 3
  done
  log "MariaDB ready."
}

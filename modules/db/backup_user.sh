#!/usr/bin/env bash
# =============================================================================
# modules/db/backup_user.sh — Backup DB User Setup
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

setup_backup_db_user() {
  local backup_pass="$1"
  wait_db
  docker compose exec -T db mariadb -uroot -p"${DB_ROOT_PASS}" <<SQL
CREATE USER IF NOT EXISTS 'backup'@'%' IDENTIFIED BY '${backup_pass}';
GRANT SELECT, LOCK TABLES, SHOW VIEW ON *.* TO 'backup'@'%';
FLUSH PRIVILEGES;
SQL
  log "DB backup user created."
}

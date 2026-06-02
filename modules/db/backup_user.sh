#!/usr/bin/env bash
# =============================================================================
# modules/db/backup_user.sh — Backup DB User Setup
# Extracted from actools.sh v9.2 during Phase 1 modular refactor
# =============================================================================

# Run a root mariadb command inside the db container with no password on the host argv.
# The container already holds MARIADB_ROOT_PASSWORD; we expose it to the client as MYSQL_PWD
# *inside* the container. Caller passes mariadb args ($@), e.g. -e "..." or a heredoc on stdin.
db_exec_root() {
  docker exec -i actools_db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot "$@"' _ "$@"
}



setup_backup_db_user() {
  local backup_pass="$1"
  wait_db
  db_exec_root <<SQL
CREATE USER IF NOT EXISTS 'backup'@'%' IDENTIFIED BY '${backup_pass}';
GRANT SELECT, LOCK TABLES, SHOW VIEW ON *.* TO 'backup'@'%';
FLUSH PRIVILEGES;
SQL
  log "DB backup user created."
}

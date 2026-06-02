#!/usr/bin/env bash
# =============================================================================
# cli/commands/restore.sh — Restore Commands
# =============================================================================

# Run a root mariadb command inside the db container with no password on the host argv.
# The container already holds MARIADB_ROOT_PASSWORD; we expose it to the client as MYSQL_PWD
# *inside* the container. Caller passes mariadb args ($@), e.g. -e "..." or a heredoc on stdin.
db_exec_root() {
  docker exec -i actools_db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot "$@"' _ "$@"
}

# Pipe-fed root mariadb (e.g. restore): stdin is the piped SQL; $1 is the target database.
# Password from container env (MYSQL_PWD); db name passed positionally. No password on host argv.
db_exec_root_stdin() {
  docker exec -i actools_db sh -c 'MYSQL_PWD="$MARIADB_ROOT_PASSWORD" exec mariadb -uroot "$1"' _ "$1"
}

cmd_restore_test() {
  cd "$INSTALL_DIR"
  LATEST=$(ls -t "${INSTALL_DIR}/backups"/prod_db_*.sql.gz 2>/dev/null | head -1)
  [[ -z "$LATEST" ]] && { echo "No prod DB backups found"; exit 1; }
  echo "Testing DB restore: $LATEST"
  sha256sum -c "$LATEST.sha256" && echo "Checksum OK" || { echo "CHECKSUM FAILED"; exit 1; }
  db_exec_root \
    -e "CREATE DATABASE IF NOT EXISTS actools_restore_test CHARACTER SET utf8mb4;"
  gunzip -c "$LATEST" | db_exec_root_stdin actools_restore_test
  TC=$(db_exec_root -sN \
    -e "SELECT count(*) FROM information_schema.tables WHERE table_schema='actools_restore_test';")
  db_exec_root \
    -e "DROP DATABASE IF EXISTS actools_restore_test;"
  echo "DB restore test OK -- ${TC} tables restored."
}

cmd_restore() {
  cd "$INSTALL_DIR"
  local env="${1:-prod}"
  local db="actools_${env}"
  local BACKUP_FILE="${2:-}"
  [[ -z "$BACKUP_FILE" ]] && \
    BACKUP_FILE=$(ls -t "${INSTALL_DIR}/backups/${env}_db_"*.sql.gz 2>/dev/null | head -1)
  [[ -z "$BACKUP_FILE" ]] && { echo "No backups found for $env"; exit 1; }
  echo "Restoring $env from: $BACKUP_FILE"
  sha256sum -c "$BACKUP_FILE.sha256" 2>/dev/null && echo "Checksum OK" \
    || echo "WARNING: no checksum file"
  read -rp "OVERWRITE actools_${env}? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
  db_exec_root \
    -e "DROP DATABASE IF EXISTS \`$db\`; CREATE DATABASE \`$db\` CHARACTER SET utf8mb4;"
  gunzip -c "$BACKUP_FILE" | db_exec_root_stdin "$db"
  echo "Restore complete. Run: actools drush $env cr"
}
